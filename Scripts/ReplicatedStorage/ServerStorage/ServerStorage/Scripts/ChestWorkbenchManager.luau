--!strict
local ChestWorkbenchManager = {}

local players = game:GetService("Players")
local runService = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")

local serverStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerMsg = require(serverScripts:WaitForChild("ServerMsg"))

-- 惰性 require ServerGameInfo；require 经 any 擦除，避免与 ServerGameInfo 内联 require 本模块形成静态循环依赖报错
local requireAny = require :: any
local serverGameInfoMod: any = nil
local function GetServerGameInfo(): any
	if serverGameInfoMod == nil then
		serverGameInfoMod = requireAny(serverScripts:WaitForChild("ServerGameInfo"))
	end
	return serverGameInfoMod
end

-- 惰性 require BrainrotQueueManager，避免其与 ServerGameInfo 的链路与本模块形成静态环
type BrainrotQueueManagerApi = {
	AddItem: (
		Player,
		number,
		number,
		number,
		boolean?,
		number?,
		boolean?,
		string?,
		number?,
		number?,
		number?,
		number?,
		number?
	) -> boolean,
	RemoveItem: (Player, string) -> boolean,
}
local brainrotQueueManagerMod: BrainrotQueueManagerApi? = nil
local function GetBrainrotQueueManager(): BrainrotQueueManagerApi
	if brainrotQueueManagerMod == nil then
		brainrotQueueManagerMod = require(serverScripts:WaitForChild("BrainrotQueueManager")) :: BrainrotQueueManagerApi
	end
	return brainrotQueueManagerMod :: BrainrotQueueManagerApi
end

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local ChestWorkbenchSaveKeyUtil = require(sharedScripts:WaitForChild("ChestWorkbenchSaveKeyUtil"))

local modelsFolder = replicatedStorage:WaitForChild("Models")
local chestModelsFolder = modelsFolder:FindFirstChild(GameConfig.FactoryChestsFolderName)
	or modelsFolder:FindFirstChild("LittleElfChests")

local MAX_INTERACT_DISTANCE = 72
local MANUAL_COOLDOWN = 0.35
local HOME_SLOT_POLL_INTERVAL = 0.2
local HOME_SLOT_POLL_TIMEOUT_SECONDS = 90
local PLAYERS_HOME_FOLDER_NAME = "PlayersHome"
local WORKBENCH_CONTAINER_NAME = "WorkbenchModel"
local HOME_SLOT_NAME_PATTERN = "^Player%d+$"
local WORKBENCH_CHEST_VISUAL_NAME = "WorkbenchChestVisual"
local WORKBENCH_PROMPT_ANCHOR_NAME = "PromptAnchor"
local CHEST_VFX_INSTANCE_NAME = "VfxInstance"
local WORKBENCH_CHEST_VISUAL_MIN_SCALE = 0.5
local WORKBENCH_CHEST_VISUAL_MAX_SCALE = 1.5

export type SlotPartInfo = {
	part: BasePart,
	slotIndex: number,
	attachmentPrompt: ProximityPrompt?,
}

export type WorkbenchRegistryEntry = {
	model: Model,
	saveKey: string,
	registryKey: string,
	homeSlotName: string,
	workbenchConfigId: number,
	slots: { SlotPartInfo },
}

local registryList: { WorkbenchRegistryEntry } = {}
local registryByKey: { [string]: WorkbenchRegistryEntry } = {}
local autoAccuSeconds: { [number]: { [string]: number } } = {}
local manualCooldownUntil: { [number]: { [string]: number } } = {}
local emptySpawnCooldownUntil: { [number]: { [string]: number } } = {}
local _visualsFolder: Folder

local SERVER_WORKBENCH_PROMPT_NAMES: { [string]: boolean } = {
	ChestWorkbenchManualPrompt = true,
	-- 已不再创建；保留名称以便 BuildRegistry 时销毁旧版本残留
	ChestWorkbenchBuyUpgradePrompt = true,
	ChestSlotPickupPrompt = true,
	ChestSlotPlacePrompt = true,
}

-- PlaceAttachment 上的 Studio Prompt 复用同一实例，避免重复 Triggered
local wiredPlaceAttachmentPrompts: { [ProximityPrompt]: boolean } = {}

local function GetRootPart(m: Model): BasePart?
	return m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
end

local function DestroyToolsWithUid(player: Player, uid: string)
	local function scan(container: Instance)
		for _, ch in container:GetChildren() do
			if ch:IsA("Tool") and ch:GetAttribute("BrainrotUID") == uid then
				ch:Destroy()
			end
		end
	end
	scan(player.Backpack)
	local char = player.Character
	if char then
		scan(char)
	end
end

local function PlayerDistanceToModel(player: Player, model: Model): number
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local target = GetRootPart(model)
	if not root or not target then
		return 1e9
	end
	return (root.Position - target.Position).Magnitude
end

local function IsPlayerAllowedOnWorkbench(player: Player, entry: WorkbenchRegistryEntry): boolean
	local pinfo = GetServerGameInfo().GetPlayerInfo(player)
	if not pinfo or pinfo.homeSlot == "" then
		return false
	end
	return pinfo.homeSlot == entry.homeSlotName
end

local hasWarnedInvalidPurchasedUpgradeValue = false

local function ParsePurchasedUpgradeRowIdKey(k: any): number?
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

local function WarnInvalidPurchasedUpgradeValue(k: any, v: any)
	if hasWarnedInvalidPurchasedUpgradeValue then
		return
	end
	hasWarnedInvalidPurchasedUpgradeValue = true
	warn(
		"[ChestWorkbenchManager] Ignore invalid purchasedWorkbenchUpgradeIds entry; expected string rowId map, keyType=",
		typeof(k),
		" valueType=",
		typeof(v)
	)
end

local function ChestWorkbenchUpgradePurchasedValueIsSet(v: any): boolean
	return v == true or v == 1 or v == "true"
end

local function ChestWorkbenchIsUpgradeRowPurchased(map: { [any]: any }?, rowId: number): boolean
	if map == nil then
		return false
	end
	return ChestWorkbenchUpgradePurchasedValueIsSet(map[rowId])
		or ChestWorkbenchUpgradePurchasedValueIsSet(map[tostring(rowId)])
end

local function ResolveRegistryEntry(player: Player, instanceKey: string): WorkbenchRegistryEntry?
	local entry = registryByKey[instanceKey]
	if entry then
		return entry
	end
	local pinfo = GetServerGameInfo().GetPlayerInfo(player)
	if not pinfo or pinfo.homeSlot == "" then
		return nil
	end
	return registryByKey[pinfo.homeSlot .. "_" .. instanceKey]
end

local function ResolveSlotIndexFromSlotPart(part: BasePart, fallbackIndex: number): number
	local idxAttr = part:GetAttribute("SlotIndex")
	if typeof(idxAttr) == "number" then
		return idxAttr
	end
	local selfN = part.Name:match("%d+")
	if selfN then
		return tonumber(selfN) :: number
	end
	local parent = part.Parent
	if parent and parent.Name:match("^ChestSlot%d+$") then
		local pn = parent.Name:match("%d+")
		if pn then
			return tonumber(pn) :: number
		end
	end
	return fallbackIndex
end

local function GetPlaceAttachmentProximityPrompt(part: BasePart): ProximityPrompt?
	local att = part:FindFirstChild("PlaceAttachment")
	if not att or not att:IsA("Attachment") then
		return nil
	end
	return att:FindFirstChildWhichIsA("ProximityPrompt")
end

local function GetFallbackPickupPrompt(slotInfo: SlotPartInfo): ProximityPrompt?
	return slotInfo.part:FindFirstChild("ChestSlotPickupPrompt", true) :: ProximityPrompt?
end

local function GetFallbackPlacePrompt(slotInfo: SlotPartInfo): ProximityPrompt?
	return slotInfo.part:FindFirstChild("ChestSlotPlacePrompt", true) :: ProximityPrompt?
end

local function GetSlotPromptAnchor(slotInfo: SlotPartInfo): Attachment?
	if slotInfo.attachmentPrompt then
		local parent = slotInfo.attachmentPrompt.Parent
		if parent and parent:IsA("Attachment") then
			return parent
		end
	end
	local fallbackAnchor = slotInfo.part:FindFirstChild(WORKBENCH_PROMPT_ANCHOR_NAME, true)
	if fallbackAnchor and fallbackAnchor:IsA("Attachment") then
		return fallbackAnchor
	end
	return nil
end

local function ResolvePromptWorldPositionFromVisual(visual: Model): Vector3?
	local vfxInstance = visual:FindFirstChild(CHEST_VFX_INSTANCE_NAME, true)
	if vfxInstance then
		if vfxInstance:IsA("Attachment") then
			return vfxInstance.WorldPosition
		end
		if vfxInstance:IsA("BasePart") then
			return vfxInstance.Position
		end
	end
	local rootPart = GetRootPart(visual)
	if rootPart then
		return rootPart.Position
	end
	return nil
end

local function GetDefaultPromptWorldPosition(slotPart: BasePart): Vector3
	local chestAttachment = slotPart:FindFirstChild("ChestAttachment")
	if chestAttachment and chestAttachment:IsA("Attachment") then
		return chestAttachment.WorldPosition
	end
	return slotPart.Position
end

local function SetPromptAnchorWorldPosition(anchor: Attachment, worldPosition: Vector3)
	local parent = anchor.Parent
	if not parent or not parent:IsA("BasePart") then
		return
	end
	anchor.Position = parent.CFrame:PointToObjectSpace(worldPosition)
end

local function AlignSlotPromptAnchorToVisual(slotInfo: SlotPartInfo, visual: Model?)
	local promptAnchor = GetSlotPromptAnchor(slotInfo)
	if not promptAnchor then
		return
	end
	local targetWorldPosition: Vector3? = nil
	if visual then
		targetWorldPosition = ResolvePromptWorldPositionFromVisual(visual)
	end
	if targetWorldPosition == nil then
		targetWorldPosition = GetDefaultPromptWorldPosition(slotInfo.part)
	end
	local resolvedTargetWorldPosition = targetWorldPosition :: Vector3
	SetPromptAnchorWorldPosition(promptAnchor, resolvedTargetWorldPosition)
end

local function DestroyServerCreatedWorkbenchPrompts(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") and SERVER_WORKBENCH_PROMPT_NAMES[d.Name] then
			d:Destroy()
		end
	end
end

local function EnsureWorkbenchEntry(playerInfo: GameConfig.PlayerInfo, instanceKey: string, _slotCount: number)
	local save = playerInfo.chestWorkbenchSave
	if save.workbenches[instanceKey] == nil then
		save.workbenches[instanceKey] = { slots = {} }
	end
end

local function GetPlayerHumanoidRootPart(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function IsPlayerHoldingChestTool(player: Player): boolean
	local char = player.Character
	if not char then
		return false
	end
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool then
		return false
	end
	return tool:GetAttribute("ItemType") == GameConfig.ItemType.Chest
end

-- 与家园展台一致：同一玩家同时只启用距离最近的一个「槽位交互」类 ProximityPrompt（有角色时）；无角色时保持各槽位原逻辑
local function SelectSlotPromptByOccupancy(
	slotInfo: SlotPartInfo,
	wd: GameConfig.ChestWorkbenchRow?,
	occupied: boolean,
	isHoldingChest: boolean
): ProximityPrompt?
	if slotInfo.attachmentPrompt then
		if wd and wd.type == GameConfig.WorkbenchType.Place then
			if occupied or isHoldingChest then
				return slotInfo.attachmentPrompt
			end
			return nil
		end
		if occupied and wd and (wd.type == GameConfig.WorkbenchType.Manual or wd.type == GameConfig.WorkbenchType.Auto) then
			return slotInfo.attachmentPrompt
		end
		return nil
	end
	if occupied then
		return GetFallbackPickupPrompt(slotInfo)
	end
	if wd and wd.type == GameConfig.WorkbenchType.Place and isHoldingChest then
		return GetFallbackPlacePrompt(slotInfo)
	end
	return nil
end

local function PickWinningChestSlotPrompt(
	player: Player,
	playerInfo: GameConfig.PlayerInfo
): ProximityPrompt?
	local root = GetPlayerHumanoidRootPart(player)
	if root == nil then
		return nil
	end
	local isHoldingChest = IsPlayerHoldingChestTool(player)
	local bestDist = math.huge
	local winner: ProximityPrompt? = nil
	local winnerTie = "\255"
	for _, entry in registryList do
		if entry.homeSlotName ~= playerInfo.homeSlot then
			continue
		end
		EnsureWorkbenchEntry(playerInfo, entry.saveKey, #entry.slots)
		local wb = playerInfo.chestWorkbenchSave.workbenches[entry.saveKey]
		local wd = GameConfig.ChestWorkbenchById[entry.workbenchConfigId]
		if wd == nil then
			continue
		end
		for _, si in ipairs(entry.slots) do
			local occupied = wb.slots[si.slotIndex] ~= nil
			local prompt = SelectSlotPromptByOccupancy(si, wd, occupied, isHoldingChest)
			if prompt == nil then
				continue
			end
			local dist = (root.Position - si.part.Position).Magnitude
			local maxD = prompt.MaxActivationDistance
			local tieKey = entry.registryKey .. "_" .. tostring(si.slotIndex)
			if dist <= maxD and (dist < bestDist - 0.01 or (math.abs(dist - bestDist) <= 0.01 and tieKey < winnerTie)) then
				bestDist = dist
				winner = prompt
				winnerTie = tieKey
			end
		end
	end
	return winner
end

local function ComputeExpDelta(playerInfo: GameConfig.PlayerInfo, workbenchConfigId: number): number
	local wd = GameConfig.ChestWorkbenchById[workbenchConfigId]
	if not wd then
		return 0
	end
	local base = wd.initialExp
	local bonus = 0
	local purchased = playerInfo.chestWorkbenchSave.purchasedWorkbenchUpgradeIds
	for _, row in pairs(GameConfig.ChestWorkbenchUpgradeByRowId) do
		if row.workbenchId == workbenchConfigId and row.upgradeType == 1 and ChestWorkbenchIsUpgradeRowPurchased(purchased, row.rowId) then
			bonus += row.increaseValue
		end
	end
	return base + bonus
end

local function ComputeAutoIntervalSeconds(playerInfo: GameConfig.PlayerInfo, workbenchConfigId: number): number
	local wd = GameConfig.ChestWorkbenchById[workbenchConfigId]
	if not wd then
		return 9999
	end
	local base = math.max(0.1, wd.initialRate)
	local mult = 1.0
	local purchased = playerInfo.chestWorkbenchSave.purchasedWorkbenchUpgradeIds
	for _, row in pairs(GameConfig.ChestWorkbenchUpgradeByRowId) do
		if row.workbenchId == workbenchConfigId and row.upgradeType == 2 and ChestWorkbenchIsUpgradeRowPurchased(purchased, row.rowId) then
			mult *= row.increaseValue
		end
	end
	return base / math.max(mult, 0.01)
end

local function GetWorkbenchSpawnIntervalSeconds(): number
	local configuredInterval = GameConfig.ChestWorkbenchSpawnIntervalSeconds
	if typeof(configuredInterval) ~= "number" then
		return 0
	end
	return math.max(0, configuredInterval)
end

local function ProcessSlotUpgrades(slotSave: GameConfig.WorkbenchSlotSave)
	local maxId = GameConfig.MaxChestId
	while slotSave.configId < maxId do
		local cfg = GameConfig.ChestIdMap[slotSave.configId]
		if not cfg then
			break
		end
		local need = cfg.exp
		if slotSave.storedExp < need then
			break
		end
		slotSave.storedExp -= need
		slotSave.configId += 1
	end
end

local function ComputeWorkbenchChestVisualScale(slotSave: GameConfig.WorkbenchSlotSave): number
	if slotSave.configId >= GameConfig.MaxChestId then
		return WORKBENCH_CHEST_VISUAL_MAX_SCALE
	end

	local cfg = GameConfig.ChestIdMap[slotSave.configId]
	if cfg == nil then
		return WORKBENCH_CHEST_VISUAL_MIN_SCALE
	end

	local needExp = math.max(0, cfg.exp)
	if needExp <= 0 then
		return WORKBENCH_CHEST_VISUAL_MAX_SCALE
	end

	local progress = math.clamp(slotSave.storedExp / needExp, 0, 1)
	local scaleSpan = WORKBENCH_CHEST_VISUAL_MAX_SCALE - WORKBENCH_CHEST_VISUAL_MIN_SCALE
	return WORKBENCH_CHEST_VISUAL_MIN_SCALE + scaleSpan * progress
end

local function PivotWorkbenchChestVisualToSlot(slotInfo: SlotPartInfo, visual: Model)
	local chestAtt = slotInfo.part:FindFirstChild("ChestAttachment")
	if chestAtt and chestAtt:IsA("Attachment") then
		visual:PivotTo(chestAtt.WorldCFrame)
	else
		visual:PivotTo(slotInfo.part.CFrame)
	end
end

local function ApplyWorkbenchChestVisualScale(slotInfo: SlotPartInfo, visual: Model, slotSave: GameConfig.WorkbenchSlotSave)
	local visualScale = ComputeWorkbenchChestVisualScale(slotSave)
	visual:ScaleTo(visualScale)
	PivotWorkbenchChestVisualToSlot(slotInfo, visual)
end

local function ClearSlotVisual(slotInfo: SlotPartInfo)
	for _, ch in slotInfo.part:GetChildren() do
		if ch:IsA("Model") and ch.Name == WORKBENCH_CHEST_VISUAL_NAME then
			ch:Destroy()
		end
	end
	AlignSlotPromptAnchorToVisual(slotInfo, nil)
end

local function RefreshSlotVisual(slotInfo: SlotPartInfo, slotSave: GameConfig.WorkbenchSlotSave)
	if not chestModelsFolder then
		AlignSlotPromptAnchorToVisual(slotInfo, nil)
		return
	end
	local cfg = GameConfig.ChestIdMap[slotSave.configId]
	if not cfg then
		AlignSlotPromptAnchorToVisual(slotInfo, nil)
		return
	end

	local existedVisual: Model? = nil
	for _, ch in slotInfo.part:GetChildren() do
		if ch:IsA("Model") and ch.Name == WORKBENCH_CHEST_VISUAL_NAME then
			if existedVisual == nil then
				existedVisual = ch
			else
				-- 只允许保留一个可视模型，清理重复实例
				ch:Destroy()
			end
		end
	end

	if existedVisual then
		local existedConfigId = existedVisual:GetAttribute("ChestConfigId")
		if typeof(existedConfigId) == "number" and existedConfigId == slotSave.configId then
			-- 等级未变化：不重建模型，仅更新数值 Attribute，避免频繁闪烁
			existedVisual:SetAttribute("ChestStoredExp", slotSave.storedExp)
			ApplyWorkbenchChestVisualScale(slotInfo, existedVisual, slotSave)
			AlignSlotPromptAnchorToVisual(slotInfo, existedVisual)
			return
		end
		existedVisual:Destroy()
	end

	local template = GameConfig.FindResourceTemplateByResourceName(chestModelsFolder, cfg.resourceName)
	if not template then
		AlignSlotPromptAnchorToVisual(slotInfo, nil)
		return
	end
	local clone = GameConfig.CloneTemplateAsModel(template)
	clone.Name = WORKBENCH_CHEST_VISUAL_NAME
	clone.Parent = slotInfo.part
	for _, p in clone:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = true
			p.CanTouch = false
		end
	end
	clone:SetAttribute("ChestConfigId", slotSave.configId)
	clone:SetAttribute("ChestStoredExp", slotSave.storedExp)
	ApplyWorkbenchChestVisualScale(slotInfo, clone, slotSave)
	AlignSlotPromptAnchorToVisual(slotInfo, clone)
end

local function FireSlotSync(player: Player, instanceKey: string, entry: WorkbenchRegistryEntry)
	local ev = NetMsg.GetNotifyWorkbenchSlotsUpdateEvent()
	if ev == nil then
		return
	end
	local playerInfo = GetServerGameInfo().GetPlayerInfo(player)
	if not playerInfo then
		return
	end
	EnsureWorkbenchEntry(playerInfo, instanceKey, #entry.slots)
	local wb = playerInfo.chestWorkbenchSave.workbenches[instanceKey]
	local purchasedCopy: { [string]: boolean } = {}
	local purchasedMap = playerInfo.chestWorkbenchSave.purchasedWorkbenchUpgradeIds
	if typeof(purchasedMap) == "table" then
		for rowIdKey, bought in pairs(purchasedMap :: { [any]: any }) do
			local rowId = ParsePurchasedUpgradeRowIdKey(rowIdKey)
			if rowId then
				if ChestWorkbenchUpgradePurchasedValueIsSet(bought) then
					purchasedCopy[tostring(rowId)] = true
				end
			elseif bought ~= nil then
				WarnInvalidPurchasedUpgradeValue(rowIdKey, bought)
			end
		end
	end
	local payload: { [string]: any } = {
		workbenchConfigId = entry.workbenchConfigId,
		slots = {},
		purchasedWorkbenchUpgradeIds = purchasedCopy,
	}
	for _, si in ipairs(entry.slots) do
		local s = wb.slots[si.slotIndex]
		payload.slots[tostring(si.slotIndex)] = if s then { configId = s.configId, storedExp = s.storedExp } else false
	end
	ev:FireClient(player, instanceKey, payload)
end

function ChestWorkbenchManager.ApplyExpRound(player: Player, entry: WorkbenchRegistryEntry)
	local playerInfo = GetServerGameInfo().GetPlayerInfo(player)
	if not playerInfo then
		return
	end
	if not IsPlayerAllowedOnWorkbench(player, entry) then
		return
	end
	local wd = GameConfig.ChestWorkbenchById[entry.workbenchConfigId]
	if not wd then
		return
	end
	local slotCount = #entry.slots
	if slotCount == 0 then
		return
	end
	EnsureWorkbenchEntry(playerInfo, entry.saveKey, slotCount)
	local wbSave = playerInfo.chestWorkbenchSave.workbenches[entry.saveKey]
	local allowFillEmpty = wd.type == GameConfig.WorkbenchType.Manual or wd.type == GameConfig.WorkbenchType.Auto

	if allowFillEmpty then
		if wd.type == GameConfig.WorkbenchType.Manual then
			for _, si in ipairs(entry.slots) do
				if wbSave.slots[si.slotIndex] == nil then
					wbSave.slots[si.slotIndex] = {
						configId = GameConfig.DefaultWorkbenchChestTier,
						storedExp = 0,
					}
					RefreshSlotVisual(si, wbSave.slots[si.slotIndex] :: GameConfig.WorkbenchSlotSave)
				end
			end
		else
			local spawnIntervalSeconds = GetWorkbenchSpawnIntervalSeconds()
			local now = os.clock()
			emptySpawnCooldownUntil[player.UserId] = emptySpawnCooldownUntil[player.UserId] or {}
			local cooldownMap = emptySpawnCooldownUntil[player.UserId]
			local isCooldownReady = now >= (cooldownMap[entry.registryKey] or 0)
			if isCooldownReady then
				for _, si in ipairs(entry.slots) do
					if wbSave.slots[si.slotIndex] == nil then
						wbSave.slots[si.slotIndex] = {
							configId = GameConfig.DefaultWorkbenchChestTier,
							storedExp = 0,
						}
						RefreshSlotVisual(si, wbSave.slots[si.slotIndex] :: GameConfig.WorkbenchSlotSave)
						if spawnIntervalSeconds > 0 then
							cooldownMap[entry.registryKey] = now + spawnIntervalSeconds
						end
						break
					end
				end
			end
		end
	end

	local delta = ComputeExpDelta(playerInfo, entry.workbenchConfigId)
	if delta <= 0 then
		return
	end

	for _, si in ipairs(entry.slots) do
		local s = wbSave.slots[si.slotIndex]
		if s then
			s.storedExp += delta
			ProcessSlotUpgrades(s)
			RefreshSlotVisual(si, s)
		end
	end

	playerInfo.playerInfoChanged = true
	FireSlotSync(player, entry.saveKey, entry)
end

local function OnManualPrompt(entry: WorkbenchRegistryEntry, player: Player)
	if PlayerDistanceToModel(player, entry.model) > MAX_INTERACT_DISTANCE then
		return
	end
	if not IsPlayerAllowedOnWorkbench(player, entry) then
		return
	end
	local wd = GameConfig.ChestWorkbenchById[entry.workbenchConfigId]
	if not wd then
		return
	end
	if wd.type ~= GameConfig.WorkbenchType.Manual and wd.type ~= GameConfig.WorkbenchType.Place then
		return
	end
	local uid = player.UserId
	manualCooldownUntil[uid] = manualCooldownUntil[uid] or {}
	local untilT = manualCooldownUntil[uid][entry.registryKey] or 0
	if os.clock() < untilT then
		return
	end
	manualCooldownUntil[uid][entry.registryKey] = os.clock() + MANUAL_COOLDOWN
	ChestWorkbenchManager.ApplyExpRound(player, entry)
end

local function OnPickupPrompt(entry: WorkbenchRegistryEntry, slotIndex: number, player: Player)
	if PlayerDistanceToModel(player, entry.model) > MAX_INTERACT_DISTANCE then
		return
	end
	if not IsPlayerAllowedOnWorkbench(player, entry) then
		return
	end
	local playerInfo = GetServerGameInfo().GetPlayerInfo(player)
	if not playerInfo then
		return
	end
	EnsureWorkbenchEntry(playerInfo, entry.saveKey, #entry.slots)
	local wb = playerInfo.chestWorkbenchSave.workbenches[entry.saveKey]
	local wd = GameConfig.ChestWorkbenchById[entry.workbenchConfigId]
	local s = wb.slots[slotIndex]
	if not s then
		return
	end
	local cfg = GameConfig.ChestIdMap[s.configId]
	local quality = if cfg then cfg.quality else 1
	local slotPart: SlotPartInfo? = nil
	for _, si in ipairs(entry.slots) do
		if si.slotIndex == slotIndex then
			slotPart = si
			break
		end
	end
	GetBrainrotQueueManager().AddItem(
		player,
		s.configId,
		quality,
		1,
		true,
		GameConfig.ItemType.Chest,
		false,
		nil,
		nil,
		nil,
		GameConfig.ModelGetSource.Workbench,
		entry.workbenchConfigId,
		s.storedExp
	)
	wb.slots[slotIndex] = nil
	if wd and wd.type ~= GameConfig.WorkbenchType.Manual then
		local spawnIntervalSeconds = GetWorkbenchSpawnIntervalSeconds()
		if spawnIntervalSeconds > 0 then
			emptySpawnCooldownUntil[player.UserId] = emptySpawnCooldownUntil[player.UserId] or {}
			emptySpawnCooldownUntil[player.UserId][entry.registryKey] = os.clock() + spawnIntervalSeconds
		end
	end
	if slotPart then
		ClearSlotVisual(slotPart)
	end
	playerInfo.playerInfoChanged = true
	FireSlotSync(player, entry.saveKey, entry)
end

local function GetEquippedChestUid(player: Player): string?
	local char = player.Character
	if not char then
		return nil
	end
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool then
		return nil
	end
	if tool:GetAttribute("ItemType") ~= GameConfig.ItemType.Chest then
		return nil
	end
	return tool:GetAttribute("BrainrotUID") :: string?
end

local function GetEquippedChestStoredExp(player: Player, uid: string): number?
	local char = player.Character
	if not char then
		return nil
	end
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool then
		return nil
	end
	if tool:GetAttribute("BrainrotUID") ~= uid then
		return nil
	end
	if tool:GetAttribute("ItemType") ~= GameConfig.ItemType.Chest then
		return nil
	end
	local storedExpAny = tool:GetAttribute("ChestStoredExp")
	if typeof(storedExpAny) == "number" then
		return math.max(0, storedExpAny)
	end
	return nil
end

local function OnPlacePrompt(entry: WorkbenchRegistryEntry, slotIndex: number, player: Player)
	if PlayerDistanceToModel(player, entry.model) > MAX_INTERACT_DISTANCE then
		return
	end
	if not IsPlayerAllowedOnWorkbench(player, entry) then
		return
	end
	local wd = GameConfig.ChestWorkbenchById[entry.workbenchConfigId]
	if not wd or wd.type ~= GameConfig.WorkbenchType.Place then
		return
	end
	local playerInfo = GetServerGameInfo().GetPlayerInfo(player)
	if not playerInfo then
		return
	end
	EnsureWorkbenchEntry(playerInfo, entry.saveKey, #entry.slots)
	local wb = playerInfo.chestWorkbenchSave.workbenches[entry.saveKey]
	if wb.slots[slotIndex] ~= nil then
		return
	end
	local uid = GetEquippedChestUid(player)
	if not uid then
		return
	end
	local foundItem: GameConfig.BrainrotQueueItem? = nil
	for _, it in ipairs(playerInfo.brainrotQueue) do
		if it.uid == uid and it.itemType == GameConfig.ItemType.Chest then
			foundItem = it
			break
		end
	end
	if not foundItem then
		return
	end
	local queueStoredExp = (foundItem :: any).chestStoredExp
	local restoredStoredExp = 0
	if typeof(queueStoredExp) == "number" then
		restoredStoredExp = math.max(0, queueStoredExp)
	else
		local equippedStoredExp = GetEquippedChestStoredExp(player, uid)
		if equippedStoredExp ~= nil then
			restoredStoredExp = equippedStoredExp
		end
	end
	if not GetBrainrotQueueManager().RemoveItem(player, uid) then
		return
	end
	DestroyToolsWithUid(player, uid)
	wb.slots[slotIndex] = {
		configId = foundItem.configId,
		storedExp = restoredStoredExp,
	}
	local slotPart: SlotPartInfo? = nil
	for _, si in ipairs(entry.slots) do
		if si.slotIndex == slotIndex then
			slotPart = si
			break
		end
	end
	if slotPart and wb.slots[slotIndex] then
		RefreshSlotVisual(slotPart, wb.slots[slotIndex] :: GameConfig.WorkbenchSlotSave)
	end
	playerInfo.playerInfoChanged = true
	FireSlotSync(player, entry.saveKey, entry)
end

local function OnPlaceAttachmentPromptTriggered(entry: WorkbenchRegistryEntry, slotIndex: number, player: Player)
	if PlayerDistanceToModel(player, entry.model) > MAX_INTERACT_DISTANCE then
		return
	end
	if not IsPlayerAllowedOnWorkbench(player, entry) then
		return
	end
	local wd = GameConfig.ChestWorkbenchById[entry.workbenchConfigId]
	if not wd then
		return
	end
	if wd.type == GameConfig.WorkbenchType.Place then
		local playerInfo = GetServerGameInfo().GetPlayerInfo(player)
		if not playerInfo then
			return
		end
		EnsureWorkbenchEntry(playerInfo, entry.saveKey, #entry.slots)
		local wb = playerInfo.chestWorkbenchSave.workbenches[entry.saveKey]
		local occupied = wb.slots[slotIndex] ~= nil
		if occupied then
			OnPickupPrompt(entry, slotIndex, player)
		else
			OnPlacePrompt(entry, slotIndex, player)
		end
	else
		OnPickupPrompt(entry, slotIndex, player)
	end
end

local function AttachPrompts(entry: WorkbenchRegistryEntry)
	local root = GetRootPart(entry.model)
	if not root then
		return
	end
	local wd = GameConfig.ChestWorkbenchById[entry.workbenchConfigId]
	if wd and (wd.type == GameConfig.WorkbenchType.Manual or wd.type == GameConfig.WorkbenchType.Place) then
		local p = Instance.new("ProximityPrompt")
		p.Name = "ChestWorkbenchManualPrompt"
		p.ActionText = "Grant EXP"
		p.ObjectText = wd.name or "Workbench"
		p.HoldDuration = 0
		p.MaxActivationDistance = 14
		p.RequiresLineOfSight = false
		p.Triggered:Connect(function(plr)
			if plr:IsA("Player") then
				OnManualPrompt(entry, plr)
			end
		end)
		p.Parent = root
	end

	for _, si in ipairs(entry.slots) do
		if si.attachmentPrompt then
			si.attachmentPrompt.MaxActivationDistance = 12
			si.attachmentPrompt.HoldDuration = 0
			si.attachmentPrompt.RequiresLineOfSight = false
			if not wiredPlaceAttachmentPrompts[si.attachmentPrompt] then
				wiredPlaceAttachmentPrompts[si.attachmentPrompt] = true
				local registryKeyForPrompt = entry.registryKey
				local slotIndexForPrompt = si.slotIndex
				si.attachmentPrompt.Triggered:Connect(function(plr)
					if not plr:IsA("Player") then
						return
					end
					local currentEntry = registryByKey[registryKeyForPrompt]
					if currentEntry then
						OnPlaceAttachmentPromptTriggered(currentEntry, slotIndexForPrompt, plr)
					end
				end)
			end
			AlignSlotPromptAnchorToVisual(si, nil)
		else
			local promptAnchor = si.part:FindFirstChild(WORKBENCH_PROMPT_ANCHOR_NAME) :: Attachment?
			if promptAnchor == nil then
				promptAnchor = Instance.new("Attachment")
			end
			if promptAnchor == nil then
				continue
			end
			promptAnchor.Name = WORKBENCH_PROMPT_ANCHOR_NAME
			promptAnchor.Parent = si.part
			local pick = Instance.new("ProximityPrompt")
			pick.Name = "ChestSlotPickupPrompt"
			pick.ActionText = "Pick up"
			pick.ObjectText = "Chest"
			pick.HoldDuration = 0
			pick.MaxActivationDistance = 12
			pick.RequiresLineOfSight = false
			pick.Enabled = false
			pick.Triggered:Connect(function(plr)
				if plr:IsA("Player") then
					OnPickupPrompt(entry, si.slotIndex, plr)
				end
			end)
			pick.Parent = promptAnchor

			local place = Instance.new("ProximityPrompt")
			place.Name = "ChestSlotPlacePrompt"
			place.ActionText = "Place chest"
			place.ObjectText = "Slot"
			place.HoldDuration = 0
			place.MaxActivationDistance = 12
			place.RequiresLineOfSight = false
			place.Enabled = false
			place.Triggered:Connect(function(plr)
				if plr:IsA("Player") then
					OnPlacePrompt(entry, si.slotIndex, plr)
				end
			end)
			place.Parent = promptAnchor
			AlignSlotPromptAnchorToVisual(si, nil)
		end
	end
end

local function RefreshAllSlotPromptsForPlayer(player: Player)
	local playerInfo = GetServerGameInfo().GetPlayerInfo(player)
	if not playerInfo or playerInfo.homeSlot == "" then
		return
	end
	local winningPrompt = PickWinningChestSlotPrompt(player, playerInfo)
	local hrp = GetPlayerHumanoidRootPart(player)
	local usePromptMutex = hrp ~= nil
	local isHoldingChest = IsPlayerHoldingChestTool(player)

	for _, entry in registryList do
		if entry.homeSlotName ~= playerInfo.homeSlot then
			continue
		end
		EnsureWorkbenchEntry(playerInfo, entry.saveKey, #entry.slots)
		local wb = playerInfo.chestWorkbenchSave.workbenches[entry.saveKey]
		local wd = GameConfig.ChestWorkbenchById[entry.workbenchConfigId]
		for _, si in ipairs(entry.slots) do
			local occupied = wb.slots[si.slotIndex] ~= nil
			if si.attachmentPrompt then
				if wd and wd.type == GameConfig.WorkbenchType.Place then
					si.attachmentPrompt.ActionText = if occupied then "Pick up" else "Place chest"
					si.attachmentPrompt.ObjectText = if occupied then "Chest" else "Slot"
					local canEnable = occupied or isHoldingChest
					si.attachmentPrompt.Enabled = canEnable and (not usePromptMutex or winningPrompt == si.attachmentPrompt)
				elseif wd then
					si.attachmentPrompt.ActionText = "Pick up"
					si.attachmentPrompt.ObjectText = "Chest"
					si.attachmentPrompt.Enabled = occupied and (not usePromptMutex or winningPrompt == si.attachmentPrompt)
				else
					si.attachmentPrompt.Enabled = false
				end
			else
				local pick = GetFallbackPickupPrompt(si)
				local place = GetFallbackPlacePrompt(si)
				if pick then
					pick.Enabled = occupied and (not usePromptMutex or winningPrompt == pick)
				end
				if place and wd and wd.type == GameConfig.WorkbenchType.Place then
					place.Enabled = (not occupied) and isHoldingChest and (not usePromptMutex or winningPrompt == place)
				elseif place then
					place.Enabled = false
				end
			end
		end
	end
end

local function BuildRegistry()
	for _, prev in registryList do
		DestroyServerCreatedWorkbenchPrompts(prev.model)
	end
	table.clear(registryList)
	table.clear(registryByKey)
	local homesFolder = workspace:FindFirstChild(PLAYERS_HOME_FOLDER_NAME) :: Folder?
	if homesFolder == nil then
		return
	end
	for _, slotFolder in homesFolder:GetChildren() do
		if not slotFolder.Name:match(HOME_SLOT_NAME_PATTERN) then
			continue
		end
		local container = slotFolder:FindFirstChild(WORKBENCH_CONTAINER_NAME)
		if container == nil then
			continue
		end
		for _, child in container:GetChildren() do
			if not child:IsA("Model") then
				continue
			end
			local model = child :: Model
			local wcfgId = tonumber(model:GetAttribute("WorkbenchId")) or 1
			local saveKey = ChestWorkbenchSaveKeyUtil.ResolveSaveKey(model)
			local registryKey = slotFolder.Name .. "_" .. saveKey
			if registryByKey[registryKey] ~= nil then
				warn("[ChestWorkbenchManager] Duplicate workbench registry key:", model:GetFullName(), "saveKey=", saveKey)
				continue
			end
			local slotParts: { SlotPartInfo } = {}
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.Name == GameConfig.ChestWorkbenchSlotPartName then
					local idx = ResolveSlotIndexFromSlotPart(d, #slotParts + 1)
					local attachmentPrompt = GetPlaceAttachmentProximityPrompt(d)
					table.insert(slotParts, {
						part = d,
						slotIndex = idx,
						attachmentPrompt = attachmentPrompt,
					})
				end
			end
			table.sort(slotParts, function(a, b)
				return a.slotIndex < b.slotIndex
			end)
			local entry: WorkbenchRegistryEntry = {
				model = model,
				saveKey = saveKey,
				registryKey = registryKey,
				homeSlotName = slotFolder.Name,
				workbenchConfigId = wcfgId,
				slots = slotParts,
			}
			table.insert(registryList, entry)
			registryByKey[registryKey] = entry
			AttachPrompts(entry)
		end
	end
end

local function OnHeartbeat(dt: number)
	for _, plr in players:GetPlayers() do
		local pinfo = GetServerGameInfo().GetPlayerInfo(plr)
		if not pinfo then
			continue
		end
		autoAccuSeconds[plr.UserId] = autoAccuSeconds[plr.UserId] or {}
		local accuMap = autoAccuSeconds[plr.UserId]
		for _, entry in registryList do
			if entry.homeSlotName ~= pinfo.homeSlot then
				continue
			end
			local wd = GameConfig.ChestWorkbenchById[entry.workbenchConfigId]
			if not wd or (wd.type ~= GameConfig.WorkbenchType.Auto and wd.type ~= GameConfig.WorkbenchType.Place) then
				continue
			end
			if PlayerDistanceToModel(plr, entry.model) > MAX_INTERACT_DISTANCE * 1.5 then
				continue
			end
			local interval = ComputeAutoIntervalSeconds(pinfo, entry.workbenchConfigId)
			accuMap[entry.registryKey] = (accuMap[entry.registryKey] or 0) + dt
			if accuMap[entry.registryKey] >= interval then
				accuMap[entry.registryKey] = 0
				ChestWorkbenchManager.ApplyExpRound(plr, entry)
			end
		end
	end
	for _, plr in players:GetPlayers() do
		RefreshAllSlotPromptsForPlayer(plr)
	end
end

-- 在 homeSlot 已分配后调用：重新扫描场景并刷新该玩家槽位与 Prompt
function ChestWorkbenchManager.NotifyPlayerHomeSlotReady(player: Player)
	BuildRegistry()
	if #registryList == 0 then
		warn("[ChestWorkbenchManager] No workbench models in registry; check Workspace.PlayersHome.PlayerN.WorkbenchModel")
	end
	ChestWorkbenchManager.LoadPlayerVisuals(player)
end

local function WaitForHomeSlotThenNotifyWorkbench(player: Player)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < HOME_SLOT_POLL_TIMEOUT_SECONDS do
			if not player.Parent then
				return
			end
			local pi = GetServerGameInfo().GetPlayerInfo(player)
			if pi == nil then
				return
			end
			if pi.homeSlot ~= "" then
				ChestWorkbenchManager.NotifyPlayerHomeSlotReady(player)
				return
			end
			task.wait(HOME_SLOT_POLL_INTERVAL)
		end
		warn("[ChestWorkbenchManager] homeSlot still empty after timeout for player:", player.Name)
	end)
end

function ChestWorkbenchManager.LoadPlayerVisuals(player: Player)
	local playerInfo = GetServerGameInfo().GetPlayerInfo(player)
	if not playerInfo then
		return
	end
	for _, entry in registryList do
		if entry.homeSlotName ~= playerInfo.homeSlot then
			continue
		end
		EnsureWorkbenchEntry(playerInfo, entry.saveKey, #entry.slots)
		local wb = playerInfo.chestWorkbenchSave.workbenches[entry.saveKey]
		for _, si in ipairs(entry.slots) do
			local s = wb.slots[si.slotIndex]
			if s then
				RefreshSlotVisual(si, s)
			else
				ClearSlotVisual(si)
			end
		end
		FireSlotSync(player, entry.saveKey, entry)
	end
	RefreshAllSlotPromptsForPlayer(player)
end

function ChestWorkbenchManager.Init()
	local existingRuntimeFolder = workspace:FindFirstChild("ChestWorkbenchRuntime")
	if existingRuntimeFolder and existingRuntimeFolder:IsA("Folder") then
		_visualsFolder = existingRuntimeFolder
	else
		local createdRuntimeFolder = Instance.new("Folder")
		createdRuntimeFolder.Name = "ChestWorkbenchRuntime"
		createdRuntimeFolder.Parent = workspace
		_visualsFolder = createdRuntimeFolder
	end
	-- 勿在主线程长时间 WaitForChild：否则会卡住 init.legacy，PlayerAdded 晚注册，早于监听分配 homeSlot。
	local homesFolder = workspace:FindFirstChild(PLAYERS_HOME_FOLDER_NAME) :: Folder?
	if homesFolder then
		BuildRegistry()
	else
		task.spawn(function()
			local folder = workspace:WaitForChild(PLAYERS_HOME_FOLDER_NAME, 60)
			if folder then
				BuildRegistry()
				for _, plr in players:GetPlayers() do
					local pi = GetServerGameInfo().GetPlayerInfo(plr)
					if pi and pi.homeSlot ~= "" then
						ChestWorkbenchManager.NotifyPlayerHomeSlotReady(plr)
					else
						WaitForHomeSlotThenNotifyWorkbench(plr)
					end
				end
			else
				warn("[ChestWorkbenchManager] PlayersHome missing after 60s; workbench registry empty.")
			end
		end)
	end
	-- InitPlayerInfo 早于 PlayerHomeServerManager 分配 homeSlot；延迟再扫一次，避免工作台稍晚进入 Workspace 时漏注册
	task.delay(2, function()
		BuildRegistry()
		for _, plr in players:GetPlayers() do
			local pi = GetServerGameInfo().GetPlayerInfo(plr)
			if pi and pi.homeSlot ~= "" then
				ChestWorkbenchManager.NotifyPlayerHomeSlotReady(plr)
			end
		end
	end)
	ServerMsg.ConnectPlayerInfoInit(function(player)
		task.defer(function()
			WaitForHomeSlotThenNotifyWorkbench(player)
		end)
	end)
	ServerMsg.ConnectLoadBackpackTools(function(player)
		task.defer(function()
			local pi = GetServerGameInfo().GetPlayerInfo(player)
			if pi and pi.homeSlot ~= "" then
				ChestWorkbenchManager.NotifyPlayerHomeSlotReady(player)
			else
				ChestWorkbenchManager.LoadPlayerVisuals(player)
			end
		end)
	end)
	runService.Heartbeat:Connect(OnHeartbeat)

	local manualEv = NetMsg.GetRequestWorkbenchManualEvent()
	if manualEv then
		manualEv.OnServerEvent:Connect(function(player, instanceKey: any)
			if typeof(instanceKey) ~= "string" then
				return
			end
			local entry = ResolveRegistryEntry(player, instanceKey)
			if not entry then
				return
			end
			OnManualPrompt(entry, player)
		end)
	end

	local purchaseEv = NetMsg.GetRequestPurchaseWorkbenchUpgradeEvent()
	if purchaseEv then
		purchaseEv.OnServerEvent:Connect(function(player, rowId: any, saveKey: any)
			if typeof(rowId) ~= "number" then
				return
			end
			local pinfo = GetServerGameInfo().GetPlayerInfo(player)
			if not pinfo then
				return
			end
			local row = GameConfig.ChestWorkbenchUpgradeByRowId[rowId]
			if not row or ChestWorkbenchIsUpgradeRowPurchased(pinfo.chestWorkbenchSave.purchasedWorkbenchUpgradeIds, rowId) then
				return
			end
			local entry: WorkbenchRegistryEntry? = nil
			if typeof(saveKey) == "string" and saveKey ~= "" then
				local resolved = ResolveRegistryEntry(player, saveKey)
				if
					resolved
					and resolved.workbenchConfigId == row.workbenchId
					and resolved.homeSlotName == pinfo.homeSlot
				then
					entry = resolved
				end
			end
			if entry == nil then
				-- 兼容旧客户端未传 saveKey：多台同 workbenchId 时取距离最近的一台
				local root = GetPlayerHumanoidRootPart(player)
				local bestDist = math.huge
				for _, e in registryList do
					if e.workbenchConfigId ~= row.workbenchId or e.homeSlotName ~= pinfo.homeSlot then
						continue
					end
					if root == nil then
						entry = e
						break
					end
					local dist = PlayerDistanceToModel(player, e.model)
					if dist < bestDist then
						bestDist = dist
						entry = e
					end
				end
			end
			if not entry then
				return
			end
			if PlayerDistanceToModel(player, entry.model) > MAX_INTERACT_DISTANCE then
				return
			end
			EnsureWorkbenchEntry(pinfo, entry.saveKey, #entry.slots)
			local price = row.price
			local currencyKey = tostring(GameConfig.CurrencyType.Coin)
			local coins = pinfo.currencies[currencyKey] or 0
			if coins < price then
				return
			end
			GetServerGameInfo().UpdatePlayerCurrency(player, GameConfig.CurrencyType.Coin, -price, GameConfig.ItemCountChangeReason.SpendOnWorkbenchUpgrade)
			if typeof(pinfo.chestWorkbenchSave.purchasedWorkbenchUpgradeIds) ~= "table" then
				pinfo.chestWorkbenchSave.purchasedWorkbenchUpgradeIds = {}
			end
			pinfo.chestWorkbenchSave.purchasedWorkbenchUpgradeIds[tostring(rowId)] = true
			pinfo.playerInfoChanged = true
			FireSlotSync(player, entry.saveKey, entry)
		end)
	end

	local placeEv = NetMsg.GetRequestPlaceChestOnWorkbenchSlotEvent()
	if placeEv then
		placeEv.OnServerEvent:Connect(function(player, instanceKey: any, slotIndex: any, chestUid: any)
			if typeof(instanceKey) ~= "string" or typeof(slotIndex) ~= "number" or typeof(chestUid) ~= "string" then
				return
			end
			local entry = ResolveRegistryEntry(player, instanceKey)
			if not entry then
				return
			end
			OnPlacePrompt(entry, slotIndex, player)
		end)
	end

	local pickupEv = NetMsg.GetRequestPickupChestFromWorkbenchSlotEvent()
	if pickupEv then
		pickupEv.OnServerEvent:Connect(function(player, instanceKey: any, slotIndex: any)
			if typeof(instanceKey) ~= "string" or typeof(slotIndex) ~= "number" then
				return
			end
			local entry = ResolveRegistryEntry(player, instanceKey)
			if not entry then
				return
			end
			OnPickupPrompt(entry, slotIndex, player)
		end)
	end

	players.PlayerRemoving:Connect(function(plr)
		autoAccuSeconds[plr.UserId] = nil
		manualCooldownUntil[plr.UserId] = nil
		emptySpawnCooldownUntil[plr.UserId] = nil
	end)

	-- 若 Init 晚于首批玩家（多 Script 顺序），补挂等待/刷新
	for _, plr in players:GetPlayers() do
		WaitForHomeSlotThenNotifyWorkbench(plr)
	end
	print("[ChestWorkbenchManager] Init complete registryEntries=", #registryList)
end

return ChestWorkbenchManager
