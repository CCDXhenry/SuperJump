--!strict
local LeaderboardClient = {}

local replicatedStorage = game:GetService("ReplicatedStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))

local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local coreClientScripts = coreScripts:WaitForChild("Client")
local NumberExtension = require(coreSharedScripts:FindFirstChild("NumberExtension"))
local TranslationTool = require(coreClientScripts:FindFirstChild("TranslationTool"))

local CATEGORY_CONFIG = {
	[GameConfig.LeaderboardCategory.WeeklyDistance] = {
		modelName = "Leaderboard_WeeklyDistance",
		childName = "Leaderboard",
		color = Color3.fromRGB(0, 170, 255),
	},
}

local categoryFrames: { [string]: ScrollingFrame } = {}
local itemTemplates: { [string]: Frame } = {}
local countdownLabel: TextLabel? = nil
local resetTargetTimestamp: number = 0
local listenersBound = false
local initDone = false
local countdownLoopStarted = false
local pendingTopLists: { [string]: { { userId: number, value: number, name: string } } } = {}
local pendingResetTimestamp: number? = nil

local function GetFallbackNextRefreshTimestamp(): number
	local nowTimestamp = math.floor(workspace:GetServerTimeNow())
	local dateTable = os.date("!*t", nowTimestamp)
	local secondsToday = dateTable.hour * 3600 + dateTable.min * 60 + dateTable.sec
	local dayStartTimestamp = nowTimestamp - secondsToday
	local refreshInterval = GameConfig.LeaderboardUpdateInterval
	local elapsedSinceDayStart = nowTimestamp - dayStartTimestamp
	local passedIntervals = math.floor(elapsedSinceDayStart / refreshInterval)

	local nextTimestamp = dayStartTimestamp + (passedIntervals + 1) * refreshInterval
	if nextTimestamp - nowTimestamp < 2 then
		nextTimestamp += refreshInterval
	end
	return nextTimestamp
end

local function InitLeaderboards()
	local leaderboardFolder = workspace:WaitForChild("Leaderboard", 5)
	if not leaderboardFolder then
		warn("[LeaderboardClient] workspace.Leaderboard folder not found!")
		return
	end

	for category, config in pairs(CATEGORY_CONFIG) do
		local model = leaderboardFolder:FindFirstChild(config.modelName)
		if not model then
			warn("[LeaderboardClient] Model not found:", config.modelName)
			continue
		end

		local leaderboardPart = model:FindFirstChild(config.childName)
		local showPart = if leaderboardPart then leaderboardPart:FindFirstChild("Show") else nil
		local gui = if showPart then showPart:FindFirstChild("LeaderboardGui") else nil
		local mainFrame = if gui then gui:FindFirstChild("Frame") else nil
		local scroll = if mainFrame then mainFrame:FindFirstChild("ScrollingFrame") else nil

		if scroll and scroll:IsA("ScrollingFrame") then
			categoryFrames[category] = scroll

			local template = scroll:FindFirstChild("Frame")
			if template and template:IsA("Frame") then
				template.Visible = false
				itemTemplates[category] = template
			else
				warn("[LeaderboardClient] Template Frame not found in", config.modelName)
			end
		else
			warn("[LeaderboardClient] ScrollingFrame not found in", config.modelName)
		end
	end

	local countdownModel = leaderboardFolder:FindFirstChild("Leaderboard_Countdown")
	local countdownGui = if countdownModel then countdownModel:FindFirstChild("LeaderboardGui") else nil
	local countdownFrame = if countdownGui then countdownGui:FindFirstChild("Frame") else nil
	countdownLabel = if countdownFrame then countdownFrame:FindFirstChild("TextLabel") :: TextLabel else nil

	if not countdownLabel then
		warn("[LeaderboardClient] Leaderboard_Countdown TextLabel not found!")
	end
end

local function GetSecondsToNextWeekReset(): number
	if resetTargetTimestamp <= 0 then
		return 0
	end
	local now = math.floor(workspace:GetServerTimeNow())
	return resetTargetTimestamp - now
end

local function UpdateCountdownDisplay()
	if not countdownLabel then
		return
	end

	local secondsLeft = math.max(0, GetSecondsToNextWeekReset())
	local days = math.floor(secondsLeft / 86400)
	local hours = math.floor((secondsLeft % 86400) / 3600)
	local mins = math.floor((secondsLeft % 3600) / 60)
	local secs = secondsLeft % 60

	TranslationTool.CustomAutoLocalizeTextLabel(
		countdownLabel,
		GameTexts.LeaderboardRefreshCountdown.source,
		GameTexts.LeaderboardRefreshCountdown.key,
		{
			string.format("%02d", days),
			string.format("%02d", hours),
			string.format("%02d", mins),
			string.format("%02d", secs),
		}
	)
end

local function FormatDistanceLabel(quantityLabel: TextLabel, value: number, color: Color3)
	local displayDistance = math.max(0, math.floor(value + 0.5))
	TranslationTool.CustomAutoLocalizeTextLabel(
		quantityLabel,
		GameTexts.JumpRunwayDistanceMeters.source,
		GameTexts.JumpRunwayDistanceMeters.key,
		{ NumberExtension.FormatBigNumberAA(displayDistance) }
	)
	quantityLabel.TextColor3 = color
end

function LeaderboardClient.UpdateList(
	category: string,
	topList: { { userId: number, value: number, name: string } },
	resetTimestamp: number?
)
	if resetTimestamp and resetTimestamp > 0 then
		resetTargetTimestamp = resetTimestamp
	end
	local scroll = categoryFrames[category]
	local template = itemTemplates[category]
	local config = CATEGORY_CONFIG[category]
	if not scroll or not template or not config then
		pendingTopLists[category] = topList
		return
	end

	local existingRows = {}
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") and child ~= template then
			table.insert(existingRows, child)
		end
	end

	for i, data in ipairs(topList) do
		local row = existingRows[i]
		if not row then
			row = template:Clone()
			row.Parent = scroll
		end

		row.Name = "Player_" .. i
		row.Visible = true
		row.LayoutOrder = i

		local rankLabel = row:FindFirstChild("Rank") :: TextLabel
		local nameLabel = row:FindFirstChild("PlayerName") :: TextLabel
		local quantityLabel = row:FindFirstChild("Quantiy") :: TextLabel
		local playerImg = row:FindFirstChild("PlayerImg") :: ImageLabel

		if rankLabel then
			rankLabel.AutoLocalize = false
			rankLabel.Text = tostring(i)
		end

		if nameLabel then
			nameLabel.Text = data.name
		end

		if quantityLabel then
			quantityLabel.AutoLocalize = false
			FormatDistanceLabel(quantityLabel, data.value, config.color)
		end

		if playerImg then
			playerImg.Image = "rbxthumb://type=AvatarHeadShot&id=" .. data.userId .. "&w=100&h=100"
		end
	end

	for i = #topList + 1, #existingRows do
		existingRows[i].Visible = false
	end

	scroll.CanvasSize = UDim2.new(0, 0, 0, #topList * (template.Size.Y.Offset + 8))
end

local function BindNetworkListeners()
	if listenersBound then
		return
	end
	listenersBound = true
	NetMsg.ConnectNotifyLeaderboardUpdate(function(category, topList, resetTimestamp)
		LeaderboardClient.UpdateList(category, topList, resetTimestamp)
	end)

	NetMsg.ConnectNotifyLeaderboardResetTime(function(resetTimestamp)
		if resetTimestamp > 0 then
			pendingResetTimestamp = resetTimestamp
			resetTargetTimestamp = resetTimestamp
		end
	end)
end

local function ApplyPendingState()
	if pendingResetTimestamp ~= nil and pendingResetTimestamp > 0 then
		resetTargetTimestamp = pendingResetTimestamp
	end
	for category, topList in pairs(pendingTopLists) do
		LeaderboardClient.UpdateList(category, topList, nil)
	end
end

function LeaderboardClient.Init()
	if initDone then
		return
	end
	initDone = true
	InitLeaderboards()
	if resetTargetTimestamp <= 0 then
		resetTargetTimestamp = GetFallbackNextRefreshTimestamp()
	end
	ApplyPendingState()

	if countdownLoopStarted then
		return
	end
	countdownLoopStarted = true
	task.spawn(function()
		while true do
			UpdateCountdownDisplay()
			task.wait(1)
		end
	end)

	print("[LeaderboardClient] Initialized weekly distance leaderboard")
end

BindNetworkListeners()

return LeaderboardClient
