--!strict
local serverStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

local function OnPlayerRequestAddFriendInThisServer(player: Player, playerId: number)
	if not GameConfig.EnableFriendOnlineBuff then
		return
	end
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil or playerInfo.friendInThisServerPlayerIdMap[playerId] then
		return
	end
	playerInfo.friendInThisServerPlayerIdMap[playerId] = true
end

local function OnPlayerRequestRemoveFriendInThisServer(player: Player, playerId: number)
	if not GameConfig.EnableFriendOnlineBuff then
		return
	end
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil or not playerInfo.friendInThisServerPlayerIdMap[playerId] then
		return
	end
	playerInfo.friendInThisServerPlayerIdMap[playerId] = nil
end

local function OnPlayerRequestUpdateFriendsPlayingSameGameCount(player: Player, friendsPlayingSameGameCount: number)
	if not GameConfig.EnableFriendOnlineBuff then
		return
	end
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil or playerInfo.friendsPlayingSameGameCount == friendsPlayingSameGameCount then
		return
	end
	playerInfo.friendsPlayingSameGameCount = friendsPlayingSameGameCount
end

NetMsg.ConnectRequestAddFriendInThisServer(OnPlayerRequestAddFriendInThisServer)
NetMsg.ConnectRequestRemoveFriendInThisServer(OnPlayerRequestRemoveFriendInThisServer)
NetMsg.ConnectRequestUpdateFriendsPlayingSameGameCount(OnPlayerRequestUpdateFriendsPlayingSameGameCount)
