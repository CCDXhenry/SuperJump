--!strict

local RunwayFxController = {}

function RunwayFxController.UpdateHeartbeat(updateJetpackFlameDashFx: (number) -> (), nowClock: number)
	updateJetpackFlameDashFx(nowClock)
end

return RunwayFxController
