--!strict
local ExEquipManager = {}

local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

local LOG_PREFIX = "[ExEquipManager]"

-- 锻炼 JumpPower 递增
local EXERCISE_JUMP_POWER_INTERVAL = GameConfig.JumpPowerExerciseInterval
local exerciseRunningMap: { [number]: boolean } = {}

local function LogInfo(message: string)
	print(string.format("%s %s", LOG_PREFIX, message))
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

	-- 取所有 costType == GroupReward 的器材 ID
	local groupRewardEquipIdList: { number } = {}
	for _, equipData in GameConfig.ExEquipDataMap do
		if equipData.costType == GameConfig.CostType.GroupReward then
			table.insert(groupRewardEquipIdList, equipData.id)
		end
	end

	if #groupRewardEquipIdList == 0 then
		warn(string.format("%s Group reward exEquip list is empty", LOG_PREFIX))
		return
	end

	-- 检查是否至少有一个群组奖励器材未拥有，避免重复通知
	local hasAnyToClaim = false
	for _, rewardEquipId in ipairs(groupRewardEquipIdList) do
		local equipIdStr = tostring(rewardEquipId)
		if not playerInfo.exEquipInventory.ownedList[equipIdStr] then
			hasAnyToClaim = true
			break
		end
	end

	if not hasAnyToClaim then
		LogInfo(string.format("GroupReward already claimed all userId=%d", player.UserId))
		return
	end

	for _, rewardEquipId in ipairs(groupRewardEquipIdList) do
		ServerGameInfo.AddExEquipToInventory(player, tostring(rewardEquipId))
	end
	LogInfo(string.format("GroupRewardClaimed userId=%d count=%d", player.UserId, #groupRewardEquipIdList))
end

-- 处理客户端请求开始锻炼
function ExEquipManager.OnRequestStartExercise(player: Player, equipId: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local equipData = GameConfig.ExEquipDataMap[equipId]
	if equipData == nil then
		return
	end

	local userId = player.UserId
	exerciseRunningMap[userId] = true

	task.spawn(function()
		while exerciseRunningMap[userId] do
			ServerGameInfo.UpdatePlayerJumpPower(player, equipData.ability)
			task.wait(EXERCISE_JUMP_POWER_INTERVAL)
		end
	end)

	NetMsg.FireNotifyExerciseStart(player, equipId)
	LogInfo(string.format("ExerciseStarted userId=%d equipId=%d", userId, equipId))
end

-- 处理客户端请求结束锻炼
function ExEquipManager.OnRequestStopExercise(player: Player)
	local userId = player.UserId
	exerciseRunningMap[userId] = nil
	NetMsg.FireNotifyExerciseEnd(player)
	LogInfo(string.format("ExerciseStopped userId=%d", userId))
end

function ExEquipManager.Init()
	NetMsg.ConnectRequestBuyExEquip(ExEquipManager.OnRequestBuyExEquip)
	NetMsg.ConnectRequestUpdateExEquipUsing(ExEquipManager.OnRequestUpdateExEquipUsing)
	NetMsg.ConnectRequestClaimGroupReward(ExEquipManager.OnRequestClaimGroupReward)
	NetMsg.ConnectRequestStartExercise(ExEquipManager.OnRequestStartExercise)
	NetMsg.ConnectRequestStopExercise(ExEquipManager.OnRequestStopExercise)
	LogInfo("Init success")
end

return ExEquipManager
