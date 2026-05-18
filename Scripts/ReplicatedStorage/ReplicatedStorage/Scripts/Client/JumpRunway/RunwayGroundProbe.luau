--!strict

local RunwayConstants = require(script.Parent.RunwayConstants)

local RunwayGroundProbe = {}

local ctx: any = nil

function RunwayGroundProbe.Bind(context: any)
	ctx = context
end

local function C(): any
	assert(ctx ~= nil, "RunwayGroundProbe not bound")
	return ctx
end

local function RaycastFeet(humanoid: Humanoid): (boolean, number)
	local root = humanoid.RootPart
	if root == nil then
		return false, 1e9
	end
	local origin = root.Position + Vector3.new(0, C().cfg.RUNWAY_GROUND_RAY_ORIGIN_Y, 0)
	local cast = Vector3.new(0, -C().cfg.RUNWAY_GROUND_PROBE_DOWN, 0)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local char = humanoid.Parent
	if char ~= nil and char:IsA("Model") then
		rp.FilterDescendantsInstances = { char }
	end
	local hit = C().workspace:Raycast(origin, cast, rp)
	if hit == nil then
		return false, 1e9
	end
	if hit.Normal.Y < C().cfg.RUNWAY_GROUND_MIN_NORMAL_Y then
		return false, 1e9
	end
	return true, hit.Distance
end

local function IsRunwayPreLanding(humanoid: Humanoid): boolean
	local root = humanoid.RootPart
	if root == nil then
		return false
	end
	local ok, dist = RaycastFeet(humanoid)
	if not ok then
		return false
	end
	local maxPreLandDist = C().cfg.RUNWAY_PRELAND_MAX_DIST_STUDS
	local baseline = C().state.preLandRayBaselineStuds
	if typeof(baseline) == "number" and baseline == baseline then
		maxPreLandDist = baseline + C().cfg.RUNWAY_PRELAND_MAX_DIST_STUDS
	end
	if dist > maxPreLandDist then
		return false
	end
	if root.AssemblyLinearVelocity.Y > C().cfg.RUNWAY_PRELAND_MAX_VY then
		return false
	end
	return true
end

-- 起跳窗/链式武装：仅 dist 与 baseline+RUNWAY_PRELAND_MAX_DIST_STUDS，不含 vy（与 IsRunwayPreLanding 区分）
local function IsRunwayJumpWindowRayBandOk(humanoid: Humanoid): boolean
	local ok, dist = RaycastFeet(humanoid)
	if not ok then
		return false
	end
	local maxBand = C().cfg.RUNWAY_PRELAND_MAX_DIST_STUDS
	local baseline = C().state.preLandRayBaselineStuds
	if typeof(baseline) == "number" and baseline == baseline then
		maxBand = baseline + C().cfg.RUNWAY_PRELAND_MAX_DIST_STUDS
	end
	return dist <= maxBand
end

-- IsRunwayScriptedGrounded 射线分支：有 baseline 时 dist < baseline + slack；无 baseline 时 ok 即真
local function IsRunwayFeetRayWithinGroundedAboveBaseline(humanoid: Humanoid): boolean
	local ok, dist = RaycastFeet(humanoid)
	if not ok then
		return false
	end
	local b = C().state.preLandRayBaselineStuds
	local slack = C().cfg.RUNWAY_SCRIPTED_GROUNDED_MAX_DIST_ABOVE_BASELINE_STUDS
	if typeof(b) == "number" and b == b and typeof(slack) == "number" and slack == slack and slack >= 0 then
		return dist < b + slack
	end
	return true
end

local function RaycastRunwayGroundFromHrpLocalOffset(hrp: BasePart, humanoid: Humanoid, localOffset: Vector3): (boolean, number)
	local worldPos = hrp.CFrame:PointToWorldSpace(localOffset)
	local origin = worldPos + Vector3.new(0, C().cfg.RUNWAY_GROUND_RAY_ORIGIN_Y, 0)
	local cast = Vector3.new(0, -C().cfg.RUNWAY_GROUND_PROBE_DOWN, 0)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local char = humanoid.Parent
	if char ~= nil and char:IsA("Model") then
		rp.FilterDescendantsInstances = { char }
	end
	local hit = C().workspace:Raycast(origin, cast, rp)
	if hit == nil then
		return false, 1e9
	end
	if hit.Normal.Y < C().cfg.RUNWAY_GROUND_MIN_NORMAL_Y then
		return false, 1e9
	end
	return true, hit.Distance
end

local function IsRunwayFinalLandFullBodyGrounded(humanoid: Humanoid, hrp: BasePart): boolean
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
	local maxDist = C().cfg.RUNWAY_FINAL_LAND_FULL_BODY_GROUND_MAX_DIST_STUDS
	for _, lo in localOffsets do
		local ok, dist = RaycastRunwayGroundFromHrpLocalOffset(hrp, humanoid, lo)
		if not ok or dist > maxDist then
			return false
		end
	end
	return true
end

-- 终局 A→B：仅用射线几何，不用 IsRunwayScriptedGrounded（终局 Slide 强转 Physics 时后者易全程为 true）
local function IsRunwayFinalLandPhaseAFeetRayTouchdown(humanoid: Humanoid): boolean
	local ok, dist = RaycastFeet(humanoid)
	if not ok then
		return false
	end
	local slackRaw = C().cfg.RUNWAY_FINAL_LAND_PHASE_A_TOUCHDOWN_FEET_MAX_ABOVE_BASELINE_STUDS
	local slack = (typeof(slackRaw) == "number" and slackRaw == slackRaw and slackRaw > 0) and slackRaw or 2
	local b = C().state.preLandRayBaselineStuds
	if typeof(b) == "number" and b == b then
		return dist <= b + slack
	end
	local fbRaw = C().cfg.RUNWAY_FINAL_LAND_PHASE_A_TOUCHDOWN_FEET_FALLBACK_MAX_DIST_STUDS
	local fbMax = (typeof(fbRaw) == "number" and fbRaw == fbRaw and fbRaw > 0.25) and fbRaw or 4
	return dist <= fbMax
end

local function IsRunwayFinalLandPhaseAGeometricTouchdown(humanoid: Humanoid, hrp: BasePart): boolean
	return IsRunwayFinalLandFullBodyGrounded(humanoid, hrp) or IsRunwayFinalLandPhaseAFeetRayTouchdown(humanoid)
end

local function IsRunwayScriptedGrounded(humanoid: Humanoid): boolean
	if
		C().state.phase == RunwayConstants.Ph.Airborne
		and C().state.takeoffCount >= C().cfg.N_TOTAL_JUMPS
		and os.clock() < C().finalTakeoffForceFreefallUntilClock
	then
		return false
	end
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		return true
	end
	local st = humanoid:GetState()
	if st == Enum.HumanoidStateType.Flying then
		local allowRaycastFlying = RunwayConstants.IsRunwayActivePhase(C().state.phase)
			and C().state.phase == RunwayConstants.Ph.Airborne
			and C().state.takeoffCount >= C().cfg.N_TOTAL_JUMPS
		if not allowRaycastFlying then
			return false
		end
	elseif st == Enum.HumanoidStateType.Seated then
		return false
	end
	if IsRunwayFeetRayWithinGroundedAboveBaseline(humanoid) then
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
	local y0 = C().state.scriptedGroundHrpYBaseline
	local dev = C().cfg.RUNWAY_SCRIPTED_GROUNDED_HRP_Y_DEVIATION_STUDS
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
RunwayGroundProbe.RaycastFeet = RaycastFeet
RunwayGroundProbe.IsRunwayPreLanding = IsRunwayPreLanding
RunwayGroundProbe.IsRunwayJumpWindowRayBandOk = IsRunwayJumpWindowRayBandOk
RunwayGroundProbe.IsRunwayFeetRayWithinGroundedAboveBaseline = IsRunwayFeetRayWithinGroundedAboveBaseline
RunwayGroundProbe.RaycastRunwayGroundFromHrpLocalOffset = RaycastRunwayGroundFromHrpLocalOffset
RunwayGroundProbe.IsRunwayFinalLandFullBodyGrounded = IsRunwayFinalLandFullBodyGrounded
RunwayGroundProbe.IsRunwayFinalLandPhaseAFeetRayTouchdown = IsRunwayFinalLandPhaseAFeetRayTouchdown
RunwayGroundProbe.IsRunwayFinalLandPhaseAGeometricTouchdown = IsRunwayFinalLandPhaseAGeometricTouchdown
RunwayGroundProbe.IsRunwayScriptedGrounded = IsRunwayScriptedGrounded

return RunwayGroundProbe
