--!strict
local LobbyTeleportClientManager = {}

local players = game:GetService("Players")
local runService = game:GetService("RunService")
local workspaceInst = game:GetService("Workspace")

local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local sharedScripts = scripts:WaitForChild("Shared")
local ClientGameInfo = require(clientScripts:WaitForChild("ClientGameInfo"))
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))

local localPlayer = players.LocalPlayer

local CAMERA_SNAP_FRAME_COUNT = 3
local CAMERA_HEIGHT_OFFSET = 2
local CAMERA_LOOK_HEIGHT = 1

local initDone = false

local function NormalizeFlatFacing(facing: Vector3): Vector3?
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	if flatFacing.Magnitude < 1e-4 then
		return nil
	end
	return flatFacing.Unit
end

local function ResolveCameraDistance(hrp: BasePart, camera: Camera): number
	local distance = (camera.CFrame.Position - hrp.Position).Magnitude
	if distance < 2 or distance > localPlayer.CameraMaxZoomDistance then
		return (localPlayer.CameraMinZoomDistance + localPlayer.CameraMaxZoomDistance) * 0.5
	end
	return distance
end

local function BuildCameraCFrame(hrp: BasePart, flatFacing: Vector3, distance: number): CFrame
	local rootPos = hrp.Position
	local cameraPos = rootPos - flatFacing * distance + Vector3.new(0, CAMERA_HEIGHT_OFFSET, 0)
	local lookAt = rootPos + Vector3.new(0, CAMERA_LOOK_HEIGHT, 0)
	return CFrame.lookAt(cameraPos, lookAt, Vector3.yAxis)
end

local function ApplyCharacterFacing(hrp: BasePart, flatFacing: Vector3)
	local rootPos = hrp.Position
	hrp.CFrame = CFrame.lookAt(rootPos, rootPos + flatFacing, Vector3.yAxis)
end

local function SnapCameraToFacing(facing: Vector3)
	if ClientGameInfo.IsInJumpRunway() or ClientGameInfo.IsInJumpRunwayEscapePhase() then
		return
	end

	local flatFacing = NormalizeFlatFacing(facing)
	if flatFacing == nil then
		return
	end

	local camera = workspaceInst.CurrentCamera
	if camera == nil or camera.CameraType == Enum.CameraType.Scriptable then
		return
	end

	local character = localPlayer.Character
	if character == nil then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if hrp == nil or humanoid == nil then
		return
	end

	ApplyCharacterFacing(hrp, flatFacing)

	local distance = ResolveCameraDistance(hrp, camera)
	local savedCameraType = camera.CameraType
	local savedCameraSubject = camera.CameraSubject
	camera.CameraType = Enum.CameraType.Scriptable

	local framesLeft = CAMERA_SNAP_FRAME_COUNT
	local connection: RBXScriptConnection?
	connection = runService.RenderStepped:Connect(function()
		if hrp.Parent == nil or camera.Parent == nil then
			if connection then
				connection:Disconnect()
			end
			return
		end

		camera.CFrame = BuildCameraCFrame(hrp, flatFacing, distance)
		framesLeft -= 1
		if framesLeft > 0 then
			return
		end

		if connection then
			connection:Disconnect()
		end
		if humanoid.Parent == nil then
			return
		end
		local restoreSubject = if savedCameraSubject ~= nil and savedCameraSubject.Parent ~= nil
			then savedCameraSubject
			else humanoid
		camera.CameraSubject = restoreSubject
		if savedCameraType == Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Custom
		else
			camera.CameraType = savedCameraType
		end
	end)
end

function LobbyTeleportClientManager.Init()
	if initDone then
		return
	end
	initDone = true

	NetMsg.ConnectNotifyLobbyTeleportFacing(function()
		SnapCameraToFacing(GameConfig.LobbyTeleportFacingDirection)
	end)
end

return LobbyTeleportClientManager
