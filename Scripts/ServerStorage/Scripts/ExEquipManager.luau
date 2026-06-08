--!strict
local ExEquipManager = {}

local players: Players = game:GetService("Players")
local runService: RunService = game:GetService("RunService")
local workspace: Workspace = game:GetService("Workspace")
local marketplaceService: MarketplaceService = game:GetService("MarketplaceService")
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local AnalyticsTool = require(serverScripts:FindFirstChild("AnalyticsTool"))
local BrainrotQueueManager = require(serverScripts:FindFirstChild("BrainrotQueueManager"))

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

local modelsFolder = replicatedStorage:FindFirstChild("Models")
local exEquipModelsFolder: Folder? = if modelsFolder ~= nil then modelsFolder:FindFirstChild("ExEquip") :: Folder? else nil

local LOG_PREFIX = "[ExEquipManager]"

-- 锻炼 JumpPower 递增
local EXERCISE_JUMP_POWER_INTERVAL = GameConfig.JumpPowerExerciseInterval
local ClickRewardConfig = GameConfig.ExerciseClickReward
-- 人物躯干高度（HumanoidRootPart 到脚底的参考偏移）
local CHARACTER_TORSO_HEIGHT: number = 3
local ACTIVE_EXERCISE_EQUIP_NAME = "ActiveExerciseEquip"
local EXERCISE_OWNER_USER_ID_ATTR = "ExerciseOwnerUserId"
local EXERCISING_ATTR = "Exercising"

local exerciseRunningMap: { [number]: boolean } = {}
local exerciseSessionMap: { [number]: number } = {}
local exerciseClickRewardNextAllowedAtMap: { [number]: number } = {}
local activeExerciseModelMap: { [number]: Model } = {}
local activeExerciseWorldPivotMap: { [number]: CFrame } = {}
local exerciseModelPivotLockConnection: RBXScriptConnection? = nil

local function LogInfo(message: string)
	print(string.format("%s %s", LOG_PREFIX, message))
end

local function IsBikeExEquipType(exEquipType: number): boolean
	return exEquipType == GameConfig.ExEquipType.Bike or exEquipType == GameConfig.ExEquipType.Bike2
end

local function AnchorExerciseModel(equipmentModel: Model)
	for _, descendant in equipmentModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

local function DestroyExerciseModel(userId: number)
	local equipmentModel = activeExerciseModelMap[userId]
	if equipmentModel ~= nil then
		equipmentModel:Destroy()
		activeExerciseModelMap[userId] = nil
	end
	activeExerciseWorldPivotMap[userId] = nil
end

local function SetPartNetworkOwner(part: BasePart, owner: Player)
	local ok, canSet = pcall(function()
		return part:CanSetNetworkOwnership()
	end)
	if not ok or not canSet then
		return
	end

	pcall(function()
		part:SetNetworkOwner(owner)
	end)
end

local function SetPartNetworkOwnershipAuto(part: BasePart)
	local ok, canSet = pcall(function()
		return part:CanSetNetworkOwnership()
	end)
	if not ok or not canSet then
		return
	end

	pcall(function()
		part:SetNetworkOwnershipAuto()
	end)
end

local function SetInstanceNetworkOwner(instance: Instance, owner: Player)
	if instance:IsA("BasePart") then
		SetPartNetworkOwner(instance, owner)
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			SetPartNetworkOwner(descendant, owner)
		end
	end
end

local function SetInstanceNetworkOwnershipAuto(instance: Instance)
	if instance:IsA("BasePart") then
		SetPartNetworkOwnershipAuto(instance)
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			SetPartNetworkOwnershipAuto(descendant)
		end
	end
end

local function ApplyExerciseNetworkOwnership(player: Player, character: Model, equipmentModel: Model)
	SetInstanceNetworkOwner(character, player)
	SetInstanceNetworkOwner(equipmentModel, player)
end

local function ReleaseExerciseNetworkOwnership(player: Player)
	local character = player.Character
	if character ~= nil then
		SetInstanceNetworkOwnershipAuto(character)
	end

	local equipmentModel = activeExerciseModelMap[player.UserId]
	if equipmentModel ~= nil then
		SetInstanceNetworkOwnershipAuto(equipmentModel)
	end
end

local function EnsureExerciseModelPivotLockConnection()
	if exerciseModelPivotLockConnection ~= nil then
		return
	end
	exerciseModelPivotLockConnection = runService.Heartbeat:Connect(function()
		for userId, equipmentModel in activeExerciseModelMap do
			local worldPivot = activeExerciseWorldPivotMap[userId]
			if worldPivot ~= nil and equipmentModel.Parent ~= nil then
				equipmentModel:PivotTo(worldPivot)
			end
		end
	end)
end

local function GetBikeLowerTorsoOffset(character: Model, hrp: BasePart): Vector3
	local lowerTorso: BasePart? = character:FindFirstChild("LowerTorso") :: BasePart?
	if lowerTorso == nil then
		return Vector3.zero
	end

	local hrpRootAttachment: Attachment? = hrp:FindFirstChild("RootRigAttachment") :: Attachment?
	local lowerTorsoRootAttachment: Attachment? = lowerTorso:FindFirstChild("RootRigAttachment") :: Attachment?
	if hrpRootAttachment ~= nil and lowerTorsoRootAttachment ~= nil then
		return hrp.CFrame:VectorToWorldSpace(hrpRootAttachment.Position - lowerTorsoRootAttachment.Position)
	end

	return lowerTorso.Position - hrp.Position
end

local function GetExerciseStandCFrame(equipmentModel: Model, equipData: GameConfig.ExEquipData, character: Model, hrp: BasePart): CFrame
	local modelRootPart: BasePart? = equipmentModel.PrimaryPart
	local rootCf: CFrame
	if modelRootPart ~= nil then
		rootCf = modelRootPart.CFrame
	else
		rootCf = equipmentModel:GetPivot()
	end

	local forwardZ: Vector3 = -rootCf.LookVector
	local rootPos: Vector3 = rootCf.Position

	local lowerTorsoOffset: Vector3 = Vector3.zero
	local lowerTorso: BasePart? = character:FindFirstChild("LowerTorso") :: BasePart?
	if lowerTorso ~= nil then
		lowerTorsoOffset = if IsBikeExEquipType(equipData.type) then GetBikeLowerTorsoOffset(character, hrp) else lowerTorso.Position - hrp.Position
	end

	local standPos: Vector3
	if equipData.type == GameConfig.ExEquipType.Treadmill or IsBikeExEquipType(equipData.type) then
		local exerciseAttachment: Attachment? = equipmentModel:FindFirstChild("ExerciseAttachment") :: Attachment?
		if exerciseAttachment ~= nil then
			local attachPos: Vector3 = exerciseAttachment.WorldPosition
			if IsBikeExEquipType(equipData.type) then
				standPos = attachPos - lowerTorsoOffset
			else
				standPos = Vector3.new(attachPos.X, attachPos.Y + CHARACTER_TORSO_HEIGHT, attachPos.Z)
			end
		else
			standPos = Vector3.new(rootPos.X, rootPos.Y + CHARACTER_TORSO_HEIGHT, rootPos.Z)
		end
	else
		local rayOrigin: Vector3 = rootPos + Vector3.new(0, 10, 0)
		local rayDirection: Vector3 = Vector3.new(0, -20, 0)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Include
		rayParams.FilterDescendantsInstances = { equipmentModel }

		local rayResult = workspace:Raycast(rayOrigin, rayDirection, rayParams)

		local modelTopY: number
		if rayResult ~= nil then
			modelTopY = rayResult.Position.Y
		else
			local cframe: CFrame, size: Vector3 = equipmentModel:GetBoundingBox()
			modelTopY = cframe.Y + size.Y / 2
		end
		standPos = Vector3.new(rootPos.X, modelTopY + CHARACTER_TORSO_HEIGHT, rootPos.Z)
	end
	return CFrame.lookAt(standPos, standPos + forwardZ)
end

local function DisableExerciseModelPrompts(equipmentModel: Model)
	for _, descendant in equipmentModel:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			descendant.Enabled = false
		end
	end
end

local function MoveExerciseModelStandXzToPlayer(equipmentModel: Model, equipData: GameConfig.ExEquipData, character: Model, hrp: BasePart)
	local standCf = GetExerciseStandCFrame(equipmentModel, equipData, character, hrp)
	local deltaXz = Vector3.new(hrp.Position.X - standCf.Position.X, 0, hrp.Position.Z - standCf.Position.Z)
	equipmentModel:PivotTo(equipmentModel:GetPivot() + deltaXz)
end

local function MoveExerciseModelPrimaryPartToGround(equipmentModel: Model, character: Model)
	local primaryPart = equipmentModel.PrimaryPart
	if primaryPart == nil then
		warn(string.format("%s Active exercise equipment missing PrimaryPart", LOG_PREFIX))
		return
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { equipmentModel, character }

	local rayOrigin = primaryPart.Position + Vector3.new(0, primaryPart.Size.Y + 20, 0)
	local rayDirection = Vector3.new(0, -(primaryPart.Size.Y + 80), 0)
	local rayResult = workspace:Raycast(rayOrigin, rayDirection, rayParams)
	if rayResult == nil then
		return
	end

	local targetPrimaryPartY = rayResult.Position.Y + primaryPart.Size.Y * 0.5
	local deltaY = targetPrimaryPartY - primaryPart.Position.Y
	equipmentModel:PivotTo(equipmentModel:GetPivot() + Vector3.new(0, deltaY, 0))
end

local function CreateExerciseModelAtPlayer(player: Player, equipData: GameConfig.ExEquipData, character: Model, hrp: BasePart): Model?
	if exEquipModelsFolder == nil then
		warn(string.format("%s ExEquip models folder not found", LOG_PREFIX))
		return nil
	end

	local sourceModel = exEquipModelsFolder:FindFirstChild(equipData.resourceName) :: Model?
	if sourceModel == nil then
		warn(string.format("%s ExEquip model not found: %s", LOG_PREFIX, equipData.resourceName))
		return nil
	end

	local lookVector = hrp.CFrame.LookVector
	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatLook.Magnitude <= 0 then
		flatLook = Vector3.new(0, 0, -1)
	end

	local equipmentModel = sourceModel:Clone()
	equipmentModel.Name = ACTIVE_EXERCISE_EQUIP_NAME
	equipmentModel:SetAttribute(EXERCISE_OWNER_USER_ID_ATTR, player.UserId)
	AnchorExerciseModel(equipmentModel)
	-- 挂到玩家角色下，避免 Invisicam 将本地玩家的健身器材当作遮挡物隐藏
	equipmentModel.Parent = character
	equipmentModel:PivotTo(CFrame.lookAt(hrp.Position, hrp.Position - flatLook.Unit))
	DisableExerciseModelPrompts(equipmentModel)
	MoveExerciseModelStandXzToPlayer(equipmentModel, equipData, character, hrp)
	MoveExerciseModelPrimaryPartToGround(equipmentModel, character)
	EnsureExerciseModelPivotLockConnection()
	return equipmentModel
end

local function StopExerciseForPlayer(player: Player, logReason: string)
	local userId = player.UserId
	local wasExercising = exerciseRunningMap[userId] == true
	exerciseSessionMap[userId] = (exerciseSessionMap[userId] or 0) + 1
	exerciseRunningMap[userId] = nil
	exerciseClickRewardNextAllowedAtMap[userId] = nil
	player:SetAttribute(EXERCISING_ATTR, false)
	ReleaseExerciseNetworkOwnership(player)
	DestroyExerciseModel(userId)
	if wasExercising then
		ServerGameInfo.ApplyWalkSpeed(player)
		NetMsg.FireNotifyExerciseEnd(player)
		LogInfo(string.format("ExerciseStopped userId=%d reason=%s", userId, logReason))
	end
end

local function CanAffordExEquip(playerInfo: GameConfig.PlayerInfo, equipData: GameConfig.ExEquipData): boolean
	local coinKey = tostring(GameConfig.CurrencyType.Coin)
	local currentCoins = playerInfo.currencies[coinKey] or 0
	local coinCost = equipData.costCoin

	if equipData.costType == GameConfig.CostType.Coin or equipData.costType == GameConfig.CostType.CoinOrRb then
		return currentCoins >= coinCost
	end
	return false
end

local function SpendExEquipCost(player: Player, equipData: GameConfig.ExEquipData)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local coinKey = tostring(GameConfig.CurrencyType.Coin)
	local currentCoins = playerInfo.currencies[coinKey] or 0
	local coinCost = equipData.costCoin

	if
		(equipData.costType == GameConfig.CostType.Coin or equipData.costType == GameConfig.CostType.CoinOrRb)
		and currentCoins >= coinCost
	then
		ServerGameInfo.UpdatePlayerCurrency(player, GameConfig.CurrencyType.Coin, -coinCost, GameConfig.ItemCountChangeReason.SpendOnUpgradeBrainrot)
	end
end

local function GetMoneyCount(playerInfo: GameConfig.PlayerInfo): number
	return playerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
end

local function GetExerciseJumpPowerInterval(playerInfo: GameConfig.PlayerInfo): number
	local multiplier = GameConfig.GetBuffMultiplier(playerInfo.buffInfo, GameConfig.BuffType.ExerciseEfficiency)
	return EXERCISE_JUMP_POWER_INTERVAL / multiplier
end

-- 处理客户端购买器材请求
function ExEquipManager.OnRequestBuyExEquip(player: Player, equipId: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local equipData = GameConfig.ExEquipDataMap[equipId]
	if equipData == nil then
		warn(string.format("%s ExEquip data not found for id: %d", LOG_PREFIX, equipId))
		return
	end

	local equipIdStr = tostring(equipId)
	if playerInfo.exEquipInventory.ownedList[equipIdStr] then
		LogInfo(string.format("BuyRejected userId=%d reason=already_owned equipId=%d", player.UserId, equipId))
		return
	end

	if CanAffordExEquip(playerInfo, equipData) then
		LogInfo(string.format("BuyAccepted userId=%d equipId=%d coinCost=%d costType=%d", player.UserId, equipId, equipData.costCoin, equipData.costType))
		SpendExEquipCost(player, equipData)
		-- 添加器材
		ServerGameInfo.AddExEquipToInventory(player, equipIdStr)
		-- 自动装备
		ExEquipManager.OnRequestUpdateExEquipUsing(player, equipId)
		AnalyticsTool.LogGymGet(player, equipId, GetMoneyCount(playerInfo), 0)
	else
		local rejectReason = "insufficient_currency"
		if equipData.costType == GameConfig.CostType.Rb then
			rejectReason = "rb_purchase_only"
		elseif equipData.costType == GameConfig.CostType.GroupReward then
			rejectReason = "group_reward_only"
		end
		LogInfo(string.format("BuyRejected userId=%d reason=%s equipId=%d", player.UserId, rejectReason, equipId))
	end
end

function ExEquipManager.OnRequestBuyExEquipPaid(player: Player, equipId: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local equipData = GameConfig.ExEquipDataMap[equipId]
	if equipData == nil or equipData.productId <= 0 then
		warn(string.format("%s PaidBuyRejected userId=%d reason=invalid_product equipId=%d", LOG_PREFIX, player.UserId, equipId))
		return
	end

	if playerInfo.exEquipInventory.ownedList[tostring(equipId)] then
		LogInfo(string.format("PaidBuyRejected userId=%d reason=already_owned equipId=%d", player.UserId, equipId))
		return
	end

	if not ServerGameInfo.SetPendingPaidShopItem(player, GameConfig.ItemType.ExEquip, equipId, equipData.productId) then
		LogInfo(string.format("PaidBuyRejected userId=%d reason=pending_failed equipId=%d", player.UserId, equipId))
		return
	end

	marketplaceService:PromptProductPurchase(player, equipData.productId)
end

-- 处理客户端更换器材请求
function ExEquipManager.OnRequestUpdateExEquipUsing(player: Player, equipId: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local equipIdStr = tostring(equipId)
	if not playerInfo.exEquipInventory.ownedList[equipIdStr] then
		warn(string.format("%s EquipRejected userId=%d reason=not_owned equipId=%d", LOG_PREFIX, player.UserId, equipId))
		return
	end

	LogInfo(string.format("EquipAccepted userId=%d equipId=%d", player.UserId, equipId))
	StopExerciseForPlayer(player, "switch_equip")
	ServerGameInfo.SetCurrentExEquip(player, equipIdStr)
end

-- 处理客户端领取群组奖励请求
function ExEquipManager.OnRequestClaimGroupReward(player: Player, isInGroup: boolean)
	if not isInGroup then
		return
	end

	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	if playerInfo.hasClaimedGroupReward then
		LogInfo(string.format("GroupReward already claimed userId=%d", player.UserId))
		return
	end

	local groupRewardConfig = GameConfig.GetGroupRewardBrainrotConfig()
	local brainrotData = GameConfig.BrainrotIdMap[groupRewardConfig.brainrotId]
	if brainrotData == nil then
		warn(
			string.format(
				"%s Group reward brainrot data not found id=%d",
				LOG_PREFIX,
				groupRewardConfig.brainrotId
			)
		)
		return
	end

	local success = BrainrotQueueManager.AddItem(
		player,
		groupRewardConfig.brainrotId,
		brainrotData.quality,
		1,
		true,
		GameConfig.ItemType.Brainrot,
		false,
		nil,
		nil,
		nil,
		nil,
		nil,
		nil,
		groupRewardConfig.variantId
	)
	if success then
		playerInfo.hasClaimedGroupReward = true
		playerInfo.playerInfoChanged = true
		NetMsg.FireNotifyPlayerClaimedGroupReward(player)
		LogInfo(
			string.format(
				"GroupRewardClaimed userId=%d brainrotId=%d variantId=%d",
				player.UserId,
				groupRewardConfig.brainrotId,
				groupRewardConfig.variantId
			)
		)
	end
end

-- 处理客户端请求开始锻炼
function ExEquipManager.OnRequestStartExercise(player: Player, equipId: number)
	local userId = player.UserId
	if exerciseRunningMap[userId] then
		LogInfo(string.format("StartRejected userId=%d reason=already_exercising", userId))
		return
	end

	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local equipIdStr = tostring(equipId)
	if playerInfo.exEquipInventory.currentId ~= equipIdStr then
		LogInfo(string.format("StartRejected userId=%d reason=not_current equipId=%d", userId, equipId))
		return
	end
	if not playerInfo.exEquipInventory.ownedList[equipIdStr] then
		LogInfo(string.format("StartRejected userId=%d reason=not_owned equipId=%d", userId, equipId))
		return
	end

	local equipData = GameConfig.ExEquipDataMap[equipId]
	if equipData == nil then
		return
	end

	local character: Model? = player.Character
	local hrp: BasePart? = if character ~= nil then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if character == nil or hrp == nil then
		LogInfo(string.format("StartRejected userId=%d reason=no_character", userId))
		return
	end

	local equipmentModel = CreateExerciseModelAtPlayer(player, equipData, character, hrp)
	if equipmentModel == nil then
		LogInfo(string.format("StartRejected userId=%d reason=model_create_failed equipId=%d", userId, equipId))
		return
	end

	activeExerciseModelMap[userId] = equipmentModel
	activeExerciseWorldPivotMap[userId] = equipmentModel:GetPivot()
	exerciseRunningMap[userId] = true
	exerciseClickRewardNextAllowedAtMap[userId] = os.clock() + ClickRewardConfig.ServerMinInterval
	player:SetAttribute(EXERCISING_ATTR, true)
	ApplyExerciseNetworkOwnership(player, character, equipmentModel)

	local sessionId = (exerciseSessionMap[userId] or 0) + 1
	exerciseSessionMap[userId] = sessionId

	if not IsBikeExEquipType(equipData.type) then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil then
			humanoid.WalkSpeed = GameConfig.ExerciseRunWalkSpeed
		end
	end

	task.spawn(function()
		local capturedSessionId = sessionId
		while exerciseSessionMap[userId] == capturedSessionId do
			task.wait(GetExerciseJumpPowerInterval(playerInfo))
			if exerciseSessionMap[userId] ~= capturedSessionId then
				break
			end
			ServerGameInfo.UpdatePlayerJumpPower(player, equipData.ability)
		end
	end)

	NetMsg.FireNotifyExerciseStart(player, equipId)
	LogInfo(string.format("ExerciseStarted userId=%d equipId=%d", userId, equipId))
end

-- 处理客户端请求结束锻炼
function ExEquipManager.OnRequestStopExercise(player: Player)
	StopExerciseForPlayer(player, "request")
end

function ExEquipManager.OnRequestExerciseClickReward(player: Player)
	local userId = player.UserId
	if exerciseRunningMap[userId] ~= true then
		LogInfo(string.format("ClickRewardRejected userId=%d reason=not_exercising", userId))
		return
	end

	local now = os.clock()
	local nextAllowedAt = exerciseClickRewardNextAllowedAtMap[userId] or math.huge
	if now < nextAllowedAt then
		LogInfo(string.format("ClickRewardRejected userId=%d reason=cooldown", userId))
		return
	end

	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local equipId = tonumber(playerInfo.exEquipInventory.currentId)
	if equipId == nil then
		LogInfo(string.format("ClickRewardRejected userId=%d reason=no_current_equip", userId))
		return
	end

	local equipData = GameConfig.ExEquipDataMap[equipId]
	if equipData == nil then
		LogInfo(string.format("ClickRewardRejected userId=%d reason=equip_not_found equipId=%d", userId, equipId))
		return
	end

	ServerGameInfo.UpdatePlayerJumpPower(player, equipData.ability * ClickRewardConfig.RewardMultiplier)
	exerciseClickRewardNextAllowedAtMap[userId] = now + ClickRewardConfig.ServerMinInterval
end

function ExEquipManager.Init()
	NetMsg.ConnectRequestBuyExEquip(ExEquipManager.OnRequestBuyExEquip)
	NetMsg.ConnectRequestBuyExEquipPaid(ExEquipManager.OnRequestBuyExEquipPaid)
	NetMsg.ConnectRequestUpdateExEquipUsing(ExEquipManager.OnRequestUpdateExEquipUsing)
	NetMsg.ConnectRequestClaimGroupReward(ExEquipManager.OnRequestClaimGroupReward)
	NetMsg.ConnectRequestStartExercise(ExEquipManager.OnRequestStartExercise)
	NetMsg.ConnectRequestStopExercise(ExEquipManager.OnRequestStopExercise)
	NetMsg.ConnectRequestExerciseClickReward(ExEquipManager.OnRequestExerciseClickReward)

	players.PlayerRemoving:Connect(function(player: Player)
		StopExerciseForPlayer(player, "player_leaving")
	end)

	local function BindPlayerCharacterCleanup(player: Player)
		player.CharacterRemoving:Connect(function()
			StopExerciseForPlayer(player, "character_removing")
		end)
	end

	for _, player in players:GetPlayers() do
		BindPlayerCharacterCleanup(player)
	end
	players.PlayerAdded:Connect(BindPlayerCharacterCleanup)

	LogInfo("Init success")
end

return ExEquipManager
