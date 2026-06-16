--!strict

local RunwayTreeUtil = {}

local physicsService = game:GetService("PhysicsService")
local workspace = game:GetService("Workspace")
local replicatedStorage = game:GetService("ReplicatedStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))

local cfg = GameConfig.JumpRunway

RunwayTreeUtil.TREE_COLLISION_GROUP = "Tree"
RunwayTreeUtil.TREE_FOLDER_NAME = "tree"

local treeCollisionInitialized = false
local treeDescendantAddedConn: RBXScriptConnection? = nil
local treeFolderAddedBound = false

local function RegisterCollisionGroupIfNeeded(groupName: string)
	pcall(function()
		physicsService:RegisterCollisionGroup(groupName)
	end)
end

local function SetCollisionGroup(part: BasePart, groupName: string)
	pcall(function()
		part.CollisionGroup = groupName
	end)
end

function RunwayTreeUtil.GetTreeFolder(): Folder?
	local treeFolder = workspace:FindFirstChild(RunwayTreeUtil.TREE_FOLDER_NAME)
	if treeFolder ~= nil and treeFolder:IsA("Folder") then
		return treeFolder
	end
	return nil
end

function RunwayTreeUtil.IsTreePart(part: BasePart): boolean
	if part.CollisionGroup == RunwayTreeUtil.TREE_COLLISION_GROUP then
		return true
	end
	local treeFolder = RunwayTreeUtil.GetTreeFolder()
	return treeFolder ~= nil and part:IsDescendantOf(treeFolder)
end

local function SetTreeCollisionGroupForInstance(instance: Instance)
	if instance:IsA("BasePart") then
		SetCollisionGroup(instance, RunwayTreeUtil.TREE_COLLISION_GROUP)
		instance.CanTouch = true
	end
end

local function ConfigureTreeCollisionGroup()
	RegisterCollisionGroupIfNeeded(RunwayTreeUtil.TREE_COLLISION_GROUP)
	local treeFolder = RunwayTreeUtil.GetTreeFolder()
	if treeFolder == nil then
		return
	end
	for _, descendant in ipairs(treeFolder:GetDescendants()) do
		SetTreeCollisionGroupForInstance(descendant)
	end
	if treeDescendantAddedConn ~= nil then
		treeDescendantAddedConn:Disconnect()
	end
	treeDescendantAddedConn = treeFolder.DescendantAdded:Connect(SetTreeCollisionGroupForInstance)
	treeCollisionInitialized = true
end

function RunwayTreeUtil.EnsureTreeCollisionGroup()
	if treeCollisionInitialized then
		return
	end
	ConfigureTreeCollisionGroup()
end

function RunwayTreeUtil.BindTreeFolderAdded()
	if treeFolderAddedBound then
		return
	end
	treeFolderAddedBound = true
	workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == RunwayTreeUtil.TREE_FOLDER_NAME and child:IsA("Folder") then
			treeCollisionInitialized = false
			task.defer(RunwayTreeUtil.EnsureTreeCollisionGroup)
		end
	end)
end

function RunwayTreeUtil.ResolveHumanoidHipHeight(humanoid: Humanoid): number
	local hip = humanoid.HipHeight
	if typeof(hip) ~= "number" or hip ~= hip or hip < 0.01 then
		hip = 2
	end
	return hip
end

function RunwayTreeUtil.RaycastTreeFeetInfo(humanoid: Humanoid, probeDown: number?): (boolean, number, Vector3?, BasePart?)
	local root = humanoid.RootPart
	if root == nil then
		return false, 1e9, nil, nil
	end
	local treeFolder = RunwayTreeUtil.GetTreeFolder()
	if treeFolder == nil then
		return false, 1e9, nil, nil
	end
	local hip = RunwayTreeUtil.ResolveHumanoidHipHeight(humanoid)
	local down = probeDown
	if typeof(down) ~= "number" or down ~= down or down <= 0 then
		down = cfg.RUNWAY_GROUND_PROBE_DOWN
	end
	local originY = cfg.RUNWAY_GROUND_RAY_ORIGIN_Y
	if typeof(originY) ~= "number" or originY ~= originY then
		originY = 0
	end
	local minNormalY = cfg.RUNWAY_GROUND_MIN_NORMAL_Y
	if typeof(minNormalY) ~= "number" or minNormalY ~= minNormalY then
		minNormalY = 0.35
	end
	local origin = root.Position + Vector3.new(0, originY - hip, 0)
	local cast = Vector3.new(0, -down, 0)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { treeFolder }
	local hit = workspace:Raycast(origin, cast, rayParams)
	if hit == nil then
		return false, 1e9, nil, nil
	end
	if hit.Normal.Y < minNormalY then
		return false, 1e9, nil, nil
	end
	local hitPart = if hit.Instance:IsA("BasePart") then hit.Instance else nil
	return true, hit.Distance, hit.Position, hitPart
end

function RunwayTreeUtil.RaycastTreeFeet(humanoid: Humanoid, probeDown: number?): (boolean, number)
	local ok, dist, _hitPosition, _hitPart = RunwayTreeUtil.RaycastTreeFeetInfo(humanoid, probeDown)
	return ok, dist
end

function RunwayTreeUtil.IsFeetOnTree(humanoid: Humanoid): boolean
	local ok, dist = RunwayTreeUtil.RaycastTreeFeet(humanoid, nil)
	if not ok then
		return false
	end
	local hip = RunwayTreeUtil.ResolveHumanoidHipHeight(humanoid)
	local slack = hip * 0.55 + 0.35
	return dist <= slack
end

task.defer(RunwayTreeUtil.EnsureTreeCollisionGroup)
RunwayTreeUtil.BindTreeFolderAdded()

return RunwayTreeUtil
