--!strict
local IdleInputClientManager = {}

local players = game:GetService("Players")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))

local isInitialized = false
local localPlayer = players.LocalPlayer
local lastInputClock: number = os.clock()
local requestedTeleportForThisIdleWindow = false
local lastTeleportRequestClock = -math.huge
local lastWarningShownClock = -math.huge
local WARNING_TIP_INTERVAL_SEC = 60

local function IsInputTypeSupported(userInputType: Enum.UserInputType): boolean
	return userInputType == Enum.UserInputType.Keyboard
		or userInputType == Enum.UserInputType.MouseButton1
		or userInputType == Enum.UserInputType.MouseButton2
		or userInputType == Enum.UserInputType.MouseButton3
		or userInputType == Enum.UserInputType.MouseWheel
		or userInputType == Enum.UserInputType.MouseMovement
		or userInputType == Enum.UserInputType.Touch
		or userInputType == Enum.UserInputType.Gamepad1
		or userInputType == Enum.UserInputType.Gamepad2
		or userInputType == Enum.UserInputType.Gamepad3
		or userInputType == Enum.UserInputType.Gamepad4
		or userInputType == Enum.UserInputType.Gamepad5
		or userInputType == Enum.UserInputType.Gamepad6
		or userInputType == Enum.UserInputType.Gamepad7
		or userInputType == Enum.UserInputType.Gamepad8
end

local function MarkInputActivity()
	lastInputClock = os.clock()
	requestedTeleportForThisIdleWindow = false
	lastWarningShownClock = -math.huge
end

local function OnInputBegan(inputObject: InputObject, _processed: boolean)
	if not IsInputTypeSupported(inputObject.UserInputType) then
		return
	end
	MarkInputActivity()
end

local function OnInputChanged(inputObject: InputObject, _processed: boolean)
	if not IsInputTypeSupported(inputObject.UserInputType) then
		return
	end
	MarkInputActivity()
end

local function IsIdleTeleportAllowed(): boolean
	return localPlayer:GetAttribute("JumpRunwayActive") ~= true
end

local function TryShowIdleWarning(nowClock: number, idleDurationSec: number)
	if idleDurationSec < GameConfig.IdleWarnSec then
		return
	end
	if nowClock - lastWarningShownClock < WARNING_TIP_INTERVAL_SEC then
		return
	end
	lastWarningShownClock = nowClock
	local remainSec = math.max(math.ceil(GameConfig.IdleTeleportSec - idleDurationSec), 0)
	local warningTip = GameTexts.IdleTeleportWarning
	ClientMsg.FireShowGameTip(
		warningTip.source,
		GameConfig.GameTipTweenType.FlyUp,
		warningTip.key,
		{ tostring(remainSec) }
	)
end

local function OnHeartbeat()
	local nowClock = os.clock()
	local idleDurationSec = nowClock - lastInputClock
	if not IsIdleTeleportAllowed() then
		return
	end
	TryShowIdleWarning(nowClock, idleDurationSec)
	if idleDurationSec < GameConfig.IdleTeleportSec then
		return
	end
	if requestedTeleportForThisIdleWindow then
		return
	end
	if nowClock - lastTeleportRequestClock < GameConfig.IdleTeleportCooldownSec then
		return
	end
	requestedTeleportForThisIdleWindow = true
	lastTeleportRequestClock = nowClock
	local teleportingTip = GameTexts.IdleTeleporting
	ClientMsg.FireShowGameTip(
		teleportingTip.source,
		GameConfig.GameTipTweenType.FlyUp,
		teleportingTip.key
	)
	NetMsg.FireRequestIdleServerTeleport()
end

local function OnCharacterAdded(_character: Model)
	MarkInputActivity()
end

function IdleInputClientManager.Init()
	if isInitialized then
		return
	end
	isInitialized = true
	lastInputClock = os.clock()
	userInputService.InputBegan:Connect(OnInputBegan)
	userInputService.InputChanged:Connect(OnInputChanged)
	runService.Heartbeat:Connect(OnHeartbeat)
	localPlayer.CharacterAdded:Connect(OnCharacterAdded)
end

return IdleInputClientManager
