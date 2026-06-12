--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local BrainrotQueueManager = require(serverScripts:FindFirstChild("BrainrotQueueManager"))
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))

local function GiveOnlineReward(player: Player, reward: GameConfig.OnlineRewardData)
	local rewardInfo: GameConfig.RewardInfo = {
		rewardType = reward.rewardType,
		rewardId = reward.rewardId,
		rewardCount = reward.rewardCount,
		rewardSource = GameConfig.ItemCountChangeReason.GainFromOnline,
	}

	if rewardInfo.rewardType == GameConfig.RewardType.Currency then
		ServerGameInfo.UpdatePlayerCurrency(
			player,
			rewardInfo.rewardId,
			rewardInfo.rewardCount,
			GameConfig.ItemCountChangeReason.GainFromOnline
		)
		return
	end

	if rewardInfo.rewardType == GameConfig.RewardType.Brainrot then
		local config = GameConfig.BrainrotIdMap[rewardInfo.rewardId]
		if config then
			for _ = 1, rewardInfo.rewardCount do
				BrainrotQueueManager.AddItem(
					player,
					rewardInfo.rewardId,
					config.quality,
					rewardInfo.rewardLv or 1,
					false,
					GameConfig.ItemType.Brainrot,
					false,
					nil,
					nil,
					nil,
					GameConfig.ModelGetSource.OnlineReward,
					0
				)
			end
		end
	end
end

local function OnPlayerRequestUpdateRewardInfo(player: Player, indexs: { number }, stateNew: number, rewardType: number)
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local indexs0: { number } = {}
	for _, i in indexs do
		if rewardType ~= GameConfig.RewardEnum.onlineTime then
			continue
		end

		local reward = GameConfig.OnlineRewardDataList[i]
		if reward == nil then
			continue
		end

		if stateNew == GameConfig.RewardState.HasGot then
			local todayGameTimeNow = os.time()
				- playerInfo.stateGame.startGameTick
				+ playerInfo.rewardInfo.todayGameTime
			local rewardState = playerInfo.rewardInfo.onlineRewardStateInfo[tostring(i)]
			if rewardState == GameConfig.RewardState.CanGet
				or (rewardState == nil and todayGameTimeNow >= reward.unlockTime)
			then
				table.insert(indexs0, i)
				GiveOnlineReward(player, reward)
			end
		elseif stateNew == GameConfig.RewardState.CanGet then
			local todayGameTimeNow = os.time()
				- playerInfo.stateGame.startGameTick
				+ playerInfo.rewardInfo.todayGameTime
			if todayGameTimeNow >= reward.unlockTime then
				table.insert(indexs0, i)
			end
		end
	end

	ServerGameInfo.PlayerUpdateRewardInfo(player, indexs0, stateNew, rewardType)
end

NetMsg.ConnectRequestUpdateReward(OnPlayerRequestUpdateRewardInfo)
