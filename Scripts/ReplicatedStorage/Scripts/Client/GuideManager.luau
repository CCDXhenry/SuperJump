--!strict
local GuideManager = {}

local runService: RunService = game:GetService("RunService")
local players: Players = game:GetService("Players")
local localPlayer: Player? = players.LocalPlayer
if localPlayer == nil then
	warn("[GuideManager] LocalPlayer is nil at module load")
end
local workspace: Workspace = game:GetService("Workspace")
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))

local initialized = false
local lastGuideType = GameConfig.GuideType.None
local guideArrowModel: Model? = nil
local guideArrowStartAttachment: Attachment? = nil
local guideArrowEndAttachment: Attachment? = nil
local lastGuideTypeRefreshAt = 0
local lastArrowTargetRefreshAt = 0
local cachedArrowGuideType = GameConfig.GuideType.None
local cachedArrowTarget: Vector3? = nil
local pickupCandidatesInitialized = false
local pickupCandidatePartMap: { [BasePart]: boolean } = {}
local pendingCompleteGuideStepMap: { [string]: boolean } = {}
local observedPlacedModelClockMap: { [string]: number } = {}

local GUIDE_TYPE_REFRESH_INTERVAL = 0.2
local GUIDE_TARGET_REFRESH_INTERVAL = 0.2
local GUIDE_COLLECT_MIN_ELAPSED_SEC = 1
local InitPickupCandidates: () -> ()

-- 与 ServerGameInfo.IsPlayerOnWorkspaceGround / PavingClientManager 安全区射线对齐
local GROUND_RAY_ORIGIN_Y = 50
local GROUND_RAY_LENGTH = 60
local ISLAND_RAY_ORIGIN_Y = 50
local ISLAND_RAY_LENGTH = 60

local function ApplyGuideArrowPartPhysics(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Massless = true
end

local function ApplyGuideArrowPhysics(root: Instance)
	if root:IsA("BasePart") then
		ApplyGuideArrowPartPhysics(root)
	end
	for _, inst in root:GetDescendants() do
		if inst:IsA("BasePart") then
			ApplyGuideArrowPartPhysics(inst)
		end
	end
end

local function HasBrainrotPlacedOnHome(info: GameConfig.ClientLocalPlayerInfo): boolean
	for _, placed in info.homeInfo.placedModels do
		if GameConfig.BrainrotIdMap[placed.configId] ~= nil then
			return true
		end
	end
	return false
end

local function CountCarryingBrainrotsInQueue(info: GameConfig.ClientLocalPlayerInfo): number
	local n = 0
	for _, item in info.brainrotQueue do
		if item.itemType == GameConfig.ItemType.Brainrot then
			n += 1
		end
	end
	return n
end

local function IsLocalPlayerCarryingBrainrot(): boolean
	if localPlayer == nil then
		return false
	end
	local character = localPlayer.Character
	if character == nil then
		return false
	end
	return character:FindFirstChild("CarryingBrainrot") ~= nil
end

local function HasEquippedBrainrotTool(): boolean
	if localPlayer == nil then
		return false
	end
	local character = localPlayer.Character
	if character == nil then
		return false
	end
	local queue = ClientGameInfo.GetBrainrotQueue()
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			local uid = child:GetAttribute("BrainrotUID")
			if uid ~= nil then
				local uidStr = tostring(uid)
				for _, item in queue do
					if item.uid == uidStr and (item.itemType or GameConfig.ItemType.Brainrot) == GameConfig.ItemType.Brainrot then
						return true
					end
				end
			end
		end
	end
	return false
end

local function IsBrainrotPlaceFinished(info: GameConfig.ClientLocalPlayerInfo): boolean
	return info.guideProgressInfo.guideStepDoneMap[GameConfig.GuideStepKey.BrainrotPlaceFinished] == true
end

local function IsGuideStepDone(info: GameConfig.ClientLocalPlayerInfo, stepKey: string): boolean
	return info.guideProgressInfo.guideStepDoneMap[stepKey] == true
end

local function CompleteGuideStep(stepKey: string)
	local info = ClientGameInfo.GetLocalPlayerInfo()
	if info ~= nil and info.guideProgressInfo.guideStepDoneMap[stepKey] == true then
		return
	end
	if pendingCompleteGuideStepMap[stepKey] == true then
		return
	end
	pendingCompleteGuideStepMap[stepKey] = true
	NetMsg.FireRequestCompleteGuideStep(stepKey)
end

local function GetCoinCount(info: GameConfig.ClientLocalPlayerInfo): number
	return info.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
end

local function GetCollectMultipleForRebirth(rebirthLevel: number?): number
	local level = rebirthLevel or 0
	local rebirthConfig = GameConfig.RebirthMap[level]
	return if rebirthConfig ~= nil then rebirthConfig.collectMultiple else 1
end

local function GetBrainrotYieldPerSecond(placed: GameConfig.ModelInfo, rebirthLevel: number?): number
	local brainrotData = GameConfig.BrainrotIdMap[placed.configId]
	if brainrotData == nil then
		return 0
	end
	local baseYield = GameConfig.GetBrainrotAbilityWithVariant(brainrotData.baseAbility, placed.level or 1, placed.variantId)
	return math.ceil(baseYield * GetCollectMultipleForRebirth(rebirthLevel))
end

local function GetEstimatedCollectableYield(pointIndexStr: string, placed: GameConfig.ModelInfo, rebirthLevel: number?): number
	local staticYield = placed.unclaimedYield or 0
	if staticYield > 0 then
		return staticYield
	end
	local perSecond = GetBrainrotYieldPerSecond(placed, rebirthLevel)
	if perSecond <= 0 then
		return 0
	end
	local placedAny = placed :: any
	local startUnix = placedAny.yieldAccrueStartUnix
	if typeof(startUnix) == "number" then
		local elapsed = math.max(0, DateTime.now().UnixTimestamp - math.floor(startUnix))
		return if elapsed >= GUIDE_COLLECT_MIN_ELAPSED_SEC then perSecond * elapsed else 0
	end
	local observedClock = observedPlacedModelClockMap[pointIndexStr]
	if observedClock == nil then
		observedClock = os.clock()
		observedPlacedModelClockMap[pointIndexStr] = observedClock
	end
	local elapsed = math.floor(os.clock() - observedClock)
	return if elapsed >= GUIDE_COLLECT_MIN_ELAPSED_SEC then perSecond * elapsed else 0
end

local function IsTargetExEquipOwned(info: GameConfig.ClientLocalPlayerInfo): boolean
	return info.exEquipInventory.ownedList[tostring(GameConfig.GuideTargetExEquipId)] == true
end

local function HasAnyOwnedJetpack(info: GameConfig.ClientLocalPlayerInfo): boolean
	for _, isOwned in pairs(info.jetpackInventory.ownedList) do
		if isOwned == true then
			return true
		end
	end
	return false
end

local function HasAnyOwnedExEquip(info: GameConfig.ClientLocalPlayerInfo): boolean
	for _, isOwned in pairs(info.exEquipInventory.ownedList) do
		if isOwned == true then
			return true
		end
	end
	return false
end

local function IsTargetJetpackAffordable(info: GameConfig.ClientLocalPlayerInfo): boolean
	local jetpackData = GameConfig.JetpackDataMap[GameConfig.GuideTargetJetpackId]
	return jetpackData ~= nil and GetCoinCount(info) >= jetpackData.costCoin
end

local function IsTargetExEquipAffordable(info: GameConfig.ClientLocalPlayerInfo): boolean
	local equipData = GameConfig.ExEquipDataMap[GameConfig.GuideTargetExEquipId]
	return equipData ~= nil and GetCoinCount(info) >= equipData.costCoin
end

local function IsExEquipGuideUnlocked(info: GameConfig.ClientLocalPlayerInfo): boolean
	return IsGuideStepDone(info, GameConfig.GuideStepKey.JetpackBuyFinished)
		and IsGuideStepDone(info, GameConfig.GuideStepKey.JetpackRunwayRetryFinished)
end

local function IsExEquipGuideFinished(info: GameConfig.ClientLocalPlayerInfo): boolean
	return IsGuideStepDone(info, GameConfig.GuideStepKey.ExEquipBuyFinished)
		and IsGuideStepDone(info, GameConfig.GuideStepKey.ExEquipUseFinished)
		and IsGuideStepDone(info, GameConfig.GuideStepKey.JumpPowerRunwayRetryFinished)
end

local function HasMetWalkSpeedUpgradeDistanceRequirement(info: GameConfig.ClientLocalPlayerInfo): boolean
	return (info.jumpRunwayBestDistance or 0) > GameConfig.GuideWalkSpeedUpgradeMinBestDistance
end

local function IsWalkSpeedUpgradeGuideUnlocked(info: GameConfig.ClientLocalPlayerInfo): boolean
	return HasMetWalkSpeedUpgradeDistanceRequirement(info)
		and IsExEquipGuideUnlocked(info)
		and IsExEquipGuideFinished(info)
end

local function TryCompleteOwnedPurchaseGuideSteps()
	local info = ClientGameInfo.GetLocalPlayerInfo()
	if info == nil then
		return
	end
	if HasAnyOwnedJetpack(info) and not IsGuideStepDone(info, GameConfig.GuideStepKey.JetpackBuyFinished) then
		CompleteGuideStep(GameConfig.GuideStepKey.JetpackBuyFinished)
	end
	if HasAnyOwnedExEquip(info) and not IsGuideStepDone(info, GameConfig.GuideStepKey.ExEquipBuyFinished) then
		CompleteGuideStep(GameConfig.GuideStepKey.ExEquipBuyFinished)
	end
end

local function HasCollectableBrainrotYield(info: GameConfig.ClientLocalPlayerInfo): boolean
	for pointIndexStr, placed in pairs(info.homeInfo.placedModels) do
		if GetEstimatedCollectableYield(pointIndexStr, placed, info.shopInfo.rebirthLevel) > 0 then
			return true
		end
	end
	return false
end

local function HasUpgradedBrainrot(info: GameConfig.ClientLocalPlayerInfo): boolean
	for _, placed in pairs(info.homeInfo.placedModels) do
		if placed.level > 1 then
			return true
		end
	end
	return false
end

local function HasAffordableUpgradeableBrainrot(info: GameConfig.ClientLocalPlayerInfo): boolean
	local coinCount = GetCoinCount(info)
	for _, placed in pairs(info.homeInfo.placedModels) do
		local brainrotData = GameConfig.BrainrotIdMap[placed.configId]
		if brainrotData ~= nil then
			local upgradeCost = GameConfig.GetBrainrotUpgradeCost(brainrotData.baseAbility, placed.level)
			if coinCount >= upgradeCost then
				return true
			end
		end
	end
	return false
end

local function HasWalkSpeedUpgraded(info: GameConfig.ClientLocalPlayerInfo): boolean
	return (info.shopInfo.walkSpeedLevel or 1) > 1
end

local function HasJumpPowerUpgraded(info: GameConfig.ClientLocalPlayerInfo): boolean
	return info.jumpPower.lv > 1
end

local function IsWalkSpeedUpgradeAffordable(info: GameConfig.ClientLocalPlayerInfo): boolean
	local walkSpeedConfig = GameConfig.Shop.WalkSpeed
	local currentLevel = info.shopInfo.walkSpeedLevel or 1
	local upgradeCost = walkSpeedConfig.upgradeCostList[currentLevel]
	return upgradeCost ~= nil and GetCoinCount(info) >= upgradeCost
end

local function ResolveNearestEmptyPlotPosition(info: GameConfig.ClientLocalPlayerInfo): Vector3?
	if info.homeSlot == nil or info.homeSlot == "" then
		return nil
	end
	local homesFolder = workspace:FindFirstChild("PlayersHome")
	local slotModel = if homesFolder then homesFolder:FindFirstChild(info.homeSlot) :: Model? else nil
	if slotModel == nil then
		return nil
	end
	if localPlayer == nil then
		return nil
	end
	local character = localPlayer.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local origin = if hrp then hrp.Position else nil

	local bestPos: Vector3? = nil
	local bestDist = math.huge
	local fallbackPos: Vector3? = nil

	for _, floor in ipairs(slotModel:GetChildren()) do
		if string.match(floor.Name, "^Lv%d+$") then
			for _, plot in ipairs(floor:GetChildren()) do
				local idxStr = string.match(plot.Name, "^PlaceModel(%d+)$")
				if idxStr and plot:IsA("Model") then
					local pointIndex = tonumber(idxStr)
					if pointIndex ~= nil and info.homeInfo.placedModels[tostring(pointIndex)] == nil then
						local rootPart = plot:FindFirstChild("RootPart") :: BasePart?
						if rootPart then
							local placeAtt = rootPart:FindFirstChild("PlaceAttachment")
							local pos: Vector3
							if placeAtt and placeAtt:IsA("Attachment") then
								pos = placeAtt.WorldPosition
							else
								pos = rootPart.Position
							end
							if fallbackPos == nil then
								fallbackPos = pos
							end
							if origin ~= nil then
								local dist = (pos - origin).Magnitude
								if dist < bestDist then
									bestDist = dist
									bestPos = pos
								end
							end
						end
					end
				end
			end
		end
	end
	return bestPos or fallbackPos
end

local function GetWorldPositionFromInstance(inst: Instance): Vector3?
	if inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	if inst:IsA("BasePart") then
		return inst.Position
	end
	return nil
end

-- 放置引导终点：在所有空展台中找 PlaceModel*.Booth.BoothModel，取离 HRP 最近的世界坐标
local function ResolvePlacementBoothWorldPosition(info: GameConfig.ClientLocalPlayerInfo): Vector3?
	if info.homeSlot == nil or info.homeSlot == "" then
		return nil
	end
	local homesFolder = workspace:FindFirstChild("PlayersHome")
	if homesFolder == nil then
		return nil
	end
	local slotModel = homesFolder:FindFirstChild(info.homeSlot)
	if slotModel == nil then
		return nil
	end
	if localPlayer == nil then
		return nil
	end
	local character = localPlayer.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local origin = if hrp then hrp.Position else nil

	local path = GameConfig.GuidePlacementBoothPath
	local bestPos: Vector3? = nil
	local bestDist = math.huge
	local fallbackPos: Vector3? = nil

	for _, floor in ipairs(slotModel:GetChildren()) do
		if string.match(floor.Name, "^Lv%d+$") then
			for _, plot in ipairs(floor:GetChildren()) do
				local idxStr = string.match(plot.Name, "^PlaceModel(%d+)$")
				if idxStr and plot:IsA("Model") then
					local pointIndex = tonumber(idxStr)
					if pointIndex ~= nil and info.homeInfo.placedModels[tostring(pointIndex)] == nil then
						local boothFolder = plot:FindFirstChild(path.BoothFolderName)
						local boothModel = if boothFolder then boothFolder:FindFirstChild(path.BoothModelName) else nil
						if boothModel == nil then
							continue
						end
						local pos = GetWorldPositionFromInstance(boothModel)
						if pos == nil then
							continue
						end
						if fallbackPos == nil then
							fallbackPos = pos
						end
						if origin ~= nil then
							local dist = (pos - origin).Magnitude
							if dist < bestDist then
								bestDist = dist
								bestPos = pos
							end
						end
					end
				end
			end
		end
	end
	if bestPos ~= nil then
		return bestPos
	end
	if fallbackPos ~= nil then
		return fallbackPos
	end
	return ResolveNearestEmptyPlotPosition(info)
end

-- 收集引导：已占用展台 PlaceModel*.Booth.CollectPart；优先 unclaimedYield > 0 且离 HRP 最近
local function ResolveCollectPartWorldPosition(info: GameConfig.ClientLocalPlayerInfo): Vector3?
	if info.homeSlot == nil or info.homeSlot == "" then
		return nil
	end
	local homesFolder = workspace:FindFirstChild("PlayersHome")
	if homesFolder == nil then
		return nil
	end
	local slotModel = homesFolder:FindFirstChild(info.homeSlot)
	if slotModel == nil then
		return nil
	end
	if localPlayer == nil then
		return nil
	end
	local character = localPlayer.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local origin = if hrp then hrp.Position else nil

	local path = GameConfig.GuidePlacementBoothPath
	local collectName = path.CollectPartName

	local bestWithYieldPos: Vector3? = nil
	local bestWithYieldDist = math.huge
	local fallbackPos: Vector3? = nil
	local fallbackDist = math.huge

	for _, floor in ipairs(slotModel:GetChildren()) do
		if string.match(floor.Name, "^Lv%d+$") then
			for _, plot in ipairs(floor:GetChildren()) do
				local idxStr = string.match(plot.Name, "^PlaceModel(%d+)$")
				if idxStr and plot:IsA("Model") then
					local pointIndex = tonumber(idxStr)
					if pointIndex == nil then
						continue
					end
					if info.homeInfo.placedModels[tostring(pointIndex)] == nil then
						continue
					end
					local boothFolder = plot:FindFirstChild(path.BoothFolderName)
					local collectPart = if boothFolder then boothFolder:FindFirstChild(collectName) else nil
					if collectPart == nil or not collectPart:IsA("BasePart") then
						continue
					end
					local pos = collectPart.Position
					if origin == nil then
						if fallbackPos == nil then
							fallbackPos = pos
						end
						continue
					end
					local modelInfo = info.homeInfo.placedModels[tostring(pointIndex)]
					local yieldAmt = if modelInfo then GetEstimatedCollectableYield(tostring(pointIndex), modelInfo, info.shopInfo.rebirthLevel) else 0
					local dist = (pos - origin).Magnitude
					if yieldAmt > 0 then
						if dist < bestWithYieldDist then
							bestWithYieldDist = dist
							bestWithYieldPos = pos
						end
					else
						if dist < fallbackDist then
							fallbackDist = dist
							fallbackPos = pos
						end
					end
				end
			end
		end
	end
	if bestWithYieldPos ~= nil then
		return bestWithYieldPos
	end
	return fallbackPos
end

local function ResolveUpgradeableBrainrotWorldPosition(info: GameConfig.ClientLocalPlayerInfo): Vector3?
	if info.homeSlot == nil or info.homeSlot == "" then
		return nil
	end
	local homesFolder = workspace:FindFirstChild("PlayersHome")
	if homesFolder == nil then
		return nil
	end
	local slotModel = homesFolder:FindFirstChild(info.homeSlot)
	if slotModel == nil then
		return nil
	end
	if localPlayer == nil then
		return nil
	end
	local character = localPlayer.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local origin = if hrp then hrp.Position else nil
	local path = GameConfig.GuidePlacementBoothPath
	local coinCount = GetCoinCount(info)

	local bestPos: Vector3? = nil
	local bestDist = math.huge
	local fallbackPos: Vector3? = nil

	for _, floor in ipairs(slotModel:GetChildren()) do
		if string.match(floor.Name, "^Lv%d+$") then
			for _, plot in ipairs(floor:GetChildren()) do
				local idxStr = string.match(plot.Name, "^PlaceModel(%d+)$")
				if idxStr == nil or not plot:IsA("Model") then
					continue
				end
				local pointIndex = tonumber(idxStr)
				if pointIndex == nil then
					continue
				end
				local modelInfo = info.homeInfo.placedModels[tostring(pointIndex)]
				if modelInfo == nil then
					continue
				end
				local brainrotData = GameConfig.BrainrotIdMap[modelInfo.configId]
				if brainrotData == nil then
					continue
				end
				local upgradeCost = GameConfig.GetBrainrotUpgradeCost(brainrotData.baseAbility, modelInfo.level)
				if coinCount < upgradeCost then
					continue
				end
				local boothFolder = plot:FindFirstChild(path.BoothFolderName)
				local upgradePart = if boothFolder then boothFolder:FindFirstChild(path.UpgradePartName) else nil
				local pos = if upgradePart ~= nil and upgradePart:IsA("BasePart") then upgradePart.Position else GetWorldPositionFromInstance(plot)
				if pos == nil then
					continue
				end
				if fallbackPos == nil then
					fallbackPos = pos
				end
				if origin ~= nil then
					local dist = (pos - origin).Magnitude
					if dist < bestDist then
						bestDist = dist
						bestPos = pos
					end
				end
			end
		end
	end
	return if bestPos ~= nil then bestPos else fallbackPos
end

local function ResolvePickupBrainrotTarget(): Vector3?
	if not pickupCandidatesInitialized then
		InitPickupCandidates()
	end
	if localPlayer == nil then
		return nil
	end
	local character = localPlayer.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local origin = if hrp then hrp.Position else nil
	if origin == nil then
		return nil
	end
	local bestPart: BasePart? = nil
	local bestDist = math.huge
	for part in pairs(pickupCandidatePartMap) do
		if part.Parent == nil then
			pickupCandidatePartMap[part] = nil
			continue
		end
		local configId = part:GetAttribute("ConfigId") :: number?
		if configId ~= nil then
			local itemType = part:GetAttribute("ItemType") :: number?
			if itemType == nil or itemType == GameConfig.ItemType.Brainrot then
				local dist = (part.Position - origin).Magnitude
				if dist < bestDist then
					bestDist = dist
					bestPart = part
				end
			end
		end
	end
	if bestPart then
		return bestPart.Position
	end
	return nil
end

local function ResolveUpgradeShopWorldPosition(): Vector3?
	local shopModelFolder = workspace:FindFirstChild("ShopModel")
	local shopModel = if shopModelFolder then shopModelFolder:FindFirstChild("UpgradeShop") else nil
	if shopModel == nil then
		return nil
	end
	local guidePart = shopModel:FindFirstChild("GuidePart", true)
	if guidePart ~= nil and guidePart:IsA("BasePart") then
		return guidePart.Position
	end
	if shopModel:IsA("Model") then
		return shopModel:GetPivot().Position
	end
	if shopModel:IsA("BasePart") then
		return shopModel.Position
	end
	return nil
end

local function ResolveStartTriggerWorldPosition(): Vector3?
	local startPoint = workspace:FindFirstChild("StartPoint")
	local startModel = if startPoint then startPoint:FindFirstChild("StartPointModel") else nil
	local startTrigger = if startModel then startModel:FindFirstChild("StartTrigger") else nil
	if startTrigger ~= nil and startTrigger:IsA("BasePart") then
		local guideAttachment = startTrigger:FindFirstChild("GuideAttachment")
		if guideAttachment and guideAttachment:IsA("Attachment") then
			return guideAttachment.WorldPosition
		end
		return startTrigger.Position
	end
	return nil
end

local function ResolveShopGuidePartWorldPosition(shopModelName: string): Vector3?
	local shopModelFolder = workspace:FindFirstChild("ShopModel")
	local shopModel = if shopModelFolder then shopModelFolder:FindFirstChild(shopModelName) else nil
	if shopModel == nil then
		return nil
	end
	local guidePart = shopModel:FindFirstChild("GuidePart", true)
	if guidePart ~= nil and guidePart:IsA("BasePart") then
		return guidePart.Position
	end
	if shopModel:IsA("Model") then
		return shopModel:GetPivot().Position
	end
	return nil
end

local function GetLocalPlayerHrp(): BasePart?
	if localPlayer == nil then
		return nil
	end
	local character = localPlayer.Character
	if character == nil then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function IsLocalPlayerOverWorkspaceGround(): boolean
	local hrp = GetLocalPlayerHrp()
	if hrp == nil then
		return false
	end
	local groundFolder = workspace:FindFirstChild("Ground") or workspace:FindFirstChild("ground")
	if groundFolder == nil then
		return false
	end
	local samplePos = hrp.Position
	local rayOrigin = samplePos + Vector3.new(0, GROUND_RAY_ORIGIN_Y, 0)
	local rayDirection = Vector3.new(0, -GROUND_RAY_LENGTH, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { groundFolder }
	return workspace:Raycast(rayOrigin, rayDirection, raycastParams) ~= nil
end

local function GetIslandRootUnderLocalHrp(): Instance?
	local hrp = GetLocalPlayerHrp()
	if hrp == nil then
		return nil
	end
	local islandsFolder = workspace:FindFirstChild("Islands")
	if islandsFolder == nil then
		return nil
	end
	local samplePos = hrp.Position
	local rayOrigin = samplePos + Vector3.new(0, ISLAND_RAY_ORIGIN_Y, 0)
	local rayDirection = Vector3.new(0, -ISLAND_RAY_LENGTH, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { islandsFolder }
	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if result == nil then
		return nil
	end
	local inst: Instance? = result.Instance
	while inst ~= nil and inst ~= islandsFolder do
		if inst.Parent == islandsFolder then
			return inst
		end
		inst = inst.Parent
	end
	return nil
end

local function ResolveIslandTeleportWorldPosition(island: Instance): Vector3?
	local teleportPoint = island:FindFirstChild("TeleportPoint")
	if teleportPoint == nil or not teleportPoint:IsA("Model") then
		return nil
	end
	local ring = teleportPoint:FindFirstChild("Ring")
	if ring and ring:IsA("MeshPart") then
		return ring.Position
	end
	return teleportPoint:GetPivot().Position
end

local function ShouldGuideIslandTeleportFirst(): boolean
	if IsLocalPlayerOverWorkspaceGround() then
		return false
	end
	local island = GetIslandRootUnderLocalHrp()
	if island == nil then
		return false
	end
	return ResolveIslandTeleportWorldPosition(island) ~= nil
end

local function MaybeIslandTeleportOr(placeType: number): number
	if ShouldGuideIslandTeleportFirst() then
		return GameConfig.GuideType.TutorialBrainrotIslandTeleport
	end
	return placeType
end

local function ResolveWorldTargetForGuide(guideType: number): Vector3?
	if guideType == GameConfig.GuideType.TutorialBrainrotIslandTeleport then
		local island = GetIslandRootUnderLocalHrp()
		if island == nil then
			return nil
		end
		return ResolveIslandTeleportWorldPosition(island)
	elseif guideType == GameConfig.GuideType.TutorialBrainrotPlace or guideType == GameConfig.GuideType.TutorialBrainrotPlaceSlot then
		local info = ClientGameInfo.GetLocalPlayerInfo()
		if info == nil then
			return nil
		end
		return ResolvePlacementBoothWorldPosition(info)
	elseif guideType == GameConfig.GuideType.TutorialBrainrotCollect then
		local info = ClientGameInfo.GetLocalPlayerInfo()
		if info == nil then
			return nil
		end
		return ResolveCollectPartWorldPosition(info)
	elseif guideType == GameConfig.GuideType.TutorialBrainrotUpgrade then
		local info = ClientGameInfo.GetLocalPlayerInfo()
		if info == nil then
			return nil
		end
		return ResolveUpgradeableBrainrotWorldPosition(info)
	elseif guideType == GameConfig.GuideType.TutorialWalkSpeedUpgrade then
		return ResolveUpgradeShopWorldPosition()
	elseif guideType == GameConfig.GuideType.TutorialBrainrotPickup then
		return ResolvePickupBrainrotTarget()
	elseif guideType == GameConfig.GuideType.TutorialStartTrigger then
		return ResolveStartTriggerWorldPosition()
	elseif guideType == GameConfig.GuideType.TutorialJetpackRunwayRetry then
		return ResolveStartTriggerWorldPosition()
	elseif guideType == GameConfig.GuideType.TutorialJumpPowerRunwayRetry then
		return ResolveStartTriggerWorldPosition()
	elseif guideType == GameConfig.GuideType.TutorialJetpackBuy then
		return ResolveShopGuidePartWorldPosition("JetpackShop")
	elseif guideType == GameConfig.GuideType.TutorialExEquipBuy then
		return ResolveShopGuidePartWorldPosition("ExEquipShop")
	end
	return nil
end

local function IsTeleShopGuideType(guideType: number): boolean
	return guideType == GameConfig.GuideType.TutorialJetpackBuy
		or guideType == GameConfig.GuideType.TutorialExEquipBuy
		or guideType == GameConfig.GuideType.TutorialWalkSpeedUpgrade
end

local function IsPlayerFarFromShopGuideTarget(guideType: number): boolean
	if not IsTeleShopGuideType(guideType) then
		return false
	end
	local target = ResolveWorldTargetForGuide(guideType)
	if target == nil then
		return false
	end
	local hrp = GetLocalPlayerHrp()
	if hrp == nil then
		return false
	end
	return (hrp.Position - target).Magnitude > GameConfig.GuideShopTeleportDistanceThreshold
end

function GuideManager.ShouldGuideTeleShopFirst(guideType: number): boolean
	return IsPlayerFarFromShopGuideTarget(guideType)
end

local function IsRunwayGuideType(guideType: number): boolean
	return guideType == GameConfig.GuideType.TutorialBeginLineJump
		or guideType == GameConfig.GuideType.TutorialLandingJump
		or guideType == GameConfig.GuideType.TutorialFinalDash
end

local function IsOutsideRunwaySessionGuideType(guideType: number): boolean
	return guideType == GameConfig.GuideType.TutorialBrainrotCollect
		or guideType == GameConfig.GuideType.TutorialBrainrotUpgrade
		or guideType == GameConfig.GuideType.TutorialBrainrotIslandTeleport
		or guideType == GameConfig.GuideType.TutorialJetpackBuy
		or guideType == GameConfig.GuideType.TutorialExEquipBuy
		or guideType == GameConfig.GuideType.TutorialExEquipUse
		or guideType == GameConfig.GuideType.TutorialWalkSpeedUpgrade
end

local function IsInJumpRunwaySession(): boolean
	return ClientGameInfo.IsInJumpRunway() or ClientGameInfo.IsInJumpRunwayEscapePhase()
end

local function FilterOutsideRunwaySessionGuide(guideType: number): number
	if IsOutsideRunwaySessionGuideType(guideType) and IsInJumpRunwaySession() then
		return GameConfig.GuideType.None
	end
	return guideType
end

local function UpdateAttachmentsRotation()
	local startAttachment = guideArrowStartAttachment
	local endAttachment = guideArrowEndAttachment
	if startAttachment == nil or endAttachment == nil then
		return
	end
	local rotation: CFrame = CFrame.new(startAttachment.Position, endAttachment.Position)
		:ToWorldSpace(CFrame.Angles(0, 0, math.rad(90))).Rotation
	startAttachment.CFrame = rotation + startAttachment.Position
	endAttachment.CFrame = rotation + endAttachment.Position
end

local function UpdateGuideArrow()
	if guideArrowModel == nil or guideArrowStartAttachment == nil or guideArrowEndAttachment == nil then
		return
	end
	if ClientGameInfo.IsExercising() then
		guideArrowModel.Parent = nil
		return
	end
	local guideType = ClientGameInfo.GetCurrentGuideType()
	if IsOutsideRunwaySessionGuideType(guideType) and IsInJumpRunwaySession() then
		guideArrowModel.Parent = nil
		return
	end
	local needsWorldArrow = guideType == GameConfig.GuideType.TutorialBrainrotPickup
		or guideType == GameConfig.GuideType.TutorialBrainrotPlace
		or guideType == GameConfig.GuideType.TutorialBrainrotPlaceSlot
		or guideType == GameConfig.GuideType.TutorialBrainrotIslandTeleport
		or guideType == GameConfig.GuideType.TutorialBrainrotCollect
		or guideType == GameConfig.GuideType.TutorialBrainrotUpgrade
		or guideType == GameConfig.GuideType.TutorialWalkSpeedUpgrade
		or guideType == GameConfig.GuideType.TutorialStartTrigger
		or guideType == GameConfig.GuideType.TutorialJetpackRunwayRetry
		or guideType == GameConfig.GuideType.TutorialJumpPowerRunwayRetry
		or guideType == GameConfig.GuideType.TutorialJetpackBuy
		or guideType == GameConfig.GuideType.TutorialExEquipBuy
	if not needsWorldArrow then
		guideArrowModel.Parent = nil
		return
	end
	if IsPlayerFarFromShopGuideTarget(guideType) then
		guideArrowModel.Parent = nil
		return
	end
	local hrp = GetLocalPlayerHrp()
	if hrp == nil then
		guideArrowModel.Parent = nil
		return
	end
	local now = os.clock()
	if cachedArrowGuideType ~= guideType or now - lastArrowTargetRefreshAt >= GUIDE_TARGET_REFRESH_INTERVAL then
		lastArrowTargetRefreshAt = now
		cachedArrowGuideType = guideType
		cachedArrowTarget = ResolveWorldTargetForGuide(guideType)
	end
	local target = cachedArrowTarget
	if target == nil then
		guideArrowModel.Parent = nil
		return
	end
	local startPos = hrp.Position
	local endPos = target --+ Vector3.new(0, GameConfig.GuideArrowYOffset, 0)
	guideArrowStartAttachment.WorldCFrame = CFrame.new(startPos)
	guideArrowEndAttachment.WorldCFrame = CFrame.new(endPos)
	UpdateAttachmentsRotation()
	guideArrowModel.Parent = workspace
end

local function ResolveGuideType(): number
	-- JumpRunway 主跑道阶段：仅保留跑道内引导
	if ClientGameInfo.IsInJumpRunway() and not ClientGameInfo.IsInJumpRunwayEscapePhase() then
		local currentGuideType = ClientGameInfo.GetCurrentGuideType()
		return if IsRunwayGuideType(currentGuideType) then currentGuideType else GameConfig.GuideType.None
	end
	-- 锻炼模式隐藏非锻炼引导
	if ClientGameInfo.IsExercising() then
		return GameConfig.GuideType.None
	end
	local info = ClientGameInfo.GetLocalPlayerInfo()
	if info == nil then
		return GameConfig.GuideType.None
	end

	if not HasBrainrotPlacedOnHome(info) and not IsBrainrotPlaceFinished(info) then
		if CountCarryingBrainrotsInQueue(info) > 0 then
			if IsLocalPlayerCarryingBrainrot() then
				return GameConfig.GuideType.TutorialBrainrotPlace
			end
			if not HasEquippedBrainrotTool() then
				return GameConfig.GuideType.TutorialBrainrotPlaceSlot
			end
			return GameConfig.GuideType.TutorialBrainrotPlace
		end
		if IsLocalPlayerCarryingBrainrot() then
			return GameConfig.GuideType.TutorialBrainrotPlace
		end
	end

	if not IsGuideStepDone(info, GameConfig.GuideStepKey.BrainrotCollectFinished) and HasCollectableBrainrotYield(info) then
		return FilterOutsideRunwaySessionGuide(
			MaybeIslandTeleportOr(GameConfig.GuideType.TutorialBrainrotCollect)
		)
	end

	if IsGuideStepDone(info, GameConfig.GuideStepKey.BrainrotCollectFinished)
		and not IsGuideStepDone(info, GameConfig.GuideStepKey.BrainrotUpgradeFinished)
	then
		if HasUpgradedBrainrot(info) then
			CompleteGuideStep(GameConfig.GuideStepKey.BrainrotUpgradeFinished)
		elseif HasAffordableUpgradeableBrainrot(info) then
			return FilterOutsideRunwaySessionGuide(
				MaybeIslandTeleportOr(GameConfig.GuideType.TutorialBrainrotUpgrade)
			)
		end
	end

	local hasAnyOwnedJetpack = HasAnyOwnedJetpack(info)
	if hasAnyOwnedJetpack and not IsGuideStepDone(info, GameConfig.GuideStepKey.JetpackBuyFinished) then
		CompleteGuideStep(GameConfig.GuideStepKey.JetpackBuyFinished)
	end
	if hasAnyOwnedJetpack then
		if IsGuideStepDone(info, GameConfig.GuideStepKey.JetpackBuyFinished)
			and not IsGuideStepDone(info, GameConfig.GuideStepKey.JetpackRunwayRetryFinished)
		then
			return GameConfig.GuideType.TutorialJetpackRunwayRetry
		end
	elseif not IsGuideStepDone(info, GameConfig.GuideStepKey.JetpackBuyFinished)
		and not HasAnyOwnedJetpack(info)
		and IsTargetJetpackAffordable(info)
	then
		return FilterOutsideRunwaySessionGuide(GameConfig.GuideType.TutorialJetpackBuy)
	end

	if IsExEquipGuideUnlocked(info) then
		local hasAnyOwnedExEquip = HasAnyOwnedExEquip(info)
		if hasAnyOwnedExEquip and not IsGuideStepDone(info, GameConfig.GuideStepKey.ExEquipBuyFinished) then
			CompleteGuideStep(GameConfig.GuideStepKey.ExEquipBuyFinished)
		end
		if hasAnyOwnedExEquip then
			if not IsGuideStepDone(info, GameConfig.GuideStepKey.ExEquipUseFinished) then
				return FilterOutsideRunwaySessionGuide(GameConfig.GuideType.TutorialExEquipUse)
			end
			if
				IsGuideStepDone(info, GameConfig.GuideStepKey.ExEquipUseFinished)
				and HasJumpPowerUpgraded(info)
				and not IsGuideStepDone(info, GameConfig.GuideStepKey.JumpPowerRunwayRetryFinished)
			then
				return GameConfig.GuideType.TutorialJumpPowerRunwayRetry
			end
		elseif not IsGuideStepDone(info, GameConfig.GuideStepKey.ExEquipBuyFinished)
			and not HasAnyOwnedExEquip(info)
			and IsTargetExEquipAffordable(info)
		then
			return FilterOutsideRunwaySessionGuide(GameConfig.GuideType.TutorialExEquipBuy)
		end
	end

	if not IsGuideStepDone(info, GameConfig.GuideStepKey.WalkSpeedUpgradeFinished) then
		if HasWalkSpeedUpgraded(info) then
			CompleteGuideStep(GameConfig.GuideStepKey.WalkSpeedUpgradeFinished)
		elseif IsWalkSpeedUpgradeGuideUnlocked(info) then
			if IsWalkSpeedUpgradeAffordable(info) then
				return FilterOutsideRunwaySessionGuide(
					MaybeIslandTeleportOr(GameConfig.GuideType.TutorialWalkSpeedUpgrade)
				)
			elseif HasCollectableBrainrotYield(info) then
				return FilterOutsideRunwaySessionGuide(
					MaybeIslandTeleportOr(GameConfig.GuideType.TutorialBrainrotCollect)
				)
			end
		end
	end

	if not IsGuideStepDone(info, GameConfig.GuideStepKey.StartTriggerFinished) then
		return GameConfig.GuideType.TutorialStartTrigger
	end

	return GameConfig.GuideType.None
end

local function RefreshGuideType()
	local now = os.clock()
	if now - lastGuideTypeRefreshAt < GUIDE_TYPE_REFRESH_INTERVAL then
		return
	end
	lastGuideTypeRefreshAt = now
	local currentGuideType = ResolveGuideType()
	if currentGuideType == lastGuideType then
		return
	end
	lastGuideType = currentGuideType
	ClientGameInfo.SetCurrentGuideType(currentGuideType)
end

local function ForceRefreshGuideType()
	lastGuideTypeRefreshAt = 0
	RefreshGuideType()
end

InitPickupCandidates = function()
	if pickupCandidatesInitialized then
		return
	end
	local islandsFolder = workspace:FindFirstChild("Islands")
	if islandsFolder == nil then
		return
	end
	pickupCandidatesInitialized = true
	for _, desc in islandsFolder:GetDescendants() do
		if desc:IsA("BasePart") then
			pickupCandidatePartMap[desc] = true
		end
	end
	islandsFolder.DescendantAdded:Connect(function(desc: Instance)
		if desc:IsA("BasePart") then
			pickupCandidatePartMap[desc] = true
		end
	end)
	islandsFolder.DescendantRemoving:Connect(function(desc: Instance)
		if desc:IsA("BasePart") then
			pickupCandidatePartMap[desc] = nil
		end
	end)
end

local function TryCreateArrowModel()
	local modelsFolder = replicatedStorage:FindFirstChild("Models")
	if modelsFolder == nil then
		return
	end
	local template = modelsFolder:FindFirstChild(GameConfig.GuideAssetName.ModelArrow)
	if template == nil then
		warn("[GuideManager] GuideArrow model not found:", GameConfig.GuideAssetName.ModelArrow)
		return
	end
	if not (template:IsA("Model") or template:IsA("BasePart")) then
		warn("[GuideManager] GuideArrow root must be Model or BasePart, got", template.ClassName)
		return
	end

	local clone = template:Clone()
	local container: Model
	if clone:IsA("Model") then
		container = clone :: Model
		container.Name = "ClientGuideArrow"
	else
		local rootPart = clone :: BasePart
		rootPart.Name = "GuideArrowRoot"
		container = Instance.new("Model")
		container.Name = "ClientGuideArrow"
		rootPart.Parent = container
	end

	local beam = container:FindFirstChild("ArrowBeam", true)
	local startAtt = container:FindFirstChild("StartAttachment", true)
	local endAtt = container:FindFirstChild("EndAttachment", true)
	if not (beam and beam:IsA("Beam") and startAtt and startAtt:IsA("Attachment") and endAtt and endAtt:IsA("Attachment")) then
		warn("[GuideManager] GuideArrow needs ArrowBeam, StartAttachment, EndAttachment in hierarchy")
		container:Destroy()
		return
	end

	beam.Attachment0 = startAtt
	beam.Attachment1 = endAtt
	beam.Enabled = true

	ApplyGuideArrowPhysics(container)

	guideArrowModel = container
	guideArrowStartAttachment = startAtt
	guideArrowEndAttachment = endAtt
end

function GuideManager.Init()
	if initialized then
		return
	end
	if localPlayer == nil then
		warn("[GuideManager] Init skipped: LocalPlayer is nil")
		return
	end
	initialized = true

	TryCreateArrowModel()
	InitPickupCandidates()

	ClientMsg.ConnectLocalPlayerInfoInit(function()
		ForceRefreshGuideType()
	end)

	ClientMsg.ConnectLocalPlayerInventoryUpdate(function()
		ForceRefreshGuideType()
	end)

	ClientMsg.ConnectLocalPlayerSkillLevelUpdate(function()
		ForceRefreshGuideType()
	end)

	ClientMsg.ConnectBrainrotQueueUpdate(function()
		ForceRefreshGuideType()
	end)

	ClientMsg.ConnectPlayerHomeInfoUpdate(function(playerId: number)
		local lp = localPlayer
		if lp and playerId == lp.UserId then
			ForceRefreshGuideType()
		end
	end)

	ClientMsg.ConnectLocalPlayerCurrencyUpdate(function()
		ForceRefreshGuideType()
	end)

	ClientMsg.ConnectCloseWindow(function()
		ForceRefreshGuideType()
	end)

	NetMsg.ConnectNotifyGuideProgressInfo(function(guideProgressInfo: GameConfig.GuideProgressSaveInfo)
		for stepKey, isDone in pairs(guideProgressInfo.guideStepDoneMap) do
			if isDone == true then
				pendingCompleteGuideStepMap[stepKey] = nil
			end
		end
		ClientGameInfo.UpdateGuideProgressInfo(guideProgressInfo)
	end)

	ClientMsg.ConnectLocalPlayerJetpackInventoryUpdate(function()
		TryCompleteOwnedPurchaseGuideSteps()
		ForceRefreshGuideType()
	end)

	ClientMsg.ConnectLocalPlayerExEquipInventoryUpdate(function()
		TryCompleteOwnedPurchaseGuideSteps()
		ForceRefreshGuideType()
	end)

	ClientMsg.ConnectLocalPlayerJumpRunwayBestDistanceUpdate(function()
		ForceRefreshGuideType()
	end)

	ClientMsg.ConnectJumpRunWayEnterEscapeHudMode(function()
		ForceRefreshGuideType()
	end)

	runService.RenderStepped:Connect(function()
		RefreshGuideType()
		UpdateGuideArrow()
	end)
end

return GuideManager
