--!strict
local function PlayerSaveInfoVersionUpdate2(playerSaveInfo: any)
	if playerSaveInfo.rewardInfo == nil then
		playerSaveInfo.rewardInfo = {
			lastLoginTime = "",
			todayGameTime = 0,
			onlineRewardStateInfo = {},
		}
	end
	if playerSaveInfo.stateGame == nil then
		playerSaveInfo.stateGame = {
			startGameTick = -1,
		}
	end
	playerSaveInfo.dataVersion = 2
end

return PlayerSaveInfoVersionUpdate2
