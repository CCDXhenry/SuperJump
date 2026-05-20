--!strict

local ChaserClientManager = {}

local players = game:GetService("Players")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
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

local function IsChaserTouchingCharacter(chaser: Model, character: Model): boolean
	local chaserParts = chaser:GetDescendants()
	for _, descendant in ipairs(chaserParts) do
		if descendant:IsA("BasePart") then
			local touching = descendant:GetTouchingParts()
			for _, touchedPart in ipairs(touching) do
				if touchedPart:IsAncestorOf(character) or character:IsAncestorOf(touchedPart) then
					return true
				end
			end
		end
	end
	return false
end

local function KillCharacter(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end
end

local function InternalCleanup()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	-- 不在这里销毁 activeChaser，由调用者根据需要决定何时销毁
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

function ChaserClientManager.SpawnChaser(character: Model, forwardDir: Vector3)
	InternalCleanupFull()

	if chaserTemplate == nil then
		warn("[ChaserClientManager] Chaser template not found under ReplicatedStorage.Models.Chaser")
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp == nil then
		return
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

	local chaserSpeed = cfg.CHASER_SPEED
	if typeof(chaserSpeed) ~= "number" or chaserSpeed ~= chaserSpeed then
		chaserSpeed = 16
	end

	-- 解除 HumanoidRootPart 的 Anchored，让 Humanoid 驱动移动和动画
	local chaserHrpInit = chaser:FindFirstChild("HumanoidRootPart") :: BasePart?
	if chaserHrpInit then
		chaserHrpInit.Anchored = false
		chaserHrpInit.CanCollide = true
	end

	-- 确保所有肢体部件有正确的物理属性
	for _, descendant in ipairs(chaser:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			descendant.CanCollide = true
		end
	end
	local chaserHumanoid = chaser:FindFirstChildOfClass("Humanoid")
	if chaserHumanoid then
		chaserHumanoid.WalkSpeed = chaserSpeed
		chaserHumanoid.AutoRotate = true
		chaserHumanoid.PlatformStand = false

		-- R6 模型需要手动加载跑步动画；R15 有内置动画，无需额外处理
		if chaserHumanoid.RigType == Enum.HumanoidRigType.R6 then
			local runAnim = Instance.new("Animation")
			runAnim.AnimationId = "rbxassetid://180426354"
			local success, runAnimTrack = pcall(function()
				return chaserHumanoid:LoadAnimation(runAnim)
			end)
			if success and runAnimTrack then
				runAnimTrack:Play(0, 1, 1)
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

		-- 碰撞检测
		if IsChaserTouchingCharacter(chaser, currentChr) then
			KillCharacter(currentChr)
			stopped = true
			task.delay(2, function()
				if activeChaser == nil then
					return
				end
				ChaserClientManager.StopAndFadeChaser()
			end)
			return
		end

		-- 通过 Humanoid:MoveTo 驱动移动，自动播放步行动画
		chaserHumanoidLive:MoveTo(currentHrp.Position)
	end)
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

return ChaserClientManager
