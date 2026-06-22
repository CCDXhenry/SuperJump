--!strict

local RunwayStateStore = {}

export type RunwayStateStoreShape = {
	phase: number,
	runwayForward: Vector3,
	runwayOrigin: Vector3?,
	alongBaseline: number?,
	sessionStartAlong: number?,
	takeoffCount: number,
	jumpSpeedCumulativeRatingBonus: number,
	jumpSpeedCurrentReductionDelta: number,
	fuel: number,
	ratingTier: number?,
	lastQtePercent: number?,
	autoChainRatingTier: number?,
	autoChainRatingBandRatio: number?,
	finalScore: number?,
	dashHeld: boolean,
	lastSampleSendClock: number,
	lastReportedDashHeld: boolean,
	lastReportedFinalDashThrustActive: boolean,
	lastSampleAlong: number,
	controlsDisabled: boolean,
	finalSent: boolean,
	groundedStableTime: number,
	jumpBoostVy: number?,
	jumpBoostUntilClock: number,
	predictJumpWindowUntil: number?,
	prevLocalGroundedForLand: boolean,
	prevPreLand: boolean,
	prevJumpWindowRayBand: boolean,
	preLandRayBaselineStuds: number?,
	scriptedGroundHrpYBaseline: number?,
	firstGroundedInWindowClock: number?,
	jumpWindowGroundedStartClock: number?,
	tHudStart: number?,
	lineJumpWindowExpireAt: number?,
	lineWindowConsumed: boolean,
	chainJumpWindowAwaitingGround: boolean,
	passedBeginLineOnce: boolean,
	jumpedBeforeBeginLine: boolean,
	slideStartClock: number,
	slideEndClock: number,
	jumpHorizLerpStartClock: number?,
	jumpHorizLerpDuration: number,
	jumpHorizLerpInitialVy: number?,
	finalDashAlongExtra: number,
	runwaySlideKind: string,
	finalLandSubPhase: number,
	finalLandPronePhaseStartClock: number,
	finalLandPhaseAPopCount: number,
	finalLandProneSlideAlongSpeedStart: number,
	finalLandTumbleImpulseApplied: boolean,
	finalLandTumblePredAirTimeSec: number,
	finalLandTumbleAirAccumSec: number,
	finalLandTumbleLeftGround: boolean,
	finalLandTumbleUseAirClock: boolean,
	finalLandPhaseAGroundedStartClock: number?,
	finalLandLockedTumbleAlong: number,
	finalLandTumblePrevPopVy: number,
	finalLandTumbleRollAngleRad: number,
	finalLandProneBStage: number,
	finalLandPronePrefallStartClock: number,
	finalLandProneSlideAlongStart: number?,
	finalLandCachedLandingVy: number?,
	finalLandCachedLandingAlong: number?,
}

function RunwayStateStore.CreateDefault(phases: any, slideKindStandard: string): RunwayStateStoreShape
	return {
		phase = phases.Idle,
		runwayForward = Vector3.xAxis,
		runwayOrigin = nil,
		alongBaseline = nil,
		sessionStartAlong = nil,
		takeoffCount = 0,
		jumpSpeedCumulativeRatingBonus = 0,
		jumpSpeedCurrentReductionDelta = 0,
		fuel = 0,
		ratingTier = nil,
		lastQtePercent = nil,
		autoChainRatingTier = nil,
		autoChainRatingBandRatio = nil,
		finalScore = nil,
		dashHeld = false,
		lastSampleSendClock = 0,
		lastReportedDashHeld = false,
		lastReportedFinalDashThrustActive = false,
		lastSampleAlong = 0,
		controlsDisabled = false,
		finalSent = false,
		groundedStableTime = 0,
		jumpBoostVy = nil,
		jumpBoostUntilClock = 0,
		predictJumpWindowUntil = nil,
		prevLocalGroundedForLand = true,
		prevPreLand = false,
		prevJumpWindowRayBand = false,
		preLandRayBaselineStuds = nil,
		scriptedGroundHrpYBaseline = nil,
		firstGroundedInWindowClock = nil,
		jumpWindowGroundedStartClock = nil,
		tHudStart = nil,
		lineJumpWindowExpireAt = nil,
		lineWindowConsumed = false,
		chainJumpWindowAwaitingGround = false,
		passedBeginLineOnce = false,
		jumpedBeforeBeginLine = false,
		slideStartClock = 0,
		slideEndClock = 0,
		jumpHorizLerpStartClock = nil,
		jumpHorizLerpDuration = 0,
		jumpHorizLerpInitialVy = nil,
		finalDashAlongExtra = 0,
		runwaySlideKind = slideKindStandard,
		finalLandSubPhase = 1,
		finalLandPronePhaseStartClock = 0,
		finalLandPhaseAPopCount = 0,
		finalLandProneSlideAlongSpeedStart = 0,
		finalLandTumbleImpulseApplied = false,
		finalLandTumblePredAirTimeSec = 0,
		finalLandTumbleAirAccumSec = 0,
		finalLandTumbleLeftGround = false,
		finalLandTumbleUseAirClock = false,
		finalLandPhaseAGroundedStartClock = nil,
		finalLandLockedTumbleAlong = 0,
		finalLandTumblePrevPopVy = 0,
		finalLandTumbleRollAngleRad = 0,
		finalLandProneBStage = 0,
		finalLandPronePrefallStartClock = 0,
		finalLandProneSlideAlongStart = nil,
		finalLandCachedLandingVy = nil,
		finalLandCachedLandingAlong = nil,
	}
end

function RunwayStateStore.ResetForIdle(localState: RunwayStateStoreShape, phases: any, slideKindStandard: string)
	localState.phase = phases.Idle
	localState.runwayOrigin = nil
	localState.alongBaseline = nil
	localState.sessionStartAlong = nil
	localState.takeoffCount = 0
	localState.jumpSpeedCumulativeRatingBonus = 0
	localState.jumpSpeedCurrentReductionDelta = 0
	localState.fuel = 0
	localState.ratingTier = nil
	localState.lastQtePercent = nil
	localState.autoChainRatingTier = nil
	localState.autoChainRatingBandRatio = nil
	localState.finalScore = nil
	localState.finalSent = false
	localState.groundedStableTime = 0
	localState.jumpBoostVy = nil
	localState.jumpBoostUntilClock = 0
	localState.predictJumpWindowUntil = nil
	localState.prevLocalGroundedForLand = true
	localState.prevPreLand = false
	localState.prevJumpWindowRayBand = false
	localState.preLandRayBaselineStuds = nil
	localState.scriptedGroundHrpYBaseline = nil
	localState.firstGroundedInWindowClock = nil
	localState.jumpWindowGroundedStartClock = nil
	localState.tHudStart = nil
	localState.lineJumpWindowExpireAt = nil
	localState.lineWindowConsumed = false
	localState.chainJumpWindowAwaitingGround = false
	localState.passedBeginLineOnce = false
	localState.jumpedBeforeBeginLine = false
	localState.slideStartClock = 0
	localState.slideEndClock = 0
	localState.jumpHorizLerpStartClock = nil
	localState.jumpHorizLerpDuration = 0
	localState.jumpHorizLerpInitialVy = nil
	localState.runwaySlideKind = slideKindStandard
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
	localState.finalDashAlongExtra = 0
	localState.lastSampleSendClock = 0
	localState.lastSampleAlong = 0
end

return RunwayStateStore
