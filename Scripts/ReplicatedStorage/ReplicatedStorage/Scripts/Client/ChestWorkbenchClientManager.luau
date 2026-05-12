--!strict
-- 客户端：宝箱工作台槽位同步 + UpgradeField/UpgradeHome/UpgradeUI 五条升级展示与购买
local ChestWorkbenchClientManager = {}

local players = game:GetService("Players")
local workspace = game:GetService("Workspace")
local replicatedStorage = game:GetService("ReplicatedStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local ChestWorkbenchSaveKeyUtil = require(sharedScripts:WaitForChild("ChestWorkbenchSaveKeyUtil"))
local ChestWorkbenchSaveNormalize = require(sharedScripts:WaitForChild("ChestWorkbenchSaveNormalize"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:WaitForChild("ClientGameInfo"))

local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local coreClientScripts = coreScripts:WaitForChild("Client")
local NumberExtension = require(coreSharedScripts:WaitForChild("NumberExtension"))
local TranslationTool = require(coreClientScripts:WaitForChild("TranslationTool"))
local BillboardManager = require(clientScripts:WaitForChild("BillboardManager"))
local ModelBillboardOffsetTool = require(clientScripts:WaitForChild("ModelBillboardOffsetTool"))

local PLAYERS_HOME_NAME = "PlayersHome"
local WORKBENCH_CONTAINER_NAME = "WorkbenchModel"
local _HOME_SLOT_PATTERN = "^Player%d+$"
local WORKBENCH_CHEST_VISUAL_NAME = "WorkbenchChestVisual"
local CLONED_CHEST_INFO_UI_NAME = "ChestInfoUIClient"
local BILLBOARD_TRACKED_ATTR = "BillboardTracked"

-- 设为 true 时在输出窗口打印每台工作台解析到的 UpgradeUI / Adornee，用于多实例绑定核对。
local DEBUG_CHEST_WORKBENCH_UPGRADE = false

local chestInfoUiTemplate: BillboardGui? = nil
local workbenchChestInfoHooked: { [Model]: boolean } = {}
local workbenchChestHomeWireDone = false

local upgradeUiConnections: { RBXScriptConnection } = {}

local function disconnectAllUpgradeUiConnections()
	for _, c in upgradeUiConnections do
		c:Disconnect()
	end
	table.clear(upgradeUiConnections)
end

local function recordConnection(c: RBXScriptConnection)
	table.insert(upgradeUiConnections, c)
end

local function ensureBillboardTracked(gui: BillboardGui)
	if gui:GetAttribute(BILLBOARD_TRACKED_ATTR) ~= true then
		gui:SetAttribute(BILLBOARD_TRACKED_ATTR, true)
	end
	BillboardManager.Track(gui)
end

local function getWorkbenchChestAdornee(visual: Model): BasePart?
	local root = visual.PrimaryPart or visual:FindFirstChild("RootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return visual:FindFirstChildWhichIsA("BasePart", true)
end

local function refreshChestInfoBillboardStudsOffset(gui: BillboardGui, visual: Model, adornee: BasePart)
	local offsetY = ModelBillboardOffsetTool.GetVisualOffsetY(visual, adornee)
	local extraY = GameConfig.ChestWorkbenchChestInfoUIBillboardOffsetY
	local add = if typeof(extraY) == "number" then extraY else 0
	gui.StudsOffset = Vector3.new(0, offsetY + add, 0)
end

local function applyChestInfoUiContent(gui: BillboardGui, visual: Model)
	local configIdAny = visual:GetAttribute("ChestConfigId")
	local storedExpAny = visual:GetAttribute("ChestStoredExp")
	if typeof(configIdAny) ~= "number" or typeof(storedExpAny) ~= "number" then
		return
	end
	local configId = configIdAny :: number
	local storedExp = storedExpAny :: number
	local cfg = GameConfig.ChestIdMap[configId]
	if cfg == nil then
		return
	end

	local controller = gui:FindFirstChild("ControllerFrame") or gui:FindFirstChild("Controller")
	if controller == nil or not controller:IsA("GuiObject") then
		return
	end
	local nameLabel = controller:FindFirstChild("NameLabel") :: TextLabel?
	local lvLabel = controller:FindFirstChild("LvLabel") :: TextLabel?
	local expImage = controller:FindFirstChild("ExpImage")
	local expTextLabel: TextLabel? = nil
	local scaleFill: GuiObject? = nil
	if expImage and expImage:IsA("GuiObject") then
		(expImage :: GuiObject).Visible = true
		local scaleBar = expImage:FindFirstChild("ScaleBar")
		if scaleBar and scaleBar:IsA("GuiObject") then
			local scale = scaleBar:FindFirstChild("Scale")
			if scale and scale:IsA("GuiObject") then
				scaleFill = scale
			end
		end
		expTextLabel = expImage:FindFirstChild("TextLabel") :: TextLabel?
	end

	if nameLabel then
		TranslationTool.CustomAutoLocalizeTextLabel(nameLabel, cfg.name_t, "", {})
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
	end
	if lvLabel then
		TranslationTool.CustomAutoLocalizeTextLabel(
			lvLabel,
			GameTexts.LevelWithNumber.source,
			GameTexts.LevelWithNumber.key,
			{ tostring(configId) }
		)
	end

	if expTextLabel then
		if configId >= GameConfig.MaxChestId then
			TranslationTool.CustomAutoLocalizeTextLabel(
				expTextLabel,
				GameTexts.ChestWorkbenchExpAtMax.source,
				GameTexts.ChestWorkbenchExpAtMax.key,
				{ NumberExtension.FormatBigNumber(storedExp) }
			)
		else
			local need = cfg.exp
			if need > 0 then
				TranslationTool.CustomAutoLocalizeTextLabel(
					expTextLabel,
					GameTexts.ChestWorkbenchExpProgress.source,
					GameTexts.ChestWorkbenchExpProgress.key,
					{ NumberExtension.FormatBigNumber(storedExp), NumberExtension.FormatBigNumber(need) }
				)
			else
				TranslationTool.CustomAutoLocalizeTextLabel(
					expTextLabel,
					GameTexts.ChestWorkbenchExpAtMax.source,
					GameTexts.ChestWorkbenchExpAtMax.key,
					{ NumberExtension.FormatBigNumber(storedExp) }
				)
			end
		end
	end

	if scaleFill then
		if configId >= GameConfig.MaxChestId then
			scaleFill.Size = UDim2.new(1, 0, 1, 0)
		else
			local need = cfg.exp
			if need > 0 then
				scaleFill.Size = UDim2.new(math.clamp(storedExp / need, 0, 1), 0, 1, 0)
			else
				scaleFill.Size = UDim2.new(1, 0, 1, 0)
			end
		end
	end
end

local function tryBindOrRefreshWorkbenchChestInfoUi(visual: Model)
	if chestInfoUiTemplate == nil then
		return
	end
	if not visual.Parent then
		return
	end
	if typeof(visual:GetAttribute("ChestConfigId")) ~= "number" or typeof(visual:GetAttribute("ChestStoredExp")) ~= "number" then
		return
	end

	local adornee = getWorkbenchChestAdornee(visual)
	if adornee == nil then
		return
	end

	local gui = visual:FindFirstChild(CLONED_CHEST_INFO_UI_NAME, true) :: BillboardGui?
	if gui == nil then
		local createdGui = (chestInfoUiTemplate :: BillboardGui):Clone()
		createdGui.Name = CLONED_CHEST_INFO_UI_NAME
		createdGui.Adornee = adornee
		createdGui.Parent = adornee
		ensureBillboardTracked(createdGui)
		gui = createdGui
	end

	refreshChestInfoBillboardStudsOffset(gui :: BillboardGui, visual, adornee)
	applyChestInfoUiContent(gui :: BillboardGui, visual)
end

local function ensureWorkbenchChestInfoUi(visual: Model)
	if chestInfoUiTemplate == nil then
		return
	end
	if workbenchChestInfoHooked[visual] then
		local gui = visual:FindFirstChild(CLONED_CHEST_INFO_UI_NAME, true) :: BillboardGui?
		if gui then
			applyChestInfoUiContent(gui, visual)
		end
		return
	end
	workbenchChestInfoHooked[visual] = true

	visual.Destroying:Connect(function()
		workbenchChestInfoHooked[visual] = nil
	end)

	local function onAttrOrDefer()
		tryBindOrRefreshWorkbenchChestInfoUi(visual)
	end

	onAttrOrDefer()
	visual:GetAttributeChangedSignal("ChestConfigId"):Connect(onAttrOrDefer)
	visual:GetAttributeChangedSignal("ChestStoredExp"):Connect(onAttrOrDefer)
end

local function refreshAllWorkbenchChestInfoUis()
	if chestInfoUiTemplate == nil then
		return
	end
	local homes = workspace:FindFirstChild(PLAYERS_HOME_NAME)
	if homes == nil then
		return
	end
	for _, d in homes:GetDescendants() do
		if d:IsA("Model") and d.Name == WORKBENCH_CHEST_VISUAL_NAME then
			ensureWorkbenchChestInfoUi(d :: Model)
		end
	end
end

local function wirePlayersHomeWorkbenchChestInfoScan()
	if workbenchChestHomeWireDone then
		return
	end
	workbenchChestHomeWireDone = true

	local function connectHomesFolder(homes: Instance)
		-- 工作台宝箱 InfoUI 的创建/刷新完全由本 Manager 负责，不依赖 HomeClientManager 的 DescendantAdded 刷新链路
		homes.DescendantAdded:Connect(function(inst)
			if inst:IsA("Model") and inst.Name == WORKBENCH_CHEST_VISUAL_NAME then
				task.defer(function()
					ensureWorkbenchChestInfoUi(inst :: Model)
				end)
			end
		end)
		task.defer(refreshAllWorkbenchChestInfoUis)
	end

	local homes = workspace:FindFirstChild(PLAYERS_HOME_NAME)
	if homes then
		connectHomesFolder(homes)
	else
		local waitHomesConn: RBXScriptConnection
		waitHomesConn = workspace.ChildAdded:Connect(function(ch)
			if ch.Name == PLAYERS_HOME_NAME then
				waitHomesConn:Disconnect()
				connectHomesFolder(ch)
			end
		end)
	end
end

local hasWarnedInvalidPurchasedUpgradePayload = false

local function parsePurchasedUpgradeRowIdKey(k: any): number?
	local rowId: number?
	if type(k) == "number" then
		rowId = k
	elseif type(k) == "string" then
		rowId = tonumber(k)
	else
		return nil
	end
	if rowId == nil then
		return nil
	end
	if rowId < 1 or rowId % 1 ~= 0 then
		return nil
	end
	return rowId
end

local function warnInvalidPurchasedUpgradePayload(k: any, v: any)
	if hasWarnedInvalidPurchasedUpgradePayload then
		return
	end
	hasWarnedInvalidPurchasedUpgradePayload = true
	warn(
		"[ChestWorkbenchClientManager] Ignore invalid purchasedWorkbenchUpgradeIds payload entry; expected string rowId map, keyType=",
		typeof(k),
		" valueType=",
		typeof(v)
	)
end

local function workbenchUpgradePurchasedValueIsSet(v: any): boolean
	return v == true or v == 1 or v == "true"
end

local function isWorkbenchUpgradePurchased(purchased: { [string]: boolean }?, rowId: number): boolean
	if purchased == nil then
		return false
	end
	local key = tostring(rowId)
	return workbenchUpgradePurchasedValueIsSet((purchased :: { [string]: any })[key])
end

local function mergeWorkbenchNotifyPayload(saveKey: string, payload: { [string]: any })
	local info = ClientGameInfo.GetLocalPlayerInfo()
	if info == nil then
		return
	end
	local chestSave = info.chestWorkbenchSave
	if chestSave.workbenches[saveKey] == nil then
		chestSave.workbenches[saveKey] = { slots = {} }
	end
	local wb = chestSave.workbenches[saveKey]
	local slotsPayload = payload.slots
	if typeof(slotsPayload) == "table" then
		for k, v in pairs(slotsPayload :: { [any]: any }) do
			local idx = tonumber(k)
			if idx then
				if v == false then
					wb.slots[idx] = nil
				elseif typeof(v) == "table" then
					local t = v :: any
					wb.slots[idx] = {
						configId = t.configId,
						storedExp = t.storedExp,
					}
				end
			end
		end
	end
	local purchasedPayload = payload.purchasedWorkbenchUpgradeIds
	if purchasedPayload ~= nil and typeof(purchasedPayload) == "table" then
		if chestSave.purchasedWorkbenchUpgradeIds == nil or typeof(chestSave.purchasedWorkbenchUpgradeIds) ~= "table" then
			chestSave.purchasedWorkbenchUpgradeIds = {}
		end
		local purchasedMap = chestSave.purchasedWorkbenchUpgradeIds :: { [any]: any }
		for k, v in pairs(purchasedPayload :: { [any]: any }) do
			local rowId = parsePurchasedUpgradeRowIdKey(k)
			if rowId then
				local rowIdKey = tostring(rowId)
				if workbenchUpgradePurchasedValueIsSet(v) then
					purchasedMap[rowIdKey] = true
				else
					purchasedMap[rowIdKey] = nil
				end
			elseif v ~= nil then
				warnInvalidPurchasedUpgradePayload(k, v)
			end
		end
	end
	ChestWorkbenchSaveNormalize.Apply(chestSave)
end

local function formatExpUpgradeText(increaseValue: number): string
	return "+" .. tostring(math.floor(increaseValue + 0.5)) .. " EXP"
end

local function formatSpeedUpgradeText(increaseValue: number): string
	local s = string.format("%.2f", increaseValue)
	s = (s:gsub("0+$", ""):gsub("%.$", ""))
	return "x" .. s .. " Speed Boost"
end

local function formatUpgradeDescription(row: GameConfig.ChestWorkbenchUpgradeRow): string
	if row.upgradeType == 1 then
		return formatExpUpgradeText(row.increaseValue)
	elseif row.upgradeType == 2 then
		return formatSpeedUpgradeText(row.increaseValue)
	end
	return ""
end

local function getUpgradeAdorneePart(upgradeHome: Instance): BasePart?
	if upgradeHome:IsA("BasePart") then
		return upgradeHome
	end
	if upgradeHome:IsA("Model") then
		local m = upgradeHome :: Model
		return m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- 解析顺序：1) 仅本台 UpgradeField 子树（多台并存时与 PlayerGui 解耦，避免误绑其它台的 UpgradeUI）
-- 2) PlayerGui 内 Adornee 落回本 Model 的 SurfaceGui（运行时挪到 PlayerGui 的常见做法）
-- 3) 整棵工作台兜底（勿单独放在 2 之前全树扫描，易命中误放的同名模板）
-- Studio 核对：每台 UpgradeUI 的 Adornee 须属于对应 ChestWorkbenchModel；ControllerFrame 下 UpgradeFrame1~5 勿嵌套重名。
local function resolveWorkbenchUpgradeSurfaceGui(workbenchModel: Model): SurfaceGui?
	local upgradeField = workbenchModel:FindFirstChild("UpgradeField", true)

	if upgradeField then
		for _, d in upgradeField:GetDescendants() do
			if d:IsA("SurfaceGui") and d.Name == "UpgradeUI" then
				local sg = d :: SurfaceGui
				if DEBUG_CHEST_WORKBENCH_UPGRADE then
					local ad = sg.Adornee
					local adPath = if ad then ad:GetFullName() else "nil"
					print(
						"[ChestWorkbenchUpgrade] resolve source=UpgradeField workbench=",
						workbenchModel:GetFullName(),
						" surfaceGui=",
						sg:GetFullName(),
						" Adornee=",
						adPath
					)
				end
				return sg
			end
		end
	end

	local best: SurfaceGui? = nil
	local bestScore = -1

	local function considerPlayerGuiSurface(sg: SurfaceGui)
		local ad = sg.Adornee
		if not ad:IsA("BasePart") then
			return
		end
		if not ad:IsDescendantOf(workbenchModel) then
			return
		end
		local score = 1
		if upgradeField and ad:IsDescendantOf(upgradeField) then
			score = 2
		end
		if score > bestScore then
			bestScore = score
			best = sg
		end
	end

	local lp = players.LocalPlayer
	local pg = lp and lp:FindFirstChild("PlayerGui")
	if pg then
		for _, ch in pg:GetDescendants() do
			if ch:IsA("SurfaceGui") and ch.Name == "UpgradeUI" then
				considerPlayerGuiSurface(ch :: SurfaceGui)
			end
		end
	end
	if best then
		if DEBUG_CHEST_WORKBENCH_UPGRADE then
			local ad = best.Adornee
			local adPath = if ad then ad:GetFullName() else "nil"
			print(
				"[ChestWorkbenchUpgrade] resolve source=PlayerGui workbench=",
				workbenchModel:GetFullName(),
				" surfaceGui=",
				best:GetFullName(),
				" Adornee=",
				adPath,
				" score=",
				bestScore
			)
		end
		return best
	end

	for _, d in workbenchModel:GetDescendants() do
		if d:IsA("SurfaceGui") and d.Name == "UpgradeUI" then
			local sg = d :: SurfaceGui
			if DEBUG_CHEST_WORKBENCH_UPGRADE then
				local ad = sg.Adornee
				local adPath = if ad then ad:GetFullName() else "nil"
				print(
					"[ChestWorkbenchUpgrade] resolve source=WorkbenchDescendant workbench=",
					workbenchModel:GetFullName(),
					" surfaceGui=",
					sg:GetFullName(),
					" Adornee=",
					adPath
				)
			end
			return sg
		end
	end
	if DEBUG_CHEST_WORKBENCH_UPGRADE then
		print("[ChestWorkbenchUpgrade] resolve miss workbench=", workbenchModel:GetFullName())
	end
	return nil
end

local function findUpgradeSlotFrame(controller: Instance, slotIndex: number): Frame?
	local name = "UpgradeFrame" .. tostring(slotIndex)
	local direct = controller:FindFirstChild(name)
	if direct and direct:IsA("Frame") then
		return direct
	end
	local best: Frame? = nil
	local bestDepth: number? = nil
	for _, d in controller:GetDescendants() do
		if d.Name == name and d:IsA("Frame") then
			local depth = 0
			local p: Instance? = d
			while p ~= nil and p ~= controller do
				depth += 1
				p = p.Parent
			end
			if bestDepth == nil or depth < bestDepth then
				bestDepth = depth
				best = d
			end
		end
	end
	return best
end

local function findUpgradeControllerFrame(workbenchModel: Model): Frame?
	local upgradeUi = resolveWorkbenchUpgradeSurfaceGui(workbenchModel)
	if upgradeUi == nil then
		return nil
	end
	local sg = upgradeUi :: SurfaceGui
	local adornee = sg.Adornee
	if not adornee:IsA("BasePart") then
		local upgradeField = workbenchModel:FindFirstChild("UpgradeField")
		local upgradeHome = upgradeField and upgradeField:FindFirstChild("UpgradeHome")
		local resolvedAdornee = if upgradeHome then getUpgradeAdorneePart(upgradeHome) else nil
		if resolvedAdornee == nil then
			return nil
		end
		adornee = resolvedAdornee
	end
	sg.Adornee = adornee
	sg.Enabled = true
	local controller = sg:FindFirstChild("ControllerFrame") :: Frame?
	if controller then
		return controller
	end
	for _, d in sg:GetDescendants() do
		if d.Name == "ControllerFrame" and d:IsA("Frame") then
			return d
		end
	end
	return nil
end

local function collectAvailableSortedUpgradeRows(
	workbenchConfigId: number,
	purchased: { [string]: boolean }
): { GameConfig.ChestWorkbenchUpgradeRow }
	local rows: { GameConfig.ChestWorkbenchUpgradeRow } = {}
	for _, row in pairs(GameConfig.ChestWorkbenchUpgradeByRowId) do
		if row.workbenchId == workbenchConfigId and not isWorkbenchUpgradePurchased(purchased, row.rowId) then
			table.insert(rows, row)
		end
	end
	table.sort(rows, function(a, b)
		if a.price ~= b.price then
			return a.price < b.price
		end
		return a.upgradeType < b.upgradeType
	end)
	return rows
end

local function bindOneWorkbenchUpgradeUi(workbenchModel: Model)
	if DEBUG_CHEST_WORKBENCH_UPGRADE then
		local wid = tonumber(workbenchModel:GetAttribute("WorkbenchId")) or 1
		local sk = ChestWorkbenchSaveKeyUtil.ResolveSaveKey(workbenchModel)
		print(
			"[ChestWorkbenchUpgrade] bind enter workbench=",
			workbenchModel:GetFullName(),
			" WorkbenchId=",
			wid,
			" saveKey=",
			sk
		)
	end
	local controller = findUpgradeControllerFrame(workbenchModel)
	if controller == nil then
		if DEBUG_CHEST_WORKBENCH_UPGRADE then
			print("[ChestWorkbenchUpgrade] bind skip no ControllerFrame workbench=", workbenchModel:GetFullName())
		end
		return
	end
	local wcfgId = tonumber(workbenchModel:GetAttribute("WorkbenchId")) or 1
	local workbenchSaveKey = ChestWorkbenchSaveKeyUtil.ResolveSaveKey(workbenchModel)
	local info = ClientGameInfo.GetLocalPlayerInfo()
	local purchased: { [string]: boolean } = {}
	if info and info.chestWorkbenchSave.purchasedWorkbenchUpgradeIds ~= nil then
		local purchasedAny = info.chestWorkbenchSave.purchasedWorkbenchUpgradeIds :: { [any]: any }
		for k, v in pairs(purchasedAny) do
			local rowId = parsePurchasedUpgradeRowIdKey(k)
			if rowId and workbenchUpgradePurchasedValueIsSet(v) then
				purchased[tostring(rowId)] = true
			end
		end
	end
	local rows = collectAvailableSortedUpgradeRows(wcfgId, purchased)
	local coins = if info then (info.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0) else 0

	for i = 1, 5 do
		local frame = findUpgradeSlotFrame(controller, i)
		if frame == nil then
			continue
		end
		local row = rows[i]
		local descLabel = frame:FindFirstChild("DescLabel") :: TextLabel?
		local buyBtn = frame:FindFirstChild("BuyButton") :: GuiButton?
		if row == nil then
			if descLabel then
				descLabel.Text = ""
			end
			if buyBtn then
				buyBtn.Visible = false
				local priceLabelEmpty = buyBtn:FindFirstChild("TextLabel") :: TextLabel?
				if priceLabelEmpty then
					priceLabelEmpty.Text = ""
				end
			end
			frame.Visible = false
			continue
		end
		frame.Visible = true
		if buyBtn then
			buyBtn.Visible = true
		end
		if descLabel then
			descLabel.Text = formatUpgradeDescription(row)
		end
		local canAfford = coins >= row.price
		if buyBtn then
			local priceLabel = buyBtn:FindFirstChild("TextLabel") :: TextLabel?
			if priceLabel then
				TranslationTool.CustomAutoLocalizeTextLabel(priceLabel, NumberExtension.FormatBigNumberAA(row.price))
			end
			buyBtn.Active = canAfford
			if buyBtn:IsA("ImageButton") or buyBtn:IsA("TextButton") then
				(buyBtn :: any).AutoButtonColor = canAfford
			end
			recordConnection(buyBtn.Activated:Connect(function()
				if not canAfford then
					return
				end
				NetMsg.FireRequestPurchaseWorkbenchUpgrade(row.rowId, workbenchSaveKey)
			end))
		end
	end
end

local function refreshLocalPlayerChestUpgradeUis()
	disconnectAllUpgradeUiConnections()
	local info = ClientGameInfo.GetLocalPlayerInfo()
	if info == nil or info.homeSlot == nil or info.homeSlot == "" then
		return
	end
	local homes = workspace:FindFirstChild(PLAYERS_HOME_NAME)
	if homes == nil then
		return
	end
	local slotFolder = homes:FindFirstChild(info.homeSlot)
	if slotFolder == nil then
		return
	end
	local wbContainer = slotFolder:FindFirstChild(WORKBENCH_CONTAINER_NAME)
	if wbContainer == nil then
		return
	end
	for _, child in wbContainer:GetChildren() do
		if child:IsA("Model") then
			bindOneWorkbenchUpgradeUi(child :: Model)
		end
	end
end

function ChestWorkbenchClientManager.Init()
	local uiFolder = replicatedStorage:FindFirstChild("UI")
	if uiFolder then
		local t = uiFolder:FindFirstChild("ChestInfoUI")
		if t and t:IsA("BillboardGui") then
			chestInfoUiTemplate = t
		end
	end
	wirePlayersHomeWorkbenchChestInfoScan()
	task.defer(refreshAllWorkbenchChestInfoUis)

	NetMsg.ConnectNotifyWorkbenchSlotsUpdate(function(saveKey: string, payload: { [string]: any })
		mergeWorkbenchNotifyPayload(saveKey, payload)
		task.defer(refreshLocalPlayerChestUpgradeUis)
		-- 宝箱经验变化主要由视觉模型 Attribute 变化驱动；此处避免重复全量扫描导致 InfoUI 频繁强刷
	end)

	NetMsg.ConnectNotifyPlayerInfoInit(function()
		task.defer(refreshLocalPlayerChestUpgradeUis)
		task.defer(refreshAllWorkbenchChestInfoUis)
	end)

	NetMsg.ConnectNotifyPlayerHomeInfoUpdate(function(playerId: number, homeSlot: string, _homeInfo: any, _rebirthLevel: number?)
		if playerId ~= players.LocalPlayer.UserId then
			return
		end
		if homeSlot ~= "" then
			task.defer(refreshLocalPlayerChestUpgradeUis)
			task.defer(refreshAllWorkbenchChestInfoUis)
		end
	end)

	local homes = workspace:FindFirstChild(PLAYERS_HOME_NAME)
	if homes then
		homes.DescendantAdded:Connect(function(inst)
			-- WorkbenchModel 子树变化（结构/UI）统一在此处触发工作台刷新，避免展台与工作台逻辑互相耦合
			if inst.Name == WORKBENCH_CONTAINER_NAME or (inst.Parent and inst.Parent.Name == WORKBENCH_CONTAINER_NAME) then
				task.defer(refreshLocalPlayerChestUpgradeUis)
				return
			end
			if inst:IsA("SurfaceGui") and inst.Name == "UpgradeUI" then
				local ad = inst.Adornee
				if ad and ad:IsA("BasePart") and ad:IsDescendantOf(homes) then
					task.defer(refreshLocalPlayerChestUpgradeUis)
				end
			end
		end)
	end

	NetMsg.ConnectNotifyPlayerCurrencyUpdate(function()
		task.defer(refreshLocalPlayerChestUpgradeUis)
	end)

	task.defer(refreshLocalPlayerChestUpgradeUis)
end

return ChestWorkbenchClientManager
