--!strict

local RunwayCameraController = {}

local runService = game:GetService("RunService")

type CameraState = {
	active: boolean,
	cameraTypeBeforeRunway: Enum.CameraType?,
	cameraSubjectBeforeRunway: Instance?,
	cameraFovBeforeRunway: number?,
	smoothedCameraPosition: Vector3?,
	smoothedCameraLookAt: Vector3?,
	releaseTransitionToken: number,
}

local state: CameraState = {
	active = false,
	cameraTypeBeforeRunway = nil,
	cameraSubjectBeforeRunway = nil,
	cameraFovBeforeRunway = nil,
	smoothedCameraPosition = nil,
	smoothedCameraLookAt = nil,
	releaseTransitionToken = 0,
}

local function ResolveReleaseTransitionDuration(cfg: any?): number
	if cfg == nil then
		return 0
	end
	local duration = cfg.RUNWAY_CAMERA_RELEASE_TRANSITION_SEC
	if typeof(duration) ~= "number" or duration ~= duration or duration < 0 then
		return 0.35
	end
	return duration
end

local function ResolveChaserFocusTransitionDuration(cfg: any?): number
	if cfg == nil then
		return 0.6
	end
	local duration = cfg.CHASER_CAMERA_FOCUS_TRANSITION_SEC
	if typeof(duration) ~= "number" or duration ~= duration or duration < 0 then
		return 0.6
	end
	return duration
end

local function ResolveChaserFocusHoldDuration(cfg: any?): number
	if cfg == nil then
		return 1
	end
	local duration = cfg.CHASER_CAMERA_FOCUS_HOLD_SEC
	if typeof(duration) ~= "number" or duration ~= duration or duration < 0 then
		return 1
	end
	return duration
end

local function ResolveChaserReturnHomeTransitionDuration(cfg: any?): number
	if cfg == nil then
		return 0.35
	end
	local duration = cfg.CHASER_CAMERA_RETURN_HOME_TRANSITION_SEC
	if typeof(duration) ~= "number" or duration ~= duration or duration < 0 then
		return 0.35
	end
	return duration
end

local function RestoreCameraControl(
	camera: Camera,
	restoreCameraType: Enum.CameraType?,
	restoreSubject: Instance?,
	restoreFov: number?,
	getCharacterParts: () -> (Model?, Humanoid?, BasePart?)
)
	if restoreSubject ~= nil and restoreSubject.Parent ~= nil then
		camera.CameraSubject = restoreSubject
	else
		local _, humanoid, _ = getCharacterParts()
		if humanoid ~= nil then
			camera.CameraSubject = humanoid
		end
	end
	if restoreFov ~= nil then
		camera.FieldOfView = restoreFov
	end
	if restoreCameraType ~= nil then
		camera.CameraType = restoreCameraType
	else
		camera.CameraType = Enum.CameraType.Custom
	end
end

local function HasRestoreSnapshot(): boolean
	return state.cameraTypeBeforeRunway ~= nil
		or state.cameraSubjectBeforeRunway ~= nil
		or state.cameraFovBeforeRunway ~= nil
end

local function ClearRestoreSnapshot(transitionToken: number?)
	if transitionToken ~= nil and state.releaseTransitionToken ~= transitionToken then
		return
	end
	if state.active then
		return
	end
	state.cameraTypeBeforeRunway = nil
	state.cameraSubjectBeforeRunway = nil
	state.cameraFovBeforeRunway = nil
end

local function PlayCameraTransition(
	camera: Camera,
	transitionToken: number,
	duration: number,
	startCFrame: CFrame,
	targetCFrame: CFrame,
	startFov: number,
	targetFov: number
): boolean
	local elapsed = 0
	while elapsed < duration do
		if state.releaseTransitionToken ~= transitionToken then
			return false
		end
		if camera.Parent == nil then
			return false
		end
		local dt = runService.RenderStepped:Wait()
		elapsed += dt
		local t = math.clamp(elapsed / duration, 0, 1)
		local eased = t * t * (3 - 2 * t)
		camera.CFrame = startCFrame:Lerp(targetCFrame, eased)
		camera.FieldOfView = startFov + (targetFov - startFov) * eased
	end
	if state.releaseTransitionToken ~= transitionToken then
		return false
	end
	if camera.Parent == nil then
		return false
	end
	camera.CFrame = targetCFrame
	camera.FieldOfView = targetFov
	return true
end

local function PlayHold(camera: Camera, transitionToken: number, holdDuration: number): boolean
	local elapsed = 0
	while elapsed < holdDuration do
		if state.releaseTransitionToken ~= transitionToken then
			return false
		end
		if camera.Parent == nil then
			return false
		end
		elapsed += runService.RenderStepped:Wait()
	end
	return state.releaseTransitionToken == transitionToken and camera.Parent ~= nil
end

local function PlayReleaseTransition(
	camera: Camera,
	transitionToken: number,
	releaseDuration: number,
	startCFrame: CFrame,
	targetCFrame: CFrame,
	startFov: number,
	targetFov: number,
	restoreCameraType: Enum.CameraType?,
	restoreSubject: Instance?,
	restoreFov: number?,
	getCharacterParts: () -> (Model?, Humanoid?, BasePart?),
	onComplete: (() -> ())?
)
	if not PlayCameraTransition(camera, transitionToken, releaseDuration, startCFrame, targetCFrame, startFov, targetFov) then
		return
	end
	RestoreCameraControl(camera, restoreCameraType, restoreSubject, restoreFov, getCharacterParts)
	if onComplete ~= nil then
		onComplete()
	end
	ClearRestoreSnapshot(transitionToken)
end

local function InvokeOnCompleteOnce(onComplete: (() -> ())?, invoked: { boolean })
	if onComplete == nil or invoked[1] then
		return
	end
	invoked[1] = true
	onComplete()
end

function RunwayCameraController.CalculateTargets(hrp: BasePart, runwayForward: Vector3, cfg: any, normalizeForward: (Vector3) -> Vector3): (Vector3, Vector3)
	local forward = normalizeForward(runwayForward)
	local right = forward:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-4 then
		right = Vector3.xAxis
	else
		right = right.Unit
	end
	local targetLookAt = hrp.Position + forward * cfg.RUNWAY_CAMERA_LOOK_AHEAD
		+ Vector3.new(0, cfg.RUNWAY_CAMERA_LOOK_HEIGHT, 0)
	local targetPosition = hrp.Position - forward * cfg.RUNWAY_CAMERA_BACK_OFFSET
		+ right * cfg.RUNWAY_CAMERA_RIGHT_OFFSET
		+ Vector3.new(0, cfg.RUNWAY_CAMERA_HEIGHT_OFFSET, 0)
	if (targetLookAt - targetPosition).Magnitude < 1e-3 then
		targetLookAt += forward
	end
	return targetPosition, targetLookAt
end

function RunwayCameraController.CalculateChaserFocusTarget(
	chaser: Model,
	hrp: BasePart?,
	fallbackForward: Vector3,
	cfg: any,
	normalizeForward: (Vector3) -> Vector3
): CFrame
	local chaserHead = chaser:FindFirstChild("Head") :: BasePart?
	print("chaserHead", chaserHead)
	local centerPos = if chaserHead ~= nil then chaserHead.Position else chaser:GetPivot().Position
	local lookAt = centerPos
	local toPlayer = if hrp ~= nil then Vector3.new(hrp.Position.X - centerPos.X, 0, hrp.Position.Z - centerPos.Z) else Vector3.zero
	if toPlayer.Magnitude < 1e-4 then
		toPlayer = -normalizeForward(fallbackForward)
	else
		toPlayer = toPlayer.Unit
	end
	local right = toPlayer:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-4 then
		right = Vector3.xAxis
	else
		right = right.Unit
	end
	local distance = cfg.CHASER_CAMERA_FOCUS_DISTANCE_STUDS
	if typeof(distance) ~= "number" or distance ~= distance or distance <= 0 then
		distance = 32
	end
	local rightOffset = cfg.CHASER_CAMERA_FOCUS_RIGHT_OFFSET_STUDS
	if typeof(rightOffset) ~= "number" or rightOffset ~= rightOffset then
		rightOffset = 0
	end
	local heightOffset = cfg.CHASER_CAMERA_FOCUS_HEIGHT_OFFSET_STUDS
	if typeof(heightOffset) ~= "number" or heightOffset ~= heightOffset then
		heightOffset = 8
	end
	local cameraPos = centerPos + toPlayer * distance + right * rightOffset + Vector3.new(0, heightOffset, 0)
	if (lookAt - cameraPos).Magnitude < 1e-3 then
		cameraPos += Vector3.new(0, 0, 1)
	end
	return CFrame.lookAt(cameraPos, lookAt, Vector3.yAxis)
end

function RunwayCameraController.Enable(workspaceRef: Workspace, cfg: any, hrp: BasePart, runwayForward: Vector3, normalizeForward: (Vector3) -> Vector3)
	local camera = workspaceRef.CurrentCamera
	if camera == nil then
		return
	end
	state.releaseTransitionToken += 1
	if not state.active and not HasRestoreSnapshot() then
		state.cameraTypeBeforeRunway = camera.CameraType
		state.cameraSubjectBeforeRunway = camera.CameraSubject
		state.cameraFovBeforeRunway = camera.FieldOfView
	end
	state.active = true
	local targetPosition, targetLookAt = RunwayCameraController.CalculateTargets(hrp, runwayForward, cfg, normalizeForward)
	state.smoothedCameraPosition = targetPosition
	state.smoothedCameraLookAt = targetLookAt
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = cfg.RUNWAY_CAMERA_FOV
	camera.CFrame = CFrame.lookAt(targetPosition, targetLookAt, Vector3.yAxis)
end

function RunwayCameraController.Disable(
	workspaceRef: Workspace,
	getCharacterParts: () -> (Model?, Humanoid?, BasePart?),
	releaseForward: Vector3?,
	cfg: any?,
	normalizeForward: ((Vector3) -> Vector3)?,
	onFocusSequenceComplete: (() -> ())?
)
	state.smoothedCameraPosition = nil
	state.smoothedCameraLookAt = nil
	if not state.active then
		return
	end
	state.active = false
	local camera = workspaceRef.CurrentCamera
	if camera ~= nil then
		state.releaseTransitionToken += 1
		local transitionToken = state.releaseTransitionToken
		local restoreCameraType = state.cameraTypeBeforeRunway
		local restoreSubject = state.cameraSubjectBeforeRunway
		local restoreFov = state.cameraFovBeforeRunway
		local releaseDuration = ResolveReleaseTransitionDuration(cfg)
		local completeInvoked = { false }
		if releaseForward ~= nil and cfg ~= nil and normalizeForward ~= nil then
			local _character, _humanoid, hrp = getCharacterParts()
			if hrp ~= nil and releaseDuration > 0 then
				local targetPosition, targetLookAt = RunwayCameraController.CalculateTargets(hrp, releaseForward, cfg, normalizeForward)
				local startCFrame = camera.CFrame
				local targetCFrame = CFrame.lookAt(targetPosition, targetLookAt, Vector3.yAxis)
				local startFov = camera.FieldOfView
				local targetFov = restoreFov or startFov
				camera.CameraType = Enum.CameraType.Scriptable
				task.spawn(function()
					PlayReleaseTransition(
						camera,
						transitionToken,
						releaseDuration,
						startCFrame,
						targetCFrame,
						startFov,
						targetFov,
						restoreCameraType,
						restoreSubject,
						restoreFov,
						getCharacterParts,
						function()
							InvokeOnCompleteOnce(onFocusSequenceComplete, completeInvoked)
						end
					)
				end)
			elseif hrp ~= nil then
				local targetPosition, targetLookAt = RunwayCameraController.CalculateTargets(hrp, releaseForward, cfg, normalizeForward)
				camera.CFrame = CFrame.lookAt(targetPosition, targetLookAt, Vector3.yAxis)
				RestoreCameraControl(camera, restoreCameraType, restoreSubject, restoreFov, getCharacterParts)
				InvokeOnCompleteOnce(onFocusSequenceComplete, completeInvoked)
				ClearRestoreSnapshot(transitionToken)
			else
				RestoreCameraControl(camera, restoreCameraType, restoreSubject, restoreFov, getCharacterParts)
				InvokeOnCompleteOnce(onFocusSequenceComplete, completeInvoked)
				ClearRestoreSnapshot(transitionToken)
			end
		else
			RestoreCameraControl(camera, restoreCameraType, restoreSubject, restoreFov, getCharacterParts)
			InvokeOnCompleteOnce(onFocusSequenceComplete, completeInvoked)
			ClearRestoreSnapshot(transitionToken)
		end
	else
		ClearRestoreSnapshot(nil)
	end
end

function RunwayCameraController.FocusChaserThenDisable(
	workspaceRef: Workspace,
	getCharacterParts: () -> (Model?, Humanoid?, BasePart?),
	chaser: Model?,
	releaseForward: Vector3,
	cfg: any,
	normalizeForward: (Vector3) -> Vector3,
	onFocusSequenceComplete: (() -> ())?
)
	if chaser == nil or chaser.Parent == nil then
		RunwayCameraController.Disable(
			workspaceRef,
			getCharacterParts,
			releaseForward,
			cfg,
			normalizeForward,
			onFocusSequenceComplete
		)
		return
	end
	state.smoothedCameraPosition = nil
	state.smoothedCameraLookAt = nil
	if not state.active then
		return
	end
	state.active = false
	local camera = workspaceRef.CurrentCamera
	if camera == nil then
		return
	end
	state.releaseTransitionToken += 1
	local transitionToken = state.releaseTransitionToken
	local restoreCameraType = state.cameraTypeBeforeRunway
	local restoreSubject = state.cameraSubjectBeforeRunway
	local restoreFov = state.cameraFovBeforeRunway
	local focusDuration = ResolveChaserFocusTransitionDuration(cfg)
	local holdDuration = ResolveChaserFocusHoldDuration(cfg)
	local releaseDuration = ResolveChaserReturnHomeTransitionDuration(cfg)
	local _character, _humanoid, hrp = getCharacterParts()
	local focusCFrame = RunwayCameraController.CalculateChaserFocusTarget(chaser, hrp, releaseForward, cfg, normalizeForward)
	local startCFrame = camera.CFrame
	local startFov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	local completeInvoked = { false }
	task.spawn(function()
		if focusDuration > 0 then
			if not PlayCameraTransition(camera, transitionToken, focusDuration, startCFrame, focusCFrame, startFov, cfg.RUNWAY_CAMERA_FOV) then
				return
			end
		else
			camera.CFrame = focusCFrame
			camera.FieldOfView = cfg.RUNWAY_CAMERA_FOV
		end
		if not PlayHold(camera, transitionToken, holdDuration) then
			return
		end
		local _releaseCharacter, _releaseHumanoid, releaseHrp = getCharacterParts()
		if releaseHrp ~= nil then
			local targetPosition, targetLookAt = RunwayCameraController.CalculateTargets(
				releaseHrp,
				releaseForward,
				cfg,
				normalizeForward
			)
			local targetCFrame = CFrame.lookAt(targetPosition, targetLookAt, Vector3.yAxis)
			local targetFov = restoreFov or camera.FieldOfView
			if releaseDuration > 0 then
				PlayReleaseTransition(
					camera,
					transitionToken,
					releaseDuration,
					camera.CFrame,
					targetCFrame,
					camera.FieldOfView,
					targetFov,
					restoreCameraType,
					restoreSubject,
					restoreFov,
					getCharacterParts,
					function()
						InvokeOnCompleteOnce(onFocusSequenceComplete, completeInvoked)
					end
				)
			else
				camera.CFrame = targetCFrame
				camera.FieldOfView = targetFov
				RestoreCameraControl(camera, restoreCameraType, restoreSubject, restoreFov, getCharacterParts)
				InvokeOnCompleteOnce(onFocusSequenceComplete, completeInvoked)
				ClearRestoreSnapshot(transitionToken)
			end
		else
			RestoreCameraControl(camera, restoreCameraType, restoreSubject, restoreFov, getCharacterParts)
			InvokeOnCompleteOnce(onFocusSequenceComplete, completeInvoked)
			ClearRestoreSnapshot(transitionToken)
		end
	end)
end

function RunwayCameraController.Update(
	workspaceRef: Workspace,
	cfg: any,
	dt: number,
	phase: number,
	isRunwayActivePhase: (number) -> boolean,
	getCharacterParts: () -> (Model?, Humanoid?, BasePart?),
	runwayForward: Vector3,
	normalizeForward: (Vector3) -> Vector3,
	smoothSpeedOverride: number?
)
	if not state.active then
		return
	end
	if not isRunwayActivePhase(phase) then
		RunwayCameraController.Disable(workspaceRef, getCharacterParts, runwayForward, cfg, normalizeForward)
		return
	end
	local camera = workspaceRef.CurrentCamera
	if camera == nil then
		return
	end
	local _character, _humanoid, hrp = getCharacterParts()
	if hrp == nil then
		RunwayCameraController.Disable(workspaceRef, getCharacterParts)
		return
	end
	local targetPosition, targetLookAt = RunwayCameraController.CalculateTargets(hrp, runwayForward, cfg, normalizeForward)
	local currentPosition: Vector3 = state.smoothedCameraPosition or targetPosition
	local currentLookAt: Vector3 = state.smoothedCameraLookAt or targetLookAt
	local smoothSpeed = smoothSpeedOverride
	if typeof(smoothSpeed) ~= "number" or smoothSpeed ~= smoothSpeed or smoothSpeed <= 0 then
		smoothSpeed = math.max(0, cfg.RUNWAY_CAMERA_SMOOTH_SPEED)
	end
	local alpha = 1 - math.exp(-math.max(0, dt) * smoothSpeed)
	local nextPosition = currentPosition:Lerp(targetPosition, alpha)
	local nextLookAt = currentLookAt:Lerp(targetLookAt, alpha)
	state.smoothedCameraPosition = nextPosition
	state.smoothedCameraLookAt = nextLookAt
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = cfg.RUNWAY_CAMERA_FOV
	camera.CFrame = CFrame.lookAt(nextPosition, nextLookAt, Vector3.yAxis)
end

return RunwayCameraController
