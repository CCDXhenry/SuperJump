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
local core = replicatedStorage:WaitForChild("Core")
local coreClientScripts = core:WaitForChild("Scripts"):WaitForChild("Client")
local TranslationTool = require(coreClientScripts:WaitForChild("TranslationTool"))

type RunwayLocalState = RunwayStateStore.RunwayStateStoreShape

local localPlayer = players.LocalPlayer
local cfg = GameConfig.JumpRunway
local CLIENT_DEBUG = cfg.DEBUG == true

local Ph = RunwayConstants.Ph
local Kind = RunwayConstants.Kind
local SlideKindStandard = RunwayConstants.SlideKindStandard
local SlideKindFinalLanding = RunwayConstants.SlideKindFinalLanding
local RunwayCameraRenderStepName = RunwayConstants.RunwayCameraRenderStepName
local RunwayFinalTiltRenderStepName = RunwayConstants.RunwayFinalTiltRenderStepName
local RunwayRingTemplateName = RunwayConstants.RunwayRingTemplateName
local RunwaySlideTraceTemplateName = RunwayConstants.RunwaySlideTraceTemplateName
local RunwaySlideTraceDestroyAfterEndSec = RunwayConstants.RunwaySlideTraceDestroyAfterEndSec

local Refs: {
	screenGui: ScreenGui?,
	phaseLabel: TextLabel?,
	windowLabel: TextLabel?,
	fuelLabel: TextLabel?,
	vyLabel: TextLabel?,
	debugScreenGui: ScreenGui?,
	debugTextLabel: TextLabel?,
	lastJumpDebugReason: string,
	startTriggerActiveInterceptCount: number,
	startTriggerActiveLastInterceptClock: number?,
	finalTakeoffForceFreefallUntilClock: number,
	initDone: boolean,
	jumpStateEnabledBeforeRunway: boolean?,
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
	slideTraceTemplateWarned: boolean,
	slideTraceCachedTemplate: BasePart?,
	slideTraceFollowerPart: BasePart?,
	slideTraceAccumAlong: number,
	slideTracePrevAlongForDelta: number?,
	slideTraceSegmentList: { BasePart? },
	slideTraceDestroyScheduleToken: number,
	prevGroundedHeartbeat: boolean,
} = {
	lastJumpDebugReason = "",
	startTriggerActiveInterceptCount = 0,
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
end

function RunwaySession.HudRefresh()
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		RunwaySession.HudDestroy()
		return
	end
	RunwaySession.HudEnsure()
	local _c, _h, hrp = RunwaySession.GetCharacterParts()
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
			Refs.fuelLabel.Text = string.format("Dash fuel  %.2f", localState.fuel)
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
		GameConfig.GetJumpRunwayJumpSpeedLimitsForSegment(segmentIndex, localState.jumpSpeedCumulativeRatingBonus)
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
		localState.jumpSpeedCumulativeRatingBonus
	)
	local forwardSpeed = defaultMinAlong
	if localState.phase == Ph.AutoRun and localState.takeoffCount == 0 then
		-- 首段自动跑保持恒定前推，避免判地边界抖动时在 0 与目标速之间跳变造成“抽回”体感。
		forwardSpeed = cfg.FIRST_TAKEOFF_AUTORUN_SPEED
	elseif localState.phase == Ph.Airborne and localState.takeoffCount <= cfg.N_TOTAL_JUMPS then
		if RunwaySession.IsRunwayScriptedGrounded(humanoid) then
			local _, minAlongGrounded = GameConfig.GetJumpRunwayJumpSpeedLimitsForSegment(
				math.max(1, localState.takeoffCount),
				localState.jumpSpeedCumulativeRatingBonus
			)
			forwardSpeed = minAlongGrounded
			if localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
				localState.finalDashAlongExtra = 0
			end
		elseif localState.takeoffCount < cfg.N_TOTAL_JUMPS then
			forwardSpeed = RunwaySession.GetJumpHorizontalForwardSpeed(nowClock, localState.takeoffCount)
		else
			local base = RunwaySession.GetJumpHorizontalForwardSpeed(nowClock, localState.takeoffCount)
			local capExtra = math.max(0, cfg.DASH_MAX_SPEED - base)
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
			forwardSpeed = math.min(base + localState.finalDashAlongExtra, cfg.DASH_MAX_SPEED)
			localState.finalDashAlongExtra = math.max(0, forwardSpeed - base)
		end
	end
	hrp.AssemblyLinearVelocity = fwdH * forwardSpeed + Vector3.new(0, vy, 0) + perpH * perpDamp
end

function RunwaySession.ApplyJumpWindowWalkPhysics(humanoid: Humanoid, hrp: BasePart, forward: Vector3)
	local walkSpd = cfg.JUMP_WINDOW_WALK_SPEED
	if humanoid.WalkSpeed ~= walkSpd then
		humanoid.WalkSpeed = walkSpd
	end
	local fh = Vector3.new(forward.X, 0, forward.Z)
	if fh.Magnitude > 1e-4 then
		humanoid:Move(fh.Unit, false)
	end
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
		localState.jumpSpeedCumulativeRatingBonus
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

function RunwaySession.ApplyFinalLandPhaseAPop(hrp: BasePart, fwdH: Vector3, nowClock: number)
	local v = hrp.AssemblyLinearVelocity
	local landingAlong, landingVy = RunwaySession.SampleFinalLandLandingAlongAndVy(hrp, fwdH)
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
		-- 使用子阶段 A 缓存的水平弹跳速度，避免 Physics 状态下实时采样被钳为 0
		local cachedAlong = localState.finalLandLockedTumbleAlong
		if cachedAlong > 0 then
			alongFwd = cachedAlong
		end
		local alongSpdEnter = math.clamp(alongFwd, 0, maxAlongCap)
		localState.finalLandProneSlideAlongSpeedStart = alongSpdEnter
		hrp.AssemblyLinearVelocity = fwdHInit * alongSpdEnter + Vector3.new(0, 0, 0)
		hrp.AssemblyAngularVelocity = Vector3.zero
		localState.finalLandProneSlideAlongStart = RunwaySession.CurrentAlongProgress(hrp)
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
		local brakeK = cfg.RUNWAY_FINAL_LAND_PRONE_SLIDE_BRAKE_EXP
		local newAlong = alongH * math.exp(-brakeK * dt)
		hrp.AssemblyLinearVelocity = fwdH * newAlong + Vector3.new(0, 0, 0) + perpH * perpDamp
		if math.abs(newAlong) < 0.45 and math.abs(v.Y) < 10 and RunwaySession.IsRunwayScriptedGrounded(humanoid) then
			localState.slideEndClock = nowClock
		end
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

function RunwaySession.ApplyFinalLandingRenderOrientation(_humanoid: Humanoid, hrp: BasePart, forward: Vector3, dt: number, _nowClock: number)
	local pos = hrp.Position
	local linVel = hrp.AssemblyLinearVelocity
	if Refs.finalLandTumbleStartHrpCf == nil then
		Refs.finalLandTumbleStartHrpCf = hrp.CFrame
	end
	if localState.finalLandSubPhase == 2 then
		local proneOffset = cfg.RUNWAY_FINAL_LAND_PRONE_GROUND_OFFSET
		if typeof(proneOffset) ~= "number" or proneOffset ~= proneOffset then
			proneOffset = 0
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
	local _dbgOk1, _dbgEncoded1 = pcall(function()
		return game:GetService("HttpService"):JSONEncode({
			sessionId = "6f8203",
			runId = "runway_pullback_probe_3",
			hypothesisId = "C1",
			location = "RunwaySession:EnterSlidePhase",
			message = "client_enter_slide_phase",
			data = {
				phaseBefore = phaseBefore,
				slideKind = slideKind,
				takeoffCount = localState.takeoffCount,
				nowClock = nowClock,
			},
			timestamp = DateTime.now().UnixTimestampMillis,
		})
	end)
	if _dbgOk1 then
		-- #region agent log
		warn("[DBG6f8203] " .. (_dbgEncoded1 :: string))
		-- #endregion
	end
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
	localState.fuel = 0
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
		RunwaySession.EnsurePlatformStandForFinalLandSlide(humanoidOpt)
		if humanoidOpt ~= nil then
			humanoidOpt:ChangeState(Enum.HumanoidStateType.Physics)
		end
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

function RunwaySession.ApplyRunwayLocomotionAnimation(humanoid: Humanoid, forward: Vector3, nowClock: number)
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		humanoid:Move(Vector3.zero, false)
		return
	end
	if localState.phase == Ph.Slide then
		if localState.runwaySlideKind == SlideKindFinalLanding then
			if humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			end
			humanoid:Move(Vector3.zero, false)
			return
		end
		if humanoid:GetState() ~= Enum.HumanoidStateType.FallingDown then
			humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
		end
		humanoid:Move(Vector3.zero, false)
		return
	end
	if localState.phase == Ph.Airborne and localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
		local forceFreefall = os.clock() < Refs.finalTakeoffForceFreefallUntilClock or not RunwaySession.IsRunwayScriptedGrounded(humanoid)
		if forceFreefall then
			local st = humanoid:GetState()
			if st ~= Enum.HumanoidStateType.Freefall and st ~= Enum.HumanoidStateType.Jumping then
				humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			end
		end
		humanoid:Move(Vector3.zero, false)
		return
	end
	local effPhysics = RunwaySession.GetEffectivePhysicsPhase(humanoid, nowClock)
	if effPhysics == Ph.JumpWindow then
		local walkSpd = cfg.JUMP_WINDOW_WALK_SPEED
		if humanoid.WalkSpeed ~= walkSpd then
			humanoid.WalkSpeed = walkSpd
		end
		local fh = Vector3.new(forward.X, 0, forward.Z)
		if fh.Magnitude > 1e-4 then
			humanoid:Move(fh.Unit, false)
		end
		return
	end
	local chainJumpHud = localState.phase == Ph.Airborne and RunwaySession.ChainHudActive(nowClock)
	local scriptedGrounded = RunwaySession.IsRunwayScriptedGrounded(humanoid)
	local shouldForceLocomotion = false
	if localState.phase == Ph.AutoRun then
		-- 首段自动跑不再因瞬时离地强切 Freefall；速度由 UpdateAutoRunVelocity 统一驱动。
		shouldForceLocomotion = true
	elseif localState.phase == Ph.JumpWindow then
		-- BeginLine 起跳窗整段保持 Humanoid 默认 Running（HumanoidStateType.Running），避免离地/判地抖动时掉 Idle。
		shouldForceLocomotion = true
	elseif chainJumpHud then
		-- 链式起跳窗仅在贴地时保持 Running，避免空中与 Freefall 高频互抢导致状态翻转抖动。
		shouldForceLocomotion = scriptedGrounded
	end
	if shouldForceLocomotion then
		if humanoid:GetState() ~= Enum.HumanoidStateType.Running then
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end
		-- 使用世界前向 Move，避免对象空间 + relativeToCamera=true 在相机/朝向变化时引入反向扰动。
		local f = Vector3.new(forward.X, 0, forward.Z)
		if f.Magnitude > 1e-4 then
			humanoid:Move(f.Unit, false)
		else
			humanoid:Move(Vector3.new(0, 0, -1), false)
		end
	end
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
	local origin = root.Position + Vector3.new(0, cfg.RUNWAY_GROUND_RAY_ORIGIN_Y, 0)
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
		or st == Enum.HumanoidStateType.Physics
		or st == Enum.HumanoidStateType.GettingUp
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
		and localState.runwaySlideKind == SlideKindFinalLanding
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
	if RunwaySession.IsRunwayScriptedGrounded(humanoid) then
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
	local extraDeg = 0
	if localState.dashHeld and localState.fuel > 0 then
		extraDeg = cfg.RUNWAY_FINAL_DASH_EXTRA_PITCH_DEG
	end
	local totalDeg = cfg.RUNWAY_FINAL_PITCH_DEG + extraDeg
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
		local outerTemplate = if modelsFolder
			then modelsFolder:FindFirstChild(cfg.RUNWAY_JETPACK_OUTER_MODEL_NAME)
			else nil
		local innerTemplate = if outerTemplate and outerTemplate:IsA("Model")
			then outerTemplate:FindFirstChild(cfg.RUNWAY_JETPACK_INNER_MODEL_NAME)
			else nil
		local middleTemplate = if innerTemplate and innerTemplate:IsA("Model")
			then innerTemplate:FindFirstChild(cfg.RUNWAY_JETPACK_MIDDLE_NAME)
			else nil
		if modelsFolder ~= nil and outerTemplate ~= nil and outerTemplate:IsA("Model") and innerTemplate ~= nil and innerTemplate:IsA("Model") and middleTemplate ~= nil and middleTemplate:IsA("BasePart") then
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
				"[RunwaySession] ReplicatedStorage.Models.Jetpack template missing or invalid hierarchy; using fallback Part."
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

function RunwaySession.DebugDestroy()
	if Refs.debugScreenGui then
		Refs.debugScreenGui:Destroy()
		Refs.debugScreenGui = nil
		Refs.debugTextLabel = nil
	end
end

function RunwaySession.DebugEnsure()
	if not CLIENT_DEBUG then
		return
	end
	if Refs.debugScreenGui then
		return
	end
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "JumpRunwayDebugHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 95
	gui.Parent = playerGui
	Refs.debugScreenGui = gui
	local t = Instance.new("TextLabel")
	t.Name = "DebugText"
	t.BackgroundTransparency = 0.25
	t.BackgroundColor3 = Color3.fromRGB(10, 24, 40)
	t.TextColor3 = Color3.fromRGB(220, 245, 255)
	t.TextSize = 14
	t.Font = Enum.Font.Code
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.Size = UDim2.new(0.42, 0, 0.42, 0)
	t.Position = UDim2.new(0.02, 0, 0.28, 0)
	t.Parent = gui
	Refs.debugTextLabel = t
end

function RunwaySession.RestoreRunwayHumanoidPoseAfterGameplay(humanoid: Humanoid?, hrp: BasePart?)
	if humanoid == nil or humanoid.Parent == nil then
		return
	end
	humanoid.PlatformStand = false
	if hrp ~= nil and hrp.Parent ~= nil then
		hrp.AssemblyAngularVelocity = Vector3.zero
		local f = NormalizeRunwayForward(localState.runwayForward)
		if f.Magnitude > 1e-4 then
			local pos = hrp.Position
			hrp.CFrame = CFrame.lookAt(pos, pos + f, Vector3.yAxis)
		end
	end
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end)
end

function RunwaySession.ResetLocalRunToIdle()
	local _, humanoid, hrp = RunwaySession.GetCharacterParts()
	local _dbgOk2, _dbgEncoded2 = pcall(function()
		return game:GetService("HttpService"):JSONEncode({
			sessionId = "6f8203",
			runId = "runway_pullback_probe_3",
			hypothesisId = "C3",
			location = "RunwaySession:ResetLocalRunToIdle",
			message = "client_reset_to_idle",
			data = {
				phaseBefore = localState.phase,
				hrpY = if hrp ~= nil then hrp.Position.Y else -1,
				hrpSpeed = if hrp ~= nil then hrp.AssemblyLinearVelocity.Magnitude else -1,
			},
			timestamp = DateTime.now().UnixTimestampMillis,
		})
	end)
	if _dbgOk2 then
		-- #region agent log
		warn("[DBG6f8203] " .. (_dbgEncoded2 :: string))
		-- #endregion
	end
	-- 先同步清理资源和状态（避免异步延迟导致新一局启动后资源混乱）
	RunwaySession.DestroyJumpRunwayRocketBackpack()
	RunwayCameraController.Disable(workspace, GetCharacterParts)
	RunwaySession.DestroyRunwayGravityForce()
	RunwayStateStore.ResetForIdle(localState, Ph, SlideKindStandard)
	RunwaySession.ClearJumpHorizontalLerp()
	lastJumpDebugReason = ""
	RunwaySession.DestroyRunwayRing()
	RunwaySession.DestroyDistanceRecorder()
	RunwaySession.SlideTraceScheduleDestroyAfterRunwayEnd()
	RunwayUiController.Destroy(RunwaySession.HudDestroy, RunwaySession.DebugDestroy)
	JumpRunWayFrame.EndSession()
	-- Humanoid 状态恢复延迟到下一帧，避免 Physics 引擎竞争条件
	task.defer(function()
		RunwaySession.RestorePlatformStandAfterFinalLand(humanoid)
		RunwaySession.ClearFinalLandingSlideModuleLocals()
		RunwaySession.RestoreHumanoidAutoRotateAfterFinalPitch(humanoid)
		RunwaySession.RestoreRunwayHumanoidPoseAfterGameplay(humanoid, hrp)
		RunwaySession.ClearRunwayFlyingHumanoid(humanoid)
		RunwaySession.ApplyExpectedWalkSpeedAfterRunway(humanoid)
		RunwaySession.ApplyRunwayHumanoidJumpState(humanoid, false)
		if localState.controlsDisabled then
			RunwaySession.SetControlsEnabled(true)
		end
	end)
end

function RunwaySession.DebugRefreshOverlay()
	if not CLIENT_DEBUG then
		return
	end
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		RunwaySession.DebugDestroy()
		return
	end
	RunwaySession.DebugEnsure()
	if Refs.debugTextLabel == nil then
		return
	end
	local _character, humanoid, hrp = RunwaySession.GetCharacterParts()
	local scrGnd = "n/a"
	local pre = "n/a"
	if humanoid ~= nil then
		scrGnd = tostring(RunwaySession.IsRunwayScriptedGrounded(humanoid))
		pre = tostring(RunwaySession.IsRunwayPreLanding(humanoid))
	end
	local preLandDbg = "n/a"
	if humanoid ~= nil then
		local okFeet, dFeet = RunwaySession.RaycastFeet(humanoid)
		preLandDbg = string.format(
			"preBase=%s feetD=%s",
			tostring(localState.preLandRayBaselineStuds),
			if okFeet then string.format("%.2f", dFeet) else "n/a"
		)
	end
	local velLine = "vel: n/a"
	if hrp ~= nil then
		local v = hrp.AssemblyLinearVelocity
		local fwd = NormalizeRunwayForward(localState.runwayForward)
		local alongSp = ComputeRunwayHorizontalAlongSpeed(v, fwd)
		velLine = string.format(
			"|v|=%.1f  horiz=%.1f  along=%.1f",
			v.Magnitude,
			HorizontalVelocity(v).Magnitude,
			alongSp
		)
	end
	Refs.debugTextLabel.Text = table.concat({
		string.format("phase=%d  ctrlOff=%s", localState.phase, tostring(localState.controlsDisabled)),
		velLine,
		string.format("scrGnd=%s  preLand=%s", scrGnd, pre),
		preLandDbg,
		string.format("lineWin=%s  passedLine=%s  jumpedBeforeLine=%s", tostring(localState.lineJumpWindowExpireAt), tostring(localState.passedBeginLineOnce), tostring(localState.jumpedBeforeBeginLine)),
		string.format("jump: %s", if Refs.lastJumpDebugReason == "" then "(none yet)" else Refs.lastJumpDebugReason),
	}, "\n")
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
	if chainSeg and localState.chainJumpWindowAwaitingGround and localState.tHudStart == nil then
		localState.tHudStart = nowClock
		localState.predictJumpWindowUntil = nowClock + cfg.T_WINDOW
		localState.chainJumpWindowAwaitingGround = false
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
			else
				localState.chainJumpWindowAwaitingGround = true
				localState.predictJumpWindowUntil = nil
				localState.tHudStart = nil
			end
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
			RunwaySession.EnterSlidePhase(nowClock, SlideKindStandard, nil)
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
	if localState.phase == Ph.Airborne and RunwaySession.ChainHudActive(nowClock) then
		if RunwaySession.WindowDriftPhysicsActive(humanoid, nowClock) then
			return Ph.JumpWindow
		end
		return Ph.AutoRun
	end
	return localState.phase
end

function RunwaySession.SyncRunwayHumanoidWalkSpeed(humanoid: Humanoid, nowClock: number)
	-- 终局 Slide 子阶段 A（翻滚阶段）：WalkSpeed 设为 0，防止 Humanoid 走路动画干扰翻滚
	if localState.phase == Ph.Slide and localState.runwaySlideKind == SlideKindFinalLanding and localState.finalLandSubPhase == 1 then
		if humanoid.WalkSpeed ~= 0 then
			humanoid.WalkSpeed = 0
		end
		return
	end
	local eff = RunwaySession.GetEffectivePhysicsPhase(humanoid, nowClock)
	if eff == Ph.JumpWindow then
		local w = cfg.JUMP_WINDOW_WALK_SPEED
		if humanoid.WalkSpeed ~= w then
			humanoid.WalkSpeed = w
		end
	else
		-- 非 JumpWindow 阶段避免 WalkSpeed=0 触发地面刹停，与跑道速度写入争抢导致“抽回”。
		local w = math.max(cfg.FIRST_TAKEOFF_AUTORUN_SPEED, cfg.JUMP_WINDOW_WALK_SPEED)
		if humanoid.WalkSpeed ~= w then
			humanoid.WalkSpeed = w
		end
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
		RunwaySession.ApplyJumpWindowWalkPhysics(humanoid, hrp, forward)
	elseif localState.phase == Ph.Airborne then
		RunwaySession.UpdateAutoRunVelocity(hrp, forward, dt, humanoid)
		if localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
			RunwaySession.UpdateDashVerticalOnly(hrp, dt)
		end
	elseif localState.phase == Ph.Slide then
		if localState.runwaySlideKind == SlideKindFinalLanding then
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
	RunwaySession.EnsureRunwayGravityForce(hrp)
	RunwaySession.UpdateRunwayGravityForce(hrp)
end

function RunwaySession.OnPreSimulation(dt: number)
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
	RunwaySession.ApplyRunwayLocomotionAnimation(humanoid, forward, os.clock())
	local isFinalLandingSlide = localState.phase == Ph.Slide and localState.runwaySlideKind == SlideKindFinalLanding
	if
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
	local nowClock = os.clock()
	if localState.phase == Ph.Airborne and localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
		RunwaySession.EnsureHumanoidAutoRotateOffForFinalPitch(humanoid)
		RunwaySession.ApplyRunwayFinalBodyPitch(hrp, forward, dt)
	elseif localState.phase == Ph.Slide and localState.runwaySlideKind == SlideKindFinalLanding then
		RunwaySession.EnsureHumanoidAutoRotateOffForFinalPitch(humanoid)
		RunwaySession.ApplyFinalLandingRenderOrientation(humanoid, hrp, forward, dt, nowClock)
		RunwaySession.SlideTraceUpdate(humanoid, hrp)
	else
		return
	end
	RunwaySession.EnsureRunwayGravityForce(hrp)
	RunwaySession.UpdateRunwayGravityForce(hrp)
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
		RunwaySession.EnterSlidePhase(nowClock, SlideKindStandard, nil)
	end
end

-- 在 Heartbeat 用 grounded 边沿处理 AutoRun 回贴（takeoffCount==0）
function RunwaySession.ProcessAirborneLandingHeartbeat(humanoid: Humanoid)
	if localState.phase ~= Ph.Airborne then
		prevGroundedHeartbeat = RunwaySession.IsRunwayScriptedGrounded(humanoid)
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
			RunwaySession.EnterSlidePhase(os.clock(), SlideKindFinalLanding, humanoid)
		elseif localState.takeoffCount >= 1 then
			-- 链式：已在 UpdateLocalJumpWindowPrediction 处理
		else
			localState.phase = Ph.AutoRun
			RunwaySession.ClearJumpHorizontalLerp()
			localState.predictJumpWindowUntil = nil
			localState.tHudStart = nil
			localState.chainJumpWindowAwaitingGround = false
		end
		prevGroundedHeartbeat = g
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
			prevGroundedHeartbeat = true
			return
		end
	end
	prevGroundedHeartbeat = g
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
		prevGroundedHeartbeat = true
		return
	end
	if not localState.controlsDisabled then
		RunwaySession.SetControlsEnabled(false)
	end
	local _character, humanoid, hrp = RunwaySession.GetCharacterParts()
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
	if localState.phase == Ph.Slide and nowClock >= localState.slideEndClock and RunwaySession.IsRunwayScriptedGrounded(humanoid) then
		if localState.runwaySlideKind == SlideKindFinalLanding then
			RunwaySession.RestorePlatformStandAfterFinalLand(humanoid)
			RunwaySession.ClearFinalLandingSlideModuleLocals()
			RunwaySession.RestoreHumanoidAutoRotateAfterFinalPitch(humanoid)
			RunwaySession.RestoreRunwayHumanoidPoseAfterGameplay(humanoid, hrp)
			RunwaySession.SlideTraceScheduleDestroyAfterRunwayEnd()
		end
		localState.phase = Ph.RunEnded
		localState.groundedStableTime = 0
	end
end

function RunwaySession.ApplyServerPayload(payload: NetMsg.JumpRunwayStatePayload)
	if payload.phase == Ph.ScoreLocked or payload.phase == Ph.Cleaning or payload.phase == Ph.Idle then
		local _cDbg, _hDbg, hrpDbg = RunwaySession.GetCharacterParts()
		local _dbgOk3, _dbgEncoded3 = pcall(function()
			return game:GetService("HttpService"):JSONEncode({
				sessionId = "6f8203",
				runId = "runway_pullback_probe_3",
				hypothesisId = "C4",
				location = "RunwaySession:ApplyServerPayload",
				message = "client_receive_terminal_phase",
				data = {
					payloadPhase = payload.phase,
					localPhaseBeforeApply = localState.phase,
					finalScore = payload.finalScore,
					hrpY = if hrpDbg ~= nil then hrpDbg.Position.Y else -1,
				},
				timestamp = DateTime.now().UnixTimestampMillis,
			})
		end)
		if _dbgOk3 then
			-- #region agent log
			warn("[DBG6f8203] " .. (_dbgEncoded3 :: string))
			-- #endregion
		end
	end
	if payload.phase == Ph.Idle or payload.phase == Ph.Cleaning then
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
		RunwaySession.RestorePlatformStandAfterFinalLand(humScore)
		RunwaySession.RestoreHumanoidAutoRotateAfterFinalPitch(humScore)
		RunwaySession.RestoreRunwayHumanoidPoseAfterGameplay(humScore, hrpScore)
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
	local b = map[t]
	if typeof(b) ~= "number" or b ~= b then
		return 0
	end
	return math.max(0, b)
end

function RunwaySession.JumpComputeSessionVy(): (number, number)
	local gBase = workspace.Gravity
	if gBase < 1e-3 then
		gBase = 196.2
	end
	local gGrav = gBase * cfg.RUNWAY_SESSION_EFFECTIVE_GRAVITY_SCALE
	local apex = cfg.RUNWAY_JUMP_APEX_STUDS
	local vy = math.sqrt(math.max(0, 2 * gGrav * apex))
	return vy, gGrav
end

function RunwaySession.JumpPerpImpulseTerm(hrp: BasePart, forward: Vector3): Vector3
	local horiz = HorizontalVelocity(hrp.AssemblyLinearVelocity)
	local alongH = horiz:Dot(forward)
	local perpH = horiz - forward * alongH
	return perpH * 0.35
end

function RunwaySession.JumpGrantDashFuelIfOnFinalSegment()
	if localState.takeoffCount == cfg.N_TOTAL_JUMPS then
		localState.fuel = cfg.DASH_FUEL_MAX
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
		if RunwaySession.IsRunwayScriptedGrounded(humanoid) and localState.tHudStart ~= nil then
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
	local vy, gGrav = RunwaySession.JumpComputeSessionVy()
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	local forward = NormalizeRunwayForward(localState.runwayForward)
	local perpTerm = RunwaySession.JumpPerpImpulseTerm(hrp, forward)
	localState.jumpBoostVy = vy
	localState.jumpBoostUntilClock = nowClock + cfg.RUNWAY_JUMP_BOOST_HOLD_SEC
	-- 先累加本次起跳评级 bonus，再取冲量 max（与顶点内 max→min 一致）；终局叠冲刺在 UpdateAutoRunVelocity。
	RunwaySession.JumpApplyRatingForTakeoff(humanoid, nowClock, inAuto, inLineWindow, inChainWindow)
	local impulseSeg = math.clamp(localState.takeoffCount + 1, 1, cfg.N_TOTAL_JUMPS)
	local forwardSpd = select(
		1,
		GameConfig.GetJumpRunwayJumpSpeedLimitsForSegment(impulseSeg, localState.jumpSpeedCumulativeRatingBonus)
	)
	hrp.AssemblyLinearVelocity = forward * forwardSpd + Vector3.new(0, vy, 0) + perpTerm
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
	if CLIENT_DEBUG then
		lastJumpDebugReason = string.format("applied_impulse_vy=%.2f", vy)
	end
	if localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
		finalTakeoffForceFreefallUntilClock = nowClock + math.max(0.12, cfg.RUNWAY_JUMP_BOOST_HOLD_SEC)
		RunwaySession.DestroyRunwayRing()
		RunwaySession.EnsureDistanceRecorderFromTemplate(humanoid, hrp)
	end
	return true
end

function RunwaySession.JumpTry(): boolean
	local nowClock = os.clock()
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		if CLIENT_DEBUG then
			lastJumpDebugReason = "blocked_not_active_phase"
		end
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
		if CLIENT_DEBUG then
			lastJumpDebugReason = string.format("blocked_phase_%d", localState.phase)
		end
		return false
	end
	if inAuto and localState.passedBeginLineOnce then
		if CLIENT_DEBUG then
			lastJumpDebugReason = "blocked_autorun_after_line_need_window"
		end
		return false
	end
	local _character, humanoid, hrp = RunwaySession.GetCharacterParts()
	if humanoid == nil or hrp == nil then
		if CLIENT_DEBUG then
			lastJumpDebugReason = "blocked_no_character"
		end
		return false
	end
	if (inLineWindow or inChainWindow) and not inAuto then
		if not RunwaySession.IsRunwayScriptedGrounded(humanoid) and not RunwaySession.IsRunwayPreLanding(humanoid) then
			if CLIENT_DEBUG then
				lastJumpDebugReason = "blocked_window_not_grounded"
			end
			return false
		end
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
		elseif CLIENT_DEBUG then
			lastJumpDebugReason = "ignored_input_not_in_runway_phase"
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
	local _dbgOkSnap, _dbgEncodedSnap = pcall(function()
		return game:GetService("HttpService"):JSONEncode({
			sessionId = "6f8203",
			runId = "runway_pullback_probe_3",
			hypothesisId = "C10",
			location = "RunwaySession:SnapLocalPlayerToRunwayGroundIfAirborne",
			message = "start_trigger_snap_applied",
			data = {
				phase = localState.phase,
				deltaY = deltaY,
				feetDist = feetDist,
				skipFeetCap = skipFeetCap,
			},
			timestamp = DateTime.now().UnixTimestampMillis,
		})
	end)
	if _dbgOkSnap then
		-- #region agent log
		warn("[DBG6f8203] " .. (_dbgEncodedSnap :: string))
		-- #endregion
	end
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
	local closeEnough = (hrp.Position - startTrigger.Position).Magnitude < math.max(startTrigger.Size.Magnitude * 2, 24)
	if not closeEnough then
		return false
	end
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
	localState.lastSampleSendClock = 0
	localState.lastSampleAlong = alongBaseline
	RunwayNetBridge.FireStartSession(NetMsg, Kind, forward, origin, alongBaseline)
	localState.lastReportedDashHeld = localState.dashHeld
	RunwaySession.ApplyRunwayHumanoidJumpState(humanoid, true)
	RunwaySession.EnsureRunwayGravityForce(hrp)
	RunwaySession.UpdateRunwayGravityForce(hrp)
	RunwaySession.EnsureRunwayRing()
	RunwaySession.UpdateRunwayRingTransform(humanoid, hrp)
	local okBaseline, baselineDist = RunwaySession.RaycastFeet(humanoid)
	localState.preLandRayBaselineStuds = if okBaseline then baselineDist else nil
	localState.prevLocalGroundedForLand = RunwaySession.IsRunwayScriptedGrounded(humanoid)
	localState.prevPreLand = RunwaySession.IsRunwayPreLanding(humanoid)
	localState.prevJumpWindowRayBand = RunwaySession.IsRunwayJumpWindowRayBandOk(humanoid)
	startTriggerActiveInterceptCount = 0
	Refs.startTriggerActiveLastInterceptClock = nil
	finalTakeoffForceFreefallUntilClock = 0
	prevGroundedHeartbeat = localState.prevLocalGroundedForLand
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
				if RunwaySession.IsRunwayActivePhase(localState.phase) then
					local localStateAny = localState :: any
					local prevLogClock = localStateAny._dbgLastStartTouchActiveLogClock
					local nowLogClock = os.clock()
					local secSinceLastIntercept: number? = nil
					if CLIENT_DEBUG then
						if Refs.startTriggerActiveLastInterceptClock ~= nil then
							secSinceLastIntercept = nowLogClock - (Refs.startTriggerActiveLastInterceptClock :: number)
						end
						Refs.startTriggerActiveLastInterceptClock = nowLogClock
						Refs.startTriggerActiveInterceptCount += 1
					end
					if type(prevLogClock) ~= "number" or (nowLogClock - (prevLogClock :: number)) >= 0.2 then
						localStateAny._dbgLastStartTouchActiveLogClock = nowLogClock
						local debugData: { [string]: any } = {
							phase = localState.phase,
							takeoffCount = localState.takeoffCount,
							hrpY = hrp.Position.Y,
						}
						if CLIENT_DEBUG then
							debugData.touchInterceptCount = Refs.startTriggerActiveInterceptCount
							if secSinceLastIntercept ~= nil then
								debugData.secSinceLastIntercept = secSinceLastIntercept
							end
						end
						local _dbgOkTouch, _dbgEncodedTouch = pcall(function()
							return game:GetService("HttpService"):JSONEncode({
								sessionId = "6f8203",
								runId = "runway_pullback_probe_3",
								hypothesisId = "C11",
								location = "RunwaySession:BindSceneTriggers",
								message = "start_trigger_touched_while_runway_active",
								data = debugData,
								timestamp = DateTime.now().UnixTimestampMillis,
							})
						end)
						if _dbgOkTouch then
							-- #region agent log
							warn("[DBG6f8203] " .. (_dbgEncodedTouch :: string))
							-- #endregion
						end
					end
					return
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
	RunwaySession.NetReportDashIfChanged()
	RunwayFxController.UpdateHeartbeat(RunwaySession.UpdateJetpackFlameDashFx, os.clock())
	RunwayUiController.Refresh(
		RunwaySession.HudRefresh,
		RunwaySession.DebugRefreshOverlay,
		CLIENT_DEBUG
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
		if RunwaySession.IsRunwayActivePhase(localState.phase) then
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

function RunwaySession.RefreshHudUi(clientDebug: boolean)
	RunwaySession.HudRefresh()
	if clientDebug then
		RunwaySession.DebugRefreshOverlay()
	end
end

function RunwaySession.Init()
	if Refs.initDone then
		return
	end
	Refs.initDone = true
	RunwaySession.BindRunwayExitOnCharacterDeathOrRemove()
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
