--!strict

local RunwayPhysicsController = {}

function RunwayPhysicsController.HorizontalVelocity(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function RunwayPhysicsController.NormalizeRunwayForward(rawForward: Vector3): Vector3
	if rawForward.Magnitude < 1e-4 then
		return Vector3.xAxis
	end
	local forwardH = Vector3.new(rawForward.X, 0, rawForward.Z)
	if forwardH.Magnitude < 1e-4 then
		return rawForward.Unit
	end
	return forwardH.Unit
end

function RunwayPhysicsController.ComputeRunwayHorizontalAlongSpeed(v: Vector3, forward: Vector3): number
	local fwdH = Vector3.new(forward.X, 0, forward.Z)
	if fwdH.Magnitude < 1e-4 then
		return v:Dot(forward)
	end
	return RunwayPhysicsController.HorizontalVelocity(v):Dot(fwdH.Unit)
end

function RunwayPhysicsController.CurrentAlongProgress(
	hrp: BasePart,
	runwayOrigin: Vector3?,
	runwayForward: Vector3,
	alongBaseline: number?
): number
	local origin = runwayOrigin
	local forward = RunwayPhysicsController.NormalizeRunwayForward(runwayForward)
	if origin == nil then
		return 0
	end
	local baseline = alongBaseline or 0
	return (hrp.Position - origin):Dot(forward) - baseline
end

return RunwayPhysicsController
