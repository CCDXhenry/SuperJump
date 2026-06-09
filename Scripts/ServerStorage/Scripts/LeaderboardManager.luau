--!strict
local LeaderboardManager = {}

local dataStoreService = game:GetService("DataStoreService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

local serverStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")

local LOG_PREFIX = "[LeaderboardManager]"
local SlowOperationWarnThresholdSeconds: number = 1

local httpService = game:GetService("HttpService")

local topLists: { [string]: { { userId: number, value: number, name: string } } } = {}
local usernameCache: { [number]: string } = {}
local lastLeaderboardHashes: { [string]: string } = {}

local UpdateToOrderedDataStore: (Player, string, number) -> boolean

local function GetServerGameInfo(): any
	return require(serverScripts:FindFirstChild("ServerGameInfo"))
end

local function WarnIfSlow(operationName: string, startClock: number)
	local elapsed = os.clock() - startClock
	if elapsed >= SlowOperationWarnThresholdSeconds then
		warn(string.format("%s SlowOperation name=%s elapsed=%.2fs", LOG_PREFIX, operationName, elapsed))
	end
end

local function GetWeekDurationSeconds(): number
	return GameConfig.LeaderboardWeekDurationSeconds
end

local function GetWeekStartUnixUtc(): number
	return GameConfig.LeaderboardWeekStartUnixUtc
end

function LeaderboardManager.GetCurrentWeekIndex(nowTimestamp: number?): number
	local now = nowTimestamp or math.floor(workspace:GetServerTimeNow())
	local delta = now - GetWeekStartUnixUtc()
	if delta < 0 then
		return 0
	end
	return math.floor(delta / GetWeekDurationSeconds())
end

local function GetWeeklyKey(category: string): string
	local weekIndex = LeaderboardManager.GetCurrentWeekIndex()
	return string.format("%s_%s_W%d", GameConfig.LeaderboardDataVersion, category, weekIndex)
end

local function GetOrderedDataStore(category: string): OrderedDataStore
	return dataStoreService:GetOrderedDataStore(GetWeeklyKey(category))
end

local function GetNextWeekResetTimestamp(): number
	local weekIndex = LeaderboardManager.GetCurrentWeekIndex()
	return GetWeekStartUnixUtc() + ((weekIndex + 1) * GetWeekDurationSeconds())
end

local function GetAlignedNextRefreshTimestamp(nowTimestamp: number): number
	local refreshInterval = GameConfig.LeaderboardUpdateInterval
	local elapsedSinceWeekStart = math.max(0, nowTimestamp - GetWeekStartUnixUtc())
	local passedIntervals = math.floor(elapsedSinceWeekStart / refreshInterval)
	return GetWeekStartUnixUtc() + ((passedIntervals + 1) * refreshInterval)
end

local function GetNextWeekResetTimestampCached(): number
	local now = math.floor(workspace:GetServerTimeNow())
	return math.max(GetNextWeekResetTimestamp(), now + 1)
end

local function EnsureWeeklyDistanceStats(playerInfo: GameConfig.PlayerInfo)
	local currentWeekIndex = LeaderboardManager.GetCurrentWeekIndex()
	if playerInfo.jumpRunwayWeeklyBestDistance == nil then
		playerInfo.jumpRunwayWeeklyBestDistance = 0
		playerInfo.playerInfoChanged = true
	end
	if playerInfo.jumpRunwayWeeklyBestDistanceWeekIndex == nil then
		playerInfo.jumpRunwayWeeklyBestDistanceWeekIndex = currentWeekIndex
		playerInfo.playerInfoChanged = true
	end
end

local function MarkLeaderboardChanged(playerInfo: GameConfig.PlayerInfo, category: string)
	playerInfo.leaderboardChanges = playerInfo.leaderboardChanges or {}
	playerInfo.leaderboardChanges[category] = true
end

local function GetLeaderboardValue(playerInfo: GameConfig.PlayerInfo, category: string): number?
	if category == GameConfig.LeaderboardCategory.WeeklyDistance then
		return playerInfo.jumpRunwayWeeklyBestDistance
	end
	return nil
end

local function RestoreCurrentWeeklyBestToOrderedDataStore(player: Player)
	local ServerGameInfo = GetServerGameInfo()
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end
	EnsureWeeklyDistanceStats(playerInfo)
	if playerInfo.jumpRunwayWeeklyBestDistanceWeekIndex ~= LeaderboardManager.GetCurrentWeekIndex() then
		return
	end
	if playerInfo.jumpRunwayWeeklyBestDistance <= 0 then
		return
	end

	local category = GameConfig.LeaderboardCategory.WeeklyDistance
	MarkLeaderboardChanged(playerInfo, category)
	local restoreValue = playerInfo.jumpRunwayWeeklyBestDistance
	task.spawn(function()
		if not UpdateToOrderedDataStore(player, category, restoreValue) then
			return
		end

		local latestPlayerInfo = ServerGameInfo.GetPlayerInfo(player)
		if latestPlayerInfo == nil or latestPlayerInfo.leaderboardChanges == nil then
			return
		end
		if latestPlayerInfo.jumpRunwayWeeklyBestDistance == restoreValue then
			latestPlayerInfo.leaderboardChanges[category] = nil
			if next(latestPlayerInfo.leaderboardChanges) == nil then
				latestPlayerInfo.leaderboardChanges = nil
			end
		end
	end)
end

function LeaderboardManager.CheckWeeklyReset(player: Player)
	local ServerGameInfo = GetServerGameInfo()
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end
	EnsureWeeklyDistanceStats(playerInfo)
	local currentWeekIndex = LeaderboardManager.GetCurrentWeekIndex()
	if playerInfo.jumpRunwayWeeklyBestDistanceWeekIndex ~= currentWeekIndex then
		print(
			string.format(
				"%s Resetting weekly distance for player %d (LastWeekIndex: %d, CurrentWeekIndex: %d)",
				LOG_PREFIX,
				player.UserId,
				playerInfo.jumpRunwayWeeklyBestDistanceWeekIndex,
				currentWeekIndex
			)
		)
		playerInfo.jumpRunwayWeeklyBestDistance = 0
		playerInfo.jumpRunwayWeeklyBestDistanceWeekIndex = currentWeekIndex
		playerInfo.playerInfoChanged = true
	end
end

function LeaderboardManager.TryUpdateWeeklyDistance(player: Player, distance: number)
	LeaderboardManager.CheckWeeklyReset(player)

	local ServerGameInfo = GetServerGameInfo()
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end
	EnsureWeeklyDistanceStats(playerInfo)

	if distance <= playerInfo.jumpRunwayWeeklyBestDistance then
		return
	end

	playerInfo.jumpRunwayWeeklyBestDistance = distance
	MarkLeaderboardChanged(playerInfo, GameConfig.LeaderboardCategory.WeeklyDistance)
	playerInfo.playerInfoChanged = true
end

function LeaderboardManager.SavePlayerStats(player: Player)
	local ServerGameInfo = GetServerGameInfo()
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil or playerInfo.leaderboardChanges == nil then
		return
	end

	for category, hasChanged in pairs(playerInfo.leaderboardChanges) do
		if not hasChanged then
			continue
		end
		local value = GetLeaderboardValue(playerInfo, category)
		if value == nil then
			playerInfo.leaderboardChanges[category] = nil
			continue
		end
		if UpdateToOrderedDataStore(player, category, value) then
			playerInfo.leaderboardChanges[category] = nil
		end
	end

	if next(playerInfo.leaderboardChanges) == nil then
		playerInfo.leaderboardChanges = nil
	end
end

function UpdateToOrderedDataStore(player: Player, category: string, value: number): boolean
	local ods = GetOrderedDataStore(category)
	local updateStartClock = os.clock()
	local success, err = pcall(function()
		ods:SetAsync(tostring(player.UserId), math.floor(value))
	end)
	if not success then
		warn(
			string.format(
				"%s Failed to update OrderedDataStore for %d in %s: %s",
				LOG_PREFIX,
				player.UserId,
				category,
				err
			)
		)
	end
	WarnIfSlow("UpdateToOrderedDataStore", updateStartClock)
	return success
end

LeaderboardManager.UpdateToOrderedDataStore = UpdateToOrderedDataStore

function LeaderboardManager.RefreshLeaderboard(category: string)
	local ods = GetOrderedDataStore(category)
	task.spawn(function()
		local refreshStartClock = os.clock()
		local success, pages = pcall(function()
			return ods:GetSortedAsync(false, GameConfig.LeaderboardDisplayCount)
		end)

		if success then
			local entries = pages:GetCurrentPage()
			local newList = {}
			for _, entry in ipairs(entries) do
				local userId = tonumber(entry.key)
				if userId then
					local name = usernameCache[userId]
					if not name then
						local successName, resultName = pcall(function()
							return players:GetNameFromUserIdAsync(userId)
						end)
						if successName then
							name = resultName
							usernameCache[userId] = name
						else
							name = "Unknown"
						end
					end
					table.insert(newList, {
						userId = userId,
						value = entry.value,
						name = name,
					})
				end
			end

			local jsonString = httpService:JSONEncode(newList)
			if lastLeaderboardHashes[category] == jsonString then
				WarnIfSlow("RefreshLeaderboard", refreshStartClock)
				return
			end
			lastLeaderboardHashes[category] = jsonString

			topLists[category] = newList
			NetMsg.FireNotifyLeaderboardUpdate(nil, category, newList, GetNextWeekResetTimestampCached())
		else
			warn(string.format("%s Failed to refresh leaderboard for %s: %s", LOG_PREFIX, category, tostring(pages)))
		end
		WarnIfSlow("RefreshLeaderboard", refreshStartClock)
	end)
end

function LeaderboardManager.Init()
	task.spawn(function()
		local nowInit = math.floor(workspace:GetServerTimeNow())
		NetMsg.FireNotifyLeaderboardResetTime(nil, GetNextWeekResetTimestampCached())

		LeaderboardManager.RefreshLeaderboard(GameConfig.LeaderboardCategory.WeeklyDistance)

		while true do
			local now = math.floor(workspace:GetServerTimeNow())
			local nextPullTimestamp = GetAlignedNextRefreshTimestamp(now)
			local waitSeconds = math.max(1, nextPullTimestamp - now)
			task.wait(waitSeconds)

			print(
				string.format(
					"%s Starting periodic refresh. NextPullAt: %s",
					LOG_PREFIX,
					os.date("!%X", nextPullTimestamp)
				)
			)
			NetMsg.FireNotifyLeaderboardResetTime(nil, GetNextWeekResetTimestampCached())
			LeaderboardManager.RefreshLeaderboard(GameConfig.LeaderboardCategory.WeeklyDistance)
		end
	end)

	print(string.format("%s Initialized", LOG_PREFIX))
end

function LeaderboardManager.OnPlayerAdded(player: Player)
	LeaderboardManager.CheckWeeklyReset(player)
	RestoreCurrentWeeklyBestToOrderedDataStore(player)

	local resetTime = GetNextWeekResetTimestampCached()
	NetMsg.FireNotifyLeaderboardResetTime(player, resetTime)

	for category, topList in pairs(topLists) do
		NetMsg.FireNotifyLeaderboardUpdate(player, category, topList, resetTime)
	end
end

return LeaderboardManager
