--!strict
-- 火箭背包模型由服务端常驻创建；客户端只同步库存数据并清理旧版本本地装饰。
local JetpackClientManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local players: Players = game:GetService("Players")
local localPlayer: Player? = players.LocalPlayer

if localPlayer == nil then
	return JetpackClientManager
end

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))

local DecorationModelName = "PlayerJetpackDecoration"
local DecorationFallbackPartName = "PlayerJetpackDecorationFallback"

local function DestroyLegacyClientJetpackDecoration()
	local character = localPlayer.Character
	if character == nil then
		return
	end
	local decorationVisualRoot = character:FindFirstChild(DecorationModelName)
	if decorationVisualRoot ~= nil then
		decorationVisualRoot:Destroy()
	end
	local decorationFallbackPart = character:FindFirstChild(DecorationFallbackPartName)
	if decorationFallbackPart ~= nil then
		decorationFallbackPart:Destroy()
	end
end

local function OnJetpackInventoryUpdateFromServer(jetpackInventory: GameConfig.JetpackInventory)
	ClientGameInfo.UpdateJetpackInventory(jetpackInventory)
end

local function OnJetpackInventoryUpdateLocal(_jetpackInventory: GameConfig.JetpackInventory)
	DestroyLegacyClientJetpackDecoration()
end

local function OnLocalPlayerInfoInit()
	DestroyLegacyClientJetpackDecoration()
end

local function OnJumpRunwayStateMayHaveChanged()
	DestroyLegacyClientJetpackDecoration()
end

local function OnCharacterAdded(character: Model)
	task.defer(function()
		if character.Parent == nil then
			return
		end
		DestroyLegacyClientJetpackDecoration()
	end)
end

function JetpackClientManager.Init()
	NetMsg.ConnectNotifyPlayerJetpackInventoryUpdate(OnJetpackInventoryUpdateFromServer)
	ClientMsg.ConnectLocalPlayerJetpackInventoryUpdate(OnJetpackInventoryUpdateLocal)
	ClientMsg.ConnectLocalPlayerInfoInit(OnLocalPlayerInfoInit)
	ClientMsg.ConnectCurrentGuideTypeChanged(OnJumpRunwayStateMayHaveChanged)
	localPlayer.CharacterAdded:Connect(OnCharacterAdded)
	if localPlayer.Character ~= nil then
		DestroyLegacyClientJetpackDecoration()
	end
end

return JetpackClientManager
