--!strict

local RunwayUiController = {}

function RunwayUiController.Refresh(refreshHud: () -> ())
	refreshHud()
end

function RunwayUiController.Destroy(destroyHud: () -> ())
	destroyHud()
end

return RunwayUiController
