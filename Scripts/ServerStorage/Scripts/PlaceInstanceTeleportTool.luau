--!strict
-- 项目专用：将玩家传送到指定 Place 的指定服务器实例（同 JobId 重连等场景）。
local PlaceInstanceTeleportTool = {}

local replicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local RetryAsync = require(coreSharedScripts:FindFirstChild("RetryAsync"))
local teleportService = game:GetService("TeleportService")
local players = game:GetService("Players")

local AttemptLimit = 5
local RetryDelay = 1
local FloodDelay = 15

type TeleportingPlayerMeta = {
	placeId: number,
	jobId: string,
}

local teleportingPlayers: { [number]: boolean } = {}
local teleportingPlayerMetaMap: { [number]: TeleportingPlayerMeta } = {}

function PlaceInstanceTeleportTool.IsPlayerTeleporting(playerId: number): boolean
	return teleportingPlayers[playerId] == true
end

local function MarkPlayersTeleporting(targetPlayers: { Player }, placeId: number, jobId: string)
	for _, player in targetPlayers do
		teleportingPlayers[player.UserId] = true
		teleportingPlayerMetaMap[player.UserId] = {
			placeId = placeId,
			jobId = jobId,
		}
	end
end

local function ClearPlayerTeleporting(playerId: number)
	teleportingPlayers[playerId] = nil
	teleportingPlayerMetaMap[playerId] = nil
end

local function GetTeleportOptionsForPlaceInstance(jobId: string, teleportOptions: TeleportOptions?): TeleportOptions
	local targetTeleportOptions = teleportOptions
	if targetTeleportOptions == nil then
		targetTeleportOptions = Instance.new("TeleportOptions")
	end
	targetTeleportOptions.ServerInstanceId = jobId
	return targetTeleportOptions
end

function PlaceInstanceTeleportTool.SafeTeleportToPlaceInstance(
	placeId: number,
	jobId: string,
	targetPlayers: { Player },
	teleportOptions: TeleportOptions?
): (boolean, any)
	if jobId == "" then
		return false, "empty jobId"
	end
	local targetTeleportOptions = GetTeleportOptionsForPlaceInstance(jobId, teleportOptions)
	MarkPlayersTeleporting(targetPlayers, placeId, jobId)
	return RetryAsync(function()
		return teleportService:TeleportAsync(placeId, targetPlayers, targetTeleportOptions)
	end, AttemptLimit, RetryDelay)
end

function PlaceInstanceTeleportTool.SafeTeleportToCurrentServer(
	targetPlayers: { Player },
	teleportOptions: TeleportOptions?
): (boolean, any)
	return PlaceInstanceTeleportTool.SafeTeleportToPlaceInstance(game.PlaceId, game.JobId, targetPlayers, teleportOptions)
end

local function HandleFailedTeleport(
	player: Instance,
	teleportResult: Enum.TeleportResult,
	errorMessage: string,
	_targetPlaceId: number,
	teleportOptions: TeleportOptions?
)
	if not player:IsA("Player") then
		return
	end

	local meta: TeleportingPlayerMeta? = teleportingPlayerMetaMap[player.UserId]
	if meta == nil then
		ClearPlayerTeleporting(player.UserId)
		return
	end

	if teleportResult == Enum.TeleportResult.Flooded then
		task.wait(FloodDelay)
	elseif teleportResult == Enum.TeleportResult.Failure then
		task.wait(RetryDelay)
	else
		ClearPlayerTeleporting(player.UserId)
		error(("Invalid place instance teleport [%s]: %s"):format(teleportResult.Name, errorMessage))
	end
	PlaceInstanceTeleportTool.SafeTeleportToPlaceInstance(meta.placeId, meta.jobId, { player }, teleportOptions)
end

local function OnPlayerRemoving(player: Player)
	ClearPlayerTeleporting(player.UserId)
end

teleportService.TeleportInitFailed:Connect(HandleFailedTeleport)
players.PlayerRemoving:Connect(OnPlayerRemoving)

return PlaceInstanceTeleportTool
