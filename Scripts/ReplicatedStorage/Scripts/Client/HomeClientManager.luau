--!strict
local players = game:GetService("Players")
local marketplaceService: MarketplaceService = game:GetService("MarketplaceService")
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local proximityPromptService = game:GetService("ProximityPromptService")
local runService = game:GetService("RunService")
local scripts = replicatedStorage:WaitForChild("Scripts")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local GameSoundManager = require(clientScripts:FindFirstChild("GameSoundManager"))
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local UIManager = require(clientScripts:FindFirstChild("UIManager"))
local TranslationTool = require(coreScripts:WaitForChild("Client"):WaitForChild("TranslationTool"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))

local BillboardManager = require(clientScripts:FindFirstChild("BillboardManager"))
local ModelBillboardOffsetTool = require(clientScripts:FindFirstChild("ModelBillboardOffsetTool"))
local BrainrotVariantVisualTool = require(clientScripts:FindFirstChild("BrainrotVariantVisualTool"))
local NumberExtension = require(coreSharedScripts:FindFirstChild("NumberExtension"))

local actualModels = replicatedStorage:WaitForChild("Models"):FindFirstChild("Brainrots")
local HomeClientManager = {}
local homesFolder = workspace:WaitForChild("PlayersHome")

local slotStateCache: { [string]: { active: boolean, homeInfo: any?, isLocalPlayer: boolean?, rebirthLevel: number?, ownerUserId: number? } } = {}
-- 服务端同步时的权威 unclaimedYield；展示数字 = 该值 + 每秒增量 * floor(服务器时间 - anchorTime)
local yieldAnchorServerTime: { [number]: { [string]: number } } = {}
local yieldAnchorModelInstanceId: { [number]: { [string]: string } } = {}
local localUpgradePreviewLevelByKey: { [string]: number } = {}
local lastClaimRequestClockByKey: { [string]: number } = {}
local floorModelsCache: { [string]: { [number]: Model } } = {}
local localSlotInteractionResetLevelBySlot: { [string]: number } = {}
local upgradeUITemplateBackup: SurfaceGui? = nil
local FLOOR_HEIGHT = 32.6
local MAX_FLOOR_COUNT = 3 -- 最大楼层上限
local FLOOR_PLACE_MODELS_NORMALIZED_PLOTS_ATTR = "PlaceModelsNormalizedPlotsPerFloor"
local FLOOR_COLLECT_TOUCH_RESET_ATTR = "CollectTouchReset"
local function GetFloorNumber(inst: Instance): number?
	return tonumber(inst.Name:match("^Lv(%d+)$"))
end

local function FindFloorModel(slotModel: Instance, floorNumber: number): Model?
	local floor = slotModel:FindFirstChild("Lv" .. tostring(floorNumber))
	if floor and floor:IsA("Model") then
		return floor
	end
	return nil
end

local function FindStructuralHomeModel(inst: Instance): Instance?
	if inst.Name:match("^HomeModel") then
		return inst
	end
	for _, child in ipairs(inst:GetChildren()) do
		if child.Name:match("^HomeModel") then
			return child
		end
	end
	return nil
end

local function NormalizeFloorPlaceModels(floorModel: Model, floorNumber: number, plotsPerFloor: number)
	if floorNumber <= 1 or plotsPerFloor <= 0 then
		return
	end
	if floorModel:GetAttribute(FLOOR_PLACE_MODELS_NORMALIZED_PLOTS_ATTR) == plotsPerFloor then
		return
	end
	for _, child in ipairs(floorModel:GetChildren()) do
		local currentPointIndex = tonumber(child.Name:match("^PlaceModel(%d+)$"))
		if currentPointIndex then
			local localPointIndex = ((currentPointIndex - 1) % plotsPerFloor) + 1
			child.Name = "PlaceModel" .. tostring((floorNumber - 1) * plotsPerFloor + localPointIndex)
		end
	end
	floorModel:SetAttribute(FLOOR_PLACE_MODELS_NORMALIZED_PLOTS_ATTR, plotsPerFloor)
end

local function GetFloorModels(slotModel: Instance): { Model }
	local floorModels: { Model } = {}
	for _, child in ipairs(slotModel:GetChildren()) do
		local floorNumber = GetFloorNumber(child)
		if floorNumber and child:IsA("Model") then
			table.insert(floorModels, child)
		end
	end
	table.sort(floorModels, function(left: Model, right: Model): boolean
		return (GetFloorNumber(left) or 0) < (GetFloorNumber(right) or 0)
	end)
	return floorModels
end

local function GetPlotsPerFloor(slotModel: Instance): number
	local lv1 = slotModel:FindFirstChild("Lv1")
	if not lv1 then
		return 6
	end -- Fallback
	local count = 0
	for _, child in ipairs(lv1:GetChildren()) do
		if child.Name:match("^PlaceModel%d+$") then
			count += 1
		end
	end
	return if count > 0 then count else 6
end

local function NormalizeHigherFloorPlaceModels(slotModel: Instance)
	local plotsPerFloor = GetPlotsPerFloor(slotModel)
	for _, floorModel in ipairs(GetFloorModels(slotModel)) do
		local floorNumber = GetFloorNumber(floorModel)
		if floorNumber then
			NormalizeFloorPlaceModels(floorModel, floorNumber, plotsPerFloor)
		end
	end
end

local function ResetFloorCollectTouchBindingsOnce(floorModel: Model)
	if floorModel:GetAttribute(FLOOR_COLLECT_TOUCH_RESET_ATTR) == true then
		return
	end
	for _, desc in ipairs(floorModel:GetDescendants()) do
		if desc.Name == "CollectPart" then
			desc:SetAttribute("TouchBound", nil)
		end
	end
	floorModel:SetAttribute(FLOOR_COLLECT_TOUCH_RESET_ATTR, true)
end

local function GetHigherFloorCloneTemplate(slotModel: Instance, fallbackFloor: Model): (Model, number)
	local lv2 = FindFloorModel(slotModel, 2)
	if lv2 then
		return lv2, 2
	end
	return fallbackFloor, 1
end

local pendingUpdates = {}
local localSlotRecoveryPending = false
local localSlotRecoveryAttemptCount = 0
local skipNextLocalInteractionFocusRefreshBySlot: { [string]: boolean } = {}
local promptToPlotMap: { [ProximityPrompt]: { pointIndex: number, slotName: string } } = {}
local isLocalHoldingBrainrot = false
local lastFocusRefreshAt = 0
local lastFocusSlotName = ""
local lastFocusWinnerPointIndex: number? = nil
-- 与 RefreshLocalHomeInteractionFocus 上次实际写到 winner 的 Enabled 目标一致时才跳过 ApplyFocusToPlot
local lastAppliedFocusPointIndex: number? = nil
local lastAppliedShowPlace: boolean? = nil
local lastAppliedShowSell: boolean? = nil

-- Brainrot 付费升级防抖
local lastBrainrotPaidPromptAt = 0
local BRAINROT_PAID_PROMPT_COOLDOWN = 2

local INTERACTION_FOCUS_REFRESH_INTERVAL = 0.1
-- 略大于激活距离仍保留上一展台焦点，避免在 MaxActivationDistance 边界抖动时关掉 Prompt 打断按住
local INTERACTION_FOCUS_RELEASE_MARGIN_STUDS = 6
local COLLECT_YIELD_TEXT_REFRESH_INTERVAL = 0.12
local CLAIM_REQUEST_COOLDOWN_SEC = 0.8
local lastCollectYieldTextRefreshAt = 0.0
local BILLBOARD_TRACKED_ATTR = "BillboardTracked"
local COLLECT_YIELD_TEXT_MANUAL_ATTR = "CollectYieldTextManual"
local PLACE_MODEL_INFO_UI_BASE_STUDS_OFFSET_Y_ATTR = "BaseStudsOffsetY"
local LOCAL_SLOT_RECOVERY_DELAY = 0.25
local LOCAL_SLOT_RECOVERY_MAX_ATTEMPTS = 24

-- 调试：设为 true 时在 ApplySlotVisuals 节流打印，用于排查高频全量刷新（默认关闭）
local DEBUG_HOME_SLOT_REFRESH = false
local lastDebugHomeApplyClock = 0.0
local DEBUG_COLLECT_YIELD_LOG = false
local COLLECT_YIELD_ZERO_LOG_INTERVAL = 1
local lastCollectYieldZeroLogAtByKey: { [string]: number } = {}

local function DebugCollectYieldLog(eventName: string, ownerUserId: number?, pointIndexStr: string?, data: { [string]: any }?)
	if not DEBUG_COLLECT_YIELD_LOG then
		return
	end
	local detailText = ""
	if data then
		for key, value in pairs(data) do
			detailText ..= " " .. tostring(key) .. "=" .. tostring(value)
		end
	end
	print(
		"[ModelYieldDebug][Client]",
		eventName,
		"userId=" .. tostring(ownerUserId),
		"point=" .. tostring(pointIndexStr),
		detailText
	)
end

local function setProximityPromptEnabledIfChanged(prompt: ProximityPrompt, enabled: boolean)
	if prompt.Enabled ~= enabled then
		prompt.Enabled = enabled
	end
end

local function setBillboardGuiEnabledIfChanged(billboard: BillboardGui, enabled: boolean)
	if billboard.Enabled ~= enabled then
		billboard.Enabled = enabled
	end
end

local function getCollectMultipleForRebirth(rebirthLevel: number): number
	if rebirthLevel <= 0 then
		return 1
	end
	local rbConfig = GameConfig.RebirthMap[rebirthLevel]
	return if rbConfig then rbConfig.collectMultiple else 1
end

local function getPerSecondUnclaimedIncrement(placedData: any, rebirthLevel: number): number
	local brainrotData = GameConfig.BrainrotIdMap[placedData.configId]
	if not brainrotData then
		return 0
	end
	local baseYield = GameConfig.GetBrainrotAbilityWithVariant(brainrotData.baseAbility, placedData.level or 1, placedData.variantId)
	return math.ceil(baseYield * getCollectMultipleForRebirth(rebirthLevel))
end

local function getYieldAnchorTime(ownerUserId: number, pointIndexStr: string): number
	local byPoint = yieldAnchorServerTime[ownerUserId]
	if not byPoint then
		byPoint = {}
		yieldAnchorServerTime[ownerUserId] = byPoint
	end
	if byPoint[pointIndexStr] == nil then
		byPoint[pointIndexStr] = workspace:GetServerTimeNow()
	end
	return byPoint[pointIndexStr]
end

local function resetYieldAnchor(ownerUserId: number, pointIndexStr: string)
	local byPoint = yieldAnchorServerTime[ownerUserId]
	if not byPoint then
		byPoint = {}
		yieldAnchorServerTime[ownerUserId] = byPoint
	end
	byPoint[pointIndexStr] = workspace:GetServerTimeNow()
end

local function getLocalUpgradePreviewKey(ownerUserId: number, pointIndexStr: string, instanceId: string): string
	return tostring(ownerUserId) .. ":" .. pointIndexStr .. ":" .. instanceId
end

local function setCollectYieldText(
	collectText: TextLabel,
	text: string,
	source: string?,
	ownerUserId: number?,
	pointIndexStr: string?,
	displayAmount: number?
)
	if collectText:GetAttribute(COLLECT_YIELD_TEXT_MANUAL_ATTR) ~= true then
		TranslationTool.RemoveCustomAutoLocalizeGui(collectText)
		collectText:SetAttribute(COLLECT_YIELD_TEXT_MANUAL_ATTR, true)
	end
	if text == "0" and collectText.Text ~= "0" then
		local debugKey = tostring(ownerUserId) .. ":" .. tostring(pointIndexStr) .. ":" .. tostring(source)
		local now = os.clock()
		local lastLogAt = lastCollectYieldZeroLogAtByKey[debugKey] or 0
		if now - lastLogAt >= COLLECT_YIELD_ZERO_LOG_INTERVAL then
			lastCollectYieldZeroLogAtByKey[debugKey] = now
			DebugCollectYieldLog("TextSetZero", ownerUserId, pointIndexStr, {
				source = source or "",
				oldText = collectText.Text,
				newText = text,
				displayAmount = displayAmount or 0,
			})
		end
	end
	if collectText.Text ~= text then
		collectText.Text = text
	end
end

local function clearYieldAnchorsForOwner(ownerUserId: number)
	yieldAnchorServerTime[ownerUserId] = nil
	yieldAnchorModelInstanceId[ownerUserId] = nil
end

local function preserveCurrentYieldForSameModels(
	slotName: string,
	incomingHomeInfo: any?,
	ownerUserId: number,
	incomingRebirthLevel: number?
)
	if not incomingHomeInfo or not incomingHomeInfo.placedModels then
		return
	end
	local currentState = slotStateCache[slotName]
	if not currentState or not currentState.homeInfo or not currentState.homeInfo.placedModels then
		return
	end
	local currentRebirthLevel = if currentState.rebirthLevel ~= nil then currentState.rebirthLevel else 0
	local resolvedIncomingRebirthLevel = if incomingRebirthLevel ~= nil then incomingRebirthLevel else currentRebirthLevel
	for pointIndexStr, incomingPlacedData in pairs(incomingHomeInfo.placedModels) do
		local currentPlacedData = currentState.homeInfo.placedModels[pointIndexStr]
		if currentPlacedData == nil then
			continue
		end
		local incomingAny = incomingPlacedData :: any
		local currentAny = currentPlacedData :: any
		local incomingInstanceId = tostring(incomingAny.instanceId or "")
		local currentInstanceId = tostring(currentAny.instanceId or "")
		if incomingInstanceId ~= currentInstanceId then
			continue
		end
		local currentLevel = tonumber(currentAny.level) or 1
		local incomingLevel = tonumber(incomingAny.level) or 1
		local previewKey = getLocalUpgradePreviewKey(ownerUserId, pointIndexStr, incomingInstanceId)
		local previewLevel = localUpgradePreviewLevelByKey[previewKey]
		if previewLevel ~= nil then
			if incomingLevel < previewLevel then
				incomingAny.level = previewLevel
				incomingLevel = previewLevel
			else
				localUpgradePreviewLevelByKey[previewKey] = nil
			end
		end
		local currentVariantId = tonumber(currentAny.variantId) or 0
		local incomingVariantId = tonumber(incomingAny.variantId) or 0
		local yieldRateChanged = currentLevel ~= incomingLevel
			or currentVariantId ~= incomingVariantId
			or currentRebirthLevel ~= resolvedIncomingRebirthLevel
		if yieldRateChanged then
			local currentBaseYield: number = if type(currentAny.unclaimedYield) == "number" then currentAny.unclaimedYield else 0
			local currentAnchorT = getYieldAnchorTime(ownerUserId, pointIndexStr)
			local currentPerSec = getPerSecondUnclaimedIncrement(currentPlacedData, currentRebirthLevel)
			local currentElapsed = math.max(0, math.floor(workspace:GetServerTimeNow() - currentAnchorT))
			local currentDisplayYield = currentBaseYield + currentPerSec * currentElapsed
			DebugCollectYieldLog("HomeInfoPreserveYieldRateChange", ownerUserId, pointIndexStr, {
				homeSlot = slotName,
				instanceId = incomingInstanceId,
				currentLevel = currentLevel,
				incomingLevel = incomingLevel,
				currentYield = currentBaseYield,
				displayYield = currentDisplayYield,
			})
			incomingAny.unclaimedYield = currentDisplayYield
			resetYieldAnchor(ownerUserId, pointIndexStr)
			continue
		end
		local incomingYield = if type(incomingAny.unclaimedYield) == "number" then incomingAny.unclaimedYield else 0
		local currentYield = if type(currentAny.unclaimedYield) == "number" then currentAny.unclaimedYield else 0
		if currentYield > incomingYield then
			DebugCollectYieldLog("HomeInfoPreserveYield", nil, pointIndexStr, {
				homeSlot = slotName,
				instanceId = incomingInstanceId,
				incomingYield = incomingYield,
				currentYield = currentYield,
			})
			incomingAny.unclaimedYield = currentYield
		elseif incomingYield > currentYield then
			DebugCollectYieldLog("HomeInfoAcceptAdvancedYield", ownerUserId, pointIndexStr, {
				homeSlot = slotName,
				instanceId = incomingInstanceId,
				incomingYield = incomingYield,
				currentYield = currentYield,
			})
			resetYieldAnchor(ownerUserId, pointIndexStr)
		end
	end
end

local function syncAllYieldAnchorsForOwner(ownerUserId: number, homeInfo: any?)
	if not homeInfo or not homeInfo.placedModels then
		clearYieldAnchorsForOwner(ownerUserId)
		return
	end
	local now = workspace:GetServerTimeNow()
	local byPoint = yieldAnchorServerTime[ownerUserId]
	if not byPoint then
		byPoint = {}
		yieldAnchorServerTime[ownerUserId] = byPoint
	end
	local byModelId = yieldAnchorModelInstanceId[ownerUserId]
	if not byModelId then
		byModelId = {}
		yieldAnchorModelInstanceId[ownerUserId] = byModelId
	end
	for pointIndexStr, placedData in pairs(homeInfo.placedModels) do
		local instanceId = tostring((placedData :: any).instanceId or "")
		if byPoint[pointIndexStr] == nil or byModelId[pointIndexStr] ~= instanceId then
			DebugCollectYieldLog("HomeAnchorReset", ownerUserId, pointIndexStr, {
				oldAnchor = byPoint[pointIndexStr] or 0,
				oldInstanceId = byModelId[pointIndexStr] or "",
				newInstanceId = instanceId,
				baseYield = ((placedData :: any).unclaimedYield or 0),
			})
			byPoint[pointIndexStr] = now
			byModelId[pointIndexStr] = instanceId
		end
	end
	for pointIndexStr in pairs(byPoint) do
		if homeInfo.placedModels[pointIndexStr] == nil then
			DebugCollectYieldLog("HomeAnchorClear", ownerUserId, pointIndexStr, {
				oldAnchor = byPoint[pointIndexStr] or 0,
				oldInstanceId = byModelId[pointIndexStr] or "",
			})
			byPoint[pointIndexStr] = nil
			byModelId[pointIndexStr] = nil
		end
	end
end

local function getExtrapolatedUnclaimedDisplay(ownerUserId: number, pointIndexStr: string, placedData: any, rebirthLevel: number): number
	local m = placedData :: any
	local baseAmount: number = if type(m.unclaimedYield) == "number" then m.unclaimedYield else 0
	local anchorT = getYieldAnchorTime(ownerUserId, pointIndexStr)
	local perSec = getPerSecondUnclaimedIncrement(placedData, rebirthLevel)
	local elapsed = math.max(0, math.floor(workspace:GetServerTimeNow() - anchorT))
	return baseAmount + perSec * elapsed
end

local function findPlaceModelFolder(slotModel: Instance, pointIndexStr: string): Instance?
	NormalizeHigherFloorPlaceModels(slotModel)
	for _, floor in ipairs(GetFloorModels(slotModel)) do
		local plot = floor:FindFirstChild("PlaceModel" .. pointIndexStr)
		if plot then
			return plot
		end
	end
	return nil
end

local function formatCollectYieldDisplay(ownerUserId: number?, pointIndexStr: string, placedData: any, rebirthLevel: number): string
	if ownerUserId == nil then
		local m = placedData :: any
		local y: number = if type(m.unclaimedYield) == "number" then m.unclaimedYield else 0
		return NumberExtension.FormatBigNumberAA(y)
	end
	return NumberExtension.FormatBigNumberAA(getExtrapolatedUnclaimedDisplay(ownerUserId, pointIndexStr, placedData, rebirthLevel))
end

local function refreshCollectYieldTextsForActiveHomes()
	local nowClock = os.clock()
	if nowClock - lastCollectYieldTextRefreshAt < COLLECT_YIELD_TEXT_REFRESH_INTERVAL then
		return
	end
	lastCollectYieldTextRefreshAt = nowClock
	for slotName, state in pairs(slotStateCache) do
		if not state.active or not state.homeInfo or not state.homeInfo.placedModels then
			continue
		end
		local ownerUserId = state.ownerUserId
		if ownerUserId == nil and state.isLocalPlayer then
			ownerUserId = players.LocalPlayer.UserId
		end
		if ownerUserId == nil then
			continue
		end
		local slotModel = homesFolder:FindFirstChild(slotName) :: Model?
		if not slotModel then
			continue
		end
		local rebirthLevel = if state.rebirthLevel ~= nil then state.rebirthLevel else 0
		for pointIndexStr, placedData in pairs(state.homeInfo.placedModels) do
			if placedData == nil then
				continue
			end
			local plot = findPlaceModelFolder(slotModel, pointIndexStr)
			if not plot then
				continue
			end
			local booth = plot:FindFirstChild("Booth")
			local collectPart = booth and booth:FindFirstChild("CollectPart")
			local collectUI = collectPart and collectPart:FindFirstChild("CollectUI") :: SurfaceGui?
			if not collectUI then
				continue
			end
			local controller = collectUI:FindFirstChild("ControllerFrame")
			local collectText = controller and controller:FindFirstChild("CollectText") :: TextLabel?
			if not collectText then
				continue
			end
			local displayAmount = getExtrapolatedUnclaimedDisplay(ownerUserId, pointIndexStr, placedData, rebirthLevel)
			setCollectYieldText(
				collectText,
				NumberExtension.FormatBigNumberAA(displayAmount),
				"HeartbeatRefresh",
				ownerUserId,
				pointIndexStr,
				displayAmount
			)
		end
	end
end

local function EnsureBillboardTracked(gui: BillboardGui)
	if gui:GetAttribute(BILLBOARD_TRACKED_ATTR) ~= true then
		gui:SetAttribute(BILLBOARD_TRACKED_ATTR, true)
	end
	BillboardManager.Track(gui)
end

local function LocalizeQualityLabel(qualityLabel: TextLabel, quality: number)
	local qualityTextName = GameConfig.BrainrotQualityTextMap[quality]
	local qualityTextData = if qualityTextName then ((GameTexts :: any)[qualityTextName] :: { source: string, key: string }?) else nil
	if qualityTextData then
		TranslationTool.CustomAutoLocalizeTextLabel(qualityLabel, qualityTextData.source, qualityTextData.key, {})
	else
		TranslationTool.CustomAutoLocalizeTextLabel(qualityLabel, "", "", {})
	end
end

-- Forward declarations
local UpdateHomeVisuals, ClearHomeVisuals

local function ApplySlotVisuals(slotName: string)
	if DEBUG_HOME_SLOT_REFRESH then
		local c = os.clock()
		if c - lastDebugHomeApplyClock >= 0.25 then
			lastDebugHomeApplyClock = c
			print("[HomeClientManager] ApplySlotVisuals", slotName, c)
		end
	end
	local state = slotStateCache[slotName]
	if state and state.active then
		UpdateHomeVisuals(slotName, state.homeInfo, state.isLocalPlayer or false)
	else
		ClearHomeVisuals(slotName)
	end
end

local function ApplyLocalBrainrotUpgradePreview(slotName: string, pointIndex: number, levelAdd: number?): boolean
	local state = slotStateCache[slotName]
	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not state or not state.homeInfo or not state.isLocalPlayer or not playerInfo then
		return false
	end

	local pointIndexStr = tostring(pointIndex)
	local placedData = state.homeInfo.placedModels[pointIndexStr]
	if not placedData then
		return false
	end

	local brainrotData = GameConfig.BrainrotIdMap[placedData.configId]
	if not brainrotData then
		return false
	end

	local resolvedLevelAdd = math.max(1, levelAdd or 1)
	local currentLevel = placedData.level or 1
	local totalCost = 0
	for i = 0, resolvedLevelAdd - 1 do
		totalCost += GameConfig.GetBrainrotUpgradeCost(brainrotData.baseAbility, currentLevel + i)
	end

	local currencyKey = tostring(GameConfig.CurrencyType.Coin)
	local currentGold = playerInfo.currencies[currencyKey] or 0
	if currentGold < totalCost then
		return false
	end

	local ownerUserId = players.LocalPlayer.UserId
	local rebirthForYield = if state.rebirthLevel ~= nil then state.rebirthLevel else 0
	local displayYield = getExtrapolatedUnclaimedDisplay(ownerUserId, pointIndexStr, placedData, rebirthForYield)
	local placedDataAny = placedData :: any
	placedDataAny.unclaimedYield = displayYield
	resetYieldAnchor(ownerUserId, pointIndexStr)
	placedData.level = currentLevel + resolvedLevelAdd
	local instanceId = tostring(placedDataAny.instanceId or "")
	localUpgradePreviewLevelByKey[getLocalUpgradePreviewKey(ownerUserId, pointIndexStr, instanceId)] = placedData.level

	playerInfo.currencies[currencyKey] = currentGold - totalCost
	ClientMsg.FireLocalPlayerCurrencyUpdate()

	if playerInfo.homeInfo and playerInfo.homeInfo.placedModels then
		local localPlacedData = playerInfo.homeInfo.placedModels[pointIndexStr]
		if localPlacedData and localPlacedData ~= placedData then
			local localPlacedDataAny = localPlacedData :: any
			localPlacedDataAny.unclaimedYield = displayYield
			localPlacedData.level = placedData.level
		end
	end

	ApplySlotVisuals(slotName)
	return true
end

-- Helper to update prompt visibility/text without full plot refresh
local function SetPromptState(
	attachment: Attachment?,
	visible: boolean,
	isOccupied: boolean,
	plotIndex: number,
	currentSlotName: string,
	applyEnabled: boolean?,
	holdingBrainrot: boolean?
)
	if not attachment then
		return
	end
	local shouldApplyEnabled = if applyEnabled == nil then true else applyEnabled
	local prompt = attachment:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		if shouldApplyEnabled then
			setProximityPromptEnabledIfChanged(prompt, visible)
		end
		promptToPlotMap[prompt] = { pointIndex = plotIndex, slotName = currentSlotName }
		if isOccupied then
			if holdingBrainrot then
				TranslationTool.CustomAutoLocalizeProximityPrompt(
					prompt,
					GameTexts.ReplaceBoothBrainrot.source,
					GameTexts.ReplaceBoothBrainrot.key
				)
			else
				TranslationTool.CustomAutoLocalizeProximityPrompt(prompt, GameTexts.PickUpBrainrot.source, GameTexts.PickUpBrainrot.key)
			end
		else
			TranslationTool.CustomAutoLocalizeProximityPrompt(prompt, GameTexts.PlaceAction.source, GameTexts.PlaceAction.key)
		end
	end
	local billboard = attachment:FindFirstChildOfClass("BillboardGui")
	if billboard then
		if shouldApplyEnabled then
			setBillboardGuiEnabledIfChanged(billboard, visible)
		end
		EnsureBillboardTracked(billboard)
	end
end

local function SetSellButtonVisibility(
	attachment: Attachment?,
	visible: boolean,
	plotIndex: number,
	slotName: string,
	applyEnabled: boolean?
)
	if not attachment then
		return
	end
	local shouldApplyEnabled = if applyEnabled == nil then true else applyEnabled
	local prompt = attachment:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		if shouldApplyEnabled then
			setProximityPromptEnabledIfChanged(prompt, visible)
		end
		promptToPlotMap[prompt] = { pointIndex = plotIndex, slotName = slotName }
	end
	local billboard = attachment:FindFirstChildOfClass("BillboardGui")
	if billboard then
		if shouldApplyEnabled then
			setBillboardGuiEnabledIfChanged(billboard, visible)
		end
		EnsureBillboardTracked(billboard)
	end
end

local function ResetPlotInteractionVisibility(placeAttachment: Attachment?, sellAttachment: Attachment?)
	local function DisableAttachmentInteraction(attachment: Attachment?)
		if not attachment then
			return
		end
		local prompt = attachment:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			setProximityPromptEnabledIfChanged(prompt, false)
		end
		local billboard = attachment:FindFirstChildOfClass("BillboardGui")
		if billboard then
			setBillboardGuiEnabledIfChanged(billboard, false)
		end
	end

	DisableAttachmentInteraction(placeAttachment)
	DisableAttachmentInteraction(sellAttachment)
end

-- 本地家：在进入 UpdatePlot 前一次性关闭所有展台交互，避免每个 PlaceModel 各 Reset 一遍导致 winner 被反复 false→true
local function ResetLocalSlotAllPlotInteractionVisibility(slotModel: Instance)
	for _, floor in ipairs(GetFloorModels(slotModel)) do
		for _, plot in ipairs(floor:GetChildren()) do
			if plot.Name:match("^PlaceModel%d+$") then
				local rootPart = plot:FindFirstChild("RootPart") :: BasePart?
				local placeAttachment = rootPart and rootPart:FindFirstChild("PlaceAttachment") :: Attachment?
				local sellAttachment = rootPart and rootPart:FindFirstChild("SellAttachment") :: Attachment?
				ResetPlotInteractionVisibility(placeAttachment, sellAttachment)
			end
		end
	end
	-- 全槽 Prompt 已关；若保留旧的 lastApplied*，下一次 Refresh 会误判「已应用」而跳过 ApplyFocusToPlot，导致按钮一直关着
	lastAppliedFocusPointIndex = nil
	lastAppliedShowPlace = nil
	lastAppliedShowSell = nil
end

local function ShouldResetLocalSlotInteractionVisibility(slotName: string, homeInfo: any): boolean
	local homeLevel = tonumber(homeInfo.level) or 1
	if localSlotInteractionResetLevelBySlot[slotName] == homeLevel then
		return false
	end
	localSlotInteractionResetLevelBySlot[slotName] = homeLevel
	return true
end

local function FindPlotByPointIndex(slotModel: Instance, pointIndex: number): Instance?
	NormalizeHigherFloorPlaceModels(slotModel)
	for _, floor in ipairs(GetFloorModels(slotModel)) do
		local plot = floor:FindFirstChild("PlaceModel" .. tostring(pointIndex))
		if plot then
			return plot
		end
	end
	return nil
end

local function ApplyFocusToPlot(slotModel: Instance, pointIndex: number, showPlace: boolean, showSell: boolean)
	local plot = FindPlotByPointIndex(slotModel, pointIndex)
	if not plot then
		return
	end
	local rootPart = plot:FindFirstChild("RootPart") :: BasePart?
	local placeAttachment = rootPart and rootPart:FindFirstChild("PlaceAttachment") :: Attachment?
	local sellAttachment = rootPart and rootPart:FindFirstChild("SellAttachment") :: Attachment?
	if placeAttachment then
		local placePrompt = placeAttachment:FindFirstChildOfClass("ProximityPrompt")
		if placePrompt then
			setProximityPromptEnabledIfChanged(placePrompt, showPlace)
		end
		local placeBillboard = placeAttachment:FindFirstChildOfClass("BillboardGui")
		if placeBillboard then
			setBillboardGuiEnabledIfChanged(placeBillboard, showPlace)
		end
	end
	if sellAttachment then
		local sellPrompt = sellAttachment:FindFirstChildOfClass("ProximityPrompt")
		if sellPrompt then
			setProximityPromptEnabledIfChanged(sellPrompt, showSell)
		end
		local sellBillboard = sellAttachment:FindFirstChildOfClass("BillboardGui")
		if sellBillboard then
			setBillboardGuiEnabledIfChanged(sellBillboard, showSell)
		end
	end
end

local function ClearLastFocusWinner()
	if lastFocusWinnerPointIndex == nil or lastFocusSlotName == "" then
		lastFocusWinnerPointIndex = nil
		lastAppliedFocusPointIndex = nil
		lastAppliedShowPlace = nil
		lastAppliedShowSell = nil
		return
	end
	local slotModel = homesFolder:FindFirstChild(lastFocusSlotName)
	if slotModel then
		ApplyFocusToPlot(slotModel, lastFocusWinnerPointIndex, false, false)
	end
	lastFocusWinnerPointIndex = nil
	lastAppliedFocusPointIndex = nil
	lastAppliedShowPlace = nil
	lastAppliedShowSell = nil
end

local function RefreshLocalHomeInteractionFocus(force: boolean?)
	local now = os.clock()
	-- 初始化或等级变化会重置全部 Prompt；这些场景必须绕过节流，立即恢复当前焦点。
	if not force and (now - lastFocusRefreshAt < INTERACTION_FOCUS_REFRESH_INTERVAL) then
		return
	end
	lastFocusRefreshAt = now

	local localInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not localInfo or localInfo.homeSlot == nil or localInfo.homeSlot == "" then
		ClearLastFocusWinner()
		return
	end
	local slotName = localInfo.homeSlot
	if slotName ~= lastFocusSlotName then
		ClearLastFocusWinner()
		lastFocusSlotName = slotName
	end
	local state = slotStateCache[slotName]
	if not state or not state.active or not state.isLocalPlayer or not state.homeInfo then
		ClearLastFocusWinner()
		return
	end
	local homeInfo = state.homeInfo
	local slotModel = homesFolder:FindFirstChild(slotName)
	if not slotModel then
		return
	end
	NormalizeHigherFloorPlaceModels(slotModel)

	local char = players.LocalPlayer.Character
	local charPos: Vector3? = nil
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			charPos = hrp.Position
		else
			charPos = char:GetPivot().Position
		end
	end

	-- UpgradeHome HomePart.InfoUI：仅本地玩家显示；水平距离<=阈值隐藏，超过才显示
	local upgradeHomeModel = slotModel:FindFirstChild("UpgradeHome") :: Model?
	local homePart = upgradeHomeModel and upgradeHomeModel:FindFirstChild("HomePart") :: BasePart?
	local infoUI = homePart and homePart:FindFirstChild("InfoUI") :: BillboardGui?
	if infoUI then
		if charPos and homePart then
			local homePos = homePart.Position
			local delta = Vector3.new(homePos.X, 0, homePos.Z) - Vector3.new(charPos.X, 0, charPos.Z)
			local horizontalDistance = delta.Magnitude
			local wantInfoEnabled = horizontalDistance > GameConfig.UpgradeHomeInfoUIDistanceLimit
			if infoUI.Enabled ~= wantInfoEnabled then
				infoUI.Enabled = wantInfoEnabled
			end
		else
			-- 没有角色坐标时，保证不显示
			if infoUI.Enabled ~= false then
				infoUI.Enabled = false
			end
		end
	end

	-- 无 HRP 的一帧不重新算展台焦点，避免误关 ProximityPrompt 打断按住
	if charPos == nil then
		return
	end

	local winnerPointIndex: number? = nil
	local winnerDist = math.huge
	local charPosNonNil = charPos :: Vector3
	for _, floor in ipairs(GetFloorModels(slotModel)) do
		local floorNumber = GetFloorNumber(floor)
		if not floorNumber or floorNumber > homeInfo.level then
			continue
		end
		for _, plot in ipairs(floor:GetChildren()) do
			local pointIndex = tonumber(plot.Name:match("^PlaceModel(%d+)$"))
			if not pointIndex then
				continue
			end
			local isOccupied = homeInfo.placedModels[tostring(pointIndex)] ~= nil
			local wantPlace = (not isOccupied and isLocalHoldingBrainrot) or isOccupied
			local wantSell = isOccupied
			if wantPlace or wantSell then
				local rootPart = plot:FindFirstChild("RootPart") :: BasePart?
				if rootPart then
					local dist = (rootPart.Position - charPosNonNil).Magnitude
					local placeAttachment = rootPart:FindFirstChild("PlaceAttachment")
					local placePrompt = placeAttachment and placeAttachment:FindFirstChildOfClass("ProximityPrompt")
					local maxDist = if placePrompt then placePrompt.MaxActivationDistance else 15
					if dist <= maxDist and (dist < winnerDist or (dist == winnerDist and winnerPointIndex ~= nil and pointIndex < winnerPointIndex)) then
						winnerDist = dist
						winnerPointIndex = pointIndex
					end
				end
			end
		end
	end

	if winnerPointIndex == nil and lastFocusWinnerPointIndex ~= nil then
		local lastPlot = FindPlotByPointIndex(slotModel, lastFocusWinnerPointIndex)
		if lastPlot then
			local lastRoot = lastPlot:FindFirstChild("RootPart") :: BasePart?
			if lastRoot then
				local lastDist = (lastRoot.Position - charPosNonNil).Magnitude
				local lastOcc = homeInfo.placedModels[tostring(lastFocusWinnerPointIndex)] ~= nil
				local lastWantPlace = (not lastOcc and isLocalHoldingBrainrot) or lastOcc
				local lastWantSell = lastOcc
				local lastPlaceAtt = lastRoot:FindFirstChild("PlaceAttachment")
				local lastPlacePrompt = lastPlaceAtt and lastPlaceAtt:FindFirstChildOfClass("ProximityPrompt")
				local lastMax = if lastPlacePrompt then lastPlacePrompt.MaxActivationDistance else 15
				if (lastWantPlace or lastWantSell) and lastDist <= lastMax + INTERACTION_FOCUS_RELEASE_MARGIN_STUDS then
					winnerPointIndex = lastFocusWinnerPointIndex
					winnerDist = lastDist
				end
			end
		end
	end

	if lastFocusWinnerPointIndex ~= nil and lastFocusWinnerPointIndex ~= winnerPointIndex then
		ApplyFocusToPlot(slotModel, lastFocusWinnerPointIndex, false, false)
		lastAppliedFocusPointIndex = nil
		lastAppliedShowPlace = nil
		lastAppliedShowSell = nil
	end
	if winnerPointIndex ~= nil then
		local isOccupied = homeInfo.placedModels[tostring(winnerPointIndex)] ~= nil
		local showPlace = (not isOccupied and isLocalHoldingBrainrot) or isOccupied
		local showSell = isOccupied
		if lastAppliedFocusPointIndex ~= winnerPointIndex or lastAppliedShowPlace ~= showPlace or lastAppliedShowSell ~= showSell then
			ApplyFocusToPlot(slotModel, winnerPointIndex, showPlace, showSell)
		end
		lastAppliedFocusPointIndex = winnerPointIndex
		lastAppliedShowPlace = showPlace
		lastAppliedShowSell = showSell
	else
		lastAppliedFocusPointIndex = nil
		lastAppliedShowPlace = nil
		lastAppliedShowSell = nil
	end
	lastFocusWinnerPointIndex = winnerPointIndex
end

-- Focus on refreshing only interactive prompts (lighter than full refresh)
local function UpdateHomePrompts(slotName: string)
	local slotModel = homesFolder:FindFirstChild(slotName)
	local state = slotStateCache[slotName]
	if not slotModel or not state or not state.active then
		return
	end

	local isLocalPlayer = state.isLocalPlayer or false
	local homeInfo = state.homeInfo
	if not homeInfo then
		return
	end
	NormalizeHigherFloorPlaceModels(slotModel)

	for _, floor in ipairs(GetFloorModels(slotModel)) do
		local floorNumber = GetFloorNumber(floor)
		if not floorNumber or floorNumber > homeInfo.level then
			continue
		end
		for _, plot in ipairs(floor:GetChildren()) do
			local pointIndex = tonumber(plot.Name:match("^PlaceModel(%d+)$"))
			if pointIndex then
				local isOccupied = homeInfo.placedModels[tostring(pointIndex)] ~= nil
				local rootPart = plot:FindFirstChild("RootPart") :: BasePart?
				local placeAttachment = rootPart and rootPart:FindFirstChild("PlaceAttachment") :: Attachment?
				local sellAttachment = rootPart and rootPart:FindFirstChild("SellAttachment") :: Attachment?

				local showPlacePrompt = (not isOccupied and isLocalPlayer and isLocalHoldingBrainrot) or (isOccupied and isLocalPlayer)
				if isLocalPlayer then
					SetPromptState(placeAttachment, showPlacePrompt, isOccupied, pointIndex, slotName, false, isLocalHoldingBrainrot)
					SetSellButtonVisibility(sellAttachment, isOccupied and isLocalPlayer, pointIndex, slotName, false)
				else
					SetPromptState(placeAttachment, showPlacePrompt, isOccupied, pointIndex, slotName, nil, isLocalHoldingBrainrot)
					SetSellButtonVisibility(sellAttachment, isOccupied and isLocalPlayer, pointIndex, slotName)
				end
			end
		end
	end
	if isLocalPlayer then
		RefreshLocalHomeInteractionFocus(true)
	end
end

local function ScheduleSlotUpdate(slotName: string)
	if pendingUpdates[slotName] then
		return
	end
	pendingUpdates[slotName] = true
	task.delay(0.2, function()
		if not pendingUpdates[slotName] then
			return
		end
		pendingUpdates[slotName] = nil
		--print("[HomeClientManager] Applying visuals for slot", slotName)
		ApplySlotVisuals(slotName)
	end)
end

local function HasSamePlacedModelOccupancy(prevHomeInfo: any?, nextHomeInfo: any?): boolean
	if prevHomeInfo == nil or nextHomeInfo == nil then
		return false
	end
	local prevPlacedModels = prevHomeInfo.placedModels
	local nextPlacedModels = nextHomeInfo.placedModels
	if type(prevPlacedModels) ~= "table" or type(nextPlacedModels) ~= "table" then
		return false
	end

	for pointIndexStr, prevPlacedData in pairs(prevPlacedModels) do
		local prevOccupied = prevPlacedData ~= nil
		local nextOccupied = nextPlacedModels[pointIndexStr] ~= nil
		if prevOccupied ~= nextOccupied then
			return false
		end
	end
	for pointIndexStr, nextPlacedData in pairs(nextPlacedModels) do
		local prevOccupied = prevPlacedModels[pointIndexStr] ~= nil
		local nextOccupied = nextPlacedData ~= nil
		if prevOccupied ~= nextOccupied then
			return false
		end
	end
	return true
end

local function IsDescendantOfWorkbenchContainer(inst: Instance): boolean
	local cur: Instance? = inst
	while cur ~= nil do
		if cur.Name == WORKBENCH_CONTAINER_NAME then
			return true
		end
		cur = cur.Parent
	end
	return false
end

local function ShouldScheduleSlotUpdateOnDescendantAdded(inst: Instance): boolean
	-- Home 仅负责展台（PlaceModel）；工作台（WorkbenchModel）增量统一由 ChestWorkbenchClientManager 处理
	if IsDescendantOfWorkbenchContainer(inst) then
		return false
	end

	-- 纯 UI 增量默认不触发结构刷新；关键 SurfaceGui 例外（可能影响交互可见性）
	if inst:IsA("BillboardGui") then
		return false
	end
	if inst:IsA("SurfaceGui") then
		return inst.Name == "UpgradeUI" or inst.Name == "CollectUI"
	end
	if inst:IsA("GuiObject") or inst:IsA("UIBase") then
		return false
	end

	-- 仅结构/交互相关对象触发槽位刷新
	if inst.Name:match("^Lv%d+$") or inst.Name:match("^PlaceModel%d+$") then
		return true
	end
	if inst.Name == "Booth" or inst.Name == "RootPart" or inst.Name == "PlaceAttachment" or inst.Name == "SellAttachment" then
		return true
	end
	if inst:IsA("Model") or inst:IsA("BasePart") or inst:IsA("Attachment") or inst:IsA("ProximityPrompt") then
		return true
	end

	return false
end

local function ApplyLocalSlotVisualsIfReady(): boolean
	local localInfo: any = ClientGameInfo.GetLocalPlayerInfo()
	if not localInfo or not localInfo.homeSlot or localInfo.homeSlot == "" or not localInfo.homeInfo then
		return false
	end

	local slotName = localInfo.homeSlot
	slotStateCache[slotName] = {
		active = true,
		homeInfo = localInfo.homeInfo,
		isLocalPlayer = true,
		rebirthLevel = if localInfo.shopInfo then localInfo.shopInfo.rebirthLevel else 0,
		ownerUserId = players.LocalPlayer.UserId,
	}
	syncAllYieldAnchorsForOwner(players.LocalPlayer.UserId, localInfo.homeInfo)
	ApplySlotVisuals(slotName)

	-- Streaming 场景下槽位模型可能晚到，补一次延迟刷新。
	if not homesFolder:FindFirstChild(slotName) then
		ScheduleSlotUpdate(slotName)
	end

	localSlotRecoveryAttemptCount = 0
	return true
end

local function ScheduleLocalSlotRecovery(resetAttempts: boolean?)
	if resetAttempts then
		localSlotRecoveryAttemptCount = 0
	end

	if ApplyLocalSlotVisualsIfReady() then
		return
	end

	if localSlotRecoveryPending or localSlotRecoveryAttemptCount >= LOCAL_SLOT_RECOVERY_MAX_ATTEMPTS then
		return
	end

	localSlotRecoveryPending = true
	localSlotRecoveryAttemptCount += 1
	task.delay(LOCAL_SLOT_RECOVERY_DELAY, function()
		localSlotRecoveryPending = false
		if not ApplyLocalSlotVisualsIfReady() then
			ScheduleLocalSlotRecovery(false)
		end
	end)
end

-- Helper to set visibility/collision for various instance types
local function SetVisuals(inst: Instance, visible: boolean, isPlaceholder: boolean?)
	if inst.Name == "SpawnLocation" then
		return
	end
	if inst:IsA("BasePart") then
		local targetTransparency = if visible then 0 else 1
		local targetCanCollide = visible and not isPlaceholder
		if inst.Transparency ~= targetTransparency then
			inst.Transparency = targetTransparency
		end
		if inst.CanCollide ~= targetCanCollide then
			inst.CanCollide = targetCanCollide
		end
	elseif inst:IsA("Decal") then
		local targetTransparency = if visible then 0 else 1
		if inst.Transparency ~= targetTransparency then
			inst.Transparency = targetTransparency
		end
	elseif inst:IsA("ParticleEmitter") or inst:IsA("BillboardGui") or inst:IsA("Texture") or inst:IsA("SurfaceGui") then
		local enabledInstance = inst :: any
		if enabledInstance.Enabled ~= visible then
			enabledInstance.Enabled = visible
		end
	end
end

local function DisablePlaceModelLightEmitters(lightEmitter: ParticleEmitter?, lightEffectEmitter: ParticleEmitter?)
	if lightEmitter then
		if lightEmitter.Enabled then
			lightEmitter.Enabled = false
		end
		lightEmitter:Clear()
	end
	if lightEffectEmitter then
		if lightEffectEmitter.Enabled then
			lightEffectEmitter.Enabled = false
		end
		lightEffectEmitter:Clear()
	end
end

local function UpdatePlaceModelLightEmitters(
	lightEmitter: ParticleEmitter?,
	lightEffectEmitter: ParticleEmitter?,
	shouldEnable: boolean,
	lightColor: Color3?
)
	if not shouldEnable or not lightEmitter or not lightColor then
		DisablePlaceModelLightEmitters(lightEmitter, lightEffectEmitter)
		return
	end

	local colorSequence = ColorSequence.new(lightColor)
	if not lightEmitter.Enabled then
		lightEmitter:Clear()
		if lightEffectEmitter then
			lightEffectEmitter:Clear()
		end
		lightEmitter.Color = colorSequence
		lightEmitter.Enabled = true
		if lightEffectEmitter then
			lightEffectEmitter.Enabled = true
		end
		return
	end

	lightEmitter.Color = colorSequence
end

-- UpgradeHome/HomePart/InfoUI 的 Enabled 由 RefreshLocalHomeInteractionFocus 按距离控制，不能用 SetVisuals 覆盖
local function IsUpgradeHomePartInfoUI(desc: Instance): boolean
	return desc:IsA("BillboardGui")
		and desc.Name == "InfoUI"
		and desc.Parent ~= nil
		and desc.Parent.Name == "HomePart"
end

-- Helper to ensure BillboardGui is set up for adaptation
local function SetupBillboardAdaptation(gui: BillboardGui)
	local controller = gui:FindFirstChild("ControllerFrame") :: Frame?
	if not controller then
		return
	end

	-- Ensure UIScale exists
	local uiScale = controller:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale") :: UIScale
		if uiScale then
			uiScale.Name = "UIScale"
			uiScale.Parent = controller
		end
	end

	-- Ensure ControllerFrame size is in Offset for BillboardManager
	-- If it's using Scale, convert it to current AbsoluteSize
	if controller.Size.X.Scale > 0 or controller.Size.Y.Scale > 0 then
		local absSize = controller.AbsoluteSize
		if absSize.X > 0 and absSize.Y > 0 then
			controller.Size = UDim2.fromOffset(absSize.X, absSize.Y)
		end
	end

	EnsureBillboardTracked(gui)
end

local function CaptureUpgradeUITemplateBackup(sourceUI: SurfaceGui)
	if upgradeUITemplateBackup then
		return
	end
	local backup = sourceUI:Clone()
	upgradeUITemplateBackup = backup
end

local function GetLocalPlayerGui(): PlayerGui?
	return players.LocalPlayer:FindFirstChild("PlayerGui") :: PlayerGui?
end

local function FindMovedUpgradeUI(upgradePart: BasePart): SurfaceGui?
	local playerGui = GetLocalPlayerGui()
	if not playerGui then
		return nil
	end
	for _, gui in ipairs(playerGui:GetChildren()) do
		if gui:IsA("SurfaceGui") and gui.Name == "UpgradeUI" and gui.Adornee == upgradePart then
			return gui
		end
	end
	return nil
end

local function DestroyUpgradeUIsForPart(upgradePart: BasePart)
	local childUI = upgradePart:FindFirstChild("UpgradeUI")
	if childUI and childUI:IsA("SurfaceGui") then
		childUI.Enabled = false
	end

	local playerGui = GetLocalPlayerGui()
	if not playerGui then
		return
	end
	for _, gui in ipairs(playerGui:GetChildren()) do
		if gui:IsA("SurfaceGui") and gui.Name == "UpgradeUI" and gui.Adornee == upgradePart then
			gui:Destroy()
		end
	end
end

local function EnsureMovedUpgradeUI(upgradePart: BasePart): SurfaceGui?
	local movedUI = FindMovedUpgradeUI(upgradePart)
	if movedUI then
		return movedUI
	end

	local upgradeUI = upgradePart:FindFirstChild("UpgradeUI") :: SurfaceGui?
	if not upgradeUI and upgradeUITemplateBackup then
		upgradeUI = upgradeUITemplateBackup:Clone()
		upgradeUI.Parent = upgradePart
	end
	if not upgradeUI then
		return nil
	end

	CaptureUpgradeUITemplateBackup(upgradeUI)
	upgradeUI.Adornee = upgradePart
	upgradeUI.Parent = players.LocalPlayer:WaitForChild("PlayerGui")
	upgradePart.Destroying:Connect(function()
		DestroyUpgradeUIsForPart(upgradePart)
	end)
	return upgradeUI
end

-- Handles model placement for a single plot
local function UpdatePlot(folder: Instance, placedData: any?, isLocalPlayer: boolean, slotName: string)
	local modelContainer = folder:FindFirstChild("Model") or folder:FindFirstChild("RootPart")
	local pedestal = folder:FindFirstChild("Booth")

	-- 1. Placeholder Content Visibility (Hide everything in Model/RootPart containers)
	if modelContainer then
		for _, desc in ipairs(modelContainer:GetDescendants()) do
			SetVisuals(desc, false, true)
			if desc:IsA("BasePart") then
				desc.Anchored = true
			end
		end
		if modelContainer:IsA("BasePart") then
			SetVisuals(modelContainer, false, true)
			modelContainer.Anchored = true
		end
	end

	-- 2. Pedestal Visibility (Always Show)
	if pedestal then
		for _, desc in ipairs(pedestal:GetDescendants()) do
			SetVisuals(desc, true, false)
		end
		if pedestal:IsA("BasePart") then
			SetVisuals(pedestal, true, false)
		end
	end

	-- 3. UI Elements (InfoUI & CollectUI)
	local infoUI = folder:FindFirstChild("InfoUI") :: BillboardGui?
	if infoUI and infoUI:GetAttribute(PLACE_MODEL_INFO_UI_BASE_STUDS_OFFSET_Y_ATTR) == nil then
		infoUI:SetAttribute(PLACE_MODEL_INFO_UI_BASE_STUDS_OFFSET_Y_ATTR, infoUI.StudsOffset.Y)
	end
	local collectPart = pedestal and pedestal:FindFirstChild("CollectPart") :: BasePart?
	if collectPart then
		collectPart.Transparency = 1
		collectPart.CanQuery = false
	end
	local collectUI = collectPart and collectPart:FindFirstChild("CollectUI") :: SurfaceGui?

	-- 交互按钮附件 (Place, Sell, Upgrade)
	local rootPart = folder:FindFirstChild("RootPart") :: BasePart?
	local placeAttachment = rootPart and rootPart:FindFirstChild("PlaceAttachment") :: Attachment?
	local sellAttachment = rootPart and rootPart:FindFirstChild("SellAttachment") :: Attachment?
	local lightAttachment = rootPart and rootPart:FindFirstChild("LightAttachment") :: Attachment?
	local lightEffectAttachment = rootPart and rootPart:FindFirstChild("LightEffectAttachment") :: Attachment?
	local lightEmitter = lightAttachment and lightAttachment:FindFirstChildOfClass("ParticleEmitter")
	local lightEffectEmitter = lightEffectAttachment and lightEffectAttachment:FindFirstChildOfClass("ParticleEmitter")

	local upgradePart = pedestal and pedestal:FindFirstChild("UpgradePart") :: BasePart?
	if upgradePart then
		upgradePart.Transparency = 1
		upgradePart.CanCollide = false
	end

	local isOccupied = placedData ~= nil
	local upgradeUI: SurfaceGui? = nil
	if upgradePart then
		if isOccupied and isLocalPlayer then
			upgradeUI = EnsureMovedUpgradeUI(upgradePart)
		else
			DestroyUpgradeUIsForPart(upgradePart)
		end
	end

	local pointIndex = tonumber(folder.Name:match("^PlaceModel(%d+)$"))

	-- 只要 BillboardGui 存在就追踪自适应 (即使当前不显示，Enabled 会在 UpdateUIScales 检查)
	if infoUI then
		SetupBillboardAdaptation(infoUI)
	end

	-- 4. Set prompt/UI visibility based on occupancy
	-- Empty booth: hide specific mesh (Workspace.*.Booth.BoothModel.group2_polySurface6.xian)
	if pedestal and pedestal.Parent then
		local boothModel = pedestal:FindFirstChild("BoothModel")
		local group2 = boothModel and boothModel:FindFirstChild("group2_polySurface6")
		local xian = group2 and group2:FindFirstChild("xian")
		if xian then
			if xian:IsA("Model") then
				for _, desc in ipairs(xian:GetDescendants()) do
					SetVisuals(desc, isOccupied, false)
				end
			else
				SetVisuals(xian, isOccupied, false)
			end
		else
			-- Fallback: if hierarchy differs, search by name within Booth.
			for _, desc in ipairs(pedestal:GetDescendants()) do
				if desc.Name == "xian" then
					SetVisuals(desc, isOccupied, false)
				end
			end
		end
	end

	local showPlacePrompt = (not isOccupied and isLocalPlayer and isLocalHoldingBrainrot) or (isOccupied and isLocalPlayer)
	local deferPromptEnabled = isLocalPlayer
	if pointIndex then
		SetPromptState(placeAttachment, showPlacePrompt, isOccupied, pointIndex, slotName, not deferPromptEnabled, isLocalHoldingBrainrot)
		SetSellButtonVisibility(sellAttachment, isOccupied and isLocalPlayer, pointIndex, slotName, not deferPromptEnabled)
	end

	local lightColor: Color3? = nil
	if isOccupied and placedData then
		local brainrotData = GameConfig.BrainrotIdMap[placedData.configId]
		if brainrotData then
			local levelIdx = placedData.level or 1
			local qualityCfg = GameConfig.BrainrotQualityConfig[brainrotData.quality]
			if qualityCfg then
				lightColor = qualityCfg.textColor
			end

			local sellPrompt = sellAttachment and sellAttachment:FindFirstChildOfClass("ProximityPrompt")
			if sellPrompt then
				local sellPrice = GameConfig.GetBrainrotSellPrice(brainrotData.baseAbility, levelIdx)
				local priceStr = NumberExtension.FormatBigNumberAA(sellPrice)
				TranslationTool.CustomAutoLocalizeProximityPrompt(sellPrompt, GameTexts.SellWithPrice.source, GameTexts.SellWithPrice.key, { priceStr })
			end
		end
	end
	UpdatePlaceModelLightEmitters(lightEmitter, lightEffectEmitter, lightColor ~= nil, lightColor)

	-- 5. Collection Touch Detection (Client-Side)
	if collectPart and not collectPart:GetAttribute("TouchBound") then
		collectPart:SetAttribute("TouchBound", true)
		collectPart.Touched:Connect(function(hit)
			if hit.Parent and hit.Parent == players.LocalPlayer.Character then
				local slotName: string? = nil
				-- Find which slot this collectPart belongs to
				local cur: Instance? = folder
				while cur and cur ~= workspace do
					if cur.Name:match("^Player%d+$") then
						slotName = cur.Name
						break
					end
					cur = cur.Parent
				end

				if slotName then
					local state = slotStateCache[slotName]
					if state and state.homeInfo then
						if not state.isLocalPlayer then
							return
						end
						local pIdx = tonumber(folder.Name:match("^PlaceModel(%d+)$"))
						local targetId = 0
						-- Find owner ID
						if state.isLocalPlayer then
							targetId = players.LocalPlayer.UserId
						else
							for _, p in ipairs(players:GetPlayers()) do
								local info = ClientGameInfo.GetOtherPlayerInfo(p.UserId)
								if info and info.homeSlot == slotName then
									targetId = p.UserId
									break
								end
							end
						end

						if pIdx and targetId ~= 0 then
							local pointIndexStr = tostring(pIdx)
							local claimKey = tostring(targetId) .. ":" .. pointIndexStr
							local nowClock = os.clock()
							local lastClaimClock = lastClaimRequestClockByKey[claimKey] or 0
							if nowClock - lastClaimClock < CLAIM_REQUEST_COOLDOWN_SEC then
								return
							end

							local modelInfo = state.homeInfo.placedModels[pointIndexStr]
							local rebirthForYield = if state.rebirthLevel ~= nil then state.rebirthLevel else 0
							local estimatedYield = if modelInfo ~= nil
								then getExtrapolatedUnclaimedDisplay(targetId, pointIndexStr, modelInfo, rebirthForYield)
								else 0
							if modelInfo == nil or estimatedYield <= 0 then
								return
							end
							lastClaimRequestClockByKey[claimKey] = nowClock
							if targetId == players.LocalPlayer.UserId and modelInfo ~= nil and estimatedYield > 0 then
								NetMsg.FireRequestCompleteGuideStep(GameConfig.GuideStepKey.BrainrotCollectFinished)
							end
							if targetId == players.LocalPlayer.UserId and modelInfo ~= nil then
								local modelInfoAny = modelInfo :: any
								DebugCollectYieldLog("ClaimTouchLocalClear", targetId, pointIndexStr, {
									beforeBase = modelInfoAny.unclaimedYield or 0,
									estimatedYield = estimatedYield,
								})
								modelInfoAny.unclaimedYield = 0
								resetYieldAnchor(targetId, pointIndexStr)
							end
							NetMsg.FireRequestClaimYield(targetId, pIdx)
						end
					end
				end
			end
		end)
	end

	if placedData and infoUI then
		infoUI.Enabled = true
		local controller = infoUI:FindFirstChild("ControllerFrame")
		local brainrotData = GameConfig.BrainrotIdMap[placedData.configId]
		if controller and brainrotData then
			local nameLabel = controller:FindFirstChild("NameLabel") :: TextLabel?
			local qualityLabel = controller:FindFirstChild("QualityLabel") :: TextLabel?
			local abilityText = controller:FindFirstChild("AbilityText") :: TextLabel?
			local lvLabel = controller:FindFirstChild("LvLabel") :: TextLabel?

			local qualityCfg = GameConfig.BrainrotQualityConfig[brainrotData.quality]
			if nameLabel then
				nameLabel.Text = brainrotData.name_t or ""
				-- NameLabel 颜色固定为白色，不随品质变化
				nameLabel.TextColor3 = Color3.new(1, 1, 1)
			end
			if qualityLabel then
				LocalizeQualityLabel(qualityLabel, brainrotData.quality)
				if qualityCfg then
					qualityLabel.TextColor3 = qualityCfg.textColor
				end
			end
			if lvLabel then
				local lvStr = tostring(placedData.level or 1)
				TranslationTool.CustomAutoLocalizeTextLabel(lvLabel, GameTexts.LevelWithNumber.source, GameTexts.LevelWithNumber.key, { lvStr })
				lvLabel.TextColor3 = GameConfig.GetBrainrotLevelTierTextColor(placedData.level or 1)
			end

			-- 收益与售价逻辑 (根据等级索引列表)
			local levelIdx = placedData.level or 1
			if abilityText then
				local abilityStr = NumberExtension.FormatBigNumberAA(
					GameConfig.GetBrainrotAbilityWithVariant(brainrotData.baseAbility, levelIdx, placedData.variantId)
				)
				TranslationTool.CustomAutoLocalizeTextLabel(abilityText, GameTexts.YieldPerSecond.source, GameTexts.YieldPerSecond.key, { abilityStr })
			end
			BrainrotVariantVisualTool.ApplyVariantLabel(controller, placedData.variantId)
		end
	elseif infoUI then
		infoUI.Enabled = false
	end

	if collectUI then
		collectUI.Enabled = true -- 始终显示
		local controller = collectUI:FindFirstChild("ControllerFrame")
		local collectText = controller and controller:FindFirstChild("CollectText") :: TextLabel?
		local coinImg = controller and controller:FindFirstChild("CoinImg") :: GuiObject?
		if collectText then
			collectText.Visible = isOccupied
			if isOccupied and placedData and pointIndex then
				local state = slotStateCache[slotName]
				local ownerUserId: number? = if state and state.ownerUserId ~= nil
					then state.ownerUserId
					elseif isLocalPlayer then players.LocalPlayer.UserId
					else nil
				local rebirthForYield = if state and state.rebirthLevel ~= nil then state.rebirthLevel else 0
				local pointIndexStr = tostring(pointIndex)
				local displayAmount = if ownerUserId ~= nil
					then getExtrapolatedUnclaimedDisplay(ownerUserId, pointIndexStr, placedData, rebirthForYield)
					else ((placedData :: any).unclaimedYield or 0)
				local yieldStr = NumberExtension.FormatBigNumberAA(displayAmount)
				setCollectYieldText(collectText, yieldStr, "UpdatePlot", ownerUserId, pointIndexStr, displayAmount)
			end
		end
		if coinImg then
			coinImg.Visible = isOccupied
		end
	end

	if upgradeUI then
		upgradeUI.Enabled = isOccupied and isLocalPlayer
		if upgradeUI.Enabled and placedData then
			local clickBtn = upgradeUI:FindFirstChild("ClickButton", true) :: ImageButton?
			if clickBtn then
				local clvLabel = clickBtn:FindFirstChild("LvLabel", true) :: TextLabel?
				local costText = clickBtn:FindFirstChild("CostText", true) :: TextLabel?

				local brainrotData = GameConfig.BrainrotIdMap[placedData.configId]
				if brainrotData then
					local currentLevel = placedData.level or 1
					local canUp = true -- Brainrot levels are infinite

					if clvLabel then
						if canUp then
							local curLvStr = tostring(currentLevel)
							local nextLvStr = tostring(currentLevel + 1)
							TranslationTool.CustomAutoLocalizeTextLabel(
								clvLabel,
								GameTexts.UpgradeLevelFormat.source,
								GameTexts.UpgradeLevelFormat.key,
								{ curLvStr, nextLvStr }
							)
						else
							TranslationTool.CustomAutoLocalizeTextLabel(clvLabel, GameTexts.MaxLevel.source, GameTexts.MaxLevel.key)
						end
					end

					if costText then
						if canUp then
							local upgradePrice = GameConfig.GetBrainrotUpgradeCost(brainrotData.baseAbility, currentLevel)
							costText.Text = NumberExtension.FormatBigNumberAA(upgradePrice)
							costText.Visible = true
						else
							costText.Visible = false
						end
					end

					if clickBtn and not clickBtn:GetAttribute("ClickBound") then
						clickBtn:SetAttribute("ClickBound", true)
						clickBtn:SetAttribute("SkipButtonClickSound", true)

						UIManager.ApplySurfaceButtonEffects(clickBtn)

						clickBtn.Activated:Connect(function()
							local slotName: string? = nil
							local cur: Instance? = folder
							while cur and cur ~= workspace do
								if cur.Name:match("^Player%d+$") then
									slotName = cur.Name
									break
								end
								cur = cur.Parent
							end

							if slotName then
								local state = slotStateCache[slotName]
								if state and state.homeInfo and state.isLocalPlayer then
									local pIdx = tonumber(folder.Name:match("^PlaceModel(%d+)$"))
									if pIdx then
										local pData = state.homeInfo.placedModels[tostring(pIdx)]
										if pData then
											local pBrainrotData = GameConfig.BrainrotIdMap[pData.configId]
											if pBrainrotData then
												local upCost = GameConfig.GetBrainrotUpgradeCost(pBrainrotData.baseAbility, pData.level)
												local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
												local currentGold = playerInfo and playerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
												if currentGold < upCost then
														-- 金币不足：走付费升 3 级路径（防抖避免重复弹出）
														local now = os.clock()
														if now - lastBrainrotPaidPromptAt < BRAINROT_PAID_PROMPT_COOLDOWN then
															return
														end
														lastBrainrotPaidPromptAt = now

														NetMsg.FireRequestUpgradeModel(pIdx, 3, true)
														if players.LocalPlayer then
															marketplaceService:PromptProductPurchase(
																players.LocalPlayer,
																GameConfig.ShopPaid.BrainrotUpgrade3ProductId
															)
														end
													return
												end
												GameSoundManager.PlayUpgradeAbilitySound()
												ApplyLocalBrainrotUpgradePreview(slotName, pIdx, 1)
												NetMsg.FireRequestUpgradeModel(pIdx)
												NetMsg.FireRequestCompleteGuideStep(GameConfig.GuideStepKey.BrainrotUpgradeFinished)
											end
										end
									end
								end
							end
						end)
					end
				end
			end
		end
	end

	-- 4. Visual Model Management
	local visualModel = folder:FindFirstChild("VisualModel")
	if placedData then
		if not visualModel or visualModel:GetAttribute("ConfigId") ~= placedData.configId then
			if visualModel then
				visualModel:Destroy()
			end

			local brainrotData = GameConfig.BrainrotIdMap[placedData.configId]
			local template = if brainrotData and actualModels
				then GameConfig.FindResourceTemplateByResourceName(actualModels, brainrotData.resourceName)
				else nil

			if template and modelContainer then
				local newVisual = GameConfig.CloneTemplateAsModel(template)
				newVisual.Name = "VisualModel"
				newVisual:SetAttribute("ConfigId", placedData.configId)

				local targetCFrame = nil
				local placeholder = modelContainer:FindFirstChild("Model")
				if placeholder and placeholder:IsA("Model") then
					targetCFrame = placeholder:GetPivot()
				elseif placeholder and placeholder:IsA("BasePart") then
					targetCFrame = placeholder.CFrame
				else
					targetCFrame = modelContainer:IsA("BasePart") and (modelContainer.CFrame * CFrame.new(0, modelContainer.Size.Y / 2, 0))
						or (modelContainer :: any):GetPivot()
				end

				if targetCFrame then
					newVisual:PivotTo(targetCFrame)
				end

				-- 新生成的宠物模型需要锚固并取消碰撞
				for _, part in ipairs(newVisual:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Anchored = true
						part.CanCollide = false
					end
				end

				-- Track BrainrotInfoUI in the visual model for scaling
				local brainrotModelRoot = newVisual:FindFirstChild("RootPart") :: BasePart?
				local brainrotUI = brainrotModelRoot and brainrotModelRoot:FindFirstChild("BrainrotInfoUI") :: BillboardGui?
				if brainrotUI then
					SetupBillboardAdaptation(brainrotUI)
				end

				GameConfig.ApplyBrainrotModelScale(
					newVisual,
					placedData.level or 1,
					GameConfig.GetBrainrotTemplateBaseScale(template)
				)
				newVisual.Parent = folder
				local placedVariantId = if placedData.variantId and placedData.variantId > 0 then placedData.variantId else 0
				BrainrotVariantVisualTool.AttachVariantEffect(newVisual, placedVariantId)
				-- Keep local reference in sync so this frame can immediately refresh BrainrotInfoUI.
				visualModel = newVisual
			elseif brainrotData and actualModels then
				warn(
					"[HomeClientManager] Placed brainrot source model not found:",
					brainrotData.resourceName,
					"candidates:",
					table.concat(GameConfig.GetResourceNameCandidates(brainrotData.resourceName), ", ")
				)
			end
		end

		if visualModel and visualModel:IsA("Model") then
			GameConfig.ApplyBrainrotModelScale(visualModel :: Model, placedData.level or 1)
		end

		-- Sync BrainrotInfoUI data
		local brainrotModelRoot = visualModel and visualModel:FindFirstChild("RootPart") :: BasePart?
		local brainrotInfoUI = brainrotModelRoot and brainrotModelRoot:FindFirstChild("BrainrotInfoUI") :: BillboardGui?
		if brainrotInfoUI and placedData then
			local resolvedAdornee = brainrotModelRoot :: BasePart
			brainrotInfoUI.Enabled = true

			local offsetY = if visualModel
				then ModelBillboardOffsetTool.GetVisualOffsetY(
					visualModel :: Model,
					resolvedAdornee,
					GameConfig.HomePlaceModelInfoUIBillboardPadding
				)
				else 2
			brainrotInfoUI.StudsOffset = Vector3.new(0, offsetY, 0)

			local controller = brainrotInfoUI:FindFirstChild("ControllerFrame")
			local brainrotData = GameConfig.BrainrotIdMap[placedData.configId]
			if controller and brainrotData then
				local nameLabel = controller:FindFirstChild("NameLabel") :: TextLabel?
				local qualityLabel = controller:FindFirstChild("QualityLabel") :: TextLabel?
				local abilityText = controller:FindFirstChild("AbilityText") :: TextLabel?
				local lvLabel = controller:FindFirstChild("LvLabel") :: TextLabel?

				local qualityCfg = GameConfig.BrainrotQualityConfig[brainrotData.quality]
				if nameLabel then
					nameLabel.Text = brainrotData.name_t or ""
					-- NameLabel 颜色固定为白色，不随品质变化
					nameLabel.TextColor3 = Color3.new(1, 1, 1)
				end
				if qualityLabel then
					LocalizeQualityLabel(qualityLabel, brainrotData.quality)
					if qualityCfg then
						qualityLabel.TextColor3 = qualityCfg.textColor
					end
				end
				if lvLabel then
					local lvStr = tostring(placedData.level or 1)
					TranslationTool.CustomAutoLocalizeTextLabel(lvLabel, GameTexts.LevelWithNumber.source, GameTexts.LevelWithNumber.key, { lvStr })
					lvLabel.TextColor3 = GameConfig.GetBrainrotLevelTierTextColor(placedData.level or 1)
				end

				local levelIdx = placedData.level or 1
				if abilityText then
					local abilityStr = NumberExtension.FormatBigNumberAA(
						GameConfig.GetBrainrotAbilityWithVariant(brainrotData.baseAbility, levelIdx, placedData.variantId)
					)
					TranslationTool.CustomAutoLocalizeTextLabel(abilityText, GameTexts.YieldPerSecond.source, GameTexts.YieldPerSecond.key, { abilityStr })
				end
				BrainrotVariantVisualTool.ApplyVariantLabel(controller, placedData.variantId)
			end
		end
	else
		if visualModel then
			visualModel:Destroy()
		end
	end

	-- PlaceModel.InfoUI：按 VisualModel 高度调整 StudsOffset.Y，空置或模型缺失时恢复 Studio 基准
	if infoUI then
		local baseStudsY = infoUI:GetAttribute(PLACE_MODEL_INFO_UI_BASE_STUDS_OFFSET_Y_ATTR)
		local defaultY = if typeof(baseStudsY) == "number" then baseStudsY else infoUI.StudsOffset.Y

		local plotVisual = if placedData then folder:FindFirstChild("VisualModel") else nil
		local plotVisualModel = plotVisual and plotVisual:IsA("Model") and (plotVisual :: Model) or nil

		if placedData and plotVisualModel then
			local adornee: BasePart? = if infoUI.Adornee and infoUI.Adornee:IsA("BasePart")
				then infoUI.Adornee :: BasePart
				else rootPart
			if adornee then
				local offsetY = ModelBillboardOffsetTool.GetVisualOffsetY(
					plotVisualModel,
					adornee,
					GameConfig.HomePlaceModelInfoUIBillboardPadding
				)
				infoUI.StudsOffset = Vector3.new(infoUI.StudsOffset.X, offsetY + GameConfig.HomePlaceModelInfoUIBillboardOffsetY, infoUI.StudsOffset.Z)
			else
				infoUI.StudsOffset = Vector3.new(infoUI.StudsOffset.X, defaultY, infoUI.StudsOffset.Z)
			end
		else
			infoUI.StudsOffset = Vector3.new(infoUI.StudsOffset.X, defaultY, infoUI.StudsOffset.Z)
		end
	end

	-- 5. Prompt Visibility Managed via SetButtonVisibility above
end

-- Handles teleport point visuals
local function UpdateTeleportPoint(tpModel: Model, isLocalPlayer: boolean)
	for _, desc in ipairs(tpModel:GetDescendants()) do
		SetVisuals(desc, isLocalPlayer)
		-- if desc:IsA("BasePart") then
		-- 	desc.CanCollide = false
		-- end
	end
end

local function GetHomeOwnerPlayer(slotName: string, isLocalPlayer: boolean): Player?
	if isLocalPlayer then
		return players.LocalPlayer
	end

	for _, player in ipairs(players:GetPlayers()) do
		if player.UserId == players.LocalPlayer.UserId then
			continue
		end

		local otherInfo = ClientGameInfo.GetOtherPlayerInfo(player.UserId)
		if otherInfo and otherInfo.homeSlot == slotName then
			return player
		end
	end

	return nil
end

-- Updates the rebirth multiplier UI for the home
local function UpdateRebirthMultiplierUI(slotName: string, homeInfo: any, isLocalPlayer: boolean, rebirthLevel: number?)
	--print("[UpdateRebirthMultiplierUI] Updating UI for slot", slotName, "isLocalPlayer", isLocalPlayer)
	local slotModel = homesFolder:FindFirstChild(slotName)
	if not slotModel or not homeInfo then
		return
	end

	-- 1. Find parts in PublicModel path
	local publicModel = slotModel:FindFirstChild("PublicModel")
	if not publicModel then
		return
	end

	local rebirthMultiplierPart = publicModel:FindFirstChild("RebirthMultiplierPart") :: BasePart?
	local rebirthInfoUI: BillboardGui? = rebirthMultiplierPart and rebirthMultiplierPart:FindFirstChild("InfoUI") :: BillboardGui?

	-- PlayerInfoPart 上的头像/名称 UI
	local playerInfoPart = publicModel:FindFirstChild("PlayerInfoPart") :: Part?
	local playerInfoUI: BillboardGui? = playerInfoPart and playerInfoPart:FindFirstChild("InfoUI") :: BillboardGui?
	local playerControllerFrame: Frame? = playerInfoUI and playerInfoUI:FindFirstChild("ControllerFrame") :: Frame?
	local playerIconImg: ImageLabel? = playerControllerFrame and playerControllerFrame:FindFirstChild("PlayerIconImg") :: ImageLabel?
	local playerNameLabel: TextLabel? = playerControllerFrame and playerControllerFrame:FindFirstChild("PlayerNameLabel") :: TextLabel?
	local ownerPlayer = GetHomeOwnerPlayer(slotName, isLocalPlayer)
	if not ownerPlayer then
		if playerInfoUI then
			playerInfoUI.Enabled = false
		end
		if rebirthInfoUI then
			rebirthInfoUI.Enabled = false
		end
		return
	end

	if playerInfoUI then
		playerInfoUI.Enabled = true
		playerInfoUI.AlwaysOnTop = false
		playerInfoUI.MaxDistance = 100
	end
	if playerNameLabel then
		playerNameLabel.Text = if ownerPlayer.DisplayName ~= "" then ownerPlayer.DisplayName else ownerPlayer.Name
	end

	if playerIconImg then
		local ok, image = pcall(function()
			return players:GetUserThumbnailAsync(
				ownerPlayer.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)
		end)
		if ok and type(image) == "string" then
			playerIconImg.Image = image
		end
	end

	if not rebirthInfoUI then
		return
	end

	-- RebirthMultiplierPart 上的倍率/收益 UI
	rebirthInfoUI.Enabled = true
	rebirthInfoUI.AlwaysOnTop = false
	rebirthInfoUI.MaxDistance = 100
	local controllerFrame: Frame? = rebirthInfoUI:FindFirstChild("ControllerFrame") :: Frame?
	if not controllerFrame then
		return
	end

	-- 确保 UI 追踪自适应
	SetupBillboardAdaptation(rebirthInfoUI)
	if playerInfoUI then
		SetupBillboardAdaptation(playerInfoUI)
	end

	local rebirthInfoLabel: TextLabel? = controllerFrame:FindFirstChild("RebirthInfoLabel") :: TextLabel?
	local totalRevenueLabel: TextLabel? = controllerFrame:FindFirstChild("TotalRevenueLabel") :: TextLabel?

	if not rebirthInfoLabel or not totalRevenueLabel then
		return
	end

	-- 2. Calculate Rebirth Multiplier
	local finalRebirthLevel: number = rebirthLevel or 0

	-- 如果没有传入 rebirthLevel 且不是本地玩家，尝试再次查找一次（作为兜底）
	if not rebirthLevel and not isLocalPlayer then
		for _, p in ipairs(players:GetPlayers()) do
			local info = ClientGameInfo.GetOtherPlayerInfo(p.UserId)
			if info and info.homeSlot == slotName then
				finalRebirthLevel = info.rebirthLevel or 0
				break
			end
		end
	elseif not rebirthLevel and isLocalPlayer then
		local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
		if playerInfo then
			finalRebirthLevel = playerInfo.shopInfo.rebirthLevel or 0
		end
	end

	-- 关键：只要 slotStateCache 标记为 active，我们就显示，如果没有 playerInfo 默认为 1 级
	-- 这里不再 return，确保 UI 基础状态始终正确

	-- Rebirth Info Label
	local levelStr = tostring(finalRebirthLevel)
	local multiplier = 1
	if finalRebirthLevel > 0 then
		local rbConfig = GameConfig.RebirthMap[finalRebirthLevel]
		multiplier = if rbConfig then rbConfig.collectMultiple else 1
	end
	local multiplierStr = string.format("%.1f", multiplier)
	TranslationTool.CustomAutoLocalizeTextLabel(
		rebirthInfoLabel,
		GameTexts.RebirthMultiplierFormat.source,
		GameTexts.RebirthMultiplierFormat.key,
		{ levelStr, multiplierStr }
	)

	-- 3. Calculate Total Revenue (Base Yield * Multiplier)
	local totalBaseRevenue = 0
	for _, model in pairs(homeInfo.placedModels) do
		local brainrotData = GameConfig.BrainrotIdMap[model.configId]
		if brainrotData then
			totalBaseRevenue += GameConfig.GetBrainrotAbilityWithVariant(brainrotData.baseAbility, model.level, model.variantId)
		end
	end
	local totalFinalRevenue = math.ceil(totalBaseRevenue * multiplier)

	-- 4. Update UI
	rebirthInfoUI.Enabled = true

	-- Total Revenue Label
	local revenueStr = NumberExtension.FormatBigNumberAA(totalFinalRevenue)
	TranslationTool.CustomAutoLocalizeTextLabel(totalRevenueLabel, GameTexts.TotalRevenueFormat.source, GameTexts.TotalRevenueFormat.key, { revenueStr })
end

local function SetFloorMovedUpgradeUIsEnabled(floorModel: Model, enabled: boolean)
	local playerGui = players.LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end
	for _, plot in ipairs(floorModel:GetChildren()) do
		if not plot.Name:match("^PlaceModel%d+$") then
			continue
		end
		local booth = plot:FindFirstChild("Booth")
		local upgradePart = booth and booth:FindFirstChild("UpgradePart")
		if not upgradePart then
			continue
		end
		for _, gui in ipairs(playerGui:GetChildren()) do
			if gui:IsA("SurfaceGui") and gui.Name == "UpgradeUI" and gui.Adornee == upgradePart then
				gui.Enabled = enabled
			end
		end
	end
end

-- Completely hides a slot (when empty)
function ClearHomeVisuals(slotName: string)
	local slotModel = homesFolder:FindFirstChild(slotName)
	if not slotModel then
		return
	end
	localSlotInteractionResetLevelBySlot[slotName] = nil

	-- Hide PublicModel UIs
	local publicModel = slotModel:FindFirstChild("PublicModel")
	local rebirthMultiplierPart = publicModel and publicModel:FindFirstChild("RebirthMultiplierPart")
	local rebirthInfoUI = rebirthMultiplierPart and rebirthMultiplierPart:FindFirstChild("InfoUI") :: BillboardGui?
	if rebirthInfoUI then
		rebirthInfoUI.Enabled = false
	end
	local playerInfoPart = publicModel and publicModel:FindFirstChild("PlayerInfoPart")
	local playerInfoUI = playerInfoPart and playerInfoPart:FindFirstChild("InfoUI") :: BillboardGui?
	if playerInfoUI then
		playerInfoUI.Enabled = false
	end

	for _, child in ipairs(GetFloorModels(slotModel)) do
		local lvNum = GetFloorNumber(child)
		if lvNum then
			if lvNum == 1 then
				-- Lv1: Show structural parts, but clear plots
				for _, sub in ipairs(child:GetChildren()) do
					if sub.Name:match("^PlaceModel%d+$") then
						UpdatePlot(sub, nil, false, slotName)
					else
						-- Structural
						for _, desc in ipairs(sub:GetDescendants()) do
							if desc.Name == "StairsPart" then
								SetVisuals(desc, false)
							else
								SetVisuals(desc, true)
							end
						end
						if sub:IsA("BasePart") then
							if sub.Name == "StairsPart" then
								SetVisuals(sub, false)
							else
								SetVisuals(sub, true)
							end
						end
					end
				end
			else
				-- Higher levels: Hide completely
				for _, desc in ipairs(child:GetDescendants()) do
					SetVisuals(desc, false)
				end
				SetFloorMovedUpgradeUIsEnabled(child, false)
			end
		end
	end
	local teleportPoint = slotModel:FindFirstChild("TeleportPoint")
	if teleportPoint then
		UpdateTeleportPoint(teleportPoint :: Model, false) -- 隐藏传送点 (针对空房)
	end
	-- Clear clones
	if floorModelsCache[slotName] then
		for _, model in pairs(floorModelsCache[slotName]) do
			model:Destroy()
		end
		floorModelsCache[slotName] = nil
	end

	-- Hide UpgradeHome for empty slots
	local upgradeHomeModel = slotModel:FindFirstChild("UpgradeHome") :: Model?
	if upgradeHomeModel then
		for _, desc in ipairs(upgradeHomeModel:GetDescendants()) do
			if IsUpgradeHomePartInfoUI(desc) then
				(desc :: BillboardGui).Enabled = false
				continue
			end
			SetVisuals(desc, false, false)
		end
		--if upgradeHomeModel:IsA("BasePart") then
		--	SetVisuals(upgradeHomeModel, false, false)
		--end
	end
end

-- Updates the visuals for a single player's home slot
function UpdateHomeVisuals(slotName: string, homeInfo: any, isLocalPlayer: boolean)
	local slotModel = homesFolder:FindFirstChild(slotName)
	if not slotModel then
		return
	end

	local lv1 = slotModel:FindFirstChild("Lv1")
	if not lv1 or not lv1:IsA("Model") then
		return
	end

	-- Capture one UpgradeUI template before any later floor clone uses it.
	if not upgradeUITemplateBackup then
		for _, place in ipairs(lv1:GetChildren()) do
			if place.Name:match("^PlaceModel%d+$") then
				local booth = place:FindFirstChild("Booth")
				local upgradePart = booth and booth:FindFirstChild("UpgradePart")
				local templateUI = upgradePart and upgradePart:FindFirstChild("UpgradeUI")
				if templateUI and templateUI:IsA("SurfaceGui") then
					CaptureUpgradeUITemplateBackup(templateUI)
					break
				end
			end
		end
	end

	-- 1. Manage floor clones in cache
	local clones = floorModelsCache[slotName]
	if not clones then
		clones = {}
		floorModelsCache[slotName] = clones
	end

	local plotsPerFloor = GetPlotsPerFloor(slotModel)

	-- Add/Remove clones to match target level
	for i = 2, MAX_FLOOR_COUNT do
		if i <= homeInfo.level then
			local existingFloor = FindFloorModel(slotModel, i)
			if existingFloor then
				NormalizeFloorPlaceModels(existingFloor, i, plotsPerFloor)
			elseif not clones[i] then
				local templateFloor, templateFloorNumber = GetHigherFloorCloneTemplate(slotModel, lv1)
				local cloned = templateFloor:Clone()
				cloned.Name = "Lv" .. i
				cloned:SetAttribute(FLOOR_PLACE_MODELS_NORMALIZED_PLOTS_ATTR, nil)
				cloned:SetAttribute(FLOOR_COLLECT_TOUCH_RESET_ATTR, nil)
				local offset = Vector3.new(0, (i - templateFloorNumber) * FLOOR_HEIGHT, 0)
				cloned:PivotTo(templateFloor:GetPivot() * CFrame.new(offset))
				cloned.Parent = slotModel
				clones[i] = cloned
				NormalizeFloorPlaceModels(cloned, i, plotsPerFloor)
			end

			local floorModel = FindFloorModel(slotModel, i)
			if floorModel then
				for _, child in ipairs(floorModel:GetChildren()) do
					if upgradeUITemplateBackup then
						local booth = child:FindFirstChild("Booth")
						local clonedUpgradePart = booth and booth:FindFirstChild("UpgradePart")
						local clonedUpgradeUI = clonedUpgradePart and clonedUpgradePart:FindFirstChild("UpgradeUI")
						local movedUpgradeUI = if clonedUpgradePart and clonedUpgradePart:IsA("BasePart")
							then FindMovedUpgradeUI(clonedUpgradePart :: BasePart)
							else nil
						if clonedUpgradePart and not clonedUpgradeUI and not movedUpgradeUI then
							local backupUI = upgradeUITemplateBackup:Clone()
							backupUI.Parent = clonedUpgradePart
						end
					end
				end
				ResetFloorCollectTouchBindingsOnce(floorModel)
			end
		else
			if clones[i] then
				clones[i]:Destroy()
				clones[i] = nil
			end
		end
	end

	local didResetLocalInteractions = false
	if isLocalPlayer and ShouldResetLocalSlotInteractionVisibility(slotName, homeInfo) then
		ResetLocalSlotAllPlotInteractionVisibility(slotModel)
		didResetLocalInteractions = true
	end

	-- 2. Update all floors (Lv1 and Clones)
	for _, child in ipairs(GetFloorModels(slotModel)) do
		local lvNum = GetFloorNumber(child)
		if lvNum then
			if lvNum <= homeInfo.level then
				-- Show & Update
				for _, sub in ipairs(child:GetChildren()) do
					if sub.Name:match("^PlaceModel%d+$") then
						local pointIndex = tonumber(sub.Name:match("^PlaceModel(%d+)$"))
						if pointIndex then
							UpdatePlot(sub, homeInfo.placedModels[tostring(pointIndex)], isLocalPlayer, slotName)
						end
					else
						-- Structural visibility
						local homeModel = FindStructuralHomeModel(sub)
						if homeModel then
							local ground = homeModel:FindFirstChild("ground")
							local stairs = homeModel:FindFirstChild("StairsPart")
							for _, desc in ipairs(sub:GetDescendants()) do
								if ground and (desc:IsAncestorOf(ground) or desc == ground) then
									SetVisuals(desc, lvNum == 1)
								elseif stairs and (desc:IsAncestorOf(stairs) or desc == stairs) then
									SetVisuals(desc, lvNum < homeInfo.level)
								else
									SetVisuals(desc, true)
								end
							end
						else
							for _, desc in ipairs(sub:GetDescendants()) do
								SetVisuals(desc, true)
							end
						end
						if sub:IsA("BasePart") then
							SetVisuals(sub, true)
						end
					end
				end
			else
				-- Hide (shouldn't happen for clones as they are destroyed above, but for static LvX)
				for _, desc in ipairs(child:GetDescendants()) do
					SetVisuals(desc, false)
				end
				SetFloorMovedUpgradeUIsEnabled(child, false)
			end
		end
	end
	local teleportPoint = slotModel:FindFirstChild("TeleportPoint")
	if teleportPoint then
		UpdateTeleportPoint(teleportPoint :: Model, isLocalPlayer)
	end

	-- 3. Update UpgradeHome
	local upgradeHomeModel = slotModel:FindFirstChild("UpgradeHome") :: Model?
	if upgradeHomeModel then
		for _, desc in ipairs(upgradeHomeModel:GetDescendants()) do
			if IsUpgradeHomePartInfoUI(desc) then
				if not isLocalPlayer then
					(desc :: BillboardGui).Enabled = false
				end
				continue
			end
			SetVisuals(desc, isLocalPlayer, false)
		end

		-- HomePart 仅作为定位锚点，任何情况下都隐藏
		local homePart = upgradeHomeModel:FindFirstChild("HomePart") :: BasePart?
		if homePart then
			homePart.Transparency = 1
			homePart.CanCollide = false
			homePart.CanQuery = false
			homePart.CanTouch = false

			-- HomePart.InfoUI 使用固定屏幕大小（通过 BillboardManager 自适应）
			local infoUI = homePart:FindFirstChild("InfoUI") :: BillboardGui?
			if infoUI then
				SetupBillboardAdaptation(infoUI)
			end
		end

		local upgradePart = upgradeHomeModel:FindFirstChild("UpgradeHome") :: BasePart?
		if upgradePart then
			local upgradeUI: SurfaceGui? = upgradePart:FindFirstChild("UpgradeUI") :: SurfaceGui?
			if upgradeUI then
				upgradeUI.Adornee = upgradePart
				upgradeUI.Parent = players.LocalPlayer:WaitForChild("PlayerGui")
				upgradePart.Destroying:Connect(function()
					if upgradeUI then
						upgradeUI:Destroy()
					end
				end)
			else
				-- 重试从 PlayerGui 获取
				for _, gui in ipairs(players.LocalPlayer:WaitForChild("PlayerGui"):GetChildren()) do
					if gui:IsA("SurfaceGui") and gui.Name == "UpgradeUI" and gui.Adornee == upgradePart then
						upgradeUI = gui
						break
					end
				end
			end

			if upgradeUI then
				upgradeUI.Enabled = isLocalPlayer
				if upgradeUI.Enabled then
					local controllerFrame = upgradeUI:FindFirstChild("ControllerFrame") :: Frame?
					local clickBtn = controllerFrame and controllerFrame:FindFirstChild("ClickButton") :: ImageButton?
					if clickBtn then
						local clvLabel = clickBtn:FindFirstChild("LvLabel") :: TextLabel?
						local costText = clickBtn:FindFirstChild("CostText") :: TextLabel?

						local skillData = GameConfig.Shop and GameConfig.Shop.HomeLevel
						if skillData then
							local currentLevel = homeInfo.level or 1
							local canUp = currentLevel < skillData.maxLevel

							if clvLabel then
								if canUp then
									local curLvStr = tostring(currentLevel)
									local nextLvStr = tostring(currentLevel + 1)
									TranslationTool.CustomAutoLocalizeTextLabel(
										clvLabel,
										GameTexts.UpgradeLevelFormat.source,
										GameTexts.UpgradeLevelFormat.key,
										{ curLvStr, nextLvStr }
									)
								else
									TranslationTool.CustomAutoLocalizeTextLabel(clvLabel, GameTexts.MaxLevel.source, GameTexts.MaxLevel.key)
								end
							end

							if costText then
								if canUp then
									local upgradePrice = skillData.upgradeCostList[currentLevel]
									costText.Text = NumberExtension.FormatBigNumberAA(upgradePrice)
									costText.Visible = true
								else
									costText.Visible = false
								end
							end

							if not clickBtn:GetAttribute("ClickBound") then
								clickBtn:SetAttribute("ClickBound", true)
								clickBtn:SetAttribute("SkipButtonClickSound", true)
								UIManager.ApplySurfaceButtonEffects(clickBtn)

								clickBtn.Activated:Connect(function()
									local state = slotStateCache[slotName]
									if state and state.homeInfo and state.isLocalPlayer then
										local sData = GameConfig.Shop.HomeLevel
										if sData then
											local cLevel = state.homeInfo.level or 1
											if cLevel < sData.maxLevel then
												local upCost = sData.upgradeCostList[cLevel]
												local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
												local currentGold = playerInfo and playerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
												if currentGold < upCost then
													ClientMsg.FireShowGameTip(
														GameTexts.InsufficientCoin.source,
														GameConfig.GameTipTweenType.FlyUp,
														GameTexts.InsufficientCoin.key
													)
													return
												end
												GameSoundManager.PlayUpgradeHomeSound()
												NetMsg.SendRequestUpgradeSkill(GameConfig.SkillType.HomeLevel)
											end
										end
									end
								end)
							end
						end
					end
				end
			end
		end
	end

	-- 4. Update RebirthMultiplier UI
	local state = slotStateCache[slotName]
	--print("[UpdateRebirthMultiplierUI] Updating UI for slot", slotName, "isLocalPlayer", isLocalPlayer, "rebirthLevel", state and state.rebirthLevel)
	UpdateRebirthMultiplierUI(slotName, homeInfo, isLocalPlayer, state and state.rebirthLevel)
	if isLocalPlayer then
		local skipFocusRefresh = skipNextLocalInteractionFocusRefreshBySlot[slotName] == true
		if skipFocusRefresh then
			skipNextLocalInteractionFocusRefreshBySlot[slotName] = nil
		end
		if didResetLocalInteractions or not skipFocusRefresh then
			RefreshLocalHomeInteractionFocus(true)
		end
	end
end

-- Refresh all online players' homes (syncs state)
local function RefreshAllHomes()
	local previousLocalSlotName: string? = nil
	local previousLocalState: { active: boolean, homeInfo: any?, isLocalPlayer: boolean?, rebirthLevel: number? }? = nil
	for slotName, state in pairs(slotStateCache) do
		if state and state.isLocalPlayer then
			previousLocalSlotName = slotName
			previousLocalState = state
			break
		end
	end

	-- Pre-fill all with inactive
	for _, child in ipairs(homesFolder:GetChildren()) do
		if child.Name:match("^Player%d+$") then
			slotStateCache[child.Name] = { active = false }
		end
	end

	local localInfo: any = ClientGameInfo.GetLocalPlayerInfo()
	if localInfo and localInfo.homeSlot and localInfo.homeSlot ~= "" and localInfo.homeInfo then
		slotStateCache[localInfo.homeSlot] = {
			active = true,
			homeInfo = localInfo.homeInfo,
			isLocalPlayer = true,
			rebirthLevel = if localInfo.shopInfo then localInfo.shopInfo.rebirthLevel else 0,
			ownerUserId = players.LocalPlayer.UserId,
		}
		localSlotRecoveryAttemptCount = 0
	elseif previousLocalSlotName and previousLocalState and previousLocalState.active then
		slotStateCache[previousLocalSlotName] = {
			active = true,
			homeInfo = previousLocalState.homeInfo,
			isLocalPlayer = true,
			rebirthLevel = previousLocalState.rebirthLevel or 0,
			ownerUserId = players.LocalPlayer.UserId,
		}
		ScheduleLocalSlotRecovery(true)
	else
		ScheduleLocalSlotRecovery(true)
	end

	for _, player in ipairs(players:GetPlayers()) do
		if player.UserId == players.LocalPlayer.UserId then
			continue
		end
		local otherInfo = ClientGameInfo.GetOtherPlayerInfo(player.UserId)
		if otherInfo and otherInfo.homeSlot and otherInfo.homeSlot ~= "" then
			slotStateCache[otherInfo.homeSlot] = {
				active = true,
				homeInfo = otherInfo.homeInfo,
				isLocalPlayer = false,
				rebirthLevel = otherInfo.rebirthLevel or 0,
				ownerUserId = player.UserId,
			}
		end
	end

	-- Apply updates
	for slotName, state in pairs(slotStateCache) do
		ApplySlotVisuals(slotName)
	end
end

local function OnPromptTriggered(prompt: ProximityPrompt, player: Player)
	if player ~= players.LocalPlayer then
		return
	end

	local parent = prompt.Parent
	if not parent then
		return
	end

	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not playerInfo then
		return
	end

	-- 岛屿拾取：岛面实体上由服务端生成 InteractionAttachment.ProximityPrompt（工厂可无岛）
	-- 这里统一监听 ProximityPromptService.PromptTriggered，确保岛屿拾取也有拾取/放下音效
	if parent.Name == "InteractionAttachment" then
		local holder = parent.Parent
		if holder and holder:IsA("BasePart") and (holder.Name == "IslandBrainrot" or holder.Name == "IslandChest") then
			GameSoundManager.PlayPickUpOrPutDownSound()
		end
	end

	if parent.Name == "PlaceAttachment" then
		local data = promptToPlotMap[prompt]
		if not data then
			return
		end

		local slotName = data.slotName
		local pointIndex = data.pointIndex

		if slotName ~= playerInfo.homeSlot then
			warn("[HomeClientManager] Unauthorized interaction: not owner of slot", slotName)
			return
		end

		local state = slotStateCache[slotName]
		local isOccupied = state and state.homeInfo and state.homeInfo.placedModels[tostring(pointIndex)] ~= nil

		if isOccupied then
			--print("[HomeClientManager] Firing pickup home model request for plot", pointIndex)
			GameSoundManager.PlayPickUpOrPutDownSound()
			NetMsg.FireRequestPickupHomeModel(pointIndex)
		else
			--print("[HomeClientManager] Firing place carrying brainrot request for plot", pointIndex)
			GameSoundManager.PlayPickUpOrPutDownSound()
			NetMsg.FireRequestPlaceCarryingBrainrot(pointIndex)
		end
	elseif parent.Name == "UpgradeAttachment" or parent.Name == "SellAttachment" then
		local data = promptToPlotMap[prompt]
		if not data then
			return
		end

		local slotName = data.slotName
		local pointIndex = data.pointIndex

		-- 1. 检核归属权 (使用注册的信息)
		if slotName ~= playerInfo.homeSlot then
			warn("[HomeClientManager] Unauthorized interaction: not owner of slot", slotName)
			return
		end

		if parent.Name == "UpgradeAttachment" then
			-- 2. 升级检核：金币与等级
			local modelData = playerInfo.homeInfo.placedModels[tostring(pointIndex)]
			if not modelData then
				return
			end

			local brainrotData = GameConfig.BrainrotIdMap[modelData.configId]
			if not brainrotData then
				return
			end

			local cost = GameConfig.GetBrainrotUpgradeCost(brainrotData.baseAbility, modelData.level)
			local currentGold = playerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
			if currentGold < cost then
				-- 金币不足：走付费升 3 级路径（防抖避免重复弹出）
				local now = os.clock()
				if now - lastBrainrotPaidPromptAt < BRAINROT_PAID_PROMPT_COOLDOWN then
					return
				end
				lastBrainrotPaidPromptAt = now

				NetMsg.FireRequestUpgradeModel(pointIndex, 3, true)
				if players.LocalPlayer then
					marketplaceService:PromptProductPurchase(players.LocalPlayer, GameConfig.ShopPaid.BrainrotUpgrade3ProductId)
				end
				return
			end

			GameSoundManager.PlayUpgradeAbilitySound()
			ApplyLocalBrainrotUpgradePreview(slotName, pointIndex, 1)
			NetMsg.FireRequestUpgradeModel(pointIndex)
			NetMsg.FireRequestCompleteGuideStep(GameConfig.GuideStepKey.BrainrotUpgradeFinished)
		else
			-- 3. 出售请求
			GameSoundManager.PlaySellSound()
			NetMsg.FireRequestSellModel(pointIndex)
		end
	end
end

function HomeClientManager.Init()
	local function UpdateLocalHoldingBrainrotStatus()
		local char = players.LocalPlayer.Character
		local holding = false
		if char then
			local carry = char:FindFirstChild("CarryingBrainrot")
			if carry then
				if carry:GetAttribute("BrainrotUID") and carry:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
					holding = true
				end
			else
				local tool = char:FindFirstChildOfClass("Tool")
				if tool and tool:GetAttribute("BrainrotUID") and tool:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
					holding = true
				end
			end
		end

		if isLocalHoldingBrainrot ~= holding then
			isLocalHoldingBrainrot = holding
			-- Refresh own home slot if active
			local localInfo = ClientGameInfo.GetLocalPlayerInfo()
			if localInfo and localInfo.homeSlot and localInfo.homeSlot ~= "" then
				--	print("[HomeClientManager] Refreshing interaction prompts for slot", localInfo.homeSlot)
				UpdateHomePrompts(localInfo.homeSlot)
				UpdateRebirthMultiplierUI(
					localInfo.homeSlot,
					localInfo.homeInfo,
					true,
					if localInfo.shopInfo then localInfo.shopInfo.rebirthLevel else 0
				)
			end
		end
	end

	players.LocalPlayer.CharacterAdded:Connect(function(char)
		UpdateLocalHoldingBrainrotStatus()
		char.ChildAdded:Connect(UpdateLocalHoldingBrainrotStatus)
		char.ChildRemoved:Connect(UpdateLocalHoldingBrainrotStatus)
	end)
	if players.LocalPlayer.Character then
		UpdateLocalHoldingBrainrotStatus()
		players.LocalPlayer.Character.ChildAdded:Connect(UpdateLocalHoldingBrainrotStatus)
		players.LocalPlayer.Character.ChildRemoved:Connect(UpdateLocalHoldingBrainrotStatus)
	end

	RefreshAllHomes()
	ScheduleLocalSlotRecovery(true)
	runService.RenderStepped:Connect(RefreshLocalHomeInteractionFocus)
	runService.Heartbeat:Connect(refreshCollectYieldTextsForActiveHomes)
	proximityPromptService.PromptTriggered:Connect(OnPromptTriggered)

	-- Monitor for streaming / replication of parts
	for _, child in ipairs(homesFolder:GetChildren()) do
		if child.Name:match("^Player%d+$") then
			child.DescendantAdded:Connect(function(inst: Instance)
				if not ShouldScheduleSlotUpdateOnDescendantAdded(inst) then
					return
				end
				ScheduleSlotUpdate(child.Name)
			end)
		end
	end
	homesFolder.ChildAdded:Connect(function(child)
		if child.Name:match("^Player%d+$") then
			child.DescendantAdded:Connect(function(inst: Instance)
				if not ShouldScheduleSlotUpdateOnDescendantAdded(inst) then
					return
				end
				ScheduleSlotUpdate(child.Name)
			end)
			ScheduleSlotUpdate(child.Name)
		end
	end)

	players.PlayerRemoving:Connect(function(player)
		clearYieldAnchorsForOwner(player.UserId)
		ClientGameInfo.RemoveOtherPlayer(player.UserId)
		RefreshAllHomes()
	end)

	NetMsg.ConnectNotifyPlayerInfoInit(function()
		RefreshAllHomes()
		ScheduleLocalSlotRecovery(true)
	end)

	NetMsg.ConnectNotifyPlayersOtherPlayerInfoInit(function(playerId)
		task.wait()
		local otherInfo = ClientGameInfo.GetOtherPlayerInfo(playerId)
		if otherInfo and otherInfo.homeSlot and otherInfo.homeSlot ~= "" then
			slotStateCache[otherInfo.homeSlot] = {
				active = true,
				homeInfo = otherInfo.homeInfo,
				isLocalPlayer = false,
				rebirthLevel = otherInfo.rebirthLevel or 0,
				ownerUserId = playerId,
			}
			syncAllYieldAnchorsForOwner(playerId, otherInfo.homeInfo)
			ApplySlotVisuals(otherInfo.homeSlot)
		end
	end)

	ClientMsg.ConnectPlayerHomeInfoUpdate(function(playerId, homeSlot, homeInfo, rebirthLevel)
		local isLocal = (playerId == players.LocalPlayer.UserId)
		if isLocal and ((not homeSlot) or homeSlot == "" or homeInfo == nil) then
			ScheduleLocalSlotRecovery(true)
			return
		end
		if (not homeSlot) or homeSlot == "" then
			return
		end
		if not isLocal then
			local ownerPlayer = players:GetPlayerByUserId(playerId)
			local otherInfo = ClientGameInfo.GetOtherPlayerInfo(playerId)
			if ownerPlayer == nil or otherInfo == nil then
				slotStateCache[homeSlot] = { active = false }
				ApplySlotVisuals(homeSlot)
				return
			end
		end
		local currentState = slotStateCache[homeSlot]
		if isLocal then
			if currentState and currentState.active and HasSamePlacedModelOccupancy(currentState.homeInfo, homeInfo) then
				skipNextLocalInteractionFocusRefreshBySlot[homeSlot] = true
			else
				skipNextLocalInteractionFocusRefreshBySlot[homeSlot] = nil
			end
		end
		local resolvedRebirthLevel = rebirthLevel
		if resolvedRebirthLevel == nil then
			if isLocal then
				local localInfo = ClientGameInfo.GetLocalPlayerInfo()
				resolvedRebirthLevel = if localInfo and localInfo.shopInfo then localInfo.shopInfo.rebirthLevel else 0
			else
				resolvedRebirthLevel = currentState and currentState.rebirthLevel
			end
		end
		if homeInfo and homeInfo.placedModels then
			for pointIndexStr, placedData in pairs(homeInfo.placedModels) do
				DebugCollectYieldLog("HomeInfoUpdateModel", playerId, pointIndexStr, {
					homeSlot = homeSlot,
					isLocal = isLocal,
					baseYield = ((placedData :: any).unclaimedYield or 0),
					instanceId = tostring((placedData :: any).instanceId or ""),
				})
			end
		end
		preserveCurrentYieldForSameModels(homeSlot, homeInfo, playerId, resolvedRebirthLevel)
		slotStateCache[homeSlot] = {
			active = true,
			homeInfo = homeInfo,
			isLocalPlayer = isLocal,
			rebirthLevel = resolvedRebirthLevel,
			ownerUserId = playerId,
		}
		syncAllYieldAnchorsForOwner(playerId, homeInfo)
		ApplySlotVisuals(homeSlot)
		if isLocal and not homesFolder:FindFirstChild(homeSlot) then
			ScheduleSlotUpdate(homeSlot)
		end
	end)

	ClientMsg.ConnectLocalPlayerSkillLevelUpdate(function(skillType, level)
		if skillType ~= GameConfig.SkillType.RebirthLevel then
			return
		end
		local localInfo = ClientGameInfo.GetLocalPlayerInfo()
		if not localInfo or not localInfo.homeSlot or localInfo.homeSlot == "" then
			return
		end
		local homeSlot = localInfo.homeSlot
		local currentState = slotStateCache[homeSlot]
		slotStateCache[homeSlot] = {
			active = true,
			homeInfo = localInfo.homeInfo,
			isLocalPlayer = true,
			rebirthLevel = level,
			ownerUserId = players.LocalPlayer.UserId,
		}
		syncAllYieldAnchorsForOwner(players.LocalPlayer.UserId, localInfo.homeInfo)
		if currentState and currentState.active and currentState.homeInfo == localInfo.homeInfo then
			UpdateRebirthMultiplierUI(homeSlot, localInfo.homeInfo, true, level)
		else
			ApplySlotVisuals(homeSlot)
		end
	end)

	ClientMsg.ConnectAllPlayersModelYieldsUpdate(function(allYields)
		for playerIdStr, yields in pairs(allYields) do
			local playerId = tonumber(playerIdStr)
			if not playerId then
				continue
			end

			local playerInfo = if playerId == players.LocalPlayer.UserId
				then ClientGameInfo.GetLocalPlayerInfo()
				else ClientGameInfo.GetOtherPlayerInfo(playerId)

			if not playerInfo then
				continue
			end

			-- 更新视图表现
			local homeSlot = playerInfo.homeSlot
			local slotModel = homesFolder:FindFirstChild(homeSlot)
			if slotModel then
				for pointIndexStr, amount in pairs(yields) do
					local plot = findPlaceModelFolder(slotModel, pointIndexStr)

					if plot then
						-- 1. 更新数据缓存 (使其在 ApplySlotVisuals 调用时能拿到最新值)
						local pData: any? = nil
						if playerInfo.homeInfo and playerInfo.homeInfo.placedModels then
							pData = playerInfo.homeInfo.placedModels[pointIndexStr]
							if pData then
								local oldAmount = (pData :: any).unclaimedYield or 0
								DebugCollectYieldLog("YieldNetUpdate", playerId, pointIndexStr, {
									oldBase = oldAmount,
									newBase = amount,
									homeSlot = homeSlot,
								})
								pData.unclaimedYield = amount
								resetYieldAnchor(playerId, pointIndexStr)
								local slotState = slotStateCache[homeSlot]
								local slotPlacedModels = if slotState and slotState.homeInfo then slotState.homeInfo.placedModels else nil
								local slotPData = slotPlacedModels and slotPlacedModels[pointIndexStr]
								if slotPData and slotPData ~= pData then
									local slotAny = slotPData :: any
									DebugCollectYieldLog("YieldNetUpdateSlotCache", playerId, pointIndexStr, {
										oldBase = slotAny.unclaimedYield or 0,
										newBase = amount,
										homeSlot = homeSlot,
									})
									slotAny.unclaimedYield = amount
								end
							end
						end

						local booth = plot:FindFirstChild("Booth")
						local collectPart = booth and booth:FindFirstChild("CollectPart")
						local collectUI = collectPart and collectPart:FindFirstChild("CollectUI") :: SurfaceGui?
						if collectUI then
							-- 收益广播节流 UI（约每秒）只更新 CollectUI 数字/显隐，不走 Place/Sell Prompt 开关逻辑。
							local placedModels = if playerInfo.homeInfo then playerInfo.homeInfo.placedModels else nil
							local isOccupied = placedModels ~= nil and placedModels[pointIndexStr] ~= nil
							if collectUI.Enabled ~= true then
								collectUI.Enabled = true
							end
							local controller = collectUI:FindFirstChild("ControllerFrame")
							local collectText = controller and controller:FindFirstChild("CollectText") :: TextLabel?
							local coinImg = controller and controller:FindFirstChild("CoinImg") :: GuiObject?
							if collectText then
								if collectText.Visible ~= isOccupied then
									collectText.Visible = isOccupied
								end
								if isOccupied and pData then
									local slotState = slotStateCache[homeSlot]
									local rlv = if slotState and slotState.rebirthLevel ~= nil then slotState.rebirthLevel else 0
									local displayAmount = getExtrapolatedUnclaimedDisplay(playerId, pointIndexStr, pData, rlv)
									local newYieldText = NumberExtension.FormatBigNumberAA(displayAmount)
									setCollectYieldText(collectText, newYieldText, "YieldNetUpdate", playerId, pointIndexStr, displayAmount)
								end
							end
							if coinImg and coinImg.Visible ~= isOccupied then
								coinImg.Visible = isOccupied
							end
						end
					end
				end
			end
		end
	end)
end

-- All UI scaling is now handled by BillboardManager

return HomeClientManager
