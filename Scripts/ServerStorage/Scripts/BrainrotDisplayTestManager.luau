--!strict
local BrainrotDisplayTestManager = {}

local httpService = game:GetService("HttpService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local serverStorage = game:GetService("ServerStorage")
local workspace = game:GetService("Workspace")

local serverCore = serverStorage:WaitForChild("Core")
local serverCoreScripts = serverCore:WaitForChild("Scripts")
local GMConfig = require(serverCoreScripts:WaitForChild("GMConfig"))

local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:WaitForChild("ServerGameInfo"))
local BrainrotQueueManager = require(serverScripts:WaitForChild("BrainrotQueueManager"))

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))

local LogPrefix = "[BrainrotDisplayTestManager]"

local AUTO_RUN_IN_STUDIO = false
local TEST_BRAINROT_LEVEL = 1
local SHOWCASE_GRID_COLUMNS = 30
local SHOWCASE_COLUMN_SPACING = 14
local SHOWCASE_ROW_SPACING = 14
local SHOWCASE_ORIGIN_POSITION = Vector3.new(-360.5, 9.794, 326.551)

local SHOWCASE_ROOT_NAME = "BrainrotDisplayTest"
local CHAT_COMMAND_SPAWN = "/testAllBrainrot"
local CHAT_COMMAND_CLEAR = "/clearBrainrotTest"

local initDone = false
local actualModels = replicatedStorage:WaitForChild("Models"):WaitForChild("Brainrots")

local function isAuthorized(player: Player): boolean
	return runService:IsStudio() or GMConfig.IsGMPlayer(player.UserId)
end

local function getSortedBrainrotConfigIds(): { number }
	local configIds: { number } = {}
	for configId in pairs(GameConfig.BrainrotIdMap) do
		table.insert(configIds, configId)
	end
	table.sort(configIds)
	return configIds
end

local function getPlotsPerFloor(slotModel: Instance): number
	local lv1 = slotModel:FindFirstChild("Lv1")
	if not lv1 then
		return 6
	end
	local count = 0
	for _, child in ipairs(lv1:GetChildren()) do
		if child.Name:match("^PlaceModel%d+$") then
			count += 1
		end
	end
	return if count > 0 then count else 6
end

local function getMaxHomePlotCount(homeSlot: string, homeLevel: number): number
	local homesFolder = workspace:FindFirstChild("PlayersHome")
	if not homesFolder then
		return homeLevel * 6
	end
	local slotModel = homesFolder:FindFirstChild(homeSlot)
	if not slotModel then
		return homeLevel * 6
	end
	return homeLevel * getPlotsPerFloor(slotModel)
end

local function buildModelInfo(configId: number, level: number, variantId: number?): GameConfig.ModelInfo
	local brainrotData = GameConfig.BrainrotIdMap[configId]
	local quality = if brainrotData then brainrotData.quality else 1
	local qualityCfg = GameConfig.BrainrotQualityConfig[quality]
	local defaultQualityCfg = GameConfig.BrainrotQualityConfig[1]
	local rarity: GameConfig.ModelRarity = (
		if qualityCfg then qualityCfg.rarity else if defaultQualityCfg then defaultQualityCfg.rarity else "Common"
	) :: any
	return {
		instanceId = httpService:GenerateGUID(false),
		configId = configId,
		level = level,
		rarity = rarity,
		variantId = variantId,
		unclaimedYield = 0,
	}
end

local function destroyBrainrotTools(player: Player)
	local char = player.Character
	if char then
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
				child:Destroy()
			end
		end
	end
	for _, child in ipairs(player.Backpack:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
			child:Destroy()
		end
	end
end

local function clearBrainrotQueueItems(player: Player)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return
	end

	destroyBrainrotTools(player)

	local keptItems: { GameConfig.BrainrotQueueItem } = {}
	for _, item in ipairs(playerInfo.brainrotQueue) do
		if item.itemType ~= GameConfig.ItemType.Brainrot then
			table.insert(keptItems, item)
		end
	end
	playerInfo.brainrotQueue = keptItems
	playerInfo.playerInfoChanged = true
	NetMsg.FireNotifyBrainrotQueueUpdate(player, playerInfo.brainrotQueue)
end

local function clearPlacedBrainrotModels(player: Player)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return
	end

	local nextPlacedModels: { [string]: GameConfig.ModelInfo } = {}
	for pointIndexStr, placedModel in pairs(playerInfo.homeInfo.placedModels) do
		local configId = (placedModel :: any).configId
		if type(configId) == "number" and GameConfig.BrainrotIdMap[configId] == nil then
			nextPlacedModels[pointIndexStr] = placedModel
		end
	end
	playerInfo.homeInfo.placedModels = nextPlacedModels
	playerInfo.playerInfoChanged = true
	ServerGameInfo.NotifyPlayerHomeInfoUpdate(player.UserId)
end

local function setHomeToMaxLevel(player: Player)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return
	end

	local homeShop = GameConfig.Shop.HomeLevel
	local maxLevel = if homeShop and homeShop.maxLevel > 0 then homeShop.maxLevel else 1
	if playerInfo.homeInfo.level ~= maxLevel then
		playerInfo.homeInfo.level = maxLevel
		playerInfo.playerInfoChanged = true
		ServerGameInfo.NotifyPlayerHomeInfoUpdate(player.UserId)
	end
end

local function findBoothTemplate(): Instance?
	local homesFolder = workspace:FindFirstChild("PlayersHome")
	if not homesFolder then
		return nil
	end
	for _, slotModel in ipairs(homesFolder:GetChildren()) do
		local lv1 = slotModel:FindFirstChild("Lv1")
		if lv1 then
			local placeModel = lv1:FindFirstChild("PlaceModel1")
			if placeModel then
				return placeModel
			end
		end
	end
	return nil
end

local function getShowcaseRoot(): Folder
	local existing = workspace:FindFirstChild(SHOWCASE_ROOT_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = SHOWCASE_ROOT_NAME
	folder.Parent = workspace
	return folder
end

local function clearPlayerShowcase(player: Player)
	local showcaseRoot = workspace:FindFirstChild(SHOWCASE_ROOT_NAME)
	if not showcaseRoot then
		return
	end
	local playerFolder = showcaseRoot:FindFirstChild(tostring(player.UserId))
	if playerFolder then
		playerFolder:Destroy()
	end
end

local function getShowcaseWorldPosition(index: number): Vector3
	local zeroBasedIndex = index - 1
	local column = zeroBasedIndex % SHOWCASE_GRID_COLUMNS
	local row = math.floor(zeroBasedIndex / SHOWCASE_GRID_COLUMNS)
	return SHOWCASE_ORIGIN_POSITION + Vector3.new(
		-row * SHOWCASE_ROW_SPACING,
		0,
		column * SHOWCASE_COLUMN_SPACING
	)
end

local function createDebugBillboard(parent: BasePart, configId: number, brainrotName: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DebugLabel"
	billboard.Size = UDim2.fromOffset(220, 56)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.35
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = string.format("#%d\n%s", configId, brainrotName)
	label.Parent = billboard
end

local function spawnVisualOnBooth(boothFolder: Instance, configId: number, level: number)
	local brainrotData = GameConfig.BrainrotIdMap[configId]
	if not brainrotData then
		return
	end

	local oldVisual = boothFolder:FindFirstChild("VisualModel")
	if oldVisual then
		oldVisual:Destroy()
	end

	local template = GameConfig.FindResourceTemplateByResourceName(actualModels, brainrotData.resourceName)
	if not template then
		warn(
			LogPrefix,
			"Missing brainrot template:",
			brainrotData.resourceName,
			"candidates:",
			table.concat(GameConfig.GetResourceNameCandidates(brainrotData.resourceName), ", ")
		)
		return
	end

	local modelContainer = boothFolder:FindFirstChild("Model") or boothFolder:FindFirstChild("RootPart")
	if not modelContainer then
		warn(LogPrefix, "Booth missing Model/RootPart container:", boothFolder:GetFullName())
		return
	end

	local newVisual = GameConfig.CloneTemplateAsModel(template)
	newVisual.Name = "VisualModel"
	newVisual:SetAttribute("ConfigId", configId)

	local targetCFrame: CFrame? = nil
	local placeholder = modelContainer:FindFirstChild("Model")
	if placeholder and placeholder:IsA("Model") then
		targetCFrame = placeholder:GetPivot()
	elseif placeholder and placeholder:IsA("BasePart") then
		targetCFrame = placeholder.CFrame
	elseif modelContainer:IsA("BasePart") then
		targetCFrame = modelContainer.CFrame * CFrame.new(0, modelContainer.Size.Y / 2, 0)
	elseif modelContainer:IsA("Model") then
		targetCFrame = modelContainer:GetPivot()
	end

	if targetCFrame then
		newVisual:PivotTo(targetCFrame)
	end

	for _, part in ipairs(newVisual:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end

	GameConfig.ApplyBrainrotModelScale(
		newVisual,
		level,
		GameConfig.GetBrainrotTemplateBaseScale(template)
	)
	newVisual.Parent = boothFolder

	local rootPart = newVisual:FindFirstChild("RootPart")
	if rootPart and rootPart:IsA("BasePart") then
		createDebugBillboard(rootPart, configId, brainrotData.name_t or brainrotData.resourceName)
	end
end

local function spawnShowcaseGrid(player: Player, configIds: { number }, level: number)
	clearPlayerShowcase(player)

	local boothTemplate = findBoothTemplate()
	if not boothTemplate then
		warn(LogPrefix, "Cannot spawn showcase: PlaceModel1 template not found in PlayersHome")
		return
	end

	local showcaseRoot = getShowcaseRoot()
	local playerFolder = Instance.new("Folder")
	playerFolder.Name = tostring(player.UserId)
	playerFolder.Parent = showcaseRoot

	for index, configId in ipairs(configIds) do
		local booth = boothTemplate:Clone()
		booth.Name = string.format("TestBooth_%03d", configId)
		local boothCFrame = CFrame.new(getShowcaseWorldPosition(index))
		if booth:IsA("Model") then
			booth:PivotTo(boothCFrame)
		elseif booth:IsA("BasePart") then
			booth.CFrame = boothCFrame
		end
		booth.Parent = playerFolder
		spawnVisualOnBooth(booth, configId, level)
	end

	print(
		LogPrefix,
		"Spawned showcase for",
		player.Name,
		"count =",
		#configIds,
		"origin =",
		SHOWCASE_ORIGIN_POSITION,
		"columns =",
		SHOWCASE_GRID_COLUMNS
	)
end

local function populateHomeBooths(player: Player, configIds: { number }, level: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo or playerInfo.homeSlot == "" then
		warn(LogPrefix, "Skip home booths: player has no home slot yet", player.Name)
		return
	end

	setHomeToMaxLevel(player)
	clearPlacedBrainrotModels(player)

	local maxPlotCount = getMaxHomePlotCount(playerInfo.homeSlot, playerInfo.homeInfo.level)
	local placedCount = math.min(#configIds, maxPlotCount)
	for pointIndex = 1, placedCount do
		local configId = configIds[pointIndex]
		ServerGameInfo.UpdatePlayerPlacedModel(player, pointIndex, buildModelInfo(configId, level, nil))
	end

	print(LogPrefix, "Placed on home booths for", player.Name, "count =", placedCount, "maxPlotCount =", maxPlotCount)
end

local function populateBrainrotTools(player: Player, configIds: { number }, level: number)
	clearBrainrotQueueItems(player)

	for _, configId in ipairs(configIds) do
		local brainrotData = GameConfig.BrainrotIdMap[configId]
		local quality = if brainrotData then brainrotData.quality else 1
		BrainrotQueueManager.AddItem(player, configId, quality, level, false, GameConfig.ItemType.Brainrot, false)
	end

	print(LogPrefix, "Granted brainrot tools for", player.Name, "count =", #configIds)
end

function BrainrotDisplayTestManager.RunForPlayer(player: Player)
	if not isAuthorized(player) then
		warn(LogPrefix, "Unauthorized:", player.Name)
		return
	end

	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		warn(LogPrefix, "PlayerInfo not ready:", player.Name)
		return
	end

	local configIds = getSortedBrainrotConfigIds()
	if #configIds == 0 then
		warn(LogPrefix, "No brainrot configs found")
		return
	end

	populateHomeBooths(player, configIds, TEST_BRAINROT_LEVEL)
	spawnShowcaseGrid(player, configIds, TEST_BRAINROT_LEVEL)
	populateBrainrotTools(player, configIds, TEST_BRAINROT_LEVEL)

	print(LogPrefix, "Completed for", player.Name, "total brainrots =", #configIds)
end

function BrainrotDisplayTestManager.ClearForPlayer(player: Player)
	if not isAuthorized(player) then
		return
	end
	clearPlayerShowcase(player)
	clearPlacedBrainrotModels(player)
	clearBrainrotQueueItems(player)
	print(LogPrefix, "Cleared test content for", player.Name)
end

local function onPlayerChatted(player: Player, message: string)
	if not isAuthorized(player) then
		return
	end

	local trimmed = string.gsub(message, "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")

	if trimmed == CHAT_COMMAND_SPAWN then
		BrainrotDisplayTestManager.RunForPlayer(player)
	elseif trimmed == CHAT_COMMAND_CLEAR then
		BrainrotDisplayTestManager.ClearForPlayer(player)
	end
end

local function tryAutoRunForPlayer(player: Player)
	if not AUTO_RUN_IN_STUDIO or not runService:IsStudio() then
		return
	end

	task.spawn(function()
		local deadline = os.clock() + 30
		while player.Parent and os.clock() < deadline do
			local playerInfo = ServerGameInfo.GetPlayerInfo(player)
			if playerInfo and playerInfo.homeSlot ~= "" then
				BrainrotDisplayTestManager.RunForPlayer(player)
				return
			end
			task.wait(0.5)
		end
		warn(LogPrefix, "Auto run timed out waiting for home slot:", player.Name)
	end)
end

function BrainrotDisplayTestManager.Init()
	if initDone then
		return
	end
	initDone = true

	players.PlayerAdded:Connect(function(player: Player)
		player.Chatted:Connect(function(message: string)
			onPlayerChatted(player, message)
		end)
		tryAutoRunForPlayer(player)
	end)

	for _, player in ipairs(players:GetPlayers()) do
		player.Chatted:Connect(function(message: string)
			onPlayerChatted(player, message)
		end)
		tryAutoRunForPlayer(player)
	end

	print(LogPrefix, "Init complete. Commands:", CHAT_COMMAND_SPAWN, CHAT_COMMAND_CLEAR)
end

return BrainrotDisplayTestManager
