--!strict

local RunwayStateStore = require(script.Parent.RunwayStateStore)

export type RunwayContext = {
	state: RunwayStateStore.RunwayStateStoreShape,
	cfg: any,
	localPlayer: Player,
	workspace: Workspace,
	replicatedStorage: ReplicatedStorage,
	finalTakeoffForceFreefallUntilClock: number,
	prevGroundedHeartbeat: boolean,
	initDone: boolean,
	startTriggerConn: RBXScriptConnection?,
	beginLineConn: RBXScriptConnection?,
	getCharacterParts: () -> (Model?, Humanoid?, BasePart?),
}

return {}
