--!strict

local httpService = game:GetService("HttpService")

local RunwayDebugProbe = {}

local DebugRunId = "runway_pullback_probe_3"

function RunwayDebugProbe.Emit(hypothesisId: string, location: string, message: string, data: { [string]: any }?)
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

return RunwayDebugProbe
