--!strict

local RunwayNetBridge = {}
local httpService = game:GetService("HttpService")
local DebugRunId = "runway_pullback_probe_3"

local function DebugEmit(hypothesisId: string, location: string, message: string, data: { [string]: any }?)
	local payload = {
		sessionId = "6f8203",
		runId = DebugRunId,
		hypothesisId = hypothesisId,
		location = location,
		message = message,
		data = data or {},
		timestamp = DateTime.now().UnixTimestampMillis,
	}
	local ok, encoded = pcall(function()
		return httpService:JSONEncode(payload)
	end)
	if ok then
		warn("[DBG6f8203] " .. encoded)
	end
end

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
	local humState = humanoid:GetState()
	local prevHumState = localState._dbgPrevHumState
	if prevHumState == nil or prevHumState ~= humState then
		local prevHumStateClock = localState._dbgPrevHumStateClock
		local dtStateFlip = if type(prevHumStateClock) == "number" then (nowClock - (prevHumStateClock :: number)) else -1
		local stateFlipBurst = localState._dbgStateFlipBurst
		if type(stateFlipBurst) ~= "number" then
			stateFlipBurst = 0
		end
		if dtStateFlip >= 0 and dtStateFlip <= 0.2 then
			stateFlipBurst = stateFlipBurst + 1
		else
			stateFlipBurst = 1
		end
		localState._dbgPrevHumStateClock = nowClock
		localState._dbgStateFlipBurst = stateFlipBurst
		localState._dbgPrevHumState = humState
		-- #region agent log
		DebugEmit("C7", "RunwayNetBridge:SendSampleIfDue", "humanoid_state_changed", {
			clientPhase = localState.phase,
			newHumanoidState = tostring(humState),
			grounded = grounded,
			takeoffCount = localState.takeoffCount,
			dtStateFlip = dtStateFlip,
			stateFlipBurst = stateFlipBurst,
			along = along,
			alongSpeed = alongSpeed,
		})
		-- #endregion
		if (localState.phase == 1 or localState.phase == 4) and stateFlipBurst >= 4 then
			-- #region agent log
			DebugEmit("C9", "RunwayNetBridge:SendSampleIfDue", "rapid_humanoid_state_flip_burst", {
				clientPhase = localState.phase,
				grounded = grounded,
				takeoffCount = localState.takeoffCount,
				stateFlipBurst = stateFlipBurst,
				dtStateFlip = dtStateFlip,
				along = along,
				alongSpeed = alongSpeed,
			})
			-- #endregion
		end
	end
	if localState.phase == 1 and humState == Enum.HumanoidStateType.Running and alongSpeed < 5 then
		-- #region agent log
		DebugEmit("C8", "RunwayNetBridge:SendSampleIfDue", "autorun_low_alongspeed_running_state", {
			clientPhase = localState.phase,
			along = along,
			alongSpeed = alongSpeed,
			grounded = grounded,
		})
		-- #endregion
	end
	local lastTickLogClock = localState._dbgLastSampleTickLogClock
	if type(lastTickLogClock) ~= "number" or (nowClock - (lastTickLogClock :: number)) >= 1.5 then
		localState._dbgLastSampleTickLogClock = nowClock
		-- #region agent log
		DebugEmit("C0", "RunwayNetBridge:SendSampleIfDue", "sample_tick", {
			clientPhase = localState.phase,
			along = along,
			alongSpeed = alongSpeed,
			grounded = grounded,
			takeoffCount = localState.takeoffCount,
		})
		-- #endregion
	end
	local prevAlong = localState.lastSampleAlong
	if type(prevAlong) == "number" then
		local deltaAlong = along - (prevAlong :: number)
		if deltaAlong < -0.8 then
			-- #region agent log
			DebugEmit("C5", "RunwayNetBridge:SendSampleIfDue", "sample_along_reversed", {
				clientPhase = localState.phase,
				prevAlong = prevAlong,
				along = along,
				deltaAlong = deltaAlong,
				alongSpeed = alongSpeed,
				grounded = grounded,
			})
			-- #endregion
		end
	end
	if alongSpeed < -2 then
		-- #region agent log
		DebugEmit("C6", "RunwayNetBridge:SendSampleIfDue", "sample_along_speed_negative", {
			clientPhase = localState.phase,
			along = along,
			alongSpeed = alongSpeed,
			grounded = grounded,
		})
		-- #endregion
	end
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
				-- #region agent log
				DebugEmit("C2", "RunwayNetBridge:MaybeReportFinal", "client_send_final", {
					clientPhase = localState.phase,
					groundedStableTime = localState.groundedStableTime,
					horiz = horiz,
					vy = v.Y,
					finalAlong = finalAlong,
					takeoffCount = localState.takeoffCount,
				})
				-- #endregion
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
