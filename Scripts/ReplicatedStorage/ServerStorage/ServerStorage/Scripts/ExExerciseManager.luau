--!strict
local ExExerciseManager = {}

local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:FindFirstChild("Scripts")
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:FindFirstChild("Scripts")
local sharedScripts = scripts:FindFirstChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

local LOG_PREFIX = "[ExExerciseManager]"

local function LogInfo(message: string)
	print(string.format("%s %s", LOG_PREFIX, message))
end

-- 正在锻炼的玩家: userId -> { equipId: number }
local exercisingPlayers: { [number]: { equipId: number } } = {}

local function OnRequestStartExercise(player: Player, equipId: number)
	if exercisingPlayers[player.UserId] ~= nil then
		LogInfo(string.format("StartRejected userId=%d reason=already_exercising", player.UserId))
		return
	end

	local equipData = GameConfig.ExEquipDataMap[equipId]
	if equipData == nil then
		warn(string.format("%s StartRejected userId=%d reason=invalid_equipId equipId=%d", LOG_PREFIX, player.UserId, equipId))
		return
	end

	exercisingPlayers[player.UserId] = { equipId = equipId }
	LogInfo(string.format("StartAccepted userId=%d equipId=%d type=%d", player.UserId, equipId, equipData.type))
	NetMsg.FireNotifyExerciseStart(player, equipId)
end

local function OnRequestStopExercise(player: Player)
	if exercisingPlayers[player.UserId] == nil then
		return
	end

	exercisingPlayers[player.UserId] = nil
	LogInfo(string.format("Stopped userId=%d", player.UserId))
	NetMsg.FireNotifyExerciseEnd(player)
end

function ExExerciseManager.Init()
	NetMsg.ConnectRequestStartExercise(OnRequestStartExercise)
	NetMsg.ConnectRequestStopExercise(OnRequestStopExercise)
	LogInfo("Init success")
end

return ExExerciseManager
