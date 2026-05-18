--!strict

local RunwayCameraController = {}

type CameraState = {
	active: boolean,
	cameraTypeBeforeRunway: Enum.CameraType?,
	cameraSubjectBeforeRunway: Instance?,
	cameraFovBeforeRunway: number?,
	smoothedCameraPosition: Vector3?,
	smoothedCameraLookAt: Vector3?,
}

local state: CameraState = {
	active = false,
	cameraTypeBeforeRunway = nil,
	cameraSubjectBeforeRunway = nil,
	cameraFovBeforeRunway = nil,
	smoothedCameraPosition = nil,
	smoothedCameraLookAt = nil,
}

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

function RunwayCameraController.Enable(workspaceRef: Workspace, cfg: any, hrp: BasePart, runwayForward: Vector3, normalizeForward: (Vector3) -> Vector3)
	local camera = workspaceRef.CurrentCamera
	if camera == nil then
		return
	end
	if not state.active then
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

function RunwayCameraController.Disable(workspaceRef: Workspace, getCharacterParts: () -> (Model?, Humanoid?, BasePart?))
	state.smoothedCameraPosition = nil
	state.smoothedCameraLookAt = nil
	if not state.active then
		return
	end
	state.active = false
	local camera = workspaceRef.CurrentCamera
	if camera ~= nil then
		local restoreCameraType = state.cameraTypeBeforeRunway
		if restoreCameraType ~= nil then
			camera.CameraType = restoreCameraType
		else
			camera.CameraType = Enum.CameraType.Custom
		end
		local restoreSubject = state.cameraSubjectBeforeRunway
		if restoreSubject ~= nil and restoreSubject.Parent ~= nil then
			camera.CameraSubject = restoreSubject
		else
			local _, humanoid, _ = getCharacterParts()
			if humanoid ~= nil then
				camera.CameraSubject = humanoid
			end
		end
		local restoreFov = state.cameraFovBeforeRunway
		if restoreFov ~= nil then
			camera.FieldOfView = restoreFov
		end
	end
	state.cameraTypeBeforeRunway = nil
	state.cameraSubjectBeforeRunway = nil
	state.cameraFovBeforeRunway = nil
end

function RunwayCameraController.Update(
	workspaceRef: Workspace,
	cfg: any,
	dt: number,
	phase: number,
	isRunwayActivePhase: (number) -> boolean,
	getCharacterParts: () -> (Model?, Humanoid?, BasePart?),
	runwayForward: Vector3,
	normalizeForward: (Vector3) -> Vector3
)
	if not state.active then
		return
	end
	if not isRunwayActivePhase(phase) then
		RunwayCameraController.Disable(workspaceRef, getCharacterParts)
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
	local smoothSpeed = math.max(0, cfg.RUNWAY_CAMERA_SMOOTH_SPEED)
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
