--!strict

local RunwayNetBridge = {}

function RunwayNetBridge.FireStartSession(netMsg: any, kind: any, forward: Vector3, origin: Vector3, alongBaseline: number)
	if not netMsg.JumpRunwayRemotesExist() then
		return
	end
	netMsg.FireRequestJumpRunwayInput({
		kind = kind.Start,
		runwayForward = forward,
		runwayOrigin = origin,
		alongBaseline = alongBaseline,
		clientClock = os.clock(),
	})
end

function RunwayNetBridge.SendSampleIfDue(
	netMsg: any,
	cfg: any,
	kind: any,
	localState: any,
	hrp: BasePart,
	humanoid: Humanoid,
	nowClock: number,
	normalizeRunwayForward: (Vector3) -> Vector3,
	computeRunwayHorizontalAlongSpeed: (Vector3, Vector3) -> number,
	isRunwayScriptedGrounded: (Humanoid) -> boolean
)
	if not netMsg.JumpRunwayRemotesExist() then
		return
	end
	if nowClock - localState.lastSampleSendClock < cfg.CLIENT_SAMPLE_INTERVAL then
		return
	end
	local forward = normalizeRunwayForward(localState.runwayForward)
	local origin = localState.runwayOrigin
	if origin == nil then
		return
	end
	local along = (hrp.Position - origin):Dot(forward)
	local v = hrp.AssemblyLinearVelocity
	local alongSpeed = computeRunwayHorizontalAlongSpeed(v, forward)
	local horizPos = Vector3.new(hrp.Position.X - origin.X, 0, hrp.Position.Z - origin.Z)
	local horizFwd = Vector3.new(forward.X, 0, forward.Z)
	local perpMag: number
	if horizFwd.Magnitude < 1e-4 then
		perpMag = horizPos.Magnitude
	else
		local forwardHorizUnit = horizFwd.Unit
		local alongHoriz = horizPos:Dot(forwardHorizUnit)
		perpMag = (horizPos - forwardHorizUnit * alongHoriz).Magnitude
	end
	local grounded = isRunwayScriptedGrounded(humanoid)
	netMsg.FireRequestJumpRunwayInput({
		kind = kind.Sample,
		dashHeld = localState.dashHeld,
		sampleAlong = along,
		sampleAlongSpeed = alongSpeed,
		samplePerpMag = perpMag,
		grounded = grounded,
		clientClock = nowClock,
		clientPhase = localState.phase,
	})
	localState.lastSampleSendClock = nowClock
	localState.lastSampleAlong = along
end

function RunwayNetBridge.MaybeReportFinal(
	netMsg: any,
	cfg: any,
	phases: any,
	kind: any,
	localState: any,
	humanoid: Humanoid,
	hrp: BasePart,
	forward: Vector3,
	dt: number,
	nowClock: number,
	horizontalVelocity: (Vector3) -> Vector3,
	isRunwayScriptedGrounded: (Humanoid) -> boolean
)
	if localState.finalSent then
		return
	end
	if localState.phase ~= phases.RunEnded and localState.phase ~= phases.Slide then
		localState.groundedStableTime = 0
		return
	end
	local grounded = isRunwayScriptedGrounded(humanoid)
	local v = hrp.AssemblyLinearVelocity
	local horiz = horizontalVelocity(v).Magnitude
	if grounded and horiz < cfg.V_EPSILON and math.abs(v.Y) < cfg.VERTICAL_EPSILON then
		localState.groundedStableTime += dt
		if localState.groundedStableTime >= cfg.K_STABLE_FRAMES * (1 / 30) then
			if netMsg.JumpRunwayRemotesExist() then
				local origin = localState.runwayOrigin
				local finalAlong = if origin ~= nil then (hrp.Position - origin):Dot(forward) else 0
				netMsg.FireRequestJumpRunwayInput({
					kind = kind.Final,
					finalAlong = finalAlong,
					clientClock = nowClock,
					clientPhase = localState.phase,
				})
				localState.finalSent = true
			end
		end
	else
		localState.groundedStableTime = 0
	end
end

return RunwayNetBridge
