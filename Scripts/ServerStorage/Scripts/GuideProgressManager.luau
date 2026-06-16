--!strict
local GuideProgressManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:WaitForChild("ServerGameInfo"))

local ValidGuideStepKeyMap: { [string]: boolean } = {}

local function InitValidGuideStepKeyMap()
	for _, stepKey in pairs(GameConfig.GuideStepKey) do
		if type(stepKey) == "string" then
			ValidGuideStepKeyMap[stepKey] = true
		end
	end
end

local function OnRequestCompleteGuideStep(player: Player, stepKey: string)
	if not ValidGuideStepKeyMap[stepKey] then
		warn("[GuideProgressManager] invalid guide step:", stepKey)
		return
	end
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end
	local guideProgressInfo = playerInfo.guideProgressInfo
	if guideProgressInfo == nil then
		guideProgressInfo = {
			guideStepDoneMap = {},
			appearedGuideTypeInfo = {},
			exEquipBuyGuideCompletedCount = 0,
		}
		playerInfo.guideProgressInfo = guideProgressInfo
	end
	if guideProgressInfo.guideStepDoneMap[stepKey] == true then
		return
	end
	guideProgressInfo.guideStepDoneMap[stepKey] = true
	playerInfo.playerInfoChanged = true
	NetMsg.FireNotifyGuideProgressInfo(player, guideProgressInfo)
end

function GuideProgressManager.Init()
	InitValidGuideStepKeyMap()
	NetMsg.ConnectRequestCompleteGuideStep(OnRequestCompleteGuideStep)
end

return GuideProgressManager
