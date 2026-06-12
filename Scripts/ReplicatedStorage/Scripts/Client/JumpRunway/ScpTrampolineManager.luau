--!strict

local ScpTrampolineManager = {}

local players = game:GetService("Players")
local workspace = game:GetService("Workspace")
local replicatedStorage = game:GetService("ReplicatedStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local jumpRunwayScripts = clientScripts:WaitForChild("JumpRunway")
local RunwayConstants = require(jumpRunwayScripts:WaitForChild("RunwayConstants"))

type RuntimeApi = {
	GetCharacterParts: () -> (Model?, Humanoid?, BasePart?),
	TryApplyBounce: (Humanoid, BasePart, number) -> boolean,
}

local localPlayer = players.LocalPlayer

local runtimeApi: RuntimeApi? = nil
local springPartList: { BasePart } = {}
local springConnList: { RBXScriptConnection } = {}
local touchingSpringMap: { [BasePart]: boolean } = {}
local lastBounceClock = -math.huge

local function ResolveSpringParts(): { BasePart }
	local result: { BasePart } = {}
	local groundFolder = workspace:FindFirstChild("Ground")
	if groundFolder == nil then
		return result
	end
	local scpFolder = groundFolder:FindFirstChild("SCP")
	if scpFolder == nil then
		return result
	end
	for _, instance in scpFolder:GetDescendants() do
		if instance:IsA("Model") and instance.Name == RunwayConstants.ScpTrampolineModelName then
			local spring = instance:FindFirstChild(RunwayConstants.ScpTrampolineSpringPartName)
			if spring ~= nil and spring:IsA("BasePart") then
				table.insert(result, spring :: BasePart)
			end
		end
	end
	return result
end

local function IsCharacterTouchingSpring(character: Model, spring: BasePart): boolean
	for _, part in spring:GetTouchingParts() do
		if part:IsDescendantOf(character) then
			return true
		end
	end
	return false
end

local function TryBounceFromSpring(): boolean
	local api = runtimeApi
	if api == nil then
		return false
	end
	local _character, humanoid, hrp = api.GetCharacterParts()
	if humanoid == nil or hrp == nil or humanoid.Health <= 0 then
		return false
	end
	local nowClock = os.clock()
	if nowClock - lastBounceClock < RunwayConstants.ScpTrampolineBounceCooldownSec then
		return false
	end
	if not api.TryApplyBounce(humanoid, hrp, nowClock) then
		return false
	end
	lastBounceClock = nowClock
	return true
end

local function OnSpringTouched(spring: BasePart, hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	if character ~= localPlayer.Character then
		return
	end
	local api = runtimeApi
	if api == nil then
		return
	end
	if touchingSpringMap[spring] == true then
		return
	end
	if TryBounceFromSpring() then
		touchingSpringMap[spring] = true
	end
end

function ScpTrampolineManager.Init(api: RuntimeApi)
	runtimeApi = api
end

function ScpTrampolineManager.Reset()
	table.clear(touchingSpringMap)
	lastBounceClock = -math.huge
end

function ScpTrampolineManager.BindSceneTriggers()
	for _, conn in springConnList do
		conn:Disconnect()
	end
	table.clear(springConnList)
	table.clear(touchingSpringMap)
	springPartList = ResolveSpringParts()
	for _, spring in springPartList do
		table.insert(
			springConnList,
			spring.Touched:Connect(function(hit: BasePart)
				OnSpringTouched(spring, hit)
			end)
		)
	end
end

function ScpTrampolineManager.UpdateOverlap()
	local api = runtimeApi
	if api == nil then
		return
	end
	local character = localPlayer.Character
	if character == nil then
		table.clear(touchingSpringMap)
		return
	end
	for _, spring in springPartList do
		if spring.Parent == nil then
			touchingSpringMap[spring] = nil
			continue
		end
		local isTouching = IsCharacterTouchingSpring(character, spring)
		if not isTouching then
			touchingSpringMap[spring] = nil
		elseif touchingSpringMap[spring] ~= true then
			if TryBounceFromSpring() then
				touchingSpringMap[spring] = true
			end
		end
	end
end

return ScpTrampolineManager
