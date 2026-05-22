--!strict
-- 火箭背包客户端管理器
--
-- 职责：当玩家在商店中更换火箭背包时，如果当前正在跑道模式中，销毁旧模型。
-- 跑道模式启动时 RunwaySession.EnsureJumpRunwayRocketBackpack 会自动从
-- jetpackInventory 读取当前装备并使用对应模型模板，无需本模块主动创建。
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
local RunwaySession = require(clientScripts:FindFirstChild("JumpRunway"):FindFirstChild("RunwaySession"))

-- 销毁旧火箭背包（仅在跑道模式激活时，DestroyJumpRunwayRocketBackpack 内部
-- 会判断 jetpackVisualRoot 是否为 nil，非跑道模式下无副作用）。
-- 下次跑道启动时 EnsureJumpRunwayRocketBackpack 会加载新模型。
local function DestroyCurrentJetpackModel()
	if RunwaySession.DestroyJumpRunwayRocketBackpack then
		RunwaySession.DestroyJumpRunwayRocketBackpack()
	end
end

-- 监听火箭背包库存更新（来自服务端的网络通知）
local function OnJetpackInventoryUpdateFromServer(jetpackInventory: GameConfig.JetpackInventory)
	ClientGameInfo.UpdateJetpackInventory(jetpackInventory)
	-- UpdateJetpackInventory 内部会 FireLocalPlayerJetpackInventoryUpdate，触发本地事件回调
end

-- 监听火箭背包库存更新（来自本地的更新通知）
local function OnJetpackInventoryUpdateLocal(_jetpackInventory: GameConfig.JetpackInventory)
	DestroyCurrentJetpackModel()
end

function JetpackClientManager.Init()
	NetMsg.ConnectNotifyPlayerJetpackInventoryUpdate(function(inventory: GameConfig.JetpackInventory)
		OnJetpackInventoryUpdateFromServer(inventory)
	end)
	ClientMsg.ConnectLocalPlayerJetpackInventoryUpdate(OnJetpackInventoryUpdateLocal)
end

return JetpackClientManager
