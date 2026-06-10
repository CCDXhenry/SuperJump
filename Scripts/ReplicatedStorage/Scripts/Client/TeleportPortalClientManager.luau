--!strict
local TeleportPortalClientManager = {}

local players = game:GetService("Players")
local runService = game:GetService("RunService")
local workspaceInst = game:GetService("Workspace")

local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local sharedScripts = scripts:WaitForChild("Shared")
local ClientGameInfo = require(clientScripts:WaitForChild("ClientGameInfo"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local RunwaySession = require(clientScripts:WaitForChild("JumpRunway"):WaitForChild("RunwaySession"))

local localPlayer = players.LocalPlayer

local MinIntoPortalSpeedStudsPerSec = 1
local ApproachSideSlackStuds = 4

local boundPortalItselfSet: { [BasePart]: boolean } = {}
local escapeTriggerConsumed = false
local initDone = false

local function BuildPortalPath(portalItself: BasePart): string
	local segments: { string } = {}
	local current: Instance? = portalItself
	while current and current ~= workspaceInst do
		table.insert(segments, 1, current.Name)
		current = current.Parent
	end
	return table.concat(segments, ".")
end

local function ResolvePortalItselfFromModel(portalModel: Model): BasePart?
	local portalItself = portalModel:FindFirstChild("PortalItself")
	if portalItself and portalItself:IsA("BasePart") then
		return portalItself
	end
	return nil
end

local function CollectPortalItselfParts(): { BasePart }
	local parts: { BasePart } = {}
	local ground = workspaceInst:FindFirstChild("Ground")
	local portalFolder = if ground then ground:FindFirstChild("TeleportPortal") else nil
	if portalFolder and portalFolder:IsA("Folder") then
		for _, child in ipairs(portalFolder:GetChildren()) do
			if child:IsA("Model") then
				local portalItself = ResolvePortalItselfFromModel(child)
				if portalItself then
					table.insert(parts, portalItself)
				end
			end
		end
	end
	local directModel = workspaceInst:FindFirstChild("TeleportPortal")
	if directModel and directModel:IsA("Model") then
		local portalItself = ResolvePortalItselfFromModel(directModel)
		if portalItself then
			table.insert(parts, portalItself)
		end
	end
	return parts
end

-- 穿越方向取 Part 最薄轴（圆柱 PortalItself 为 local X / RightVector）
local function ResolvePortalPassageNormalHorizontal(portalItself: BasePart): Vector3?
	local size = portalItself.Size
	local worldAxis: Vector3
	if size.X <= size.Y and size.X <= size.Z then
		worldAxis = portalItself.CFrame.RightVector
	elseif size.Y <= size.Z then
		worldAxis = portalItself.CFrame.UpVector
	else
		worldAxis = portalItself.CFrame.LookVector
	end
	local horizontal = Vector3.new(worldAxis.X, 0, worldAxis.Z)
	if horizontal.Magnitude < 1e-4 then
		return nil
	end
	return horizontal.Unit
end

local function IsOnApproachSide(portalItself: BasePart, worldPos: Vector3, passageNormal: Vector3): boolean
	local offsetHorizontal = Vector3.new(worldPos.X - portalItself.Position.X, 0, worldPos.Z - portalItself.Position.Z)
	return offsetHorizontal:Dot(passageNormal) > -ApproachSideSlackStuds
end

local function ResolveIntoPortalSpeed(hrp: BasePart, humanoid: Humanoid?, intoPortal: Vector3): number
	local horizontalVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
	local intoSpeed = horizontalVelocity:Dot(intoPortal)
	if intoSpeed >= MinIntoPortalSpeedStudsPerSec then
		return intoSpeed
	end
	if humanoid and humanoid.MoveDirection.Magnitude > 0.05 then
		local moveHorizontal = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z)
		if moveHorizontal.Magnitude > 1e-4 then
			return moveHorizontal.Unit:Dot(intoPortal) * humanoid.WalkSpeed
		end
	end
	return intoSpeed
end

local function IsApproachingFromPortalFront(
	portalItself: BasePart,
	hrp: BasePart,
	hit: BasePart,
	humanoid: Humanoid?
): boolean
	local passageNormal = ResolvePortalPassageNormalHorizontal(portalItself)
	if passageNormal == nil then
		return false
	end
	local intoPortal = -passageNormal
	local intoSpeed = ResolveIntoPortalSpeed(hrp, humanoid, intoPortal)
	if intoSpeed < MinIntoPortalSpeedStudsPerSec then
		return false
	end
	local horizontalVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
	if horizontalVelocity:Dot(passageNormal) > intoSpeed then
		return false
	end
	return IsOnApproachSide(portalItself, hrp.Position, passageNormal)
		or IsOnApproachSide(portalItself, hit.Position, passageNormal)
end

local function TryTriggerPortalEscape(portalItself: BasePart, hrp: BasePart, hit: BasePart, humanoid: Humanoid?)
	if escapeTriggerConsumed then
		return
	end
	if not ClientGameInfo.IsInJumpRunwayEscapePhase() then
		return
	end
	if not IsApproachingFromPortalFront(portalItself, hrp, hit, humanoid) then
		return
	end
	escapeTriggerConsumed = true
	NetMsg.FireRequestJumpRunwayTeleportPortalEscape(BuildPortalPath(portalItself))
	RunwaySession.TryCompleteEscapeViaTeleportPortal()
end

local function OnPortalItselfTouched(portalItself: BasePart, hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	if character == nil or character ~= localPlayer.Character then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	TryTriggerPortalEscape(portalItself, hrp, hit, humanoid)
end

local function BindPortalItself(portalItself: BasePart)
	if boundPortalItselfSet[portalItself] then
		return
	end
	boundPortalItselfSet[portalItself] = true
	portalItself.Touched:Connect(function(hit)
		if hit:IsA("BasePart") then
			OnPortalItselfTouched(portalItself, hit)
		end
	end)
end

local function BindAllPortals()
	for _, portalItself in ipairs(CollectPortalItselfParts()) do
		BindPortalItself(portalItself)
	end
end

local function WatchPortalFolder()
	local ground = workspaceInst:FindFirstChild("Ground")
	local portalFolder = if ground then ground:FindFirstChild("TeleportPortal") else nil
	if portalFolder and portalFolder:IsA("Folder") then
		portalFolder.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				local portalItself = ResolvePortalItselfFromModel(child)
				if portalItself then
					BindPortalItself(portalItself)
				end
			end
		end)
	end
end

function TeleportPortalClientManager.Init()
	if initDone then
		return
	end
	initDone = true
	BindAllPortals()
	WatchPortalFolder()
	runService.Heartbeat:Connect(function()
		if not ClientGameInfo.IsInJumpRunwayEscapePhase() then
			escapeTriggerConsumed = false
		end
	end)
end

return TeleportPortalClientManager
