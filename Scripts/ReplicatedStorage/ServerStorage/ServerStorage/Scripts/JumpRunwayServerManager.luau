--!strict
-- JumpRunwayServerManager（客户端权威状态机版）
-- ----------------------------------------------------------------------
-- 客户端：开局 / BeginLine 触碰、完整相位机、起跳窗与物理表现。
-- 服务端：会话登记（Start 包）、沿轴样本防作弊累加 maxAlong、终局锁定分数与清理。
-- 不再：StartTrigger 服端触碰开局、几何穿线、JumpWindow/Coyote/Heartbeat 状态推进、HandleJumpIntent。
local JumpRunwayServerManager = {}

local players: Players = game:GetService("Players")
local workspaceInst: Workspace = game:GetService("Workspace")
local httpService: HttpService = game:GetService("HttpService")

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))

type RunState = {
	runwayForward: Vector3,
	runwayOrigin: Vector3,
	alongBaseline: number,
	lastSampleAlong: number?,
	lastSampleClock: number?,
	lastNotifyClock: number,
	notifyDistQ: number,
	diedConn: RBXScriptConnection?,
	antiCheatRejectCount: number,
	debugLastRawAlong: number?,
	debugLastParsedAlong: number?,
	debugSampleAlongNilWarns: number,
}

local cfg = GameConfig.JumpRunway
local SERVER_DEBUG = cfg.DEBUG == true

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
}

local pendingLittleElfChestRewardMap: { [number]: PendingLittleElfChestReward } = {}

local JumpRunwayLittleElfChestCarryAttr = "JumpRunwayLittleElfChestCarry"
local StartTriggerCloseEnoughMinStuds = 24

local brainrotCarryingManagerMod: any = nil
local function GetBrainrotCarryingManager(): any
	if brainrotCarryingManagerMod == nil then
		brainrotCarryingManagerMod = require(serverScripts:WaitForChild("BrainrotCarryingManager"))
	end
	return brainrotCarryingManagerMod
end

local Ph = {
	AutoRun = 1,
	ScoreLocked = 8,
	Cleaning = 9,
	Idle = 0,
}

local Kind = {
	Input = 1,
	Sample = 2,
	Final = 3,
	Start = 4,
}

local runMap: { [number]: RunState } = {}
local maxAlongByUserId: { [number]: number } = {}
local playerFinalScore: { [number]: number } = {}
local initDone: boolean = false
local warnedRemotesOnce: boolean = false
local DebugRunId = "runway_pullback_probe_1"

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
	pcall(function()
		httpService:RequestAsync({
			Url = "http://127.0.0.1:7477/ingest/d880235d-ec65-4b2d-88e2-c8b819ceca93",
			Method = "POST",
			Compress = Enum.HttpCompression.None,
			Headers = {
				["Content-Type"] = "application/json",
				["X-Debug-Session-Id"] = "6f8203",
			},
			Body = httpService:JSONEncode(payload),
		})
	end)
	local okEncode, encoded = pcall(function()
		return httpService:JSONEncode(payload)
	end)
	if okEncode then
		warn("[DBG6f8203] " .. encoded)
	end
end

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
	-- #region agent log
	DebugEmit("H3", "JumpRunwayServerManager:TeleportPlayerToHomeSlot", "server_teleport_home_slot", {
		playerUserId = player.UserId,
		jumpRunwayActive = player:GetAttribute("JumpRunwayActive") == true,
	})
	-- #endregion
	hrp.CFrame = spawnLocation.CFrame * CFrame.new(0, 3, 0)
	return true
end

local function ClearPlayerRunAttribute(player: Player)
	player:SetAttribute("JumpRunwayActive", false)
end

local function DisconnectState(player: Player, st: RunState)
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
	if phase ~= Ph.AutoRun then
		-- #region agent log
		DebugEmit("H1", "JumpRunwayServerManager:NotifyJumpRunway", "non_autorun_phase_notify", {
			playerUserId = player.UserId,
			phase = phase,
			force = force,
			dist = dist,
			hasRunState = st ~= nil,
		})
		-- #endregion
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
	NotifyJumpRunway(player, Ph.Cleaning, maxAlongByUserId[player.UserId] or 0, nil, runwayForward, runwayOrigin, true)
	-- 先退出跑道会话（含清理 JumpRunwayActive），再执行清场传送，避免跑道中状态与传送并发造成回抽体感。
	DisconnectState(player, st)
	if not TeleportPlayerToHomeSlot(player) then
		warn("[JumpRunwayServerManager] Teleport to home slot failed; check PlayersHome / TeleportPoint / SpawnLocation.")
	end
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

local function LockScoreAndTeleport(player: Player, st: RunState, nowClock: number)
	local capped = math.min(maxAlongByUserId[player.UserId] or 0, cfg.ANTI_CHEAT_DISTANCE_HARD_CAP)
	playerFinalScore[player.UserId] = capped
	player:SetAttribute("JumpRunwayCooldownUntil", nowClock + cfg.RUN_START_COOLDOWN)
	NotifyJumpRunway(player, Ph.ScoreLocked, capped, capped, st.runwayForward, st.runwayOrigin, true)
	local stSnapshot = st
	task.defer(function()
		BeginCleaning(player, stSnapshot)
	end)
end

local function IngestSample(player: Player, st: RunState, report: NetMsg.JumpRunwayInputReport, nowClock: number): boolean
	if report.sampleAlong == nil then
		if SERVER_DEBUG then
			st.debugSampleAlongNilWarns += 1
			if st.debugSampleAlongNilWarns <= 3 then
				warn(string.format("[JumpRunwayDBG] %s Sample without along (warn #%d)", player.Name, st.debugSampleAlongNilWarns))
			end
		end
		return false
	end
	local sampleAlong = report.sampleAlong :: number
	local progressAlong = sampleAlong - st.alongBaseline
	if progressAlong > cfg.ANTI_CHEAT_DISTANCE_HARD_CAP then
		st.antiCheatRejectCount += 1
		return false
	end
	if report.samplePerpMag ~= nil and (report.samplePerpMag :: number) > cfg.ANTI_CHEAT_MAX_PERP_DEVIATION then
		st.antiCheatRejectCount += 1
		return false
	end
	if report.sampleAlongSpeed ~= nil and math.abs(report.sampleAlongSpeed :: number) > cfg.ANTI_CHEAT_MAX_ALONG_SPEED then
		st.antiCheatRejectCount += 1
		return false
	end
	local prevAlong = st.lastSampleAlong
	local prevClock = st.lastSampleClock
	if prevAlong ~= nil and prevClock ~= nil then
		local dtSample = math.max(nowClock - prevClock, 1e-3)
		local delta = sampleAlong - prevAlong
		local maxDelta = cfg.ANTI_CHEAT_MAX_ALONG_SPEED * dtSample + cfg.ANTI_CHEAT_MAX_DELTA_PER_SAMPLE
		if delta > maxDelta then
			st.antiCheatRejectCount += 1
			return false
		end
	end
	st.lastSampleAlong = sampleAlong
	st.lastSampleClock = nowClock
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
		lastSampleAlong = nil,
		lastSampleClock = nil,
		lastNotifyClock = 0,
		notifyDistQ = -1,
		diedConn = nil,
		antiCheatRejectCount = 0,
		debugLastRawAlong = nil,
		debugLastParsedAlong = nil,
		debugSampleAlongNilWarns = 0,
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
		end
	end)
	-- 客户端全表现：开局阶段服务端不再写 Humanoid locomotion，避免与客户端推速对抗。
	NotifyJumpRunway(player, Ph.AutoRun, 0, nil, forward, origin, true)
	return true
end

local function ClearLittleElfChestPending(player: Player)
	pendingLittleElfChestRewardMap[player.UserId] = nil
end

local function ResolveStartTrigger(): Part?
	local startPoint = workspaceInst:FindFirstChild("StartPoint")
	local startModel = if startPoint then startPoint:FindFirstChild("StartPointModel") else nil
	return if startModel then startModel:FindFirstChild("StartTrigger") :: Part? else nil
end

local function IsPlayerNearStartTrigger(player: Player): boolean
	local character = player.Character
	if character == nil then
		return false
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local startTrigger = ResolveStartTrigger()
	if hrp == nil or startTrigger == nil then
		return false
	end
	local closeEnough = (hrp.Position - startTrigger.Position).Magnitude
		< math.max(startTrigger.Size.Magnitude * 2, StartTriggerCloseEnoughMinStuds)
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
	carryPart:SetAttribute(JumpRunwayLittleElfChestCarryAttr, true)
	return carryPart
end

local function EndRunwaySessionWithoutTeleport(player: Player)
	local st = runMap[player.UserId]
	if st == nil then
		ClearPlayerRunAttribute(player)
		return
	end
	local runwayForward = st.runwayForward
	local runwayOrigin = st.runwayOrigin
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
		pending.chestConfigId
	)
	if not success then
		warn("[JumpRunwayServerManager] GrantLittleElfChestPending: AddItem failed for", player.Name)
		return false
	end
	pendingLittleElfChestRewardMap[player.UserId] = nil
	return true
end

local function HandleLittleElfChestReward(player: Player, chestConfigId: number)
	-- 不检查 runMap：可能玩家跑道已结束但宝箱撞击滞后，仍应发放奖励
	local character = player.Character
	if character == nil then
		return
	end
	local existingPending = pendingLittleElfChestRewardMap[player.UserId]
	if existingPending ~= nil and existingPending.chestConfigId == chestConfigId then
		NetMsg.FireNotifyJumpRunwayLittleElfChestReward(
			player,
			existingPending.brainrotId,
			existingPending.chestConfigId,
			1
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
	-- 服务端只 Notify 一次：Roll 结果缓存，入背包由客户端开箱动画结束后再请求
	pendingLittleElfChestRewardMap[player.UserId] = {
		brainrotId = brainrotId,
		chestConfigId = chestConfigId,
		quality = brainrotData.quality,
	}
	NetMsg.FireNotifyJumpRunwayLittleElfChestReward(player, brainrotId, chestConfigId, 1)
end

local function HandleLittleElfChestStartCarry(player: Player)
	local pending = pendingLittleElfChestRewardMap[player.UserId]
	if pending == nil then
		return
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
	end
end

local function HandleLittleElfChestGrant(player: Player)
	if pendingLittleElfChestRewardMap[player.UserId] == nil then
		return
	end
	if GetRunwayLittleElfChestCarrying(player) == nil then
		return
	end
	if not IsPlayerNearStartTrigger(player) then
		return
	end
	local success = GrantLittleElfChestPendingToPlayer(player)
	if not success then
		return
	end
	GetBrainrotCarryingManager().StopCarrying(player)
	EndRunwaySessionWithoutTeleport(player)
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
		end)
	end)
end

local function OnJumpRunwayReport(player: Player, rawPayload: NetMsg.JumpRunwayInputReport)
	local report = NormalizeJumpRunwayInputReport(rawPayload :: any)
	if report == nil then
		if SERVER_DEBUG then
			warn(string.format("[JumpRunwayDBG] %s dropped JumpRunwayInput: could not normalize payload", player.Name))
		end
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
	if kind == Kind.Sample and report.clientPhase ~= nil and ((report.clientPhase :: number) == Ph.Idle or (report.clientPhase :: number) == Ph.Cleaning) then
		-- #region agent log
		DebugEmit("H4", "JumpRunwayServerManager:OnJumpRunwayReport", "client_phase_regressed_to_idle_or_cleaning", {
			playerUserId = player.UserId,
			clientPhase = report.clientPhase,
			maxAlong = maxAlongByUserId[player.UserId] or 0,
		})
		-- #endregion
	end
	if SERVER_DEBUG and report.kind == Kind.Sample then
		local inner = UnwrapReportTable(rawPayload :: any)
		if inner ~= nil then
			local ra = CoerceNumber(inner.sampleAlong)
			if ra == nil then
				ra = CoerceNumber(inner.along)
			end
			st.debugLastRawAlong = ra
		else
			st.debugLastRawAlong = nil
		end
		st.debugLastParsedAlong = report.sampleAlong
	end
	if kind == Kind.Sample then
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
		else
			-- #region agent log
			DebugEmit("H5", "JumpRunwayServerManager:OnJumpRunwayReport", "sample_rejected", {
				playerUserId = player.UserId,
				clientPhase = report.clientPhase,
				rejectCount = st.antiCheatRejectCount,
				lastSampleAlong = st.lastSampleAlong,
			})
			-- #endregion
		end
	elseif kind == Kind.Final then
		LockScoreAndTeleport(player, st, nowClock)
	end
	-- kind Input：客户端权威下服端不解析起跳，可忽略
end

function JumpRunwayServerManager.Init()
	if initDone then
		return
	end
	initDone = true
	NetMsg.ConnectRequestJumpRunwayInput(OnJumpRunwayReport)
	NetMsg.ConnectRequestJumpRunwayLittleElfChestReward(function(player: Player, chestConfigId: number)
		HandleLittleElfChestReward(player, chestConfigId)
	end)
	NetMsg.ConnectRequestJumpRunwayLittleElfChestStartCarry(function(player: Player)
		HandleLittleElfChestStartCarry(player)
	end)
	NetMsg.ConnectRequestJumpRunwayLittleElfChestGrant(function(player: Player)
		HandleLittleElfChestGrant(player)
	end)
	for _, player in ipairs(players:GetPlayers()) do
		BindLittleElfChestDeathHandler(player)
	end
	players.PlayerAdded:Connect(BindLittleElfChestDeathHandler)
	players.PlayerRemoving:Connect(function(player)
		ClearLittleElfChestPending(player)
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
