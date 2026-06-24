--!strict
-- JumpRunwayServerManager（客户端权威状态机版）
-- ----------------------------------------------------------------------
-- 客户端：开局 / BeginLine 触碰、完整相位机、起跳窗与物理表现。
-- 服务端：会话登记（Start 包）、沿轴样本累加 maxAlong（距离硬上限）、终局锁定分数与清理。
-- 不再：StartTrigger 服端触碰开局、几何穿线、JumpWindow/Coyote/Heartbeat 状态推进、HandleJumpIntent。
local JumpRunwayServerManager = {}

local players: Players = game:GetService("Players")
local workspaceInst: Workspace = game:GetService("Workspace")
local httpService: HttpService = game:GetService("HttpService")
local physicsService: PhysicsService = game:GetService("PhysicsService")

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local LeaderboardManager = require(serverScripts:FindFirstChild("LeaderboardManager"))
local AnalyticsTool = require(serverScripts:FindFirstChild("AnalyticsTool"))
local JetpackManager = require(serverScripts:FindFirstChild("JetpackManager"))

type RunState = {
	runwayForward: Vector3,
	runwayOrigin: Vector3,
	alongBaseline: number,
	lastNotifyClock: number,
	notifyDistQ: number,
	diedConn: RBXScriptConnection?,
	analyticsEndLogged: boolean,
}

local cfg = GameConfig.JumpRunway
local PlayerSlideCollisionGroupName = "PlayerSlideState"
local ChestCollisionGroupName = "Chest"
local TreeCollisionGroupName = "Tree"

-- 惰性引用 BrainrotQueueManager，避免静态循环依赖
local brainrotQueueManagerMod: any = nil
local function GetBrainrotQueueManager(): any
	if brainrotQueueManagerMod == nil then
		brainrotQueueManagerMod = require(serverScripts:WaitForChild("BrainrotQueueManager"))
	end
	return brainrotQueueManagerMod
end

type PendingLittleElfChestReward = {
	brainrotId: number,
	chestConfigId: number,
	quality: number,
	variantId: number,
}

local pendingLittleElfChestRewardMap: { [number]: PendingLittleElfChestReward } = {}

local JumpRunwayLittleElfChestCarryAttr = "JumpRunwayLittleElfChestCarry"
local JumpRunwayEscapeActiveAttr = "JumpRunwayEscapeActive"
local ExercisingAttr = "Exercising"
local EndTriggerCloseEnoughMinStuds = 24
local PortalItselfCloseEnoughMinStuds = 24

local function EnsureCollisionGroup(groupName: string)
	pcall(function()
		physicsService:RegisterCollisionGroup(groupName)
	end)
end

local function ConfigureJumpRunwayCollisionGroups()
	EnsureCollisionGroup(PlayerSlideCollisionGroupName)
	EnsureCollisionGroup(ChestCollisionGroupName)
	EnsureCollisionGroup(TreeCollisionGroupName)
	pcall(function()
		physicsService:CollisionGroupSetCollidable(PlayerSlideCollisionGroupName, TreeCollisionGroupName, false)
	end)
	pcall(function()
		physicsService:CollisionGroupSetCollidable(ChestCollisionGroupName, TreeCollisionGroupName, false)
	end)
end

local brainrotCarryingManagerMod: any = nil
local function GetBrainrotCarryingManager(): any
	if brainrotCarryingManagerMod == nil then
		brainrotCarryingManagerMod = require(serverScripts:WaitForChild("BrainrotCarryingManager"))
	end
	return brainrotCarryingManagerMod
end

local Ph = {
	AutoRun = 1,
	Airborne = 4,
	ScoreLocked = 8,
	Cleaning = 9,
	Idle = 0,
}

local Kind = {
	Input = 1,
	Sample = 2,
	Final = 3,
	Start = 4,
	Abort = 5,
}

local runMap: { [number]: RunState } = {}
local maxAlongByUserId: { [number]: number } = {}
local playerFinalScore: { [number]: number } = {}
local initDone: boolean = false
local warnedRemotesOnce: boolean = false

local function CoerceNumber(n: any): number?
	if typeof(n) == "number" then
		if n ~= n then
			return nil
		end
		return n
	end
	if typeof(n) == "string" then
		return tonumber(n)
	end
	return nil
end

local function UnwrapReportTable(raw: any): { [any]: any }?
	if typeof(raw) ~= "table" then
		return nil
	end
	local t = raw :: { [any]: any }
	if t.kind == nil and t[1] ~= nil and typeof(t[1]) == "table" then
		t = t[1] :: { [any]: any }
	end
	if t.kind == nil and typeof(t.payload) == "table" then
		t = t.payload :: { [any]: any }
	end
	return t
end

local function CoerceVector3(v: any): Vector3?
	if typeof(v) == "Vector3" then
		return v :: Vector3
	end
	if typeof(v) == "table" then
		local x = CoerceNumber((v :: any).X) or CoerceNumber((v :: any).x)
		local y = CoerceNumber((v :: any).Y) or CoerceNumber((v :: any).y)
		local z = CoerceNumber((v :: any).Z) or CoerceNumber((v :: any).z)
		if x ~= nil and y ~= nil and z ~= nil then
			return Vector3.new(x, y, z)
		end
	end
	return nil
end

local function NormalizeJumpRunwayInputReport(raw: any): NetMsg.JumpRunwayInputReport?
	local t = UnwrapReportTable(raw)
	if t == nil then
		return nil
	end
	local kindAny = t.kind
	if kindAny == nil then
		kindAny = t.type
	end
	local kindN = CoerceNumber(kindAny)
	if kindN == nil and typeof(kindAny) == "string" then
		local ks = string.lower(kindAny :: string)
		if ks == "input" then
			kindN = 1
		elseif ks == "sample" then
			kindN = 2
		elseif ks == "final" then
			kindN = 3
		elseif ks == "start" then
			kindN = 4
		elseif ks == "abort" then
			kindN = 5
		end
	end
	if kindN == nil then
		return nil
	end
	local sampleAlong = CoerceNumber(t.sampleAlong)
	if sampleAlong == nil then
		sampleAlong = CoerceNumber(t.along)
	end
	local out: NetMsg.JumpRunwayInputReport = {
		kind = kindN,
		jumpPressed = if typeof(t.jumpPressed) == "boolean" then t.jumpPressed :: boolean else nil,
		dashHeld = if typeof(t.dashHeld) == "boolean" then t.dashHeld :: boolean else nil,
		finalDashThrustActive = if typeof(t.finalDashThrustActive) == "boolean" then t.finalDashThrustActive :: boolean else nil,
		sampleAlong = sampleAlong,
		sampleAlongSpeed = CoerceNumber(t.sampleAlongSpeed),
		samplePerpMag = CoerceNumber(t.samplePerpMag),
		grounded = if typeof(t.grounded) == "boolean" then t.grounded :: boolean else nil,
		finalAlong = CoerceNumber(t.finalAlong),
		clientClock = CoerceNumber(t.clientClock),
		clientPhase = CoerceNumber(t.clientPhase),
		alongBaseline = CoerceNumber(t.alongBaseline),
		runwayForward = CoerceVector3(t.runwayForward),
		runwayOrigin = CoerceVector3(t.runwayOrigin),
		qteTimes = CoerceNumber(t.qteTimes),
		qtePercent = CoerceNumber(t.qtePercent),
	}
	return out
end

local function NormalizeRunwayForward(rawForward: Vector3): Vector3
	if rawForward.Magnitude < 1e-4 then
		return Vector3.xAxis
	end
	local forwardH = Vector3.new(rawForward.X, 0, rawForward.Z)
	if forwardH.Magnitude < 1e-4 then
		return rawForward.Unit
	end
	return forwardH.Unit
end

local function Quantize(v: number, step: number): number
	if step <= 0 then
		return v
	end
	return math.floor(v / step + 0.5) * step
end

local function TeleportPlayerToHomeSlot(player: Player): boolean
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	local homes = workspaceInst:FindFirstChild("PlayersHome")
	if playerInfo == nil or playerInfo.homeSlot == "" or homes == nil then
		return false
	end
	local homeModel = homes:FindFirstChild(playerInfo.homeSlot)
	if homeModel == nil then
		return false
	end
	local teleportPoint = homeModel:FindFirstChild("TeleportPoint")
	if teleportPoint == nil then
		return false
	end
	local spawnLocation = teleportPoint:FindFirstChild("SpawnLocation") :: SpawnLocation?
	local character = player.Character
	if spawnLocation == nil or character == nil then
		return false
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp == nil then
		return false
	end
	hrp.CFrame = spawnLocation.CFrame * CFrame.new(0, 3, 0)
	return true
end

local function ClearPlayerRunAttribute(player: Player)
	player:SetAttribute("JumpRunwayActive", false)
end

local function DisconnectState(player: Player, st: RunState)
	JetpackManager.SetPlayerJetpackDashParticlesEnabled(player, false)
	if st.diedConn then
		st.diedConn:Disconnect()
		st.diedConn = nil
	end
	runMap[player.UserId] = nil
	ClearPlayerRunAttribute(player)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		humanoid.AutoRotate = true
	end
	ServerGameInfo.ApplyWalkSpeed(player)
end

local function ResetScoreTracking(userId: number)
	maxAlongByUserId[userId] = 0
	playerFinalScore[userId] = nil
end

local function MergeDistanceIntoScoreTracking(player: Player, distanceOpt: number?)
	if distanceOpt == nil or distanceOpt ~= distanceOpt then
		return
	end
	local userId = player.UserId
	local capped = math.min(math.max(0, distanceOpt :: number), cfg.ANTI_CHEAT_DISTANCE_HARD_CAP)
	if capped > (maxAlongByUserId[userId] or 0) then
		maxAlongByUserId[userId] = capped
	end
end

local function StoreReportedFinalDistance(player: Player, distanceOpt: number?): number
	local distance = 0
	if distanceOpt ~= nil and distanceOpt == distanceOpt then
		distance = math.max(0, distanceOpt :: number)
	end
	local capped = math.min(distance, cfg.ANTI_CHEAT_DISTANCE_HARD_CAP)
	playerFinalScore[player.UserId] = capped
	return capped
end

local function GetPlayerPowerLevel(player: Player): number
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return 0
	end
	return playerInfo.jumpPower.lv
end

local function LogJumpStart(player: Player)
	-- player_speed 埋点忽略减速，使用 JumpPower 等级对应 ExStats walkSpeed
	AnalyticsTool.LogJumpStart(
		player,
		GetPlayerPowerLevel(player),
		ServerGameInfo.GetResolvedWalkSpeedValue(player),
		ServerGameInfo.GetJumpRunwayJumpCount(player)
	)
end

local function LogJumpEnd(player: Player, st: RunState, isDead: number)
	if st.analyticsEndLogged then
		return
	end
	st.analyticsEndLogged = true
	local distance = playerFinalScore[player.UserId] or 0
	-- player_speed 埋点忽略减速，使用 JumpPower 等级对应 ExStats walkSpeed
	AnalyticsTool.LogJumpEnd(
		player,
		GetPlayerPowerLevel(player),
		ServerGameInfo.GetResolvedWalkSpeedValue(player),
		distance,
		isDead,
		ServerGameInfo.GetJumpRunwayJumpCount(player)
	)
end

local function LogJumpQte(player: Player, qteTimes: number, qtePercent: number, jumpCount: number)
	AnalyticsTool.LogJumpQte(
		player,
		GetPlayerPowerLevel(player),
		ServerGameInfo.GetResolvedWalkSpeedValue(player),
		jumpCount,
		qteTimes,
		qtePercent
	)
end

local function NotifyJumpRunway(
	player: Player,
	phase: number,
	dist: number,
	finalScore: number?,
	forward: Vector3,
	origin: Vector3,
	force: boolean
)
	if not NetMsg.JumpRunwayRemotesExist() then
		if not warnedRemotesOnce then
			warnedRemotesOnce = true
			warn(
				"[JumpRunwayServerManager] RemoteEvents missing (NotifyJumpRunwayState / RequestJumpRunwayInput). Create them under ReplicatedStorage.RemoteEvents."
			)
		end
		return
	end
	local st = runMap[player.UserId]
	local nowClock = os.clock()
	local distQ = Quantize(dist, 0.25)
	if not force and st ~= nil and (nowClock - st.lastNotifyClock) < cfg.NOTIFY_INTERVAL and distQ == st.notifyDistQ then
		return
	end
	if st ~= nil then
		st.lastNotifyClock = nowClock
		st.notifyDistQ = distQ
	end
	NetMsg.FireNotifyJumpRunwayState(player, {
		phase = phase,
		distance = dist,
		windowRemainSec = nil,
		fuel = 0,
		takeoffCount = 0,
		ratingTier = nil,
		finalScore = finalScore,
		runwayForward = forward,
		runwayOrigin = origin,
	})
end

local function BeginCleaning(player: Player, st: RunState)
	local runwayForward = st.runwayForward
	local runwayOrigin = st.runwayOrigin
	LogJumpEnd(player, st, 0)
	TeleportPlayerToHomeSlot(player)
	NotifyJumpRunway(player, Ph.Cleaning, maxAlongByUserId[player.UserId] or 0, nil, runwayForward, runwayOrigin, true)
	DisconnectState(player, st)
	ResetScoreTracking(player.UserId)
	if NetMsg.JumpRunwayRemotesExist() then
		NetMsg.FireNotifyJumpRunwayState(player, {
			phase = Ph.Idle,
			distance = 0,
			windowRemainSec = nil,
			fuel = 0,
			takeoffCount = 0,
			ratingTier = nil,
			finalScore = nil,
			runwayForward = runwayForward,
			runwayOrigin = runwayOrigin,
		})
	end
end

local function LockScoreAndTeleport(player: Player, st: RunState, nowClock: number, finalAlongOpt: number?)
	local capped = StoreReportedFinalDistance(player, finalAlongOpt)
	if cfg.DEBUG then
		print("[JumpRunwayServerManager] LockScoreAndTeleport for", player.Name, "capped", capped)
	end
	if capped > 0 then
		ServerGameInfo.UpdateJumpRunwayBestDistance(player, capped)
		LeaderboardManager.TryUpdateWeeklyDistance(player, capped)
	end
	player:SetAttribute("JumpRunwayCooldownUntil", nowClock + cfg.RUN_START_COOLDOWN)
	NotifyJumpRunway(player, Ph.ScoreLocked, capped, capped, st.runwayForward, st.runwayOrigin, true)
	local stSnapshot = st
	task.defer(function()
		BeginCleaning(player, stSnapshot)
	end)
end

local function IngestSample(player: Player, st: RunState, report: NetMsg.JumpRunwayInputReport, _nowClock: number): boolean
	if report.sampleAlong == nil then
		return false
	end
	local sampleAlong = report.sampleAlong :: number
	local progressAlong = sampleAlong - st.alongBaseline
	if progressAlong > cfg.ANTI_CHEAT_DISTANCE_HARD_CAP then
		return false
	end
	local userId = player.UserId
	if progressAlong > (maxAlongByUserId[userId] or 0) then
		maxAlongByUserId[userId] = math.min(progressAlong, cfg.ANTI_CHEAT_DISTANCE_HARD_CAP)
	end
	return true
end

local function TryStartSession(player: Player, report: NetMsg.JumpRunwayInputReport, nowClock: number): boolean
	if runMap[player.UserId] ~= nil then
		return false
	end
	if player:GetAttribute(ExercisingAttr) == true then
		return false
	end
	local lastCd = player:GetAttribute("JumpRunwayCooldownUntil") :: number?
	if type(lastCd) == "number" and nowClock < lastCd then
		return false
	end
	local character = player.Character
	if character == nil then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid == nil or hrp == nil or humanoid.Health <= 0 then
		return false
	end
	local fwd = report.runwayForward
	local org = report.runwayOrigin
	local baseline = report.alongBaseline
	if fwd == nil or org == nil or baseline == nil then
		return false
	end
	local forward = NormalizeRunwayForward(fwd :: Vector3)
	local origin = org :: Vector3
	local st: RunState = {
		runwayForward = forward,
		runwayOrigin = origin,
		alongBaseline = baseline :: number,
		lastNotifyClock = 0,
		notifyDistQ = -1,
		diedConn = nil,
		analyticsEndLogged = false,
	}
	runMap[player.UserId] = st
	ResetScoreTracking(player.UserId)
	player:SetAttribute("JumpRunwayActive", true)
	humanoid.AutoRotate = true
	st.diedConn = humanoid.Died:Connect(function()
		local s = runMap[player.UserId]
		if s then
			local fwd = s.runwayForward
			local org = s.runwayOrigin
			task.delay(0.1, function()
				if runMap[player.UserId] ~= s then
					return
				end
				LogJumpEnd(player, s, 1)
				DisconnectState(player, s)
				ResetScoreTracking(player.UserId)
				if NetMsg.JumpRunwayRemotesExist() then
					NetMsg.FireNotifyJumpRunwayState(player, {
						phase = Ph.Idle,
						distance = 0,
						windowRemainSec = nil,
						fuel = 0,
						takeoffCount = 0,
						ratingTier = nil,
						finalScore = nil,
						runwayForward = fwd,
						runwayOrigin = org,
					})
				end
			end)
		end
	end)
	-- 客户端全表现：开局阶段服务端不再写 Humanoid locomotion，避免与客户端推速对抗。
	LogJumpStart(player)
	NotifyJumpRunway(player, Ph.AutoRun, 0, nil, forward, origin, true)
	return true
end

local function ClearLittleElfChestPending(player: Player)
	pendingLittleElfChestRewardMap[player.UserId] = nil
end

local function ClearJumpRunwayEscapeActive(player: Player)
	player:SetAttribute(JumpRunwayEscapeActiveAttr, false)
end

local function IsPlayerNearPortalItself(player: Player, portalItself: BasePart): boolean
	local character = player.Character
	if character == nil then
		return false
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp == nil then
		return false
	end
	return (hrp.Position - portalItself.Position).Magnitude
		< math.max(portalItself.Size.Magnitude * 2, PortalItselfCloseEnoughMinStuds)
end

local function ResolveEndTrigger(): Part?
	local startPoint = workspaceInst:FindFirstChild("StartPoint")
	local startModel = if startPoint then startPoint:FindFirstChild("StartPointModel") else nil
	return if startModel then startModel:FindFirstChild("EndTrigger") :: Part? else nil
end

local function IsPlayerNearEndTrigger(player: Player): boolean
	local character = player.Character
	if character == nil then
		return false
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local endTrigger = ResolveEndTrigger()
	if hrp == nil or endTrigger == nil then
		return false
	end
	local closeEnough = (hrp.Position - endTrigger.Position).Magnitude
		< math.max(endTrigger.Size.Magnitude * 2, EndTriggerCloseEnoughMinStuds)
	return closeEnough
end

local function GetRunwayLittleElfChestCarrying(player: Player): Instance?
	local character = player.Character
	if character == nil then
		return nil
	end
	local carrying = character:FindFirstChild("CarryingBrainrot")
	if carrying == nil then
		return nil
	end
	if carrying:GetAttribute(JumpRunwayLittleElfChestCarryAttr) == true then
		return carrying
	end
	return nil
end

local function CreateLittleElfChestCarryPart(pending: PendingLittleElfChestReward): BasePart
	local carryPart = Instance.new("Part")
	carryPart.Size = Vector3.new(1, 1, 1)
	carryPart.Transparency = 1
	carryPart.CanCollide = false
	carryPart.Anchored = true
	carryPart.Name = "IslandBrainrot"
	carryPart:SetAttribute("ConfigId", pending.brainrotId)
	carryPart:SetAttribute("ItemType", GameConfig.ItemType.Brainrot)
	carryPart:SetAttribute("Quality", pending.quality)
	carryPart:SetAttribute("Level", 1)
	carryPart:SetAttribute("BrainrotUID", httpService:GenerateGUID(false))
	if pending.variantId > 0 then
		carryPart:SetAttribute("VariantId", pending.variantId)
	end
	carryPart:SetAttribute(JumpRunwayLittleElfChestCarryAttr, true)
	return carryPart
end

local function ShouldForceLittleElfChestVariant(player: Player, chestConfig: GameConfig.LittleElfChestConfigData): boolean
	local zoneId = chestConfig.zoneId or 0
	if zoneId <= 0 then
		return false
	end
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return false
	end
	local previousMaxZoneId = playerInfo.jumpRunwayMaxZoneId or 0
	local isNewMaxZone = zoneId > previousMaxZoneId
	if isNewMaxZone then
		playerInfo.jumpRunwayMaxZoneId = zoneId
		playerInfo.playerInfoChanged = true
	end
	local forceVariant = isNewMaxZone and playerInfo.playerConfigInfo.isFirstZone == true
	if cfg.FIRST_ZONE_DEBUG == true then
		print(
			"[JumpRunwayServerManager][FirstZone]",
			"userId",
			player.UserId,
			"name",
			player.Name,
			"chestConfigId",
			chestConfig.id,
			"zoneId",
			zoneId,
			"previousMaxZoneId",
			previousMaxZoneId,
			"currentMaxZoneId",
			playerInfo.jumpRunwayMaxZoneId,
			"isNewMaxZone",
			isNewMaxZone,
			"isFirstZone",
			playerInfo.playerConfigInfo.isFirstZone,
			"forceVariant",
			forceVariant
		)
	end
	return forceVariant
end

local function EndRunwaySessionWithoutTeleport(player: Player)
	local st = runMap[player.UserId]
	if st == nil then
		ClearPlayerRunAttribute(player)
		return
	end
	local runwayForward = st.runwayForward
	local runwayOrigin = st.runwayOrigin
	LogJumpEnd(player, st, 0)
	DisconnectState(player, st)
	ResetScoreTracking(player.UserId)
	if NetMsg.JumpRunwayRemotesExist() then
		NetMsg.FireNotifyJumpRunwayState(player, {
			phase = Ph.Idle,
			distance = 0,
			windowRemainSec = nil,
			fuel = 0,
			takeoffCount = 0,
			ratingTier = nil,
			finalScore = nil,
			runwayForward = runwayForward,
			runwayOrigin = runwayOrigin,
		})
	end
end

local function GrantLittleElfChestPendingToPlayer(player: Player): boolean
	local pending = pendingLittleElfChestRewardMap[player.UserId]
	if pending == nil then
		return false
	end
	local brainrotData = GameConfig.BrainrotIdMap[pending.brainrotId]
	if not brainrotData then
		warn("[JumpRunwayServerManager] GrantLittleElfChestPending: brainrotId", pending.brainrotId, "not found")
		return false
	end
	local success = GetBrainrotQueueManager().AddItem(
		player,
		pending.brainrotId,
		pending.quality,
		1,
		true,
		nil,
		false,
		nil,
		nil,
		nil,
		GameConfig.ModelGetSource.LittleElfChest,
		pending.chestConfigId,
		nil,
		pending.variantId
	)
	if not success then
		warn("[JumpRunwayServerManager] GrantLittleElfChestPending: AddItem failed for", player.Name)
		return false
	end
	pendingLittleElfChestRewardMap[player.UserId] = nil
	return true
end

local function TryCreateFallbackLittleElfChestPending(player: Player, brainrotId: number?, chestConfigId: number?): boolean
	if brainrotId == nil or chestConfigId == nil then
		return false
	end
	local chestConfig = GameConfig.LittleElfChestIdMap[chestConfigId]
	if not GameConfig.IsLittleElfChestAvailableForJumpRunway(chestConfig) then
		return false
	end
	local rewardPool = GameConfig.LittleElfChestRewardPoolMap[chestConfigId]
	if rewardPool == nil then
		return false
	end
	local smallestId: number? = nil
	local inPool = false
	for _, entry in ipairs(rewardPool) do
		if entry.itemId == brainrotId then
			inPool = true
		end
		if smallestId == nil or entry.itemId < (smallestId :: number) then
			smallestId = entry.itemId
		end
	end
	if not inPool or smallestId ~= brainrotId then
		return false
	end
	local brainrotData = GameConfig.BrainrotIdMap[brainrotId]
	if brainrotData == nil then
		return false
	end
	local rewardEntry = GameConfig.FindLittleElfChestRewardEntry(chestConfigId, brainrotId)
	local forceVariant = ShouldForceLittleElfChestVariant(player, chestConfig)
	local variantId = if rewardEntry then GameConfig.RollVariantIdFromEntry(rewardEntry, forceVariant) else 0
	if cfg.FIRST_ZONE_DEBUG == true then
		print(
			"[JumpRunwayServerManager][FirstZoneReward]",
			"source",
			"fallback",
			"userId",
			player.UserId,
			"chestConfigId",
			chestConfigId,
			"brainrotId",
			brainrotId,
			"forceVariant",
			forceVariant,
			"variantId",
			variantId
		)
	end
	pendingLittleElfChestRewardMap[player.UserId] = {
		brainrotId = brainrotId,
		chestConfigId = chestConfigId,
		quality = brainrotData.quality,
		variantId = variantId,
	}
	return true
end

local function HandleLittleElfChestReward(player: Player, chestConfigId: number)
	-- 不检查 runMap：可能玩家跑道已结束但宝箱撞击滞后，仍应发放奖励
	local character = player.Character
	if character == nil then
		return
	end
	local chestConfig = GameConfig.LittleElfChestIdMap[chestConfigId]
	if not GameConfig.IsLittleElfChestAvailableForJumpRunway(chestConfig) then
		warn(
			"[JumpRunwayServerManager] HandleLittleElfChestReward: chestConfigId is not available for JumpRunway",
			chestConfigId
		)
		return
	end
	local existingPending = pendingLittleElfChestRewardMap[player.UserId]
	if existingPending ~= nil and existingPending.chestConfigId == chestConfigId then
		NetMsg.FireNotifyJumpRunwayLittleElfChestReward(
			player,
			existingPending.brainrotId,
			existingPending.chestConfigId,
			1,
			existingPending.variantId
		)
		return
	end
	local rewardPool = GameConfig.LittleElfChestRewardPoolMap[chestConfigId]
	if not rewardPool or #rewardPool == 0 then
		warn("[JumpRunwayServerManager] HandleLittleElfChestReward: no reward pool for chestConfigId", chestConfigId)
		return
	end
	-- 按 weight 做加权随机选取一个条目
	local totalWeight = 0
	for _, entry in ipairs(rewardPool) do
		totalWeight += entry.weight
	end
	if totalWeight <= 0 then
		return
	end
	local roll = math.random(1, totalWeight)
	local cumulative = 0
	local chosenEntry = nil
	for _, entry in ipairs(rewardPool) do
		cumulative += entry.weight
		if roll <= cumulative then
			chosenEntry = entry
			break
		end
	end
	if not chosenEntry then
		return
	end
	local brainrotId = chosenEntry.itemId
	local brainrotData = GameConfig.BrainrotIdMap[brainrotId]
	if not brainrotData then
		warn("[JumpRunwayServerManager] HandleLittleElfChestReward: brainrotId", brainrotId, "not found in BrainrotIdMap")
		return
	end
	local forceVariant = ShouldForceLittleElfChestVariant(player, chestConfig)
	local variantId = GameConfig.RollVariantIdFromEntry(chosenEntry, forceVariant)
	if cfg.FIRST_ZONE_DEBUG == true then
		print(
			"[JumpRunwayServerManager][FirstZoneReward]",
			"source",
			"normal",
			"userId",
			player.UserId,
			"chestConfigId",
			chestConfigId,
			"brainrotId",
			brainrotId,
			"forceVariant",
			forceVariant,
			"variantId",
			variantId
		)
	end
	-- 服务端只 Notify 一次：Roll 结果缓存，入背包由客户端开箱动画结束后再请求
	pendingLittleElfChestRewardMap[player.UserId] = {
		brainrotId = brainrotId,
		chestConfigId = chestConfigId,
		quality = brainrotData.quality,
		variantId = variantId,
	}
	NetMsg.FireNotifyJumpRunwayLittleElfChestReward(player, brainrotId, chestConfigId, 1, variantId)
end

local function HandleLittleElfChestStartCarry(player: Player, brainrotId: number?, chestConfigId: number?)
	local pending = pendingLittleElfChestRewardMap[player.UserId]
	if pending == nil then
		if not TryCreateFallbackLittleElfChestPending(player, brainrotId, chestConfigId) then
			return
		end
		pending = pendingLittleElfChestRewardMap[player.UserId]
		if pending == nil then
			return
		end
	elseif brainrotId ~= nil and chestConfigId ~= nil and pending.chestConfigId == chestConfigId and pending.brainrotId ~= brainrotId then
		if TryCreateFallbackLittleElfChestPending(player, brainrotId, chestConfigId) then
			pending = pendingLittleElfChestRewardMap[player.UserId]
		end
	end
	if GetRunwayLittleElfChestCarrying(player) ~= nil then
		return
	end
	local character = player.Character
	if character == nil then
		return
	end
	local carryPart = CreateLittleElfChestCarryPart(pending)
	carryPart.Parent = workspaceInst
	local carry = GetBrainrotCarryingManager().StartCarrying(player, carryPart)
	if carry == nil then
		if carryPart.Parent then
			carryPart:Destroy()
		end
		warn("[JumpRunwayServerManager] HandleLittleElfChestStartCarry failed for", player.Name)
	else
		AnalyticsTool.LogModelPickUp(player, pending.brainrotId, 1, GameConfig.ItemType.Brainrot)
	end
end

local function HandleLittleElfChestGrant(player: Player, finalDistance: number?)
	if pendingLittleElfChestRewardMap[player.UserId] == nil then
		return
	end
	if player:GetAttribute(JumpRunwayEscapeActiveAttr) ~= true then
		return
	end
	if GetRunwayLittleElfChestCarrying(player) == nil then
		return
	end
	if not IsPlayerNearEndTrigger(player) then
		return
	end
	local success = GrantLittleElfChestPendingToPlayer(player)
	if not success then
		return
	end
	StoreReportedFinalDistance(player, finalDistance)
	MergeDistanceIntoScoreTracking(player, finalDistance)
	GetBrainrotCarryingManager().StopCarrying(player)
	ClearJumpRunwayEscapeActive(player)
	EndRunwaySessionWithoutTeleport(player)
end

local brainrotIslandManagerMod: any = nil
local function GetBrainrotIslandManager(): any
	if brainrotIslandManagerMod == nil then
		brainrotIslandManagerMod = require(serverScripts:WaitForChild("BrainrotIslandManager"))
	end
	return brainrotIslandManagerMod
end

local function HandleEnterEscapePhase(player: Player)
	if GetRunwayLittleElfChestCarrying(player) == nil and GetBrainrotCarryingManager().GetCarryingBrainrot(player) == nil then
		return
	end
	player:SetAttribute(JumpRunwayEscapeActiveAttr, true)
end

function JumpRunwayServerManager.TryCompleteEscapeViaTeleportPortal(player: Player, portalItself: BasePart): boolean
	if player:GetAttribute(JumpRunwayEscapeActiveAttr) ~= true then
		return false
	end
	if not IsPlayerNearPortalItself(player, portalItself) then
		return false
	end

	local littleElfCarrying = GetRunwayLittleElfChestCarrying(player)
	if littleElfCarrying ~= nil then
		if pendingLittleElfChestRewardMap[player.UserId] == nil then
			return false
		end
		if not GrantLittleElfChestPendingToPlayer(player) then
			return false
		end
		GetBrainrotCarryingManager().StopCarrying(player)
	else
		GetBrainrotIslandManager().TryConvertCarryingToQueue(player)
	end

	ClearJumpRunwayEscapeActive(player)
	EndRunwaySessionWithoutTeleport(player)
	TeleportPlayerToHomeSlot(player)
	return true
end

local function BindLittleElfChestDeathHandler(player: Player)
	player.CharacterAdded:Connect(function(_character: Model)
		local humanoid = _character:WaitForChild("Humanoid", 15) :: Humanoid?
		if humanoid == nil then
			return
		end
		humanoid.Died:Connect(function()
			if pendingLittleElfChestRewardMap[player.UserId] ~= nil then
				ClearLittleElfChestPending(player)
			end
			ClearJumpRunwayEscapeActive(player)
		end)
	end)
end

local function OnJumpRunwayReport(player: Player, rawPayload: NetMsg.JumpRunwayInputReport)
	local report = NormalizeJumpRunwayInputReport(rawPayload :: any)
	if report == nil then
		return
	end
	local nowClock = os.clock()
	local kind = report.kind
	if kind == Kind.Start then
		TryStartSession(player, report, nowClock)
		return
	end
	local st = runMap[player.UserId]
	if st == nil then
		return
	end
	if kind == Kind.Sample then
		if report.finalDashThrustActive ~= nil then
			JetpackManager.SetPlayerJetpackDashParticlesEnabled(player, report.finalDashThrustActive == true)
		end
		local ok = IngestSample(player, st, report, nowClock)
		if ok then
			NotifyJumpRunway(
				player,
				Ph.AutoRun,
				maxAlongByUserId[player.UserId] or 0,
				nil,
				st.runwayForward,
				st.runwayOrigin,
				false
			)
		end
	elseif kind == Kind.Final then
		if cfg.DEBUG then
			print("[JumpRunwayServerManager] Final report for", player.Name, "distance", report.finalAlong or maxAlongByUserId[player.UserId])
		end
		JetpackManager.SetPlayerJetpackDashParticlesEnabled(player, false)
		LockScoreAndTeleport(player, st, nowClock, report.finalAlong)
	elseif kind == Kind.Input then
		if report.jumpPressed == true then
			local jumpCount = ServerGameInfo.IncrementJumpRunwayJumpCount(player)
			if report.qteTimes ~= nil and report.qtePercent ~= nil then
				LogJumpQte(player, report.qteTimes, report.qtePercent, jumpCount)
			end
		end
		if report.finalDashThrustActive ~= nil then
			JetpackManager.SetPlayerJetpackDashParticlesEnabled(player, report.finalDashThrustActive == true)
		end
	elseif kind == Kind.Abort then
		JetpackManager.SetPlayerJetpackDashParticlesEnabled(player, false)
		StoreReportedFinalDistance(player, report.finalAlong)
	end
	-- kind Input：客户端权威下服端只记录累计起跳次数，不驱动物理表现
end

function JumpRunwayServerManager.Init()
	if initDone then
		return
	end
	initDone = true
	ConfigureJumpRunwayCollisionGroups()
	NetMsg.ConnectRequestJumpRunwayInput(OnJumpRunwayReport)
	NetMsg.ConnectRequestJumpRunwayLittleElfChestReward(function(player: Player, chestConfigId: number)
		HandleLittleElfChestReward(player, chestConfigId)
	end)
	NetMsg.ConnectRequestJumpRunwayBestDistance(function(player: Player, distance: number)
		local verifiedDistance = math.min(
			math.max(0, maxAlongByUserId[player.UserId] or 0),
			math.max(0, distance),
			cfg.ANTI_CHEAT_DISTANCE_HARD_CAP
		)
		if verifiedDistance <= 0 then
			return
		end
		ServerGameInfo.UpdateJumpRunwayBestDistance(player, verifiedDistance)
		LeaderboardManager.TryUpdateWeeklyDistance(player, verifiedDistance)
	end)
	NetMsg.ConnectRequestJumpRunwayLittleElfChestStartCarry(function(player: Player, brainrotId: number?, chestConfigId: number?)
		HandleLittleElfChestStartCarry(player, brainrotId, chestConfigId)
	end)
	NetMsg.ConnectRequestJumpRunwayLittleElfChestGrant(function(player: Player, finalDistance: number?)
		HandleLittleElfChestGrant(player, finalDistance)
	end)
	NetMsg.ConnectRequestJumpRunwayEnterEscapePhase(function(player: Player)
		HandleEnterEscapePhase(player)
	end)
	for _, player in ipairs(players:GetPlayers()) do
		BindLittleElfChestDeathHandler(player)
	end
	players.PlayerAdded:Connect(BindLittleElfChestDeathHandler)
	players.PlayerRemoving:Connect(function(player)
		ClearLittleElfChestPending(player)
		ClearJumpRunwayEscapeActive(player)
		local st = runMap[player.UserId]
		if st then
			local fwd = st.runwayForward
			local org = st.runwayOrigin
			DisconnectState(player, st)
			ResetScoreTracking(player.UserId)
			if NetMsg.JumpRunwayRemotesExist() then
				NetMsg.FireNotifyJumpRunwayState(player, {
					phase = Ph.Idle,
					distance = 0,
					windowRemainSec = nil,
					fuel = 0,
					takeoffCount = 0,
					ratingTier = nil,
					finalScore = nil,
					runwayForward = fwd,
					runwayOrigin = org,
				})
			end
		end
	end)
end

return JumpRunwayServerManager
