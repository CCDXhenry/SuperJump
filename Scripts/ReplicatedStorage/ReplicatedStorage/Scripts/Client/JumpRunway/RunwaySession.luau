--!strict
-- RunwaySession（客户端权威状态机）
-- ----------------------------------------------------------------------
-- 开局 / BeginLine 触碰、相位机、起跳窗与物理均在客户端；服端仅 Start 登记、Sample 防作弊、Final 锁定成绩。
local RunwaySession = {}

local players = game:GetService("Players")
local userInputService = game:GetService("UserInputService")
local runService = game:GetService("RunService")
local workspace = game:GetService("Workspace")
local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local ClientGameInfo = require(clientScripts:WaitForChild("ClientGameInfo"))
local JumpRunWayFrame = require(clientScripts:WaitForChild("JumpRunWayFrame"))
local jumpRunwayScripts = clientScripts:WaitForChild("JumpRunway")
local RunwayStateStore = require(jumpRunwayScripts:WaitForChild("RunwayStateStore"))
local RunwayConstants = require(jumpRunwayScripts:WaitForChild("RunwayConstants"))
local RunwayPhysicsController = require(jumpRunwayScripts:WaitForChild("RunwayPhysicsController"))
local RunwayCameraController = require(jumpRunwayScripts:WaitForChild("RunwayCameraController"))
local RunwayFxController = require(jumpRunwayScripts:WaitForChild("RunwayFxController"))
local RunwayUiController = require(jumpRunwayScripts:WaitForChild("RunwayUiController"))
local RunwayNetBridge = require(jumpRunwayScripts:WaitForChild("RunwayNetBridge"))
local ChaserClientManager = require(jumpRunwayScripts:WaitForChild("ChaserClientManager"))
local ChestOpenAnimationManager = require(clientScripts:WaitForChild("ChestOpenAnimationManager"))
local core = replicatedStorage:WaitForChild("Core")
local coreClientScripts = core:WaitForChild("Scripts"):WaitForChild("Client")
local TranslationTool = require(coreClientScripts:WaitForChild("TranslationTool"))

type RunwayLocalState = RunwayStateStore.RunwayStateStoreShape

local localPlayer = players.LocalPlayer
local cfg = GameConfig.JumpRunway

local function GetJumpPowerBaseSpeed(): number
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	return if localPlayerInfo then localPlayerInfo.jumpPower else GameConfig.JumpPowerDefaultValue
end

local Ph = RunwayConstants.Ph
local Kind = RunwayConstants.Kind
local SlideKindStandard = RunwayConstants.SlideKindStandard
local SlideKindFinalLanding = RunwayConstants.SlideKindFinalLanding
local SlideKindMiss = RunwayConstants.SlideKindMiss
local RunwayCameraRenderStepName = RunwayConstants.RunwayCameraRenderStepName
local RunwayFinalTiltRenderStepName = RunwayConstants.RunwayFinalTiltRenderStepName
local RunwayRingTemplateName = RunwayConstants.RunwayRingTemplateName
local RunwaySlideTraceTemplateName = RunwayConstants.RunwaySlideTraceTemplateName
local RunwaySlideTraceDestroyAfterEndSec = RunwayConstants.RunwaySlideTraceDestroyAfterEndSec

local modelsFolder = replicatedStorage:WaitForChild("Models")
local actualChests = modelsFolder:FindFirstChild("LittleElfChests")
local CHEST_GROUND_RAISE_STUDS = 0.2
local CHEST_HIT_HORIZONTAL_MAX_DIST_STUDS = 14
local CHEST_HIT_MIN_SETTLE_AFTER_LAND_SEC = 0.2
local CHEST_FALL_MAX_HEIGHT_STUDS = 8
local JumpRunwayLittleElfChestCarryAttr = "JumpRunwayLittleElfChestCarry"
local StartTriggerCloseEnoughMinStuds = 24
local StartTriggerRearmOutsideMinSec = 0.2

local Refs: {
	screenGui: ScreenGui?,
	phaseLabel: TextLabel?,
	windowLabel: TextLabel?,
	fuelLabel: TextLabel?,
	vyLabel: TextLabel?,
	finalTakeoffForceFreefallUntilClock: number,
	initDone: boolean,
	jumpStateEnabledBeforeRunway: boolean?,
	runningStateEnabledBeforeFinalSegment: boolean?,
	flyingStateEnabledBeforeRunway: boolean?,
	runwayGravityAttachment: Attachment?,
	runwayGravityVectorForce: VectorForce?,
	startTriggerConn: RBXScriptConnection?,
	beginLineConn: RBXScriptConnection?,
	runwayRingPart: Part?,
	ringBaseSizeX: number,
	ringBaseSizeY: number,
	ringBaseSizeZ: number,
	ringLastGroundY: number?,
	ringTemplateWarned: boolean,
	runwayDistanceRecorderPart: BasePart?,
	runwayDistanceRecorderText: TextLabel?,
	distanceRecorderLastGroundY: number?,
	distanceRecorderTemplateWarned: boolean,
	rocketBackpackPart: BasePart?,
	rocketBackpackFallbackWarned: boolean,
	jetpackVisualRoot: Model?,
	jetpackFlame1Part: BasePart?,
	jetpackFlame2Part: BasePart?,
	jetpackFlame1IdleColor: Color3?,
	jetpackFlame2IdleColor: Color3?,
	jetpackDashParticleEmitters: { ParticleEmitter },
	jetpackTemplateWarned: boolean,
	autoRotateSavedForFinalPitch: boolean?,
	finalLandTumbleStartHrpCf: CFrame?,
	platformStandSavedBeforeFinalLand: boolean?,
	finalPitchSmoothedExtraDeg: number,
	slideTraceTemplateWarned: boolean,
	slideTraceCachedTemplate: BasePart?,
	slideTraceFollowerPart: BasePart?,
	slideTraceAccumAlong: number,
	slideTracePrevAlongForDelta: number?,
	slideTraceSegmentList: { BasePart? },
	slideTraceDestroyScheduleToken: number,
	prevGroundedHeartbeat: boolean,
	chestSpawnedForThisRun: boolean?,
	chestSpawnedModel: Model?,
	chestSpawnedConnList: { RBXScriptConnection }?,
	chestPickedBrainrotId: number?,
	chestPickedConfigId: number?,
	chestAnimPlaying: boolean?,
	chestReadyForHit: boolean?,
	chestHitSequenceActive: boolean?,
	chestOpenCFrame: CFrame?,
	chestSlideFwdH: Vector3?,
	chestSpawnDelayToken: number,
	chestRunwayAwaitingExit: boolean?,
	chestBounceActive: boolean?,
	chestRewardWaitPose: boolean?,
	chestLandedOnGround: boolean?,
	chestGroundOpenCFrame: CFrame?,
	chestPendingReward: { brainrotId: number, chestConfigId: number, chestLevel: number }?,
	chestRewardPresentationStarted: boolean?,
	chestBounceAlongSpeed: number?,
	chestLandClock: number?,
	chestDynamicConfigId: number?,
	chestScheduledSpawnPos: Vector3?,
	chestPredictedPlaceDistance: number?,
	chestPostRewardExitCleanup: boolean?,
	chestPostOpenTeleportDelayToken: number,
	chestBackpackDeliverRequested: boolean?,
	chestCarryReturnActive: boolean?,
	lastRunAlongDistance: number?,
	missAbortSentForThisRun: boolean?,
	startTriggerStartArmed: boolean?,
	startTriggerPlayerWasInsideVolume: boolean?,
	startTriggerOutsideVolumeClock: number?,
	deferredTerminalServerPayload: NetMsg.JumpRunwayStatePayload?,
} = {
	finalTakeoffForceFreefallUntilClock = 0,
	initDone = false,
	ringBaseSizeX = 1,
	ringBaseSizeY = 1,
	ringBaseSizeZ = 1,
	ringTemplateWarned = false,
	distanceRecorderTemplateWarned = false,
	rocketBackpackFallbackWarned = false,
	jetpackDashParticleEmitters = {},
	jetpackTemplateWarned = false,
	slideTraceTemplateWarned = false,
	slideTraceAccumAlong = 0,
	slideTraceSegmentList = {},
	slideTraceDestroyScheduleToken = 0,
	prevGroundedHeartbeat = true,
	finalPitchSmoothedExtraDeg = 0,
	chestSpawnedForThisRun = false,
	chestSpawnedModel = nil,
	chestSpawnedConnList = nil,
	chestPickedBrainrotId = nil,
	chestPickedConfigId = nil,
	chestAnimPlaying = false,
	chestReadyForHit = false,
	chestHitSequenceActive = false,
	chestOpenCFrame = nil,
	chestSlideFwdH = nil,
	chestSpawnDelayToken = 0,
	chestRunwayAwaitingExit = false,
	chestBounceActive = false,
	chestRewardWaitPose = false,
	chestLandedOnGround = false,
	chestGroundOpenCFrame = nil,
	chestPendingReward = nil,
	chestRewardPresentationStarted = false,
	chestBounceAlongSpeed = nil,
	chestLandClock = nil,
	chestDynamicConfigId = nil,
	chestScheduledSpawnPos = nil,
	chestPredictedPlaceDistance = nil,
	chestPostRewardExitCleanup = false,
	chestPostOpenTeleportDelayToken = 0,
	chestBackpackDeliverRequested = false,
	chestCarryReturnActive = false,
	lastRunAlongDistance = nil,
	startTriggerStartArmed = true,
	startTriggerPlayerWasInsideVolume = false,
	startTriggerOutsideVolumeClock = nil,
	deferredTerminalServerPayload = nil,
	missAbortSentForThisRun = nil,
}

local localState: RunwayLocalState = RunwayStateStore.CreateDefault(Ph, SlideKindStandard)

-- ChainHudActive: (nowClock: number) -> boolean
-- LineHudActive: (nowClock: number) -> boolean

function RunwaySession.ResolveSceneParts(): (Part?, Part?)
	local startPoint = workspace:FindFirstChild("StartPoint")
	local startModel = if startPoint then startPoint:FindFirstChild("StartPointModel") else nil
	local startTrigger = if startModel then startModel:FindFirstChild("StartTrigger") :: Part? else nil
	local jumpRunway = workspace:FindFirstChild("JumpRunway")
	local beginLine = if jumpRunway then jumpRunway:FindFirstChild("BeginLine") :: Part? else nil
	return startTrigger, beginLine
end

function RunwaySession.GetCharacterParts(): (Model?, Humanoid?, BasePart?)
	local character = localPlayer.Character
	if character == nil then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return character, humanoid, hrp
end

function RunwaySession.GetPlayerControls(): any
	local playerScripts = localPlayer:FindFirstChildOfClass("PlayerScripts")
	if playerScripts == nil then
		return nil
	end
	local playerModuleScript = playerScripts:FindFirstChild("PlayerModule") :: ModuleScript?
	if playerModuleScript == nil then
		return nil
	end
	local ok, mod = pcall(require, playerModuleScript)
	if not ok or mod == nil then
		return nil
	end
	local controls
	local okGet, res = pcall(function()
		return (mod :: any):GetControls()
	end)
	if okGet then
		controls = res
	end
	return controls
end

function RunwaySession.SetControlsEnabled(enabled: boolean)
	local controls = RunwaySession.GetPlayerControls()
	if controls == nil then
		return
	end
	if enabled == not localState.controlsDisabled then
		return
	end
	if enabled then
		pcall(function()
			controls:Enable()
		end)
		localState.controlsDisabled = false
	else
		pcall(function()
			controls:Disable()
		end)
		localState.controlsDisabled = true
	end
end

function RunwaySession.IsRunwayActivePhase(phase: number): boolean
	return RunwayConstants.IsRunwayActivePhase(phase)
end

-- 与 SendSampleIfDue 上报的 sampleAlongSpeed 一致：水平速度在跑道前向轴上的分量（forward 须为 NormalizeRunwayForward 结果）
local HorizontalVelocity = RunwayPhysicsController.HorizontalVelocity
local NormalizeRunwayForward = RunwayPhysicsController.NormalizeRunwayForward
local ComputeRunwayHorizontalAlongSpeed = RunwayPhysicsController.ComputeRunwayHorizontalAlongSpeed

function RunwaySession.CurrentAlongProgress(hrp: BasePart): number
	return RunwayPhysicsController.CurrentAlongProgress(hrp, localState.runwayOrigin, localState.runwayForward, localState.alongBaseline)
end

function RunwaySession.HudDestroy()
	if Refs.screenGui then
		Refs.screenGui:Destroy()
		Refs.screenGui = nil
		Refs.phaseLabel = nil
		Refs.windowLabel = nil
		Refs.fuelLabel = nil
		Refs.vyLabel = nil
	end
end

function RunwaySession.HudEnsure()
	if Refs.screenGui then
		return
	end
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "JumpRunwayHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 80
	gui.Parent = playerGui
	Refs.screenGui = gui

	local function makeLabel(name: string, y: number): TextLabel
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 0.35
		t.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
		t.TextColor3 = Color3.fromRGB(240, 240, 255)
		t.TextSize = 18
		t.Font = Enum.Font.GothamMedium
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.Size = UDim2.new(0.35, 0, 0, 28)
		t.Position = UDim2.new(0.02, 0, 0, y)
		t.Parent = gui
		return t
	end

	Refs.phaseLabel = makeLabel("PhaseLabel", 72)
	Refs.windowLabel = makeLabel("WindowLabel", 104)
	Refs.fuelLabel = makeLabel("FuelLabel", 136)
	Refs.vyLabel = makeLabel("VyLabel", 168)
	Refs.stateLabel = makeLabel("StateLabel", 200)
end

function RunwaySession.HudRefresh()
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		RunwaySession.HudDestroy()
		return
	end
	RunwaySession.HudEnsure()
	local _c, humanoid, hrp = RunwaySession.GetCharacterParts()
	local dist = 0
	if hrp ~= nil and localState.runwayOrigin ~= nil then
		dist = math.max(0, RunwaySession.CurrentAlongProgress(hrp))
	end
	if Refs.phaseLabel then
		local extra = ""
		if localState.finalScore ~= nil then
			extra = string.format("  FINAL %.1f", localState.finalScore :: number)
		end
		Refs.phaseLabel.Text = string.format(
			"JumpRunway  phase=%d  dist=%.1f  jumps=%d%s",
			localState.phase,
			dist,
			localState.takeoffCount,
			extra
		)
	end
	if Refs.windowLabel then
		local nowClock = os.clock()
		local show = false
		local remain = 0.0
		if cfg.T_WINDOW > 0 then
			local inLineWindow = RunwaySession.LineHudActive(nowClock)
			local inChainHud = RunwaySession.ChainHudActive(nowClock)
			if inLineWindow or inChainHud then
				show = true
				if localState.tHudStart ~= nil then
					remain = math.max(0, cfg.T_WINDOW - (nowClock - (localState.tHudStart :: number)))
				else
					remain = cfg.T_WINDOW
				end
			end
		end
		if show then
			Refs.windowLabel.Text = string.format("Window  %.2fs", remain)
			Refs.windowLabel.Visible = true
		else
			Refs.windowLabel.Visible = false
		end
	end
	if Refs.fuelLabel then
		if localState.fuel > 0.001 then
			local maxFuel = RunwaySession.GetExpectedPlayerMaxFuel()
			Refs.fuelLabel.Text = string.format("Dash fuel  %.1f/%.0f", localState.fuel, maxFuel)
			Refs.fuelLabel.Visible = true
		else
			Refs.fuelLabel.Visible = false
		end
	end
	if Refs.vyLabel then
		local vy = 0
		if hrp ~= nil then
			vy = hrp.AssemblyLinearVelocity.Y
		end
		Refs.vyLabel.Text = string.format("Vy  %.2f", vy)
	end
	if Refs.stateLabel then
		local humanoidState = "nil"
		if humanoid then
			humanoidState = humanoid:GetState().Name
		end
		Refs.stateLabel.Text = string.format("State  ph=%d  slide=%s  finSub=%d  hState=%s", localState.phase, localState.runwaySlideKind, localState.finalLandSubPhase, humanoidState)
	end
end

function RunwaySession.RestoreRunningStateAfterFinalSegment(humanoid: Humanoid?)
	if Refs.runningStateEnabledBeforeFinalSegment == nil then
		return
	end
	if humanoid ~= nil and humanoid.Parent ~= nil then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, Refs.runningStateEnabledBeforeFinalSegment :: boolean)
	end
	Refs.runningStateEnabledBeforeFinalSegment = nil
end

-- 终局空中冲刺：物理步前禁用 Running，否则 Humanoid 会因高沿轴速在 Physics 步内切回 Running。
function RunwaySession.ApplyRunwayHumanoidFinalSegmentStateGate(humanoid: Humanoid)
	-- 宝箱反弹结束等待/开箱：恢复 Running 门闸，勿与站立姿态抢 Physics
	if Refs.chestRewardWaitPose == true or Refs.chestBounceActive == true then
		RunwaySession.RestoreRunningStateAfterFinalSegment(humanoid)
		return
	end
	local inFinalSegment = RunwaySession.IsRunwayFinalAirbornePhase() or RunwaySession.IsRunwayFinalLandingSlidePhase()
	if not inFinalSegment then
		RunwaySession.RestoreRunningStateAfterFinalSegment(humanoid)
		return
	end
	if Refs.runningStateEnabledBeforeFinalSegment == nil then
		Refs.runningStateEnabledBeforeFinalSegment = humanoid:GetStateEnabled(Enum.HumanoidStateType.Running)
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
end

function RunwaySession.SyncRunwayFinalSegmentLocomotionPrePhysics(humanoid: Humanoid, hrp: BasePart?)
	if Refs.chestRewardWaitPose == true then
		RunwaySession.ApplyRunwayHumanoidFinalSegmentStateGate(humanoid)
		if hrp ~= nil then
			local forwardWait = NormalizeRunwayForward(localState.runwayForward)
			RunwaySession.ApplyLittleElfChestStandingWaitOrientation(humanoid, hrp, forwardWait)
		end
		return
	end
	if Refs.chestBounceActive == true then
		RunwaySession.ApplyRunwayHumanoidFinalSegmentStateGate(humanoid)
		return
	end
	RunwaySession.ApplyRunwayHumanoidFinalSegmentStateGate(humanoid)
	if RunwaySession.IsRunwayFinalAirbornePhase() then
		RunwaySession.EnsureHumanoidFreefallState(humanoid)
	end
	if RunwaySession.IsRunwayFinalLandingSlidePhase() then
		RunwaySession.EnsureHumanoidFinalSlidePhysicsState(humanoid)
	end
end

function RunwaySession.ApplyRunwayHumanoidJumpState(humanoid: Humanoid?, runwayLocomotionActive: boolean)
	if not runwayLocomotionActive then
		if humanoid ~= nil then
			humanoid:SetStateEnabled(
				Enum.HumanoidStateType.Jumping,
				if Refs.jumpStateEnabledBeforeRunway == nil then true else Refs.jumpStateEnabledBeforeRunway
			)
		end
		Refs.jumpStateEnabledBeforeRunway = nil
		RunwaySession.RestoreRunningStateAfterFinalSegment(humanoid)
		return
	end
	if humanoid == nil then
		return
	end
	if Refs.jumpStateEnabledBeforeRunway == nil then
		Refs.jumpStateEnabledBeforeRunway = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
end

function RunwaySession.GetRunwayEffectiveGravityScale(): number
	if localState.phase == Ph.Slide then
		if localState.runwaySlideKind == SlideKindFinalLanding then
			if localState.finalLandSubPhase == 1 then
				local ga = cfg.RUNWAY_FINAL_LAND_PHASE_A_EFFECTIVE_GRAVITY_SCALE
				return (typeof(ga) == "number" and ga == ga and ga > 0) and ga or cfg.RUNWAY_SESSION_EFFECTIVE_GRAVITY_SCALE
			end
			return cfg.RUNWAY_SESSION_EFFECTIVE_GRAVITY_SCALE
		elseif localState.runwaySlideKind == SlideKindMiss then
			return cfg.RUNWAY_SESSION_EFFECTIVE_GRAVITY_SCALE
		end
		return cfg.RUNWAY_SLIDE_EFFECTIVE_GRAVITY_SCALE
	end
	if localState.phase == Ph.Airborne and localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
		if localState.dashHeld and localState.fuel > 0 then
			return cfg.RUNWAY_FINAL_DASH_EFFECTIVE_GRAVITY_SCALE
		end
	end
	return cfg.RUNWAY_SESSION_EFFECTIVE_GRAVITY_SCALE
end

function RunwaySession.DestroyRunwayGravityForce()
	if Refs.runwayGravityVectorForce ~= nil then
		Refs.runwayGravityVectorForce:Destroy()
		Refs.runwayGravityVectorForce = nil
	end
	if Refs.runwayGravityAttachment ~= nil then
		Refs.runwayGravityAttachment:Destroy()
		Refs.runwayGravityAttachment = nil
	end
end

function RunwaySession.EnsureRunwayGravityForce(hrp: BasePart)
	if Refs.runwayGravityVectorForce ~= nil and Refs.runwayGravityVectorForce.Parent == hrp then
		return
	end
	RunwaySession.DestroyRunwayGravityForce()
	local att = Instance.new("Attachment")
	att.Name = "JumpRunwayGravityAtt"
	att.Parent = hrp
	local vf = Instance.new("VectorForce")
	vf.Name = "JumpRunwayGravityForce"
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Attachment0 = att
	vf.ApplyAtCenterOfMass = true
	vf.Parent = hrp
	Refs.runwayGravityAttachment = att
	Refs.runwayGravityVectorForce = vf
end

function RunwaySession.UpdateRunwayGravityForce(hrp: BasePart)
	if Refs.runwayGravityVectorForce == nil or Refs.runwayGravityVectorForce.Parent == nil then
		return
	end
	local g = workspace.Gravity
	if g < 1e-3 then
		g = 196.2
	end
	local effScale = RunwaySession.GetRunwayEffectiveGravityScale()
	effScale = math.clamp(effScale, 0.02, 1)
	local mass = hrp.AssemblyMass
	if mass < 1e-4 then
		mass = 1
	end
	Refs.runwayGravityVectorForce.Force = Vector3.new(0, mass * g * (1 - effScale), 0)
end

function RunwaySession.ClearRunwayFlyingHumanoid(humanoid: Humanoid?)
	if Refs.flyingStateEnabledBeforeRunway == nil then
		return
	end
	if humanoid ~= nil then
		if humanoid:GetState() == Enum.HumanoidStateType.Flying then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Flying, Refs.flyingStateEnabledBeforeRunway :: boolean)
	end
	Refs.flyingStateEnabledBeforeRunway = nil
end

function RunwaySession.GetExpectedPlayerWalkSpeed(): number
	local walkSpeedConfig = GameConfig.Shop.WalkSpeed
	local fallback = walkSpeedConfig.abilityList[1] or 16
	local info = ClientGameInfo.GetLocalPlayerInfo()
	if info == nil then
		return fallback
	end
	local level = info.shopInfo.walkSpeedLevel or 1
	local maxLevel = walkSpeedConfig.maxLevel
	if typeof(level) ~= "number" or level ~= level then
		level = 1
	end
	level = math.clamp(math.floor(level), 1, maxLevel)
	return walkSpeedConfig.abilityList[level] or fallback
end

function RunwaySession.GetExpectedPlayerMaxFuel(): number
	local fallback = 2.5
	local info = ClientGameInfo.GetLocalPlayerInfo()
	if info == nil then
		return fallback
	end
	local currentId = info.jetpackInventory.currentId or "1"
	local jetpackData = GameConfig.JetpackDataMap[tonumber(currentId)]
	if jetpackData then
		return jetpackData.fuel
	end
	return fallback
end

function RunwaySession.GetCurrentFuel(): number
	-- 终局冲刺段才返回实时燃料；之前显示最大值（UI 显示满格）
	if localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
		return localState.fuel
	end
	return RunwaySession.GetExpectedPlayerMaxFuel()
end

function RunwaySession.GetExpectedPlayerMaxThrustSpeed(): number
	local fallback = 100
	local info = ClientGameInfo.GetLocalPlayerInfo()
	if info == nil then
		return fallback
	end
	local currentId = info.jetpackInventory.currentId or "1"
	local jetpackData = GameConfig.JetpackDataMap[tonumber(currentId)]
	if jetpackData then
		return jetpackData.thrust
	end
	return fallback
end

function RunwaySession.ApplyExpectedWalkSpeedAfterRunway(humanoid: Humanoid?)
	if humanoid == nil then
		return
	end
	local expected = RunwaySession.GetExpectedPlayerWalkSpeed()
	if humanoid.WalkSpeed ~= expected then
		humanoid.WalkSpeed = expected
	end
end

function RunwaySession.GetBoostedVerticalY(rawY: number): number
	if localState.jumpBoostVy ~= nil and os.clock() < localState.jumpBoostUntilClock then
		return math.max(rawY, localState.jumpBoostVy :: number)
	end
	return rawY
end

function RunwaySession.ClearJumpBoostIfNeeded(phase: number)
	if
		phase == Ph.Airborne
		or phase == Ph.Slide
		or phase == Ph.RunEnded
		or phase == Ph.ScoreLocked
		or phase == Ph.Idle
		or phase == Ph.Cleaning
	then
		localState.jumpBoostVy = nil
		localState.jumpBoostUntilClock = 0
	end
end

function RunwaySession.ClearJumpHorizontalLerp()
	localState.jumpHorizLerpStartClock = nil
	localState.jumpHorizLerpDuration = 0
end

function RunwaySession.EaseOutQuad01(t: number): number
	local u = math.clamp(t, 0, 1)
	return 1 - (1 - u) * (1 - u)
end

function RunwaySession.GetJumpHorizontalForwardSpeed(nowClock: number, segmentIndex: number): number
	local maxSpd, minSpd =
		GameConfig.GetJumpRunwayJumpSpeedLimitsForSegment(segmentIndex, localState.jumpSpeedCumulativeRatingBonus, GetJumpPowerBaseSpeed())
	local startClock = localState.jumpHorizLerpStartClock
	if startClock == nil then
		return minSpd
	end
	local duration = localState.jumpHorizLerpDuration
	if duration < 1e-4 then
		return minSpd
	end
	local progress = (nowClock - startClock) / duration
	if progress >= 1 then
		return minSpd
	end
	local curveName = cfg.JUMP_SPEED_LERP_CURVE
	local eased = if curveName == "ease_out" then RunwaySession.EaseOutQuad01(progress) else progress
	return maxSpd + (minSpd - maxSpd) * eased
end

function RunwaySession.UpdateAutoRunVelocity(hrp: BasePart, forward: Vector3, dt: number, humanoid: Humanoid)
	local v = hrp.AssemblyLinearVelocity
	local vy = RunwaySession.GetBoostedVerticalY(v.Y)
	local horiz = HorizontalVelocity(v)
	local fwdH = forward
	local alongH = horiz:Dot(fwdH)
	local perpH = horiz - fwdH * alongH
	local perpDamp = math.clamp(1 - 14 * dt, 0, 1)
	local nowClock = os.clock()
	local segForDefault = math.max(1, localState.takeoffCount)
	local _, defaultMinAlong = GameConfig.GetJumpRunwayJumpSpeedLimitsForSegment(
		segForDefault,
		localState.jumpSpeedCumulativeRatingBonus,
		GetJumpPowerBaseSpeed()
	)
	local forwardSpeed = defaultMinAlong
	if localState.takeoffCount == 0 then
		-- 首段 AutoRun / BeginLine 窗（含 JumpWindow 漂移）统一使用 FIRST_TAKEOFF_AUTORUN_SPEED。
		forwardSpeed = cfg.FIRST_TAKEOFF_AUTORUN_SPEED
	elseif localState.phase == Ph.Airborne and localState.takeoffCount <= cfg.N_TOTAL_JUMPS then
		if localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
			local base = RunwaySession.GetJumpHorizontalForwardSpeed(nowClock, localState.takeoffCount)
			local playerThrustSpeed = RunwaySession.GetExpectedPlayerMaxThrustSpeed()
			local capExtra = math.max(0, playerThrustSpeed)
			if localState.dashHeld and localState.fuel > 0 then
				localState.finalDashAlongExtra = math.min(
					localState.finalDashAlongExtra + cfg.DASH_ACCEL * dt,
					capExtra
				)
			else
				local decelPerSec = math.clamp(cfg.FINAL_DASH_ALONG_EXTRA_DECEL_PER_SEC, 0, 80)
				localState.finalDashAlongExtra *= math.clamp(1 - decelPerSec * dt, 0, 1)
				if localState.finalDashAlongExtra < 0.5 then
					localState.finalDashAlongExtra = 0
				end
			end
			forwardSpeed = math.min(base + localState.finalDashAlongExtra, base + playerThrustSpeed)
			localState.finalDashAlongExtra = math.max(0, forwardSpeed - base)
		else
			-- Airborne 全程走跳跃水平 lerp，不因落地窗口内判地切回 minAlongGrounded（会触发 run 并覆盖起跳冲量）。
			forwardSpeed = RunwaySession.GetJumpHorizontalForwardSpeed(nowClock, localState.takeoffCount)
		end
	end
	hrp.AssemblyLinearVelocity = fwdH * forwardSpeed + Vector3.new(0, vy, 0) + perpH * perpDamp
end

function RunwaySession.ApplyJumpWindowWalkPhysics(_humanoid: Humanoid, hrp: BasePart, _forward: Vector3)
	local v = hrp.AssemblyLinearVelocity
	local vy = RunwaySession.GetBoostedVerticalY(v.Y)
	hrp.AssemblyLinearVelocity = Vector3.new(v.X, vy, v.Z)
end

function RunwaySession.UpdateSlideVelocity(hrp: BasePart, forward: Vector3, nowClock: number)
	local v = hrp.AssemblyLinearVelocity
	local duration = math.max(0.01, cfg.SLIDE_DURATION_SEC)
	local elapsed = math.max(0, nowClock - localState.slideStartClock)
	local alpha = math.clamp(elapsed / duration, 0, 1)
	local slideSegIndex = math.clamp(math.max(1, localState.takeoffCount), 1, cfg.N_TOTAL_JUMPS)
	local _, slideFloorAlong = GameConfig.GetJumpRunwayJumpSpeedLimitsForSegment(
		slideSegIndex,
		localState.jumpSpeedCumulativeRatingBonus,
		GetJumpPowerBaseSpeed()
	)
	local slideSpeed = math.max(0, slideFloorAlong * (1 - alpha))
	hrp.AssemblyLinearVelocity = forward * slideSpeed + Vector3.new(0, v.Y * cfg.SLIDE_VERTICAL_DAMP, 0)
end

function RunwaySession.ClearFinalLandingSlideModuleLocals()
	Refs.finalLandTumbleStartHrpCf = nil
end

function RunwaySession.RestorePlatformStandAfterFinalLand(humanoid: Humanoid?)
	if Refs.platformStandSavedBeforeFinalLand == nil then
		return
	end
	if humanoid ~= nil and humanoid.Parent ~= nil then
		humanoid.PlatformStand = Refs.platformStandSavedBeforeFinalLand :: boolean
	end
	Refs.platformStandSavedBeforeFinalLand = nil
end

function RunwaySession.EnsurePlatformStandForFinalLandSlide(humanoid: Humanoid?)
	if humanoid == nil then
		return
	end
	if Refs.platformStandSavedBeforeFinalLand ~= nil then
		return
	end
	Refs.platformStandSavedBeforeFinalLand = humanoid.PlatformStand
	humanoid.PlatformStand = true
end

function RunwaySession.CFrameAtPositionWithSameOrientation(cf: CFrame, pos: Vector3): CFrame
	local rx, ry, rz = cf:ToOrientation()
	return CFrame.new(pos) * CFrame.fromOrientation(rx, ry, rz)
end

function RunwaySession.BuildProneRunwayCFrame(pos: Vector3, runwayForward: Vector3): CFrame
	local f = runwayForward
	if f.Magnitude < 1e-4 then
		f = Vector3.new(0, 0, -1)
	else
		f = Vector3.new(f.X, 0, f.Z)
		if f.Magnitude < 1e-4 then
			f = Vector3.new(0, 0, -1)
		else
			f = f.Unit
		end
	end
	local right = f:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-4 then
		right = Vector3.new(1, 0, 0)
	else
		right = right.Unit
	end
	return CFrame.fromMatrix(pos, right, f)
end

function RunwaySession.RotateCFrameAroundWorldAxisAtPoint(cf: CFrame, point: Vector3, axis: Vector3, angle: number): CFrame
	if axis.Magnitude < 1e-6 then
		return cf
	end
	local ax = axis.Unit
	local rot = CFrame.fromAxisAngle(ax, angle)
	return CFrame.new(point) * rot * CFrame.new(-point) * cf
end

function RunwaySession.GetFinalLandAxisRollWorldFromForward(forward: Vector3): Vector3
	local fwdH = Vector3.new(forward.X, 0, forward.Z)
	if fwdH.Magnitude < 1e-4 then
		fwdH = Vector3.new(0, 0, -1)
	else
		fwdH = fwdH.Unit
	end
	local axisRoll = fwdH:Cross(Vector3.yAxis)
	if axisRoll.Magnitude < 1e-4 then
		return Vector3.new(1, 0, 0)
	end
	return axisRoll.Unit
end

function RunwaySession.ComputeFinalLandTumbleSpunAt(pos: Vector3, forward: Vector3, signedRollRad: number): CFrame
	local startCfStored = Refs.finalLandTumbleStartHrpCf
	if startCfStored == nil then
		return CFrame.new(pos)
	end
	local axisRoll = RunwaySession.GetFinalLandAxisRollWorldFromForward(forward)
	local startAtPos = RunwaySession.CFrameAtPositionWithSameOrientation(startCfStored, pos)
	return RunwaySession.RotateCFrameAroundWorldAxisAtPoint(startAtPos, pos, axisRoll, signedRollRad)
end

function RunwaySession.ClampFinalLandPhaseARetain(raw: any, defaultRetain: number): number
	if typeof(raw) == "number" and raw == raw then
		return math.clamp(raw, 0.01, 1)
	end
	return defaultRetain
end

function RunwaySession.SampleFinalLandLandingAlongAndVy(hrp: BasePart, fwdH: Vector3): (number, number)
	local horiz = HorizontalVelocity(hrp.AssemblyLinearVelocity)
	local landingAlong = math.max(0, horiz:Dot(fwdH))
	local landingVy = hrp.AssemblyLinearVelocity.Y
	return landingAlong, landingVy
end

function RunwaySession.ComputeFinalLandPhaseAPopAlong(landingAlong: number, popIndex: number): number
	local retain = RunwaySession.ClampFinalLandPhaseARetain(cfg.RUNWAY_FINAL_LAND_PHASE_A_ALONG_RETAIN_PER_BOUNCE, 0.82)
	local maxSpd = cfg.ANTI_CHEAT_MAX_ALONG_SPEED
	local scaled = landingAlong * retain ^ popIndex
	return math.clamp(scaled, 0, maxSpd)
end

function RunwaySession.ComputeFinalLandPhaseAPopVy(landingVy: number, popIndex: number): number
	local retain = RunwaySession.ClampFinalLandPhaseARetain(cfg.RUNWAY_FINAL_LAND_PHASE_A_VY_RETAIN_PER_BOUNCE, 0.85)
	local minVyRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_MIN_POP_VY
	local minVy = (typeof(minVyRaw) == "number" and minVyRaw == minVyRaw and minVyRaw >= 0) and minVyRaw or 3
	local scaled = math.abs(landingVy) * retain ^ popIndex
	return math.max(minVy, scaled)
end

function RunwaySession.ShouldEnterFinalLandPhaseB(popCount: number, landingAlong: number): boolean
	local maxPopRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_MAX_POP_COUNT
	local maxPop = (typeof(maxPopRaw) == "number" and maxPopRaw == maxPopRaw and maxPopRaw >= 1) and math.floor(maxPopRaw) or 4
	local minAlongRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_MIN_ALONG_SPEED
	local minAlong = (typeof(minAlongRaw) == "number" and minAlongRaw == minAlongRaw and minAlongRaw >= 0) and minAlongRaw or 12
	if popCount >= maxPop then
		return true
	end
	if landingAlong < minAlong then
		return true
	end
	return false
end

function RunwaySession.ResolveFinalLandAlongSpeedForPhaseB(hrp: BasePart, fwdH: Vector3): number
	local horiz = HorizontalVelocity(hrp.AssemblyLinearVelocity)
	local sampledAlong = math.max(0, horiz:Dot(fwdH))
	local lockedAlong = math.max(0, localState.finalLandLockedTumbleAlong)
	local cachedLandingAlong = localState.finalLandCachedLandingAlong
	if typeof(cachedLandingAlong) ~= "number" or cachedLandingAlong ~= cachedLandingAlong then
		cachedLandingAlong = 0
	else
		cachedLandingAlong = math.max(0, cachedLandingAlong)
	end
	local storedStart = localState.finalLandProneSlideAlongSpeedStart
	if typeof(storedStart) ~= "number" or storedStart ~= storedStart then
		storedStart = 0
	else
		storedStart = math.max(0, storedStart)
	end
	return math.clamp(
		math.max(sampledAlong, lockedAlong, cachedLandingAlong, storedStart),
		0,
		cfg.ANTI_CHEAT_MAX_ALONG_SPEED
	)
end

function RunwaySession.ApplyFinalLandPhaseAPop(hrp: BasePart, fwdH: Vector3, nowClock: number)
	local v = hrp.AssemblyLinearVelocity
	local landingAlong, landingVy = RunwaySession.SampleFinalLandLandingAlongAndVy(hrp, fwdH)
	if landingAlong < 1 then
		if not localState.finalLandTumbleImpulseApplied then
			local cachedLandingAlong = localState.finalLandCachedLandingAlong
			if typeof(cachedLandingAlong) == "number" and cachedLandingAlong == cachedLandingAlong then
				landingAlong = math.max(landingAlong, cachedLandingAlong)
			end
		elseif localState.finalLandLockedTumbleAlong > 0 then
			landingAlong = localState.finalLandLockedTumbleAlong
		end
	end
	-- 首次弹跳使用缓存坠落速度；后续弹跳使用前一次弹跳速度 x 折减系数
	if not localState.finalLandTumbleImpulseApplied then
		if localState.finalLandCachedLandingVy ~= nil then
			landingVy = localState.finalLandCachedLandingVy :: number
			localState.finalLandCachedLandingVy = nil
		end
	else
		local prevVy = localState.finalLandTumblePrevPopVy
		if prevVy ~= nil and prevVy > 0 then
			landingVy = -(prevVy :: number)
		end
	end
	local popIndex = localState.finalLandPhaseAPopCount + 1
	-- 沿轴速度：每次从落地沿轴速 x retain（不走 retain^popIndex 多折减）
	local retainAlong = RunwaySession.ClampFinalLandPhaseARetain(cfg.RUNWAY_FINAL_LAND_PHASE_A_ALONG_RETAIN_PER_BOUNCE, 0.82)
	local alongPop = math.clamp(landingAlong * retainAlong, 0, cfg.ANTI_CHEAT_MAX_ALONG_SPEED)
	-- 竖直弹跳速度：首次用缓存 vy x retain，后续用前一次弹跳速度 x retain
	-- 不走 ComputeFinalLandPhaseAPopVy（它用 retain^popIndex 多折减）
	local retainVy = RunwaySession.ClampFinalLandPhaseARetain(cfg.RUNWAY_FINAL_LAND_PHASE_A_VY_RETAIN_PER_BOUNCE, 0.85)
	local minVyRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_MIN_POP_VY
	local minVy = (typeof(minVyRaw) == "number" and minVyRaw == minVyRaw and minVyRaw >= 0) and minVyRaw or 3
	local vyPop = math.max(minVy, math.abs(landingVy) * retainVy)
	localState.finalLandPhaseAPopCount = popIndex
	if not localState.finalLandTumbleImpulseApplied then
		localState.finalLandTumbleRollAngleRad = 0
	end
	localState.finalLandTumbleImpulseApplied = true
	local gBaseImp = workspace.Gravity
	if gBaseImp < 1e-3 then
		gBaseImp = 196.2
	end
	local gScaleAImp = cfg.RUNWAY_FINAL_LAND_PHASE_A_EFFECTIVE_GRAVITY_SCALE
	if typeof(gScaleAImp) ~= "number" or gScaleAImp ~= gScaleAImp or gScaleAImp <= 0 then
		gScaleAImp = cfg.RUNWAY_SESSION_EFFECTIVE_GRAVITY_SCALE
	end
	local gEffImp = gBaseImp * gScaleAImp
	local T_pred: number
	local useAirClock: boolean
	if vyPop > 0.5 then
		T_pred = math.clamp(2 * vyPop / math.max(1e-4, gEffImp), 0.12, 8)
		useAirClock = true
	else
		T_pred = math.max(0.12, cfg.RUNWAY_FINAL_LAND_TUMBLE_NO_POP_ROLL_SEC)
		useAirClock = false
	end
	localState.finalLandTumblePredAirTimeSec = T_pred
	localState.finalLandTumbleUseAirClock = useAirClock
	localState.finalLandTumbleAirAccumSec = 0
	localState.finalLandTumbleLeftGround = false
	if vyPop > 1e-5 then
		localState.jumpBoostVy = vyPop
		localState.jumpBoostUntilClock = nowClock + cfg.RUNWAY_JUMP_BOOST_HOLD_SEC
	else
		localState.jumpBoostVy = nil
		localState.jumpBoostUntilClock = 0
	end
	localState.finalLandLockedTumbleAlong = alongPop
	localState.finalLandTumblePrevPopVy = vyPop
	local horizPh = HorizontalVelocity(v)
	local alongHPh = horizPh:Dot(fwdH)
	local perpHPh = horizPh - fwdH * alongHPh
	local zeroPerp = cfg.RUNWAY_FINAL_LAND_TUMBLE_ZERO_PERP == true
	local perpMul = if zeroPerp then 0 else 0.35
	hrp.AssemblyLinearVelocity = fwdH * alongPop + Vector3.new(0, vyPop, 0) + perpHPh * perpMul
end

function RunwaySession.ComputeFinalLandTumbleRollOmegaRadPerSec(): number
	local scaleRaw = cfg.RUNWAY_FINAL_LAND_TUMBLE_ROLL_OMEGA_SCALE
	local scale = (typeof(scaleRaw) == "number" and scaleRaw == scaleRaw and scaleRaw > 0) and scaleRaw or 1
	local T_pred = math.max(0.05, localState.finalLandTumblePredAirTimeSec)
	local periodRaw = cfg.RUNWAY_FINAL_LAND_TUMBLE_ROLL_PERIOD_SEC
	if typeof(periodRaw) == "number" and periodRaw == periodRaw and periodRaw > 0.05 then
		return (2 * math.pi) / periodRaw * scale
	end
	local tMinRaw = cfg.RUNWAY_FINAL_LAND_TUMBLE_ROLL_T_REF_MIN_SEC
	local tMaxRaw = cfg.RUNWAY_FINAL_LAND_TUMBLE_ROLL_T_REF_MAX_SEC
	local tMin = (typeof(tMinRaw) == "number" and tMinRaw == tMinRaw) and tMinRaw or 0.12
	local tMax = (typeof(tMaxRaw) == "number" and tMaxRaw == tMaxRaw) and tMaxRaw or 1.35
	tMax = math.max(tMax, tMin)
	local T_ref = math.clamp(T_pred, tMin, tMax)
	local omega = (2 * math.pi) / T_ref
	return omega * scale
end

function RunwaySession.StartFinalLandPronePhase(nowClock: number, hrp: BasePart?, forward: Vector3?)
	if localState.finalLandSubPhase ~= 1 then
		return
	end
	localState.finalLandSubPhase = 2
	localState.finalLandPronePhaseStartClock = nowClock
	localState.finalLandTumbleAirAccumSec = math.max(
		localState.finalLandTumbleAirAccumSec,
		localState.finalLandTumblePredAirTimeSec
	)
	if hrp ~= nil and forward ~= nil then
		localState.finalLandProneBStage = 1
		local fwdHInit = Vector3.new(forward.X, 0, forward.Z)
		if fwdHInit.Magnitude < 1e-4 then
			fwdHInit = Vector3.new(0, 0, -1)
		else
			fwdHInit = fwdHInit.Unit
		end
		local vv = hrp.AssemblyLinearVelocity
		local horizInit = HorizontalVelocity(vv)
		local alongFwd = math.max(0, horizInit:Dot(fwdHInit))
		local maxAlongCap = cfg.ANTI_CHEAT_MAX_ALONG_SPEED
		local alongSpdEnter = RunwaySession.ResolveFinalLandAlongSpeedForPhaseB(hrp, fwdHInit)
		if alongSpdEnter < 1e-2 then
			alongSpdEnter = math.clamp(alongFwd, 0, maxAlongCap)
		end
		localState.finalLandProneSlideAlongSpeedStart = alongSpdEnter
		hrp.AssemblyLinearVelocity = fwdHInit * alongSpdEnter + Vector3.new(0, 0, 0)
		hrp.AssemblyAngularVelocity = Vector3.zero
		localState.finalLandProneSlideAlongStart = RunwaySession.CurrentAlongProgress(hrp)
		Refs.chestSlideFwdH = fwdHInit
		-- 记录本次跑道的沿轴距离，用于宝箱与怪物动态配置
		local alongAtPhaseB = RunwaySession.CurrentAlongProgress(hrp)
		Refs.lastRunAlongDistance = alongAtPhaseB
		-- 根据距离动态选择宝箱配置
		local chestByDist = GameConfig.GetLittleElfChestByDistance(alongAtPhaseB)
		local chestIdOverride = if chestByDist then chestByDist.id else nil
		Refs.chestDynamicConfigId = chestIdOverride
		-- 子阶段 B 入口：用实际位置刷新宝箱落点（创建时机已在进入终局 Slide 时按 A+B 总时长调度）
		local brakeK = cfg.RUNWAY_FINAL_LAND_PRONE_SLIDE_BRAKE_EXP
		local aheadStuds = cfg.RUNWAY_CHEST_SPAWN_AHEAD_STUDS
		if typeof(aheadStuds) ~= "number" or aheadStuds ~= aheadStuds or aheadStuds < 0 then
			aheadStuds = 3
		end
		local dStop, tSlideB = RunwaySession.ComputePhaseBSlideStopDistance(alongSpdEnter, brakeK)
		local placeDistance = dStop + aheadStuds
		Refs.chestPredictedPlaceDistance = placeDistance
		local spawnPos = RunwaySession.ComputeLittleElfChestSpawnPosition(hrp, fwdHInit, placeDistance)
		Refs.chestScheduledSpawnPos = spawnPos
		RunwaySession.ScheduleLittleElfChestAtPhaseBEnter(fwdHInit, alongSpdEnter, spawnPos, tSlideB)
	else
		localState.finalLandProneBStage = 1
		localState.finalLandProneSlideAlongStart = nil
	end
end

function RunwaySession.ApplyFinalLandingSlidePhysics(hrp: BasePart, forward: Vector3, dt: number, nowClock: number, humanoid: Humanoid)
	local fwdH = Vector3.new(forward.X, 0, forward.Z)
	if fwdH.Magnitude < 1e-4 then
		fwdH = Vector3.new(0, 0, -1)
	else
		fwdH = fwdH.Unit
	end
	local v = hrp.AssemblyLinearVelocity
	local perpDamp = math.clamp(1 - 14 * dt, 0, 1)
	local zeroPerp = cfg.RUNWAY_FINAL_LAND_TUMBLE_ZERO_PERP == true
	local perpMulFrame = zeroPerp and 0 or perpDamp
	if localState.finalLandSubPhase == 2 then
		if localState.finalLandProneSlideAlongStart == nil then
			localState.finalLandProneSlideAlongStart = RunwaySession.CurrentAlongProgress(hrp)
		end
		local horiz = HorizontalVelocity(v)
		local alongH = horiz:Dot(fwdH)
		local perpH = horiz - fwdH * alongH
		if Refs.chestBounceActive == true then
			local slideFwd = Refs.chestSlideFwdH or fwdH
			if slideFwd.Magnitude < 1e-4 then
				slideFwd = fwdH
			else
				slideFwd = slideFwd.Unit
			end
			local bounceSpd = Refs.chestBounceAlongSpeed or cfg.RUNWAY_CHEST_BOUNCE_BACK_SPEED
			if typeof(bounceSpd) ~= "number" or bounceSpd ~= bounceSpd or bounceSpd < 0 then
				bounceSpd = 12
			end
			local damped = bounceSpd * math.exp(-14 * dt)
			hrp.AssemblyLinearVelocity = slideFwd * (-damped)
			hrp.AssemblyAngularVelocity = Vector3.zero
			return
		end
		if Refs.chestRewardWaitPose == true then
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			return
		end
		local brakeK = cfg.RUNWAY_FINAL_LAND_PRONE_SLIDE_BRAKE_EXP
		local alongStart = localState.finalLandProneSlideAlongSpeedStart
		if typeof(alongStart) ~= "number" or alongStart ~= alongStart or alongStart < 1e-2 then
			alongStart = RunwaySession.ResolveFinalLandAlongSpeedForPhaseB(hrp, fwdH)
			if alongStart > 1e-2 then
				localState.finalLandProneSlideAlongSpeedStart = alongStart
				localState.finalLandPronePhaseStartClock = nowClock
			end
		end
		local phaseStart = localState.finalLandPronePhaseStartClock
		if typeof(phaseStart) ~= "number" or phaseStart ~= phaseStart or phaseStart <= 0 then
			phaseStart = nowClock
			localState.finalLandPronePhaseStartClock = nowClock
		end
		local elapsed = math.max(0, nowClock - phaseStart)
		local newAlong = alongStart * math.exp(-brakeK * elapsed)
		newAlong = math.max(0, newAlong)
		hrp.AssemblyLinearVelocity = fwdH * newAlong + Vector3.new(0, 0, 0) + perpH * perpDamp
		-- 子阶段 B 仅由宝箱撞击流程结束，不因低速提前 slideEndClock
		return
	end
	if not localState.finalLandTumbleImpulseApplied then
		RunwaySession.ApplyFinalLandPhaseAPop(hrp, fwdH, nowClock)
		-- Physics 状态下 Humanoid 引擎会抵抗竖直速度；小幅抬升 HRP 确保离开地面碰撞
		if hrp.AssemblyLinearVelocity.Y > 1 then
			local poppedCf = hrp.CFrame + Vector3.new(0, 0.3, 0)
			hrp.CFrame = poppedCf
			hrp.AssemblyLinearVelocity = fwdH * localState.finalLandLockedTumbleAlong
				+ Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
		end
		return
	end
	local fullGroundTrack = RunwaySession.IsRunwayFinalLandFullBodyGrounded(humanoid, hrp)
	if localState.finalLandTumbleUseAirClock then
		if not fullGroundTrack then
			localState.finalLandTumbleLeftGround = true
		end
	else
		localState.finalLandTumbleAirAccumSec += dt
	end
	local alongSpd = math.clamp(localState.finalLandLockedTumbleAlong, 0, cfg.ANTI_CHEAT_MAX_ALONG_SPEED)
	local vyPhaseA = RunwaySession.GetBoostedVerticalY(v.Y)
	-- Physics 状态下 Humanoid 引擎会抵抗竖直速度；如果尚未离地且应有弹跳，保持最小离地速度
	if
		localState.finalLandTumbleUseAirClock
		and not localState.finalLandTumbleLeftGround
		and localState.finalLandPhaseAPopCount >= 1
	then
		local minVyKeep = cfg.RUNWAY_FINAL_LAND_PHASE_A_MIN_POP_VY
		vyPhaseA = math.max(vyPhaseA, minVyKeep)
	end
	local horiz = HorizontalVelocity(v)
	local alongH = horiz:Dot(fwdH)
	local perpH = horiz - fwdH * alongH
	hrp.AssemblyLinearVelocity = fwdH * alongSpd + Vector3.new(0, vyPhaseA, 0) + perpH * perpMulFrame
end

function RunwaySession.ApplyFinalLandingRenderOrientation(_humanoid: Humanoid, hrp: BasePart, forward: Vector3, dt: number, _nowClock: number, proneOffsetOverride: number?)
	local pos = hrp.Position
	local linVel = hrp.AssemblyLinearVelocity
	if Refs.finalLandTumbleStartHrpCf == nil then
		Refs.finalLandTumbleStartHrpCf = hrp.CFrame
	end
	if localState.finalLandSubPhase == 2 then
		local proneOffset = proneOffsetOverride
		if typeof(proneOffset) ~= "number" or proneOffset ~= proneOffset then
			proneOffset = cfg.RUNWAY_FINAL_LAND_PRONE_GROUND_OFFSET
			if typeof(proneOffset) ~= "number" or proneOffset ~= proneOffset then
				proneOffset = 0
			end
		end
		local pronePos = Vector3.new(pos.X, pos.Y - proneOffset, pos.Z)
		local proneLocked = RunwaySession.BuildProneRunwayCFrame(pronePos, forward)
		hrp.CFrame = proneLocked
		hrp.AssemblyLinearVelocity = linVel
		hrp.AssemblyAngularVelocity = hrp.AssemblyAngularVelocity * math.exp(-18 * dt)
		return
	end
	local omegaDirect = cfg.RUNWAY_FINAL_LAND_PHASE_A_ROLL_OMEGA_RAD_PER_SEC
	local omega: number
	if typeof(omegaDirect) == "number" and omegaDirect == omegaDirect and math.abs(omegaDirect) > 1e-8 then
		omega = omegaDirect
	else
		local rollSignLegacy = cfg.RUNWAY_FINAL_LAND_TUMBLE_ROLL_SIGN
		if math.abs(rollSignLegacy) < 1e-6 then
			rollSignLegacy = 1
		end
		omega = RunwaySession.ComputeFinalLandTumbleRollOmegaRadPerSec() * rollSignLegacy
	end
	localState.finalLandTumbleRollAngleRad += omega * dt
	local spun = RunwaySession.ComputeFinalLandTumbleSpunAt(pos, forward, localState.finalLandTumbleRollAngleRad)
	hrp.CFrame = spun
	hrp.AssemblyLinearVelocity = linVel
	hrp.AssemblyAngularVelocity = hrp.AssemblyAngularVelocity * math.exp(-14 * dt)
end

function RunwaySession.EnterSlidePhase(nowClock: number, slideKind: string, humanoidOpt: Humanoid?)
	if localState.phase == Ph.Slide then
		return
	end
	RunwaySession.SlideTraceDestroy()
	local phaseBefore = localState.phase
	localState.phase = Ph.Slide
	localState.runwaySlideKind = slideKind
	RunwaySession.ClearJumpHorizontalLerp()
	localState.finalDashAlongExtra = 0
	localState.predictJumpWindowUntil = nil
	localState.lineJumpWindowExpireAt = nil
	localState.tHudStart = nil
	localState.firstGroundedInWindowClock = nil
	localState.chainJumpWindowAwaitingGround = false
	localState.slideStartClock = nowClock
	-- 进入终局 Slide 时清除冲刺状态，避免 Physics 状态下的残留干扰
	localState.dashHeld = false
	if slideKind == SlideKindFinalLanding then
		-- 终局落地保留燃料值，不清零
	else
		localState.fuel = 0
	end
	localState.finalDashAlongExtra = 0
	if slideKind == SlideKindFinalLanding then
		localState.jumpBoostVy = nil
		localState.jumpBoostUntilClock = 0
		localState.finalLandSubPhase = 1
		localState.finalLandPronePhaseStartClock = 0
		localState.finalLandPhaseAPopCount = 0
		localState.finalLandProneSlideAlongSpeedStart = 0
		localState.finalLandTumbleImpulseApplied = false
		localState.finalLandLockedTumbleAlong = 0
		localState.finalLandTumblePrevPopVy = 0
		localState.finalLandTumblePredAirTimeSec = 0
		localState.finalLandTumbleAirAccumSec = 0
		localState.finalLandTumbleLeftGround = false
		localState.finalLandTumbleUseAirClock = false
		RunwaySession.ClearFinalLandingSlideModuleLocals()
		localState.slideEndClock = nowClock + 7200
		localState.finalLandTumbleRollAngleRad = 0
		localState.finalLandProneBStage = 0
		localState.finalLandPronePrefallStartClock = 0
		localState.finalLandProneSlideAlongStart = nil
		localState.finalLandCachedLandingAlong = nil
		local _, _, hrpFinalLand = RunwaySession.GetCharacterParts()
		if hrpFinalLand ~= nil then
			local fwdLand = NormalizeRunwayForward(localState.runwayForward)
			local fwdHLand = Vector3.new(fwdLand.X, 0, fwdLand.Z)
			if fwdHLand.Magnitude < 1e-4 then
				fwdHLand = Vector3.new(0, 0, -1)
			else
				fwdHLand = fwdHLand.Unit
			end
			localState.finalLandCachedLandingAlong = math.max(
				0,
				HorizontalVelocity(hrpFinalLand.AssemblyLinearVelocity):Dot(fwdHLand)
			)
		end
		RunwaySession.EnsurePlatformStandForFinalLandSlide(humanoidOpt)
		if humanoidOpt ~= nil then
			RunwaySession.EnsureHumanoidFinalSlidePhysicsState(humanoidOpt)
		end
	elseif slideKind == SlideKindMiss then
		localState.jumpBoostVy = nil
		localState.jumpBoostUntilClock = 0
		localState.finalLandSubPhase = 2
		localState.finalLandPronePhaseStartClock = nowClock
		localState.finalLandPhaseAPopCount = 0
		localState.finalLandProneSlideAlongSpeedStart = 0
		localState.finalLandTumbleImpulseApplied = false
		localState.finalLandLockedTumbleAlong = 0
		localState.finalLandTumblePrevPopVy = 0
		localState.finalLandTumblePredAirTimeSec = 0
		localState.finalLandTumbleAirAccumSec = 0
		localState.finalLandTumbleLeftGround = false
		localState.finalLandTumbleUseAirClock = false
		RunwaySession.ClearFinalLandingSlideModuleLocals()
		localState.finalLandTumbleRollAngleRad = 0
		localState.finalLandProneBStage = 1
		localState.finalLandPronePrefallStartClock = 0
		localState.finalLandProneSlideAlongStart = nil
		localState.finalLandCachedLandingAlong = nil
		-- 用当前段最大水平速度（jumpPower + 累计起跳评级 bonus）作为滑行起始速度
		local _, maxSpdForSeg = GameConfig.GetJumpRunwayJumpSpeedLimitsForSegment(
			math.max(1, localState.takeoffCount),
			localState.jumpSpeedCumulativeRatingBonus,
			GetJumpPowerBaseSpeed()
		)
		local alongSpd = math.max(0, maxSpdForSeg)
		localState.finalLandProneSlideAlongSpeedStart = alongSpd
		-- 立即贴地，避免从空中下沉
		if humanoidOpt ~= nil then
			local _chSnap, _humSnap, hrpSnap = RunwaySession.GetCharacterParts()
			if hrpSnap ~= nil then
				local fwdSnap = NormalizeRunwayForward(localState.runwayForward)
				RunwaySession.SnapCharacterHrpToGround(humanoidOpt, hrpSnap, fwdSnap)
			end
		end
		RunwaySession.EnsurePlatformStandForFinalLandSlide(humanoidOpt)
		if humanoidOpt ~= nil then
			RunwaySession.EnsureHumanoidFinalSlidePhysicsState(humanoidOpt)
		end
		-- 计算制动停止时长
		local brakeK = cfg.RUNWAY_FINAL_LAND_PRONE_SLIDE_BRAKE_EXP
		if typeof(brakeK) ~= "number" or brakeK ~= brakeK or brakeK <= 0 then
			brakeK = 1.6
		end
		local _, tSlideStop = RunwaySession.ComputePhaseBSlideStopDistance(alongSpd, brakeK)
		localState.slideEndClock = nowClock + math.max(0.3, tSlideStop)
	else
		localState.finalLandSubPhase = 1
		localState.finalLandPronePhaseStartClock = 0
		localState.finalLandPhaseAPopCount = 0
		localState.finalLandProneSlideAlongSpeedStart = 0
		localState.finalLandTumbleImpulseApplied = false
		localState.finalLandTumblePredAirTimeSec = 0
		localState.finalLandTumbleAirAccumSec = 0
		localState.finalLandTumbleLeftGround = false
		localState.finalLandTumbleUseAirClock = false
		localState.finalLandLockedTumbleAlong = 0
		localState.finalLandTumblePrevPopVy = 0
		localState.finalLandTumbleRollAngleRad = 0
		localState.finalLandProneBStage = 0
		localState.finalLandPronePrefallStartClock = 0
		localState.finalLandProneSlideAlongStart = nil
		RunwaySession.ClearFinalLandingSlideModuleLocals()
		local slideDuration = math.max(0.01, cfg.SLIDE_DURATION_SEC)
		localState.slideEndClock = nowClock + slideDuration
	end
end

-- WindowDriftPhysicsActive: (humanoid: Humanoid, nowClock: number) -> boolean
-- GetEffectivePhysicsPhase: (humanoid: Humanoid, nowClock: number) -> number

local RUNWAY_LOCOMOTION_RUN = "run"
local RUNWAY_LOCOMOTION_WALK = "walk"
local RUNWAY_LOCOMOTION_FREEFALL = "freefall"
local RUNWAY_LOCOMOTION_NONE = "none"
local RUNWAY_GROUNDED_ALONG_CORRECT_THRESHOLD = 2.5

function RunwaySession.IsRunwayFinalAirbornePhase(): boolean
	return localState.phase == Ph.Airborne and localState.takeoffCount >= cfg.N_TOTAL_JUMPS
end

function RunwaySession.IsRunwayFinalLandingSlidePhase(): boolean
	return localState.phase == Ph.Slide and localState.runwaySlideKind == SlideKindFinalLanding
end

function RunwaySession.ResolveRunwayLocomotionMode(humanoid: Humanoid, nowClock: number): string
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		return RUNWAY_LOCOMOTION_NONE
	end
	-- 终局跳全程禁用 run/walk（含冲刺贴地误判）；Slide 由 Physics 姿态接管
	if localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
		if localState.phase == Ph.Airborne then
			return RUNWAY_LOCOMOTION_FREEFALL
		end
		if RunwaySession.IsRunwayFinalLandingSlidePhase() then
			return RUNWAY_LOCOMOTION_NONE
		end
	end
	if
		localState.phase == Ph.Slide
		and localState.runwaySlideKind == SlideKindFinalLanding
		and (localState.finalLandSubPhase == 1 or localState.finalLandSubPhase == 2)
	then
		return RUNWAY_LOCOMOTION_NONE
	end
	if Refs.chestRewardWaitPose == true or Refs.chestPostRewardExitCleanup == true then
		return RUNWAY_LOCOMOTION_NONE
	end
	local grounded = RunwaySession.IsRunwayScriptedGrounded(humanoid)
	if localState.phase == Ph.Airborne then
		if not grounded then
			return RUNWAY_LOCOMOTION_FREEFALL
		end
		if RunwaySession.ChainHudActive(nowClock) and RunwaySession.WindowDriftPhysicsActive(humanoid, nowClock) then
			return RUNWAY_LOCOMOTION_WALK
		end
		if RunwaySession.ChainHudActive(nowClock) then
			return RUNWAY_LOCOMOTION_RUN
		end
		return RUNWAY_LOCOMOTION_FREEFALL
	end
	if localState.phase == Ph.JumpWindow then
		if grounded and RunwaySession.WindowDriftPhysicsActive(humanoid, nowClock) then
			return RUNWAY_LOCOMOTION_WALK
		end
		if grounded then
			return RUNWAY_LOCOMOTION_RUN
		end
		return RUNWAY_LOCOMOTION_FREEFALL
	end
	if localState.phase == Ph.AutoRun and grounded then
		return RUNWAY_LOCOMOTION_RUN
	end
	return RUNWAY_LOCOMOTION_NONE
end

function RunwaySession.EnsureHumanoidRunningState(humanoid: Humanoid)
	if not RunwaySession.IsRunwayScriptedGrounded(humanoid) then
		return
	end
	local st = humanoid:GetState()
	if st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.RunningNoPhysics then
		return
	end
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end)
end

-- 慢漂无 HumanoidStateType.Walking；用 Running + JUMP_WINDOW_WALK_SPEED + Move(forward)，默认 Animate 会播 walk。
function RunwaySession.EnsureHumanoidWalkingState(humanoid: Humanoid)
	RunwaySession.EnsureHumanoidRunningState(humanoid)
end

function RunwaySession.EnsureHumanoidFreefallState(humanoid: Humanoid)
	-- 终局跳空中（含冲刺）：强制 Freefall，避免 FloorMaterial/Running 判贴地后仍播 run
	if not RunwaySession.IsRunwayFinalAirbornePhase() and RunwaySession.IsRunwayScriptedGrounded(humanoid) then
		return
	end
	local st = humanoid:GetState()
	if st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.Jumping then
		return
	end
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end)
end

function RunwaySession.EnsureHumanoidFinalSlidePhysicsState(humanoid: Humanoid)
	if not RunwaySession.IsRunwayFinalLandingSlidePhase() then
		return
	end
	if Refs.chestRewardWaitPose == true then
		RunwaySession.RestorePlatformStandAfterFinalLand(humanoid)
		if humanoid.PlatformStand then
			humanoid.PlatformStand = false
		end
		local stWait = humanoid:GetState()
		if stWait == Enum.HumanoidStateType.Physics or stWait == Enum.HumanoidStateType.Running then
			pcall(function()
				humanoid:ChangeState(Enum.HumanoidStateType.Landed)
			end)
		end
		return
	end
	local st = humanoid:GetState()
	if st == Enum.HumanoidStateType.Physics then
		return
	end
	if
		st == Enum.HumanoidStateType.Running
		or st == Enum.HumanoidStateType.RunningNoPhysics
		or st == Enum.HumanoidStateType.Landed
		or st == Enum.HumanoidStateType.Freefall
	then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	end
end

function RunwaySession.GetRunwayTargetGroundAlongSpeed(humanoid: Humanoid, nowClock: number): number
	if localState.takeoffCount == 0 then
		if localState.phase == Ph.JumpWindow and RunwaySession.WindowDriftPhysicsActive(humanoid, nowClock) then
			return cfg.JUMP_WINDOW_WALK_SPEED
		end
		return cfg.FIRST_TAKEOFF_AUTORUN_SPEED
	end
	if
		(localState.phase == Ph.JumpWindow or RunwaySession.ChainHudActive(nowClock))
		and RunwaySession.WindowDriftPhysicsActive(humanoid, nowClock)
	then
		return cfg.JUMP_WINDOW_WALK_SPEED
	end
	local seg = math.max(1, localState.takeoffCount)
	if localState.phase == Ph.Airborne and localState.jumpHorizLerpStartClock ~= nil then
		return RunwaySession.GetJumpHorizontalForwardSpeed(nowClock, seg)
	end
	local _, minSpd = GameConfig.GetJumpRunwayJumpSpeedLimitsForSegment(seg, localState.jumpSpeedCumulativeRatingBonus, GetJumpPowerBaseSpeed())
	return minSpd
end

function RunwaySession.MaybeCorrectGroundedAlongVelocity(hrp: BasePart, forward: Vector3, humanoid: Humanoid, nowClock: number)
	local targetAlong = RunwaySession.GetRunwayTargetGroundAlongSpeed(humanoid, nowClock)
	local v = hrp.AssemblyLinearVelocity
	local along = ComputeRunwayHorizontalAlongSpeed(v, forward)
	if math.abs(along - targetAlong) <= RUNWAY_GROUNDED_ALONG_CORRECT_THRESHOLD then
		return
	end
	local fwdH = Vector3.new(forward.X, 0, forward.Z)
	if fwdH.Magnitude < 1e-4 then
		return
	end
	fwdH = fwdH.Unit
	local horiz = HorizontalVelocity(v)
	local perpH = horiz - fwdH * along
	hrp.AssemblyLinearVelocity = fwdH * targetAlong + Vector3.new(0, v.Y, 0) + perpH
end

function RunwaySession.ApplyRunwayLocomotionAnimation(humanoid: Humanoid, forward: Vector3, nowClock: number, hrp: BasePart?)
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		humanoid:Move(Vector3.zero, false)
		return
	end
	local mode = RunwaySession.ResolveRunwayLocomotionMode(humanoid, nowClock)
	if mode == RUNWAY_LOCOMOTION_NONE then
		if Refs.chestRewardWaitPose ~= true then
			RunwaySession.EnsureHumanoidFinalSlidePhysicsState(humanoid)
		end
		humanoid:Move(Vector3.zero, false)
		return
	end
	if mode == RUNWAY_LOCOMOTION_FREEFALL then
		RunwaySession.EnsureHumanoidFreefallState(humanoid)
		humanoid:Move(Vector3.zero, false)
		return
	end
	if mode == RUNWAY_LOCOMOTION_WALK then
		RunwaySession.EnsureHumanoidWalkingState(humanoid)
		humanoid:Move(forward, false)
		return
	end
	if mode == RUNWAY_LOCOMOTION_RUN then
		RunwaySession.EnsureHumanoidRunningState(humanoid)
		humanoid:Move(forward, false)
		if hrp ~= nil then
			RunwaySession.MaybeCorrectGroundedAlongVelocity(hrp, forward, humanoid, nowClock)
		end
		return
	end
	humanoid:Move(Vector3.zero, false)
end

-- 终局跳水平冲刺在 UpdateAutoRunVelocity 内与基底合并；此处仅处理冲刺向上加速度
function RunwaySession.UpdateDashVerticalOnly(hrp: BasePart, dt: number)
	if not localState.dashHeld or localState.fuel <= 0 then
		return
	end
	local v = hrp.AssemblyLinearVelocity
	local newVy = v.Y
	local upAccel = cfg.DASH_UPWARD_ACCEL
	if upAccel > 0 and v.Y < cfg.DASH_UPWARD_VY_MAX then
		newVy = math.min(v.Y + upAccel * dt, cfg.DASH_UPWARD_VY_MAX)
	end
	if newVy ~= v.Y then
		hrp.AssemblyLinearVelocity = Vector3.new(v.X, newVy, v.Z)
	end
end

function RunwaySession.CollectParticleEmittersUnderFlame(flame: BasePart): { ParticleEmitter }
	local list: { ParticleEmitter } = {}
	for _, d in flame:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			local p = d.Parent
			local nestedUnderEmitter = false
			while p ~= nil and p ~= flame do
				if p:IsA("ParticleEmitter") then
					nestedUnderEmitter = true
					break
				end
				p = p.Parent
			end
			if not nestedUnderEmitter then
				table.insert(list, d :: ParticleEmitter)
			end
		end
	end
	return list
end

function RunwaySession.AppendParticleEmittersUnique(target: { ParticleEmitter }, extra: { ParticleEmitter })
	local seen: { [ParticleEmitter]: boolean } = {}
	for _, pe in target do
		seen[pe] = true
	end
	for _, pe in extra do
		if not seen[pe] then
			seen[pe] = true
			table.insert(target, pe)
		end
	end
end

function RunwaySession.SetJetpackDashParticlesEnabled(enabled: boolean)
	for _, pe in Refs.jetpackDashParticleEmitters do
		if pe.Parent ~= nil then
			pe.Enabled = enabled
			if not enabled and cfg.RUNWAY_JETPACK_DASH_PARTICLE_CLEAR_ON_IDLE then
				pe:Clear()
			end
		end
	end
end

function RunwaySession.RestoreJetpackFlameIdleColors()
	local c1 = Refs.jetpackFlame1IdleColor
	if Refs.jetpackFlame1Part ~= nil and Refs.jetpackFlame1Part.Parent ~= nil and c1 ~= nil then
		Refs.jetpackFlame1Part.Color = c1
	end
	local c2 = Refs.jetpackFlame2IdleColor
	if Refs.jetpackFlame2Part ~= nil and Refs.jetpackFlame2Part.Parent ~= nil and c2 ~= nil then
		Refs.jetpackFlame2Part.Color = c2
	end
end

function RunwaySession.UpdateJetpackFlameDashFx(nowClock: number)
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		RunwaySession.SetJetpackDashParticlesEnabled(false)
		RunwaySession.RestoreJetpackFlameIdleColors()
		return
	end
	local f1 = Refs.jetpackFlame1Part
	local f2 = Refs.jetpackFlame2Part
	if f1 == nil or f2 == nil or f1.Parent == nil or f2.Parent == nil then
		RunwaySession.SetJetpackDashParticlesEnabled(false)
		RunwaySession.RestoreJetpackFlameIdleColors()
		return
	end
	local dashFxActive = localState.phase == Ph.Airborne
		and localState.takeoffCount >= cfg.N_TOTAL_JUMPS
		and localState.dashHeld
		and localState.fuel > 0
	if not dashFxActive then
		RunwaySession.SetJetpackDashParticlesEnabled(false)
		RunwaySession.RestoreJetpackFlameIdleColors()
		return
	end
	RunwaySession.SetJetpackDashParticlesEnabled(true)
	local interval = cfg.RUNWAY_JETPACK_FLAME_COLOR_INTERVAL_SEC
	if interval <= 0 then
		return
	end
	local useRed = math.floor(nowClock / interval) % 2 == 0
	local c = if useRed then cfg.RUNWAY_JETPACK_FLAME_COLOR_RED else cfg.RUNWAY_JETPACK_FLAME_COLOR_YELLOW
	f1.Color = c
	f2.Color = c
end

function RunwaySession.RaycastFeet(humanoid: Humanoid): (boolean, number)
	local root = humanoid.RootPart
	if root == nil then
		return false, 1e9
	end
	local hip = humanoid.HipHeight
	if typeof(hip) ~= "number" or hip ~= hip or hip < 0.01 then
		hip = 2
	end
	local origin = root.Position + Vector3.new(0, cfg.RUNWAY_GROUND_RAY_ORIGIN_Y - hip, 0)
	local cast = Vector3.new(0, -cfg.RUNWAY_GROUND_PROBE_DOWN, 0)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local char = humanoid.Parent
	if char ~= nil and char:IsA("Model") then
		rp.FilterDescendantsInstances = { char }
	end
	local hit = workspace:Raycast(origin, cast, rp)
	if hit == nil then
		return false, 1e9
	end
	if hit.Normal.Y < cfg.RUNWAY_GROUND_MIN_NORMAL_Y then
		return false, 1e9
	end
	return true, hit.Distance
end

function RunwaySession.IsRunwayPreLanding(humanoid: Humanoid): boolean
	local root = humanoid.RootPart
	if root == nil then
		return false
	end
	local ok, dist = RunwaySession.RaycastFeet(humanoid)
	if not ok then
		return false
	end
	local maxPreLandDist = cfg.RUNWAY_PRELAND_MAX_DIST_STUDS
	local baseline = localState.preLandRayBaselineStuds
	if typeof(baseline) == "number" and baseline == baseline then
		maxPreLandDist = baseline + cfg.RUNWAY_PRELAND_MAX_DIST_STUDS
	end
	if dist > maxPreLandDist then
		return false
	end
	if root.AssemblyLinearVelocity.Y > cfg.RUNWAY_PRELAND_MAX_VY then
		return false
	end
	return true
end

-- 起跳窗/链式武装：仅 dist 与 baseline+RUNWAY_PRELAND_MAX_DIST_STUDS，不含 vy（与 IsRunwayPreLanding 区分）
function RunwaySession.IsRunwayJumpWindowRayBandOk(humanoid: Humanoid): boolean
	local ok, dist = RunwaySession.RaycastFeet(humanoid)
	if not ok then
		return false
	end
	local maxBand = cfg.RUNWAY_PRELAND_MAX_DIST_STUDS
	local baseline = localState.preLandRayBaselineStuds
	if typeof(baseline) == "number" and baseline == baseline then
		maxBand = baseline + cfg.RUNWAY_PRELAND_MAX_DIST_STUDS
	end
	return dist <= maxBand
end

-- 链式起跳窗口倒计时启动高度检测：dist <= baseline + RUNWAY_CHAIN_WINDOW_START_HEIGHT_STUDS
function RunwaySession.IsRunwayChainWindowHeightOk(humanoid: Humanoid): boolean
	local ok, dist = RunwaySession.RaycastFeet(humanoid)
	if not ok then
		return false
	end
	local maxH = cfg.RUNWAY_CHAIN_WINDOW_START_HEIGHT_STUDS
	local baseline = localState.preLandRayBaselineStuds
	if typeof(baseline) == "number" and baseline == baseline then
		maxH = baseline + cfg.RUNWAY_CHAIN_WINDOW_START_HEIGHT_STUDS
	end
	return dist <= maxH
end

-- IsRunwayScriptedGrounded 射线分支：有 baseline 时 dist < baseline + slack；无 baseline 时 ok 即真
function RunwaySession.IsRunwayFeetRayWithinGroundedAboveBaseline(humanoid: Humanoid): boolean
	local ok, dist = RunwaySession.RaycastFeet(humanoid)
	if not ok then
		return false
	end
	local b = localState.preLandRayBaselineStuds
	local slack = cfg.RUNWAY_SCRIPTED_GROUNDED_MAX_DIST_ABOVE_BASELINE_STUDS
	if typeof(b) == "number" and b == b and typeof(slack) == "number" and slack == slack and slack >= 0 then
		return dist < b + slack
	end
	return true
end

function RunwaySession.RaycastRunwayGroundFromHrpLocalOffset(hrp: BasePart, humanoid: Humanoid, localOffset: Vector3): (boolean, number)
	local worldPos = hrp.CFrame:PointToWorldSpace(localOffset)
	local origin = worldPos + Vector3.new(0, cfg.RUNWAY_GROUND_RAY_ORIGIN_Y, 0)
	local cast = Vector3.new(0, -cfg.RUNWAY_GROUND_PROBE_DOWN, 0)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local char = humanoid.Parent
	if char ~= nil and char:IsA("Model") then
		rp.FilterDescendantsInstances = { char }
	end
	local hit = workspace:Raycast(origin, cast, rp)
	if hit == nil then
		return false, 1e9
	end
	if hit.Normal.Y < cfg.RUNWAY_GROUND_MIN_NORMAL_Y then
		return false, 1e9
	end
	return true, hit.Distance
end

function RunwaySession.IsRunwayFinalLandFullBodyGrounded(humanoid: Humanoid, hrp: BasePart): boolean
	local hip = humanoid.HipHeight
	if typeof(hip) ~= "number" or hip ~= hip or hip < 0.15 then
		hip = 2
	end
	local d = math.clamp(hip * 0.55, 0.85, 1.75)
	local localOffsets = {
		Vector3.new(0.4, -d, 0),
		Vector3.new(-0.4, -d, 0),
		Vector3.new(0, -d * 0.88, 0.32),
		Vector3.new(0, -d * 0.88, -0.32),
		Vector3.new(0, -d * 0.35, 0),
	}
	local maxDist = cfg.RUNWAY_FINAL_LAND_FULL_BODY_GROUND_MAX_DIST_STUDS
	for _, lo in localOffsets do
		local ok, dist = RunwaySession.RaycastRunwayGroundFromHrpLocalOffset(hrp, humanoid, lo)
		if not ok or dist > maxDist then
			return false
		end
	end
	return true
end

-- 终局 A→B：仅用射线几何，不用 IsRunwayScriptedGrounded（终局 Slide 强转 Physics 时后者易全程为 true）
function RunwaySession.IsRunwayFinalLandPhaseAFeetRayTouchdown(humanoid: Humanoid): boolean
	local ok, dist = RunwaySession.RaycastFeet(humanoid)
	if not ok then
		return false
	end
	local slackRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_TOUCHDOWN_FEET_MAX_ABOVE_BASELINE_STUDS
	local slack = (typeof(slackRaw) == "number" and slackRaw == slackRaw and slackRaw > 0) and slackRaw or 2
	local b = localState.preLandRayBaselineStuds
	if typeof(b) == "number" and b == b then
		return dist <= b + slack
	end
	local fbRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_TOUCHDOWN_FEET_FALLBACK_MAX_DIST_STUDS
	local fbMax = (typeof(fbRaw) == "number" and fbRaw == fbRaw and fbRaw > 0.25) and fbRaw or 4
	return dist <= fbMax
end

function RunwaySession.IsRunwayFinalLandPhaseAGeometricTouchdown(humanoid: Humanoid, hrp: BasePart): boolean
	return RunwaySession.IsRunwayFinalLandFullBodyGrounded(humanoid, hrp)
		or RunwaySession.IsRunwayFinalLandPhaseAFeetRayTouchdown(humanoid)
end

function RunwaySession.IsRunwayScriptedGrounded(humanoid: Humanoid): boolean
	-- 任意起跳后短保护期内强制视为离地，避免 FloorMaterial/射线仍判贴地触发 run 与链式误武装。
	if localState.phase == Ph.Airborne and os.clock() < localState.jumpBoostUntilClock then
		return false
	end
	if
		localState.phase == Ph.Airborne
		and localState.takeoffCount >= cfg.N_TOTAL_JUMPS
		and os.clock() < Refs.finalTakeoffForceFreefallUntilClock
	then
		return false
	end
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		return true
	end
	local st = humanoid:GetState()
	if st == Enum.HumanoidStateType.Flying then
		local allowRaycastFlying = RunwaySession.IsRunwayActivePhase(localState.phase)
			and localState.phase == Ph.Airborne
			and localState.takeoffCount >= cfg.N_TOTAL_JUMPS
		if not allowRaycastFlying then
			return false
		end
	elseif st == Enum.HumanoidStateType.Seated then
		return false
	end
	if RunwaySession.IsRunwayFeetRayWithinGroundedAboveBaseline(humanoid) then
		return true
	end
	local root = humanoid.RootPart
	if root == nil then
		return false
	end
	local vy = math.abs(root.AssemblyLinearVelocity.Y)
	if vy >= 12 then
		return false
	end
	local y0 = localState.scriptedGroundHrpYBaseline
	local dev = cfg.RUNWAY_SCRIPTED_GROUNDED_HRP_Y_DEVIATION_STUDS
	if
		y0 ~= nil
		and typeof(y0) == "number"
		and y0 == y0
		and typeof(dev) == "number"
		and dev == dev
		and dev > 0
		and math.abs(root.Position.Y - y0) <= dev
	then
		return true
	end
	if
		st == Enum.HumanoidStateType.Running
		or st == Enum.HumanoidStateType.Landed
		or st == Enum.HumanoidStateType.GettingUp
		or (st == Enum.HumanoidStateType.Physics and localState.phase == Ph.Slide)
	then
		return true
	end
	return false
end

function RunwaySession.GetJumpRunwayLocalFxFolder(): Folder
	local existing = workspace:FindFirstChild("JumpRunwayLocalFx")
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "JumpRunwayLocalFx"
	folder.Parent = workspace
	return folder
end

function RunwaySession.SlideTraceGetSegmentsFolder(): Folder
	local fx = RunwaySession.GetJumpRunwayLocalFxFolder()
	local existing = fx:FindFirstChild("SlideTraceSegments")
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "SlideTraceSegments"
	folder.Parent = fx
	return folder
end

function RunwaySession.SlideTraceDestroyImpl()
	if Refs.slideTraceFollowerPart ~= nil then
		Refs.slideTraceFollowerPart:Destroy()
		Refs.slideTraceFollowerPart = nil
	end
	for i = #Refs.slideTraceSegmentList, 1, -1 do
		local segMaybe = Refs.slideTraceSegmentList[i]
		if segMaybe ~= nil then
			local seg = segMaybe :: BasePart
			if seg.Parent ~= nil then
				seg:Destroy()
			end
		end
		Refs.slideTraceSegmentList[i] = nil
	end
	table.clear(Refs.slideTraceSegmentList)
	Refs.slideTraceAccumAlong = 0
	Refs.slideTracePrevAlongForDelta = nil
end

function RunwaySession.FireSlideTraceScheduledDestroyIfCurrent(scheduledAt: number)
	if scheduledAt ~= Refs.slideTraceDestroyScheduleToken then
		return
	end
	Refs.slideTraceDestroyScheduleToken += 1
	RunwaySession.SlideTraceDestroyImpl()
end

function RunwaySession.SlideTraceDestroy()
	Refs.slideTraceDestroyScheduleToken += 1
	RunwaySession.SlideTraceDestroyImpl()
end

function RunwaySession.SlideTraceScheduleDestroyAfterRunwayEnd()
	Refs.slideTraceDestroyScheduleToken += 1
	local scheduledAt = Refs.slideTraceDestroyScheduleToken
	task.delay(RunwaySlideTraceDestroyAfterEndSec, function()
		RunwaySession.FireSlideTraceScheduledDestroyIfCurrent(scheduledAt)
	end)
end

function RunwaySession.SlideTraceGetTemplate(): BasePart?
	local cached = Refs.slideTraceCachedTemplate
	if cached ~= nil and cached.Parent ~= nil then
		return cached
	end
	Refs.slideTraceCachedTemplate = nil
	local modelsFolder = replicatedStorage:FindFirstChild("Models")
	if modelsFolder == nil then
		if not Refs.slideTraceTemplateWarned then
			Refs.slideTraceTemplateWarned = true
			warn(
				"[RunwaySession] ReplicatedStorage.Models missing; SlideTracePart skipped. Add Models.SlideTracePart in Studio."
			)
		end
		return nil
	end
	local template = modelsFolder:FindFirstChild(RunwaySlideTraceTemplateName)
	if template == nil or not template:IsA("BasePart") then
		if not Refs.slideTraceTemplateWarned then
			Refs.slideTraceTemplateWarned = true
			warn(
				"[RunwaySession] ReplicatedStorage.Models.SlideTracePart missing or not a BasePart; add template in Studio."
			)
		end
		return nil
	end
	Refs.slideTraceCachedTemplate = template :: BasePart
	return Refs.slideTraceCachedTemplate
end

function RunwaySession.SlideTraceRaycastGroundHit(hrp: BasePart, humanoid: Humanoid): RaycastResult?
	local origin = hrp.Position + Vector3.new(0, cfg.RUNWAY_GROUND_RAY_ORIGIN_Y, 0)
	local cast = Vector3.new(0, -cfg.RUNWAY_GROUND_PROBE_DOWN, 0)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local char = humanoid.Parent
	if char ~= nil and char:IsA("Model") then
		rp.FilterDescendantsInstances = { char }
	end
	local hit = workspace:Raycast(origin, cast, rp)
	if hit == nil or hit.Normal.Y < cfg.RUNWAY_GROUND_MIN_NORMAL_Y then
		return nil
	end
	return hit
end

function RunwaySession.SlideTraceComputeWorldCFrame(hrp: BasePart, humanoid: Humanoid, runwayForward: Vector3): CFrame?
	local hit = RunwaySession.SlideTraceRaycastGroundHit(hrp, humanoid)
	if hit == nil then
		return nil
	end
	local n = hit.Normal
	local fwdH = NormalizeRunwayForward(runwayForward)
	local xAxis = fwdH - n * fwdH:Dot(n)
	if xAxis.Magnitude < 1e-4 then
		xAxis = Vector3.new(1, 0, 0) - n * n.X
	end
	if xAxis.Magnitude < 1e-4 then
		xAxis = Vector3.new(1, 0, 0)
	end
	xAxis = xAxis.Unit
	local liftRaw = cfg.RUNWAY_SLIDE_TRACE_GROUND_NORMAL_LIFT_STUDS
	local lift = (typeof(liftRaw) == "number" and liftRaw == liftRaw) and liftRaw or 0.035
	local center = hit.Position + n * lift
	local alongOffRaw = cfg.RUNWAY_SLIDE_TRACE_HRP_ALONG_OFFSET_STUDS
	local alongOff = (typeof(alongOffRaw) == "number" and alongOffRaw == alongOffRaw) and alongOffRaw or 0
	center += xAxis * alongOff
	return CFrame.fromMatrix(center, xAxis, n)
end

function RunwaySession.SlideTraceEnsureFollowerFromTemplate(): boolean
	if Refs.slideTraceFollowerPart ~= nil and Refs.slideTraceFollowerPart.Parent ~= nil then
		return true
	end
	Refs.slideTraceFollowerPart = nil
	local tmpl = RunwaySession.SlideTraceGetTemplate()
	if tmpl == nil then
		return false
	end
	local p = tmpl:Clone()
	p.Name = "JumpRunwaySlideTraceFollower"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Parent = RunwaySession.GetJumpRunwayLocalFxFolder()
	Refs.slideTraceFollowerPart = p
	Refs.slideTracePrevAlongForDelta = nil
	return true
end

function RunwaySession.SlideTraceStampSegmentsIfDue()
	local follower = Refs.slideTraceFollowerPart
	if follower == nil then
		return
	end
	local tmpl = RunwaySession.SlideTraceGetTemplate()
	if tmpl == nil then
		return
	end
	local lenX = follower.Size.X
	if lenX < 1e-4 then
		return
	end
	local fracRaw = cfg.RUNWAY_SLIDE_TRACE_STAMP_AT_ALONG_FRAC
	local frac = (typeof(fracRaw) == "number" and fracRaw == fracRaw) and math.clamp(fracRaw, 0.05, 1) or 0.75
	local thresh = frac * lenX
	local maxSegRaw = cfg.RUNWAY_SLIDE_TRACE_MAX_SEGMENTS
	local maxSeg = (typeof(maxSegRaw) == "number" and maxSegRaw == maxSegRaw and maxSegRaw >= 2) and math.floor(maxSegRaw) or 64
	local folder = RunwaySession.SlideTraceGetSegmentsFolder()
	while Refs.slideTraceAccumAlong >= thresh do
		Refs.slideTraceAccumAlong -= thresh
		local seg = tmpl:Clone()
		seg.Name = "JumpRunwaySlideTraceSegment"
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CFrame = follower.CFrame
		seg.Parent = folder
		table.insert(Refs.slideTraceSegmentList, seg)
		while #Refs.slideTraceSegmentList > maxSeg do
			local old = table.remove(Refs.slideTraceSegmentList, 1)
			if old ~= nil and old.Parent ~= nil then
				old:Destroy()
			end
		end
	end
end

function RunwaySession.SlideTraceUpdate(humanoid: Humanoid, hrp: BasePart)
	if cfg.RUNWAY_SLIDE_TRACE_ENABLED ~= true then
		if Refs.slideTraceFollowerPart ~= nil or #Refs.slideTraceSegmentList > 0 then
			RunwaySession.SlideTraceDestroy()
		end
		return
	end
	local shouldTraces =
		localState.phase == Ph.Slide
		and (localState.runwaySlideKind == SlideKindFinalLanding or localState.runwaySlideKind == SlideKindMiss)
		and localState.finalLandSubPhase == 2
		and localState.finalLandProneBStage >= 1
	if not shouldTraces then
		if Refs.slideTraceFollowerPart ~= nil or #Refs.slideTraceSegmentList > 0 then
			RunwaySession.SlideTraceDestroy()
		end
		return
	end
	if not RunwaySession.SlideTraceEnsureFollowerFromTemplate() then
		return
	end
	local forward = NormalizeRunwayForward(localState.runwayForward)
	local cf = RunwaySession.SlideTraceComputeWorldCFrame(hrp, humanoid, forward)
	if cf == nil then
		return
	end
	local follower = Refs.slideTraceFollowerPart :: BasePart
	follower.CFrame = cf
	local alongNow = RunwaySession.CurrentAlongProgress(hrp)
	if Refs.slideTracePrevAlongForDelta == nil then
		Refs.slideTracePrevAlongForDelta = alongNow
		return
	end
	local prev = Refs.slideTracePrevAlongForDelta :: number
	local delta = alongNow - prev
	Refs.slideTracePrevAlongForDelta = alongNow
	if delta < -12 then
		Refs.slideTraceAccumAlong = 0
		return
	end
	if delta > 0 then
		Refs.slideTraceAccumAlong += delta
	end
	RunwaySession.SlideTraceStampSegmentsIfDue()
end

function RunwaySession.DestroyRunwayRing()
	if Refs.runwayRingPart ~= nil then
		Refs.runwayRingPart:Destroy()
		Refs.runwayRingPart = nil
	end
	Refs.ringLastGroundY = nil
end

function RunwaySession.SetupJumpRunwayRingSurfaceUi(ringPart: BasePart)
	for _, child in ringPart:GetChildren() do
		if child:IsA("SurfaceGui") then
			child:Destroy()
		end
	end

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "RingSurfaceGui"
	surfaceGui.Face = Enum.NormalId.Top
	surfaceGui.LightInfluence = 0
	surfaceGui.AlwaysOnTop = false
	surfaceGui.ResetOnSpawn = false
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = cfg.RUNWAY_RING_UI_PIXELS_PER_STUD
	surfaceGui.Parent = ringPart

	local rootFrame = Instance.new("Frame")
	rootFrame.Name = "RingUiRootFrame"
	rootFrame.Size = UDim2.fromScale(1, 1)
	rootFrame.BackgroundTransparency = 1
	rootFrame.BorderSizePixel = 0
	rootFrame.Parent = surfaceGui

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = rootFrame

	local trackFrame = Instance.new("Frame")
	trackFrame.Name = "RingTrackFrame"
	trackFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	trackFrame.Position = UDim2.fromScale(0.5, 0.5)
	trackFrame.Size = UDim2.fromScale(0.98, 0.98)
	trackFrame.BackgroundTransparency = 1
	trackFrame.BorderSizePixel = 0
	trackFrame.ZIndex = 1
	trackFrame.Parent = rootFrame

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0.5, 0)
	trackCorner.Parent = trackFrame

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Thickness = cfg.RUNWAY_RING_UI_TRACK_STROKE_PX
	trackStroke.Color = cfg.RUNWAY_RING_UI_TRACK_COLOR
	trackStroke.LineJoinMode = Enum.LineJoinMode.Round
	trackStroke.Parent = trackFrame

	local fixedFrame = Instance.new("Frame")
	fixedFrame.Name = "RingFixedFrame"
	fixedFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	fixedFrame.Position = UDim2.fromScale(0.5, 0.5)
	fixedFrame.Size = UDim2.fromOffset(cfg.RUNWAY_RING_UI_FIXED_DIAMETER_PX, cfg.RUNWAY_RING_UI_FIXED_DIAMETER_PX)
	fixedFrame.BackgroundTransparency = 1
	fixedFrame.BorderSizePixel = 0
	fixedFrame.ZIndex = 2
	fixedFrame.Parent = rootFrame

	local fixedCorner = Instance.new("UICorner")
	fixedCorner.CornerRadius = UDim.new(0.5, 0)
	fixedCorner.Parent = fixedFrame

	local fixedStroke = Instance.new("UIStroke")
	fixedStroke.Thickness = cfg.RUNWAY_RING_UI_FIXED_STROKE_PX
	fixedStroke.Color = cfg.RUNWAY_RING_UI_FIXED_COLOR
	fixedStroke.LineJoinMode = Enum.LineJoinMode.Round
	fixedStroke.Parent = fixedFrame
end

function RunwaySession.RaycastRingGroundY(humanoid: Humanoid): (boolean, number)
	local root = humanoid.RootPart
	if root == nil then
		return false, 0
	end
	local origin = root.Position + Vector3.new(0, cfg.RUNWAY_GROUND_RAY_ORIGIN_Y, 0)
	local cast = Vector3.new(0, -cfg.RUNWAY_RING_GROUND_RAY_MAX, 0)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local char = humanoid.Parent
	if char ~= nil and char:IsA("Model") then
		rp.FilterDescendantsInstances = { char }
	end
	local hit = workspace:Raycast(origin, cast, rp)
	if hit == nil then
		return false, 0
	end
	if hit.Normal.Y < cfg.RUNWAY_GROUND_MIN_NORMAL_Y then
		return false, 0
	end
	return true, hit.Position.Y
end

function RunwaySession.EnsureRunwayRing()
	RunwaySession.DestroyRunwayRing()
	if cfg.RUNWAY_RING_ENABLED ~= true then
		return
	end
	local modelsFolder = replicatedStorage:FindFirstChild("Models")
	if modelsFolder == nil then
		if not Refs.ringTemplateWarned then
			Refs.ringTemplateWarned = true
			warn("[RunwaySession] ReplicatedStorage.Models missing; runway ring skipped.")
		end
		return
	end
	local template = modelsFolder:FindFirstChild(RunwayRingTemplateName)
	if template == nil or not template:IsA("BasePart") then
		if not Refs.ringTemplateWarned then
			Refs.ringTemplateWarned = true
			warn(
				string.format(
					"[RunwaySession] ReplicatedStorage.Models.%s missing or not a BasePart; runway ring skipped.",
					RunwayRingTemplateName
				)
			)
		end
		return
	end
	local clone = template:Clone() :: Part
	clone.Name = RunwayRingTemplateName
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanQuery = false
	clone.Parent = RunwaySession.GetJumpRunwayLocalFxFolder()
	Refs.ringBaseSizeX = clone.Size.X
	Refs.ringBaseSizeY = clone.Size.Y
	Refs.ringBaseSizeZ = clone.Size.Z
	if cfg.RUNWAY_RING_SCRIPTED_SURFACE_UI == true then
		RunwaySession.SetupJumpRunwayRingSurfaceUi(clone)
	end
	Refs.runwayRingPart = clone
end

function RunwaySession.UpdateRunwayRingTransform(humanoid: Humanoid, hrp: BasePart)
	local ring = Refs.runwayRingPart
	if ring == nil or ring.Parent == nil then
		return
	end
	local okGround, groundY = RunwaySession.RaycastRingGroundY(humanoid)
	if okGround then
		Refs.ringLastGroundY = groundY
	elseif Refs.ringLastGroundY ~= nil then
		groundY = Refs.ringLastGroundY :: number
	else
		groundY = hrp.Position.Y - humanoid.HipHeight
	end
	local sizeMul: number
	if localState.phase == Ph.AutoRun and not localState.passedBeginLineOnce then
		-- AutoRun 且未过 BeginLine：根据距 BeginLine 的沿轴距离缩放
		local _, beginLine = RunwaySession.ResolveSceneParts()
		if beginLine ~= nil and beginLine:IsA("BasePart") and localState.runwayOrigin ~= nil then
			local fwd = NormalizeRunwayForward(localState.runwayForward)
			local beginAlong = (beginLine.Position - localState.runwayOrigin):Dot(fwd)
			local currentAlong = (hrp.Position - localState.runwayOrigin):Dot(fwd)
			local distToBegin = beginAlong - currentAlong
			local maxDist = beginAlong - localState.alongBaseline
			if distToBegin > 0 and maxDist > 1e-4 then
				local beginMaxMul = cfg.RUNWAY_RING_BEGINLINE_MAX_MULTIPLIER
				local t = math.clamp(distToBegin / maxDist, 0, 1)
				sizeMul = 1 + (beginMaxMul - 1) * t
			else
				sizeMul = 1
			end
		else
			sizeMul = 1
		end
	elseif RunwaySession.IsRunwayScriptedGrounded(humanoid) then
		sizeMul = 1
	else
		local altStuds = math.max(0, hrp.Position.Y - groundY - humanoid.HipHeight)
		sizeMul = 1 + cfg.RUNWAY_RING_SIZE_PER_STUD_ALT * altStuds
	end
	ring.Size = Vector3.new(Refs.ringBaseSizeX * sizeMul, Refs.ringBaseSizeY, Refs.ringBaseSizeZ * sizeMul)
	local yCenter = groundY + cfg.RUNWAY_RING_WORLD_Y_OFFSET
	local fwd = NormalizeRunwayForward(localState.runwayForward)
	local flatFwd = Vector3.new(fwd.X, 0, fwd.Z)
	if flatFwd.Magnitude < 1e-4 then
		flatFwd = Vector3.new(0, 0, -1)
	else
		flatFwd = flatFwd.Unit
	end
	local center = Vector3.new(hrp.Position.X, yCenter, hrp.Position.Z)
	ring.CFrame = CFrame.lookAt(center, center + flatFwd)
end

function RunwaySession.DestroyDistanceRecorder()
	local lbl = Refs.runwayDistanceRecorderText
	if lbl ~= nil then
		TranslationTool.RemoveCustomAutoLocalizeGui(lbl)
		Refs.runwayDistanceRecorderText = nil
	end
	if Refs.runwayDistanceRecorderPart ~= nil then
		Refs.runwayDistanceRecorderPart:Destroy()
		Refs.runwayDistanceRecorderPart = nil
	end
	Refs.distanceRecorderLastGroundY = nil
end

function RunwaySession.DestroyJumpRunwayRocketBackpack()
	if Refs.jetpackVisualRoot ~= nil then
		Refs.jetpackVisualRoot:Destroy()
		Refs.jetpackVisualRoot = nil
	end
	table.clear(Refs.jetpackDashParticleEmitters)
	Refs.jetpackFlame1Part = nil
	Refs.jetpackFlame2Part = nil
	Refs.jetpackFlame1IdleColor = nil
	Refs.jetpackFlame2IdleColor = nil
	if Refs.rocketBackpackPart ~= nil then
		Refs.rocketBackpackPart:Destroy()
		Refs.rocketBackpackPart = nil
	end
end

function RunwaySession.RestoreHumanoidAutoRotateAfterFinalPitch(humanoid: Humanoid?)
	if Refs.autoRotateSavedForFinalPitch == nil then
		return
	end
	if humanoid ~= nil and humanoid.Parent ~= nil then
		humanoid.AutoRotate = Refs.autoRotateSavedForFinalPitch :: boolean
	end
	Refs.autoRotateSavedForFinalPitch = nil
end

function RunwaySession.EnsureHumanoidAutoRotateOffForFinalPitch(humanoid: Humanoid)
	if Refs.autoRotateSavedForFinalPitch == nil then
		Refs.autoRotateSavedForFinalPitch = humanoid.AutoRotate
	end
	humanoid.AutoRotate = false
end

function RunwaySession.ApplyRunwayFinalBodyPitch(hrp: BasePart, forward: Vector3, dt: number)
	local f = NormalizeRunwayForward(forward)
	if f.Magnitude < 1e-4 then
		return
	end
	local extraDegTarget = 0
	if localState.dashHeld and localState.fuel > 0 then
		extraDegTarget = cfg.RUNWAY_FINAL_DASH_EXTRA_PITCH_DEG
	end
	local pitchRate = cfg.RUNWAY_FINAL_PITCH_SMOOTH_RATE
	local pitchAlpha: number
	if pitchRate <= 0 then
		pitchAlpha = 1
	else
		pitchAlpha = 1 - math.exp(-pitchRate * dt)
	end
	Refs.finalPitchSmoothedExtraDeg += (extraDegTarget - Refs.finalPitchSmoothedExtraDeg) * pitchAlpha
	local totalDeg = cfg.RUNWAY_FINAL_PITCH_DEG + Refs.finalPitchSmoothedExtraDeg
	local axisSign = cfg.RUNWAY_FINAL_PITCH_AXIS_SIGN
	if math.abs(axisSign) < 1e-6 then
		axisSign = 1
	end
	local pos = hrp.Position
	local linVel = hrp.AssemblyLinearVelocity
	local yawFlat = CFrame.lookAt(pos, pos + f, Vector3.yAxis)
	local pitchRad = math.rad(totalDeg) * axisSign
	local targetCf = yawFlat * CFrame.Angles(pitchRad, 0, 0)
	local rate = cfg.RUNWAY_FINAL_PITCH_SMOOTH_RATE
	local alpha: number
	if rate <= 0 then
		alpha = 1
	else
		alpha = 1 - math.exp(-rate * dt)
	end
	-- 对旋转做球面插值，位置固定为 hrp 当前位置
	local blendedRot = hrp.CFrame.Rotation:Lerp(targetCf.Rotation, alpha)
	hrp.CFrame = CFrame.fromMatrix(pos, blendedRot.XVector, blendedRot.YVector, blendedRot.ZVector)
	hrp.AssemblyLinearVelocity = linVel
	local dampRate = cfg.RUNWAY_FINAL_PITCH_ANGULAR_DAMP_RATE
	if dampRate > 1e-6 then
		local k = math.exp(-dampRate * dt)
		hrp.AssemblyAngularVelocity = hrp.AssemblyAngularVelocity * k
	else
		hrp.AssemblyAngularVelocity = Vector3.zero
	end
end

function RunwaySession.ConfigureRunwayJetpackBaseParts(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local bp = d :: BasePart
			bp.Anchored = false
			bp.CanCollide = false
			bp.CanQuery = false
			bp.Massless = true
		end
	end
end

function RunwaySession.JetpackPartsShareWeldConstraint(a: BasePart, b: BasePart): boolean
	for _, ch in a:GetChildren() do
		if ch:IsA("WeldConstraint") then
			local w = ch :: WeldConstraint
			if w.Part0 == b or w.Part1 == b then
				return true
			end
		end
	end
	for _, ch in b:GetChildren() do
		if ch:IsA("WeldConstraint") then
			local w = ch :: WeldConstraint
			if w.Part0 == a or w.Part1 == a then
				return true
			end
		end
	end
	return false
end

-- 取消锚点后，未与 Middle 同装配的 Part 会散落/掉落；在移动 Middle 之前焊上，保留模板相对位姿。
function RunwaySession.WeldAllRunwayJetpackPartsToMiddle(jetpackRoot: Model, middle: BasePart)
	for _, d in jetpackRoot:GetDescendants() do
		if d:IsA("BasePart") then
			local bp = d :: BasePart
			if bp ~= middle and not RunwaySession.JetpackPartsShareWeldConstraint(bp, middle) then
				local w = Instance.new("WeldConstraint")
				w.Part0 = middle
				w.Part1 = bp
				w.Parent = bp
			end
		end
	end
end

function RunwaySession.EnsureJumpRunwayRocketBackpack(character: Model)
	if Refs.jetpackVisualRoot ~= nil and Refs.jetpackVisualRoot.Parent ~= nil then
		return
	end
	if Refs.rocketBackpackPart ~= nil and Refs.rocketBackpackPart.Parent ~= nil then
		return
	end
	Refs.jetpackVisualRoot = nil
	Refs.jetpackFlame1Part = nil
	Refs.jetpackFlame2Part = nil
	Refs.jetpackFlame1IdleColor = nil
	Refs.jetpackFlame2IdleColor = nil
	table.clear(Refs.jetpackDashParticleEmitters)
	Refs.rocketBackpackPart = nil
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp == nil then
		return
	end
	local torso = character:FindFirstChild("UpperTorso") :: BasePart?
	if torso == nil then
		torso = character:FindFirstChild("Torso") :: BasePart?
	end
	local attachPart = torso or hrp

	local function CreateFallbackRocketBackpackPart()
		local p = Instance.new("Part")
		p.Name = "JumpRunwayRocketBackpack"
		p.Size = cfg.RUNWAY_ROCKET_BACKPACK_SIZE
		p.Color = cfg.RUNWAY_ROCKET_BACKPACK_COLOR
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.Massless = true
		p.Parent = character
		if torso ~= nil then
			p.CFrame = torso.CFrame
				* CFrame.new(
					cfg.RUNWAY_ROCKET_BACKPACK_OFFSET_X,
					cfg.RUNWAY_ROCKET_BACKPACK_OFFSET_Y,
					cfg.RUNWAY_ROCKET_BACKPACK_OFFSET_Z
				)
		else
			if not Refs.rocketBackpackFallbackWarned then
				Refs.rocketBackpackFallbackWarned = true
				warn("[RunwaySession] No UpperTorso/Torso; rocket backpack welded to HumanoidRootPart.")
			end
			p.CFrame = hrp.CFrame
				* CFrame.new(
					cfg.RUNWAY_ROCKET_BACKPACK_HRP_FALLBACK_OFFSET_X,
					cfg.RUNWAY_ROCKET_BACKPACK_HRP_FALLBACK_OFFSET_Y,
					cfg.RUNWAY_ROCKET_BACKPACK_HRP_FALLBACK_OFFSET_Z
				)
		end
		local w = Instance.new("WeldConstraint")
		w.Part0 = attachPart
		w.Part1 = p
		w.Parent = p
		Refs.rocketBackpackPart = p
	end

	local useJetpackTemplate = cfg.RUNWAY_JETPACK_ENABLED == true
	if useJetpackTemplate then
		local modelsFolder = replicatedStorage:FindFirstChild("Models")
		local jetpackFolder = if modelsFolder then modelsFolder:FindFirstChild("Jetpack") :: Folder? else nil
		local outerTemplate: Model? = nil
		local innerTemplate: Instance? = nil
		local middleTemplate: Instance? = nil

		-- 尝试加载玩家当前装备的火箭背包模型
		local function TryLoadEquippedJetpack(): boolean
			local info = ClientGameInfo.GetLocalPlayerInfo()
			if info == nil then
				return false
			end
			local currentId = tonumber(info.jetpackInventory.currentId) or 1
			local jetpackData = GameConfig.JetpackDataMap[currentId]
			if jetpackData == nil then
				return false
			end
			if jetpackFolder == nil then
				return false
			end
			-- 用 resourceName 查找对应的子模型
			outerTemplate = jetpackFolder:FindFirstChild(jetpackData.resourceName) :: Model?
			if outerTemplate == nil or not outerTemplate:IsA("Model") then
				outerTemplate = nil
				return false
			end
			innerTemplate = outerTemplate:FindFirstChild(cfg.RUNWAY_JETPACK_INNER_MODEL_NAME)
			middleTemplate = if innerTemplate and innerTemplate:IsA("Model")
				then innerTemplate:FindFirstChild(cfg.RUNWAY_JETPACK_MIDDLE_NAME)
				else nil
			return outerTemplate ~= nil and innerTemplate ~= nil
				and innerTemplate:IsA("Model") and middleTemplate ~= nil
				and middleTemplate:IsA("BasePart")
		end

		-- 备用：加载默认的 Jetpack 模板
		local function TryLoadDefaultJetpack(): boolean
			outerTemplate = if modelsFolder
				then modelsFolder:FindFirstChild(cfg.RUNWAY_JETPACK_OUTER_MODEL_NAME) :: Model?
				else nil
			innerTemplate = if outerTemplate and outerTemplate:IsA("Model")
				then outerTemplate:FindFirstChild(cfg.RUNWAY_JETPACK_INNER_MODEL_NAME)
				else nil
			middleTemplate = if innerTemplate and innerTemplate:IsA("Model")
				then innerTemplate:FindFirstChild(cfg.RUNWAY_JETPACK_MIDDLE_NAME)
				else nil
			return outerTemplate ~= nil and outerTemplate:IsA("Model")
				and innerTemplate ~= nil and innerTemplate:IsA("Model")
				and middleTemplate ~= nil and middleTemplate:IsA("BasePart")
		end

		local templateReady = TryLoadEquippedJetpack() or TryLoadDefaultJetpack()

		if templateReady and outerTemplate ~= nil and innerTemplate ~= nil and middleTemplate ~= nil then
			local clone = outerTemplate:Clone() :: Model
			clone.Name = "JumpRunwayJetpackClone"
			clone.Parent = character
			RunwaySession.ConfigureRunwayJetpackBaseParts(clone)
			local inner = clone:FindFirstChild(cfg.RUNWAY_JETPACK_INNER_MODEL_NAME) :: Model?
			local middle = if inner then inner:FindFirstChild(cfg.RUNWAY_JETPACK_MIDDLE_NAME) :: BasePart? else nil
			if inner == nil or middle == nil then
				clone:Destroy()
				if not Refs.jetpackTemplateWarned then
					Refs.jetpackTemplateWarned = true
					warn("[RunwaySession] Jetpack clone missing inner model or Middle; using fallback Part.")
				end
				CreateFallbackRocketBackpackPart()
				return
			end
			local flame1 = inner:FindFirstChild(cfg.RUNWAY_JETPACK_FLAME1_NAME)
			local flame2 = inner:FindFirstChild(cfg.RUNWAY_JETPACK_FLAME2_NAME)
			RunwaySession.WeldAllRunwayJetpackPartsToMiddle(clone, middle)
			if torso ~= nil then
				middle.CFrame = torso.CFrame
					* CFrame.new(
						cfg.RUNWAY_ROCKET_BACKPACK_OFFSET_X,
						cfg.RUNWAY_ROCKET_BACKPACK_OFFSET_Y,
						cfg.RUNWAY_ROCKET_BACKPACK_OFFSET_Z
					)
			else
				if not Refs.rocketBackpackFallbackWarned then
					Refs.rocketBackpackFallbackWarned = true
					warn("[RunwaySession] No UpperTorso/Torso; jetpack Middle welded to HumanoidRootPart.")
				end
				middle.CFrame = hrp.CFrame
					* CFrame.new(
						cfg.RUNWAY_ROCKET_BACKPACK_HRP_FALLBACK_OFFSET_X,
						cfg.RUNWAY_ROCKET_BACKPACK_HRP_FALLBACK_OFFSET_Y,
						cfg.RUNWAY_ROCKET_BACKPACK_HRP_FALLBACK_OFFSET_Z
					)
			end
			local w = Instance.new("WeldConstraint")
			w.Part0 = attachPart
			w.Part1 = middle
			w.Parent = middle
			Refs.jetpackVisualRoot = clone
			table.clear(Refs.jetpackDashParticleEmitters)
			if flame1 ~= nil and flame1:IsA("BasePart") then
				local fp = flame1 :: BasePart
				Refs.jetpackFlame1Part = fp
				Refs.jetpackFlame1IdleColor = fp.Color
				RunwaySession.AppendParticleEmittersUnique(Refs.jetpackDashParticleEmitters, RunwaySession.CollectParticleEmittersUnderFlame(fp))
			end
			if flame2 ~= nil and flame2:IsA("BasePart") then
				local fp = flame2 :: BasePart
				Refs.jetpackFlame2Part = fp
				Refs.jetpackFlame2IdleColor = fp.Color
				RunwaySession.AppendParticleEmittersUnique(Refs.jetpackDashParticleEmitters, RunwaySession.CollectParticleEmittersUnderFlame(fp))
			end
			RunwaySession.SetJetpackDashParticlesEnabled(false)
			return
		end
		if not Refs.jetpackTemplateWarned then
			Refs.jetpackTemplateWarned = true
			warn(
				"[RunwaySession] Jetpack template missing (looked in Models.Jetpack.<resourceName> and Models.Jetpack); using fallback Part."
			)
		end
	end

	CreateFallbackRocketBackpackPart()
end

function RunwaySession.RaycastRunwayGroundYAtWorldXZ(
	worldXZ: Vector3,
	humanoid: Humanoid,
	probeOriginY: number,
	extraExclude: Instance?
): (boolean, number)
	local origin = Vector3.new(worldXZ.X, probeOriginY, worldXZ.Z)
	local cast = Vector3.new(0, -cfg.RUNWAY_RING_GROUND_RAY_MAX, 0)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local filterList: { Instance } = {}
	local char = humanoid.Parent
	if char ~= nil and char:IsA("Model") then
		table.insert(filterList, char)
	end
	if extraExclude ~= nil then
		table.insert(filterList, extraExclude)
	end
	if #filterList > 0 then
		rp.FilterDescendantsInstances = filterList
	end
	local hit = workspace:Raycast(origin, cast, rp)
	if hit == nil then
		return false, 0
	end
	if hit.Normal.Y < cfg.RUNWAY_GROUND_MIN_NORMAL_Y then
		return false, 0
	end
	return true, hit.Position.Y
end

function RunwaySession.GetDistanceRecorderWorldCenter(hrp: BasePart, humanoid: Humanoid, part: BasePart): Vector3
	local fwd = NormalizeRunwayForward(localState.runwayForward)
	local flatFwd = Vector3.new(fwd.X, 0, fwd.Z)
	if flatFwd.Magnitude < 1e-4 then
		flatFwd = Vector3.new(0, 0, -1)
	else
		flatFwd = flatFwd.Unit
	end
	local anchor = hrp.Position + flatFwd * cfg.RUNWAY_DISTANCE_RECORDER_FORWARD_STUDS
	local probeY = hrp.Position.Y + cfg.RUNWAY_GROUND_RAY_ORIGIN_Y
	local okGround, groundY = RunwaySession.RaycastRunwayGroundYAtWorldXZ(Vector3.new(anchor.X, 0, anchor.Z), humanoid, probeY)
	if okGround then
		Refs.distanceRecorderLastGroundY = groundY
	elseif Refs.distanceRecorderLastGroundY ~= nil then
		groundY = Refs.distanceRecorderLastGroundY :: number
	else
		groundY = hrp.Position.Y - humanoid.HipHeight
	end
	local halfY = part.Size.Y * 0.5
	return Vector3.new(anchor.X, groundY + halfY, anchor.Z)
end

function RunwaySession.EnsureDistanceRecorderFromTemplate(humanoid: Humanoid, hrp: BasePart)
	RunwaySession.DestroyDistanceRecorder()
	local modelsFolder = replicatedStorage:FindFirstChild("Models")
	if modelsFolder == nil then
		if not Refs.distanceRecorderTemplateWarned then
			Refs.distanceRecorderTemplateWarned = true
			warn("[RunwaySession] ReplicatedStorage.Models missing; DistanceRecorder skipped.")
		end
		return
	end
	local template = modelsFolder:FindFirstChild("DistanceRecorder")
	if template == nil or not template:IsA("BasePart") then
		if not Refs.distanceRecorderTemplateWarned then
			Refs.distanceRecorderTemplateWarned = true
			warn("[RunwaySession] ReplicatedStorage.Models.DistanceRecorder missing or not a BasePart; skipped.")
		end
		return
	end
	local clone = template:Clone()
	if not clone:IsA("BasePart") then
		clone:Destroy()
		return
	end
	local part = clone :: BasePart
	part.Name = "JumpRunwayDistanceRecorder"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Parent = RunwaySession.GetJumpRunwayLocalFxFolder()
	local worldCenter = RunwaySession.GetDistanceRecorderWorldCenter(hrp, humanoid, part)
	part.Position = worldCenter
	local ui = part:FindFirstChild("UI")
	if ui == nil or not ui:IsA("SurfaceGui") then
		if not Refs.distanceRecorderTemplateWarned then
			Refs.distanceRecorderTemplateWarned = true
			warn("[RunwaySession] DistanceRecorder.UI missing or not SurfaceGui; text skipped.")
		end
		Refs.runwayDistanceRecorderPart = part
		return
	end
	local surfaceGui = ui :: SurfaceGui
	surfaceGui.Adornee = part
	local controller = surfaceGui:FindFirstChild("ControllerFrame")
	if controller == nil or not controller:IsA("Frame") then
		if not Refs.distanceRecorderTemplateWarned then
			Refs.distanceRecorderTemplateWarned = true
			warn("[RunwaySession] DistanceRecorder.UI.ControllerFrame missing; text skipped.")
		end
		Refs.runwayDistanceRecorderPart = part
		return
	end
	local ability = controller:FindFirstChild("AbilityText")
	if ability == nil or not ability:IsA("TextLabel") then
		if not Refs.distanceRecorderTemplateWarned then
			Refs.distanceRecorderTemplateWarned = true
			warn("[RunwaySession] DistanceRecorder...AbilityText missing or not TextLabel; text skipped.")
		end
		Refs.runwayDistanceRecorderPart = part
		return
	end
	Refs.runwayDistanceRecorderPart = part
	local abilityLabel = ability :: TextLabel
	abilityLabel.AutoLocalize = false
	Refs.runwayDistanceRecorderText = abilityLabel
	local studs = math.max(0, RunwaySession.CurrentAlongProgress(hrp))
	local metersWhole = math.floor(studs + 0.5)
	local tip = GameTexts.JumpRunwayDistanceMeters
	TranslationTool.CustomAutoLocalizeTextLabel(abilityLabel, tip.source, tip.key, { tostring(metersWhole) })
end

function RunwaySession.UpdateDistanceRecorder(humanoid: Humanoid, hrp: BasePart)
	local part = Refs.runwayDistanceRecorderPart
	if part == nil or part.Parent == nil then
		return
	end
	local worldCenter = RunwaySession.GetDistanceRecorderWorldCenter(hrp, humanoid, part)
	part.Position = worldCenter
	local lbl = Refs.runwayDistanceRecorderText
	if lbl ~= nil and lbl.Parent ~= nil then
		local studs = math.max(0, RunwaySession.CurrentAlongProgress(hrp))
		local metersWhole = math.floor(studs + 0.5)
		local tip = GameTexts.JumpRunwayDistanceMeters
		TranslationTool.CustomAutoLocalizeTextLabel(lbl, tip.source, tip.key, { tostring(metersWhole) })
	end
end

function RunwaySession.RestoreRunwayHumanoidLocomotionFromScriptedMode(humanoid: Humanoid?)
	if humanoid == nil or humanoid.Parent == nil then
		return
	end
	RunwaySession.RestoreRunningStateAfterFinalSegment(humanoid)
	RunwaySession.RestorePlatformStandAfterFinalLand(humanoid)
	if humanoid.PlatformStand then
		humanoid.PlatformStand = false
	end
	RunwaySession.RestoreHumanoidAutoRotateAfterFinalPitch(humanoid)
	if humanoid:GetState() == Enum.HumanoidStateType.Physics then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Landed)
		end)
	end
end

function RunwaySession.RestoreRunwayHumanoidPoseAfterGameplay(humanoid: Humanoid?, hrp: BasePart?)
	if humanoid == nil or humanoid.Parent == nil then
		return
	end
	RunwaySession.RestoreRunwayHumanoidLocomotionFromScriptedMode(humanoid)
	if hrp ~= nil and hrp.Parent ~= nil then
		hrp.AssemblyAngularVelocity = Vector3.zero
		local f = NormalizeRunwayForward(localState.runwayForward)
		if f.Magnitude > 1e-4 then
			local pos = hrp.Position
			hrp.CFrame = CFrame.lookAt(pos, pos + f, Vector3.yAxis)
		end
	end
end

function RunwaySession.ResetLocalRunToIdle()
	local _, humanoid, hrp = RunwaySession.GetCharacterParts()
	-- 先同步清理资源和状态（避免异步延迟导致新一局启动后资源混乱）
	RunwaySession.DestroyJumpRunwayRocketBackpack()
	RunwayCameraController.Disable(workspace, GetCharacterParts)
	RunwaySession.DestroyRunwayGravityForce()
	RunwayStateStore.ResetForIdle(localState, Ph, SlideKindStandard)
	RunwaySession.ClearJumpHorizontalLerp()
	RunwaySession.DestroyRunwayRing()
	RunwaySession.ClearLittleElfChestRefs()
	Refs.chestPostRewardExitCleanup = false
	Refs.chestCarryReturnActive = false
	Refs.chestPostOpenTeleportDelayToken += 1
	Refs.deferredTerminalServerPayload = nil
	Refs.missAbortSentForThisRun = nil
	RunwaySession.DestroyDistanceRecorder()
	RunwaySession.SlideTraceScheduleDestroyAfterRunwayEnd()
	RunwayUiController.Destroy(RunwaySession.HudDestroy)
	JumpRunWayFrame.EndSession()
	-- Humanoid 状态恢复延迟到下一帧，避免 Physics 引擎竞争条件
	task.defer(function()
		if RunwaySession.IsRunwayActivePhase(localState.phase) and localState.phase ~= Ph.RunEnded then
			return
		end
		RunwaySession.RestoreRunwayHumanoidLocomotionFromScriptedMode(humanoid)
		RunwaySession.ClearFinalLandingSlideModuleLocals()
		RunwaySession.RestoreRunwayHumanoidPoseAfterGameplay(humanoid, hrp)
		RunwaySession.ClearRunwayFlyingHumanoid(humanoid)
		RunwaySession.ApplyExpectedWalkSpeedAfterRunway(humanoid)
		RunwaySession.ApplyRunwayHumanoidJumpState(humanoid, false)
		if localState.controlsDisabled then
			RunwaySession.SetControlsEnabled(true)
		end
	end)
end

function RunwaySession.ChainHudActive(nowClock: number): boolean
	if localState.phase ~= Ph.Airborne then
		return false
	end
	if localState.takeoffCount < 1 or localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
		return false
	end
	if localState.chainJumpWindowAwaitingGround then
		return true
	end
	if localState.predictJumpWindowUntil ~= nil and nowClock < (localState.predictJumpWindowUntil :: number) then
		return true
	end
	return false
end

function RunwaySession.LineHudActive(nowClock: number): boolean
	if localState.phase ~= Ph.JumpWindow then
		return false
	end
	if localState.lineWindowConsumed then
		return false
	end
	if localState.tHudStart == nil then
		return true
	end
	return localState.lineJumpWindowExpireAt ~= nil and nowClock < (localState.lineJumpWindowExpireAt :: number)
end

function RunwaySession.WindowDriftPhysicsActive(humanoid: Humanoid, nowClock: number): boolean
	local lineCtx = RunwaySession.LineHudActive(nowClock)
	local chainCtx = RunwaySession.ChainHudActive(nowClock)
	if not lineCtx and not chainCtx then
		return false
	end
	if not RunwaySession.IsRunwayJumpWindowRayBandOk(humanoid) then
		return false
	end
	if localState.firstGroundedInWindowClock == nil then
		return false
	end
	return nowClock - (localState.firstGroundedInWindowClock :: number) >= cfg.RUNWAY_JUMPWINDOW_DRIFT_DELAY_AFTER_TOUCH_SEC
end

-- 线窗触线 / 链式武装后：仅在 IsRunwayScriptedGrounded 首次为真时启动 T_WINDOW 与 tHudStart
function RunwaySession.MaybeStartJumpWindowTimingFromGround(humanoid: Humanoid, nowClock: number)
	if not RunwaySession.IsRunwayScriptedGrounded(humanoid) then
		return
	end
	if localState.phase == Ph.JumpWindow and not localState.lineWindowConsumed and localState.tHudStart == nil then
		localState.tHudStart = nowClock
		localState.lineJumpWindowExpireAt = nowClock + cfg.T_WINDOW
		return
	end
	local chainSeg = localState.phase == Ph.Airborne
		and localState.takeoffCount >= 1
		and localState.takeoffCount < cfg.N_TOTAL_JUMPS
	if chainSeg and localState.chainJumpWindowAwaitingGround then
		if RunwaySession.IsRunwayChainWindowHeightOk(humanoid) or RunwaySession.IsRunwayScriptedGrounded(humanoid) then
			if localState.tHudStart == nil then
				localState.tHudStart = nowClock
			end
			localState.predictJumpWindowUntil = nowClock + cfg.T_WINDOW
			localState.chainJumpWindowAwaitingGround = false
		end
	end
end

function RunwaySession.UpdateLocalJumpWindowPrediction(humanoid: Humanoid, nowClock: number)
	local bandOk = RunwaySession.IsRunwayJumpWindowRayBandOk(humanoid)
	local pre = RunwaySession.IsRunwayPreLanding(humanoid)
	local g = RunwaySession.IsRunwayScriptedGrounded(humanoid)
	local lineOrChainContext = localState.phase == Ph.Airborne and localState.takeoffCount >= 1 and localState.takeoffCount < cfg.N_TOTAL_JUMPS
	if lineOrChainContext then
		local armEdge = bandOk and not localState.prevJumpWindowRayBand
		if armEdge then
			localState.firstGroundedInWindowClock = nil
			if g then
				localState.predictJumpWindowUntil = nowClock + cfg.T_WINDOW
				localState.tHudStart = nowClock
				localState.chainJumpWindowAwaitingGround = false
			elseif RunwaySession.IsRunwayChainWindowHeightOk(humanoid) then
				localState.predictJumpWindowUntil = nowClock + cfg.T_WINDOW
				localState.tHudStart = nowClock
				localState.chainJumpWindowAwaitingGround = false
			else
				localState.chainJumpWindowAwaitingGround = true
				localState.predictJumpWindowUntil = nil
				localState.tHudStart = nil
			end
		elseif localState.chainJumpWindowAwaitingGround and RunwaySession.IsRunwayChainWindowHeightOk(humanoid) then
			-- chainJumpWindowAwaitingGround 期间高度达到要求：启动倒计时
			localState.predictJumpWindowUntil = nowClock + cfg.T_WINDOW
			localState.tHudStart = if localState.tHudStart == nil then nowClock else localState.tHudStart
			localState.chainJumpWindowAwaitingGround = false
		end
		localState.prevJumpWindowRayBand = bandOk
		localState.prevLocalGroundedForLand = g
		localState.prevPreLand = pre
	else
		localState.prevLocalGroundedForLand = g
		localState.prevPreLand = pre
		localState.prevJumpWindowRayBand = bandOk
	end
	if localState.predictJumpWindowUntil ~= nil and nowClock >= (localState.predictJumpWindowUntil :: number) then
		if localState.phase == Ph.Airborne and localState.takeoffCount >= 1 and localState.takeoffCount < cfg.N_TOTAL_JUMPS then
			JumpRunWayFrame.ShowMiss()
			RunwaySession.EnterSlidePhase(nowClock, SlideKindMiss, humanoid)
		end
		localState.predictJumpWindowUntil = nil
		localState.chainJumpWindowAwaitingGround = false
	end
	if (RunwaySession.LineHudActive(nowClock) or RunwaySession.ChainHudActive(nowClock)) and bandOk and g then
		if localState.firstGroundedInWindowClock == nil then
			localState.firstGroundedInWindowClock = nowClock
		end
	elseif not RunwaySession.LineHudActive(nowClock) and not RunwaySession.ChainHudActive(nowClock) then
		localState.firstGroundedInWindowClock = nil
	end
	RunwaySession.MaybeStartJumpWindowTimingFromGround(humanoid, nowClock)
end

function RunwaySession.GetEffectivePhysicsPhase(humanoid: Humanoid, nowClock: number): number
	if localState.phase == Ph.AutoRun then
		return Ph.AutoRun
	end
	if localState.phase == Ph.JumpWindow then
		if RunwaySession.WindowDriftPhysicsActive(humanoid, nowClock) then
			return Ph.JumpWindow
		end
		return Ph.AutoRun
	end
	if localState.phase == Ph.Airborne then
		if RunwaySession.ChainHudActive(nowClock) and RunwaySession.WindowDriftPhysicsActive(humanoid, nowClock) then
			return Ph.JumpWindow
		end
		return Ph.Airborne
	end
	return localState.phase
end

function RunwaySession.SyncRunwayHumanoidWalkSpeed(humanoid: Humanoid, nowClock: number)
	if Refs.chestPostRewardExitCleanup == true then
		RunwaySession.ApplyExpectedWalkSpeedAfterRunway(humanoid)
		return
	end
	if localState.phase == Ph.Slide and Refs.chestRewardWaitPose == true then
		RunwaySession.ApplyExpectedWalkSpeedAfterRunway(humanoid)
		return
	end
	if
		localState.phase == Ph.Slide
		and (localState.runwaySlideKind == SlideKindFinalLanding or localState.runwaySlideKind == SlideKindMiss)
		and (localState.finalLandSubPhase == 1 or localState.finalLandSubPhase == 2)
	then
		if humanoid.WalkSpeed ~= 0 then
			humanoid.WalkSpeed = 0
		end
		return
	end
	if localState.phase == Ph.Airborne then
		local locMode = RunwaySession.ResolveRunwayLocomotionMode(humanoid, nowClock)
		if locMode == RUNWAY_LOCOMOTION_WALK then
			local wWalk = cfg.JUMP_WINDOW_WALK_SPEED
			if humanoid.WalkSpeed ~= wWalk then
				humanoid.WalkSpeed = wWalk
			end
			return
		end
		if locMode == RUNWAY_LOCOMOTION_RUN then
			local wRun = RunwaySession.GetRunwayTargetGroundAlongSpeed(humanoid, nowClock)
			if humanoid.WalkSpeed ~= wRun then
				humanoid.WalkSpeed = wRun
			end
			return
		end
		if humanoid.WalkSpeed ~= 0 then
			humanoid.WalkSpeed = 0
		end
		return
	end
	if localState.phase == Ph.JumpWindow and RunwaySession.WindowDriftPhysicsActive(humanoid, nowClock) then
		local wDrift = cfg.JUMP_WINDOW_WALK_SPEED
		if humanoid.WalkSpeed ~= wDrift then
			humanoid.WalkSpeed = wDrift
		end
		return
	end
	-- AutoRun / 起跳窗触地前段 / 链式窗贴地前段：与沿轴脚本推速对齐，供 Running 动画
	local w = cfg.FIRST_TAKEOFF_AUTORUN_SPEED
	if localState.takeoffCount >= 1 then
		local _, minSpd = GameConfig.GetJumpRunwayJumpSpeedLimitsForSegment(
			math.max(1, localState.takeoffCount),
			localState.jumpSpeedCumulativeRatingBonus,
			GetJumpPowerBaseSpeed()
		)
		w = minSpd
	end
	if humanoid.WalkSpeed ~= w then
		humanoid.WalkSpeed = w
	end
end

function RunwaySession.ApplyLocalPhysics(dt: number)
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		return
	end
	local _character, humanoid, hrp = RunwaySession.GetCharacterParts()
	if humanoid == nil or hrp == nil then
		return
	end
	local forward = NormalizeRunwayForward(localState.runwayForward)
	local nowClock = os.clock()
	RunwaySession.UpdateLocalJumpWindowPrediction(humanoid, nowClock)
	local eff = RunwaySession.GetEffectivePhysicsPhase(humanoid, nowClock)
	if eff == Ph.AutoRun then
		RunwaySession.UpdateAutoRunVelocity(hrp, forward, dt, humanoid)
	elseif eff == Ph.JumpWindow then
		if RunwaySession.WindowDriftPhysicsActive(humanoid, nowClock) then
			RunwaySession.ApplyJumpWindowWalkPhysics(humanoid, hrp, forward)
		elseif localState.takeoffCount == 0 then
			RunwaySession.UpdateAutoRunVelocity(hrp, forward, dt, humanoid)
		else
			RunwaySession.ApplyJumpWindowWalkPhysics(humanoid, hrp, forward)
		end
	elseif localState.phase == Ph.Airborne then
		RunwaySession.UpdateAutoRunVelocity(hrp, forward, dt, humanoid)
		if localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
			RunwaySession.UpdateDashVerticalOnly(hrp, dt)
		end
	elseif localState.phase == Ph.Slide then
		if localState.runwaySlideKind == SlideKindFinalLanding or localState.runwaySlideKind == SlideKindMiss then
			RunwaySession.ApplyFinalLandingSlidePhysics(hrp, forward, dt, nowClock, humanoid)
		else
			RunwaySession.UpdateSlideVelocity(hrp, forward, nowClock)
		end
	elseif localState.phase == Ph.RunEnded then
		-- 终局稳定窗口内禁止沿轴回退，避免在 Final 上报前出现“抽回”体感。
		local v = hrp.AssemblyLinearVelocity
		local along = RunwayPhysicsController.ComputeRunwayHorizontalAlongSpeed(v, forward)
		local keepAlong = math.max(0, along)
		hrp.AssemblyLinearVelocity = forward * keepAlong + Vector3.new(0, v.Y, 0)
	end
	if not RunwaySession.IsLittleElfChestRunwayFlowActive() or Refs.chestBounceActive == true then
		if Refs.chestPostRewardExitCleanup ~= true then
			RunwaySession.EnsureRunwayGravityForce(hrp)
			RunwaySession.UpdateRunwayGravityForce(hrp)
		else
			RunwaySession.DestroyRunwayGravityForce()
		end
	elseif RunwaySession.IsLittleElfChestRunwayFlowActive() then
		RunwaySession.DestroyRunwayGravityForce()
	end
end

function RunwaySession.OnPreSimulation(dt: number)
	if RunwaySession.IsRunwayActivePhase(localState.phase) then
		local _, humanoidPre, hrpPre = RunwaySession.GetCharacterParts()
		if humanoidPre ~= nil then
			local nowClockPre = os.clock()
			RunwaySession.SyncRunwayHumanoidWalkSpeed(humanoidPre, nowClockPre)
			RunwaySession.SyncRunwayFinalSegmentLocomotionPrePhysics(humanoidPre, hrpPre)
		end
	end
	RunwaySession.ApplyLocalPhysics(dt)
end

function RunwaySession.OnPostSimulationLocomotion(dt: number)
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		return
	end
	local _, humanoid, hrp = RunwaySession.GetCharacterParts()
	if humanoid == nil then
		return
	end
	local forward = NormalizeRunwayForward(localState.runwayForward)
	local nowClock = os.clock()
	RunwaySession.ApplyRunwayLocomotionAnimation(humanoid, forward, nowClock, hrp)
	if hrp ~= nil and localState.phase == Ph.Airborne and localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
		RunwaySession.EnsureHumanoidAutoRotateOffForFinalPitch(humanoid)
		RunwaySession.ApplyRunwayFinalBodyPitch(hrp, forward, dt)
	elseif hrp ~= nil and localState.phase == Ph.Slide and localState.runwaySlideKind == SlideKindFinalLanding then
		if not RunwaySession.IsLittleElfChestRunwayFlowActive() then
			RunwaySession.EnsureHumanoidAutoRotateOffForFinalPitch(humanoid)
			RunwaySession.ApplyFinalLandingRenderOrientation(humanoid, hrp, forward, dt, nowClock)
			RunwaySession.SlideTraceUpdate(humanoid, hrp)
		end
	elseif hrp ~= nil and localState.phase == Ph.Slide and localState.runwaySlideKind == SlideKindMiss then
		if not RunwaySession.IsLittleElfChestRunwayFlowActive() then
			RunwaySession.EnsureHumanoidAutoRotateOffForFinalPitch(humanoid)
			-- miss 滑行：趴姿但不压地面偏移
			RunwaySession.ApplyFinalLandingRenderOrientation(humanoid, hrp, forward, dt, nowClock, 0)
			RunwaySession.SlideTraceUpdate(humanoid, hrp)
		end
	end
	local isFinalLandingSlide = localState.phase == Ph.Slide and localState.runwaySlideKind == SlideKindFinalLanding
	if RunwaySession.IsLittleElfChestRunwayFlowActive() and Refs.chestRewardWaitPose == true then
		RunwaySession.RestoreHumanoidAutoRotateAfterFinalPitch(humanoid)
		if hrp ~= nil then
			RunwaySession.ApplyLittleElfChestStandingWaitOrientation(humanoid, hrp, forward)
		end
	elseif Refs.chestPostRewardExitCleanup == true and hrp ~= nil then
		RunwaySession.SnapCharacterHrpToGround(humanoid, hrp, forward)
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	elseif
		(localState.phase == Ph.Airborne and localState.takeoffCount >= cfg.N_TOTAL_JUMPS)
		or isFinalLandingSlide
	then
		if hrp ~= nil then
			RunwaySession.EnsureHumanoidAutoRotateOffForFinalPitch(humanoid)
		end
	else
		RunwaySession.RestoreHumanoidAutoRotateAfterFinalPitch(humanoid)
	end
end

function RunwaySession.OnJumpRunwayFinalTiltRenderStep(dt: number)
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		return
	end
	local _, humanoid, hrp = RunwaySession.GetCharacterParts()
	if humanoid == nil or hrp == nil then
		return
	end
	local forward = NormalizeRunwayForward(localState.runwayForward)
	if localState.phase == Ph.Slide and (localState.runwaySlideKind == SlideKindFinalLanding or localState.runwaySlideKind == SlideKindMiss) then
		if RunwaySession.IsLittleElfChestRunwayFlowActive() then
			RunwaySession.EnsureHumanoidAutoRotateOffForFinalPitch(humanoid)
			if Refs.chestBounceActive == true then
				RunwaySession.ApplyLittleElfChestProneBounceOrientation(hrp, forward, dt)
			else
				RunwaySession.ApplyLittleElfChestStandingWaitOrientation(humanoid, hrp, forward)
			end
		end
	else
		return
	end
	if not RunwaySession.IsLittleElfChestRunwayFlowActive() or Refs.chestBounceActive == true then
		if Refs.chestPostRewardExitCleanup ~= true then
			RunwaySession.EnsureRunwayGravityForce(hrp)
			RunwaySession.UpdateRunwayGravityForce(hrp)
		else
			RunwaySession.DestroyRunwayGravityForce()
		end
	elseif RunwaySession.IsLittleElfChestRunwayFlowActive() then
		RunwaySession.DestroyRunwayGravityForce()
	end
end

function RunwaySession.ProcessJumpWindowTimeout(nowClock: number)
	if localState.phase ~= Ph.JumpWindow then
		return
	end
	if localState.lineWindowConsumed then
		return
	end
	if localState.lineJumpWindowExpireAt ~= nil and nowClock >= (localState.lineJumpWindowExpireAt :: number) then
		localState.lineWindowConsumed = true
		JumpRunWayFrame.ShowMiss()
		local _character, humanoidTimeout, _hrpTimeout = RunwaySession.GetCharacterParts()
		RunwaySession.EnterSlidePhase(nowClock, SlideKindMiss, humanoidTimeout)
	end
end

-- 在 Heartbeat 用 grounded 边沿处理 AutoRun 回贴（takeoffCount==0）
function RunwaySession.ProcessAirborneLandingHeartbeat(humanoid: Humanoid)
	if localState.phase ~= Ph.Airborne then
		Refs.prevGroundedHeartbeat = RunwaySession.IsRunwayScriptedGrounded(humanoid)
		return
	end
	-- 第 N 跳：缓存坠落竖直速度用于子阶段 A 弹跳计算
	-- 防抖：速度变化超过正常重力加速度区间则不缓存（避免碰撞突变干扰）
	if localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
		local _chkChar, _chkHum, chkHrp = RunwaySession.GetCharacterParts()
		if chkHrp ~= nil then
			local curVy = chkHrp.AssemblyLinearVelocity.Y
			local prevVy = localState.finalLandCachedLandingVy
			if prevVy == nil or math.abs(curVy - prevVy) < 8 then
				localState.finalLandCachedLandingVy = curVy
			end
		end
	end
	local g = RunwaySession.IsRunwayScriptedGrounded(humanoid)
	if g and not Refs.prevGroundedHeartbeat then
		if localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
			-- 终局跳不在此用 IsRunwayScriptedGrounded 边沿触发 Slide；见下方 RaycastFeet 专用触地。
		elseif localState.takeoffCount >= 1 then
			-- 链式：已在 UpdateLocalJumpWindowPrediction 处理
		else
			localState.phase = Ph.AutoRun
			RunwaySession.ClearJumpHorizontalLerp()
			localState.predictJumpWindowUntil = nil
			localState.tHudStart = nil
			localState.chainJumpWindowAwaitingGround = false
		end
		Refs.prevGroundedHeartbeat = g
		return
	end
	-- 第 N 跳：保护期结束后用射线检测实际贴地
	-- 不使用 IsRunwayScriptedGrounded（可能因 Freefall 状态返回 false）
	-- 不使用 FloorMaterial（起跳后在空中仍可能保持非 Air 值）
	-- 直接用 RaycastFeet 检测脚下地面距离是否小于阈值（~1 倍 hip height）
	if localState.takeoffCount >= cfg.N_TOTAL_JUMPS
		and os.clock() >= Refs.finalTakeoffForceFreefallUntilClock then
		local ok, dist = RunwaySession.RaycastFeet(humanoid)
		if ok and dist <= humanoid.HipHeight * 1.5 + cfg.RUNWAY_GROUND_RAY_ORIGIN_Y then
			RunwaySession.EnterSlidePhase(os.clock(), SlideKindFinalLanding, humanoid)
			Refs.prevGroundedHeartbeat = true
			return
		end
	end
	Refs.prevGroundedHeartbeat = g
end

function RunwaySession.OnBeginLineCharacterContactConfirmed()
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		return
	end
	localState.passedBeginLineOnce = true
	if localState.phase == Ph.AutoRun and not localState.jumpedBeforeBeginLine then
		local nowClock = os.clock()
		localState.phase = Ph.JumpWindow
		localState.lineWindowConsumed = false
		localState.lineJumpWindowExpireAt = nil
		localState.tHudStart = nil
		localState.firstGroundedInWindowClock = nil
		local _character, humanoid, _hrp = RunwaySession.GetCharacterParts()
		if humanoid ~= nil then
			RunwaySession.MaybeStartJumpWindowTimingFromGround(humanoid, nowClock)
		end
	end
end

function RunwaySession.PollBeginLineOverlapForJumpWindow()
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		return
	end
	local character = localPlayer.Character
	if character == nil then
		return
	end
	local _, beginLine = RunwaySession.ResolveSceneParts()
	if beginLine == nil or not beginLine:IsA("BasePart") then
		return
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { character }
	overlap.MaxParts = 64
	overlap.RespectCanCollide = false
	local pad = cfg.BEGIN_LINE_OVERLAP_PADDING_STUDS
	local boxSize = beginLine.Size + Vector3.new(pad * 2, pad * 2, pad * 2)
	local parts = workspace:GetPartBoundsInBox(beginLine.CFrame, boxSize, overlap)
	if #parts == 0 then
		return
	end
	RunwaySession.OnBeginLineCharacterContactConfirmed()
end

function RunwaySession.ProcessFinalLandingSubPhaseTransition(humanoid: Humanoid, hrp: BasePart, nowClock: number)
	if localState.phase ~= Ph.Slide or localState.runwaySlideKind ~= SlideKindFinalLanding then
		return
	end
	if localState.finalLandSubPhase ~= 1 then
		return
	end
	if not localState.finalLandTumbleImpulseApplied then
		return
	end
	local forwardCheck = NormalizeRunwayForward(localState.runwayForward)

	local vyScriptMaxRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_TOUCHDOWN_SCRIPT_MAX_VY
	local vyScriptMax = -3
	if typeof(vyScriptMaxRaw) == "number" and vyScriptMaxRaw == vyScriptMaxRaw and vyScriptMaxRaw < -0.05 then
		vyScriptMax = vyScriptMaxRaw
	end

	local vyFbAbsMaxRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_TOUCHDOWN_FULLBODY_MAX_ABS_VY
	local vyFbAbsMax = 85
	if typeof(vyFbAbsMaxRaw) == "number" and vyFbAbsMaxRaw == vyFbAbsMaxRaw and vyFbAbsMaxRaw >= 6 then
		vyFbAbsMax = vyFbAbsMaxRaw
	end

	-- 终局触地检测：使用独立配置 RUNWAY_FINAL_LAND_TOUCHDOWN_FEET_MAX_DIST_STUDS，不依赖 preLandRayBaselineStuds
	local okFeet, distFeet = RunwaySession.RaycastFeet(humanoid)
	local fullBody = RunwaySession.IsRunwayFinalLandFullBodyGrounded(humanoid, hrp)
	local touchdownDistRaw = cfg.RUNWAY_FINAL_LAND_TOUCHDOWN_FEET_MAX_DIST_STUDS
	local touchdownDist = (typeof(touchdownDistRaw) == "number" and touchdownDistRaw == touchdownDistRaw and touchdownDistRaw > 0) and touchdownDistRaw or 4
	local geomTouch = fullBody or (okFeet and distFeet <= touchdownDist)
	local vy = hrp.AssemblyLinearVelocity.Y
	if not geomTouch or vy > vyScriptMax or math.abs(vy) > vyFbAbsMax then
		return
	end

	local fwdHCheck = Vector3.new(forwardCheck.X, 0, forwardCheck.Z)
	if fwdHCheck.Magnitude < 1e-4 then
		fwdHCheck = Vector3.new(0, 0, -1)
	else
		fwdHCheck = fwdHCheck.Unit
	end

	-- 子阶段 A → B：竖直速度判断。弹性次弹跳时 finalLandTumblePrevPopVy 是前一次 vyPop；
	-- 如果前一次弹跳速度已经接近最低阈值（minPopVy），本次触地后不再弹跳直接进 B
	local minVyRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_MIN_POP_VY
	local minBounceVy = (typeof(minVyRaw) == "number" and minVyRaw == minVyRaw and minVyRaw >= 0) and minVyRaw or 3
	local shouldEnterB = localState.finalLandTumblePrevPopVy <= minBounceVy * 1.1
	if shouldEnterB then
		RunwaySession.StartFinalLandPronePhase(nowClock, hrp, forwardCheck)
		return
	end

	if localState.finalLandTumbleUseAirClock and not localState.finalLandTumbleLeftGround then
		return
	end

	RunwaySession.ApplyFinalLandPhaseAPop(hrp, fwdHCheck, nowClock)
end

function RunwaySession.OnBeginLineTouched(hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	if character ~= localPlayer.Character then
		return
	end
	RunwaySession.OnBeginLineCharacterContactConfirmed()
end

function RunwaySession.ComputePhaseBSlideStopDistance(alongSpd: number, brakeK: number): (number, number)
	local vSafe = math.max(0.45, alongSpd)
	local tSlide = math.log(vSafe / 0.45) / brakeK
	local dStop = vSafe / brakeK * (1 - math.exp(-brakeK * tSlide))
	return dStop, tSlide
end

-- 子阶段 B 入口调度：总时长 = 实际 T_A + T_B，此处已知 A 已结束，只需在 B 结束前 spawnBeforeSec 生成
function RunwaySession.ScheduleLittleElfChestAtPhaseBEnter(
	fwdH: Vector3,
	alongSpdEnter: number,
	spawnPos: Vector3,
	phaseBSec: number?
)
	if Refs.chestSpawnedForThisRun == true then
		return
	end
	local brakeK = cfg.RUNWAY_FINAL_LAND_PRONE_SLIDE_BRAKE_EXP
	local tSlideB = phaseBSec
	if typeof(tSlideB) ~= "number" or tSlideB ~= tSlideB or tSlideB < 0 then
		local _, computedB = RunwaySession.ComputePhaseBSlideStopDistance(alongSpdEnter, brakeK)
		tSlideB = computedB
	end
	local spawnBeforeSec = cfg.RUNWAY_CHEST_SPAWN_BEFORE_END_SEC
	if typeof(spawnBeforeSec) ~= "number" or spawnBeforeSec ~= spawnBeforeSec or spawnBeforeSec < 0 then
		spawnBeforeSec = 1.0
	end
	local spawnDelay = math.max(0, tSlideB - spawnBeforeSec)
	local fallDuration = math.min(1, math.max(0.25, spawnBeforeSec * 0.85))

	Refs.chestSlideFwdH = fwdH
	Refs.chestScheduledSpawnPos = spawnPos

	Refs.chestSpawnDelayToken += 1
	local delayToken = Refs.chestSpawnDelayToken
	task.delay(spawnDelay, function()
		if delayToken ~= Refs.chestSpawnDelayToken then
			return
		end
		if localState.phase ~= Ph.Slide or localState.runwaySlideKind ~= SlideKindFinalLanding then
			return
		end
		if localState.finalLandSubPhase ~= 2 then
			return
		end
		if Refs.chestSpawnedForThisRun == true then
			return
		end
		local slideFwd = Refs.chestSlideFwdH or fwdH
		local resolvedSpawnPos = Refs.chestScheduledSpawnPos or spawnPos
		RunwaySession.SpawnLittleElfChestAtPosition(slideFwd, resolvedSpawnPos, fallDuration)
	end)
end

function RunwaySession.IsLittleElfChestRunwayFlowActive(): boolean
	return Refs.chestRunwayAwaitingExit == true
end

function RunwaySession.ShouldBlockFinalLandingSlideEndForChest(): boolean
	if localState.runwaySlideKind ~= SlideKindFinalLanding then
		return false
	end
	if localState.finalLandSubPhase ~= 2 then
		return false
	end
	return Refs.chestRewardPresentationStarted ~= true
end

function RunwaySession.ClearLittleElfChestRefs()
	Refs.chestSpawnDelayToken += 1
	RunwaySession.DestroyLittleElfChestSpawnedModel()
	Refs.chestSpawnedForThisRun = false
	Refs.chestPickedBrainrotId = nil
	Refs.chestPickedConfigId = nil
	Refs.chestAnimPlaying = false
	Refs.chestReadyForHit = false
	Refs.chestHitSequenceActive = false
	Refs.chestOpenCFrame = nil
	Refs.chestSlideFwdH = nil
	Refs.chestRunwayAwaitingExit = false
	Refs.chestBounceActive = false
	Refs.chestRewardWaitPose = false
	Refs.chestLandedOnGround = false
	Refs.chestGroundOpenCFrame = nil
	Refs.chestPendingReward = nil
	Refs.chestRewardPresentationStarted = false
	Refs.chestBounceAlongSpeed = nil
	Refs.chestLandClock = nil
	Refs.chestDynamicConfigId = nil
	Refs.chestScheduledSpawnPos = nil
	Refs.chestPredictedPlaceDistance = nil
	Refs.chestBackpackDeliverRequested = false
	Refs.lastRunAlongDistance = nil
	ChaserClientManager.CleanupChaser()
end

function RunwaySession.BuildLittleElfChestOpenCFrame(pos: Vector3, _slideFwdH: Vector3, chestModel: Model?): CFrame
	-- 保留模型模板默认朝向（与随机开箱 GetPivot 一致）；lookAt 会与资源轴向差 90°
	if chestModel then
		local pivot = chestModel:GetPivot()
		return CFrame.new(pos) * (pivot - pivot.Position)
	end
	return CFrame.new(pos)
end

function RunwaySession.ComputeLittleElfChestSpawnPositionAtOrigin(
	originPos: Vector3,
	hrpForHeight: BasePart,
	fwdH: Vector3,
	placeDistance: number
): Vector3
	local rayStart = originPos + fwdH * placeDistance + Vector3.new(0, 5, 0)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local character = hrpForHeight:FindFirstAncestorOfClass("Model")
	if character then
		rayParams.FilterDescendantsInstances = { character }
	end
	local rayResult = workspace:Raycast(rayStart, Vector3.new(0, -30, 0), rayParams)
	local groundY = if rayResult then rayResult.Position.Y else originPos.Y - 1
	-- 落点以跑道地面射线为准，略高于地面避免穿模（不再钳到 HRP 趴滑高度，否则会视觉上悬空）
	local chestY = groundY + CHEST_GROUND_RAISE_STUDS
	return Vector3.new(
		originPos.X + fwdH.X * placeDistance,
		chestY,
		originPos.Z + fwdH.Z * placeDistance
	)
end

function RunwaySession.ComputeLittleElfChestSpawnPosition(hrp: BasePart, fwdH: Vector3, placeDistance: number): Vector3
	return RunwaySession.ComputeLittleElfChestSpawnPositionAtOrigin(hrp.Position, hrp, fwdH, placeDistance)
end

function RunwaySession.HideLittleElfChestModel(chestModel: Model)
	for _, part in chestModel:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanTouch = false
			part.Transparency = 1
		end
	end
end

function RunwaySession.DestroyLittleElfChestSpawnedModel()
	if Refs.chestSpawnedConnList then
		for _, conn in ipairs(Refs.chestSpawnedConnList) do
			conn:Disconnect()
		end
		Refs.chestSpawnedConnList = nil
	end
	if Refs.chestSpawnedModel and Refs.chestSpawnedModel.Parent then
		Refs.chestSpawnedModel:Destroy()
	end
	Refs.chestSpawnedModel = nil
end

function RunwaySession.GetLittleElfChestFallbackBrainrotId(chestConfigId: number): number?
	local rewardPool = GameConfig.LittleElfChestRewardPoolMap[chestConfigId]
	if rewardPool == nil then
		return nil
	end
	local smallestId: number? = nil
	for _, entry in ipairs(rewardPool) do
		local itemId = entry.itemId
		if typeof(itemId) == "number" and (smallestId == nil or itemId < (smallestId :: number)) then
			smallestId = itemId
		end
	end
	return smallestId
end

function RunwaySession.IsLittleElfChestCarryReturnActive(): boolean
	return Refs.chestCarryReturnActive == true
end

function RunwaySession.IsLocalPlayerCarryingRunwayLittleElfChest(character: Model): boolean
	local carrying = character:FindFirstChild("CarryingBrainrot")
	if carrying == nil then
		return false
	end
	return carrying:GetAttribute(JumpRunwayLittleElfChestCarryAttr) == true
end

function RunwaySession.IsPlayerInsideStartTriggerVolume(startTrigger: Part, hrp: BasePart): boolean
	local localPos = startTrigger.CFrame:PointToObjectSpace(hrp.Position)
	local halfSize = startTrigger.Size * 0.5
	return math.abs(localPos.X) <= halfSize.X
		and math.abs(localPos.Y) <= halfSize.Y + 3
		and math.abs(localPos.Z) <= halfSize.Z
end

function RunwaySession.IsPlayerCloseEnoughToStartTrigger(startTrigger: Part, hrp: BasePart): boolean
	return (hrp.Position - startTrigger.Position).Magnitude
		< math.max(startTrigger.Size.Magnitude * 2, StartTriggerCloseEnoughMinStuds)
end

function RunwaySession.UpdateStartTriggerReentryState()
	local startTrigger, _ = RunwaySession.ResolveSceneParts()
	if startTrigger == nil then
		return
	end
	local character, humanoid, hrp = RunwaySession.GetCharacterParts()
	if hrp == nil then
		return
	end

	local insideNow = RunwaySession.IsPlayerInsideStartTriggerVolume(startTrigger, hrp)
	local wasInside = Refs.startTriggerPlayerWasInsideVolume == true

	if Refs.startTriggerStartArmed == false then
		if not insideNow then
			local outsideClock = Refs.startTriggerOutsideVolumeClock
			if outsideClock == nil then
				Refs.startTriggerOutsideVolumeClock = os.clock()
			elseif os.clock() - outsideClock >= StartTriggerRearmOutsideMinSec then
				Refs.startTriggerStartArmed = true
			end
		else
			Refs.startTriggerOutsideVolumeClock = nil
		end
	end

	local enteredNow = insideNow and not wasInside
	if enteredNow then
		if character and RunwaySession.IsLocalPlayerCarryingRunwayLittleElfChest(character) then
			RunwaySession.TryDeliverLittleElfChestAtStartTrigger(startTrigger)
		elseif Refs.chestCarryReturnActive ~= true and Refs.startTriggerStartArmed == true then
			if humanoid and not RunwaySession.IsRunwayActivePhase(localState.phase) then
				if RunwaySession.SnapLocalPlayerToRunwayGroundIfAirborne(startTrigger, humanoid, hrp) then
					RunwaySession.TryStartLocalRun(startTrigger)
				end
			end
		end
	elseif insideNow and character and RunwaySession.IsLocalPlayerCarryingRunwayLittleElfChest(character) then
		RunwaySession.TryDeliverLittleElfChestAtStartTrigger(startTrigger)
	end

	Refs.startTriggerPlayerWasInsideVolume = insideNow
end

function RunwaySession.ShouldBlockJumpRunwayStartAtStartTrigger(): boolean
	if Refs.startTriggerStartArmed == false then
		return true
	end
	local character = localPlayer.Character
	if character and RunwaySession.IsLocalPlayerCarryingRunwayLittleElfChest(character) then
		return true
	end
	return Refs.chestCarryReturnActive == true
end

function RunwaySession.EnterLittleElfChestCarryReturn(brainrotId: number?, chestConfigId: number?)
	NetMsg.FireRequestJumpRunwayLittleElfChestStartCarry(brainrotId, chestConfigId)
	RunwayCameraController.Disable(workspace, RunwaySession.GetCharacterParts)
	RunwaySession.DestroyJumpRunwayRocketBackpack()
	RunwaySession.DestroyRunwayGravityForce()
	RunwaySession.DestroyRunwayRing()
	RunwaySession.SlideTraceScheduleDestroyAfterRunwayEnd()
	local forwardExit = Refs.chestSlideFwdH or NormalizeRunwayForward(localState.runwayForward)
	if forwardExit.Magnitude < 1e-4 then
		forwardExit = Vector3.new(0, 0, -1)
	else
		forwardExit = Vector3.new(forwardExit.X, 0, forwardExit.Z).Unit
	end
	local _, hDelay, hrpDelay = RunwaySession.GetCharacterParts()
	if hDelay and hrpDelay then
		RunwaySession.SnapCharacterHrpToGround(hDelay, hrpDelay, forwardExit)
		hrpDelay.AssemblyLinearVelocity = Vector3.zero
		hrpDelay.AssemblyAngularVelocity = Vector3.zero
		RunwaySession.RestoreRunwayHumanoidLocomotionFromScriptedMode(hDelay)
		RunwaySession.ClearFinalLandingSlideModuleLocals()
		RunwaySession.RestoreRunwayHumanoidPoseAfterGameplay(hDelay, hrpDelay)
		RunwaySession.ApplyExpectedWalkSpeedAfterRunway(hDelay)
	end
	localState.phase = Ph.Idle
	localState.groundedStableTime = 0
	Refs.deferredTerminalServerPayload = nil
	Refs.chestPostOpenTeleportDelayToken += 1
	if localState.controlsDisabled then
		RunwaySession.SetControlsEnabled(true)
	end
	-- 在清理之前先获取怪物数据
	local monsterData: GameConfig.MonsterData? = nil
	if Refs.lastRunAlongDistance ~= nil then
		monsterData = GameConfig.GetMonsterByDistance(Refs.lastRunAlongDistance)
	end
	local chaserSpeedOverride = if monsterData then monsterData.moveSpeed else nil
	RunwaySession.ClearLittleElfChestRefs()
	if hDelay then
		ChaserClientManager.SpawnChaser(hDelay:FindFirstAncestorOfClass("Model") :: Model, forwardExit, chaserSpeedOverride)
	end
	Refs.chestCarryReturnActive = true
	JumpRunWayFrame.EndSession()
end

function RunwaySession.TryDeliverLittleElfChestAtStartTrigger(startTrigger: Part)
	if Refs.chestBackpackDeliverRequested == true then
		return
	end
	local character, humanoid, hrp = RunwaySession.GetCharacterParts()
	if character == nil or humanoid == nil or hrp == nil then
		return
	end
	if not RunwaySession.IsLocalPlayerCarryingRunwayLittleElfChest(character) then
		return
	end
	if not RunwaySession.IsPlayerCloseEnoughToStartTrigger(startTrigger, hrp) then
		return
	end
	Refs.chestBackpackDeliverRequested = true
	Refs.startTriggerStartArmed = false
	Refs.startTriggerPlayerWasInsideVolume = true
	Refs.startTriggerOutsideVolumeClock = nil
	Refs.chestCarryReturnActive = false
	ChaserClientManager.StopAndFadeChaser()
	NetMsg.FireRequestJumpRunwayLittleElfChestGrant()
	task.delay(1, function()
		if Refs.chestBackpackDeliverRequested ~= true then
			return
		end
		local retryCharacter = localPlayer.Character
		if retryCharacter and RunwaySession.IsLocalPlayerCarryingRunwayLittleElfChest(retryCharacter) then
			Refs.chestBackpackDeliverRequested = false
		end
	end)
end

function RunwaySession.DeliverLittleElfChestRewardToBackpackAfterOpenAnim()
	if Refs.chestBackpackDeliverRequested == true then
		return
	end
	if Refs.chestPendingReward == nil and Refs.chestPickedBrainrotId == nil then
		return
	end
	Refs.chestBackpackDeliverRequested = true
	NetMsg.FireRequestJumpRunwayLittleElfChestGrant()
	Refs.chestPendingReward = nil
end

function RunwaySession.TryPresentLittleElfChestReward()
	if Refs.chestRewardPresentationStarted == true then
		return
	end
	local pickedConfigId = Refs.chestPickedConfigId
	if pickedConfigId == nil then
		return
	end
	Refs.chestRewardPresentationStarted = true
	Refs.chestAnimPlaying = true

	local runwayChestModelForOpen = Refs.chestSpawnedModel
	local openCFrame = if runwayChestModelForOpen and runwayChestModelForOpen.Parent
		then runwayChestModelForOpen:GetPivot()
		else (Refs.chestGroundOpenCFrame or Refs.chestOpenCFrame)
	if openCFrame == nil then
		local _, _, hrp = RunwaySession.GetCharacterParts()
		if hrp then
			openCFrame = hrp.CFrame
		end
	end
	local _, humanoidOpen, hrpOpen = RunwaySession.GetCharacterParts()
	if Refs.chestBounceActive ~= true and humanoidOpen and hrpOpen then
		RunwaySession.EnterLittleElfChestRewardWaitPose(humanoidOpen, hrpOpen)
	end
	if openCFrame then
		local runwayChestModel = Refs.chestSpawnedModel
		Refs.chestSpawnedModel = nil
		Refs.chestSpawnedConnList = nil
		local selectedBrainrotId = ChestOpenAnimationManager.PlayInWorldAndWait(
			"RunwayChest_" .. tostring(os.clock()),
			pickedConfigId,
			1,
			Refs.chestPickedBrainrotId or 0,
			openCFrame,
			{
				existingChestModel = runwayChestModel,
				lockFacing = true,
				resolveFinalBrainrotId = function()
					if Refs.chestPickedConfigId ~= pickedConfigId then
						return nil
					end
					return Refs.chestPickedBrainrotId
				end,
			}
		)
		if selectedBrainrotId == nil then
			selectedBrainrotId = RunwaySession.GetLittleElfChestFallbackBrainrotId(pickedConfigId)
		end
		Refs.chestPickedBrainrotId = selectedBrainrotId
	end
	RunwaySession.EnterLittleElfChestCarryReturn(Refs.chestPickedBrainrotId, pickedConfigId)
end

function RunwaySession.EndChestProneBounceAndWaitForReward()
	if Refs.chestRunwayAwaitingExit ~= true then
		return
	end
	Refs.chestBounceActive = false
	Refs.chestBounceAlongSpeed = nil
	Refs.chestRewardWaitPose = true
	RunwaySession.DestroyRunwayGravityForce()
	local _, humanoidWait, hrpWait = RunwaySession.GetCharacterParts()
	if humanoidWait and hrpWait then
		local forwardWait = NormalizeRunwayForward(localState.runwayForward)
		RunwaySession.ApplyLittleElfChestStandingWaitOrientation(humanoidWait, hrpWait, forwardWait)
	end
	RunwaySession.TryPresentLittleElfChestReward()
end

function RunwaySession.SnapCharacterHrpToGround(humanoid: Humanoid, hrp: BasePart, fwdStand: Vector3)
	local character = hrp:FindFirstAncestorOfClass("Model")
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	if character then
		rayParams.FilterDescendantsInstances = { character }
	end
	local rayOrigin = hrp.Position + Vector3.new(0, 3, 0)
	local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -25, 0), rayParams)
	if rayResult then
		local hipHeight = humanoid.HipHeight
		if typeof(hipHeight) ~= "number" or hipHeight ~= hipHeight or hipHeight < 0 then
			hipHeight = 2
		end
		local groundPos = Vector3.new(hrp.Position.X, rayResult.Position.Y + hipHeight, hrp.Position.Z)
		hrp.CFrame = CFrame.lookAt(groundPos, groundPos + fwdStand, Vector3.yAxis)
	end
end

function RunwaySession.ApplyLittleElfChestProneBounceOrientation(hrp: BasePart, forward: Vector3, dt: number)
	local slideFwd = Refs.chestSlideFwdH or forward
	local pos = hrp.Position
	local linVel = hrp.AssemblyLinearVelocity
	local proneOffset = cfg.RUNWAY_FINAL_LAND_PRONE_GROUND_OFFSET
	if typeof(proneOffset) ~= "number" or proneOffset ~= proneOffset then
		proneOffset = 0
	end
	-- 与子阶段 B 趴滑一致：相对当前 HRP 做 prone 偏移，勿射线钳到地面（会把趴滑高度压进地底）
	local pronePos = Vector3.new(pos.X, pos.Y - proneOffset, pos.Z)
	local proneLocked = RunwaySession.BuildProneRunwayCFrame(pronePos, slideFwd)
	hrp.CFrame = proneLocked
	local slideFwdUnit = slideFwd
	if slideFwdUnit.Magnitude < 1e-4 then
		slideFwdUnit = Vector3.new(0, 0, -1)
	else
		slideFwdUnit = slideFwdUnit.Unit
	end
	local alongOnly = linVel:Dot(slideFwdUnit)
	hrp.AssemblyLinearVelocity = slideFwdUnit * alongOnly
	hrp.AssemblyAngularVelocity = hrp.AssemblyAngularVelocity * math.exp(-18 * dt)
end

function RunwaySession.ApplyLittleElfChestStandingWaitOrientation(humanoid: Humanoid, hrp: BasePart, forward: Vector3)
	RunwaySession.RestoreRunwayHumanoidLocomotionFromScriptedMode(humanoid)
	local fwdStand: Vector3
	local chestFwdRef = Refs.chestSlideFwdH
	if chestFwdRef == nil or chestFwdRef.Magnitude < 1e-4 then
		fwdStand = Vector3.new(forward.X, 0, forward.Z)
		if fwdStand.Magnitude < 1e-4 then
			fwdStand = Vector3.new(0, 0, -1)
		else
			fwdStand = fwdStand.Unit
		end
	else
		fwdStand = chestFwdRef.Unit
	end
	RunwaySession.SnapCharacterHrpToGround(humanoid, hrp, fwdStand)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	humanoid:Move(Vector3.zero, false)
end

function RunwaySession.EnterLittleElfChestRewardWaitPose(humanoid: Humanoid, hrp: BasePart)
	Refs.chestBounceActive = false
	Refs.chestRewardWaitPose = true
	Refs.chestHitSequenceActive = false
	RunwaySession.DestroyRunwayGravityForce()
	local forwardReward = NormalizeRunwayForward(localState.runwayForward)
	RunwaySession.ApplyLittleElfChestStandingWaitOrientation(humanoid, hrp, forwardReward)
end

function RunwaySession.TryForceReportFinalAfterChestExit()
	if localState.finalSent == true then
		return
	end
	if not NetMsg.JumpRunwayRemotesExist() then
		return
	end
	local _, _humanoidFinal, hrpFinal = RunwaySession.GetCharacterParts()
	if hrpFinal == nil then
		return
	end
	local forwardFinal = NormalizeRunwayForward(localState.runwayForward)
	local origin = localState.runwayOrigin
	local finalAlong = if origin ~= nil then (hrpFinal.Position - origin):Dot(forwardFinal) else 0
	NetMsg.FireRequestJumpRunwayInput({
		kind = Kind.Final,
		finalAlong = finalAlong,
		clientClock = os.clock(),
		clientPhase = Ph.RunEnded,
	})
	localState.finalSent = true
end

function RunwaySession.ApplyDeferredTerminalServerPayloadAfterChest()
	local deferred = Refs.deferredTerminalServerPayload
	if deferred == nil then
		return
	end
	Refs.deferredTerminalServerPayload = nil
	RunwaySession.ApplyServerPayload(deferred)
end

function RunwaySession.ScheduleChestExitFinalReportAfterDelay()
	Refs.chestPostOpenTeleportDelayToken += 1
	local token = Refs.chestPostOpenTeleportDelayToken
	local delaySec = cfg.RUNWAY_CHEST_POST_OPEN_TELEPORT_DELAY_SEC
	if typeof(delaySec) ~= "number" or delaySec ~= delaySec or delaySec < 0 then
		delaySec = 0.5
	end
	task.delay(delaySec, function()
		if Refs.chestPostOpenTeleportDelayToken ~= token then
			return
		end
		if Refs.chestPostRewardExitCleanup ~= true then
			return
		end
		RunwaySession.TryForceReportFinalAfterChestExit()
		RunwaySession.ApplyDeferredTerminalServerPayloadAfterChest()
	end)
end

function RunwaySession.FinishLittleElfChestRunwayExit()
	Refs.chestPostRewardExitCleanup = true
	local forwardExit = Refs.chestSlideFwdH or NormalizeRunwayForward(localState.runwayForward)
	if forwardExit.Magnitude < 1e-4 then
		forwardExit = Vector3.new(0, 0, -1)
	else
		forwardExit = Vector3.new(forwardExit.X, 0, forwardExit.Z).Unit
	end
	local _, hDelay, hrpDelay = RunwaySession.GetCharacterParts()
	RunwaySession.DestroyRunwayGravityForce()
	if hDelay and hrpDelay then
		RunwaySession.SnapCharacterHrpToGround(hDelay, hrpDelay, forwardExit)
		hrpDelay.AssemblyLinearVelocity = Vector3.zero
		hrpDelay.AssemblyAngularVelocity = Vector3.zero
		RunwaySession.RestoreRunwayHumanoidLocomotionFromScriptedMode(hDelay)
		RunwaySession.ClearFinalLandingSlideModuleLocals()
		RunwaySession.RestoreRunwayHumanoidPoseAfterGameplay(hDelay, hrpDelay)
		RunwaySession.ApplyExpectedWalkSpeedAfterRunway(hDelay)
		RunwaySession.SlideTraceScheduleDestroyAfterRunwayEnd()
	end
	localState.phase = Ph.RunEnded
	localState.groundedStableTime = 0
	if localState.controlsDisabled then
		RunwaySession.SetControlsEnabled(true)
	end
	RunwaySession.ClearLittleElfChestRefs()
	RunwaySession.ScheduleChestExitFinalReportAfterDelay()
end

function RunwaySession.IsPlayerNearLittleElfChest(hrp: BasePart, chestModel: Model, fwdH: Vector3): boolean
	if Refs.chestReadyForHit ~= true or Refs.chestLandedOnGround ~= true then
		return false
	end
	local landClock = Refs.chestLandClock
	if landClock == nil or os.clock() - landClock < CHEST_HIT_MIN_SETTLE_AFTER_LAND_SEC then
		return false
	end
	local chestPos = chestModel:GetPivot().Position
	local groundCf = Refs.chestGroundOpenCFrame
	if groundCf ~= nil then
		if math.abs(chestPos.Y - groundCf.Position.Y) > 1.5 then
			return false
		end
	end
	local toChest = Vector3.new(chestPos.X - hrp.Position.X, 0, chestPos.Z - hrp.Position.Z)
	if toChest.Magnitude > CHEST_HIT_HORIZONTAL_MAX_DIST_STUDS then
		return false
	end
	-- 须在宝箱前方或已贴到（沿跑道轴投影为正）
	return toChest:Dot(fwdH) >= -3
end

function RunwaySession.ProcessLittleElfChestHit(chestModel: Model, fwdH: Vector3, chestConfigId: number)
	if Refs.chestRunwayAwaitingExit == true then
		return
	end
	if Refs.chestLandedOnGround ~= true then
		return
	end
	local _, humanoidT, hrpT = RunwaySession.GetCharacterParts()
	if hrpT == nil or humanoidT == nil then
		return
	end
	if not RunwaySession.IsPlayerNearLittleElfChest(hrpT, chestModel, fwdH) then
		return
	end

	local slideFwdForOpen = Refs.chestSlideFwdH or fwdH
	if slideFwdForOpen.Magnitude < 1e-4 then
		slideFwdForOpen = fwdH
	end
	local chestPos = chestModel:GetPivot().Position
	local openCFrame = RunwaySession.BuildLittleElfChestOpenCFrame(chestPos, slideFwdForOpen, chestModel)
	Refs.chestGroundOpenCFrame = openCFrame

	Refs.chestRunwayAwaitingExit = true
	Refs.chestBounceActive = true
	Refs.chestHitSequenceActive = true
	Refs.chestOpenCFrame = openCFrame
	Refs.chestPickedConfigId = chestConfigId
	Refs.chestPickedBrainrotId = nil
	Refs.chestPendingReward = nil
	Refs.chestRewardPresentationStarted = false

	if Refs.chestSpawnedConnList then
		for _, conn in ipairs(Refs.chestSpawnedConnList) do
			conn:Disconnect()
		end
		Refs.chestSpawnedConnList = nil
	end
	chestModel:PivotTo(openCFrame)
	Refs.chestReadyForHit = false

	localState.slideEndClock = math.huge

	RunwaySession.EnsurePlatformStandForFinalLandSlide(humanoidT)
	local bounceFwd = Refs.chestSlideFwdH or fwdH
	if bounceFwd.Magnitude < 1e-4 then
		bounceFwd = fwdH
	end
	bounceFwd = bounceFwd.Unit
	local bounceSpeed = cfg.RUNWAY_CHEST_BOUNCE_BACK_SPEED
	if typeof(bounceSpeed) ~= "number" or bounceSpeed ~= bounceSpeed or bounceSpeed < 0 then
		bounceSpeed = 12
	end
	Refs.chestBounceAlongSpeed = bounceSpeed
	hrpT.AssemblyLinearVelocity = bounceFwd * (-bounceSpeed)
	hrpT.AssemblyAngularVelocity = Vector3.zero

	local bounceSec = cfg.RUNWAY_CHEST_BOUNCE_DELAY_SEC
	if typeof(bounceSec) ~= "number" or bounceSec ~= bounceSec or bounceSec < 0.05 then
		bounceSec = 0.5
	end
	task.delay(bounceSec, function()
		RunwaySession.EndChestProneBounceAndWaitForReward()
	end)

	NetMsg.FireRequestJumpRunwayLittleElfChestReward(chestConfigId)
	task.spawn(RunwaySession.TryPresentLittleElfChestReward)
end

function RunwaySession.TryLittleElfChestProximityHit(hrp: BasePart)
	if Refs.chestReadyForHit ~= true or Refs.chestRunwayAwaitingExit == true then
		return
	end
	local chestModel = Refs.chestSpawnedModel
	if chestModel == nil or chestModel.Parent == nil then
		return
	end
	local slideFwd: Vector3
	local chestFwdRef = Refs.chestSlideFwdH
	if chestFwdRef == nil or chestFwdRef.Magnitude < 1e-4 then
		slideFwd = Vector3.new(0, 0, -1)
	else
		slideFwd = chestFwdRef.Unit
	end
	if not RunwaySession.IsPlayerNearLittleElfChest(hrp, chestModel, slideFwd) then
		return
	end
	local chestConfigId = if Refs.chestDynamicConfigId ~= nil then Refs.chestDynamicConfigId else cfg.RUNWAY_CHEST_CONFIG_ID
	RunwaySession.ProcessLittleElfChestHit(chestModel, slideFwd, chestConfigId)
end

function RunwaySession.SpawnLittleElfChestAtPosition(fwdH: Vector3, spawnPos: Vector3, fallDuration: number)
	if Refs.chestSpawnedForThisRun == true then
		return
	end
	if actualChests == nil then
		warn("[RunwaySession] LittleElfChests folder missing under ReplicatedStorage.Models")
		return
	end
	local chestConfigId = if Refs.chestDynamicConfigId ~= nil then Refs.chestDynamicConfigId else cfg.RUNWAY_CHEST_CONFIG_ID
	local chestConfig = GameConfig.LittleElfChestIdMap[chestConfigId]
	if not chestConfig then
		return
	end
	local template = GameConfig.FindResourceTemplateByResourceName(actualChests, chestConfig.resourceName)
	if not template then
		return
	end

	Refs.chestSpawnedForThisRun = true
	Refs.chestReadyForHit = false
	Refs.chestLandedOnGround = false
	Refs.chestLandClock = nil

	local chestModel = GameConfig.CloneTemplateAsModel(template)
	chestModel.Name = "RunwayLittleElfChest"

	local dropHeight = CHEST_FALL_MAX_HEIGHT_STUDS
	local airPos = spawnPos + Vector3.new(0, dropHeight, 0)
	chestModel:PivotTo(CFrame.new(airPos))

	local touchPartList: { BasePart } = {}
	for _, part in ipairs(chestModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = true
			part.CanTouch = false
			part.Massless = true
			table.insert(touchPartList, part)
		end
	end

	chestModel.Parent = workspace
	Refs.chestSpawnedModel = chestModel

	local function OnChestTouched(hit: BasePart)
		if Refs.chestReadyForHit ~= true or Refs.chestRunwayAwaitingExit == true then
			return
		end
		if not hit or not hit.Parent then
			return
		end
		local hitCharacter = hit:FindFirstAncestorOfClass("Model")
		if hitCharacter ~= localPlayer.Character then
			return
		end
		RunwaySession.ProcessLittleElfChestHit(chestModel, fwdH, chestConfigId)
	end

	local function EnableChestHit()
		if not chestModel or not chestModel.Parent then
			return
		end
		local touchConns: { RBXScriptConnection } = {}
		for _, touchPart in ipairs(touchPartList) do
			touchPart.CanTouch = true
			table.insert(touchConns, touchPart.Touched:Connect(OnChestTouched))
		end
		Refs.chestSpawnedConnList = touchConns
		Refs.chestReadyForHit = true
	end

	coroutine.wrap(function()
		local tweenService = game:GetService("TweenService")
		local driver = Instance.new("NumberValue")
		driver.Value = dropHeight
		local conn = driver:GetPropertyChangedSignal("Value"):Connect(function()
			if chestModel and chestModel.Parent then
				local currentPos = spawnPos + Vector3.new(0, driver.Value, 0)
				chestModel:PivotTo(CFrame.new(currentPos))
			end
		end)
		local tween = tweenService:Create(
			driver,
			TweenInfo.new(fallDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Value = 0 }
		)
		tween:Play()
		tween.Completed:Wait()
		conn:Disconnect()
		driver:Destroy()
		if chestModel and chestModel.Parent then
			local landPos = RunwaySession.ResolveLittleElfChestGroundPosition(spawnPos, chestModel)
			local landCf = RunwaySession.BuildLittleElfChestOpenCFrame(landPos, fwdH, chestModel)
			chestModel:PivotTo(landCf)
			Refs.chestLandedOnGround = true
			Refs.chestGroundOpenCFrame = landCf
			Refs.chestLandClock = os.clock()
			EnableChestHit()
		end
	end)()
end

function RunwaySession.ResolveLittleElfChestGroundPosition(targetPos: Vector3, chestModel: Model?): Vector3
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList: { Instance } = {}
	if chestModel then
		table.insert(filterList, chestModel)
	end
	local character = localPlayer.Character
	if character then
		table.insert(filterList, character)
	end
	if #filterList > 0 then
		rayParams.FilterDescendantsInstances = filterList
	end
	local rayOrigin = Vector3.new(targetPos.X, targetPos.Y + 12, targetPos.Z)
	local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -40, 0), rayParams)
	if rayResult then
		return Vector3.new(targetPos.X, rayResult.Position.Y + CHEST_GROUND_RAISE_STUDS, targetPos.Z)
	end
	return targetPos
end

function RunwaySession.OnLittleElfChestRewardReceived(brainrotId: number, chestConfigId: number, chestLevel: number)
	if Refs.chestPickedConfigId ~= chestConfigId then
		return
	end
	if Refs.chestPendingReward ~= nil then
		return
	end
	Refs.chestPickedBrainrotId = brainrotId
	Refs.chestPendingReward = {
		brainrotId = brainrotId,
		chestConfigId = chestConfigId,
		chestLevel = chestLevel,
	}
	RunwaySession.TryPresentLittleElfChestReward()
end
function RunwaySession.UpdateTick(dt: number)
	local nowClock = os.clock()
	RunwaySession.ProcessJumpWindowTimeout(nowClock)
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		if localState.controlsDisabled then
			RunwaySession.SetControlsEnabled(true)
		end
		local _, humanoidIdle, _ = RunwaySession.GetCharacterParts()
		RunwaySession.ApplyExpectedWalkSpeedAfterRunway(humanoidIdle)
		RunwaySession.ApplyRunwayHumanoidJumpState(humanoidIdle, false)
		Refs.prevGroundedHeartbeat = true
		return
	end
	if not localState.controlsDisabled then
		RunwaySession.SetControlsEnabled(false)
	end
	local _, humanoid, hrp = RunwaySession.GetCharacterParts()
	if humanoid == nil or hrp == nil then
		return
	end
	RunwaySession.SyncRunwayHumanoidWalkSpeed(humanoid, nowClock)
	RunwaySession.ApplyRunwayHumanoidJumpState(humanoid, true)
	RunwaySession.PollBeginLineOverlapForJumpWindow()
	RunwaySession.UpdateRunwayRingTransform(humanoid, hrp)
	RunwaySession.UpdateDistanceRecorder(humanoid, hrp)
	if localState.phase == Ph.Airborne and localState.takeoffCount == cfg.N_TOTAL_JUMPS then
		if localState.dashHeld and localState.fuel > 0 then
			localState.fuel = math.max(0, localState.fuel - cfg.DASH_FUEL_DRAIN_PER_SEC * dt)
		end
	end
	RunwaySession.ProcessAirborneLandingHeartbeat(humanoid)
	RunwaySession.ProcessFinalLandingSubPhaseTransition(humanoid, hrp, nowClock)
	RunwayNetBridge.SendSampleIfDue(
		NetMsg,
		cfg,
		Kind,
		localState,
		hrp,
		humanoid,
		nowClock,
		NormalizeRunwayForward,
		ComputeRunwayHorizontalAlongSpeed,
		RunwaySession.IsRunwayScriptedGrounded
	)
	if not RunwaySession.IsLittleElfChestRunwayFlowActive() and Refs.chestPostRewardExitCleanup ~= true then
		RunwayNetBridge.MaybeReportFinal(
			NetMsg,
			cfg,
			Ph,
			Kind,
			localState,
			humanoid,
			hrp,
			localState.runwayForward,
			dt,
			nowClock,
			HorizontalVelocity,
			RunwaySession.IsRunwayScriptedGrounded
		)
	end
	if
		localState.phase == Ph.Slide
		and localState.finalLandSubPhase == 2
		and localState.runwaySlideKind == SlideKindFinalLanding
	then
		RunwaySession.TryLittleElfChestProximityHit(hrp)
	end
	if localState.phase == Ph.Slide and nowClock >= localState.slideEndClock then
		if localState.runwaySlideKind == SlideKindFinalLanding then
			if not RunwaySession.IsRunwayScriptedGrounded(humanoid) then
				return
			end
			if RunwaySession.ShouldBlockFinalLandingSlideEndForChest() then
				return
			end
			RunwaySession.RestorePlatformStandAfterFinalLand(humanoid)
			RunwaySession.ClearFinalLandingSlideModuleLocals()
			RunwaySession.RestoreHumanoidAutoRotateAfterFinalPitch(humanoid)
			RunwaySession.RestoreRunwayHumanoidPoseAfterGameplay(humanoid, hrp)
			RunwaySession.SlideTraceScheduleDestroyAfterRunwayEnd()
		elseif localState.runwaySlideKind == SlideKindMiss then
			RunwaySession.RestorePlatformStandAfterFinalLand(humanoid)
			RunwaySession.ClearFinalLandingSlideModuleLocals()
			RunwaySession.RestoreHumanoidAutoRotateAfterFinalPitch(humanoid)
			RunwaySession.RestoreRunwayHumanoidPoseAfterGameplay(humanoid, hrp)
			-- 发送 Abort 让服务端清理 run 状态
			if NetMsg.JumpRunwayRemotesExist() and not localState.finalSent and Refs.missAbortSentForThisRun ~= true then
				Refs.missAbortSentForThisRun = true
				NetMsg.FireRequestJumpRunwayInput({
					kind = Kind.Abort,
					clientClock = os.clock(),
					clientPhase = localState.phase,
				})
				localState.finalSent = true
			end
			RunwaySession.SlideTraceDestroy()
			RunwaySession.RestoreRunwayHumanoidLocomotionFromScriptedMode(humanoid)
			RunwaySession.ClearRunwayFlyingHumanoid(humanoid)
			if localState.controlsDisabled then
				RunwaySession.SetControlsEnabled(true)
			end
			RunwaySession.ResetLocalRunToIdle()
			return
		end
	end
end

function RunwaySession.ApplyServerPayload(payload: NetMsg.JumpRunwayStatePayload)
	if RunwaySession.IsLittleElfChestRunwayFlowActive() then
		if payload.phase == Ph.ScoreLocked and payload.finalScore ~= nil then
			localState.finalScore = payload.finalScore
		end
		if payload.phase == Ph.ScoreLocked or payload.phase == Ph.Cleaning or payload.phase == Ph.Idle then
			Refs.deferredTerminalServerPayload = payload
		end
		return
	end
	if payload.phase == Ph.Idle or payload.phase == Ph.Cleaning then
		if localState.phase == Ph.Idle then
			-- 已经清理过了，忽略服务端延迟消息
			return
		end
		-- 如果当前已经是新 Run 的活跃阶段（非 RunEnded），说明玩家已重新开始，
		-- 忽略服务端延迟通知，避免误杀新 Run
		if RunwaySession.IsRunwayActivePhase(localState.phase) and localState.phase ~= Ph.RunEnded then
			return
		end
		RunwaySession.ResetLocalRunToIdle()
		if payload.runwayForward.Magnitude > 1e-4 then
			localState.runwayForward = NormalizeRunwayForward(payload.runwayForward)
		end
		if payload.runwayOrigin ~= nil then
			localState.runwayOrigin = payload.runwayOrigin
		end
		return
	end
	if payload.phase == Ph.ScoreLocked and payload.finalScore ~= nil then
		localState.finalScore = payload.finalScore
		RunwaySession.ClearJumpBoostIfNeeded(Ph.ScoreLocked)
		local _, humScore, hrpScore = RunwaySession.GetCharacterParts()
		RunwaySession.RestoreRunwayHumanoidLocomotionFromScriptedMode(humScore)
		RunwaySession.RestoreRunwayHumanoidPoseAfterGameplay(humScore, hrpScore)
		RunwaySession.ApplyExpectedWalkSpeedAfterRunway(humScore)
		if localState.controlsDisabled then
			RunwaySession.SetControlsEnabled(true)
		end
	end
end

function RunwaySession.NetReportJump()
	if not NetMsg.JumpRunwayRemotesExist() then
		return
	end
	NetMsg.FireRequestJumpRunwayInput({
		kind = Kind.Input,
		jumpPressed = true,
		dashHeld = localState.dashHeld,
		clientClock = os.clock(),
		clientPhase = localState.phase,
	})
end

function RunwaySession.NetReportDashIfChanged()
	if not NetMsg.JumpRunwayRemotesExist() then
		return
	end
	if localState.dashHeld == localState.lastReportedDashHeld then
		return
	end
	localState.lastReportedDashHeld = localState.dashHeld
	NetMsg.FireRequestJumpRunwayInput({
		kind = Kind.Input,
		dashHeld = localState.dashHeld,
		clientClock = os.clock(),
		clientPhase = localState.phase,
	})
end

function RunwaySession.JumpComputeJumpWindowRatingTier(deltaT: number): number
	local w = cfg.T_WINDOW
	if w <= 1e-6 then
		return 1
	end
	local frac = deltaT / w
	local perfectMax = cfg.JUMP_WINDOW_RATING_PERFECT_MAX_FRAC
	local okMax = cfg.JUMP_WINDOW_RATING_OK_MAX_FRAC
	if frac < perfectMax then
		return 1
	elseif frac < okMax then
		return 2
	else
		return 3
	end
end

function RunwaySession.JumpSpeedBonusForTier(tier: number): number
	local t = math.clamp(math.floor(tier), 1, 3)
	local map = cfg.JUMP_WINDOW_RATING_SPEED_BONUS_BY_TIER :: { [number]: number }
	local ratio = map[t]
	if typeof(ratio) ~= "number" or ratio ~= ratio then
		return 0
	end
	ratio = math.max(0, ratio)
	local baseSpd = GetJumpPowerBaseSpeed()
	return baseSpd * ratio
end

function RunwaySession.JumpComputeSessionVy(): (number, number, number)
	local gBase = workspace.Gravity
	if gBase < 1e-3 then
		gBase = 196.2
	end
	local gGrav = gBase * cfg.RUNWAY_SESSION_EFFECTIVE_GRAVITY_SCALE
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	local jumpPower = if localPlayerInfo then localPlayerInfo.jumpPower else GameConfig.JumpPowerDefaultValue
	local vy = jumpPower * cfg.JUMP_VERTICAL_RATIO
	return jumpPower, vy, gGrav
end

function RunwaySession.JumpPerpImpulseTerm(hrp: BasePart, forward: Vector3): Vector3
	local horiz = HorizontalVelocity(hrp.AssemblyLinearVelocity)
	local alongH = horiz:Dot(forward)
	local perpH = horiz - forward * alongH
	return perpH * 0.35
end

function RunwaySession.JumpGrantDashFuelIfOnFinalSegment()
	if localState.takeoffCount == cfg.N_TOTAL_JUMPS then
		localState.fuel = RunwaySession.GetExpectedPlayerMaxFuel()
		localState.finalDashAlongExtra = 0
	end
end

function RunwaySession.JumpApplyRatingForTakeoff(
	humanoid: Humanoid,
	nowClock: number,
	inAuto: boolean,
	inLineWindow: boolean,
	inChainWindow: boolean
)
	if inAuto then
		local tierFirst = math.clamp(math.floor(cfg.JUMP_FIRST_TAKEOFF_BEFORE_LINE_SPEED_RATING_TIER), 1, 3)
		localState.jumpSpeedCumulativeRatingBonus += RunwaySession.JumpSpeedBonusForTier(tierFirst)
		localState.ratingTier = tierFirst
		JumpRunWayFrame.ShowRatingTier(tierFirst)
	elseif inLineWindow then
		local tierLine: number
		if RunwaySession.IsRunwayScriptedGrounded(humanoid) and localState.tHudStart ~= nil then
			tierLine = RunwaySession.JumpComputeJumpWindowRatingTier(nowClock - (localState.tHudStart :: number))
		else
			tierLine = 2
		end
		localState.jumpSpeedCumulativeRatingBonus += RunwaySession.JumpSpeedBonusForTier(tierLine)
		localState.ratingTier = tierLine
		JumpRunWayFrame.ShowRatingTier(tierLine)
	elseif inChainWindow then
		local tierChain: number
		if localState.tHudStart ~= nil then
			tierChain = RunwaySession.JumpComputeJumpWindowRatingTier(nowClock - (localState.tHudStart :: number))
		else
			tierChain = 2
		end
		localState.jumpSpeedCumulativeRatingBonus += RunwaySession.JumpSpeedBonusForTier(tierChain)
		localState.ratingTier = tierChain
		JumpRunWayFrame.ShowRatingTier(tierChain)
	end
end

function RunwaySession.JumpAdvancePhaseAfterImpulse(inAuto: boolean, inLineWindow: boolean, inChainWindow: boolean)
	if inAuto then
		if not localState.passedBeginLineOnce then
			localState.jumpedBeforeBeginLine = true
		end
		localState.takeoffCount += 1
		RunwaySession.JumpGrantDashFuelIfOnFinalSegment()
		localState.phase = Ph.Airborne
	elseif inLineWindow then
		localState.lineWindowConsumed = true
		localState.lineJumpWindowExpireAt = nil
		localState.tHudStart = nil
		localState.chainJumpWindowAwaitingGround = false
		localState.takeoffCount += 1
		RunwaySession.JumpGrantDashFuelIfOnFinalSegment()
		localState.phase = Ph.Airborne
	elseif inChainWindow then
		localState.takeoffCount += 1
		RunwaySession.JumpGrantDashFuelIfOnFinalSegment()
		localState.predictJumpWindowUntil = nil
		localState.tHudStart = nil
		localState.chainJumpWindowAwaitingGround = false
		localState.phase = Ph.Airborne
	end
end

function RunwaySession.JumpApplyTakeoff(
	humanoid: Humanoid,
	hrp: BasePart,
	nowClock: number,
	inAuto: boolean,
	inLineWindow: boolean,
	inChainWindow: boolean
): boolean
	local horizontalBaseSpeed, vy, gGrav = RunwaySession.JumpComputeSessionVy()
	local forward = NormalizeRunwayForward(localState.runwayForward)
	local perpTerm = RunwaySession.JumpPerpImpulseTerm(hrp, forward)
	-- 先累加本次起跳评级 bonus，再取冲量 max（与顶点内 max→min 一致）；终局叠冲刺在 UpdateAutoRunVelocity。
	RunwaySession.JumpApplyRatingForTakeoff(humanoid, nowClock, inAuto, inLineWindow, inChainWindow)
	local impulseSeg = math.clamp(localState.takeoffCount + 1, 1, cfg.N_TOTAL_JUMPS)
	local forwardSpd = select(
		1,
		GameConfig.GetJumpRunwayJumpSpeedLimitsForSegment(impulseSeg, localState.jumpSpeedCumulativeRatingBonus, horizontalBaseSpeed)
	)
	-- 竖直速度 = 水平速度基准对应比例 + bonus 对应比例
	local bonusPart = forwardSpd - horizontalBaseSpeed
	vy += bonusPart * cfg.JUMP_VERTICAL_RATIO
	localState.jumpBoostVy = vy
	localState.jumpBoostUntilClock = nowClock + cfg.RUNWAY_JUMP_BOOST_HOLD_SEC
	hrp.AssemblyLinearVelocity = forward * forwardSpd + Vector3.new(0, vy, 0) + perpTerm
	print(
		string.format(
			"[JumpApplyTakeoff] takeoffCount=%d forwardSpd=%.1f vy=%.1f bonusPart=%.1f",
			localState.takeoffCount,
			forwardSpd,
			vy,
			bonusPart
		)
	)
	local tApex = if gGrav > 1e-6 then vy / gGrav else 0.25
	localState.jumpHorizLerpStartClock = nowClock
	localState.jumpHorizLerpDuration = math.max(0.01, tApex)
	RunwaySession.JumpAdvancePhaseAfterImpulse(inAuto, inLineWindow, inChainWindow)
	-- 冲量起跳后首帧 Raycast/Humanoid 仍常判贴地或 preland；若 prev* 为 false 会被当成「着地/快触地上升沿」
	-- 立刻武装链式 T_WINDOW，约 1s 超时进 Slide。置 true 表示上升沿已消费，仅真实再落地时才武装。
	localState.prevLocalGroundedForLand = true
	localState.prevPreLand = true
	localState.prevJumpWindowRayBand = true
	localState.firstGroundedInWindowClock = nil
	Refs.prevGroundedHeartbeat = true
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end)
	if localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
		Refs.finalTakeoffForceFreefallUntilClock = nowClock + math.max(0.12, cfg.RUNWAY_JUMP_BOOST_HOLD_SEC)
		RunwaySession.DestroyRunwayRing()
		RunwaySession.EnsureDistanceRecorderFromTemplate(humanoid, hrp)
	end
	return true
end

function RunwaySession.JumpTry(): boolean
	local nowClock = os.clock()
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		return false
	end
	local inAuto = localState.phase == Ph.AutoRun
	local inLineWindow = localState.phase == Ph.JumpWindow
		and not localState.lineWindowConsumed
		and (
			localState.tHudStart == nil
			or (
				localState.lineJumpWindowExpireAt ~= nil
				and nowClock < (localState.lineJumpWindowExpireAt :: number)
			)
		)
	local inChainWindow = localState.phase == Ph.Airborne
		and localState.takeoffCount >= 1
		and localState.takeoffCount < cfg.N_TOTAL_JUMPS
		and (
			localState.chainJumpWindowAwaitingGround
			or (
				localState.predictJumpWindowUntil ~= nil
				and nowClock < (localState.predictJumpWindowUntil :: number)
			)
		)
	if not inAuto and not inLineWindow and not inChainWindow then
		return false
	end
	if inAuto and localState.passedBeginLineOnce then
		return false
	end
	local _character, humanoid, hrp = RunwaySession.GetCharacterParts()
	if humanoid == nil or hrp == nil then
		return false
	end
	if (inLineWindow or inChainWindow) and not inAuto then
		if not RunwaySession.IsRunwayScriptedGrounded(humanoid) and not RunwaySession.IsRunwayJumpWindowRayBandOk(humanoid) then
			return false
		end
	end
	local okDist, distFeet = RunwaySession.RaycastFeet(humanoid)
	if okDist then
		local deltaT = if localState.tHudStart ~= nil then nowClock - (localState.tHudStart :: number) else -1
		print(
			`[RunwaySession] JumpTry takeoffCount={localState.takeoffCount} dist={string.format("%.2f", distFeet)}`
				.. ` deltaT={string.format("%.3f", deltaT)} phase={localState.phase}`
		)
	end
	return RunwaySession.JumpApplyTakeoff(humanoid, hrp, nowClock, inAuto, inLineWindow, inChainWindow)
end

function RunwaySession.OnJumpRunwayState(payload: NetMsg.JumpRunwayStatePayload)
	RunwaySession.ApplyServerPayload(payload)
	RunwaySession.HudRefresh()
end

function RunwaySession.OnInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if
		input.KeyCode == Enum.KeyCode.Space
		or input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		if RunwaySession.IsRunwayActivePhase(localState.phase) then
			if RunwaySession.JumpTry() then
				RunwaySession.NetReportJump()
			end
		end
	end
	-- 冲刺：键盘空格（与起跳同键；终局空由 takeoffCount/fuel 决定是否叠加速）
	if input.KeyCode == Enum.KeyCode.Space and RunwaySession.IsRunwayActivePhase(localState.phase) then
		localState.dashHeld = true
		RunwaySession.NetReportDashIfChanged()
	end
end

function RunwaySession.OnInputEnded(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space then
		localState.dashHeld = false
		RunwaySession.NetReportDashIfChanged()
	end
end

function RunwaySession.AlignCharacterYawToRunwayForward(hrp: BasePart, forward: Vector3)
	local f = NormalizeRunwayForward(forward)
	if f.Magnitude < 1e-4 then
		return
	end
	local pos = hrp.Position
	hrp.CFrame = CFrame.lookAt(pos, pos + f, Vector3.yAxis)
	hrp.AssemblyAngularVelocity = Vector3.zero
end

function RunwaySession.GetStartTriggerGroundRaycastExclude(startTrigger: Part): Instance
	local parent = startTrigger.Parent
	if parent ~= nil and parent ~= workspace then
		return parent
	end
	return startTrigger
end

function RunwaySession.SnapLocalPlayerToRunwayGroundIfAirborne(startTrigger: Part, humanoid: Humanoid, hrp: BasePart): boolean
	-- 仅「脚本贴地且脚线足够近」才省略吸附；否则先归位再开局，否则 TryStartLocalRun 里 RaycastFeet 得到的 preLandRayBaselineStuds 会带着起跳高度
	local feetOk, feetDist = RunwaySession.RaycastFeet(humanoid)
	local floorCap = cfg.RUNWAY_START_TRIGGER_SKIP_SNAP_MAX_FEET_DIST_STUDS
	local hipMult = cfg.RUNWAY_START_TRIGGER_SKIP_SNAP_HIP_HEIGHT_MULT
	local hipForCap = humanoid.HipHeight
	if typeof(hipForCap) ~= "number" or hipForCap ~= hipForCap or hipForCap < 0.1 then
		hipForCap = 2
	end
	local floorN = if typeof(floorCap) == "number" and floorCap == floorCap then floorCap else 4.25
	local multN = if typeof(hipMult) == "number" and hipMult == hipMult and hipMult > 0 then hipMult else 2.25
	local skipFeetCap = math.max(floorN, hipForCap * multN + cfg.RUNWAY_GROUND_RAY_ORIGIN_Y)
	local canSkipSnap = RunwaySession.IsRunwayScriptedGrounded(humanoid)
		and feetOk
		and feetDist <= skipFeetCap
	if canSkipSnap then
		return true
	end
	local rayExclude = RunwaySession.GetStartTriggerGroundRaycastExclude(startTrigger)
	local triggerTopY = startTrigger.Position.Y + startTrigger.Size.Y * 0.5
	local probeY = math.max(hrp.Position.Y, triggerTopY)
		+ cfg.RUNWAY_GROUND_RAY_ORIGIN_Y
		+ cfg.RUNWAY_START_TRIGGER_GROUND_SNAP_PROBE_EXTRA_Y
	local xzHrp = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
	local okGround, groundY = RunwaySession.RaycastRunwayGroundYAtWorldXZ(xzHrp, humanoid, probeY, rayExclude)
	if not okGround then
		local xzTrig = Vector3.new(startTrigger.Position.X, 0, startTrigger.Position.Z)
		okGround, groundY = RunwaySession.RaycastRunwayGroundYAtWorldXZ(xzTrig, humanoid, probeY, rayExclude)
	end
	if not okGround then
		return false
	end
	local hip = humanoid.HipHeight
	if typeof(hip) ~= "number" or hip ~= hip or hip < 0.1 then
		hip = 2
	end
	local targetRootY = groundY + hip
	local deltaY = targetRootY - hrp.Position.Y
	local character = humanoid.Parent
	if character ~= nil and character:IsA("Model") and math.abs(deltaY) > 1e-4 then
		character:PivotTo(character:GetPivot() + Vector3.new(0, deltaY, 0))
		for _, inst in character:GetDescendants() do
			if inst:IsA("BasePart") then
				local bp = inst :: BasePart
				bp.AssemblyLinearVelocity = Vector3.zero
				bp.AssemblyAngularVelocity = Vector3.zero
			end
		end
	else
		local p = hrp.Position
		hrp.Position = Vector3.new(p.X, targetRootY, p.Z)
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end
	return true
end

function RunwaySession.TryStartLocalRun(startTrigger: Part): boolean
	if RunwaySession.ShouldBlockJumpRunwayStartAtStartTrigger() then
		return false
	end
	if RunwaySession.IsRunwayActivePhase(localState.phase) then
		return false
	end
	local nowClock = os.clock()
	local lastCd = localPlayer:GetAttribute("JumpRunwayCooldownUntil") :: number?
	if type(lastCd) == "number" and nowClock < lastCd then
		return false
	end
	local character, humanoid, hrp = RunwaySession.GetCharacterParts()
	if character == nil or humanoid == nil or hrp == nil or humanoid.Health <= 0 then
		return false
	end
	local closeEnough = RunwaySession.IsPlayerCloseEnoughToStartTrigger(startTrigger, hrp)
	if not closeEnough then
		return false
	end
	Refs.startTriggerStartArmed = false
	RunwaySession.DestroyDistanceRecorder()
	RunwaySession.SlideTraceDestroy()
	local forward = NormalizeRunwayForward(startTrigger.CFrame.RightVector)
	local origin = startTrigger.Position
	RunwaySession.AlignCharacterYawToRunwayForward(hrp, forward)
	localState.scriptedGroundHrpYBaseline = hrp.Position.Y
	local alongBaseline = (hrp.Position - origin):Dot(forward)
	localState.runwayForward = forward
	localState.runwayOrigin = origin
	localState.alongBaseline = alongBaseline
	localState.phase = Ph.AutoRun
	localState.takeoffCount = 0
	localState.jumpSpeedCumulativeRatingBonus = 0
	localState.fuel = 0
	localState.ratingTier = nil
	localState.finalScore = nil
	localState.finalSent = false
	localState.groundedStableTime = 0
	localState.jumpBoostVy = nil
	localState.jumpBoostUntilClock = 0
	localState.predictJumpWindowUntil = nil
	localState.firstGroundedInWindowClock = nil
	localState.tHudStart = nil
	localState.lineJumpWindowExpireAt = nil
	localState.lineWindowConsumed = false
	localState.chainJumpWindowAwaitingGround = false
	localState.passedBeginLineOnce = false
	localState.jumpedBeforeBeginLine = false
	localState.slideStartClock = 0
	localState.slideEndClock = 0
	localState.runwaySlideKind = SlideKindStandard
	localState.finalLandSubPhase = 1
	localState.finalLandPronePhaseStartClock = 0
	localState.finalLandPhaseAPopCount = 0
	localState.finalLandProneSlideAlongSpeedStart = 0
	localState.finalLandTumbleImpulseApplied = false
	localState.finalLandTumblePredAirTimeSec = 0
	localState.finalLandTumbleAirAccumSec = 0
	localState.finalLandTumbleLeftGround = false
	localState.finalLandTumbleUseAirClock = false
	localState.finalLandLockedTumbleAlong = 0
	localState.finalLandTumblePrevPopVy = 0
	localState.finalLandTumbleRollAngleRad = 0
	localState.finalLandProneBStage = 0
	localState.finalLandPronePrefallStartClock = 0
	localState.finalLandProneSlideAlongStart = nil
	RunwaySession.ClearJumpHorizontalLerp()
	localState.finalDashAlongExtra = 0
	Refs.finalPitchSmoothedExtraDeg = 0
	localState.lastSampleSendClock = 0
	localState.lastSampleAlong = alongBaseline
	RunwayNetBridge.FireStartSession(NetMsg, Kind, forward, origin, alongBaseline)
	localState.lastReportedDashHeld = localState.dashHeld
	RunwaySession.ApplyRunwayHumanoidJumpState(humanoid, true)
	humanoid.WalkSpeed = cfg.FIRST_TAKEOFF_AUTORUN_SPEED
	local fwdH = Vector3.new(forward.X, 0, forward.Z)
	if fwdH.Magnitude > 1e-4 then
		fwdH = fwdH.Unit
	else
		fwdH = Vector3.new(0, 0, -1)
	end
	hrp.AssemblyLinearVelocity = fwdH * cfg.FIRST_TAKEOFF_AUTORUN_SPEED
	RunwaySession.EnsureRunwayGravityForce(hrp)
	RunwaySession.UpdateRunwayGravityForce(hrp)
	RunwaySession.EnsureRunwayRing()
	RunwaySession.UpdateRunwayRingTransform(humanoid, hrp)
	local okBaseline, baselineDist = RunwaySession.RaycastFeet(humanoid)
	localState.preLandRayBaselineStuds = if okBaseline then baselineDist else nil
	localState.prevLocalGroundedForLand = RunwaySession.IsRunwayScriptedGrounded(humanoid)
	localState.prevPreLand = RunwaySession.IsRunwayPreLanding(humanoid)
	localState.prevJumpWindowRayBand = RunwaySession.IsRunwayJumpWindowRayBandOk(humanoid)
	Refs.finalTakeoffForceFreefallUntilClock = 0
	Refs.prevGroundedHeartbeat = localState.prevLocalGroundedForLand
	RunwayCameraController.Enable(workspace, cfg, hrp, localState.runwayForward, NormalizeRunwayForward)
	RunwaySession.EnsureJumpRunwayRocketBackpack(character)
	JumpRunWayFrame.EnsureSession()
	return true
end

function RunwaySession.BindSceneTriggers()
	if Refs.startTriggerConn then
		Refs.startTriggerConn:Disconnect()
		Refs.startTriggerConn = nil
	end
	if Refs.beginLineConn then
		Refs.beginLineConn:Disconnect()
		Refs.beginLineConn = nil
	end
	local startTrigger, beginLine = RunwaySession.ResolveSceneParts()
	if startTrigger then
		Refs.startTriggerConn = startTrigger.Touched:Connect(function(hit)
			local ch = hit:FindFirstAncestorOfClass("Model")
			if ch ~= nil and ch == localPlayer.Character then
				local _character, humanoid, hrp = RunwaySession.GetCharacterParts()
				if humanoid == nil or hrp == nil then
					return
				end
				if RunwaySession.IsLocalPlayerCarryingRunwayLittleElfChest(ch) then
					RunwaySession.TryDeliverLittleElfChestAtStartTrigger(startTrigger)
					return
				end
				if Refs.chestCarryReturnActive == true then
					return
				end
				if Refs.startTriggerStartArmed ~= true then
					return
				end
				if RunwaySession.IsRunwayActivePhase(localState.phase) then
					if localState.phase == Ph.RunEnded then
						-- RunEnded 状态下允许重新开始新 run：先清理再启动
						RunwaySession.ResetLocalRunToIdle()
					else
						return
					end
				end
				if not RunwaySession.SnapLocalPlayerToRunwayGroundIfAirborne(startTrigger, humanoid, hrp) then
					return
				end
				RunwaySession.TryStartLocalRun(startTrigger)
			end
		end)
	end
	if beginLine then
		Refs.beginLineConn = beginLine.Touched:Connect(RunwaySession.OnBeginLineTouched)
	end
end

function RunwaySession.OnHeartbeat(dt: number)
	RunwaySession.UpdateTick(dt)
	RunwaySession.UpdateStartTriggerReentryState()
	RunwaySession.NetReportDashIfChanged()
	RunwayFxController.UpdateHeartbeat(RunwaySession.UpdateJetpackFlameDashFx, os.clock())
	RunwayUiController.Refresh(
		RunwaySession.HudRefresh
	)
end

function RunwaySession.OnCameraRenderStep(dt: number)
	RunwayCameraController.Update(
		workspace,
		cfg,
		dt,
		localState.phase,
		RunwaySession.IsRunwayActivePhase,
		RunwaySession.GetCharacterParts,
		localState.runwayForward,
		NormalizeRunwayForward
	)
end

function RunwaySession.BindInput()
	userInputService.InputBegan:Connect(RunwaySession.OnInputBegan)
	userInputService.InputEnded:Connect(RunwaySession.OnInputEnded)
end

function RunwaySession.BindRunwayExitOnCharacterDeathOrRemove()
	local function resetIfRunwayActive()
		if RunwaySession.IsRunwayActivePhase(localState.phase) or Refs.chestCarryReturnActive == true then
			RunwaySession.ResetLocalRunToIdle()
		end
	end
	localPlayer.CharacterRemoving:Connect(function(_character: Model)
		resetIfRunwayActive()
	end)
	local function bindHumanoidDied(character: Model)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid == nil then
			humanoid = character:WaitForChild("Humanoid", 15) :: Humanoid?
		end
		if humanoid == nil then
			return
		end
		humanoid.Died:Connect(resetIfRunwayActive)
	end
	if localPlayer.Character then
		bindHumanoidDied(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(bindHumanoidDied)
end

function RunwaySession.RefreshHudUi()
	RunwaySession.HudRefresh()
end

function RunwaySession.Init()
	if Refs.initDone then
		return
	end
	Refs.initDone = true
	RunwaySession.BindRunwayExitOnCharacterDeathOrRemove()
	NetMsg.ConnectNotifyJumpRunwayLittleElfChestReward(function(brainrotId: number, chestConfigId: number, chestLevel: number)
		RunwaySession.OnLittleElfChestRewardReceived(brainrotId, chestConfigId, chestLevel)
	end)
	task.defer(function()
		localPlayer:WaitForChild("PlayerGui", 60)
		RunwaySession.BindInput()
		RunwaySession.BindSceneTriggers()
		task.delay(2, RunwaySession.BindSceneTriggers)
	end)
	runService.PreSimulation:Connect(RunwaySession.OnPreSimulation)
	runService.PostSimulation:Connect(RunwaySession.OnPostSimulationLocomotion)
	runService.Heartbeat:Connect(RunwaySession.OnHeartbeat)
	runService:BindToRenderStep(
		RunwayCameraRenderStepName,
		Enum.RenderPriority.Camera.Value + 1,
		RunwaySession.OnCameraRenderStep
	)
	runService:BindToRenderStep(
		RunwayFinalTiltRenderStepName,
		Enum.RenderPriority.Last.Value,
		RunwaySession.OnJumpRunwayFinalTiltRenderStep
	)
end

NetMsg.ConnectNotifyJumpRunwayState(RunwaySession.OnJumpRunwayState)

return RunwaySession
