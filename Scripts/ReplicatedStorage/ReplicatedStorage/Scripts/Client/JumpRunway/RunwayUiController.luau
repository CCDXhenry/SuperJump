--!strict

local RunwayUiController = {}

function RunwayUiController.Refresh(refreshHud: () -> (), refreshDebug: () -> (), clientDebug: boolean)
	refreshHud()
	if clientDebug then
		refreshDebug()
	end
end

function RunwayUiController.Destroy(destroyHud: () -> (), destroyDebug: () -> ())
	destroyHud()
	destroyDebug()
end

return RunwayUiController
