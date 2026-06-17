--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))

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
	local guideProgressInfo = playerSaveInfo.guideProgressInfo
	if guideProgressInfo == nil then
		guideProgressInfo = {
			guideStepDoneMap = {},
			appearedGuideTypeInfo = {},
			--exEquipBuyGuideCompletedCount = 0,
		}
		playerSaveInfo.guideProgressInfo = guideProgressInfo
	end
	if guideProgressInfo.exEquipBuyGuideCompletedCount == nil then
		local exEquipInventory = playerSaveInfo.exEquipInventory
		local ownedList = if exEquipInventory ~= nil then exEquipInventory.ownedList else nil
		local ownedGuideExEquipCount = 0
		for _, targetExEquipId in ipairs(GameConfig.GuideTargetExEquipIdList) do
			if ownedList ~= nil and ownedList[tostring(targetExEquipId)] == true then
				ownedGuideExEquipCount += 1
			end
		end
		guideProgressInfo.exEquipBuyGuideCompletedCount =
			math.clamp(ownedGuideExEquipCount, 0, #GameConfig.GuideTargetExEquipIdList)
	end
	playerSaveInfo.dataVersion = 2
end

return PlayerSaveInfoVersionUpdate2
