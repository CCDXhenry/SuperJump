--!strict

local RunwayConstants = {}

RunwayConstants.Ph = {
	Idle = 0,
	AutoRun = 1,
	JumpWindow = 3,
	Airborne = 4,
	Slide = 6,
	RunEnded = 7,
	ScoreLocked = 8,
	Cleaning = 9,
}

RunwayConstants.Kind = {
	Input = 1,
	Sample = 2,
	Final = 3,
	Start = 4,
	Abort = 5,
}

RunwayConstants.SlideKindStandard = "standard"
RunwayConstants.SlideKindFinalLanding = "finalLanding"
RunwayConstants.SlideKindMiss = "miss"
RunwayConstants.SlideKindObstacleBounce = "obstacleBounce"
RunwayConstants.RunwaySlideTraceDestroyAfterEndSec = 5
RunwayConstants.RunwayCameraRenderStepName = "JumpRunwayCamera"
RunwayConstants.RunwayFinalTiltRenderStepName = "JumpRunwayFinalBodyTilt"
RunwayConstants.RunwayRingTemplateName = "JumpRunwayRing"
RunwayConstants.RunwaySlideTraceTemplateName = "SlideTraceTrail"
RunwayConstants.RunwayJumpSmokeTemplateName = "JumpSmoke"
RunwayConstants.ScpTrampolineModelName = "SCP-Trampoline"
RunwayConstants.ScpTrampolineSpringPartName = "Spring"
RunwayConstants.ScpTrampolineBounceCooldownSec = 0.2

function RunwayConstants.IsRunwayActivePhase(phase: number): boolean
	return phase ~= RunwayConstants.Ph.Idle and phase ~= RunwayConstants.Ph.Cleaning
end

return RunwayConstants
