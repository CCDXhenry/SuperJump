--!strict
local TeleportPortalServerManager = {}

local workspaceInst = game:GetService("Workspace")

local serverStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local JumpRunwayServerManager = require(serverScripts:WaitForChild("JumpRunwayServerManager"))

local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))

local initDone = false

local function ResolvePortalItselfFromPath(portalItselfPath: string?): BasePart?
	if portalItselfPath == nil or portalItselfPath == "" then
		return nil
	end
	local current: Instance = workspaceInst
	for segment in string.gmatch(portalItselfPath, "[^%.]+") do
		if segment == "Workspace" or segment == "workspace" or segment == "game" then
			continue
		end
		local nextInst = current:FindFirstChild(segment)
		if nextInst == nil then
			return nil
		end
		current = nextInst
	end
	if current:IsA("BasePart") and current.Name == "PortalItself" then
		return current
	end
	return nil
end

local function OnRequestTeleportPortalEscape(player: Player, portalItselfPath: any)
	local path = if typeof(portalItselfPath) == "string" then portalItselfPath :: string else nil
	local portalItself = ResolvePortalItselfFromPath(path)
	if portalItself == nil then
		return
	end
	JumpRunwayServerManager.TryCompleteEscapeViaTeleportPortal(player, portalItself)
end

function TeleportPortalServerManager.Init()
	if initDone then
		return
	end
	initDone = true
	NetMsg.ConnectRequestJumpRunwayTeleportPortalEscape(OnRequestTeleportPortalEscape)
end

return TeleportPortalServerManager
