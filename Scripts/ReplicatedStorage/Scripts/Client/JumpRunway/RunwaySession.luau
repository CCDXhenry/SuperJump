--!strict
-- RunwaySession（客户端权威状态机）
-- ----------------------------------------------------------------------
-- 开局 / BeginLine 触碰、相位机、起跳窗与物理均在客户端；服端仅 Start 登记、Sample 防作弊、Final 锁定成绩。
local RunwaySession = {}

local players = game:GetService("Players")
local contextActionService = game:GetService("ContextActionService")
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
local ClientMsg = require(clientScripts:WaitForChild("ClientMsg"))
local UIManager = require(clientScripts:WaitForChild("UIManager"))
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
local GameSoundManager = require(clientScripts:WaitForChild("GameSoundManager"))
local BrainrotClientManager = require(clientScripts:WaitForChild("BrainrotClientManager"))
local JetpackModelTool = require(clientScripts:WaitForChild("JetpackModelTool"))
local core = replicatedStorage:WaitForChild("Core")
local coreClientScripts = core:WaitForChild("Scripts"):WaitForChild("Client")
local TranslationTool = require(coreClientScripts:WaitForChild("TranslationTool"))

type RunwayLocalState = RunwayStateStore.RunwayStateStoreShape
type ScriptedSlideMotion = {
	startClock: number,
	startPosition: Vector3,
	forward: Vector3,
	startSpeed: number,
	endSpeed: number,
	deceleration: number,
	duration: number,
	totalDistance: number,
	lastDistance: number,
}
type ChestBounceMotion = {
	startClock: number,
	startPosition: Vector3,
	forward: Vector3,
	startSpeed: number,
	deceleration: number,
	duration: number,
	totalDistance: number,
	lastDistance: number,
}
type RunwayDistanceLogSegment = {
	stageName: string,
	startAlong: number,
	endAlong: number,
	deltaAlong: number,
	startClock: number,
	endClock: number,
	duration: number,
	takeoffCount: number,
	ratingTier: number?,
	extra: string?,
}

local localPlayer = players.LocalPlayer
local cfg = GameConfig.JumpRunway

local function GetJumpPowerBaseSpeed(): number
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	return if localPlayerInfo then GameConfig.GetJumpPowerAbility(localPlayerInfo.jumpPower) else GameConfig.JumpPowerDefaultValue
end

local Ph = RunwayConstants.Ph
local Kind = RunwayConstants.Kind
local SlideKindStandard = RunwayConstants.SlideKindStandard
local SlideKindFinalLanding = RunwayConstants.SlideKindFinalLanding
local SlideKindMiss = RunwayConstants.SlideKindMiss
local SlideKindObstacleBounce = RunwayConstants.SlideKindObstacleBounce
local RunwayCameraRenderStepName = RunwayConstants.RunwayCameraRenderStepName
local RunwayFinalTiltRenderStepName = RunwayConstants.RunwayFinalTiltRenderStepName
local RunwayRingTemplateName = RunwayConstants.RunwayRingTemplateName
local RunwaySlideTraceTemplateName = RunwayConstants.RunwaySlideTraceTemplateName
local RunwaySlideTraceDestroyAfterEndSec = RunwayConstants.RunwaySlideTraceDestroyAfterEndSec

local modelsFolder = replicatedStorage:WaitForChild("Models")
local actualChests = modelsFolder:FindFirstChild("LittleElfChests")
local CHEST_GROUND_RAISE_STUDS = 0.2
local ChestHitHorizontalMaxDistStudsDefault = 14
local CHEST_FALL_MAX_HEIGHT_STUDS = 8
local CHEST_FALL_DURATION_SEC = 0.5
local PlayerSlideCollisionGroupName = "PlayerSlideState"
local ChestCollisionGroupName = "Chest"
local JumpRunwayLittleElfChestCarryAttr = "JumpRunwayLittleElfChestCarry"
local StartTriggerCloseEnoughMinStuds = 24
local EndTriggerCloseEnoughMinStuds = 24
local JumpRunwayJetpackModelName = "JumpRunwayJetpackClone"
local JumpRunwayRocketBackpackPartName = "JumpRunwayRocketBackpack"
local JumpRunwayJetpackServerCreatedAttr = "JumpRunwayJetpackServerCreated"
local StartTriggerRearmOutsideMinSec = 0.2
local BestDistanceWallDestroyDelaySec = 3
local BestDistanceWallLockedZ = 670.8
local BestDistanceWallTextXMinNorm = 0.05
local BestDistanceWallTextXMaxNorm = 0.95
local BestDistanceWallTextYMinNorm = 0.05
local BestDistanceWallTextYMaxNorm = 0.95
local ObstacleBounceProneSlideBlockMarginStuds = 0.6
local JumpWindowStumblePulseFrequencyHz = 2.4
local JumpWindowStumblePulseStrength = 0.18
local JumpWindowStumbleMinSpeedScale = 0.72
local JumpWindowR15WalkAnimationId = "rbxassetid://507777826"
local JumpWindowR6WalkAnimationId = "rbxassetid://180426354"
local FinalLandPhaseALeftGroundMinVy = 1.5
local RunwayMovementInputSinkActionName = "JumpRunwayMovementInputSink"
local RunwayMovementInputSinkPriority = 10000
local GuideSlowMotionSpeedScale = 0.15
local GuideSlowMotionAnimRenderStepName = "JumpRunwayGuideSlowMotionAnim"
local GuideSlowMotionAnimPriorities: { [Enum.AnimationPriority]: boolean } = {
	[Enum.AnimationPriority.Movement] = true,
	[Enum.AnimationPriority.Core] = true,
}
local guideSlowMotionAnimBaseSpeedMap: { [AnimationTrack]: number } = setmetatable({}, { __mode = "k" })

local function ResolveConfigNumber(rawValue: any, fallbackValue: number): number
	return if typeof(rawValue) == "number" and rawValue == rawValue then rawValue else fallbackValue
end

local function ResolveChestHitHorizontalMaxDistStuds(): number
	return math.max(0, ResolveConfigNumber(cfg.RUNWAY_CHEST_HIT_HORIZONTAL_MAX_DIST_STUDS, ChestHitHorizontalMaxDistStudsDefault))
end

local function ResolveChestHoldDelaySec(rawValue: any, fallbackSec: number): number
	if typeof(rawValue) ~= "number" or rawValue ~= rawValue or rawValue < 0 then
		return fallbackSec
	end
	return rawValue
end

local function ResolveChestFinalRewardHoldSec(): number
	return ResolveChestHoldDelaySec(cfg.RUNWAY_CHEST_FINAL_REWARD_HOLD_SEC, 0.5)
end

local function ResolveChestCarryPresentHoldSec(): number
	return ResolveChestHoldDelaySec(cfg.RUNWAY_CHEST_CARRY_PRESENT_HOLD_SEC, 0.5)
end

local Refs: {
	screenGui: ScreenGui?,
	phaseLabel: TextLabel?,
	windowLabel: TextLabel?,
	fuelLabel: TextLabel?,
	vyLabel: TextLabel?,
	stateLabel: TextLabel?,
	finalTakeoffForceFreefallUntilClock: number,
	initDone: boolean,
	jumpStateEnabledBeforeRunway: boolean?,
	runningStateEnabledBeforeFinalSegment: boolean?,
	flyingStateEnabledBeforeRunway: boolean?,
	jumpWindowWalkAnimTrack: AnimationTrack?,
	jumpWindowWalkAnimId: string?,
	runwayGravityAttachment: Attachment?,
	runwayGravityVectorForce: VectorForce?,
	startTriggerConn: RBXScriptConnection?,
	endTriggerConn: RBXScriptConnection?,
	beginLineConn: RBXScriptConnection?,
	runwayRingPart: Part?,
	ringBaseSizeX: number,
	ringBaseSizeY: number,
	ringBaseSizeZ: number,
	ringLastGroundY: number?,
	ringTrackStroke: UIStroke?,
	ringFixedStroke: UIStroke?,
	ringSmoothedColor: Color3?,
	ringTemplateWarned: boolean,
	runwayDistanceRecorderPart: BasePart?,
	runwayDistanceRecorderText: TextLabel?,
	distanceRecorderLastGroundY: number?,
	distanceRecorderTemplateWarned: boolean,
	runwayDistanceRecorderPeakStuds: number?,
	runwayDistanceRecorderFrozenStuds: number?,
	runwayBestDistanceCommitted: boolean?,
	rocketBackpackPart: BasePart?,
	rocketBackpackFallbackWarned: boolean,
	jetpackVisualRoot: Model?,
	jetpackFlame1Part: BasePart?,
	jetpackFlame2Part: BasePart?,
	jetpackFlame1IdleColor: Color3?,
	jetpackFlame2IdleColor: Color3?,
	jetpackDashParticleEmitters: { ParticleEmitter },
	jetpackTemplateWarned: boolean,
	bestDistanceWallModel: Model?,
	bestDistanceWallPart: BasePart?,
	bestDistanceWallText: TextLabel?,
	bestDistanceWallDistance: number?,
	bestDistanceWallPassed: boolean,
	bestDistanceWallDestroyToken: number,
	autoRotateSavedForFinalPitch: boolean?,
	finalLandTumbleStartHrpCf: CFrame?,
	platformStandSavedBeforeFinalLand: boolean?,
	finalPitchSmoothedExtraDeg: number,
	slideTraceTemplateWarned: boolean,
	slideTraceCachedTemplate: Instance?,
	slideTraceRootInstance: Instance?,
	slideTraceAnchorPart: BasePart?,
	slideTraceTrail: Trail?,
	slideTraceDestroyScheduleToken: number,
	prevGroundedHeartbeat: boolean,
	slideCollisionGroupOriginalMap: { [BasePart]: string },
	chestSpawnedForThisRun: boolean?,
	chestSpawnedModel: Model?,
	chestSpawnedConnList: { RBXScriptConnection }?,
	chestPickedBrainrotId: number?,
	chestPickedVariantId: number?,
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
	chestPendingReward: { brainrotId: number, chestConfigId: number, chestLevel: number, variantId: number }?,
	chestRewardPresentationStarted: boolean?,
	chestBounceMotion: ChestBounceMotion?,
	chestLandClock: number?,
	chestDynamicConfigId: number?,
	chestScheduledSpawnPos: Vector3?,
	chestPredictedPlaceDistance: number?,
	chestBackpackDeliverRequested: boolean?,
	chestCarryReturnActive: boolean?,
	lastRunAlongDistance: number?,
	missAbortSentForThisRun: boolean?,
	startTriggerStartArmed: boolean?,
	startTriggerPlayerWasInsideVolume: boolean?,
	startTriggerOutsideVolumeClock: number?,
	endTriggerPlayerWasInsideVolume: boolean?,
	forwardBlockedStartClock: number?,
	forwardBlockedStartAlong: number?,
	treeHitLastProcessClock: number,
	treeHitBlockedStartClock: number?,
	treeHitBlockedStartAlong: number?,
	obstacleBounceForward: Vector3?,
	lastRunwayTakeoffClock: number?,
	finalLandPhaseADebugNextClock: number,
	slideEndFallbackWarnNextClock: number,
	slideMotion: ScriptedSlideMotion?,
	movementInputSinkBound: boolean,
	distanceLogRunId: number,
	distanceLogStageName: string?,
	distanceLogStageStartAlong: number?,
	distanceLogStageStartClock: number,
	distanceLogStageStartTakeoffCount: number,
	distanceLogStageStartRatingTier: number?,
	distanceLogSegments: { RunwayDistanceLogSegment },
	distanceLogSummaryPrinted: boolean,
	guideSlowMotionActive: boolean,
	guideSlowMotionStepKey: string?,
	guideSlowMotionGuideType: number,
	guideSlowMotionLocallyCompletedStepKeys: { [string]: boolean },
	guideSlowMotionFreezePosition: Vector3?,
	finalJumpGuideSlowMotionApexReady: boolean,
	finalJumpGuideSlowMotionAscentSeen: boolean,
	finalJumpGuideSlowMotionPrevRawVy: number?,
} = {
	finalTakeoffForceFreefallUntilClock = 0,
	initDone = false,
	ringBaseSizeX = 1,
	ringBaseSizeY = 1,
	ringBaseSizeZ = 1,
	ringTemplateWarned = false,
	distanceRecorderTemplateWarned = false,
	runwayDistanceRecorderPeakStuds = 0,
	runwayDistanceRecorderFrozenStuds = nil,
	runwayBestDistanceCommitted = false,
	rocketBackpackFallbackWarned = false,
	jetpackDashParticleEmitters = {},
	jetpackTemplateWarned = false,
	bestDistanceWallModel = nil,
	bestDistanceWallPart = nil,
	bestDistanceWallText = nil,
	bestDistanceWallDistance = nil,
	bestDistanceWallPassed = false,
	bestDistanceWallDestroyToken = 0,
	slideTraceTemplateWarned = false,
	slideTraceDestroyScheduleToken = 0,
	prevGroundedHeartbeat = true,
	slideCollisionGroupOriginalMap = {},
	finalPitchSmoothedExtraDeg = 0,
	chestSpawnedForThisRun = false,
	chestSpawnedModel = nil,
	chestSpawnedConnList = nil,
	chestPickedBrainrotId = nil,
	chestPickedVariantId = nil,
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
	chestBounceMotion = nil,
	chestLandClock = nil,
	chestDynamicConfigId = nil,
	chestScheduledSpawnPos = nil,
	chestPredictedPlaceDistance = nil,
	chestBackpackDeliverRequested = false,
	chestCarryReturnActive = false,
	lastRunAlongDistance = nil,
	startTriggerStartArmed = true,
	startTriggerPlayerWasInsideVolume = false,
	startTriggerOutsideVolumeClock = nil,
	endTriggerPlayerWasInsideVolume = false,
	missAbortSentForThisRun = nil,
	forwardBlockedStartClock = nil,
	forwardBlockedStartAlong = nil,
	treeHitLastProcessClock = -math.huge,
	treeHitBlockedStartClock = nil,
	treeHitBlockedStartAlong = nil,
	obstacleBounceForward = nil,
	lastRunwayTakeoffClock = nil,
	finalLandPhaseADebugNextClock = 0,
	slideEndFallbackWarnNextClock = 0,
	slideMotion = nil,
	movementInputSinkBound = false,
	distanceLogRunId = 0,
	distanceLogStageName = nil,
	distanceLogStageStartAlong = nil,
	distanceLogStageStartClock = 0,
	distanceLogStageStartTakeoffCount = 0,
	distanceLogStageStartRatingTier = nil,
	distanceLogSegments = {},
	distanceLogSummaryPrinted = false,
	guideSlowMotionActive = false,
	guideSlowMotionStepKey = nil,
	guideSlowMotionGuideType = GameConfig.GuideType.None,
	guideSlowMotionLocallyCompletedStepKeys = {},
	guideSlowMotionFreezePosition = nil,
	finalJumpGuideSlowMotionApexReady = false,
	finalJumpGuideSlowMotionAscentSeen = false,
	finalJumpGuideSlowMotionPrevRawVy = nil,
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

function RunwaySession.ResolveEndTrigger(): Part?
	local startPoint = workspace:FindFirstChild("StartPoint")
	local startModel = if startPoint then startPoint:FindFirstChild("StartPointModel") else nil
	return if startModel then startModel:FindFirstChild("EndTrigger") :: Part? else nil
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

function RunwaySession.OnRunwayMovementInputSink(
	_actionName: string,
	_inputState: Enum.UserInputState,
	_inputObject: InputObject
): Enum.ContextActionResult
	if RunwaySession.IsRunwayActivePhase(localState.phase) then
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

function RunwaySession.SetMovementInputSinkEnabled(enabled: boolean)
	if enabled == Refs.movementInputSinkBound then
		return
	end
	if enabled then
		contextActionService:BindActionAtPriority(
			RunwayMovementInputSinkActionName,
			RunwaySession.OnRunwayMovementInputSink,
			false,
			RunwayMovementInputSinkPriority,
			Enum.KeyCode.W,
			Enum.KeyCode.A,
			Enum.KeyCode.S,
			Enum.KeyCode.D,
			Enum.KeyCode.Up,
			Enum.KeyCode.Down,
			Enum.KeyCode.Left,
			Enum.KeyCode.Right,
			Enum.KeyCode.Thumbstick1
		)
		Refs.movementInputSinkBound = true
	else
		contextActionService:UnbindAction(RunwayMovementInputSinkActionName)
		Refs.movementInputSinkBound = false
	end
end

function RunwaySession.SetControlsEnabled(enabled: boolean)
	RunwaySession.SetMovementInputSinkEnabled(not enabled)
	local controls = RunwaySession.GetPlayerControls()
	if enabled == not localState.controlsDisabled then
		return
	end
	if enabled then
		if controls ~= nil then
			pcall(function()
				controls:Enable()
			end)
		end
		localState.controlsDisabled = false
	else
		if controls ~= nil then
			pcall(function()
				controls:Disable()
			end)
		end
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

function RunwaySession.IsDistanceLogEnabled(): boolean
	return cfg.RUNWAY_DISTANCE_LOG_ENABLED == true
end

function RunwaySession.ResetDistanceLog()
	Refs.distanceLogStageName = nil
	Refs.distanceLogStageStartAlong = nil
	Refs.distanceLogStageStartClock = 0
	Refs.distanceLogStageStartTakeoffCount = 0
	Refs.distanceLogStageStartRatingTier = nil
	table.clear(Refs.distanceLogSegments)
	Refs.distanceLogSummaryPrinted = false
	if not RunwaySession.IsDistanceLogEnabled() then
		return
	end
	Refs.distanceLogRunId += 1
end

function RunwaySession.ResolveDistanceLogAlong(hrpOpt: BasePart?): number?
	local hrp = hrpOpt
	if hrp == nil then
		local _, _, hrpNow = RunwaySession.GetCharacterParts()
		hrp = hrpNow
	end
	if hrp == nil then
		return nil
	end
	return RunwaySession.CurrentAlongProgress(hrp)
end

function RunwaySession.StartDistanceLogStage(stageName: string, along: number, nowClock: number)
	if not RunwaySession.IsDistanceLogEnabled() then
		return
	end
	Refs.distanceLogStageName = stageName
	Refs.distanceLogStageStartAlong = along
	Refs.distanceLogStageStartClock = nowClock
	Refs.distanceLogStageStartTakeoffCount = localState.takeoffCount
	Refs.distanceLogStageStartRatingTier = localState.ratingTier
	print(
		string.format(
			"[JumpRunwayDistance] run=%d stage_start stage=%s along=%.2f takeoff=%d jumpPower=%.2f",
			Refs.distanceLogRunId,
			stageName,
			along,
			localState.takeoffCount,
			GetJumpPowerBaseSpeed()
		)
	)
end

function RunwaySession.CloseDistanceLogStage(reason: string, alongOpt: number?, nowClock: number, extra: string?)
	if not RunwaySession.IsDistanceLogEnabled() then
		return
	end
	local stageName = Refs.distanceLogStageName
	local startAlong = Refs.distanceLogStageStartAlong
	if stageName == nil or startAlong == nil then
		return
	end
	local endAlong = alongOpt or startAlong
	local startClock = Refs.distanceLogStageStartClock
	local duration = math.max(0, nowClock - startClock)
	local deltaAlong = endAlong - startAlong
	local segment: RunwayDistanceLogSegment = {
		stageName = stageName,
		startAlong = startAlong,
		endAlong = endAlong,
		deltaAlong = deltaAlong,
		startClock = startClock,
		endClock = nowClock,
		duration = duration,
		takeoffCount = Refs.distanceLogStageStartTakeoffCount,
		ratingTier = Refs.distanceLogStageStartRatingTier,
		extra = extra,
	}
	table.insert(Refs.distanceLogSegments, segment)
	print(
		string.format(
			"[JumpRunwayDistance] run=%d stage_end reason=%s stage=%s start=%.2f end=%.2f delta=%.2f duration=%.2f takeoff=%d rating=%s extra=%s",
			Refs.distanceLogRunId,
			reason,
			stageName,
			startAlong,
			endAlong,
			deltaAlong,
			duration,
			segment.takeoffCount,
			tostring(segment.ratingTier),
			extra or ""
		)
	)
end

function RunwaySession.TransitionDistanceLogStage(stageName: string, reason: string, hrpOpt: BasePart?, extra: string?)
	if not RunwaySession.IsDistanceLogEnabled() then
		return
	end
	local nowClock = os.clock()
	local along = RunwaySession.ResolveDistanceLogAlong(hrpOpt)
	if along == nil then
		return
	end
	if Refs.distanceLogStageName ~= nil then
		RunwaySession.CloseDistanceLogStage(reason, along, nowClock, extra)
	end
	RunwaySession.StartDistanceLogStage(stageName, along, nowClock)
end

function RunwaySession.PrintDistanceLogSummary(reason: string, hrpOpt: BasePart?)
	if not RunwaySession.IsDistanceLogEnabled() then
		return
	end
	if Refs.distanceLogSummaryPrinted then
		return
	end
	if Refs.distanceLogStageName == nil and #Refs.distanceLogSegments == 0 then
		return
	end
	local nowClock = os.clock()
	local finalAlong = RunwaySession.ResolveDistanceLogAlong(hrpOpt)
	if Refs.distanceLogStageName ~= nil then
		RunwaySession.CloseDistanceLogStage(reason, finalAlong, nowClock, "summary")
		Refs.distanceLogStageName = nil
		Refs.distanceLogStageStartAlong = nil
		Refs.distanceLogStageStartRatingTier = nil
	end
	Refs.distanceLogSummaryPrinted = true
	local positiveTotal = 0
	local signedTotal = 0
	for _, segment in Refs.distanceLogSegments do
		signedTotal += segment.deltaAlong
		positiveTotal += math.max(0, segment.deltaAlong)
	end
	print(
		string.format(
			"[JumpRunwayDistance] run=%d summary reason=%s jumpPower=%.2f finalAlong=%s signedTotal=%.2f positiveTotal=%.2f segmentCount=%d",
			Refs.distanceLogRunId,
			reason,
			GetJumpPowerBaseSpeed(),
			if finalAlong ~= nil then string.format("%.2f", finalAlong) else "nil",
			signedTotal,
			positiveTotal,
			#Refs.distanceLogSegments
		)
	)
	for index, segment in Refs.distanceLogSegments do
		print(
			string.format(
				"[JumpRunwayDistance] run=%d summary_segment index=%d stage=%s start=%.2f end=%.2f delta=%.2f duration=%.2f takeoff=%d rating=%s extra=%s",
				Refs.distanceLogRunId,
				index,
				segment.stageName,
				segment.startAlong,
				segment.endAlong,
				segment.deltaAlong,
				segment.duration,
				segment.takeoffCount,
				tostring(segment.ratingTier),
				segment.extra or ""
			)
		)
	end
end

function RunwaySession.ResolveBeginLineAlongFromOrigin(forward: Vector3, origin: Vector3): number?
	local _, beginLine = RunwaySession.ResolveSceneParts()
	if beginLine == nil or not beginLine:IsA("BasePart") then
		return nil
	end
	local fwd = NormalizeRunwayForward(forward)
	local beginEdgeWorld = beginLine.CFrame * Vector3.new(beginLine.Size.X / 2, 0, 0)
	return (beginEdgeWorld - origin):Dot(fwd)
end

function RunwaySession.ComputeRunwayDisplayDistanceStuds(hrp: BasePart): number
	if Refs.runwayDistanceRecorderPart ~= nil then
		return RunwaySession.GetDistanceRecorderDisplayStuds(hrp)
	end
	return RunwaySession.CurrentAlongProgress(hrp)
end

function RunwaySession.AppendRunwayGroundWallExcludeList(excludeList: { Instance })
	local groundFolder = workspace:FindFirstChild("Ground")
	if groundFolder ~= nil then
		local wallFolder = groundFolder:FindFirstChild("Wall")
		if wallFolder ~= nil then
			table.insert(excludeList, wallFolder)
		end
	end
end

function RunwaySession.BuildRunwayGroundRaycastExcludeList(character: Model?, extraExcludeList: { Instance }?): { Instance }
	local excludeList: { Instance } = {}
	if character ~= nil then
		table.insert(excludeList, character)
	end
	if extraExcludeList ~= nil then
		for _, inst in ipairs(extraExcludeList) do
			table.insert(excludeList, inst)
		end
	end
	local obstacleFolder = workspace:FindFirstChild("Obstacle")
	if obstacleFolder ~= nil then
		table.insert(excludeList, obstacleFolder)
	end
	local treeFolder = workspace:FindFirstChild("tree")
	if treeFolder ~= nil then
		table.insert(excludeList, treeFolder)
	end
	local localFx = workspace:FindFirstChild("JumpRunwayLocalFx")
	if localFx ~= nil then
		table.insert(excludeList, localFx)
	end
	if Refs.chestSpawnedModel ~= nil then
		table.insert(excludeList, Refs.chestSpawnedModel :: Model)
	end
	if Refs.bestDistanceWallModel ~= nil then
		table.insert(excludeList, Refs.bestDistanceWallModel :: Model)
	end
	RunwaySession.AppendRunwayGroundWallExcludeList(excludeList)
	return excludeList
end

function RunwaySession.BuildRunwayObstacleRaycastExcludeList(character: Model): { Instance }
	local excludeList: { Instance } = { character }
	local localFx = workspace:FindFirstChild("JumpRunwayLocalFx")
	if localFx ~= nil then
		table.insert(excludeList, localFx)
	end
	if Refs.chestSpawnedModel ~= nil then
		table.insert(excludeList, Refs.chestSpawnedModel :: Model)
	end
	if Refs.bestDistanceWallModel ~= nil then
		table.insert(excludeList, Refs.bestDistanceWallModel :: Model)
	end
	return excludeList
end

function RunwaySession.SetBasePartCollisionGroup(part: BasePart, groupName: string)
	pcall(function()
		part.CollisionGroup = groupName
	end)
end

function RunwaySession.SetModelCollisionGroup(model: Model, groupName: string)
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			RunwaySession.SetBasePartCollisionGroup(inst, groupName)
		end
	end
end

function RunwaySession.ApplyPlayerSlideCollisionGroup(character: Model?)
	if character == nil then
		return
	end
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("BasePart") then
			local part = inst :: BasePart
			if Refs.slideCollisionGroupOriginalMap[part] == nil then
				Refs.slideCollisionGroupOriginalMap[part] = part.CollisionGroup
			end
			RunwaySession.SetBasePartCollisionGroup(part, PlayerSlideCollisionGroupName)
		end
	end
end

function RunwaySession.RestorePlayerSlideCollisionGroup()
	for part, groupName in pairs(Refs.slideCollisionGroupOriginalMap) do
		if part.Parent ~= nil then
			RunwaySession.SetBasePartCollisionGroup(part, groupName)
		end
	end
	Refs.slideCollisionGroupOriginalMap = {}
end

function RunwaySession.BuildRunwayGroundRaycastParams(humanoid: Humanoid): RaycastParams
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local char = humanoid.Parent
	local character: Model? = nil
	if char ~= nil and char:IsA("Model") then
		character = char
	end
	rp.FilterDescendantsInstances = RunwaySession.BuildRunwayGroundRaycastExcludeList(character, nil)
	return rp
end

function RunwaySession.RaycastRunwayGroundYAtPosition(pos: Vector3, character: Model?, extraExcludeList: { Instance }?): number?
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = RunwaySession.BuildRunwayGroundRaycastExcludeList(character, extraExcludeList)
	local raycastHeight = ResolveConfigNumber(cfg.RUNWAY_CHEST_GROUND_RAYCAST_HEIGHT_STUDS, 256)
	local raycastDistance = ResolveConfigNumber(cfg.RUNWAY_CHEST_GROUND_RAYCAST_DISTANCE_STUDS, 512)
	local rayOrigin = Vector3.new(pos.X, pos.Y + raycastHeight, pos.Z)
	local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -raycastDistance, 0), rayParams)
	if rayResult == nil or rayResult.Normal.Y < cfg.RUNWAY_GROUND_MIN_NORMAL_Y then
		return nil
	end
	return rayResult.Position.Y
end

function RunwaySession.BuildLittleElfChestGroundPosition(targetPos: Vector3, groundY: number): Vector3
	return Vector3.new(
		targetPos.X,
		groundY + CHEST_GROUND_RAISE_STUDS,
		targetPos.Z
	)
end

function RunwaySession.ComputeLittleElfChestFallbackSpawnPosition(
	originPos: Vector3,
	hrpForHeight: BasePart,
	fwdH: Vector3,
	placeDistance: number
): Vector3
	local character = hrpForHeight:FindFirstAncestorOfClass("Model")
	local originGroundY = RunwaySession.RaycastRunwayGroundYAtPosition(originPos, character, nil)
	if originGroundY ~= nil then
		local targetXZ = originPos + fwdH * placeDistance
		return RunwaySession.BuildLittleElfChestGroundPosition(targetXZ, originGroundY)
	end
	return originPos + fwdH * placeDistance
end

function RunwaySession.RaycastRunwayForwardBlock(character: Model, hrp: BasePart, forward: Vector3): RaycastResult?
	local rayDistance = cfg.RUNWAY_BLOCKED_FORWARD_RAY_DISTANCE
	if typeof(rayDistance) ~= "number" or rayDistance ~= rayDistance or rayDistance <= 0 then
		rayDistance = 3.5
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = RunwaySession.BuildRunwayObstacleRaycastExcludeList(character)
	local origin = hrp.Position + Vector3.new(0, 0.2, 0)
	local hit = workspace:Raycast(origin, forward * rayDistance, rp)
	if hit == nil or not hit.Instance:IsA("BasePart") then
		return nil
	end
	if not hit.Instance.CanCollide then
		return nil
	end
	return hit
end

function RunwaySession.ResetRunwayForwardBlockedState()
	Refs.forwardBlockedStartClock = nil
	Refs.forwardBlockedStartAlong = nil
end

function RunwaySession.DebugFinalLandPhaseA(reason: string, humanoid: Humanoid?, hrp: BasePart?, nowClock: number)
	if cfg.DEBUG ~= true then
		return
	end
	if nowClock < Refs.finalLandPhaseADebugNextClock then
		return
	end
	Refs.finalLandPhaseADebugNextClock = nowClock + 0.25
	local okFeet = false
	local distFeet = 1e9
	local fullBody = false
	local looseGround = false
	local floorMaterial = Enum.Material.Air
	local humanoidState = "nil"
	local vy = 0
	local alongVelocity = 0
	if humanoid ~= nil then
		floorMaterial = humanoid.FloorMaterial
		humanoidState = humanoid:GetState().Name
		okFeet, distFeet = RunwaySession.RaycastFeet(humanoid)
	end
	if humanoid ~= nil and hrp ~= nil then
		local forward = NormalizeRunwayForward(localState.runwayForward)
		fullBody = RunwaySession.IsRunwayFinalLandFullBodyGrounded(humanoid, hrp)
		looseGround = RunwaySession.IsRunwayFinalLandPhaseAGroundedLoose(humanoid, hrp)
		vy = hrp.AssemblyLinearVelocity.Y
		alongVelocity = ComputeRunwayHorizontalAlongSpeed(hrp.AssemblyLinearVelocity, forward)
	end
	local groundedAge = if localState.finalLandPhaseAGroundedStartClock ~= nil
		then nowClock - (localState.finalLandPhaseAGroundedStartClock :: number)
		else -1
	--print(
	--	string.format(
	--		"[RunwaySession][FinalA] reason=%s sub=%d pop=%d lockedAlong=%.2f velAlong=%.2f vy=%.2f useAir=%s leftGround=%s groundedAge=%.2f okFeet=%s distFeet=%.2f fullBody=%s looseGround=%s floor=%s hState=%s slideElapsed=%.2f",
	--		reason,
	--		localState.finalLandSubPhase,
	--		localState.finalLandPhaseAPopCount,
	--		localState.finalLandLockedTumbleAlong,
	--		alongVelocity,
	--		vy,
	--		tostring(localState.finalLandTumbleUseAirClock),
	--		tostring(localState.finalLandTumbleLeftGround),
	--		groundedAge,
	--		tostring(okFeet),
	--		distFeet,
	--		tostring(fullBody),
	--		tostring(looseGround),
	--		floorMaterial.Name,
	--		humanoidState,
	--		nowClock - localState.slideStartClock
	--	)
	--)
end

function RunwaySession.DebugFinalLandPhaseAPop(
	reason: string,
	popIndex: number,
	landingAlong: number,
	landingVy: number,
	vySource: string,
	alongPop: number,
	vyPop: number,
	nowClock: number
)
	if cfg.DEBUG ~= true then
		return
	end
	print(
		string.format(
			"[RunwaySession][FinalA][Pop] reason=%s pop=%d landingAlong=%.2f landingVy=%.2f vySource=%s alongPop=%.2f vyPop=%.2f lockedAlong=%.2f slideElapsed=%.2f",
			reason,
			popIndex,
			landingAlong,
			landingVy,
			vySource,
			alongPop,
			vyPop,
			localState.finalLandLockedTumbleAlong,
			nowClock - localState.slideStartClock
		)
	)
end

function RunwaySession.ProcessRunwayForwardBlocked(character: Model, humanoid: Humanoid, hrp: BasePart, nowClock: number)
	if localState.phase ~= Ph.Airborne then
		RunwaySession.ResetRunwayForwardBlockedState()
		return
	end
	local forward = NormalizeRunwayForward(localState.runwayForward)
	if RunwaySession.RaycastRunwayForwardBlock(character, hrp, forward) == nil then
		RunwaySession.ResetRunwayForwardBlockedState()
		return
	end
	local currentAlong = RunwaySession.CurrentAlongProgress(hrp)
	if Refs.forwardBlockedStartClock == nil or Refs.forwardBlockedStartAlong == nil then
		Refs.forwardBlockedStartClock = nowClock
		Refs.forwardBlockedStartAlong = currentAlong
		return
	end
	local minStuckSec = cfg.RUNWAY_BLOCKED_MIN_STUCK_SEC
	if typeof(minStuckSec) ~= "number" or minStuckSec ~= minStuckSec or minStuckSec < 0 then
		minStuckSec = 0.35
	end
	if nowClock - (Refs.forwardBlockedStartClock :: number) < minStuckSec then
		return
	end
	local minProgress = cfg.RUNWAY_BLOCKED_MIN_PROGRESS_STUDS
	if typeof(minProgress) ~= "number" or minProgress ~= minProgress or minProgress < 0 then
		minProgress = 0.35
	end
	if currentAlong - (Refs.forwardBlockedStartAlong :: number) > minProgress then
		Refs.forwardBlockedStartClock = nowClock
		Refs.forwardBlockedStartAlong = currentAlong
		return
	end
	local maxAlongSpeed = cfg.RUNWAY_BLOCKED_MAX_ALONG_SPEED
	if typeof(maxAlongSpeed) ~= "number" or maxAlongSpeed ~= maxAlongSpeed or maxAlongSpeed < 0 then
		maxAlongSpeed = 2.5
	end
	local alongSpeed = math.abs(ComputeRunwayHorizontalAlongSpeed(hrp.AssemblyLinearVelocity, forward))
	if alongSpeed > maxAlongSpeed and currentAlong - (Refs.forwardBlockedStartAlong :: number) > minProgress * 0.25 then
		Refs.forwardBlockedStartClock = nowClock
		Refs.forwardBlockedStartAlong = currentAlong
		return
	end
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	RunwaySession.CancelJumpWindowTimeoutUntilGroundedAgain()
	RunwaySession.SnapCharacterHrpToGround(humanoid, hrp, forward)
	ClientMsg.FireJumpRunWayShowMiss()
	RunwaySession.EnterSlidePhase(nowClock, SlideKindMiss, humanoid)
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
	if cfg.DEBUG ~= true then
		RunwaySession.HudDestroy()
		local _, _, hrp = RunwaySession.GetCharacterParts()
		RunwaySession.RefreshJumpRunWayFrameStats(hrp)
		return
	end
	RunwaySession.HudEnsure()
	local _c, humanoid, hrp = RunwaySession.GetCharacterParts()
	local dist = 0
	if hrp ~= nil and localState.runwayOrigin ~= nil then
		dist = RunwaySession.ComputeRunwayDisplayDistanceStuds(hrp)
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
	RunwaySession.RefreshJumpRunWayFrameStats(hrp)
end

function RunwaySession.RefreshJumpRunWayFrameStats(hrp: BasePart?)
	local distanceStuds = 0
	local horizontalSpeed = 0
	if hrp ~= nil and localState.runwayOrigin ~= nil then
		distanceStuds = RunwaySession.ComputeRunwayDisplayDistanceStuds(hrp)
	end
	if hrp ~= nil then
		horizontalSpeed = HorizontalVelocity(hrp.AssemblyLinearVelocity).Magnitude
	end
	local maxFuel = RunwaySession.GetExpectedPlayerMaxFuel()
	local fuelVisible = localState.phase == Ph.Airborne
		and localState.takeoffCount >= cfg.N_TOTAL_JUMPS
		and maxFuel > 0
	local distanceVisible = distanceStuds > 0
	ClientMsg.FireJumpRunWayRefreshStats(distanceStuds, localState.fuel, maxFuel, fuelVisible, distanceVisible, horizontalSpeed)
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
	elseif RunwaySession.IsRunwayObstacleBounceSlidePhase() and Refs.chestRewardWaitPose ~= true then
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
		if RunwaySession.IsFinalDashThrustActive() then
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
	if info.settingInfo.decelerationOn == true then
		level = 1
	end
	local maxLevel = walkSpeedConfig.maxLevel
	if typeof(level) ~= "number" or level ~= level then
		level = 1
	end
	level = math.clamp(math.floor(level), 1, maxLevel)
	return walkSpeedConfig.abilityList[level] or fallback
end


function RunwaySession.HasEquippedJetpack(): boolean
   local info = ClientGameInfo.GetLocalPlayerInfo()
   if info == nil then
       return false
   end
   local currentId = info.jetpackInventory.currentId
   if currentId == nil or currentId == "" then
       return false
   end
   local jetpackData = GameConfig.JetpackDataMap[tonumber(currentId)]
   return jetpackData ~= nil
end

function RunwaySession.GetExpectedPlayerMaxFuel(): number
   local fallback = 0
	local info = ClientGameInfo.GetLocalPlayerInfo()
	if info == nil then
		return fallback
	end
   local currentId = info.jetpackInventory.currentId
   if currentId == nil or currentId == "" then
       return 0
   end
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

function RunwaySession.GetExpectedPlayerThrustPercent(): number
	local fallback = 100
	local info = ClientGameInfo.GetLocalPlayerInfo()
	if info == nil then
		return fallback
	end
	local currentId = info.jetpackInventory.currentId
	if currentId == nil or currentId == "" then
		return fallback
	end
	local jetpackData = GameConfig.JetpackDataMap[tonumber(currentId)]
	if jetpackData then
		return GameConfig.GetJetpackThrustPercent(jetpackData)
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

function RunwaySession.ResolveJumpWindowWalkAnimationId(humanoid: Humanoid): string
	local character = humanoid.Parent
	if character ~= nil and character:IsA("Model") then
		local animate = character:FindFirstChild("Animate")
		if animate ~= nil then
			for _, groupName in ipairs({ "walk", "run" }) do
				local group = animate:FindFirstChild(groupName)
				if group ~= nil then
					for _, inst in group:GetDescendants() do
						if inst:IsA("Animation") and inst.AnimationId ~= "" then
							return inst.AnimationId
						end
					end
				end
			end
		end
	end
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		return JumpWindowR6WalkAnimationId
	end
	return JumpWindowR15WalkAnimationId
end

function RunwaySession.StopJumpWindowWalkAnimation()
	if Refs.jumpWindowWalkAnimTrack ~= nil then
		Refs.jumpWindowWalkAnimTrack:Stop(0.08)
	end
	Refs.jumpWindowWalkAnimTrack = nil
	Refs.jumpWindowWalkAnimId = nil
end

function RunwaySession.EnsureJumpWindowWalkAnimation(humanoid: Humanoid, speedScale: number)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animationId = RunwaySession.ResolveJumpWindowWalkAnimationId(humanoid)
	if Refs.jumpWindowWalkAnimTrack ~= nil and Refs.jumpWindowWalkAnimId ~= animationId then
		RunwaySession.StopJumpWindowWalkAnimation()
	end
	if Refs.jumpWindowWalkAnimTrack == nil then
		local animation = Instance.new("Animation")
		animation.AnimationId = animationId
		local track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Movement
		Refs.jumpWindowWalkAnimTrack = track
		Refs.jumpWindowWalkAnimId = animationId
	end

	local track = Refs.jumpWindowWalkAnimTrack
	if track == nil then
		return
	end
	if not track.IsPlaying then
		track:Play(0.08, 1, 0.9)
	end
	local guideAnimScale = RunwaySession.GetGuideSlowMotionScale()
	local stumbleAnimSpeed = math.clamp(0.85 + (1 - speedScale) * 1.4, 0.75, 1.25)
	track:AdjustSpeed(math.max(stumbleAnimSpeed * guideAnimScale, 0.05))
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
	localState.jumpHorizLerpInitialVy = nil
end

function RunwaySession.GetJumpHorizontalForwardSpeed(nowClock: number, segmentIndex: number, currentVerticalY: number?): number
	local maxSpd, minSpd =
		GameConfig.GetJumpRunwayJumpSpeedLimitsForSegment(
			segmentIndex,
			localState.jumpSpeedCumulativeRatingBonus,
			GetJumpPowerBaseSpeed(),
			localState.jumpSpeedCurrentReductionDelta
		)
	local startClock = localState.jumpHorizLerpStartClock
	if startClock == nil then
		return minSpd
	end
	local duration = localState.jumpHorizLerpDuration
	if duration < 1e-4 then
		return minSpd
	end
	local initialVy = localState.jumpHorizLerpInitialVy
	local progress = (nowClock - startClock) / duration
	if
		typeof(currentVerticalY) == "number"
		and currentVerticalY == currentVerticalY
		and typeof(initialVy) == "number"
		and initialVy == initialVy
		and initialVy > 1e-4
	then
		progress = 1 - math.max(0, currentVerticalY) / initialVy
	end
	if progress >= 1 then
		return minSpd
	end
	local eased = progress
	return maxSpd + (minSpd - maxSpd) * eased
end

function RunwaySession.GetGuideSlowMotionScale(): number
	return if Refs.guideSlowMotionActive then GuideSlowMotionSpeedScale else 1
end

function RunwaySession.IsFinalDashTutorialGateOpen(): boolean
	if RunwaySession.IsGuideStepDone(GameConfig.GuideStepKey.FinalDashFinished) then
		return true
	end
	return Refs.guideSlowMotionActive
		and Refs.guideSlowMotionStepKey == GameConfig.GuideStepKey.FinalDashFinished
end

function RunwaySession.IsFinalDashThrustActive(): boolean
	return localState.phase == Ph.Airborne
		and localState.takeoffCount >= cfg.N_TOTAL_JUMPS
		and localState.dashHeld
		and localState.fuel > 0
		and RunwaySession.IsFinalDashTutorialGateOpen()
end

function RunwaySession.UpdateAutoRunVelocity(hrp: BasePart, forward: Vector3, dt: number, humanoid: Humanoid)
	local v = hrp.AssemblyLinearVelocity
	local vy = RunwaySession.GetBoostedVerticalY(v.Y)
	local fwdH = forward
	local nowClock = os.clock()
	local segForDefault = math.max(1, localState.takeoffCount)
	local _, defaultMinAlong = GameConfig.GetJumpRunwayJumpSpeedLimitsForSegment(
		segForDefault,
		localState.jumpSpeedCumulativeRatingBonus,
		GetJumpPowerBaseSpeed(),
		localState.jumpSpeedCurrentReductionDelta
	)
	local forwardSpeed = defaultMinAlong
	if localState.takeoffCount == 0 then
		-- 首段 AutoRun / BeginLine 窗（含 JumpWindow 漂移）统一使用 FIRST_TAKEOFF_AUTORUN_SPEED。
		forwardSpeed = cfg.FIRST_TAKEOFF_AUTORUN_SPEED
	elseif localState.phase == Ph.Airborne and localState.takeoffCount <= cfg.N_TOTAL_JUMPS then
		if localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
			local base = RunwaySession.GetJumpHorizontalForwardSpeed(nowClock, localState.takeoffCount, vy)
			local thrustPercent = RunwaySession.GetExpectedPlayerThrustPercent()
			local capExtra = math.max(0, base * thrustPercent / 100)
			if RunwaySession.IsFinalDashThrustActive() then
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
			forwardSpeed = math.min(base + localState.finalDashAlongExtra, base + capExtra)
			localState.finalDashAlongExtra = math.max(0, forwardSpeed - base)
		else
			-- Airborne 全程走跳跃水平 lerp，不因落地窗口内判地切回 minAlongGrounded（会触发 run 并覆盖起跳冲量）。
			forwardSpeed = RunwaySession.GetJumpHorizontalForwardSpeed(nowClock, localState.takeoffCount, vy)
		end
	end
	local guideSlowMotionScale = RunwaySession.GetGuideSlowMotionScale()
	forwardSpeed *= guideSlowMotionScale
	vy *= guideSlowMotionScale
	hrp.AssemblyLinearVelocity = fwdH * forwardSpeed + Vector3.new(0, vy, 0)
end

function RunwaySession.ApplyJumpWindowWalkPhysics(humanoid: Humanoid, hrp: BasePart, forward: Vector3)
	local v = hrp.AssemblyLinearVelocity
	local vy = RunwaySession.GetBoostedVerticalY(v.Y)
	local fwdH = Vector3.new(forward.X, 0, forward.Z)
	if fwdH.Magnitude < 1e-4 then
		hrp.AssemblyLinearVelocity = Vector3.new(v.X, vy, v.Z)
		return
	end
	fwdH = fwdH.Unit
	local stumbleWave = math.abs(math.sin(os.clock() * math.pi * 2 * JumpWindowStumblePulseFrequencyHz))
	local speedScale = math.max(JumpWindowStumbleMinSpeedScale, 1 - stumbleWave * JumpWindowStumblePulseStrength)
	local guideSlowMotionScale = RunwaySession.GetGuideSlowMotionScale()
	RunwaySession.EnsureHumanoidWalkingState(humanoid)
	RunwaySession.EnsureJumpWindowWalkAnimation(humanoid, speedScale)
	humanoid:Move(fwdH, false)
	local walkSpeed = cfg.JUMP_WINDOW_WALK_SPEED * speedScale * guideSlowMotionScale
	hrp.AssemblyLinearVelocity = fwdH * walkSpeed + Vector3.new(0, vy * guideSlowMotionScale, 0)
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
		GetJumpPowerBaseSpeed(),
		localState.jumpSpeedCurrentReductionDelta
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

function RunwaySession.FreezeGuideSlowMotionFinalDashPosition(hrp: BasePart)
	if not Refs.guideSlowMotionActive or Refs.guideSlowMotionStepKey ~= GameConfig.GuideStepKey.FinalDashFinished then
		Refs.guideSlowMotionFreezePosition = nil
		return
	end
	if localState.phase ~= Ph.Airborne or localState.takeoffCount < cfg.N_TOTAL_JUMPS then
		Refs.guideSlowMotionFreezePosition = nil
		return
	end
	local freezePosition = Refs.guideSlowMotionFreezePosition
	if freezePosition == nil then
		freezePosition = hrp.Position
		Refs.guideSlowMotionFreezePosition = freezePosition
	end
	hrp.CFrame = RunwaySession.CFrameAtPositionWithSameOrientation(hrp.CFrame, freezePosition)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

function RunwaySession.ApplyRunwayYawCorrection(hrp: BasePart, forward: Vector3, dt: number)
	if localState.phase == Ph.Slide then
		return
	end
	if localState.phase == Ph.Airborne and localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
		return
	end
	local f = Vector3.new(forward.X, 0, forward.Z)
	if f.Magnitude < 1e-4 then
		return
	end
	f = f.Unit
	local pos = hrp.Position
	local linVel = hrp.AssemblyLinearVelocity
	local targetCf = CFrame.lookAt(pos, pos + f, Vector3.yAxis)
	local rate = cfg.RUNWAY_ORIENTATION_CORRECT_RATE
	if typeof(rate) ~= "number" or rate ~= rate then
		rate = 18
	end
	local alpha = if rate <= 0 then 1 else 1 - math.exp(-rate * dt)
	local blendedRot = hrp.CFrame.Rotation:Lerp(targetCf.Rotation, alpha)
	hrp.CFrame = CFrame.fromMatrix(pos, blendedRot.XVector, blendedRot.YVector, blendedRot.ZVector)
	hrp.AssemblyLinearVelocity = linVel
	hrp.AssemblyAngularVelocity = hrp.AssemblyAngularVelocity * math.exp(-math.max(0, rate) * dt)
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

function RunwaySession.ResolveFiniteNumber(raw: any, fallback: number): number
	if typeof(raw) == "number" and raw == raw then
		return raw
	end
	return fallback
end

function RunwaySession.GetHumanoidRootGroundHeight(humanoid: Humanoid, hrp: BasePart): number
	local hipHeight = RunwaySession.ResolveFiniteNumber(humanoid.HipHeight, 2)
	local rootHalfHeight = math.max(0, hrp.Size.Y * 0.5)
	return math.max(0, hipHeight + rootHalfHeight)
end

function RunwaySession.GetRunwayGroundYUnderHrp(_humanoid: Humanoid, hrp: BasePart): number?
	local character = hrp:FindFirstAncestorOfClass("Model")
	return RunwaySession.RaycastRunwayGroundYAtPosition(hrp.Position, character, nil)
end

function RunwaySession.GetRunwayGroundYAtWorldPosition(pos: Vector3, character: Model?): number?
	return RunwaySession.RaycastRunwayGroundYAtPosition(pos, character, nil)
end

function RunwaySession.ResolveProneHrpGroundHeight(rawHeight: any, fallbackHeight: number): number
	local height = RunwaySession.ResolveFiniteNumber(rawHeight, fallbackHeight)
	return math.max(0, height)
end

function RunwaySession.BuildProneRunwayCFrameAtGroundHeight(
	humanoid: Humanoid,
	hrp: BasePart,
	runwayForward: Vector3,
	heightRaw: any,
	fallbackHeight: number
): CFrame
	local height = RunwaySession.ResolveProneHrpGroundHeight(heightRaw, fallbackHeight)
	local groundY = RunwaySession.GetRunwayGroundYUnderHrp(humanoid, hrp)
	local pos = hrp.Position
	if groundY ~= nil then
		pos = Vector3.new(pos.X, groundY + height, pos.Z)
	end
	return RunwaySession.BuildProneRunwayCFrame(pos, runwayForward)
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

function RunwaySession.CacheFinalLandLandingAlongValue(alongSpeed: number)
	if typeof(alongSpeed) ~= "number" or alongSpeed ~= alongSpeed then
		return
	end
	localState.finalLandCachedLandingAlong = math.clamp(
		math.max(0, alongSpeed),
		0,
		cfg.ANTI_CHEAT_MAX_ALONG_SPEED
	)
end

function RunwaySession.ResolveCachedFinalLandLandingAlong(): number
	local cachedLandingAlong = localState.finalLandCachedLandingAlong
	if typeof(cachedLandingAlong) == "number" and cachedLandingAlong == cachedLandingAlong then
		return math.clamp(math.max(0, cachedLandingAlong), 0, cfg.ANTI_CHEAT_MAX_ALONG_SPEED)
	end
	return 0
end

function RunwaySession.ResolveMissSlideStartSpeed(): number
	local startSpeed = ResolveConfigNumber(cfg.RUNWAY_MISS_SLIDE_START_SPEED, 50)
	return math.clamp(math.max(0, startSpeed), 0, cfg.ANTI_CHEAT_MAX_ALONG_SPEED)
end

function RunwaySession.ResolveProneSlideDeceleration(): number
	return math.max(0.01, ResolveConfigNumber(cfg.RUNWAY_PRONE_SLIDE_DECELERATION, 80))
end

function RunwaySession.ResolveChestHitSpeed(): number
	return math.clamp(math.max(0, ResolveConfigNumber(cfg.RUNWAY_CHEST_HIT_SPEED, 12)), 0, cfg.ANTI_CHEAT_MAX_ALONG_SPEED)
end

function RunwaySession.ResolveFinalLandProneSlideDeceleration(alongSpeedStart: number, landingVy: number): number
	local baseDeceleration = RunwaySession.ResolveProneSlideDeceleration()
	local verticalRatioScale = ResolveConfigNumber(cfg.RUNWAY_FINAL_LAND_VERTICAL_DECELERATION_RATIO, 0)
	if verticalRatioScale <= 0 then
		return baseDeceleration
	end
	local maxVerticalRatio = math.max(0, ResolveConfigNumber(cfg.RUNWAY_FINAL_LAND_VERTICAL_DECELERATION_MAX_RATIO, 2))
	if maxVerticalRatio <= 0 then
		return baseDeceleration
	end
	local expectedVerticalSpeed = math.max(1, math.max(0, alongSpeedStart) * cfg.JUMP_VERTICAL_RATIO)
	local verticalRatio = math.clamp(math.abs(landingVy) / expectedVerticalSpeed, 0, maxVerticalRatio)
	return baseDeceleration + baseDeceleration * verticalRatioScale * verticalRatio
end

function RunwaySession.NormalizeHorizontalForward(forward: Vector3): Vector3
	local fwdH = Vector3.new(forward.X, 0, forward.Z)
	if fwdH.Magnitude < 1e-4 then
		return Vector3.new(0, 0, -1)
	end
	return fwdH.Unit
end

function RunwaySession.CreateScriptedSlideMotion(
	startClock: number,
	startPosition: Vector3,
	forward: Vector3,
	startSpeed: number,
	endSpeed: number,
	deceleration: number
): ScriptedSlideMotion
	local resolvedStartSpeed = math.clamp(math.max(0, startSpeed), 0, cfg.ANTI_CHEAT_MAX_ALONG_SPEED)
	local resolvedDeceleration = math.max(0.01, deceleration)
	local resolvedEndSpeed = math.clamp(math.max(0, endSpeed), 0, math.max(0, resolvedStartSpeed - 1e-2))
	local duration = if resolvedStartSpeed > 1e-2 then (resolvedStartSpeed - resolvedEndSpeed) / resolvedDeceleration else 0
	local totalDistance = if duration > 0 then (resolvedStartSpeed + resolvedEndSpeed) * duration * 0.5 else 0
	return {
		startClock = startClock,
		startPosition = startPosition,
		forward = RunwaySession.NormalizeHorizontalForward(forward),
		startSpeed = resolvedStartSpeed,
		endSpeed = resolvedEndSpeed,
		deceleration = resolvedDeceleration,
		duration = duration,
		totalDistance = totalDistance,
		lastDistance = 0,
	}
end

function RunwaySession.CreateFinalLandProneSlideMotion(
	startClock: number,
	startPosition: Vector3,
	forward: Vector3,
	alongSpeedStart: number,
	landingVy: number
): ScriptedSlideMotion
	return RunwaySession.CreateScriptedSlideMotion(
		startClock,
		startPosition,
		forward,
		alongSpeedStart,
		RunwaySession.ResolveChestHitSpeed(),
		RunwaySession.ResolveFinalLandProneSlideDeceleration(alongSpeedStart, landingVy)
	)
end

function RunwaySession.CreateMissSlideMotion(
	startClock: number,
	startPosition: Vector3,
	forward: Vector3
): ScriptedSlideMotion
	return RunwaySession.CreateScriptedSlideMotion(
		startClock,
		startPosition,
		forward,
		RunwaySession.ResolveMissSlideStartSpeed(),
		RunwaySession.ResolveChestHitSpeed(),
		RunwaySession.ResolveProneSlideDeceleration()
	)
end

function RunwaySession.ComputeScriptedSlideDistanceAt(motion: ScriptedSlideMotion, nowClock: number): number
	local elapsed = math.clamp(nowClock - motion.startClock, 0, motion.duration)
	local distance = motion.startSpeed * elapsed - 0.5 * motion.deceleration * elapsed * elapsed
	return math.clamp(distance, 0, motion.totalDistance)
end

function RunwaySession.ClearScriptedSlideMotion()
	Refs.slideMotion = nil
end

function RunwaySession.ResolveTreeHitNumber(rawValue: any, fallbackValue: number, minValue: number?, maxValue: number?): number
	local value = if typeof(rawValue) == "number" and rawValue == rawValue then rawValue else fallbackValue
	if minValue ~= nil then
		value = math.max(minValue :: number, value)
	end
	if maxValue ~= nil then
		value = math.min(maxValue :: number, value)
	end
	return value
end

function RunwaySession.ResetTreeHitBlockedState()
	Refs.treeHitBlockedStartClock = nil
	Refs.treeHitBlockedStartAlong = nil
end

function RunwaySession.IsFinalLandingSlideTreeHitEligible(): boolean
	if Refs.chestRunwayAwaitingExit == true or Refs.chestRewardPresentationStarted == true then
		return false
	end
	if localState.finalLandSubPhase ~= 1 and localState.finalLandSubPhase ~= 2 then
		return false
	end
	return localState.runwaySlideKind == SlideKindFinalLanding
		or localState.runwaySlideKind == SlideKindObstacleBounce
end

function RunwaySession.IsTreeHitCheckActive(): boolean
	if cfg.RUNWAY_TREE_HIT_ENABLED ~= true then
		return false
	end
	if localState.phase == Ph.Airborne then
		return localState.takeoffCount >= 1
	end
	if localState.phase == Ph.Slide and RunwaySession.IsFinalLandingSlideTreeHitEligible() then
		return true
	end
	return false
end

function RunwaySession.ResolveTreeHitMoveDirection(hrp: BasePart): Vector3
	if localState.phase == Ph.Slide and localState.finalLandSubPhase == 2 then
		local motion = Refs.slideMotion
		if motion ~= nil and motion.forward.Magnitude > 1e-4 then
			return RunwaySession.NormalizeHorizontalForward(motion.forward)
		end
	end
	local velocityH = HorizontalVelocity(hrp.AssemblyLinearVelocity)
	if velocityH.Magnitude > 1e-3 then
		return velocityH.Unit
	end
	return NormalizeRunwayForward(localState.runwayForward)
end

function RunwaySession.RaycastJumpRunwayTreeHit(hrp: BasePart, moveDir: Vector3): RaycastResult?
	local treeFolder = workspace:FindFirstChild("tree")
	if treeFolder == nil then
		return nil
	end
	local dirH = RunwaySession.NormalizeHorizontalForward(moveDir)
	local rayDistance = RunwaySession.ResolveTreeHitNumber(cfg.RUNWAY_TREE_HIT_CHECK_DISTANCE_STUDS, 5, 0.1, 32)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { treeFolder }
	local origin = hrp.Position + Vector3.new(0, 0.35, 0)
	local hit = workspace:Raycast(origin, dirH * rayDistance, rayParams)
	if hit == nil or not hit.Instance:IsA("BasePart") then
		return nil
	end
	return hit
end

function RunwaySession.ComputeTreeHitImpactDot(hit: RaycastResult, moveDir: Vector3): (number, Vector3)
	local normalH = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
	local moveH = RunwaySession.NormalizeHorizontalForward(moveDir)
	if normalH.Magnitude < 1e-4 then
		normalH = -moveH
	else
		normalH = normalH.Unit
	end
	return math.clamp(moveH:Dot(-normalH), -1, 1), normalH
end

function RunwaySession.ApplyAirborneTreeSlow(hrp: BasePart, slowScale: number)
	local v = hrp.AssemblyLinearVelocity
	local horiz = HorizontalVelocity(v)
	if horiz.Magnitude < 1e-3 then
		return
	end
	local nextHoriz = horiz * slowScale
	hrp.AssemblyLinearVelocity = nextHoriz + Vector3.new(0, v.Y, 0)
	local baseSpeed = GetJumpPowerBaseSpeed()
	local nextSpeed = nextHoriz.Magnitude
	localState.jumpSpeedCumulativeRatingBonus = math.max(0, nextSpeed - baseSpeed)
	localState.jumpSpeedCurrentReductionDelta = 0
	localState.finalDashAlongExtra = 0
	localState.jumpHorizLerpStartClock = nil
	localState.jumpHorizLerpDuration = 0
	localState.jumpHorizLerpInitialVy = nil
end

function RunwaySession.ApplyFinalLandPhaseATreeSlow(hrp: BasePart, slowScale: number)
	localState.finalLandLockedTumbleAlong = math.max(0, localState.finalLandLockedTumbleAlong * slowScale)
	local v = hrp.AssemblyLinearVelocity
	local horiz = HorizontalVelocity(v)
	if horiz.Magnitude < 1e-3 then
		return
	end
	local nextHoriz = horiz * slowScale
	hrp.AssemblyLinearVelocity = nextHoriz + Vector3.new(0, v.Y, 0)
end

function RunwaySession.ApplyProneSlideTreeSlow(hrp: BasePart, nowClock: number, slowScale: number)
	local motion = Refs.slideMotion
	if motion == nil then
		return
	end
	local elapsed = math.clamp(nowClock - motion.startClock, 0, motion.duration)
	local currentSpeed = math.max(motion.endSpeed, motion.startSpeed - motion.deceleration * elapsed)
	local slowedSpeed = math.max(0, currentSpeed * slowScale)
	local nextEndSpeed = math.min(motion.endSpeed, math.max(0, slowedSpeed * 0.5))
	local character = hrp:FindFirstAncestorOfClass("Model")
	local startPos = RunwaySession.ComputeGroundedPronePosition(hrp.Position, character)
	Refs.slideMotion = RunwaySession.CreateScriptedSlideMotion(
		nowClock,
		startPos,
		motion.forward,
		slowedSpeed,
		nextEndSpeed,
		motion.deceleration
	)
	RunwaySession.ApplyScriptedProneSlideMotion(hrp, nowClock)
end

function RunwaySession.ComputeTreeBounceDirection(velocityH: Vector3, normalH: Vector3): Vector3
	local source = velocityH
	if source.Magnitude < 1e-3 then
		source = NormalizeRunwayForward(localState.runwayForward)
	end
	local reflect = source - normalH * (2 * source:Dot(normalH))
	local reflectH = Vector3.new(reflect.X, 0, reflect.Z)
	if reflectH.Magnitude < 1e-4 then
		return -NormalizeRunwayForward(localState.runwayForward)
	end
	return reflectH.Unit
end

function RunwaySession.EnterObstacleBounceFromTree(
	humanoid: Humanoid,
	hrp: BasePart,
	nowClock: number,
	normalH: Vector3,
	moveDir: Vector3,
	reason: string
)
	if localState.phase == Ph.Slide and localState.runwaySlideKind == SlideKindObstacleBounce then
		return
	end
	GameSoundManager.PlayImpactSound()
	RunwaySession.TransitionDistanceLogStage("ObstacleBounce", reason, hrp, string.format("takeoffCount=%d", localState.takeoffCount))
	local v = hrp.AssemblyLinearVelocity
	local velocityH = HorizontalVelocity(v)
	if velocityH.Magnitude < 1e-3 then
		velocityH = RunwaySession.NormalizeHorizontalForward(moveDir) * RunwaySession.ResolveTreeHitNumber(
			cfg.RUNWAY_TREE_HIT_BOUNCE_MIN_SPEED,
			18,
			0,
			cfg.ANTI_CHEAT_MAX_ALONG_SPEED
		)
	end
	local bounceDir = RunwaySession.ComputeTreeBounceDirection(velocityH, normalH)
	local speedScale = RunwaySession.ResolveTreeHitNumber(cfg.RUNWAY_TREE_HIT_BOUNCE_SPEED_SCALE, 0.55, 0, 2)
	local minSpeed = RunwaySession.ResolveTreeHitNumber(cfg.RUNWAY_TREE_HIT_BOUNCE_MIN_SPEED, 18, 0, cfg.ANTI_CHEAT_MAX_ALONG_SPEED)
	local bounceSpeed = math.clamp(math.max(minSpeed, velocityH.Magnitude * speedScale), 0, cfg.ANTI_CHEAT_MAX_ALONG_SPEED)
	local bounceVy = RunwaySession.ResolveTreeHitNumber(cfg.RUNWAY_TREE_HIT_BOUNCE_UP_VY, 18, 0, 200)
	RunwaySession.CancelJumpWindowTimeoutUntilGroundedAgain()
	RunwaySession.ClearJumpHorizontalLerp()
	RunwaySession.ClearScriptedSlideMotion()
	RunwaySession.ClearChestBounceMotion()
	Refs.obstacleBounceForward = bounceDir
	Refs.treeHitLastProcessClock = nowClock
	RunwaySession.ResetTreeHitBlockedState()
	if localState.phase == Ph.Slide then
		RunwaySession.ApplyObstacleBounceSlideKindTransition(nowClock)
	else
		RunwaySession.EnterSlidePhase(nowClock, SlideKindObstacleBounce, humanoid)
	end
	RunwaySession.StartObstacleBouncePhaseA(hrp, bounceDir, bounceSpeed, bounceVy, nowClock)
end

function RunwaySession.ProcessJumpRunwayTreeHit(humanoid: Humanoid, hrp: BasePart, nowClock: number)
	if not RunwaySession.IsTreeHitCheckActive() then
		RunwaySession.ResetTreeHitBlockedState()
		return
	end
	local cooldownSec = RunwaySession.ResolveTreeHitNumber(cfg.RUNWAY_TREE_HIT_COOLDOWN_SEC, 0.25, 0, 3)
	if nowClock - Refs.treeHitLastProcessClock < cooldownSec then
		return
	end
	local moveDir = RunwaySession.ResolveTreeHitMoveDirection(hrp)
	local hit = RunwaySession.RaycastJumpRunwayTreeHit(hrp, moveDir)
	if hit == nil then
		RunwaySession.ResetTreeHitBlockedState()
		return
	end
	local impactDot, normalH = RunwaySession.ComputeTreeHitImpactDot(hit, moveDir)
	local slowThreshold = RunwaySession.ResolveTreeHitNumber(cfg.RUNWAY_TREE_HIT_SLOW_DOT_THRESHOLD, 0.18, -1, 1)
	if impactDot < slowThreshold then
		RunwaySession.ResetTreeHitBlockedState()
		return
	end
	local currentAlong = RunwaySession.CurrentAlongProgress(hrp)
	if Refs.treeHitBlockedStartClock == nil or Refs.treeHitBlockedStartAlong == nil then
		Refs.treeHitBlockedStartClock = nowClock
		Refs.treeHitBlockedStartAlong = currentAlong
	end
	local bounceThreshold = RunwaySession.ResolveTreeHitNumber(cfg.RUNWAY_TREE_HIT_BOUNCE_DOT_THRESHOLD, 0.58, -1, 1)
	local blockedLongEnough = false
	local startClock = Refs.treeHitBlockedStartClock
	local startAlong = Refs.treeHitBlockedStartAlong
	if startClock ~= nil and startAlong ~= nil then
		blockedLongEnough = nowClock - (startClock :: number) >= 0.25 and currentAlong - (startAlong :: number) <= 0.35
	end
	if impactDot >= bounceThreshold or blockedLongEnough then
		RunwaySession.EnterObstacleBounceFromTree(humanoid, hrp, nowClock, normalH, moveDir, "tree_bounce")
		return
	end
	GameSoundManager.PlayImpactSound()
	local slowScale = RunwaySession.ResolveTreeHitNumber(cfg.RUNWAY_TREE_HIT_SLOW_SPEED_SCALE, 0.65, 0, 1)
	if localState.phase == Ph.Slide then
		if localState.finalLandSubPhase == 1 then
			RunwaySession.ApplyFinalLandPhaseATreeSlow(hrp, slowScale)
		else
			RunwaySession.ApplyProneSlideTreeSlow(hrp, nowClock, slowScale)
		end
	else
		RunwaySession.ApplyAirborneTreeSlow(hrp, slowScale)
	end
	Refs.treeHitLastProcessClock = nowClock
end

function RunwaySession.ResolveProneSlidePlaceDistance(): number
	local motion = Refs.slideMotion
	local hitDistance = ResolveChestHitHorizontalMaxDistStuds()
	if motion == nil then
		return hitDistance
	end
	return motion.totalDistance + hitDistance
end

function RunwaySession.GetProneSlideHrpGroundHeight(): number
	if localState.runwaySlideKind == SlideKindMiss then
		return RunwaySession.ResolveProneHrpGroundHeight(cfg.RUNWAY_MISS_SLIDE_PRONE_HRP_GROUND_HEIGHT, 2.8)
	end
	if localState.runwaySlideKind == SlideKindObstacleBounce then
		return RunwaySession.ResolveProneHrpGroundHeight(cfg.RUNWAY_OBSTACLE_BOUNCE_SLIDE_PRONE_HRP_GROUND_HEIGHT, 2.8)
	end
	return RunwaySession.ResolveProneHrpGroundHeight(cfg.RUNWAY_FINAL_LAND_PRONE_HRP_GROUND_HEIGHT, 2.8)
end

function RunwaySession.ComputeGroundedPronePosition(pos: Vector3, character: Model?): Vector3
	local groundY = RunwaySession.GetRunwayGroundYAtWorldPosition(pos, character)
	if groundY == nil then
		return pos
	end
	return Vector3.new(pos.X, groundY + RunwaySession.GetProneSlideHrpGroundHeight(), pos.Z)
end

function RunwaySession.ApplyScriptedProneSlideMotion(hrp: BasePart, nowClock: number): boolean
	local motion = Refs.slideMotion
	if motion == nil then
		return false
	end
	local distance = RunwaySession.ComputeScriptedSlideDistanceAt(motion, nowClock)
	local character = hrp:FindFirstAncestorOfClass("Model")
	if localState.runwaySlideKind == SlideKindObstacleBounce and localState.finalLandSubPhase == 2 then
		local blockedDistance = RunwaySession.ResolveObstacleBounceProneSlideBlockedDistance(motion, distance)
		if blockedDistance + 0.01 < distance then
			RunwaySession.FreezeScriptedSlideMotionAtDistance(motion, blockedDistance, nowClock)
			distance = blockedDistance
		end
	end
	motion.lastDistance = distance
	local nextPos = RunwaySession.ComputeGroundedPronePosition(
		motion.startPosition + motion.forward * distance,
		character
	)
	local proneForward = if localState.runwaySlideKind == SlideKindObstacleBounce
		then NormalizeRunwayForward(localState.runwayForward)
		else motion.forward
	hrp.CFrame = RunwaySession.BuildProneRunwayCFrame(nextPos, proneForward)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	return true
end

function RunwaySession.StartChestBounceMotion(nowClock: number, hrp: BasePart, forward: Vector3)
	local startSpeed = RunwaySession.ResolveChestHitSpeed()
	local deceleration = RunwaySession.ResolveProneSlideDeceleration()
	local duration = if startSpeed > 1e-2 then startSpeed / deceleration else 0
	Refs.chestBounceMotion = {
		startClock = nowClock,
		startPosition = hrp.Position,
		forward = -RunwaySession.NormalizeHorizontalForward(forward),
		startSpeed = startSpeed,
		deceleration = deceleration,
		duration = duration,
		totalDistance = if duration > 0 then startSpeed * duration * 0.5 else 0,
		lastDistance = 0,
	}
end

function RunwaySession.ClearChestBounceMotion()
	Refs.chestBounceMotion = nil
end

function RunwaySession.ApplyChestBounceMotion(hrp: BasePart, nowClock: number): boolean
	local motion = Refs.chestBounceMotion
	if motion == nil then
		return false
	end
	local elapsed = math.clamp(nowClock - motion.startClock, 0, motion.duration)
	local distance = motion.startSpeed * elapsed - 0.5 * motion.deceleration * elapsed * elapsed
	distance = math.clamp(distance, 0, motion.totalDistance)
	motion.lastDistance = distance
	local character = hrp:FindFirstAncestorOfClass("Model")
	local nextPos = RunwaySession.ComputeGroundedPronePosition(
		motion.startPosition + motion.forward * distance,
		character
	)
	hrp.CFrame = RunwaySession.BuildProneRunwayCFrame(nextPos, -motion.forward)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	return true
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

function RunwaySession.ResolveFinalLandAlongSpeedForPhaseB(): number
	local lockedAlong = math.max(0, localState.finalLandLockedTumbleAlong)
	if lockedAlong > 1e-2 then
		return math.clamp(lockedAlong, 0, cfg.ANTI_CHEAT_MAX_ALONG_SPEED)
	end
	return RunwaySession.ResolveCachedFinalLandLandingAlong()
end

function RunwaySession.ApplyFinalLandPhaseAPop(hrp: BasePart, fwdH: Vector3, nowClock: number)
	local v = hrp.AssemblyLinearVelocity
	local landingAlong, landingVy = RunwaySession.SampleFinalLandLandingAlongAndVy(hrp, fwdH)
	local vySource = "current"
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
			vySource = "cached_falling"
		end
	else
		local prevVy = localState.finalLandTumblePrevPopVy
		if prevVy ~= nil and prevVy > 0 then
			landingVy = -(prevVy :: number)
			vySource = "previous_pop"
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
	GameSoundManager.PlayImpactSound()
	RunwaySession.DebugFinalLandPhaseAPop("apply", popIndex, landingAlong, landingVy, vySource, alongPop, vyPop, nowClock)
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
	localState.finalLandPhaseAGroundedStartClock = nil
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

function RunwaySession.StartObstacleBouncePhaseA(hrp: BasePart, bounceDir: Vector3, bounceSpeed: number, bounceVy: number, nowClock: number)
	local fwdH = RunwaySession.NormalizeHorizontalForward(bounceDir)
	local faceFwdH = NormalizeRunwayForward(localState.runwayForward)
	localState.finalLandPhaseAPopCount = 1
	localState.finalLandTumbleImpulseApplied = true
	localState.finalLandTumbleRollAngleRad = 0
	localState.finalLandLockedTumbleAlong = math.clamp(bounceSpeed, 0, cfg.ANTI_CHEAT_MAX_ALONG_SPEED)
	localState.finalLandTumblePrevPopVy = math.max(0, bounceVy)
	localState.finalLandTumbleAirAccumSec = 0
	localState.finalLandTumbleLeftGround = false
	localState.finalLandTumbleUseAirClock = bounceVy > 0.5
	localState.finalLandPhaseAGroundedStartClock = nil
	local gBase = workspace.Gravity
	if gBase < 1e-3 then
		gBase = 196.2
	end
	local gScale = cfg.RUNWAY_FINAL_LAND_PHASE_A_EFFECTIVE_GRAVITY_SCALE
	if typeof(gScale) ~= "number" or gScale ~= gScale or gScale <= 0 then
		gScale = cfg.RUNWAY_SESSION_EFFECTIVE_GRAVITY_SCALE
	end
	local gEff = gBase * gScale
	localState.finalLandTumblePredAirTimeSec = if bounceVy > 0.5
		then math.clamp(2 * bounceVy / math.max(1e-4, gEff), 0.12, 8)
		else math.max(0.12, cfg.RUNWAY_FINAL_LAND_TUMBLE_NO_POP_ROLL_SEC)
	localState.jumpBoostVy = if bounceVy > 1e-5 then bounceVy else nil
	localState.jumpBoostUntilClock = if bounceVy > 1e-5 then nowClock + cfg.RUNWAY_JUMP_BOOST_HOLD_SEC else 0
	localState.finalLandCachedLandingAlong = localState.finalLandLockedTumbleAlong
	localState.finalLandCachedLandingVy = -math.max(0, bounceVy)
	Refs.finalLandTumbleStartHrpCf = CFrame.lookAt(hrp.Position, hrp.Position + faceFwdH, Vector3.yAxis)
	hrp.AssemblyLinearVelocity = fwdH * localState.finalLandLockedTumbleAlong + Vector3.new(0, bounceVy, 0)
	hrp.AssemblyAngularVelocity = hrp.AssemblyAngularVelocity * 0.25
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
	local _, humanoidDbg, _ = RunwaySession.GetCharacterParts()
	RunwaySession.DebugFinalLandPhaseA("enter_phase_b", humanoidDbg, hrp, nowClock)
	GameSoundManager.PlayImpactSound()
	localState.finalLandSubPhase = 2
	localState.finalLandPronePhaseStartClock = nowClock
	localState.finalLandTumbleAirAccumSec = math.max(
		localState.finalLandTumbleAirAccumSec,
		localState.finalLandTumblePredAirTimeSec
	)
	localState.finalLandPhaseAGroundedStartClock = nil
	if hrp ~= nil and forward ~= nil then
		localState.finalLandProneBStage = 1
		local fwdHInit = Vector3.new(forward.X, 0, forward.Z)
		if fwdHInit.Magnitude < 1e-4 then
			fwdHInit = Vector3.new(0, 0, -1)
		else
			fwdHInit = fwdHInit.Unit
		end
		local alongSpdEnter = RunwaySession.ResolveFinalLandAlongSpeedForPhaseB()
		localState.finalLandProneSlideAlongSpeedStart = alongSpdEnter
		RunwaySession.TransitionDistanceLogStage(
			"FinalLandB_ProneSlide",
			"enter_final_land_phase_b",
			hrp,
			string.format("alongSpeedStart=%.2f popCount=%d", alongSpdEnter, localState.finalLandPhaseAPopCount)
		)
		local landingVyForSlide = localState.finalLandCachedLandingVy
		if typeof(landingVyForSlide) ~= "number" or landingVyForSlide ~= landingVyForSlide then
			landingVyForSlide = hrp.AssemblyLinearVelocity.Y
		end
		Refs.slideMotion = RunwaySession.CreateFinalLandProneSlideMotion(
			nowClock,
			hrp.Position,
			fwdHInit,
			alongSpdEnter,
			landingVyForSlide :: number
		)
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		localState.finalLandProneSlideAlongStart = RunwaySession.CurrentAlongProgress(hrp)
		local chestFwdH = if localState.runwaySlideKind == SlideKindObstacleBounce
			then NormalizeRunwayForward(localState.runwayForward)
			else fwdHInit
		Refs.chestSlideFwdH = chestFwdH
		-- 记录本次跑道的沿轴距离，用于宝箱与怪物动态配置
		local alongAtPhaseB = RunwaySession.CurrentAlongProgress(hrp)
		Refs.lastRunAlongDistance = alongAtPhaseB
		-- 根据距离动态选择宝箱配置
		local chestByDist = GameConfig.GetLittleElfChestByDistance(alongAtPhaseB)
		local chestIdOverride = if chestByDist then chestByDist.id else nil
		Refs.chestDynamicConfigId = chestIdOverride
		if localState.runwaySlideKind == SlideKindObstacleBounce then
			Refs.chestPredictedPlaceDistance = 0
			Refs.chestScheduledSpawnPos = nil
			return
		end
		local placeDistance = RunwaySession.ResolveProneSlidePlaceDistance()
		Refs.chestPredictedPlaceDistance = placeDistance
		local spawnPos = RunwaySession.ComputeLittleElfChestSpawnPosition(hrp, fwdHInit, placeDistance)
		Refs.chestScheduledSpawnPos = spawnPos
		RunwaySession.ScheduleLittleElfChestAtPhaseBEnter(fwdHInit, spawnPos)
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
		if Refs.chestBounceActive == true then
			RunwaySession.ApplyChestBounceMotion(hrp, nowClock)
			return
		end
		if Refs.chestRewardWaitPose == true then
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			return
		end
		if Refs.slideMotion == nil then
			local alongStart = localState.finalLandProneSlideAlongSpeedStart
			if localState.runwaySlideKind == SlideKindMiss then
				Refs.slideMotion = RunwaySession.CreateMissSlideMotion(nowClock, hrp.Position, fwdH)
			else
				local landingVyForSlide = localState.finalLandCachedLandingVy
				if typeof(landingVyForSlide) ~= "number" or landingVyForSlide ~= landingVyForSlide then
					landingVyForSlide = hrp.AssemblyLinearVelocity.Y
				end
				Refs.slideMotion = RunwaySession.CreateFinalLandProneSlideMotion(
					nowClock,
					hrp.Position,
					fwdH,
					alongStart,
					landingVyForSlide :: number
				)
			end
		end
		RunwaySession.ApplyScriptedProneSlideMotion(hrp, nowClock)
		local motion = Refs.slideMotion
		if localState.runwaySlideKind == SlideKindObstacleBounce then
			if motion ~= nil and motion.lastDistance >= motion.totalDistance - 0.05 then
				RunwaySession.HandleObstacleBounceSlideStop(humanoid, hrp)
			end
			return
		end
		local chestModel = Refs.chestSpawnedModel
		if chestModel ~= nil and chestModel.Parent ~= nil and Refs.chestRunwayAwaitingExit ~= true then
			local reachedPathHit = motion ~= nil and motion.lastDistance >= motion.totalDistance - 0.05
			if reachedPathHit or RunwaySession.IsPlayerNearLittleElfChest(hrp, chestModel, fwdH) then
				local chestConfigId = if Refs.chestDynamicConfigId ~= nil then Refs.chestDynamicConfigId else cfg.RUNWAY_CHEST_CONFIG_ID
				RunwaySession.ProcessLittleElfChestHit(chestModel, fwdH, chestConfigId, reachedPathHit)
				return
			end
		end
		-- 子阶段 B 仅由宝箱撞击流程结束，不因低速提前 slideEndClock
		return
	end
	if not localState.finalLandTumbleImpulseApplied then
		local landingAlong, landingVy = RunwaySession.SampleFinalLandLandingAlongAndVy(hrp, fwdH)
		local cachedLandingAlong = localState.finalLandCachedLandingAlong
		if landingAlong < 1 and typeof(cachedLandingAlong) == "number" and cachedLandingAlong == cachedLandingAlong then
			landingAlong = math.max(landingAlong, cachedLandingAlong)
		end
		local vySource = "current"
		if localState.finalLandCachedLandingVy ~= nil then
			landingVy = localState.finalLandCachedLandingVy :: number
			vySource = "cached_falling"
		end
		local minAlongRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_MIN_ALONG_SPEED
		local minAlong = (typeof(minAlongRaw) == "number" and minAlongRaw == minAlongRaw and minAlongRaw >= 0) and minAlongRaw or 12
		local vyScriptMaxRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_TOUCHDOWN_SCRIPT_MAX_VY
		local vyScriptMax = -3
		if typeof(vyScriptMaxRaw) == "number" and vyScriptMaxRaw == vyScriptMaxRaw and vyScriptMaxRaw < -0.05 then
			vyScriptMax = vyScriptMaxRaw
		end
		if landingAlong < minAlong then
			RunwaySession.DebugFinalLandPhaseAPop(
				"skip_initial_pop_along_below_min",
				0,
				landingAlong,
				landingVy,
				vySource,
				0,
				0,
				nowClock
			)
			RunwaySession.StartFinalLandPronePhase(nowClock, hrp, forward)
			return
		end
		if landingVy > vyScriptMax then
			RunwaySession.DebugFinalLandPhaseAPop(
				"skip_initial_pop_vy_not_falling",
				0,
				landingAlong,
				landingVy,
				vySource,
				0,
				0,
				nowClock
			)
			RunwaySession.StartFinalLandPronePhase(nowClock, hrp, forward)
			return
		end
		RunwaySession.ApplyFinalLandPhaseAPop(hrp, fwdH, nowClock)
		RunwaySession.DebugFinalLandPhaseA("apply_first_pop", humanoid, hrp, nowClock)
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
	local looseGroundTrack = RunwaySession.IsRunwayFinalLandPhaseAGroundedLoose(humanoid, hrp)
	if looseGroundTrack then
		RunwaySession.DebugFinalLandPhaseA("physics_loose_ground_before_brake", humanoid, hrp, nowClock)
	end
	local boostedYForGround = RunwaySession.GetBoostedVerticalY(v.Y)
	if localState.finalLandTumbleUseAirClock then
		if not looseGroundTrack or boostedYForGround > FinalLandPhaseALeftGroundMinVy then
			localState.finalLandTumbleLeftGround = true
		end
	else
		localState.finalLandTumbleAirAccumSec += dt
	end
	local alongSpd = math.clamp(localState.finalLandLockedTumbleAlong, 0, cfg.ANTI_CHEAT_MAX_ALONG_SPEED)
	if
		looseGroundTrack
		and (not localState.finalLandTumbleUseAirClock or localState.finalLandTumbleLeftGround or boostedYForGround <= 0)
	then
		local brakeRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_GROUNDED_BRAKE_EXP
		local brakeK = (typeof(brakeRaw) == "number" and brakeRaw == brakeRaw and brakeRaw > 0) and brakeRaw or 2.4
		alongSpd *= math.exp(-brakeK * dt)
		localState.finalLandLockedTumbleAlong = alongSpd
		RunwaySession.DebugFinalLandPhaseA("physics_loose_ground_after_brake", humanoid, hrp, nowClock)
	end
	local vyPhaseA = boostedYForGround
	-- Physics 状态下 Humanoid 引擎会抵抗竖直速度；如果尚未离地且应有弹跳，保持最小离地速度
	if
		localState.finalLandTumbleUseAirClock
		and not localState.finalLandTumbleLeftGround
		and localState.finalLandPhaseAPopCount >= 1
		and not looseGroundTrack
	then
		local minVyKeep = cfg.RUNWAY_FINAL_LAND_PHASE_A_MIN_POP_VY
		vyPhaseA = math.max(vyPhaseA, minVyKeep)
	elseif
		looseGroundTrack
		and localState.finalLandTumbleUseAirClock
		and not localState.finalLandTumbleLeftGround
		and boostedYForGround <= 0
	then
		vyPhaseA = math.min(vyPhaseA, 0)
	end
	local horiz = HorizontalVelocity(v)
	local alongH = horiz:Dot(fwdH)
	local perpH = horiz - fwdH * alongH
	hrp.AssemblyLinearVelocity = fwdH * alongSpd + Vector3.new(0, vyPhaseA, 0) + perpH * perpMulFrame
end

function RunwaySession.ApplyFinalLandingRenderOrientation(
	humanoid: Humanoid,
	hrp: BasePart,
	forward: Vector3,
	dt: number,
	_nowClock: number,
	proneHeightOverride: number?
)
	local pos = hrp.Position
	local linVel = hrp.AssemblyLinearVelocity
	if Refs.finalLandTumbleStartHrpCf == nil then
		Refs.finalLandTumbleStartHrpCf = hrp.CFrame
	end
	if localState.finalLandSubPhase == 2 then
		local fallbackHeight = RunwaySession.ResolveProneHrpGroundHeight(
			cfg.RUNWAY_FINAL_LAND_PRONE_HRP_GROUND_HEIGHT,
			2.8
		)
		local proneLocked = RunwaySession.BuildProneRunwayCFrameAtGroundHeight(
			humanoid,
			hrp,
			forward,
			proneHeightOverride or cfg.RUNWAY_FINAL_LAND_PRONE_HRP_GROUND_HEIGHT,
			fallbackHeight
		)
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
	if localState.runwaySlideKind == SlideKindObstacleBounce then
		omega = -omega
	end
	localState.finalLandTumbleRollAngleRad += omega * dt
	local spun = RunwaySession.ComputeFinalLandTumbleSpunAt(pos, forward, localState.finalLandTumbleRollAngleRad)
	hrp.CFrame = spun
	hrp.AssemblyLinearVelocity = linVel
	hrp.AssemblyAngularVelocity = hrp.AssemblyAngularVelocity * math.exp(-14 * dt)
end

function RunwaySession.ApplyObstacleBounceSlideKindTransition(nowClock: number)
	if Refs.chestRunwayAwaitingExit ~= true and Refs.chestRewardPresentationStarted ~= true then
		if Refs.chestSpawnedForThisRun == true or Refs.chestScheduledSpawnPos ~= nil then
			Refs.chestSpawnDelayToken += 1
			RunwaySession.DestroyLittleElfChestSpawnedModel()
			Refs.chestSpawnedForThisRun = false
			Refs.chestScheduledSpawnPos = nil
			Refs.chestPredictedPlaceDistance = nil
		end
	end
	RunwaySession.DestroyRunwayRing()
	localState.runwaySlideKind = SlideKindObstacleBounce
	Refs.treeHitBlockedStartClock = nil
	Refs.treeHitBlockedStartAlong = nil
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
	localState.finalLandPhaseAGroundedStartClock = nil
	RunwaySession.ClearFinalLandingSlideModuleLocals()
	RunwaySession.ClearScriptedSlideMotion()
	localState.finalLandTumbleRollAngleRad = 0
	localState.finalLandProneBStage = 0
	localState.finalLandPronePrefallStartClock = 0
	localState.finalLandProneSlideAlongStart = nil
	localState.slideEndClock = nowClock + 7200
end

function RunwaySession.EnterSlidePhase(nowClock: number, slideKind: string, humanoidOpt: Humanoid?)
	if localState.phase == Ph.Slide then
		return
	end
	if slideKind == SlideKindStandard then
		RunwaySession.ApplyPlayerSlideCollisionGroup(localPlayer.Character)
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
	localState.jumpWindowGroundedStartClock = nil
	localState.chainJumpWindowAwaitingGround = false
	Refs.forwardBlockedStartClock = nil
	Refs.forwardBlockedStartAlong = nil
	Refs.treeHitBlockedStartClock = nil
	Refs.treeHitBlockedStartAlong = nil
	localState.slideStartClock = nowClock
	RunwaySession.ClearScriptedSlideMotion()
	RunwaySession.ClearChestBounceMotion()
	if slideKind == SlideKindFinalLanding then
		RunwaySession.TransitionDistanceLogStage("FinalLandA_Tumble", "enter_final_landing_slide", nil, "phaseBefore=" .. tostring(phaseBefore))
	elseif slideKind == SlideKindMiss then
		RunwaySession.TransitionDistanceLogStage("MissProneSlide", "enter_miss_slide", nil, "phaseBefore=" .. tostring(phaseBefore))
	else
		RunwaySession.TransitionDistanceLogStage("StandardSlide", "enter_standard_slide", nil, "phaseBefore=" .. tostring(phaseBefore))
	end
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
		localState.finalLandPhaseAGroundedStartClock = nil
		RunwaySession.ClearFinalLandingSlideModuleLocals()
		localState.slideEndClock = nowClock + 7200
		localState.finalLandTumbleRollAngleRad = 0
		localState.finalLandProneBStage = 0
		localState.finalLandPronePrefallStartClock = 0
		localState.finalLandProneSlideAlongStart = nil
		RunwaySession.EnsurePlatformStandForFinalLandSlide(humanoidOpt)
		if humanoidOpt ~= nil then
			RunwaySession.EnsureHumanoidFinalSlidePhysicsState(humanoidOpt)
		end
	elseif slideKind == SlideKindMiss then
		GameSoundManager.PlayImpactSound()
		RunwaySession.DestroyRunwayRing()
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
		localState.finalLandPhaseAGroundedStartClock = nil
		RunwaySession.ClearFinalLandingSlideModuleLocals()
		localState.finalLandTumbleRollAngleRad = 0
		localState.finalLandProneBStage = 1
		localState.finalLandPronePrefallStartClock = 0
		localState.finalLandProneSlideAlongStart = nil
		local alongSpd = RunwaySession.ResolveMissSlideStartSpeed()
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
		-- MISS: 与正常终局子阶段B一致，显示DistanceRecorder、生成宝箱与追击者
		local _, _, hrpMissChest = RunwaySession.GetCharacterParts()
		if hrpMissChest ~= nil then
			local fwdHMiss = NormalizeRunwayForward(localState.runwayForward)
			local fwdHChest = Vector3.new(fwdHMiss.X, 0, fwdHMiss.Z)
			if fwdHChest.Magnitude < 1e-4 then
				fwdHChest = Vector3.new(0, 0, -1)
			else
				fwdHChest = fwdHChest.Unit
			end
			Refs.slideMotion = RunwaySession.CreateMissSlideMotion(nowClock, hrpMissChest.Position, fwdHChest)
			Refs.chestSlideFwdH = fwdHChest
			local alongAtMiss = RunwaySession.CurrentAlongProgress(hrpMissChest)
			Refs.lastRunAlongDistance = alongAtMiss
			local chestByDist = GameConfig.GetLittleElfChestByDistance(alongAtMiss)
			local chestIdOverride = if chestByDist then chestByDist.id else nil
			Refs.chestDynamicConfigId = chestIdOverride
			RunwaySession.EnsureDistanceRecorderFromTemplate(humanoidOpt, hrpMissChest)
			local placeDistance = RunwaySession.ResolveProneSlidePlaceDistance()
			Refs.chestPredictedPlaceDistance = placeDistance
			local spawnPos = RunwaySession.ComputeLittleElfChestSpawnPosition(hrpMissChest, fwdHChest, placeDistance)
			Refs.chestScheduledSpawnPos = spawnPos
			RunwaySession.ScheduleLittleElfChestAtPhaseBEnter(fwdHChest, spawnPos)
		end
	elseif slideKind == SlideKindObstacleBounce then
		RunwaySession.ApplyObstacleBounceSlideKindTransition(nowClock)
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
		localState.finalLandPhaseAGroundedStartClock = nil
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

function RunwaySession.IsRunwayObstacleBounceSlidePhase(): boolean
	return localState.phase == Ph.Slide and localState.runwaySlideKind == SlideKindObstacleBounce
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
	if
		localState.phase == Ph.Slide
		and localState.runwaySlideKind == SlideKindObstacleBounce
		and (localState.finalLandSubPhase == 1 or localState.finalLandSubPhase == 2)
		and Refs.chestRewardWaitPose ~= true
	then
		return RUNWAY_LOCOMOTION_NONE
	end
	if Refs.chestRewardWaitPose == true then
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
	if not RunwaySession.IsRunwayFinalLandingSlidePhase() and not RunwaySession.IsRunwayObstacleBounceSlidePhase() then
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
		return RunwaySession.GetJumpHorizontalForwardSpeed(nowClock, seg, nil)
	end
	local _, minSpd = GameConfig.GetJumpRunwayJumpSpeedLimitsForSegment(
		seg,
		localState.jumpSpeedCumulativeRatingBonus,
		GetJumpPowerBaseSpeed(),
		localState.jumpSpeedCurrentReductionDelta
	)
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
	hrp.AssemblyLinearVelocity = fwdH * targetAlong + Vector3.new(0, v.Y, 0)
end

function RunwaySession.ApplyRunwayLocomotionAnimation(humanoid: Humanoid, forward: Vector3, nowClock: number, hrp: BasePart?)
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		RunwaySession.StopJumpWindowWalkAnimation()
		humanoid:Move(Vector3.zero, false)
		return
	end
	local mode = RunwaySession.ResolveRunwayLocomotionMode(humanoid, nowClock)
	if mode == RUNWAY_LOCOMOTION_NONE then
		RunwaySession.StopJumpWindowWalkAnimation()
		if Refs.chestRewardWaitPose ~= true then
			if RunwaySession.IsRunwayFinalLandingSlidePhase() or RunwaySession.IsRunwayObstacleBounceSlidePhase() then
				RunwaySession.EnsureHumanoidFinalSlidePhysicsState(humanoid)
			end
		end
		humanoid:Move(Vector3.zero, false)
		return
	end
	if mode == RUNWAY_LOCOMOTION_FREEFALL then
		RunwaySession.StopJumpWindowWalkAnimation()
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
		RunwaySession.StopJumpWindowWalkAnimation()
		RunwaySession.EnsureHumanoidRunningState(humanoid)
		humanoid:Move(forward, false)
		if hrp ~= nil then
			RunwaySession.MaybeCorrectGroundedAlongVelocity(hrp, forward, humanoid, nowClock)
		end
		return
	end
	RunwaySession.StopJumpWindowWalkAnimation()
	humanoid:Move(Vector3.zero, false)
end

-- 终局跳水平冲刺在 UpdateAutoRunVelocity 内与基底合并；此处仅处理冲刺向上加速度
function RunwaySession.UpdateDashVerticalOnly(hrp: BasePart, dt: number)
	if not RunwaySession.IsFinalDashThrustActive() then
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
	if Refs.jetpackVisualRoot ~= nil and Refs.jetpackVisualRoot:GetAttribute(JumpRunwayJetpackServerCreatedAttr) == true then
		return
	end
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
		GameSoundManager.StopJettingSound()
		RunwaySession.SetJetpackDashParticlesEnabled(false)
		RunwaySession.RestoreJetpackFlameIdleColors()
		return
	end
	local f1 = Refs.jetpackFlame1Part
	local f2 = Refs.jetpackFlame2Part
	if f1 == nil or f2 == nil or f1.Parent == nil or f2.Parent == nil then
		GameSoundManager.StopJettingSound()
		RunwaySession.SetJetpackDashParticlesEnabled(false)
		RunwaySession.RestoreJetpackFlameIdleColors()
		return
	end
	local dashFxActive = localState.phase == Ph.Airborne
		and localState.takeoffCount >= cfg.N_TOTAL_JUMPS
		and RunwaySession.IsFinalDashThrustActive()
	if not dashFxActive then
		GameSoundManager.StopJettingSound()
		RunwaySession.SetJetpackDashParticlesEnabled(false)
		RunwaySession.RestoreJetpackFlameIdleColors()
		return
	end
	GameSoundManager.PlayJettingSound()
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
	local rp = RunwaySession.BuildRunwayGroundRaycastParams(humanoid)
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

-- 链式近地区/倒计时门槛检测：dist <= baseline + RUNWAY_CHAIN_WINDOW_START_HEIGHT_STUDS
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
	local rp = RunwaySession.BuildRunwayGroundRaycastParams(humanoid)
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

function RunwaySession.GetFinalLandPhaseALooseTouchdownDistance(humanoid: Humanoid): number
	local touchdownDistRaw = cfg.RUNWAY_FINAL_LAND_TOUCHDOWN_FEET_MAX_DIST_STUDS
	local touchdownDist = (typeof(touchdownDistRaw) == "number" and touchdownDistRaw == touchdownDistRaw and touchdownDistRaw > 0)
		and touchdownDistRaw
		or 2
	local hipMultRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_LOOSE_TOUCHDOWN_HIP_MULT
	local hipMult = (typeof(hipMultRaw) == "number" and hipMultRaw == hipMultRaw and hipMultRaw > 0)
		and hipMultRaw
		or 1.5
	return math.max(touchdownDist, humanoid.HipHeight * hipMult + cfg.RUNWAY_GROUND_RAY_ORIGIN_Y)
end

function RunwaySession.IsRunwayFinalLandPhaseAGroundedLoose(humanoid: Humanoid, hrp: BasePart): boolean
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		return true
	end
	if RunwaySession.IsRunwayFinalLandFullBodyGrounded(humanoid, hrp) then
		return true
	end
	local okFeet, distFeet = RunwaySession.RaycastFeet(humanoid)
	if not okFeet then
		return false
	end
	return distFeet <= RunwaySession.GetFinalLandPhaseALooseTouchdownDistance(humanoid)
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

function RunwaySession.SlideTraceDisableTrailOnly()
	local trailMaybe = Refs.slideTraceTrail
	if trailMaybe ~= nil and trailMaybe.Parent ~= nil then
		trailMaybe.Enabled = false
	end
end

function RunwaySession.SlideTraceDestroyImpl()
	RunwaySession.SlideTraceDisableTrailOnly()
	if Refs.slideTraceRootInstance ~= nil then
		if Refs.slideTraceRootInstance.Parent ~= nil then
			Refs.slideTraceRootInstance:Destroy()
		end
		Refs.slideTraceRootInstance = nil
	end
	Refs.slideTraceAnchorPart = nil
	Refs.slideTraceTrail = nil
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
	RunwaySession.SlideTraceDisableTrailOnly()
	task.delay(RunwaySlideTraceDestroyAfterEndSec, function()
		RunwaySession.FireSlideTraceScheduledDestroyIfCurrent(scheduledAt)
	end)
end

function RunwaySession.SlideTraceResolveAnchorPartFromClone(clone: Instance): BasePart?
	if clone:IsA("BasePart") then
		return clone
	end
	if clone:IsA("Model") then
		local named = clone:FindFirstChild("AnchorPart")
		if named ~= nil and named:IsA("BasePart") then
			return named
		end
		local firstPart = clone:FindFirstChildWhichIsA("BasePart", true)
		if firstPart ~= nil then
			return firstPart
		end
	end
	return nil
end

function RunwaySession.SlideTraceResolveTrailFromAnchor(anchor: BasePart): Trail?
	for _, child in anchor:GetChildren() do
		if child:IsA("Trail") then
			local trail = child :: Trail
			if trail.Attachment0 ~= nil and trail.Attachment1 ~= nil then
				return trail
			end
		end
	end
	return nil
end

function RunwaySession.SlideTraceGetTemplate(): Instance?
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
				"[RunwaySession] ReplicatedStorage.Models missing; SlideTraceTrail skipped. Add Models.SlideTraceTrail in Studio."
			)
		end
		return nil
	end
	local template = modelsFolder:FindFirstChild(RunwaySlideTraceTemplateName)
	if template == nil or (not template:IsA("Model") and not template:IsA("BasePart")) then
		if not Refs.slideTraceTemplateWarned then
			Refs.slideTraceTemplateWarned = true
			warn(
				"[RunwaySession] ReplicatedStorage.Models.SlideTraceTrail missing or invalid; add AnchorPart + Trail template in Studio."
			)
		end
		return nil
	end
	local anchor = RunwaySession.SlideTraceResolveAnchorPartFromClone(template)
	if anchor == nil then
		if not Refs.slideTraceTemplateWarned then
			Refs.slideTraceTemplateWarned = true
			warn("[RunwaySession] SlideTraceTrail template has no AnchorPart BasePart.")
		end
		return nil
	end
	if RunwaySession.SlideTraceResolveTrailFromAnchor(anchor) == nil then
		if not Refs.slideTraceTemplateWarned then
			Refs.slideTraceTemplateWarned = true
			warn("[RunwaySession] SlideTraceTrail template missing Trail with Attachment0/Attachment1.")
		end
		return nil
	end
	Refs.slideTraceCachedTemplate = template
	return Refs.slideTraceCachedTemplate
end

function RunwaySession.SlideTraceRaycastGroundHit(hrp: BasePart, humanoid: Humanoid): RaycastResult?
	local origin = hrp.Position + Vector3.new(0, cfg.RUNWAY_GROUND_RAY_ORIGIN_Y, 0)
	local cast = Vector3.new(0, -cfg.RUNWAY_GROUND_PROBE_DOWN, 0)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local excludeList: { Instance } = {}
	local char = humanoid.Parent
	if char ~= nil and char:IsA("Model") then
		table.insert(excludeList, char)
	end
	local treeFolder = workspace:FindFirstChild("tree")
	if treeFolder ~= nil then
		table.insert(excludeList, treeFolder)
	end
	local localFx = workspace:FindFirstChild("JumpRunwayLocalFx")
	if localFx ~= nil then
		table.insert(excludeList, localFx)
	end
	if Refs.slideTraceRootInstance ~= nil then
		table.insert(excludeList, Refs.slideTraceRootInstance :: Instance)
	end
	rp.FilterDescendantsInstances = excludeList
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

function RunwaySession.SlideTraceEnsureAnchorFromTemplate(): boolean
	if Refs.slideTraceAnchorPart ~= nil and Refs.slideTraceAnchorPart.Parent ~= nil then
		return true
	end
	Refs.slideTraceRootInstance = nil
	Refs.slideTraceAnchorPart = nil
	Refs.slideTraceTrail = nil
	local tmpl = RunwaySession.SlideTraceGetTemplate()
	if tmpl == nil then
		return false
	end
	local clone = tmpl:Clone()
	local anchor = RunwaySession.SlideTraceResolveAnchorPartFromClone(clone)
	if anchor == nil then
		clone:Destroy()
		return false
	end
	local trail = RunwaySession.SlideTraceResolveTrailFromAnchor(anchor)
	if trail == nil then
		clone:Destroy()
		return false
	end
	clone.Name = "JumpRunwaySlideTrace"
	anchor.Name = "JumpRunwaySlideTraceAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	clone.Parent = RunwaySession.GetJumpRunwayLocalFxFolder()
	local lifetimeRaw = cfg.RUNWAY_SLIDE_TRACE_LIFETIME
	if typeof(lifetimeRaw) == "number" and lifetimeRaw == lifetimeRaw and lifetimeRaw > 0 then
		trail.Lifetime = lifetimeRaw
	end
	local minLenRaw = cfg.RUNWAY_SLIDE_TRACE_MIN_LENGTH
	if typeof(minLenRaw) == "number" and minLenRaw == minLenRaw and minLenRaw > 0 then
		trail.MinLength = minLenRaw
	end
	trail.Enabled = true
	Refs.slideTraceRootInstance = clone
	Refs.slideTraceAnchorPart = anchor
	Refs.slideTraceTrail = trail
	return true
end

function RunwaySession.SlideTraceHasActiveInstance(): boolean
	return Refs.slideTraceAnchorPart ~= nil or Refs.slideTraceRootInstance ~= nil
end

function RunwaySession.SlideTraceUpdate(humanoid: Humanoid, hrp: BasePart)
	if cfg.RUNWAY_SLIDE_TRACE_ENABLED ~= true then
		if RunwaySession.SlideTraceHasActiveInstance() then
			RunwaySession.SlideTraceDestroy()
		end
		return
	end
	local shouldTraces =
		localState.phase == Ph.Slide
		and (
			localState.runwaySlideKind == SlideKindFinalLanding
			or localState.runwaySlideKind == SlideKindMiss
			or localState.runwaySlideKind == SlideKindObstacleBounce
		)
		and localState.finalLandSubPhase == 2
		and localState.finalLandProneBStage >= 1
	if not shouldTraces then
		if RunwaySession.SlideTraceHasActiveInstance() then
			RunwaySession.SlideTraceDestroy()
		end
		return
	end
	if not RunwaySession.SlideTraceEnsureAnchorFromTemplate() then
		return
	end
	local forward = NormalizeRunwayForward(localState.runwayForward)
	local cf = RunwaySession.SlideTraceComputeWorldCFrame(hrp, humanoid, forward)
	if cf == nil then
		return
	end
	local anchor = Refs.slideTraceAnchorPart :: BasePart
	anchor.CFrame = cf
end

function RunwaySession.DestroyRunwayRing()
	if Refs.runwayRingPart ~= nil then
		Refs.runwayRingPart:Destroy()
		Refs.runwayRingPart = nil
	end
	Refs.ringLastGroundY = nil
	Refs.ringTrackStroke = nil
	Refs.ringFixedStroke = nil
	Refs.ringSmoothedColor = nil
end

function RunwaySession.ResolveBeginLineAlongMetrics(hrp: BasePart): (boolean, number, number)
	local _, beginLine = RunwaySession.ResolveSceneParts()
	if beginLine == nil or not beginLine:IsA("BasePart") or localState.runwayOrigin == nil then
		return false, 0, 0
	end
	local fwd = NormalizeRunwayForward(localState.runwayForward)
	local beginEdgeWorld = beginLine.CFrame * Vector3.new(beginLine.Size.X / 2, 0, 0)
	local beginEdgeAlong = (beginEdgeWorld - localState.runwayOrigin):Dot(fwd)
	local currentAlong = (hrp.Position - localState.runwayOrigin):Dot(fwd)
	local distToBegin = beginEdgeAlong - currentAlong
	local sessionStartAlong = localState.sessionStartAlong
	if sessionStartAlong == nil then
		sessionStartAlong = localState.alongBaseline or 0
	end
	local maxDist = beginEdgeAlong - sessionStartAlong
	return true, distToBegin, maxDist
end

function RunwaySession.ComputeRunwayRingTargetColorBeforeBeginLine(hrp: BasePart): Color3?
	if localState.phase ~= Ph.AutoRun or localState.passedBeginLineOnce then
		return nil
	end
	local yellow = cfg.RUNWAY_RING_COLOR_YELLOW
	local red = cfg.RUNWAY_RING_COLOR_RED
	local ok, distToBegin, maxDist = RunwaySession.ResolveBeginLineAlongMetrics(hrp)
	if not ok or maxDist <= 1e-4 then
		return yellow
	end
	local t = math.clamp(1 - distToBegin / maxDist, 0, 1)
	return yellow:Lerp(red, t)
end

function RunwaySession.ResolveRunwayRingFeetBandThresholds(): (number, number)
	local maxPreLandDist = cfg.RUNWAY_PRELAND_MAX_DIST_STUDS
	local maxChainDist = cfg.RUNWAY_CHAIN_WINDOW_START_HEIGHT_STUDS
	local baseline = localState.preLandRayBaselineStuds
	if typeof(baseline) == "number" and baseline == baseline then
		maxPreLandDist = baseline + cfg.RUNWAY_PRELAND_MAX_DIST_STUDS
		maxChainDist = baseline + cfg.RUNWAY_CHAIN_WINDOW_START_HEIGHT_STUDS
	end
	return maxPreLandDist, maxChainDist
end

function RunwaySession.ComputeRunwayRingTargetColorFromFeetDist(ok: boolean, dist: number): Color3
	local green = cfg.RUNWAY_RING_COLOR_GREEN
	local yellow = cfg.RUNWAY_RING_COLOR_YELLOW
	local red = cfg.RUNWAY_RING_COLOR_RED
	if not ok then
		return green
	end
	local maxPreLandDist, maxChainDist = RunwaySession.ResolveRunwayRingFeetBandThresholds()
	local fadeWidth = cfg.RUNWAY_RING_COLOR_GREEN_FADE_ABOVE_PRELAND_STUDS
	if fadeWidth <= 0 then
		fadeWidth = math.max(maxPreLandDist - maxChainDist, 1e-4)
	end
	local greenStart = maxPreLandDist + fadeWidth
	if dist >= greenStart then
		return green
	end
	if dist > maxPreLandDist then
		local t = math.clamp((dist - maxPreLandDist) / fadeWidth, 0, 1)
		return yellow:Lerp(green, t)
	end
	if dist <= maxChainDist then
		return red
	end
	local band = math.max(maxPreLandDist - maxChainDist, 1e-4)
	local t = math.clamp((dist - maxChainDist) / band, 0, 1)
	return red:Lerp(yellow, t)
end

function RunwaySession.CacheRunwayRingUiStrokes(ringPart: BasePart)
	Refs.ringTrackStroke = nil
	Refs.ringFixedStroke = nil
	local surfaceGui = ringPart:FindFirstChild("RingSurfaceGui")
	if surfaceGui == nil or not surfaceGui:IsA("SurfaceGui") then
		surfaceGui = ringPart:FindFirstChildOfClass("SurfaceGui")
	end
	if surfaceGui == nil then
		return
	end
	local rootFrame = surfaceGui:FindFirstChild("RingUiRootFrame")
	if rootFrame ~= nil and rootFrame:IsA("Frame") then
		local trackFrame = rootFrame:FindFirstChild("RingTrackFrame")
		if trackFrame ~= nil then
			local trackStroke = trackFrame:FindFirstChildOfClass("UIStroke")
			if trackStroke ~= nil then
				Refs.ringTrackStroke = trackStroke
			end
		end
		local fixedFrame = rootFrame:FindFirstChild("RingFixedFrame")
		if fixedFrame ~= nil then
			local fixedStroke = fixedFrame:FindFirstChildOfClass("UIStroke")
			if fixedStroke ~= nil then
				Refs.ringFixedStroke = fixedStroke
			end
		end
	end
	if Refs.ringTrackStroke ~= nil and Refs.ringFixedStroke ~= nil then
		return
	end
	for _, desc in surfaceGui:GetDescendants() do
		if desc:IsA("UIStroke") then
			if Refs.ringTrackStroke == nil then
				Refs.ringTrackStroke = desc
			elseif Refs.ringFixedStroke == nil then
				Refs.ringFixedStroke = desc
				break
			end
		end
	end
end

function RunwaySession.UpdateRunwayRingColor(humanoid: Humanoid, hrp: BasePart, dt: number)
	local trackStroke = Refs.ringTrackStroke
	if trackStroke == nil then
		return
	end
	local targetColor: Color3
	local beforeBeginColor = RunwaySession.ComputeRunwayRingTargetColorBeforeBeginLine(hrp)
	if beforeBeginColor ~= nil then
		targetColor = beforeBeginColor
	else
		local okFeet, distFeet = RunwaySession.RaycastFeet(humanoid)
		targetColor = RunwaySession.ComputeRunwayRingTargetColorFromFeetDist(okFeet, distFeet)
	end
	local smoothed = Refs.ringSmoothedColor
	if smoothed == nil or dt <= 0 then
		smoothed = targetColor
	else
		local rate = cfg.RUNWAY_RING_COLOR_SMOOTH_RATE
		local alpha = if rate <= 0 then 1 else 1 - math.exp(-rate * dt)
		smoothed = smoothed:Lerp(targetColor, alpha)
	end
	Refs.ringSmoothedColor = smoothed
	trackStroke.Color = smoothed
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
	RunwaySession.CacheRunwayRingUiStrokes(clone)
	Refs.ringSmoothedColor = nil
	Refs.runwayRingPart = clone
end

function RunwaySession.UpdateRunwayRingTransform(humanoid: Humanoid, hrp: BasePart, dt: number)
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
		-- AutoRun 且未过 BeginLine：根据距 BeginLine 负 X 边缘的沿轴距离缩放
		local okBegin, distToBegin, maxDist = RunwaySession.ResolveBeginLineAlongMetrics(hrp)
		if okBegin and distToBegin > 0 and maxDist > 1e-4 then
			local beginMaxMul = cfg.RUNWAY_RING_BEGINLINE_MAX_MULTIPLIER
			local t = math.clamp(distToBegin / maxDist, 0, 1)
			sizeMul = 1 + (beginMaxMul - 1) * t
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
	RunwaySession.UpdateRunwayRingColor(humanoid, hrp, dt)
end

function RunwaySession.ResetDistanceRecorderDistanceTracking()
	Refs.runwayDistanceRecorderPeakStuds = 0
	Refs.runwayDistanceRecorderFrozenStuds = nil
	Refs.runwayBestDistanceCommitted = false
end

function RunwaySession.RefreshDistanceRecorderPeak(hrp: BasePart)
	local live = RunwaySession.CurrentAlongProgress(hrp)
	local peak = Refs.runwayDistanceRecorderPeakStuds or 0
	if live > peak then
		Refs.runwayDistanceRecorderPeakStuds = live
	end
end

function RunwaySession.GetDistanceRecorderDisplayStuds(hrp: BasePart): number
	local frozen = Refs.runwayDistanceRecorderFrozenStuds
	if frozen ~= nil then
		return frozen
	end
	RunwaySession.RefreshDistanceRecorderPeak(hrp)
	return Refs.runwayDistanceRecorderPeakStuds or 0
end

function RunwaySession.CommitRunwayBestDistanceFromDistanceRecorder(hrpOpt: BasePart?)
	if Refs.runwayBestDistanceCommitted == true then
		return
	end
	if hrpOpt ~= nil then
		RunwaySession.RefreshDistanceRecorderPeak(hrpOpt)
	end
	local peak = Refs.runwayDistanceRecorderPeakStuds
	if peak == nil or peak <= 0 then
		return
	end
	Refs.runwayBestDistanceCommitted = true
	Refs.runwayDistanceRecorderFrozenStuds = peak
	ClientGameInfo.UpdateJumpRunwayBestDistance(peak)
	NetMsg.FireRequestJumpRunwayBestDistance(peak)
	local lbl = Refs.runwayDistanceRecorderText
	if lbl ~= nil and lbl.Parent ~= nil then
		if hrpOpt ~= nil then
			RunwaySession.ApplyDistanceRecorderDisplay(lbl, hrpOpt)
		else
			local metersWhole = math.floor(peak + 0.5)
			if metersWhole <= 0 then
				lbl.Visible = false
			else
				lbl.Visible = true
				local tip = GameTexts.JumpRunwayDistanceMeters
				TranslationTool.CustomAutoLocalizeTextLabel(lbl, tip.source, tip.key, { tostring(metersWhole) })
			end
		end
	end
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
	RunwaySession.ResetDistanceRecorderDistanceTracking()
end

function RunwaySession.DestroyBestDistanceWall()
	Refs.bestDistanceWallDestroyToken += 1
	if Refs.bestDistanceWallModel ~= nil then
		Refs.bestDistanceWallModel:Destroy()
		Refs.bestDistanceWallModel = nil
	end
	Refs.bestDistanceWallDistance = nil
	Refs.bestDistanceWallPart = nil
	Refs.bestDistanceWallText = nil
	Refs.bestDistanceWallPassed = false
end

function RunwaySession.DestroyJumpRunwayRocketBackpack()
	if Refs.jetpackVisualRoot ~= nil then
		if Refs.jetpackVisualRoot:GetAttribute(JumpRunwayJetpackServerCreatedAttr) ~= true then
			Refs.jetpackVisualRoot:Destroy()
		end
		Refs.jetpackVisualRoot = nil
	end
	table.clear(Refs.jetpackDashParticleEmitters)
	Refs.jetpackFlame1Part = nil
	Refs.jetpackFlame2Part = nil
	Refs.jetpackFlame1IdleColor = nil
	Refs.jetpackFlame2IdleColor = nil
	if Refs.rocketBackpackPart ~= nil then
		if Refs.rocketBackpackPart:GetAttribute(JumpRunwayJetpackServerCreatedAttr) ~= true then
			Refs.rocketBackpackPart:Destroy()
		end
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
	if RunwaySession.IsFinalDashThrustActive() then
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

-- 取消锚点后，未与 PrimaryPart 同装配的 Part 会散落/掉落；在移动 PrimaryPart 之前焊上，保留模板相对位姿。
function RunwaySession.WeldAllRunwayJetpackPartsToPrimaryPart(jetpackRoot: Model, primaryPart: BasePart)
	for _, d in jetpackRoot:GetDescendants() do
		if d:IsA("BasePart") then
			local bp = d :: BasePart
			if bp ~= primaryPart and not RunwaySession.JetpackPartsShareWeldConstraint(bp, primaryPart) then
				local w = Instance.new("WeldConstraint")
				w.Part0 = primaryPart
				w.Part1 = bp
				w.Parent = bp
			end
		end
	end
end

function RunwaySession.TryAdoptServerJumpRunwayJetpack(character: Model): boolean
	local serverModel = character:FindFirstChild(JumpRunwayJetpackModelName)
	if serverModel ~= nil and serverModel:IsA("Model") and serverModel:GetAttribute(JumpRunwayJetpackServerCreatedAttr) == true then
		local model = serverModel :: Model
		Refs.jetpackVisualRoot = model
		Refs.rocketBackpackPart = nil
		table.clear(Refs.jetpackDashParticleEmitters)
		local flame1 = JetpackModelTool.FindJetpackModelPart(model, cfg.RUNWAY_JETPACK_FLAME1_NAME)
		local flame2 = JetpackModelTool.FindJetpackModelPart(model, cfg.RUNWAY_JETPACK_FLAME2_NAME)
		if flame1 ~= nil then
			Refs.jetpackFlame1Part = flame1
			Refs.jetpackFlame1IdleColor = flame1.Color
		end
		if flame2 ~= nil then
			Refs.jetpackFlame2Part = flame2
			Refs.jetpackFlame2IdleColor = flame2.Color
		end
		return true
	end
	local serverFallback = character:FindFirstChild(JumpRunwayRocketBackpackPartName)
	if serverFallback ~= nil
		and serverFallback:IsA("BasePart")
		and serverFallback:GetAttribute(JumpRunwayJetpackServerCreatedAttr) == true
	then
		Refs.rocketBackpackPart = serverFallback :: BasePart
		Refs.jetpackVisualRoot = nil
		table.clear(Refs.jetpackDashParticleEmitters)
		Refs.jetpackFlame1Part = nil
		Refs.jetpackFlame2Part = nil
		Refs.jetpackFlame1IdleColor = nil
		Refs.jetpackFlame2IdleColor = nil
		return true
	end
	return false
end

function RunwaySession.EnsureJumpRunwayRocketBackpack(character: Model)
	if not RunwaySession.HasEquippedJetpack() then
		return
	end
	if RunwaySession.TryAdoptServerJumpRunwayJetpack(character) then
		return
	end
	local waitedServerModel = character:WaitForChild(JumpRunwayJetpackModelName, 1)
	if waitedServerModel ~= nil then
		RunwaySession.TryAdoptServerJumpRunwayJetpack(character)
	end
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
	RunwaySession.ResetDistanceRecorderDistanceTracking()
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
	RunwaySession.ApplyDistanceRecorderDisplay(abilityLabel, hrp)
end

function RunwaySession.ApplyDistanceRecorderDisplay(lbl: TextLabel, hrp: BasePart)
	local studs = RunwaySession.GetDistanceRecorderDisplayStuds(hrp)
	if studs <= 0 then
		lbl.Visible = false
		return
	end
	lbl.Visible = true
	local metersWhole = math.floor(studs + 0.5)
	local tip = GameTexts.JumpRunwayDistanceMeters
	TranslationTool.CustomAutoLocalizeTextLabel(lbl, tip.source, tip.key, { tostring(metersWhole) })
end

function RunwaySession.UpdateDistanceRecorder(humanoid: Humanoid, hrp: BasePart)
	if ClientGameInfo.IsInJumpRunwayEscapePhase() then
		return
	end
	local part = Refs.runwayDistanceRecorderPart
	if part == nil or part.Parent == nil then
		return
	end
	local worldCenter = RunwaySession.GetDistanceRecorderWorldCenter(hrp, humanoid, part)
	part.Position = worldCenter
	local lbl = Refs.runwayDistanceRecorderText
	if lbl ~= nil and lbl.Parent ~= nil then
		RunwaySession.ApplyDistanceRecorderDisplay(lbl, hrp)
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

function RunwaySession.EnsureBestDistanceWall(forward: Vector3, origin: Vector3, scoreBaselineAlong: number)
	RunwaySession.DestroyBestDistanceWall()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil then
		return
	end
	local bestDistance = localPlayerInfo.jumpRunwayBestDistance
	if bestDistance == nil or bestDistance <= 0 then
		return
	end
	local template = modelsFolder:FindFirstChild("BestDistanceWallModel")
	if template == nil then
		warn("[RunwaySession] BestDistanceWallModel not found in ReplicatedStorage.Models")
		return
	end
	if not template:IsA("Model") then
		warn("[RunwaySession] BestDistanceWallModel under ReplicatedStorage.Models must be a Model")
		return
	end
	local wallTemplate = template :: Model
	local wallModel = wallTemplate:Clone()
	wallModel.Name = "BestDistanceWallModel"
	wallModel.Parent = workspace

	local primaryPart = wallModel.PrimaryPart
	if primaryPart == nil then
		warn("[RunwaySession] BestDistanceWallModel.PrimaryPart missing")
		wallModel:Destroy()
		return
	end
	local wallHeight = cfg.BEST_DISTANCE_WALL_HEIGHT_Y
	local pos = origin + forward * (scoreBaselineAlong + bestDistance)
	local targetPosition = Vector3.new(pos.X, wallHeight, BestDistanceWallLockedZ)
	local modelMoveDelta = targetPosition - primaryPart.Position
	wallModel:PivotTo(wallModel:GetPivot() + modelMoveDelta)

	Refs.bestDistanceWallPart = nil
	Refs.bestDistanceWallText = nil
	local wallPart = wallModel:FindFirstChild("BestDistanceWall")
	if wallPart ~= nil and wallPart:IsA("BasePart") then
		local wallBase = wallPart :: BasePart
		wallBase.Anchored = true
		wallBase.CanCollide = false
		wallBase.CanTouch = false
		Refs.bestDistanceWallPart = wallBase

		local ui = wallBase:FindFirstChild("UI")
		if ui ~= nil and ui:IsA("SurfaceGui") then
			local controllerFrame = ui:FindFirstChild("ControllerFrame")
			if controllerFrame ~= nil and controllerFrame:IsA("Frame") then
				local textLabel = controllerFrame:FindFirstChild("Text")
				if textLabel ~= nil and textLabel:IsA("TextLabel") then
					local text = textLabel :: TextLabel
					text.AnchorPoint = Vector2.new(0.5, 0.5)
					Refs.bestDistanceWallText = text
				end
			end
		end
	else
		warn("[RunwaySession] BestDistanceWallModel.BestDistanceWall missing or not a BasePart")
	end

	Refs.bestDistanceWallModel = wallModel
	Refs.bestDistanceWallDistance = bestDistance
	Refs.bestDistanceWallPassed = false
end

local function MapWorldPosToBestDistanceWallSurfaceNorms(
	wallPart: BasePart,
	face: Enum.NormalId,
	worldPos: Vector3
): (number?, number?)
	local localPos = wallPart.CFrame:PointToObjectSpace(worldPos)
	local size = wallPart.Size
	local xNorm: number
	local yNorm: number
	if face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		if size.Z < 1e-4 or size.Y < 1e-4 then
			return nil, nil
		end
		xNorm = (localPos.Z / size.Z) + 0.5
		yNorm = (localPos.Y / size.Y) + 0.5
	elseif face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		if size.X < 1e-4 or size.Z < 1e-4 then
			return nil, nil
		end
		xNorm = (localPos.X / size.X) + 0.5
		yNorm = (localPos.Z / size.Z) + 0.5
	else
		if size.X < 1e-4 or size.Y < 1e-4 then
			return nil, nil
		end
		xNorm = (localPos.X / size.X) + 0.5
		yNorm = (localPos.Y / size.Y) + 0.5
	end
	return xNorm, yNorm
end

local function ShouldTickBestDistanceWall(): boolean
	if Refs.bestDistanceWallModel == nil or Refs.bestDistanceWallPassed then
		return false
	end
	return ClientGameInfo.IsInJumpRunway() or ClientGameInfo.IsInJumpRunwayEscapePhase()
end

function RunwaySession.TickBestDistanceWallIfNeeded()
	if not ShouldTickBestDistanceWall() then
		return
	end
	local _, _, hrp = RunwaySession.GetCharacterParts()
	if hrp == nil then
		return
	end
	RunwaySession.UpdateBestDistanceWallText(hrp)
	if not ClientGameInfo.IsInJumpRunwayEscapePhase() then
		RunwaySession.UpdateBestDistanceWall(hrp)
	end
end

function RunwaySession.UpdateBestDistanceWallText(hrp: BasePart)
	if Refs.bestDistanceWallPassed then
		return
	end
	local wallPart = Refs.bestDistanceWallPart
	local textLabel = Refs.bestDistanceWallText
	if wallPart == nil or wallPart.Parent == nil or textLabel == nil or textLabel.Parent == nil then
		return
	end
	local ui = wallPart:FindFirstChild("UI")
	local face = Enum.NormalId.Front
	if ui ~= nil and ui:IsA("SurfaceGui") then
		face = (ui :: SurfaceGui).Face
	end
	local xNorm, yNorm = MapWorldPosToBestDistanceWallSurfaceNorms(wallPart, face, hrp.Position)
	if xNorm == nil or yNorm == nil then
		return
	end
	xNorm = math.clamp(xNorm, BestDistanceWallTextXMinNorm, BestDistanceWallTextXMaxNorm)
	yNorm = math.clamp(yNorm, BestDistanceWallTextYMinNorm, BestDistanceWallTextYMaxNorm)
	local pos = textLabel.Position
	textLabel.Position = UDim2.new(xNorm, pos.X.Offset, 1 - yNorm, pos.Y.Offset)
end

function RunwaySession.UpdateBestDistanceWall(hrp: BasePart)
	local wallModel = Refs.bestDistanceWallModel
	local wallDistance = Refs.bestDistanceWallDistance
	if wallModel == nil or wallDistance == nil or Refs.bestDistanceWallPassed then
		return
	end
	if RunwaySession.CurrentAlongProgress(hrp) < wallDistance then
		return
	end
	Refs.bestDistanceWallPassed = true
	ClientMsg.FireJumpRunWayShowNewRecordTip()
	Refs.bestDistanceWallDestroyToken += 1
	local destroyToken = Refs.bestDistanceWallDestroyToken
	task.delay(BestDistanceWallDestroyDelaySec, function()
		if destroyToken ~= Refs.bestDistanceWallDestroyToken then
			return
		end
		RunwaySession.DestroyBestDistanceWall()
	end)
end

function RunwaySession.ResetLocalRunToIdle()
	ClientMsg.FireJumpRunWayStopEscapeRedScreen()
	local _, humanoid, hrp = RunwaySession.GetCharacterParts()
	ClientGameInfo.SetInJumpRunwayEscapePhase(false)
	ClientGameInfo.SetInJumpRunway(false)
	RunwaySession.ClearRunwayGuideSlowMotion()
	RunwaySession.ResetFinalJumpGuideSlowMotionApexGate()
	RunwaySession.PrintDistanceLogSummary("reset_to_idle", hrp)
	-- 先同步清理资源和状态（避免异步延迟导致新一局启动后资源混乱）
	RunwaySession.StopJumpWindowWalkAnimation()
	RunwaySession.DestroyJumpRunwayRocketBackpack()
	RunwaySession.RestorePlayerSlideCollisionGroup()
	RunwayCameraController.Disable(workspace, GetCharacterParts)
	RunwaySession.DestroyRunwayGravityForce()
	RunwayStateStore.ResetForIdle(localState, Ph, SlideKindStandard)
	RunwaySession.ClearJumpHorizontalLerp()
	RunwaySession.DestroyRunwayRing()
	RunwaySession.ClearLittleElfChestRefs()
	Refs.chestCarryReturnActive = false
	Refs.missAbortSentForThisRun = nil
	Refs.forwardBlockedStartClock = nil
	Refs.forwardBlockedStartAlong = nil
	Refs.lastRunwayTakeoffClock = nil
	Refs.slideEndFallbackWarnNextClock = 0
	RunwaySession.ClearScriptedSlideMotion()
	RunwaySession.ClearChestBounceMotion()
	RunwaySession.DestroyDistanceRecorder()
	RunwaySession.DestroyBestDistanceWall()
	RunwaySession.SlideTraceScheduleDestroyAfterRunwayEnd()
	RunwayUiController.Destroy(RunwaySession.HudDestroy)
	UIManager.CloseWindow(UIManager.WindowId.JumpRunWayFrame)
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

function RunwaySession.IsJumpWindowStableGrounded(humanoid: Humanoid, nowClock: number): boolean
	if not RunwaySession.IsRunwayScriptedGrounded(humanoid) then
		localState.jumpWindowGroundedStartClock = nil
		return false
	end
	if localState.jumpWindowGroundedStartClock == nil then
		localState.jumpWindowGroundedStartClock = nowClock
	end
	local holdSec = cfg.RUNWAY_JUMP_WINDOW_GROUNDED_HOLD_SEC
	if typeof(holdSec) ~= "number" or holdSec ~= holdSec or holdSec < 0 then
		holdSec = 0.12
	end
	return nowClock - (localState.jumpWindowGroundedStartClock :: number) >= holdSec
end

function RunwaySession.CancelJumpWindowTimeoutUntilGroundedAgain()
	localState.lineJumpWindowExpireAt = nil
	localState.predictJumpWindowUntil = nil
	localState.tHudStart = nil
	localState.firstGroundedInWindowClock = nil
	localState.jumpWindowGroundedStartClock = nil
end

-- 线窗触线后仍按稳定贴地启动；链式窗按近地区高度阈值启动，避免刚进 preland 就开始计时。
function RunwaySession.MaybeStartJumpWindowTiming(humanoid: Humanoid, nowClock: number)
	if localState.phase == Ph.JumpWindow and not localState.lineWindowConsumed and localState.tHudStart == nil then
		if not RunwaySession.IsJumpWindowStableGrounded(humanoid, nowClock) then
			return
		end
		localState.tHudStart = nowClock
		localState.lineJumpWindowExpireAt = nowClock + cfg.T_WINDOW
		return
	end
	local chainSeg = localState.phase == Ph.Airborne
		and localState.takeoffCount >= 1
		and localState.takeoffCount < cfg.N_TOTAL_JUMPS
	if chainSeg and localState.chainJumpWindowAwaitingGround then
		if
			not RunwaySession.IsRunwayJumpWindowRayBandOk(humanoid)
			or not RunwaySession.IsRunwayChainWindowHeightOk(humanoid)
		then
			return
		end
		if not RunwaySession.IsRunwayScriptedGrounded(humanoid) then
			return
		end
		if localState.tHudStart == nil then
			localState.tHudStart = nowClock
		end
		localState.predictJumpWindowUntil = nowClock + cfg.T_WINDOW
		localState.chainJumpWindowAwaitingGround = false
	elseif chainSeg and localState.predictJumpWindowUntil == nil then
		if
			not RunwaySession.IsRunwayJumpWindowRayBandOk(humanoid)
			or not RunwaySession.IsRunwayChainWindowHeightOk(humanoid)
		then
			return
		end
		if not RunwaySession.IsRunwayScriptedGrounded(humanoid) then
			return
		end
		if localState.tHudStart == nil then
			localState.tHudStart = nowClock
		end
		localState.predictJumpWindowUntil = nowClock + cfg.T_WINDOW
		localState.chainJumpWindowAwaitingGround = false
	end
end

function RunwaySession.UpdateLocalJumpWindowPrediction(humanoid: Humanoid, nowClock: number)
	local bandOk = RunwaySession.IsRunwayJumpWindowRayBandOk(humanoid)
	local pre = RunwaySession.IsRunwayPreLanding(humanoid)
	local g = RunwaySession.IsRunwayScriptedGrounded(humanoid)
	local lineOrChainContext = localState.phase == Ph.Airborne and localState.takeoffCount >= 1 and localState.takeoffCount < cfg.N_TOTAL_JUMPS
	if localState.phase == Ph.JumpWindow and not g then
		RunwaySession.CancelJumpWindowTimeoutUntilGroundedAgain()
	end
	if lineOrChainContext then
		if not bandOk and localState.predictJumpWindowUntil == nil then
			localState.chainJumpWindowAwaitingGround = false
			localState.tHudStart = nil
			localState.jumpWindowGroundedStartClock = nil
		end
		local armEdge = bandOk and not localState.prevJumpWindowRayBand
		if armEdge then
			localState.firstGroundedInWindowClock = nil
			localState.chainJumpWindowAwaitingGround = true
			localState.predictJumpWindowUntil = nil
			localState.tHudStart = nil
			localState.jumpWindowGroundedStartClock = nil
		end
		if localState.chainJumpWindowAwaitingGround then
			RunwaySession.MaybeStartJumpWindowTiming(humanoid, nowClock)
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
		if
			localState.phase == Ph.Airborne
			and localState.takeoffCount >= 1
			and localState.takeoffCount < cfg.N_TOTAL_JUMPS
			and g
		then
			ClientMsg.FireJumpRunWayShowMiss()
			RunwaySession.EnterSlidePhase(nowClock, SlideKindMiss, humanoid)
			localState.predictJumpWindowUntil = nil
			localState.chainJumpWindowAwaitingGround = false
		end
		return
	end
	if (RunwaySession.LineHudActive(nowClock) or RunwaySession.ChainHudActive(nowClock)) and bandOk and g then
		if localState.firstGroundedInWindowClock == nil then
			localState.firstGroundedInWindowClock = nowClock
		end
	elseif not RunwaySession.LineHudActive(nowClock) and not RunwaySession.ChainHudActive(nowClock) then
		localState.firstGroundedInWindowClock = nil
	end
	RunwaySession.MaybeStartJumpWindowTiming(humanoid, nowClock)
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
	if localState.phase == Ph.Slide and Refs.chestRewardWaitPose == true then
		RunwaySession.ApplyExpectedWalkSpeedAfterRunway(humanoid)
		return
	end
	if
		localState.phase == Ph.Slide
		and (
			localState.runwaySlideKind == SlideKindFinalLanding
			or localState.runwaySlideKind == SlideKindMiss
			or localState.runwaySlideKind == SlideKindObstacleBounce
		)
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
			local wWalk = cfg.JUMP_WINDOW_WALK_SPEED * RunwaySession.GetGuideSlowMotionScale()
			if humanoid.WalkSpeed ~= wWalk then
				humanoid.WalkSpeed = wWalk
			end
			return
		end
		if locMode == RUNWAY_LOCOMOTION_RUN then
			local wRun = RunwaySession.GetRunwayTargetGroundAlongSpeed(humanoid, nowClock) * RunwaySession.GetGuideSlowMotionScale()
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
		local wDrift = cfg.JUMP_WINDOW_WALK_SPEED * RunwaySession.GetGuideSlowMotionScale()
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
			GetJumpPowerBaseSpeed(),
			localState.jumpSpeedCurrentReductionDelta
		)
		w = minSpd
	end
	w *= RunwaySession.GetGuideSlowMotionScale()
	if humanoid.WalkSpeed ~= w then
		humanoid.WalkSpeed = w
	end
end

function RunwaySession.IsGuideStepDone(stepKey: string): boolean
	if Refs.guideSlowMotionLocallyCompletedStepKeys[stepKey] == true then
		return true
	end
	local info = ClientGameInfo.GetLocalPlayerInfo()
	if info == nil then
		return false
	end
	return info.guideProgressInfo.guideStepDoneMap[stepKey] == true
end

function RunwaySession.RestoreGuideSlowMotionAnimatorTracks()
	for track, baseSpeed in guideSlowMotionAnimBaseSpeedMap do
		if track.Parent ~= nil then
			pcall(function()
				track:AdjustSpeed(baseSpeed)
			end)
		end
	end
	table.clear(guideSlowMotionAnimBaseSpeedMap)
end

function RunwaySession.ApplyGuideSlowMotionAnimatorScale(humanoid: Humanoid)
	if not Refs.guideSlowMotionActive or not RunwaySession.IsRunwayActivePhase(localState.phase) then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		return
	end
	local customWalkTrack = Refs.jumpWindowWalkAnimTrack
	for _, track in animator:GetPlayingAnimationTracks() do
		if track == customWalkTrack then
			continue
		end
		if not GuideSlowMotionAnimPriorities[track.Priority] then
			continue
		end
		local baseSpeed = guideSlowMotionAnimBaseSpeedMap[track]
		if baseSpeed == nil then
			baseSpeed = track.Speed
			guideSlowMotionAnimBaseSpeedMap[track] = baseSpeed
		end
		local targetSpeed = math.max(baseSpeed * GuideSlowMotionSpeedScale, 0.05)
		if math.abs(track.Speed - targetSpeed) > 1e-4 then
			track:AdjustSpeed(targetSpeed)
		end
	end
end

function RunwaySession.OnGuideSlowMotionAnimRenderStep(_dt: number)
	if not Refs.guideSlowMotionActive or not RunwaySession.IsRunwayActivePhase(localState.phase) then
		return
	end
	local _character, humanoid, _hrp = RunwaySession.GetCharacterParts()
	if humanoid == nil then
		return
	end
	RunwaySession.ApplyGuideSlowMotionAnimatorScale(humanoid)
end

function RunwaySession.ResetFinalJumpGuideSlowMotionApexGate()
	Refs.finalJumpGuideSlowMotionApexReady = false
	Refs.finalJumpGuideSlowMotionAscentSeen = false
	Refs.finalJumpGuideSlowMotionPrevRawVy = nil
end

function RunwaySession.UpdateFinalJumpGuideSlowMotionApexGate(hrp: BasePart)
	if localState.phase ~= Ph.Airborne or localState.takeoffCount < cfg.N_TOTAL_JUMPS then
		RunwaySession.ResetFinalJumpGuideSlowMotionApexGate()
		return
	end
	if Refs.finalJumpGuideSlowMotionApexReady then
		return
	end
	if RunwaySession.IsGuideStepDone(GameConfig.GuideStepKey.FinalDashFinished) then
		Refs.finalJumpGuideSlowMotionApexReady = true
		return
	end
	local rawVy = hrp.AssemblyLinearVelocity.Y
	if rawVy > 0 then
		Refs.finalJumpGuideSlowMotionAscentSeen = true
	end
	local prevVy = Refs.finalJumpGuideSlowMotionPrevRawVy
	Refs.finalJumpGuideSlowMotionPrevRawVy = rawVy
	if Refs.finalJumpGuideSlowMotionAscentSeen and prevVy ~= nil and prevVy > 0 and rawVy <= 0 then
		Refs.finalJumpGuideSlowMotionApexReady = true
	end
end

function RunwaySession.IsFinalJumpGuideSlowMotionApexReady(): boolean
	return Refs.finalJumpGuideSlowMotionApexReady
end

function RunwaySession.SetRunwayGuideSlowMotion(guideType: number, stepKey: string)
	if RunwaySession.IsGuideStepDone(stepKey) then
		return
	end
	if Refs.guideSlowMotionActive and Refs.guideSlowMotionStepKey == stepKey then
		return
	end
	Refs.guideSlowMotionActive = true
	Refs.guideSlowMotionStepKey = stepKey
	Refs.guideSlowMotionGuideType = guideType
	ClientGameInfo.SetCurrentGuideType(guideType)
	if stepKey == GameConfig.GuideStepKey.FinalDashFinished then
		local _character, _humanoid, hrp = RunwaySession.GetCharacterParts()
		localState.dashHeld = false
		localState.finalDashAlongExtra = 0
		Refs.guideSlowMotionFreezePosition = if hrp ~= nil then hrp.Position else nil
		RunwaySession.NetReportDashIfChanged()
	end
end

function RunwaySession.ClearRunwayGuideSlowMotion()
	Refs.guideSlowMotionActive = false
	Refs.guideSlowMotionStepKey = nil
	Refs.guideSlowMotionGuideType = GameConfig.GuideType.None
	Refs.guideSlowMotionFreezePosition = nil
	RunwaySession.RestoreGuideSlowMotionAnimatorTracks()
	if ClientGameInfo.GetCurrentGuideType() == GameConfig.GuideType.TutorialBeginLineJump
		or ClientGameInfo.GetCurrentGuideType() == GameConfig.GuideType.TutorialLandingJump
		or ClientGameInfo.GetCurrentGuideType() == GameConfig.GuideType.TutorialFinalDash
	then
		ClientGameInfo.SetCurrentGuideType(GameConfig.GuideType.None)
	end
end

function RunwaySession.CompleteActiveRunwayGuideSlowMotion()
	local stepKey = Refs.guideSlowMotionStepKey
	if stepKey ~= nil then
		Refs.guideSlowMotionLocallyCompletedStepKeys[stepKey] = true
		NetMsg.FireRequestCompleteGuideStep(stepKey)
	end
	RunwaySession.ClearRunwayGuideSlowMotion()
end

function RunwaySession.RefreshRunwayGuideSlowMotionState()
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		RunwaySession.ClearRunwayGuideSlowMotion()
		return
	end
	if localState.phase == Ph.JumpWindow
		and not RunwaySession.IsGuideStepDone(GameConfig.GuideStepKey.BeginLineJumpFinished)
	then
		RunwaySession.SetRunwayGuideSlowMotion(
			GameConfig.GuideType.TutorialBeginLineJump,
			GameConfig.GuideStepKey.BeginLineJumpFinished
		)
	elseif localState.phase == Ph.Airborne
		and localState.takeoffCount >= 1
		and localState.takeoffCount < cfg.N_TOTAL_JUMPS
		and localState.predictJumpWindowUntil ~= nil
		and not RunwaySession.IsGuideStepDone(GameConfig.GuideStepKey.LandingJumpFinished)
	then
		RunwaySession.SetRunwayGuideSlowMotion(
			GameConfig.GuideType.TutorialLandingJump,
			GameConfig.GuideStepKey.LandingJumpFinished
		)
	elseif localState.phase == Ph.Airborne
		and localState.takeoffCount >= cfg.N_TOTAL_JUMPS
		and localState.fuel > 0
		and RunwaySession.GetExpectedPlayerMaxFuel() > 0
		and not RunwaySession.IsGuideStepDone(GameConfig.GuideStepKey.FinalDashFinished)
		and RunwaySession.IsFinalJumpGuideSlowMotionApexReady()
	then
		RunwaySession.SetRunwayGuideSlowMotion(
			GameConfig.GuideType.TutorialFinalDash,
			GameConfig.GuideStepKey.FinalDashFinished
		)
	end

	if Refs.guideSlowMotionActive then
		local nowClock = os.clock()
		if Refs.guideSlowMotionStepKey == GameConfig.GuideStepKey.BeginLineJumpFinished then
			localState.lineJumpWindowExpireAt = nowClock + cfg.T_WINDOW
		elseif Refs.guideSlowMotionStepKey == GameConfig.GuideStepKey.LandingJumpFinished then
			localState.predictJumpWindowUntil = nowClock + cfg.T_WINDOW
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
	RunwaySession.UpdateFinalJumpGuideSlowMotionApexGate(hrp)
	RunwaySession.RefreshRunwayGuideSlowMotionState()
	if Refs.guideSlowMotionActive then
		dt *= GuideSlowMotionSpeedScale
	end
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
		RunwaySession.ProcessJumpRunwayTreeHit(humanoid, hrp, nowClock)
	elseif localState.phase == Ph.Slide then
		if localState.runwaySlideKind == SlideKindFinalLanding or localState.runwaySlideKind == SlideKindMiss then
			RunwaySession.ApplyFinalLandingSlidePhysics(hrp, forward, dt, nowClock, humanoid)
			RunwaySession.ProcessJumpRunwayTreeHit(humanoid, hrp, nowClock)
		elseif localState.runwaySlideKind == SlideKindObstacleBounce then
			local bounceForward = RunwaySession.ResolveObstacleBounceChestForward(hrp)
			RunwaySession.ApplyFinalLandingSlidePhysics(hrp, bounceForward, dt, nowClock, humanoid)
			RunwaySession.ProcessJumpRunwayTreeHit(humanoid, hrp, nowClock)
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
	if not RunwaySession.IsLittleElfChestRunwayFlowActive() then
		RunwaySession.EnsureRunwayGravityForce(hrp)
		RunwaySession.UpdateRunwayGravityForce(hrp)
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
	elseif hrp ~= nil and (localState.phase == Ph.AutoRun or localState.phase == Ph.JumpWindow or localState.phase == Ph.Airborne) then
		RunwaySession.ApplyRunwayYawCorrection(hrp, forward, dt)
	elseif hrp ~= nil and localState.phase == Ph.Slide and localState.runwaySlideKind == SlideKindFinalLanding then
		if not RunwaySession.IsLittleElfChestRunwayFlowActive() then
			RunwaySession.EnsureHumanoidAutoRotateOffForFinalPitch(humanoid)
			RunwaySession.ApplyFinalLandingRenderOrientation(humanoid, hrp, forward, dt, nowClock)
			RunwaySession.SlideTraceUpdate(humanoid, hrp)
		end
	elseif hrp ~= nil and localState.phase == Ph.Slide and localState.runwaySlideKind == SlideKindMiss then
		if not RunwaySession.IsLittleElfChestRunwayFlowActive() then
			RunwaySession.EnsureHumanoidAutoRotateOffForFinalPitch(humanoid)
			RunwaySession.ApplyFinalLandingRenderOrientation(humanoid, hrp, forward, dt, nowClock, cfg.RUNWAY_MISS_SLIDE_PRONE_HRP_GROUND_HEIGHT)
			RunwaySession.SlideTraceUpdate(humanoid, hrp)
		end
	elseif hrp ~= nil and localState.phase == Ph.Slide and localState.runwaySlideKind == SlideKindObstacleBounce then
		if not RunwaySession.IsLittleElfChestRunwayFlowActive() then
			local faceForward = NormalizeRunwayForward(localState.runwayForward)
			RunwaySession.ApplyFinalLandingRenderOrientation(
				humanoid,
				hrp,
				faceForward,
				dt,
				nowClock,
				cfg.RUNWAY_OBSTACLE_BOUNCE_SLIDE_PRONE_HRP_GROUND_HEIGHT
			)
			RunwaySession.SlideTraceUpdate(humanoid, hrp)
		end
	end
	local isFinalLandingSlide = localState.phase == Ph.Slide
		and (
			localState.runwaySlideKind == SlideKindFinalLanding
			or localState.runwaySlideKind == SlideKindMiss
			or localState.runwaySlideKind == SlideKindObstacleBounce
		)
	if RunwaySession.IsLittleElfChestRunwayFlowActive() and Refs.chestRewardWaitPose == true then
		RunwaySession.RestoreHumanoidAutoRotateAfterFinalPitch(humanoid)
		if hrp ~= nil then
			local waitForward = if localState.runwaySlideKind == SlideKindObstacleBounce
				then NormalizeRunwayForward(localState.runwayForward)
				else forward
			RunwaySession.ApplyLittleElfChestStandingWaitOrientation(humanoid, hrp, waitForward)
		end
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
	if hrp ~= nil then
		RunwaySession.FreezeGuideSlowMotionFinalDashPosition(hrp)
	end
end

function RunwaySession.OnJumpRunwayFinalTiltRenderStep(dt: number)
	if not RunwaySession.IsRunwayActivePhase(localState.phase) then
		return
	end
	local _character, humanoid, hrp = RunwaySession.GetCharacterParts()
	if humanoid == nil or hrp == nil then
		return
	end
	local forward = NormalizeRunwayForward(localState.runwayForward)
	if
		localState.phase == Ph.Slide
		and (
			localState.runwaySlideKind == SlideKindFinalLanding
			or localState.runwaySlideKind == SlideKindMiss
			or localState.runwaySlideKind == SlideKindObstacleBounce
		)
	then
		local renderForward = if localState.runwaySlideKind == SlideKindObstacleBounce
			then NormalizeRunwayForward(localState.runwayForward)
			else forward
		if RunwaySession.IsLittleElfChestRunwayFlowActive() then
			RunwaySession.EnsureHumanoidAutoRotateOffForFinalPitch(humanoid)
			if Refs.chestBounceActive == true then
				RunwaySession.ApplyLittleElfChestProneBounceOrientation(humanoid, hrp, renderForward, dt)
			else
				RunwaySession.ApplyLittleElfChestStandingWaitOrientation(humanoid, hrp, renderForward)
			end
		end
	else
		return
	end
	if not RunwaySession.IsLittleElfChestRunwayFlowActive() then
		RunwaySession.EnsureRunwayGravityForce(hrp)
		RunwaySession.UpdateRunwayGravityForce(hrp)
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
		local _character, humanoidTimeout, _hrpTimeout = RunwaySession.GetCharacterParts()
		if humanoidTimeout == nil or not RunwaySession.IsRunwayScriptedGrounded(humanoidTimeout) then
			RunwaySession.CancelJumpWindowTimeoutUntilGroundedAgain()
			return
		end
		ClientMsg.FireJumpRunWayShowMiss()
		localState.lineWindowConsumed = true
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
			local vyScriptMaxRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_TOUCHDOWN_SCRIPT_MAX_VY
			local vyScriptMax = -3
			if typeof(vyScriptMaxRaw) == "number" and vyScriptMaxRaw == vyScriptMaxRaw and vyScriptMaxRaw < -0.05 then
				vyScriptMax = vyScriptMaxRaw
			end
			if curVy <= vyScriptMax and (prevVy == nil or math.abs(curVy - prevVy) < 8) then
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
			localState.jumpWindowGroundedStartClock = nil
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
		localState.jumpWindowGroundedStartClock = nil
		local _character, humanoid, _hrp = RunwaySession.GetCharacterParts()
		if humanoid ~= nil then
			RunwaySession.MaybeStartJumpWindowTiming(humanoid, nowClock)
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
	if
		localState.phase ~= Ph.Slide
		or (localState.runwaySlideKind ~= SlideKindFinalLanding and localState.runwaySlideKind ~= SlideKindObstacleBounce)
	then
		return
	end
	if localState.finalLandSubPhase ~= 1 then
		return
	end
	if not localState.finalLandTumbleImpulseApplied then
		return
	end
	local forwardCheck = if localState.runwaySlideKind == SlideKindObstacleBounce
		then RunwaySession.ResolveObstacleBounceChestForward(hrp)
		else NormalizeRunwayForward(localState.runwayForward)
	local maxPhaseASecRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_MAX_SEC
	local maxPhaseASec = (typeof(maxPhaseASecRaw) == "number" and maxPhaseASecRaw == maxPhaseASecRaw and maxPhaseASecRaw > 0)
		and maxPhaseASecRaw
		or 6
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

	-- 终局触地检测使用宽松几何判定，避免 Physics/翻滚姿态下脚射线或全身点位漏判。
	local geomTouch = RunwaySession.IsRunwayFinalLandPhaseAGroundedLoose(humanoid, hrp)
	if nowClock - localState.slideStartClock >= maxPhaseASec then
		if geomTouch then
			RunwaySession.DebugFinalLandPhaseA("exit_max_phase_a_sec", humanoid, hrp, nowClock)
			RunwaySession.StartFinalLandPronePhase(nowClock, hrp, forwardCheck)
		else
			RunwaySession.DebugFinalLandPhaseA("return_max_phase_a_wait_touchdown", humanoid, hrp, nowClock)
		end
		return
	end
	local vy = hrp.AssemblyLinearVelocity.Y
	local fwdHCheck = Vector3.new(forwardCheck.X, 0, forwardCheck.Z)
	if fwdHCheck.Magnitude < 1e-4 then
		fwdHCheck = Vector3.new(0, 0, -1)
	else
		fwdHCheck = fwdHCheck.Unit
	end
	local minVyRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_MIN_POP_VY
	local minBounceVy = (typeof(minVyRaw) == "number" and minVyRaw == minVyRaw and minVyRaw >= 0) and minVyRaw or 3
	local minAlongRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_MIN_ALONG_SPEED
	local minAlong = (typeof(minAlongRaw) == "number" and minAlongRaw == minAlongRaw and minAlongRaw >= 0) and minAlongRaw or 12
	local maxPopRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_MAX_POP_COUNT
	local maxPop = (typeof(maxPopRaw) == "number" and maxPopRaw == maxPopRaw and maxPopRaw >= 1) and math.floor(maxPopRaw) or 4
	if geomTouch and localState.finalLandTumbleUseAirClock and not localState.finalLandTumbleLeftGround then
		if localState.finalLandPhaseAGroundedStartClock == nil then
			localState.finalLandPhaseAGroundedStartClock = nowClock
		end
		local stuckSecRaw = cfg.RUNWAY_FINAL_LAND_PHASE_A_GROUNDED_STUCK_SEC
		local stuckSec = (typeof(stuckSecRaw) == "number" and stuckSecRaw == stuckSecRaw and stuckSecRaw >= 0)
			and stuckSecRaw
			or 0.35
		if nowClock - (localState.finalLandPhaseAGroundedStartClock :: number) >= stuckSec then
			RunwaySession.DebugFinalLandPhaseA("exit_grounded_stuck_sec", humanoid, hrp, nowClock)
			RunwaySession.StartFinalLandPronePhase(nowClock, hrp, forwardCheck)
			return
		end
		if localState.finalLandLockedTumbleAlong <= minAlong then
			RunwaySession.DebugFinalLandPhaseA("exit_locked_along_below_min_in_grounded_branch", humanoid, hrp, nowClock)
			RunwaySession.StartFinalLandPronePhase(nowClock, hrp, forwardCheck)
			return
		end
	else
		localState.finalLandPhaseAGroundedStartClock = nil
	end
	if geomTouch and localState.finalLandPhaseAPopCount >= maxPop then
		RunwaySession.DebugFinalLandPhaseA("exit_max_pop", humanoid, hrp, nowClock)
		RunwaySession.StartFinalLandPronePhase(nowClock, hrp, forwardCheck)
		return
	end
	if not geomTouch or vy > vyScriptMax or math.abs(vy) > vyFbAbsMax then
		if geomTouch and localState.finalLandLockedTumbleAlong <= minAlong then
			RunwaySession.DebugFinalLandPhaseA("exit_locked_along_below_min_before_vy_return", humanoid, hrp, nowClock)
			RunwaySession.StartFinalLandPronePhase(nowClock, hrp, forwardCheck)
			return
		end
		local reason = if not geomTouch then "return_not_geom_touch"
			elseif vy > vyScriptMax then "return_vy_not_falling"
			else "return_vy_abs_too_large"
		RunwaySession.DebugFinalLandPhaseA(reason, humanoid, hrp, nowClock)
		return
	end

	-- 子阶段 A → B：竖直速度判断。弹性次弹跳时 finalLandTumblePrevPopVy 是前一次 vyPop；
	-- 如果前一次弹跳速度已经接近最低阈值（minPopVy），本次触地后不再弹跳直接进 B
	local shouldEnterB = localState.finalLandTumblePrevPopVy <= minBounceVy * 1.1
	if shouldEnterB then
		RunwaySession.DebugFinalLandPhaseA("exit_prev_pop_vy_below_min", humanoid, hrp, nowClock)
		RunwaySession.StartFinalLandPronePhase(nowClock, hrp, forwardCheck)
		return
	end

	if localState.finalLandTumbleUseAirClock and not localState.finalLandTumbleLeftGround then
		RunwaySession.DebugFinalLandPhaseA("return_wait_left_ground", humanoid, hrp, nowClock)
		return
	end

	RunwaySession.DebugFinalLandPhaseA("apply_next_pop", humanoid, hrp, nowClock)
	RunwaySession.ApplyFinalLandPhaseAPop(hrp, fwdHCheck, nowClock)
end

function RunwaySession.OnBeginLineTouched(hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	if character ~= localPlayer.Character then
		return
	end
	RunwaySession.OnBeginLineCharacterContactConfirmed()
end

-- 子阶段 B 入口：宝箱直接落在地面，滑行全程由宝箱当前位置驱动。
function RunwaySession.ScheduleLittleElfChestAtPhaseBEnter(
	fwdH: Vector3,
	spawnPos: Vector3
)
	if Refs.chestSpawnedForThisRun == true then
		return
	end
	Refs.chestSlideFwdH = fwdH
	Refs.chestScheduledSpawnPos = spawnPos

	Refs.chestSpawnDelayToken += 1
	RunwaySession.SpawnLittleElfChestAtPosition(fwdH, spawnPos)
end

function RunwaySession.ResolveObstacleBounceChestForward(hrp: BasePart): Vector3
	local fwd = Refs.obstacleBounceForward or NormalizeRunwayForward(localState.runwayForward)
	local fwdH = Vector3.new(fwd.X, 0, fwd.Z)
	if fwdH.Magnitude < 1e-4 then
		local look = hrp.CFrame.LookVector
		fwdH = Vector3.new(look.X, 0, look.Z)
	end
	if fwdH.Magnitude < 1e-4 then
		return NormalizeRunwayForward(localState.runwayForward)
	end
	return fwdH.Unit
end

function RunwaySession.BuildObstacleBounceProneSlideBlockIncludeList(): { Instance }
	local includeList: { Instance } = {}
	local treeFolder = workspace:FindFirstChild("tree")
	if treeFolder ~= nil then
		table.insert(includeList, treeFolder)
	end
	local obstacleFolder = workspace:FindFirstChild("Obstacle")
	if obstacleFolder ~= nil then
		table.insert(includeList, obstacleFolder)
	end
	local groundFolder = workspace:FindFirstChild("Ground")
	if groundFolder ~= nil then
		local wallFolder = groundFolder:FindFirstChild("Wall")
		if wallFolder ~= nil then
			table.insert(includeList, wallFolder)
		end
	end
	return includeList
end

function RunwaySession.ResolveObstacleBounceProneSlideBlockedDistance(
	motion: ScriptedSlideMotion,
	desiredDistance: number
): number
	if desiredDistance <= 1e-3 then
		return desiredDistance
	end
	local includeList = RunwaySession.BuildObstacleBounceProneSlideBlockIncludeList()
	if #includeList == 0 then
		return desiredDistance
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = includeList
	local rayOrigin = motion.startPosition + Vector3.new(0, 0.35, 0)
	local hit = workspace:Raycast(rayOrigin, motion.forward * desiredDistance, rayParams)
	if hit == nil or not hit.Instance:IsA("BasePart") then
		return desiredDistance
	end
	if not hit.Instance.CanCollide then
		return desiredDistance
	end
	return math.max(0, hit.Distance - ObstacleBounceProneSlideBlockMarginStuds)
end

function RunwaySession.FreezeScriptedSlideMotionAtDistance(motion: ScriptedSlideMotion, stopDistance: number, nowClock: number)
	stopDistance = math.clamp(stopDistance, 0, motion.totalDistance)
	motion.totalDistance = stopDistance
	motion.lastDistance = stopDistance
	motion.duration = math.max(0, nowClock - motion.startClock)
end

function RunwaySession.IsLittleElfChestRunwayFlowActive(): boolean
	return Refs.chestRunwayAwaitingExit == true
end

function RunwaySession.WarnSlideEndContext(reason: string)
	local nowClock = os.clock()
	if nowClock < Refs.slideEndFallbackWarnNextClock then
		return
	end
	Refs.slideEndFallbackWarnNextClock = nowClock + 0.5
	local _character, humanoid, hrp = RunwaySession.GetCharacterParts()
	local grounded = if humanoid ~= nil then RunwaySession.IsRunwayScriptedGrounded(humanoid) else false
	local speed = if hrp ~= nil then hrp.AssemblyLinearVelocity.Magnitude else 0
	local along = if hrp ~= nil and localState.runwayOrigin ~= nil then RunwaySession.CurrentAlongProgress(hrp) else 0
	local chestModel = Refs.chestSpawnedModel
	local chestDelta = Vector3.zero
	local chestAlongDelta = 0
	local chestLateralDelta = 0
	local chestYDelta = 0
	if hrp ~= nil and chestModel ~= nil and chestModel.Parent ~= nil then
		local chestPos = chestModel:GetPivot().Position
		chestDelta = chestPos - hrp.Position
		local fwd = Refs.chestSlideFwdH or NormalizeRunwayForward(localState.runwayForward)
		if fwd.Magnitude > 1e-4 then
			fwd = Vector3.new(fwd.X, 0, fwd.Z).Unit
			local deltaH = Vector3.new(chestDelta.X, 0, chestDelta.Z)
			chestAlongDelta = deltaH:Dot(fwd)
			chestLateralDelta = (deltaH - fwd * chestAlongDelta).Magnitude
		end
		chestYDelta = chestDelta.Y
	end
	warn(
		string.format(
			"[RunwaySession] SlideEndFallback reason=%s phase=%d slide=%s sub=%d elapsed=%.2f endOver=%.2f grounded=%s speed=%.2f along=%.2f chestSpawned=%s chestReady=%s chestLanded=%s chestRewardStarted=%s chestAwaitingExit=%s finalSent=%s chestAlongDelta=%.2f chestLateralDelta=%.2f chestYDelta=%.2f chestDist=%.2f",
			reason,
			localState.phase,
			localState.runwaySlideKind,
			localState.finalLandSubPhase,
			nowClock - localState.slideStartClock,
			nowClock - localState.slideEndClock,
			tostring(grounded),
			speed,
			along,
			tostring(Refs.chestSpawnedForThisRun),
			tostring(Refs.chestReadyForHit),
			tostring(Refs.chestLandedOnGround),
			tostring(Refs.chestRewardPresentationStarted),
			tostring(Refs.chestRunwayAwaitingExit),
			tostring(localState.finalSent),
			chestAlongDelta,
			chestLateralDelta,
			chestYDelta,
			chestDelta.Magnitude
		)
	)
end

function RunwaySession.ShouldBlockFinalLandingSlideEndForChest(): boolean
	if
		localState.runwaySlideKind ~= SlideKindFinalLanding
		and localState.runwaySlideKind ~= SlideKindMiss
		and localState.runwaySlideKind ~= SlideKindObstacleBounce
	then
		return false
	end
	if localState.finalLandSubPhase ~= 2 then
		return false
	end
	if Refs.chestRunwayAwaitingExit == true or Refs.chestRewardPresentationStarted == true then
		return true
	end
	if Refs.chestSpawnedForThisRun ~= true then
		if os.clock() >= localState.slideEndClock then
			RunwaySession.WarnSlideEndContext("wait_chest_spawn_required")
		end
		return true
	end
	local chestModel = Refs.chestSpawnedModel
	if chestModel == nil or chestModel.Parent == nil then
		RunwaySession.WarnSlideEndContext("chest_model_missing")
		return true
	end
	local landClock = Refs.chestLandClock
	if Refs.chestReadyForHit == true and Refs.chestLandedOnGround == true and landClock ~= nil and os.clock() - landClock >= 3 then
		RunwaySession.WarnSlideEndContext("chest_ready_but_not_hit_after_slide_end")
	end
	return true
end

function RunwaySession.ShouldDeferFinalReportForSlideChest(): boolean
	if localState.phase ~= Ph.Slide then
		return false
	end
	if localState.finalLandSubPhase ~= 2 then
		return false
	end
	if
		localState.runwaySlideKind ~= SlideKindFinalLanding
		and localState.runwaySlideKind ~= SlideKindMiss
		and localState.runwaySlideKind ~= SlideKindObstacleBounce
	then
		return false
	end
	if Refs.chestRewardPresentationStarted == true or Refs.chestRunwayAwaitingExit == true then
		return true
	end
	return Refs.chestSpawnedForThisRun == true or Refs.chestScheduledSpawnPos ~= nil
end

function RunwaySession.ClearLittleElfChestRefs()
	Refs.chestSpawnDelayToken += 1
	RunwaySession.DestroyLittleElfChestSpawnedModel()
	Refs.chestSpawnedForThisRun = false
	Refs.chestPickedBrainrotId = nil
	Refs.chestPickedVariantId = nil
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
	RunwaySession.ClearChestBounceMotion()
	Refs.chestLandClock = nil
	Refs.chestDynamicConfigId = nil
	Refs.chestScheduledSpawnPos = nil
	Refs.chestPredictedPlaceDistance = nil
	Refs.chestBackpackDeliverRequested = false
	Refs.lastRunAlongDistance = nil
	Refs.obstacleBounceForward = nil
	RunwaySession.ResetTreeHitBlockedState()
	RunwaySession.ClearScriptedSlideMotion()
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
	local targetXZ = originPos + fwdH * placeDistance
	local character = hrpForHeight:FindFirstAncestorOfClass("Model")
	local groundY = RunwaySession.RaycastRunwayGroundYAtPosition(targetXZ, character, nil)
	if groundY ~= nil then
		return RunwaySession.BuildLittleElfChestGroundPosition(targetXZ, groundY)
	end
	return RunwaySession.ComputeLittleElfChestFallbackSpawnPosition(originPos, hrpForHeight, fwdH, placeDistance)
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

function RunwaySession.IsLittleElfChestCreatedOrPending(): boolean
	if Refs.chestSpawnedForThisRun == true or Refs.chestScheduledSpawnPos ~= nil then
		return true
	end
	if Refs.chestRunwayAwaitingExit == true or Refs.chestRewardPresentationStarted == true then
		return true
	end
	if Refs.chestHitSequenceActive == true or Refs.chestPendingReward ~= nil or Refs.chestPickedConfigId ~= nil then
		return true
	end
	local chestModel = Refs.chestSpawnedModel
	return chestModel ~= nil and chestModel.Parent ~= nil
end

function RunwaySession.IsPlayerInsideTriggerVolume(trigger: Part, hrp: BasePart): boolean
	local localPos = trigger.CFrame:PointToObjectSpace(hrp.Position)
	local halfSize = trigger.Size * 0.5
	return math.abs(localPos.X) <= halfSize.X
		and math.abs(localPos.Y) <= halfSize.Y + 3
		and math.abs(localPos.Z) <= halfSize.Z
end

function RunwaySession.IsPlayerInsideStartTriggerVolume(startTrigger: Part, hrp: BasePart): boolean
	return RunwaySession.IsPlayerInsideTriggerVolume(startTrigger, hrp)
end

function RunwaySession.IsPlayerCloseEnoughToTrigger(trigger: Part, hrp: BasePart, closeEnoughMinStuds: number): boolean
	return (hrp.Position - trigger.Position).Magnitude
		< math.max(trigger.Size.Magnitude * 2, closeEnoughMinStuds)
end

function RunwaySession.IsPlayerCloseEnoughToStartTrigger(startTrigger: Part, hrp: BasePart): boolean
	return RunwaySession.IsPlayerCloseEnoughToTrigger(startTrigger, hrp, StartTriggerCloseEnoughMinStuds)
end

function RunwaySession.IsPlayerCloseEnoughToEndTrigger(endTrigger: Part, hrp: BasePart): boolean
	return RunwaySession.IsPlayerCloseEnoughToTrigger(endTrigger, hrp, EndTriggerCloseEnoughMinStuds)
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
		if Refs.chestCarryReturnActive ~= true and not RunwaySession.ShouldBlockJumpRunwayStartAtStartTrigger() then
			if humanoid and not RunwaySession.IsRunwayActivePhase(localState.phase) then
				if RunwaySession.SnapLocalPlayerToRunwayGroundIfAirborne(startTrigger, humanoid, hrp) then
					RunwaySession.TryStartLocalRun(startTrigger)
				end
			end
		end
	end

	Refs.startTriggerPlayerWasInsideVolume = insideNow
end

function RunwaySession.UpdateEndTriggerReentryState()
	local endTrigger = RunwaySession.ResolveEndTrigger()
	if endTrigger == nil then
		return
	end
	local character, _humanoid, hrp = RunwaySession.GetCharacterParts()
	if hrp == nil then
		return
	end

	local insideNow = RunwaySession.IsPlayerInsideTriggerVolume(endTrigger, hrp)
	local wasInside = Refs.endTriggerPlayerWasInsideVolume == true
	local enteredNow = insideNow and not wasInside

	if enteredNow then
		if character and RunwaySession.IsLocalPlayerCarryingRunwayLittleElfChest(character) then
			RunwaySession.TryDeliverLittleElfChestAtEndTrigger(endTrigger)
		elseif Refs.chestCarryReturnActive == true then
			RunwaySession.TryExitEscapePhaseAtEndTrigger(endTrigger)
		end
	elseif insideNow and character and RunwaySession.IsLocalPlayerCarryingRunwayLittleElfChest(character) then
		RunwaySession.TryDeliverLittleElfChestAtEndTrigger(endTrigger)
	elseif insideNow and Refs.chestCarryReturnActive == true then
		RunwaySession.TryExitEscapePhaseAtEndTrigger(endTrigger)
	end

	Refs.endTriggerPlayerWasInsideVolume = insideNow
end

function RunwaySession.ShouldBlockJumpRunwayStartAtStartTrigger(): boolean
	if Refs.startTriggerStartArmed == false then
		return true
	end
	if ClientGameInfo.IsExercising() then
		return true
	end
	local character = localPlayer.Character
	if character and RunwaySession.IsLocalPlayerCarryingRunwayLittleElfChest(character) then
		return true
	end
	if RunwaySession.IsLittleElfChestCreatedOrPending() then
		return true
	end
	return Refs.chestCarryReturnActive == true
end

local RunwayCarryVisualMaxWaitSec = 3
local RunwayCarryVisualPollIntervalSec = 0.05

local function ResolveRunwayCarryVariantId(): number
	if Refs.chestPendingReward and Refs.chestPendingReward.variantId > 0 then
		return Refs.chestPendingReward.variantId
	end
	if Refs.chestPickedVariantId and Refs.chestPickedVariantId > 0 then
		return Refs.chestPickedVariantId
	end
	return 0
end

local function EnsureLocalRunwayCarryBrainrotVisual()
	local variantId = ResolveRunwayCarryVariantId()
	task.spawn(function()
		local deadline = os.clock() + RunwayCarryVisualMaxWaitSec
		while os.clock() < deadline do
			local character = localPlayer.Character
			if character then
				local carrying = character:FindFirstChild("CarryingBrainrot")
				if carrying and carrying:IsA("BasePart") then
					if carrying:GetAttribute(JumpRunwayLittleElfChestCarryAttr) == true then
						BrainrotClientManager.SetupCarryingBrainrotVisual(carrying, if variantId > 0 then variantId else nil)
						return
					end
				end
			end
			task.wait(RunwayCarryVisualPollIntervalSec)
		end
	end)
end

function RunwaySession.EnterLittleElfChestCarryReturn(brainrotId: number?, chestConfigId: number?)
	NetMsg.FireRequestJumpRunwayLittleElfChestStartCarry(brainrotId, chestConfigId)
	EnsureLocalRunwayCarryBrainrotVisual()
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
	local baseDirection = -forwardExit
	if baseDirection.Magnitude < 1e-4 then
		baseDirection = Vector3.new(0, 0, 1)
	else
		baseDirection = Vector3.new(baseDirection.X, 0, baseDirection.Z).Unit
	end
	local _, hDelay, hrpDelay = RunwaySession.GetCharacterParts()
	if hDelay and hrpDelay then
		RunwaySession.SnapCharacterHrpToGround(hDelay, hrpDelay, baseDirection)
		hrpDelay.AssemblyLinearVelocity = Vector3.zero
		hrpDelay.AssemblyAngularVelocity = Vector3.zero
		RunwaySession.AlignCharacterYawToRunwayForward(hrpDelay, baseDirection)
		RunwaySession.RestoreRunwayHumanoidLocomotionFromScriptedMode(hDelay)
		RunwaySession.ClearFinalLandingSlideModuleLocals()
		RunwaySession.RestoreRunwayHumanoidPoseAfterGameplay(hDelay, hrpDelay)
		RunwaySession.AlignCharacterYawToRunwayForward(hrpDelay, baseDirection)
		RunwaySession.ApplyExpectedWalkSpeedAfterRunway(hDelay)
	else
		RunwayCameraController.Disable(workspace, RunwaySession.GetCharacterParts, baseDirection, cfg, NormalizeRunwayForward)
	end
	if localState.controlsDisabled then
		RunwaySession.SetControlsEnabled(true)
	end
	local carryPresentHoldSec = ResolveChestCarryPresentHoldSec()
	if carryPresentHoldSec > 0 then
		task.wait(carryPresentHoldSec)
	end
	if Refs.chestPickedConfigId ~= chestConfigId or Refs.chestRewardPresentationStarted ~= true then
		return
	end
	-- 举起展示结束后再切 Idle，避免等待期间 OnCameraRenderStep 提前 Disable 导致追击者镜头动画失效
	localState.phase = Ph.Idle
	localState.groundedStableTime = 0
	-- 在清理之前先获取怪物数据
	local monsterData: GameConfig.MonsterData? = nil
	if Refs.lastRunAlongDistance ~= nil then
		monsterData = GameConfig.GetMonsterByDistance(Refs.lastRunAlongDistance)
	end
	local chaserSpeedOverride = if monsterData then monsterData.moveSpeed else nil
	RunwaySession.ClearLittleElfChestRefs()
	if hDelay then
		local chaserFreezeDuration = cfg.CHASER_FREEZE_AFTER_SPAWN_SEC
		local chaser = ChaserClientManager.SpawnChaser(
			hDelay:FindFirstAncestorOfClass("Model") :: Model,
			forwardExit,
			chaserSpeedOverride,
			chaserFreezeDuration
		)
		RunwayCameraController.FocusChaserThenDisable(
			workspace,
			RunwaySession.GetCharacterParts,
			chaser,
			baseDirection,
			cfg,
			NormalizeRunwayForward,
			function()
				ClientMsg.FireJumpRunWayStartEscapeRedScreen()
			end
		)
	else
		RunwayCameraController.FocusChaserThenDisable(
			workspace,
			RunwaySession.GetCharacterParts,
			nil,
			baseDirection,
			cfg,
			NormalizeRunwayForward,
			function()
				ClientMsg.FireJumpRunWayStartEscapeRedScreen()
			end
		)
	end
	ClientGameInfo.SetInJumpRunwayEscapePhase(true)
	Refs.chestCarryReturnActive = true
	ClientMsg.FireJumpRunWayEnterEscapeHudMode()
end

function RunwaySession.TryDeliverLittleElfChestAtEndTrigger(endTrigger: Part)
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
	if not RunwaySession.IsPlayerCloseEnoughToEndTrigger(endTrigger, hrp) then
		return
	end
	Refs.chestBackpackDeliverRequested = true
	Refs.startTriggerStartArmed = false
	Refs.endTriggerPlayerWasInsideVolume = true
	Refs.chestCarryReturnActive = false
	ChaserClientManager.StopAndFadeChaser()
	ClientMsg.FireJumpRunWayStopEscapeRedScreen()
	RunwaySession.DestroyDistanceRecorder()
	NetMsg.FireRequestJumpRunwayLittleElfChestGrant()
	ClientGameInfo.SetInJumpRunwayEscapePhase(false)
	ClientGameInfo.SetInJumpRunway(false)
	UIManager.CloseWindow(UIManager.WindowId.JumpRunWayFrame)
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

function RunwaySession.TryExitEscapePhaseAtEndTrigger(endTrigger: Part)
	if Refs.chestCarryReturnActive ~= true then
		return
	end

	local _character, _humanoid, hrp = RunwaySession.GetCharacterParts()
	if hrp == nil then
		return
	end
	if not RunwaySession.IsPlayerCloseEnoughToEndTrigger(endTrigger, hrp) then
		return
	end

	Refs.chestCarryReturnActive = false
	Refs.startTriggerStartArmed = false
	Refs.endTriggerPlayerWasInsideVolume = true
	ChaserClientManager.StopAndFadeChaser()
	RunwaySession.ResetLocalRunToIdle()
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
	RunwayCameraController.SetChestOpenZoomActive(true)

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
				resolveFinalVariantId = function()
					if Refs.chestPickedConfigId ~= pickedConfigId then
						return nil
					end
					if Refs.chestPendingReward then
						return Refs.chestPendingReward.variantId
					end
					return Refs.chestPickedVariantId
				end,
				postFinalRevealHoldSec = ResolveChestFinalRewardHoldSec(),
			}
		)
		if selectedBrainrotId == nil then
			selectedBrainrotId = RunwaySession.GetLittleElfChestFallbackBrainrotId(pickedConfigId)
		end
		Refs.chestPickedBrainrotId = selectedBrainrotId
	end
	RunwayCameraController.SetChestOpenZoomActive(false)
	if Refs.chestPickedConfigId ~= pickedConfigId or Refs.chestRewardPresentationStarted ~= true then
		return
	end
	RunwaySession.EnterLittleElfChestCarryReturn(Refs.chestPickedBrainrotId, pickedConfigId)
end

function RunwaySession.EndChestProneBounceAndWaitForReward()
	if Refs.chestRunwayAwaitingExit ~= true then
		return
	end
	Refs.chestBounceActive = false
	RunwaySession.ClearChestBounceMotion()
	Refs.chestRewardWaitPose = true
	RunwaySession.DestroyRunwayGravityForce()
	local _, humanoidWait, hrpWait = RunwaySession.GetCharacterParts()
	if humanoidWait and hrpWait then
		local forwardWait = NormalizeRunwayForward(localState.runwayForward)
		RunwaySession.ApplyLittleElfChestStandingWaitOrientation(humanoidWait, hrpWait, forwardWait)
		RunwaySession.CommitRunwayBestDistanceFromDistanceRecorder(hrpWait)
	end
	RunwaySession.TryPresentLittleElfChestReward()
end

function RunwaySession.SnapCharacterHrpToGround(humanoid: Humanoid, hrp: BasePart, fwdStand: Vector3)
	local groundY = RunwaySession.GetRunwayGroundYUnderHrp(humanoid, hrp)
	if groundY ~= nil then
		local standExtra = RunwaySession.ResolveFiniteNumber(cfg.RUNWAY_CHEST_STAND_HRP_GROUND_EXTRA_HEIGHT, 0)
		local standHeight = RunwaySession.GetHumanoidRootGroundHeight(humanoid, hrp) + standExtra
		local groundPos = Vector3.new(hrp.Position.X, groundY + standHeight, hrp.Position.Z)
		hrp.CFrame = CFrame.lookAt(groundPos, groundPos + fwdStand, Vector3.yAxis)
	end
end

function RunwaySession.ApplyLittleElfChestProneBounceOrientation(humanoid: Humanoid, hrp: BasePart, forward: Vector3, dt: number)
	local slideFwd = Refs.chestSlideFwdH or forward
	local linVel = hrp.AssemblyLinearVelocity
	local fallbackHeight = RunwaySession.ResolveProneHrpGroundHeight(cfg.RUNWAY_FINAL_LAND_PRONE_HRP_GROUND_HEIGHT, 2.8)
	local bounceHeight = cfg.RUNWAY_CHEST_BOUNCE_PRONE_HRP_GROUND_HEIGHT
	if localState.runwaySlideKind == SlideKindFinalLanding then
		bounceHeight = cfg.RUNWAY_FINAL_LAND_CHEST_BOUNCE_PRONE_HRP_GROUND_HEIGHT
	end
	local proneLocked = RunwaySession.BuildProneRunwayCFrameAtGroundHeight(
		humanoid,
		hrp,
		slideFwd,
		bounceHeight,
		fallbackHeight
	)
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
	RunwaySession.ClearChestBounceMotion()
	Refs.chestRewardWaitPose = true
	Refs.chestHitSequenceActive = false
	RunwaySession.ClearScriptedSlideMotion()
	RunwaySession.ClearFinalLandingSlideModuleLocals()
	RunwaySession.DestroyRunwayGravityForce()
	local forwardReward = NormalizeRunwayForward(localState.runwayForward)
	RunwaySession.ApplyLittleElfChestStandingWaitOrientation(humanoid, hrp, forwardReward)
	RunwaySession.EnsureHumanoidRunningState(humanoid)
	RunwaySession.CommitRunwayBestDistanceFromDistanceRecorder(hrp)
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
	local baseline = localState.alongBaseline or 0
	local finalAlong = if origin ~= nil then (hrpFinal.Position - origin):Dot(forwardFinal) - baseline else 0
	NetMsg.FireRequestJumpRunwayInput({
		kind = Kind.Final,
		finalAlong = finalAlong,
		clientClock = os.clock(),
		clientPhase = Ph.RunEnded,
	})
	localState.finalSent = true
	RunwaySession.PrintDistanceLogSummary("force_final_report", hrpFinal)
end

function RunwaySession.IsPlayerNearLittleElfChest(hrp: BasePart, chestModel: Model, _fwdH: Vector3): boolean
	if Refs.chestReadyForHit ~= true or Refs.chestLandedOnGround ~= true then
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
	if toChest.Magnitude > ResolveChestHitHorizontalMaxDistStuds() then
		return false
	end
	-- 固定宝箱流程只要求进入水平命中半径；允许帧步进导致角色略微越过宝箱后仍能开箱。
	return true
end

function RunwaySession.IsObstacleBounceHrpBeforeStartTrigger(hrp: BasePart): boolean
	local startTrigger, _ = RunwaySession.ResolveSceneParts()
	if startTrigger == nil then
		return false
	end
	return hrp.Position.X < startTrigger.Position.X
end

function RunwaySession.ExitObstacleBounceBeforeStartTrigger(humanoid: Humanoid, hrp: BasePart)
	RunwaySession.RestorePlatformStandAfterFinalLand(humanoid)
	RunwaySession.ClearFinalLandingSlideModuleLocals()
	RunwaySession.ClearScriptedSlideMotion()
	RunwaySession.RestoreHumanoidAutoRotateAfterFinalPitch(humanoid)
	RunwaySession.RestoreRunwayHumanoidPoseAfterGameplay(humanoid, hrp)
	if NetMsg.JumpRunwayRemotesExist() and not localState.finalSent and Refs.missAbortSentForThisRun ~= true then
		Refs.missAbortSentForThisRun = true
		NetMsg.FireRequestJumpRunwayInput({
			kind = Kind.Abort,
			clientClock = os.clock(),
			clientPhase = localState.phase,
		})
		localState.finalSent = true
	end
	RunwaySession.SlideTraceScheduleDestroyAfterRunwayEnd()
	RunwaySession.RestoreRunwayHumanoidLocomotionFromScriptedMode(humanoid)
	RunwaySession.ClearRunwayFlyingHumanoid(humanoid)
	if localState.controlsDisabled then
		RunwaySession.SetControlsEnabled(true)
	end
	RunwaySession.ResetLocalRunToIdle()
end

function RunwaySession.HandleObstacleBounceSlideStop(humanoid: Humanoid, hrp: BasePart)
	if RunwaySession.IsObstacleBounceHrpBeforeStartTrigger(hrp) then
		RunwaySession.ExitObstacleBounceBeforeStartTrigger(humanoid, hrp)
		return
	end
	RunwaySession.OpenLittleElfChestAfterObstacleBounceStop(humanoid, hrp)
end

function RunwaySession.OpenLittleElfChestAfterObstacleBounceStop(humanoid: Humanoid, hrp: BasePart)
	if Refs.chestRunwayAwaitingExit == true or Refs.chestRewardPresentationStarted == true then
		return
	end
	local faceFwdH = NormalizeRunwayForward(localState.runwayForward)
	Refs.chestSlideFwdH = faceFwdH
	local chestConfigId = if Refs.chestDynamicConfigId ~= nil then Refs.chestDynamicConfigId else cfg.RUNWAY_CHEST_CONFIG_ID
	local chestConfig = GameConfig.LittleElfChestIdMap[chestConfigId]
	if
		chestConfig == nil
		or not GameConfig.IsLittleElfChestAvailableForJumpRunway(chestConfig)
		or actualChests == nil
	then
		return
	end
	local template = GameConfig.FindResourceTemplateByResourceName(actualChests, chestConfig.resourceName)
	if not template then
		return
	end
	local ahead = RunwaySession.ResolveTreeHitNumber(cfg.RUNWAY_TREE_HIT_DIRECT_OPEN_CHEST_AHEAD_STUDS, 3, 0, 16)
	local spawnPos = RunwaySession.ComputeLittleElfChestSpawnPositionAtOrigin(hrp.Position, hrp, faceFwdH, ahead)
	local chestModel = GameConfig.CloneTemplateAsModel(template)
	chestModel.Name = "RunwayLittleElfChest"
	RunwaySession.SetModelCollisionGroup(chestModel, ChestCollisionGroupName)
	local landPos = RunwaySession.ResolveLittleElfChestGroundPosition(spawnPos, chestModel)
	local openCFrame = RunwaySession.BuildLittleElfChestOpenCFrame(landPos, faceFwdH, chestModel)
	for _, part in ipairs(chestModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = true
			part.CanTouch = false
			part.Massless = true
		end
	end
	chestModel:PivotTo(openCFrame)
	chestModel.Parent = workspace
	Refs.chestSpawnedForThisRun = true
	Refs.chestSpawnedModel = chestModel
	Refs.chestGroundOpenCFrame = openCFrame
	Refs.chestOpenCFrame = openCFrame
	Refs.chestLandedOnGround = true
	Refs.chestReadyForHit = false
	Refs.chestRunwayAwaitingExit = true
	Refs.chestBounceActive = false
	Refs.chestHitSequenceActive = true
	Refs.chestPickedConfigId = chestConfigId
	Refs.chestPickedBrainrotId = nil
	Refs.chestPickedVariantId = nil
	Refs.chestPendingReward = nil
	Refs.chestRewardPresentationStarted = false
	localState.slideEndClock = math.huge
	RunwaySession.EnterLittleElfChestRewardWaitPose(humanoid, hrp)
	NetMsg.FireRequestJumpRunwayLittleElfChestReward(chestConfigId)
	task.spawn(RunwaySession.TryPresentLittleElfChestReward)
end

function RunwaySession.ProcessLittleElfChestHit(chestModel: Model, fwdH: Vector3, chestConfigId: number, allowPathTerminalHit: boolean?)
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
	local isNearChest = RunwaySession.IsPlayerNearLittleElfChest(hrpT, chestModel, fwdH)
	if not isNearChest and allowPathTerminalHit ~= true then
		return
	end
	if not isNearChest then
		local chestPos = chestModel:GetPivot().Position
		local deltaH = Vector3.new(chestPos.X - hrpT.Position.X, 0, chestPos.Z - hrpT.Position.Z)
		--warn(
		--	string.format(
		--		"[RunwaySession] LittleElfChest terminal path hit accepted outside near radius. chestConfigId=%d chestDist=%.2f hitRadius=%.2f",
		--		chestConfigId,
		--		deltaH.Magnitude,
		--		ResolveChestHitHorizontalMaxDistStuds()
		--	)
		--)
	end
	RunwaySession.TransitionDistanceLogStage(
		"ChestBounce",
		"little_elf_chest_hit",
		hrpT,
		string.format("chestConfigId=%d", chestConfigId)
	)

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
	Refs.chestPickedVariantId = nil
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
	local bounceStartClock = os.clock()
	RunwaySession.StartChestBounceMotion(bounceStartClock, hrpT, bounceFwd)
	RunwaySession.ApplyChestBounceMotion(hrpT, bounceStartClock)
	hrpT.AssemblyLinearVelocity = Vector3.zero
	hrpT.AssemblyAngularVelocity = Vector3.zero

	local bounceMotion = Refs.chestBounceMotion
	local bounceSec = if bounceMotion ~= nil then math.max(0.05, bounceMotion.duration) else 0.05
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

function RunwaySession.SpawnLittleElfChestAtPosition(fwdH: Vector3, spawnPos: Vector3)
	if Refs.chestSpawnedForThisRun == true then
		return
	end
	if actualChests == nil then
		warn("[RunwaySession] LittleElfChests folder missing under ReplicatedStorage.Models")
		return
	end
	local chestConfigId = if Refs.chestDynamicConfigId ~= nil then Refs.chestDynamicConfigId else cfg.RUNWAY_CHEST_CONFIG_ID
	local chestConfig = GameConfig.LittleElfChestIdMap[chestConfigId]
	if chestConfig == nil or not GameConfig.IsLittleElfChestAvailableForJumpRunway(chestConfig) then
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
	local spawnToken = Refs.chestSpawnDelayToken

	local chestModel = GameConfig.CloneTemplateAsModel(template)
	chestModel.Name = "RunwayLittleElfChest"
	RunwaySession.SetModelCollisionGroup(chestModel, ChestCollisionGroupName)

	local landPos = RunwaySession.ResolveLittleElfChestGroundPosition(spawnPos, chestModel)
	local landCf = RunwaySession.BuildLittleElfChestOpenCFrame(landPos, fwdH, chestModel)
	local airPos = landPos + Vector3.new(0, CHEST_FALL_MAX_HEIGHT_STUDS, 0)
	chestModel:PivotTo(CFrame.new(airPos))

	Refs.chestGroundOpenCFrame = landCf

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
		driver.Value = CHEST_FALL_MAX_HEIGHT_STUDS
		local conn = driver:GetPropertyChangedSignal("Value"):Connect(function()
			if Refs.chestSpawnDelayToken ~= spawnToken then
				return
			end
			if chestModel and chestModel.Parent then
				local currentPos = landPos + Vector3.new(0, driver.Value, 0)
				chestModel:PivotTo(CFrame.new(currentPos))
			end
		end)
		local tween = tweenService:Create(
			driver,
			TweenInfo.new(CHEST_FALL_DURATION_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Value = 0 }
		)
		tween:Play()
		tween.Completed:Wait()
		conn:Disconnect()
		driver:Destroy()
		if Refs.chestSpawnDelayToken ~= spawnToken then
			return
		end
		if chestModel and chestModel.Parent then
			chestModel:PivotTo(landCf)
			Refs.chestLandedOnGround = true
			Refs.chestLandClock = os.clock()
			EnableChestHit()
		end
	end)()
end

function RunwaySession.ResolveLittleElfChestGroundPosition(targetPos: Vector3, chestModel: Model?): Vector3
	local extraExcludeList: { Instance } = {}
	if chestModel then
		table.insert(extraExcludeList, chestModel)
	end
	local character = localPlayer.Character
	local groundY = RunwaySession.RaycastRunwayGroundYAtPosition(targetPos, character, extraExcludeList)
	if groundY ~= nil then
		return RunwaySession.BuildLittleElfChestGroundPosition(targetPos, groundY)
	end
	return targetPos
end

function RunwaySession.OnLittleElfChestRewardReceived(brainrotId: number, chestConfigId: number, chestLevel: number, variantId: number)
	if Refs.chestPickedConfigId ~= chestConfigId then
		return
	end
	if Refs.chestPendingReward ~= nil then
		return
	end
	Refs.chestPickedBrainrotId = brainrotId
	Refs.chestPickedVariantId = variantId
	Refs.chestPendingReward = {
		brainrotId = brainrotId,
		chestConfigId = chestConfigId,
		chestLevel = chestLevel,
		variantId = variantId,
	}
	RunwaySession.TryPresentLittleElfChestReward()
end
function RunwaySession.UpdateTick(dt: number)
	local nowClock = os.clock()
	RunwaySession.ProcessJumpWindowTimeout(nowClock)
	RunwaySession.TickBestDistanceWallIfNeeded()
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
	local character, humanoid, hrp = RunwaySession.GetCharacterParts()
	if character == nil or humanoid == nil or hrp == nil then
		return
	end
	RunwaySession.SyncRunwayHumanoidWalkSpeed(humanoid, nowClock)
	RunwaySession.ApplyRunwayHumanoidJumpState(humanoid, true)
	RunwaySession.PollBeginLineOverlapForJumpWindow()
	RunwaySession.UpdateFinalJumpGuideSlowMotionApexGate(hrp)
	RunwaySession.RefreshRunwayGuideSlowMotionState()
	if Refs.guideSlowMotionActive then
		dt *= GuideSlowMotionSpeedScale
	end
	RunwaySession.UpdateRunwayRingTransform(humanoid, hrp, dt)
	RunwaySession.UpdateDistanceRecorder(humanoid, hrp)
	local phaseBeforeForwardBlocked = localState.phase
	RunwaySession.ProcessRunwayForwardBlocked(character, humanoid, hrp, nowClock)
	if phaseBeforeForwardBlocked ~= Ph.Slide and localState.phase == Ph.Slide then
		return
	end
	if localState.phase == Ph.Airborne and localState.takeoffCount == cfg.N_TOTAL_JUMPS then
		if RunwaySession.IsFinalDashThrustActive() then
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
	if not RunwaySession.IsLittleElfChestRunwayFlowActive() and not RunwaySession.ShouldDeferFinalReportForSlideChest() then
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
			ComputeRunwayHorizontalAlongSpeed,
			RunwaySession.IsRunwayScriptedGrounded
		)
	end
	if
		localState.phase == Ph.Slide
		and localState.finalLandSubPhase == 2
		and (
			localState.runwaySlideKind == SlideKindFinalLanding
			or localState.runwaySlideKind == SlideKindMiss
			or localState.runwaySlideKind == SlideKindObstacleBounce
		)
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
			RunwaySession.WarnSlideEndContext("final_landing_slide_end")
			RunwaySession.TryForceReportFinalAfterChestExit()
			RunwaySession.ResetLocalRunToIdle()
			return
		elseif localState.runwaySlideKind == SlideKindMiss or localState.runwaySlideKind == SlideKindObstacleBounce then
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
		return
	end
	if payload.phase == Ph.Idle or payload.phase == Ph.Cleaning then
		if localState.phase == Ph.Idle then
			-- 已经清理过了，忽略服务端延迟消息
			return
		end
		-- 如果当前已经是新 Run 的活跃阶段（非 RunEnded），说明玩家已重新开始或仍在固定宝箱流程中，
		-- 忽略服务端延迟通知，避免误杀新 Run / 跳过宝箱流程。
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
		if localState.phase == Ph.RunEnded then
			RunwaySession.WarnSlideEndContext("server_score_locked_cleanup")
			RunwaySession.ResetLocalRunToIdle()
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

function RunwaySession.LerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * math.clamp(t, 0, 1)
end

function RunwaySession.JumpRatingTierName(tier: number): string
	local t = math.clamp(math.floor(tier), 1, 3)
	if t == 1 then
		return "Perfect"
	elseif t == 2 then
		return "Ok"
	end
	return "Late"
end

function RunwaySession.ResolveJumpWindowRatingSpeedBonusRatio(jumpIndex: number, tier: number): number
	local t = math.clamp(math.floor(tier), 1, 3)
	local index = math.clamp(math.floor(jumpIndex), 1, math.max(1, cfg.N_TOTAL_JUMPS))
	local list = cfg.JUMP_WINDOW_RATING_SPEED_BONUS_BY_TIER
	if typeof(list) ~= "table" then
		return 0
	end
	local jumpMap = list[index]
	if typeof(jumpMap) ~= "table" then
		local lastMap = list[#list]
		if typeof(lastMap) == "table" then
			jumpMap = lastMap
		end
	end
	if typeof(jumpMap) == "table" then
		local ratio = jumpMap[t]
		if typeof(ratio) == "number" and ratio == ratio then
			return math.max(0, ratio)
		end
	end
	local legacyRatio = list[t]
	if typeof(legacyRatio) == "number" and legacyRatio == legacyRatio then
		return math.max(0, legacyRatio)
	end
	return 0
end

function RunwaySession.ResolveJumpWindowRatingSpeedBonusTriplet(jumpIndex: number): (number, number, number)
	return RunwaySession.ResolveJumpWindowRatingSpeedBonusRatio(jumpIndex, 1),
		RunwaySession.ResolveJumpWindowRatingSpeedBonusRatio(jumpIndex, 2),
		RunwaySession.ResolveJumpWindowRatingSpeedBonusRatio(jumpIndex, 3)
end

function RunwaySession.JumpSpeedBonusForRatio(bonusRatio: number, currentBaseSpeed: number): number
	local ratio = bonusRatio
	if typeof(ratio) ~= "number" or ratio ~= ratio then
		ratio = 0
	end
	ratio = math.max(0, ratio)
	local baseSpd = currentBaseSpeed
	if typeof(baseSpd) ~= "number" or baseSpd ~= baseSpd then
		baseSpd = 0
	end
	baseSpd = math.max(0, baseSpd)
	return baseSpd * ratio
end

function RunwaySession.JumpSpeedBonusForTier(tier: number, currentBaseSpeed: number, jumpIndex: number): number
	local t = math.clamp(math.floor(tier), 1, 3)
	local ratio = RunwaySession.ResolveJumpWindowRatingSpeedBonusRatio(jumpIndex, t)
	return RunwaySession.JumpSpeedBonusForRatio(ratio, currentBaseSpeed)
end

function RunwaySession.JumpSpeedReductionDeltaForBaseSpeed(currentBaseSpeed: number): number
	local ratio = cfg.JUMP_SPEED_REDUCTION_RATIO
	if typeof(ratio) ~= "number" or ratio ~= ratio then
		return 0
	end
	ratio = math.max(0, ratio)
	return math.max(0, currentBaseSpeed) * ratio
end

function RunwaySession.GetJumpSpeedCurrentDeceleratedBaseSpeed(): number
	local segmentIndex = math.max(1, localState.takeoffCount)
	local _, minSpd = GameConfig.GetJumpRunwayJumpSpeedLimitsForSegment(
		segmentIndex,
		localState.jumpSpeedCumulativeRatingBonus,
		GetJumpPowerBaseSpeed(),
		localState.jumpSpeedCurrentReductionDelta
	)
	return minSpd
end

function RunwaySession.ApplyJumpSpeedRatingForBonusRatio(
	bonusRatio: number,
	currentBaseSpeed: number
): (number, number, number, number)
	local addedBonus = RunwaySession.JumpSpeedBonusForRatio(bonusRatio, currentBaseSpeed)
	local nextMaxSpeed = currentBaseSpeed + addedBonus
	local jumpPowerBaseSpeed = GetJumpPowerBaseSpeed()
	localState.jumpSpeedCumulativeRatingBonus = math.max(0, nextMaxSpeed - jumpPowerBaseSpeed)
	localState.jumpSpeedCurrentReductionDelta = RunwaySession.JumpSpeedReductionDeltaForBaseSpeed(currentBaseSpeed)
	return addedBonus, nextMaxSpeed, localState.jumpSpeedCumulativeRatingBonus, localState.jumpSpeedCurrentReductionDelta
end

function RunwaySession.ApplyJumpSpeedRatingForTier(tier: number, currentBaseSpeed: number, jumpIndex: number)
	local ratio = RunwaySession.ResolveJumpWindowRatingSpeedBonusRatio(jumpIndex, tier)
	RunwaySession.ApplyJumpSpeedRatingForBonusRatio(ratio, currentBaseSpeed)
end

function RunwaySession.ResolveAutoBeforeLineRating(jumpIndex: number, hrp: BasePart?): (number, number, string)
	local perfectRatio, okRatio, lateRatio = RunwaySession.ResolveJumpWindowRatingSpeedBonusTriplet(jumpIndex)
	if hrp == nil then
		return 2, lateRatio, "AutoBeforeLine"
	end
	local okBegin, distToBegin, maxDist = RunwaySession.ResolveBeginLineAlongMetrics(hrp)
	if not okBegin or maxDist <= 1e-4 then
		return 2, lateRatio, "AutoBeforeLine"
	end
	local perfectDistance = cfg.RUNWAY_BEGIN_LINE_PERFECT_DISTANCE_STUDS
	if typeof(perfectDistance) ~= "number" or perfectDistance ~= perfectDistance or perfectDistance < 0 then
		perfectDistance = 3
	end
	print(
		string.format(
			"[JumpRunwayBeginLineDistance] jump=%d distToBegin=%.2f perfectDistance=%.2f maxDist=%.2f",
			jumpIndex,
			distToBegin,
			perfectDistance,
			maxDist
		)
	)
	if distToBegin <= perfectDistance then
		local progress = math.clamp((perfectDistance - distToBegin) / math.max(perfectDistance, 1e-4), 0, 1)
		return 1, RunwaySession.LerpNumber(okRatio, perfectRatio, progress), "AutoBeforeLine"
	end
	local okBand = math.max(maxDist - perfectDistance, 1e-4)
	local progress = math.clamp((maxDist - distToBegin) / okBand, 0, 1)
	return 2, RunwaySession.LerpNumber(lateRatio, okRatio, progress), "AutoBeforeLine"
end

function RunwaySession.ResolveChainDistanceRating(
	humanoid: Humanoid,
	jumpIndex: number
): (number, number, string)
	local perfectRatio, okRatio, lateRatio = RunwaySession.ResolveJumpWindowRatingSpeedBonusTriplet(jumpIndex)
	local ok, dist = RunwaySession.RaycastFeet(humanoid)
	if not ok then
		return 2, lateRatio, "ChainPreland"
	end
	local baseline = localState.preLandRayBaselineStuds
	local groundDist = 0
	if typeof(baseline) == "number" and baseline == baseline then
		groundDist = baseline
	end
	local prelandDist = groundDist + cfg.RUNWAY_PRELAND_MAX_DIST_STUDS
	local chainDist = groundDist + cfg.RUNWAY_CHAIN_WINDOW_START_HEIGHT_STUDS
	if dist > chainDist then
		local denom = math.max(prelandDist - chainDist, 1e-4)
		local progress = math.clamp((prelandDist - dist) / denom, 0, 1)
		return 2, RunwaySession.LerpNumber(lateRatio, okRatio, progress), "ChainPreland"
	end
	local denom = math.max(chainDist - groundDist, 1e-4)
	local progress = math.clamp((chainDist - dist) / denom, 0, 1)
	return 1, RunwaySession.LerpNumber(okRatio, perfectRatio, progress), "ChainNearGround"
end

function RunwaySession.ResolveTimedWindowRating(
	deltaT: number,
	jumpIndex: number,
	contextName: string
): (number, number, string)
	local perfectRatio, okRatio, lateRatio = RunwaySession.ResolveJumpWindowRatingSpeedBonusTriplet(jumpIndex)
	local w = cfg.T_WINDOW
	if w <= 1e-6 then
		return 1, perfectRatio, contextName
	end
	local frac = math.max(0, deltaT / w)
	local perfectMax = cfg.JUMP_WINDOW_RATING_PERFECT_MAX_FRAC
	local okMax = cfg.JUMP_WINDOW_RATING_OK_MAX_FRAC
	if frac < perfectMax then
		local progress = if perfectMax > 1e-6 then frac / perfectMax else 1
		return 1, RunwaySession.LerpNumber(perfectRatio, okRatio, progress), contextName
	elseif frac < okMax then
		local denom = math.max(okMax - perfectMax, 1e-6)
		local progress = (frac - perfectMax) / denom
		return 2, RunwaySession.LerpNumber(okRatio, lateRatio, progress), contextName
	end
	return 3, lateRatio, contextName
end

function RunwaySession.LogJumpRunwayRating(
	jumpIndex: number,
	contextName: string,
	tier: number,
	bonusRatio: number,
	addedBonus: number,
	currentBaseSpeed: number,
	nextMaxSpeed: number,
	cumulativeBonus: number,
	reductionDelta: number
)
	print(
		string.format(
			"[JumpRunwayRating] jump=%d context=%s tier=%s tierValue=%d bonusRatio=%.3f addedBonus=%.2f base=%.2f nextMax=%.2f cumulative=%.2f reduction=%.2f",
			jumpIndex,
			contextName,
			RunwaySession.JumpRatingTierName(tier),
			tier,
			bonusRatio,
			addedBonus,
			currentBaseSpeed,
			nextMaxSpeed,
			cumulativeBonus,
			reductionDelta
		)
	)
end

function RunwaySession.ComputeJumpHorizontalDecelerationDuration(vy: number, gGrav: number): number
	local boostHoldSec = cfg.RUNWAY_JUMP_BOOST_HOLD_SEC
	if typeof(boostHoldSec) ~= "number" or boostHoldSec ~= boostHoldSec then
		boostHoldSec = 0
	end
	boostHoldSec = math.max(0, boostHoldSec)
	local apexAfterBoostSec = if gGrav > 1e-6 then math.max(0, vy) / gGrav else 0.25
	return math.max(0.01, boostHoldSec + apexAfterBoostSec)
end

function RunwaySession.JumpComputeSessionVy(): (number, number, number)
	local gBase = workspace.Gravity
	if gBase < 1e-3 then
		gBase = 196.2
	end
	local gGrav = gBase * cfg.RUNWAY_SESSION_EFFECTIVE_GRAVITY_SCALE
	local jumpPower = GetJumpPowerBaseSpeed()
	local vy = jumpPower * cfg.JUMP_VERTICAL_RATIO
	return jumpPower, vy, gGrav
end

function RunwaySession.JumpPerpImpulseTerm(_hrp: BasePart, _forward: Vector3): Vector3
	return Vector3.zero
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
	local jumpIndex = math.clamp(localState.takeoffCount + 1, 1, cfg.N_TOTAL_JUMPS)
	local currentBaseSpeed = RunwaySession.GetJumpSpeedCurrentDeceleratedBaseSpeed()
	local tier = 2
	local bonusRatio = RunwaySession.ResolveJumpWindowRatingSpeedBonusRatio(jumpIndex, tier)
	local contextName = "LineWindow"
	if inAuto then
		tier, bonusRatio, contextName = RunwaySession.ResolveAutoBeforeLineRating(jumpIndex, humanoid.RootPart)
	elseif inLineWindow then
		if localState.tHudStart ~= nil then
			tier, bonusRatio, contextName =
				RunwaySession.ResolveTimedWindowRating(nowClock - (localState.tHudStart :: number), jumpIndex, "TimedWindow")
		else
			-- 触线后计时器需稳定贴地才启动；此期间起跳按距 BeginLine 距离评分（与 AutoRun 提前跳一致）。
			tier, bonusRatio, contextName = RunwaySession.ResolveAutoBeforeLineRating(jumpIndex, humanoid.RootPart)
		end
	elseif inChainWindow then
		if localState.tHudStart ~= nil then
			tier, bonusRatio, contextName =
				RunwaySession.ResolveTimedWindowRating(nowClock - (localState.tHudStart :: number), jumpIndex, "TimedWindow")
		else
			tier, bonusRatio, contextName = RunwaySession.ResolveChainDistanceRating(humanoid, jumpIndex)
		end
	else
		return
	end
	local addedBonus, nextMaxSpeed, cumulativeBonus, reductionDelta =
		RunwaySession.ApplyJumpSpeedRatingForBonusRatio(bonusRatio, currentBaseSpeed)
	localState.ratingTier = tier
	ClientMsg.FireJumpRunWayShowRatingTier(tier)
	--RunwaySession.LogJumpRunwayRating(
	--	jumpIndex,
	--	contextName,
	--	tier,
	--	bonusRatio,
	--	addedBonus,
	--	currentBaseSpeed,
	--	nextMaxSpeed,
	--	cumulativeBonus,
	--	reductionDelta
	--)
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
		localState.jumpWindowGroundedStartClock = nil
		localState.chainJumpWindowAwaitingGround = false
		localState.takeoffCount += 1
		RunwaySession.JumpGrantDashFuelIfOnFinalSegment()
		localState.phase = Ph.Airborne
	elseif inChainWindow then
		localState.takeoffCount += 1
		RunwaySession.JumpGrantDashFuelIfOnFinalSegment()
		localState.predictJumpWindowUntil = nil
		localState.tHudStart = nil
		localState.jumpWindowGroundedStartClock = nil
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
	-- 基于起跳前最终减速完的速度计算本次评级 bonus，再取冲量 max；终局叠冲刺在 UpdateAutoRunVelocity。
	RunwaySession.JumpApplyRatingForTakeoff(humanoid, nowClock, inAuto, inLineWindow, inChainWindow)
	local impulseSeg = math.clamp(localState.takeoffCount + 1, 1, cfg.N_TOTAL_JUMPS)
	local forwardSpd = select(
		1,
		GameConfig.GetJumpRunwayJumpSpeedLimitsForSegment(
			impulseSeg,
			localState.jumpSpeedCumulativeRatingBonus,
			GetJumpPowerBaseSpeed(),
			localState.jumpSpeedCurrentReductionDelta
		)
	)
	-- 竖直速度 = 水平速度基准对应比例 + bonus 对应比例
	local bonusPart = forwardSpd - horizontalBaseSpeed
	vy += bonusPart * cfg.JUMP_VERTICAL_RATIO
	local stageName = if impulseSeg >= cfg.N_TOTAL_JUMPS then "Jump" .. tostring(impulseSeg) .. "_FinalAir" else "Jump" .. tostring(impulseSeg) .. "_Air"
	RunwaySession.TransitionDistanceLogStage(
		stageName,
		"takeoff",
		hrp,
		string.format(
			"jumpIndex=%d rating=%s forwardSpd=%.2f vy=%.2f bonusPart=%.2f",
			impulseSeg,
			tostring(localState.ratingTier),
			forwardSpd,
			vy,
			bonusPart
		)
	)
	RunwaySession.CacheFinalLandLandingAlongValue(forwardSpd)
	localState.jumpBoostVy = vy
	localState.jumpBoostUntilClock = nowClock + cfg.RUNWAY_JUMP_BOOST_HOLD_SEC
	hrp.AssemblyLinearVelocity = forward * forwardSpd + Vector3.new(0, vy, 0) + perpTerm
	--print(
	--	string.format(
	--		"[JumpApplyTakeoff] takeoffCount=%d forwardSpd=%.1f vy=%.1f bonusPart=%.1f",
	--		localState.takeoffCount,
	--		forwardSpd,
	--		vy,
	--		bonusPart
	--	)
	--)
	localState.jumpHorizLerpStartClock = nowClock
	localState.jumpHorizLerpDuration = RunwaySession.ComputeJumpHorizontalDecelerationDuration(vy, gGrav)
	localState.jumpHorizLerpInitialVy = vy
	if impulseSeg >= cfg.N_TOTAL_JUMPS then
		GameSoundManager.PlayJumpRunwayFinalTakeoffSound()
	else
		GameSoundManager.PlayJumpRunwayTakeoffSound()
	end
	RunwaySession.JumpAdvancePhaseAfterImpulse(inAuto, inLineWindow, inChainWindow)
	-- 冲量起跳后首帧 Raycast/Humanoid 仍常判贴地或 preland；若 prev* 为 false 会被当成「着地/快触地上升沿」
	-- 立刻武装链式 T_WINDOW，约 1s 超时进 Slide。置 true 表示上升沿已消费，仅真实再落地时才武装。
	localState.prevLocalGroundedForLand = true
	localState.prevPreLand = true
	localState.prevJumpWindowRayBand = true
	localState.firstGroundedInWindowClock = nil
	Refs.prevGroundedHeartbeat = true
	Refs.lastRunwayTakeoffClock = nowClock
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end)
	if localState.takeoffCount >= cfg.N_TOTAL_JUMPS then
		Refs.finalTakeoffForceFreefallUntilClock = nowClock + math.max(0.12, cfg.RUNWAY_JUMP_BOOST_HOLD_SEC)
		RunwaySession.ResetFinalJumpGuideSlowMotionApexGate()
		RunwaySession.DestroyRunwayRing()
		RunwaySession.EnsureDistanceRecorderFromTemplate(humanoid, hrp)
	end
	return true
end

function RunwaySession.JumpTry(): boolean
	local nowClock = os.clock()
	local jumpInputCooldownSec = cfg.JUMP_INPUT_COOLDOWN_SEC
	if typeof(jumpInputCooldownSec) ~= "number" or jumpInputCooldownSec ~= jumpInputCooldownSec or jumpInputCooldownSec < 0 then
		jumpInputCooldownSec = 0.18
	end
	if Refs.lastRunwayTakeoffClock ~= nil and nowClock - (Refs.lastRunwayTakeoffClock :: number) < jumpInputCooldownSec then
		return false
	end
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
	local inChainWindowPhase = localState.phase == Ph.Airborne
		and localState.takeoffCount >= 1
		and localState.takeoffCount < cfg.N_TOTAL_JUMPS
	if inAuto and localState.passedBeginLineOnce then
		return false
	end
	local _character, humanoid, hrp = RunwaySession.GetCharacterParts()
	if humanoid == nil or hrp == nil then
		return false
	end
	local inChainDistanceBand = inChainWindowPhase and RunwaySession.IsRunwayJumpWindowRayBandOk(humanoid)
	local inChainWindow = inChainWindowPhase
		and (
			inChainDistanceBand
			or localState.chainJumpWindowAwaitingGround
			or (
				localState.predictJumpWindowUntil ~= nil
				and nowClock < (localState.predictJumpWindowUntil :: number)
			)
		)
	if not inAuto and not inLineWindow and not inChainWindow then
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
		local okBegin, distToBegin, _maxDist = RunwaySession.ResolveBeginLineAlongMetrics(hrp)
		local distToBeginText = if okBegin then string.format("%.2f", distToBegin) else "n/a"
		print(
			`[RunwaySession] JumpTry takeoffCount={localState.takeoffCount} distFeet={string.format("%.2f", distFeet)}`
				.. ` distToBegin={distToBeginText} deltaT={string.format("%.3f", deltaT)} phase={localState.phase}`
		)
	end
	return RunwaySession.JumpApplyTakeoff(humanoid, hrp, nowClock, inAuto, inLineWindow, inChainWindow)
end

function RunwaySession.OnJumpRunwayState(payload: NetMsg.JumpRunwayStatePayload)
	RunwaySession.ApplyServerPayload(payload)
	RunwaySession.HudRefresh()
end

local function IsRunwayPrimaryActionInput(input: InputObject): boolean
	return input.KeyCode == Enum.KeyCode.Space
		or input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

function RunwaySession.OnInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if IsRunwayPrimaryActionInput(input) then
		if Refs.guideSlowMotionActive then
			RunwaySession.CompleteActiveRunwayGuideSlowMotion()
		end
		if RunwaySession.IsRunwayActivePhase(localState.phase) then
			if RunwaySession.JumpTry() then
				RunwaySession.NetReportJump()
			end
		end
	end
	-- 冲刺：与起跳相同的主操作键（Space / 左键 / 触摸）；终局空由 takeoffCount/fuel 决定是否叠加速
	if IsRunwayPrimaryActionInput(input) and RunwaySession.IsRunwayActivePhase(localState.phase) then
		if RunwaySession.IsFinalDashTutorialGateOpen() then
			localState.dashHeld = true
			RunwaySession.NetReportDashIfChanged()
		end
	end
end

function RunwaySession.OnInputEnded(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if IsRunwayPrimaryActionInput(input) then
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
	-- 进入跑道时收起所有手持 Tool
	humanoid:UnequipTools()
	NetMsg.FireRequestCompleteGuideStep(GameConfig.GuideStepKey.StartTriggerFinished)
	local currentGuideType = ClientGameInfo.GetCurrentGuideType()
	if currentGuideType == GameConfig.GuideType.TutorialJetpackRunwayRetry then
		NetMsg.FireRequestCompleteGuideStep(GameConfig.GuideStepKey.JetpackRunwayRetryFinished)
	elseif currentGuideType == GameConfig.GuideType.TutorialJumpPowerRunwayRetry then
		NetMsg.FireRequestCompleteGuideStep(GameConfig.GuideStepKey.JumpPowerRunwayRetryFinished)
	end
	ClientGameInfo.SetInJumpRunway(true)
	Refs.startTriggerStartArmed = false
	RunwaySession.DestroyDistanceRecorder()
	RunwaySession.SlideTraceDestroy()
	local forward = NormalizeRunwayForward(startTrigger.CFrame.RightVector)
	local origin = startTrigger.Position
	local sessionStartAlong = (hrp.Position - origin):Dot(forward)
	local beginLineAlong = RunwaySession.ResolveBeginLineAlongFromOrigin(forward, origin)
	local scoreBaselineAlong = if beginLineAlong ~= nil then beginLineAlong else sessionStartAlong
	RunwaySession.EnsureBestDistanceWall(forward, origin, scoreBaselineAlong)
	RunwaySession.AlignCharacterYawToRunwayForward(hrp, forward)
	localState.scriptedGroundHrpYBaseline = hrp.Position.Y
	localState.runwayForward = forward
	localState.runwayOrigin = origin
	localState.sessionStartAlong = sessionStartAlong
	localState.alongBaseline = scoreBaselineAlong
	localState.phase = Ph.AutoRun
	localState.takeoffCount = 0
	localState.dashHeld = false
	localState.jumpSpeedCumulativeRatingBonus = 0
	localState.jumpSpeedCurrentReductionDelta = 0
	localState.fuel = 0
	localState.ratingTier = nil
	localState.finalScore = nil
	localState.finalSent = false
	localState.groundedStableTime = 0
	localState.jumpBoostVy = nil
	localState.jumpBoostUntilClock = 0
	localState.predictJumpWindowUntil = nil
	localState.firstGroundedInWindowClock = nil
	localState.jumpWindowGroundedStartClock = nil
	localState.tHudStart = nil
	Refs.lastRunwayTakeoffClock = nil
	Refs.slideEndFallbackWarnNextClock = 0
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
	localState.finalLandPhaseAGroundedStartClock = nil
	localState.finalLandLockedTumbleAlong = 0
	localState.finalLandTumblePrevPopVy = 0
	localState.finalLandTumbleRollAngleRad = 0
	localState.finalLandProneBStage = 0
	localState.finalLandPronePrefallStartClock = 0
	localState.finalLandProneSlideAlongStart = nil
	localState.finalLandCachedLandingVy = nil
	localState.finalLandCachedLandingAlong = nil
	RunwaySession.ClearJumpHorizontalLerp()
	localState.finalDashAlongExtra = 0
	Refs.finalPitchSmoothedExtraDeg = 0
	localState.lastSampleSendClock = 0
	localState.lastSampleAlong = scoreBaselineAlong
	RunwaySession.ResetDistanceLog()
	RunwaySession.StartDistanceLogStage("AutoRun", RunwaySession.CurrentAlongProgress(hrp), nowClock)
	RunwayNetBridge.FireStartSession(NetMsg, Kind, forward, origin, scoreBaselineAlong)
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
	RunwaySession.UpdateRunwayRingTransform(humanoid, hrp, 0)
	local okBaseline, baselineDist = RunwaySession.RaycastFeet(humanoid)
	localState.preLandRayBaselineStuds = if okBaseline then baselineDist else nil
	localState.prevLocalGroundedForLand = RunwaySession.IsRunwayScriptedGrounded(humanoid)
	localState.prevPreLand = RunwaySession.IsRunwayPreLanding(humanoid)
	localState.prevJumpWindowRayBand = RunwaySession.IsRunwayJumpWindowRayBandOk(humanoid)
	Refs.finalTakeoffForceFreefallUntilClock = 0
	RunwaySession.ResetFinalJumpGuideSlowMotionApexGate()
	Refs.prevGroundedHeartbeat = localState.prevLocalGroundedForLand
	RunwayCameraController.Enable(workspace, cfg, hrp, localState.runwayForward, NormalizeRunwayForward)
	RunwaySession.EnsureJumpRunwayRocketBackpack(character)
	UIManager.OpenWindow(UIManager.WindowId.JumpRunWayFrame)
	return true
end

function RunwaySession.BindSceneTriggers()
	if Refs.startTriggerConn then
		Refs.startTriggerConn:Disconnect()
		Refs.startTriggerConn = nil
	end
	if Refs.endTriggerConn then
		Refs.endTriggerConn:Disconnect()
		Refs.endTriggerConn = nil
	end
	if Refs.beginLineConn then
		Refs.beginLineConn:Disconnect()
		Refs.beginLineConn = nil
	end
	local startTrigger, beginLine = RunwaySession.ResolveSceneParts()
	local endTrigger = RunwaySession.ResolveEndTrigger()
	if startTrigger then
		Refs.startTriggerConn = startTrigger.Touched:Connect(function(hit)
			local ch = hit:FindFirstAncestorOfClass("Model")
			if ch ~= nil and ch == localPlayer.Character then
				local _character, humanoid, hrp = RunwaySession.GetCharacterParts()
				if humanoid == nil or hrp == nil then
					return
				end
				if RunwaySession.ShouldBlockJumpRunwayStartAtStartTrigger() then
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
	if endTrigger then
		Refs.endTriggerConn = endTrigger.Touched:Connect(function(hit)
			local ch = hit:FindFirstAncestorOfClass("Model")
			if ch ~= nil and ch == localPlayer.Character then
				if RunwaySession.IsLocalPlayerCarryingRunwayLittleElfChest(ch) then
					RunwaySession.TryDeliverLittleElfChestAtEndTrigger(endTrigger)
					return
				end
				if Refs.chestCarryReturnActive == true then
					RunwaySession.TryExitEscapePhaseAtEndTrigger(endTrigger)
				end
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
	RunwaySession.UpdateEndTriggerReentryState()
	RunwaySession.NetReportDashIfChanged()
	RunwayFxController.UpdateHeartbeat(RunwaySession.UpdateJetpackFlameDashFx, os.clock())
	RunwayUiController.Refresh(
		RunwaySession.HudRefresh
	)
	if ClientGameInfo.IsInJumpRunwayEscapePhase() then
		local _, _, hrp = RunwaySession.GetCharacterParts()
		RunwaySession.RefreshJumpRunWayFrameStats(hrp)
	end
end

function RunwaySession.OnCameraRenderStep(dt: number)
	local cameraSmoothSpeed: number? = nil
	if localState.phase == Ph.Slide and localState.runwaySlideKind == SlideKindObstacleBounce then
		local bounceSmooth = cfg.RUNWAY_CAMERA_BOUNCE_SMOOTH_SPEED
		if typeof(bounceSmooth) == "number" and bounceSmooth == bounceSmooth and bounceSmooth > 0 then
			cameraSmoothSpeed = bounceSmooth
		end
	end
	RunwayCameraController.Update(
		workspace,
		cfg,
		dt,
		localState.phase,
		RunwaySession.IsRunwayActivePhase,
		RunwaySession.GetCharacterParts,
		localState.runwayForward,
		NormalizeRunwayForward,
		cameraSmoothSpeed
	)
end

function RunwaySession.BindInput()
	userInputService.InputBegan:Connect(RunwaySession.OnInputBegan)
	userInputService.InputEnded:Connect(RunwaySession.OnInputEnded)
end

function RunwaySession.BindRunwayExitOnCharacterDeathOrRemove()
	local function resetIfRunwayActive()
		if
			RunwaySession.IsRunwayActivePhase(localState.phase)
			or Refs.chestCarryReturnActive == true
			or ClientGameInfo.IsInJumpRunwayEscapePhase()
		then
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
	NetMsg.ConnectNotifyJumpRunwayLittleElfChestReward(function(brainrotId: number, chestConfigId: number, chestLevel: number, variantId: number)
		RunwaySession.OnLittleElfChestRewardReceived(brainrotId, chestConfigId, chestLevel, variantId)
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
	runService:BindToRenderStep(
		GuideSlowMotionAnimRenderStepName,
		Enum.RenderPriority.Last.Value,
		RunwaySession.OnGuideSlowMotionAnimRenderStep
	)
end

NetMsg.ConnectNotifyJumpRunwayState(RunwaySession.OnJumpRunwayState)

return RunwaySession
