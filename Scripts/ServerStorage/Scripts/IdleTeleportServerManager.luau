--!strict
local IdleTeleportServerManager = {}

local players = game:GetService("Players")
local serverStorage = game:GetService("ServerStorage")
local replicatedStorage = game:GetService("ReplicatedStorage")

local serverScripts = serverStorage:WaitForChild("Scripts")
local PlaceInstanceTeleportTool = require(serverScripts:WaitForChild("PlaceInstanceTeleportTool"))

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))

type PlayerIdleTeleportState = {
	lastIdleTeleportClock: number,
	pendingIdleTeleport: boolean,
}

local playerIdleStateMap: { [number]: PlayerIdleTeleportState } = {}
local teleportOptions = Instance.new("TeleportOptions")

local function GetOrCreatePlayerIdleState(playerId: number): PlayerIdleTeleportState
	local state = playerIdleStateMap[playerId]
	if state == nil then
		state = {
			lastIdleTeleportClock = -math.huge,
			pendingIdleTeleport = false,
		}
		playerIdleStateMap[playerId] = state
	end
	return state
end

local function IsIdleTeleportBlocked(player: Player): boolean
	return player:GetAttribute("JumpRunwayActive") == true
end

local function TryProcessIdleTeleport(player: Player, nowClock: number, reason: string)
	local state = GetOrCreatePlayerIdleState(player.UserId)
	if state.pendingIdleTeleport then
		return
	end
	local cooldownRemainSec = GameConfig.IdleTeleportCooldownSec - (nowClock - state.lastIdleTeleportClock)
	if cooldownRemainSec > 0 then
		return
	end
	if IsIdleTeleportBlocked(player) then
		return
	end

	if game.JobId == "" then
		warn("[IdleTeleportServerManager] Skip idle teleport in Studio (empty JobId)")
		return
	end

	state.pendingIdleTeleport = true
	local teleportSuccess, teleportResult = PlaceInstanceTeleportTool.SafeTeleportToCurrentServer({ player }, teleportOptions)
	if teleportSuccess then
		state.lastIdleTeleportClock = nowClock
		return
	end
	state.pendingIdleTeleport = false
	warn(string.format(
		"[IdleTeleportServerManager] IdleTeleportFailed userId=%d reason=%s err=%s",
		player.UserId,
		reason,
		tostring(teleportResult)
	))
end

local function OnRequestIdleServerTeleport(player: Player)
	if IsIdleTeleportBlocked(player) then
		return
	end
	TryProcessIdleTeleport(player, os.clock(), "client_idle_request")
end

function IdleTeleportServerManager.Init()
	NetMsg.ConnectRequestIdleServerTeleport(OnRequestIdleServerTeleport)

	players.PlayerRemoving:Connect(function(player: Player)
		playerIdleStateMap[player.UserId] = nil
	end)
end

return IdleTeleportServerManager
