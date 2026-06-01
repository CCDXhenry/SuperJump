--!strict
-- JumpRunwayClientManager：跑道客户端入口，逻辑在 RunwaySession 与各 JumpRunway 子模块。
local JumpRunwayClientManager = {}

local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local jumpRunwayScripts = clientScripts:WaitForChild("JumpRunway")
local RunwaySession = require(jumpRunwayScripts:WaitForChild("RunwaySession"))

function JumpRunwayClientManager.Init()
	RunwaySession.Init()
end

return JumpRunwayClientManager
