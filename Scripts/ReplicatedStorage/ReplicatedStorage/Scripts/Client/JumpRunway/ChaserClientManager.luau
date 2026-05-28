--!strict

local ChaserClientManager = {}

local players = game:GetService("Players")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local physicsService = game:GetService("PhysicsService")
local workspace = game:GetService("Workspace")
local replicatedStorage = game:GetService("ReplicatedStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

local chaserModels = replicatedStorage:FindFirstChild("Models"):FindFirstChild("Chaser")
local chaserTemplate = if chaserModels then chaserModels:FindFirstChild("Chaser") :: Model? else nil

local localPlayer = players.LocalPlayer

local activeChaser: Model? = nil
local heartbeatConn: RBXScriptConnection? = nil
local faded = false
local stopped = false

local chaserCollisionGroup = "Chaser"
local playerCollisionGroup = "Player"
local treeCollisionGroup = "Tree"
local treeFolderName = "tree"
local treeCollisionInitialized = false
local treeDescendantAddedConn: RBXScriptConnection? = nil

-- 管理 Chaser 所有 BasePart 的 Touched 连接，便于清理时统一断开
local touchConns: { RBXScriptConnection } = {}

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

local function ConfigureCollisionGroups()
	RegisterCollisionGroupIfNeeded(chaserCollisionGroup)
	RegisterCollisionGroupIfNeeded(playerCollisionGroup)
	RegisterCollisionGroupIfNeeded(treeCollisionGroup)
	pcall(function()
		physicsService:CollisionGroupSetCollidable(chaserCollisionGroup, treeCollisionGroup, false)
	end)
end

local function GetTreeFolder(): Folder?
	local treeFolder = workspace:FindFirstChild(treeFolderName)
	if treeFolder ~= nil and treeFolder:IsA("Folder") then
		return treeFolder
	end
	return nil
end

local function SetTreeCollisionGroupForInstance(instance: Instance)
	if instance:IsA("BasePart") then
		SetCollisionGroup(instance, treeCollisionGroup)
		instance.CanTouch = true
	end
end

local function ConfigureTreeCollisionGroup()
	ConfigureCollisionGroups()
	local treeFolder = GetTreeFolder()
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

local function EnsureTreeCollisionGroup()
	if treeCollisionInitialized then
		return
	end
	ConfigureTreeCollisionGroup()
end

local function IsTreePart(part: BasePart): boolean
	local treeFolder = GetTreeFolder()
	return treeFolder ~= nil and part:IsDescendantOf(treeFolder)
end

local function IsChaserOverlappingTree(chaserHrp: BasePart): boolean
	local treeFolder = GetTreeFolder()
	if treeFolder == nil then
		return false
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { treeFolder }
	overlap.MaxParts = 8
	local boxSize = chaserHrp.Size + Vector3.new(2, 3, 2)
	local parts = workspace:GetPartBoundsInBox(chaserHrp.CFrame, boxSize, overlap)
	return #parts > 0
end

local function SetPlayerCollisionGroup(character: Model)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			SetCollisionGroup(descendant, playerCollisionGroup)
		end
	end
end

local function EnsurePlayerCollisionGroup()
	local character = localPlayer.Character
	if character then
		SetPlayerCollisionGroup(character)
	end
end

-- CharacterAdded 时也同步设置 Player 碰撞组
localPlayer.CharacterAdded:Connect(function(character: Model)
	SetPlayerCollisionGroup(character)
end)

local function KillCharacter(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end
end

local function DisconnectTouchConns()
	for _, conn in ipairs(touchConns) do
		conn:Disconnect()
	end
	table.clear(touchConns)
end

local function InternalCleanup()
	DisconnectTouchConns()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	faded = false
	stopped = false
end

local function InternalCleanupFull()
	InternalCleanup()
	if activeChaser then
		activeChaser:Destroy()
		activeChaser = nil
	end
end

function ChaserClientManager.SpawnChaser(
	character: Model,
	forwardDir: Vector3,
	speedOverride: number?,
	startDelayOverrideSec: number?
): Model?
	InternalCleanupFull()
	EnsureTreeCollisionGroup()

	if chaserTemplate == nil then
		warn("[ChaserClientManager] Chaser template not found under ReplicatedStorage.Models.Chaser")
		return nil
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp == nil then
		return nil
	end

	local forwardH = Vector3.new(forwardDir.X, 0, forwardDir.Z)
	if forwardH.Magnitude < 1e-4 then
		forwardH = Vector3.new(0, 0, -1)
	else
		forwardH = forwardH.Unit
	end

	local cfg = GameConfig.JumpRunway
	local spawnAhead = cfg.CHASER_SPAWN_AHEAD_STUDS
	if typeof(spawnAhead) ~= "number" or spawnAhead ~= spawnAhead then
		spawnAhead = 50
	end

	local spawnPos = hrp.Position + forwardH * spawnAhead
	spawnPos = Vector3.new(spawnPos.X, hrp.Position.Y, spawnPos.Z)

	-- 把 Chaser 放到地面高度
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = if character then { character } else {}
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local rayResult = workspace:Raycast(spawnPos + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), rayParams)
	if rayResult then
		spawnPos = Vector3.new(spawnPos.X, rayResult.Position.Y, spawnPos.Z)
	end

	local chaser = chaserTemplate:Clone()
	chaser:PivotTo(CFrame.lookAt(spawnPos, hrp.Position, Vector3.yAxis))
	chaser.Parent = workspace
	activeChaser = chaser

	local chaserSpeed = if speedOverride ~= nil then speedOverride else cfg.CHASER_SPEED
	if typeof(chaserSpeed) ~= "number" or chaserSpeed ~= chaserSpeed then
		chaserSpeed = 16
	end
	local treeSlowScale = cfg.CHASER_TREE_SLOW_SCALE
	if typeof(treeSlowScale) ~= "number" or treeSlowScale ~= treeSlowScale then
		treeSlowScale = 0.5
	end
	treeSlowScale = math.clamp(treeSlowScale, 0.05, 1)
	local treeSlowDuration = cfg.CHASER_TREE_SLOW_DURATION_SEC
	if typeof(treeSlowDuration) ~= "number" or treeSlowDuration ~= treeSlowDuration or treeSlowDuration <= 0 then
		treeSlowDuration = 0.35
	end
	local treeSlowUntilClock = 0

	-- 设置玩家角色的碰撞组
	EnsurePlayerCollisionGroup()

	-- 解除 HumanoidRootPart 的 Anchored，让 Humanoid 驱动移动和动画
	local chaserHrpInit = chaser:FindFirstChild("HumanoidRootPart") :: BasePart?
	if chaserHrpInit then
		chaserHrpInit.Anchored = false
		chaserHrpInit.CanCollide = true
	end

	-- 设置 Chaser 所有部件的碰撞组 + 绑定 Touched 事件
	-- 使用碰撞组使 Player 和 Chaser 不物理互碰，避免 Humanoid 避障干扰
	-- 通过 Touched 事件检测接触来击杀玩家
	for _, descendant in ipairs(chaser:GetDescendants()) do
		if descendant:IsA("BasePart") then
			SetCollisionGroup(descendant, chaserCollisionGroup)
			descendant.CanCollide = true
			descendant.CanTouch = true
			local conn = descendant.Touched:Connect(function(hit: BasePart)
				if stopped or faded then
					return
				end
				if not hit or not hit.Parent then
					return
				end
				if IsTreePart(hit) then
					treeSlowUntilClock = math.max(treeSlowUntilClock, os.clock() + treeSlowDuration)
					return
				end
				local hitCharacter = hit:FindFirstAncestorOfClass("Model")
				if hitCharacter == nil then
					return
				end
				if hitCharacter ~= localPlayer.Character then
					return
				end
				KillCharacter(hitCharacter)
				stopped = true
				task.delay(2, function()
					if activeChaser == nil then
						return
					end
					ChaserClientManager.StopAndFadeChaser()
				end)
			end)
			table.insert(touchConns, conn)
		end
	end
	local chaserHumanoid = chaser:FindFirstChildOfClass("Humanoid")
	local runAnimTrack: AnimationTrack? = nil
	if chaserHumanoid then
		chaserHumanoid.WalkSpeed = 0
		chaserHumanoid.AutoRotate = true
		chaserHumanoid.PlatformStand = false

		-- R6 模型需要手动加载跑步动画；R15 有内置动画，无需额外处理
		if chaserHumanoid.RigType == Enum.HumanoidRigType.R6 then
			local runAnim = Instance.new("Animation")
			runAnim.AnimationId = "rbxassetid://180426354"
			local success, loadedRunAnimTrack = pcall(function()
				return chaserHumanoid:LoadAnimation(runAnim)
			end)
			if success and loadedRunAnimTrack then
				runAnimTrack = loadedRunAnimTrack
			end
		end
	end

	-- 确保所有 BodyMover 类型的约束被移除，避免干扰 Humanoid 移动
	local bodyMovers = chaser:GetDescendants()
	for _, descendant in ipairs(bodyMovers) do
		if descendant:IsA("BodyVelocity") or descendant:IsA("BodyPosition")
			or descendant:IsA("BodyGyro") or descendant:IsA("BodyThrust")
			or descendant:IsA("VectorForce") then
			descendant:Destroy()
		end
	end

	stopped = false
	faded = false

	local startDelaySec = if startDelayOverrideSec ~= nil then startDelayOverrideSec else cfg.CHASER_START_DELAY_SEC
	if typeof(startDelaySec) ~= "number" or startDelaySec ~= startDelaySec then
		startDelaySec = 3
	end
	local chaseStartClock = os.clock() + math.max(0, startDelaySec)
	local chaseStarted = false

	heartbeatConn = runService.Heartbeat:Connect(function(dt: number)
		if stopped or faded then
			return
		end

		local currentChr = localPlayer.Character
		if currentChr == nil then
			return
		end

		local currentHrp = currentChr:FindFirstChild("HumanoidRootPart") :: BasePart?
		if currentHrp == nil then
			return
		end

		local chaserHrpLive = chaser:FindFirstChild("HumanoidRootPart") :: BasePart?
		if chaserHrpLive == nil then
			return
		end
		local chaserHumanoidLive = chaser:FindFirstChildOfClass("Humanoid")
		if chaserHumanoidLive == nil then
			return
		end

		local nowClock = os.clock()
		if nowClock < chaseStartClock then
			chaserHumanoidLive.WalkSpeed = 0
			chaserHumanoidLive:MoveTo(chaserHrpLive.Position)
			return
		end
		if not chaseStarted then
			chaseStarted = true
			if runAnimTrack ~= nil then
				runAnimTrack:Play(0, 1, 1)
			end
		end
		if IsChaserOverlappingTree(chaserHrpLive) then
			treeSlowUntilClock = math.max(treeSlowUntilClock, nowClock + treeSlowDuration)
		end
		local targetWalkSpeed = chaserSpeed
		if nowClock < treeSlowUntilClock then
			targetWalkSpeed = chaserSpeed * treeSlowScale
		end
		if chaserHumanoidLive.WalkSpeed ~= targetWalkSpeed then
			chaserHumanoidLive.WalkSpeed = targetWalkSpeed
		end

		chaserHumanoidLive:MoveTo(currentHrp.Position)
	end)
	return chaser
end

function ChaserClientManager.StopAndFadeChaser()
	stopped = true

	if faded then
		return
	end
	if activeChaser == nil then
		return
	end

	-- 让 Humanoid 停止移动
	local chaserH = activeChaser:FindFirstChildOfClass("Humanoid")
	if chaserH then
		chaserH:MoveTo(activeChaser:GetPivot().Position)
	end

	local cfg = GameConfig.JumpRunway
	local fadeDuration = cfg.CHASER_FADE_DURATION_SEC
	if typeof(fadeDuration) ~= "number" or fadeDuration ~= fadeDuration or fadeDuration <= 0 then
		fadeDuration = 1.5
	end

	-- 在所有 BasePart 上做透明度渐变动画
	local tweenInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	local partsToFade: { BasePart } = {}
	for _, descendant in ipairs(activeChaser:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(partsToFade, descendant :: BasePart)
		end
	end

	local completedCount = 0
	local totalParts = #partsToFade

	if totalParts == 0 then
		faded = true
		InternalCleanup()
		if activeChaser then
			activeChaser:Destroy()
			activeChaser = nil
		end
		return
	end

	for _, part in ipairs(partsToFade) do
		local goal: { [string]: any } = { Transparency = 1 }
		local tween = tweenService:Create(part, tweenInfo, goal)
		tween.Completed:Connect(function()
			completedCount += 1
			if completedCount >= totalParts then
				faded = true
				InternalCleanup()
				if activeChaser then
					activeChaser:Destroy()
					activeChaser = nil
				end
			end
		end)
		tween:Play()
	end

	-- 同时将整个人形也设为不可见（防止 Outline 等残留）
	local chaserHumanoid = activeChaser:FindFirstChildOfClass("Humanoid")
	local nonPartDescendants = activeChaser:GetDescendants()
	for _, descendant in ipairs(nonPartDescendants) do
		if descendant:IsA("Decal") then
			local decalGoal: { [string]: any } = { Transparency = 1 }
			local decalTween = tweenService:Create(descendant, tweenInfo, decalGoal)
			decalTween:Play()
		end
	end
end

function ChaserClientManager.CleanupChaser()
	-- 如果正在淡出中（stopped 但未 faded），不打断淡出，由 tween 回调自行销毁
	if stopped and not faded then
		return
	end
	InternalCleanupFull()
end

ConfigureCollisionGroups()
task.defer(ConfigureTreeCollisionGroup)
workspace.ChildAdded:Connect(function(child: Instance)
	if child.Name == treeFolderName and child:IsA("Folder") then
		task.defer(ConfigureTreeCollisionGroup)
	end
end)

return ChaserClientManager
