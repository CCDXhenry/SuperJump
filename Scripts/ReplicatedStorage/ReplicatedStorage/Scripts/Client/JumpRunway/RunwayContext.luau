--!strict

local RunwayStateStore = require(script.Parent.RunwayStateStore)

export type RunwayContext = {
	state: RunwayStateStore.RunwayStateStoreShape,
	cfg: any,
	clientDebug: boolean,
	localPlayer: Player,
	workspace: Workspace,
	replicatedStorage: ReplicatedStorage,
	finalTakeoffForceFreefallUntilClock: number,
	lastJumpDebugReason: string,
	startTriggerActiveInterceptCount: number,
	startTriggerActiveLastInterceptClock: number?,
	prevGroundedHeartbeat: boolean,
	initDone: boolean,
	startTriggerConn: RBXScriptConnection?,
	beginLineConn: RBXScriptConnection?,
	getCharacterParts: () -> (Model?, Humanoid?, BasePart?),
}

return {}
