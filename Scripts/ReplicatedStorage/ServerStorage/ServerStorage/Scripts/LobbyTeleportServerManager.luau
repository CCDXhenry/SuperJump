--!strict
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local serverScripts = ServerStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:WaitForChild("ServerGameInfo"))
local BrainrotIslandManager = require(serverScripts:WaitForChild("BrainrotIslandManager"))

local scripts = ReplicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))

local LobbyTeleportServerManager = {}

local TELEPORT_Y_OFFSET = CFrame.new(0, 3, 0)
local SHOP_MODEL_FOLDER_NAME = "ShopModel"
local SHOP_TELEPORT_POINT_NAME = "ShopTeleportPoint"

local function IsTeleportBlockedByJumpRunway(player: Player): boolean
	return player:GetAttribute("JumpRunwayActive") == true
end

local function TeleportCharacterToSpawnLocation(player: Player, spawnLocation: SpawnLocation): boolean
	if IsTeleportBlockedByJumpRunway(player) then
		return false
	end

	local character = player.Character
	if character == nil then
		return false
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp == nil then
		return false
	end

	hrp.CFrame = spawnLocation.CFrame * TELEPORT_Y_OFFSET
	return true
end

local function TeleportPlayerToHome(player: Player): boolean
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	local homesFolder = workspace:FindFirstChild("PlayersHome")
	if playerInfo == nil or playerInfo.homeSlot == "" or homesFolder == nil then
		return false
	end

	local homeModel = homesFolder:FindFirstChild(playerInfo.homeSlot)
	if homeModel == nil then
		return false
	end

	local teleportPoint = homeModel:FindFirstChild("TeleportPoint")
	if teleportPoint == nil then
		return false
	end

	local spawnLocation = teleportPoint:FindFirstChild("SpawnLocation") :: SpawnLocation?
	if spawnLocation == nil then
		return false
	end

	local teleported = TeleportCharacterToSpawnLocation(player, spawnLocation)
	if teleported then
		BrainrotIslandManager.TryConvertCarryingToQueue(player)
	end
	return teleported
end

local function TeleportPlayerToShop(player: Player): boolean
	local shopModelFolder = workspace:FindFirstChild(SHOP_MODEL_FOLDER_NAME)
	if shopModelFolder == nil then
		return false
	end

	local shopTeleportPoint = shopModelFolder:FindFirstChild(SHOP_TELEPORT_POINT_NAME)
	if shopTeleportPoint == nil then
		return false
	end

	local spawnLocation = shopTeleportPoint:FindFirstChild("SpawnLocation") :: SpawnLocation?
	if spawnLocation == nil then
		return false
	end

	return TeleportCharacterToSpawnLocation(player, spawnLocation)
end

function LobbyTeleportServerManager.Init()
	NetMsg.ConnectRequestTeleportToHome(function(player: Player)
		TeleportPlayerToHome(player)
	end)

	NetMsg.ConnectRequestTeleportToShop(function(player: Player)
		TeleportPlayerToShop(player)
	end)
end

return LobbyTeleportServerManager
