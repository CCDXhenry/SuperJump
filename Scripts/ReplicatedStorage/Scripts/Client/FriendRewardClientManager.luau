--!strict
local FriendRewardClientManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local players: Players = game:GetService("Players")
local starterGui: StarterGui = game:GetService("StarterGui")

local function HandleFriendInThisServerChanged(localPlayerInfo: GameConfig.ClientLocalPlayerInfo, playerId: number, isFriend: boolean)
	if isFriend then
		if not localPlayerInfo.friendInThisServerPlayerIdMap[playerId] then
			ClientGameInfo.AddLocalPlayerFriendInThisServer(playerId)
			NetMsg.FireRequestAddFriendInThisServer(playerId)
		end
	else
		if localPlayerInfo.friendInThisServerPlayerIdMap[playerId] then
			ClientGameInfo.RemoveLocalPlayerFriendInThisServer(playerId)
			NetMsg.FireRequestRemoveFriendInThisServer(playerId)
		end
	end
end

local function OnLocalPlayerInfoInit()
	local localPlayerInfo: GameConfig.ClientLocalPlayerInfo? = ClientGameInfo.GetLocalPlayerInfo()
	local paramConfig = GameConfig.GetFriendRewardBuffParamConfig()
	if localPlayerInfo == nil or players.LocalPlayer == nil or paramConfig == nil then
		return
	end
	for _, player: Player in players:GetPlayers() do
		if player.UserId == players.LocalPlayer.UserId then
			continue
		end
		task.spawn(function()
			local success: boolean, result: any = pcall(function()
				return players.LocalPlayer:IsFriendsWithAsync(player.UserId)
			end)
			local isFriend: boolean = success and result
			if players:GetPlayerByUserId(player.UserId) == nil then
				return
			end
			HandleFriendInThisServerChanged(localPlayerInfo, player.UserId, isFriend)
		end)
	end
	task.spawn(function()
		while localPlayerInfo ~= nil do
			local success: boolean, result: any = pcall(function()
				return players.LocalPlayer:GetFriendsOnlineAsync()
			end)
			if success then
				local friendsPlayingSameGameCount: number = 0
				local onlineFriendIdMap2: { [number]: boolean } = {}
				for _: number, friend in result do
					onlineFriendIdMap2[friend.VisitorId] = true
					if
						friend.LocationType == paramConfig.onlineInGameLocationType
						and friend.PlaceId ~= nil
						and friend.PlaceId == GameConfig.GamePlaceId
					then
						friendsPlayingSameGameCount += 1
					end
				end
				localPlayerInfo.onlineFriendIdMap = onlineFriendIdMap2
				ClientGameInfo.UpdateFriendsPlayingSameGameCount(friendsPlayingSameGameCount)
				NetMsg.FireRequestUpdateFriendsPlayingSameGameCount(friendsPlayingSameGameCount)
			else
				warn(result)
			end
			task.wait(paramConfig.updateInterval)
		end
	end)
end

local function OnPlayerAdded(player: Player)
	if players.LocalPlayer == nil or player.UserId == players.LocalPlayer.UserId then
		return
	end
	local localPlayerInfo: GameConfig.ClientLocalPlayerInfo? = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil then
		return
	end
	local success: boolean, result: any = pcall(function()
		return players.LocalPlayer:IsFriendsWithAsync(player.UserId)
	end)
	local isFriend: boolean = success and result
	if players:GetPlayerByUserId(player.UserId) == nil then
		return
	end
	HandleFriendInThisServerChanged(localPlayerInfo, player.UserId, isFriend)
end

local function OnPlayerRemoving(player: Player)
	if players.LocalPlayer == nil or player.UserId == players.LocalPlayer.UserId then
		return
	end
	local localPlayerInfo: GameConfig.ClientLocalPlayerInfo? = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil then
		return
	end
	HandleFriendInThisServerChanged(localPlayerInfo, player.UserId, false)
end

local function OnPlayerFriended(friendedPlayer: Player)
	local localPlayerInfo: GameConfig.ClientLocalPlayerInfo? = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil or localPlayerInfo.friendInThisServerPlayerIdMap[friendedPlayer.UserId] then
		return
	end
	HandleFriendInThisServerChanged(localPlayerInfo, friendedPlayer.UserId, true)
end

local function OnPlayerUnfriended(unfriendedPlayer: Player)
	local localPlayerInfo: GameConfig.ClientLocalPlayerInfo? = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil or not localPlayerInfo.friendInThisServerPlayerIdMap[unfriendedPlayer.UserId] then
		return
	end
	HandleFriendInThisServerChanged(localPlayerInfo, unfriendedPlayer.UserId, false)
end

function FriendRewardClientManager.Init()
	if not GameConfig.EnableFriendOnlineBuff or players.LocalPlayer == nil then
		return
	end
	ClientMsg.ConnectLocalPlayerInfoInit(OnLocalPlayerInfoInit)
	players.PlayerAdded:Connect(OnPlayerAdded)
	players.PlayerRemoving:Connect(OnPlayerRemoving)
	task.spawn(function()
		local playerFriendedEvent: BindableEvent
		local playerUnfriendedEvent: BindableEvent
		while true do
			local success: boolean, result: any = pcall(function()
				playerFriendedEvent = starterGui:GetCore("PlayerFriendedEvent")
			end)
			if success then
				break
			end
			task.wait()
		end
		while true do
			local success: boolean, result: any = pcall(function()
				playerUnfriendedEvent = starterGui:GetCore("PlayerUnfriendedEvent")
			end)
			if success then
				break
			end
			task.wait()
		end
		playerFriendedEvent.Event:Connect(OnPlayerFriended)
		playerUnfriendedEvent.Event:Connect(OnPlayerUnfriended)
	end)
end

return FriendRewardClientManager
