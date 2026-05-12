--!strict
-- 工厂玩法精简配置：Brainrot + Chest 工作台；岛屿/铺砖/地震等表已移除，保留占位字段供旧脚本不崩。
local GameConfig = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local DateTimeExtension = require(coreSharedScripts:FindFirstChild("DateTimeExtension"))
local BrainrotDataModule = require(script:WaitForChild("BrainrotData"))
local ChestDataModule = require(script:WaitForChild("ChestData"))
local ChestWorkbenchDataModule = require(script:WaitForChild("ChestWorkbenchData"))
local ChestWorkbenchUpgradeDataModule = require(script:WaitForChild("ChestWorkbenchUpgradeData"))
local ChestRewardPoolDataModule = require(script:WaitForChild("ChestRewardPoolData"))

GameConfig.GameVersion = "1.0.0"
GameConfig.ABTestVersion = "1.0.0"
GameConfig.PlayerSaveInfoDataVersion = 1
GameConfig.GameId = 9971505831

if game.GameId == GameConfig.GameId then
	GameConfig.GamePlaceId = 106064553761864
	GameConfig.ClearDataStorePlaceId = 73637948383969
else
	GameConfig.GamePlaceId = 17432470623
	GameConfig.ClearDataStorePlaceId = 18733054561
end

GameConfig.GamePassId = {}
GameConfig.GamePassPrice = {}

GameConfig.CoinIconImage = "rbxassetid://138756794615498"
GameConfig.RbImage = "rbxassetid://116949418469040"
GameConfig.DecelerationOnImage = "rbxassetid://114216336762183"
GameConfig.DecelerationOffImage = "rbxassetid://113696020530948"
GameConfig.DecelerationButtonShowSpeed = 40

GameConfig.GuideType = {
	None = 0,
	TutorialBrainrotPickup = 1,
	TutorialBrainrotPlace = 2,
	TutorialBricksLobby = 3,
	TutorialBricksShop = 4,
	TutorialBrainrotPlaceSlot = 5,
	TutorialBrainrotIslandTeleport = 6,
	TutorialWorkbench = 7,
	TutorialChestOpen = 8,
	TutorialFactoryPlace = 9,
}

GameConfig.GuideStepKey = {
	BricksIntroFinished = "BricksIntroFinished",
	BrainrotPlaceFinished = "BrainrotPlaceFinished",
	WorkbenchIntroFinished = "WorkbenchIntroFinished",
	ChestOpenFinished = "ChestOpenFinished",
	FactoryPlaceFinished = "FactoryPlaceFinished",
}

GameConfig.GuideWorldAnchorName = {
	Workbench = "Workbench",
}

GameConfig.GuideTextKeyMap = {
	[GameConfig.GuideType.TutorialBrainrotPickup] = "GuideTutorialBrainrotPickup",
	[GameConfig.GuideType.TutorialBrainrotPlace] = "GuideTutorialBrainrotPlace",
	[GameConfig.GuideType.TutorialBrainrotPlaceSlot] = "GuideTutorialBrainrotPlaceSlot",
	[GameConfig.GuideType.TutorialBricksLobby] = "GuideTutorialBricksLobby",
	[GameConfig.GuideType.TutorialBricksShop] = "GuideTutorialBricksShop",
	[GameConfig.GuideType.TutorialBrainrotIslandTeleport] = "GuideTutorialBrainrotIslandTeleport",
	[GameConfig.GuideType.TutorialWorkbench] = "GuideTutorialWorkbench",
	[GameConfig.GuideType.TutorialChestOpen] = "GuideTutorialChestOpen",
	[GameConfig.GuideType.TutorialFactoryPlace] = "GuideTutorialFactoryPlace",
}

GameConfig.GuideBricksIntroMinCoin = 50

GameConfig.GuideAssetName = {
	UiFrame = "GuideFrame",
	ModelArrow = "GuideArrow",
}

GameConfig.GuideArrowYOffset = 4
GameConfig.GuidePlacementBoothPath = {
	BoothFolderName = "Booth",
	BoothModelName = "BoothModel",
	CollectPartName = "CollectPart",
}

GameConfig.SixcubeGroupId = 33977495

export type RewardInfo = {
	rewardType: number,
	rewardId: number,
	rewardCount: number,
	rewardSource: number?,
	rewardLv: number?,
	productIndex: number?,
}

GameConfig.RewardType = {
	Currency = 1,
	Brainrot = 2,
	Coil = 3,
	Chest = 4,
	LittleElfChest = 4,
}

GameConfig.CurrencyType = {
	Coin = 1,
}

GameConfig.SkillType = {
	WalkSpeed = 1,
	MaxBricks = 2,
	HomeLevel = 3,
	RebirthLevel = 4,
}

GameConfig.ItemType = {
	Brainrot = 1,
	Coil = 2,
	Chest = 3,
	LittleElfChest = 3,
}

GameConfig.ModelGetSource = {
	Island = 1,
	Chest = 2,
	LittleElfChest = 2,
	Shop = 3,
	PlayerGift = 4,
	Workbench = 5,
}

GameConfig.EnablePlayerGift = false
GameConfig.PlayerRespawnTime = 1

GameConfig.CoilType = {
	Speed = 1,
	DoubleJump = 2,
	Gravity = 3,
}

GameConfig.GameTipTweenType = {
	FlyUp = 1,
	Twinkle = 2,
	StayFlyUp = 3,
	FlyUpTwinkle = 4,
	Twinkle2 = 5,
}

GameConfig.ItemCountChangeReason = {
	GainFromGMCommand = 1001,
	GainFromPurchase = 1002,
	GainFromSellModel = 1003,
	GainFromCollect = 1004,
	GainFromClaimModelYield = 1005,
	SpendOnUpgradeBrainrot = 2001,
	SpendOnUpgradeHome = 2002,
	SpendOnUpgradeWalkSpeed = 2003,
	SpendOnUpgradeMaxBricks = 2004,
	SpendOnWorkbenchUpgrade = 2005,
}

export type BrainrotData = {
	id: number,
	name_t: string,
	resourceName: string,
	iconImageId: string,
	quality: number,
	baseAbility: number,
}

local RECOVERY = 0.8
local MAX_PAYBACK = 60
local COST_RATE = 1.3

function GameConfig.GetBrainrotAbility(baseAbility: number, level: number): number
	local linear = level + baseAbility - 1
	local expo = math.ceil(baseAbility * (1.2 ^ (level - 1)))
	return math.max(linear, expo)
end

function GameConfig.GetBrainrotUpgradeCost(baseAbility: number, level: number): number
	local basePaybackTime = 5
	local maxPaybackTime = 600
	local paybackTime = math.min(basePaybackTime + 2 * level, maxPaybackTime)
	local expectedRebirthCount = math.max(math.floor((level - 10) / 10), 0)
	local expectedMultiplier = 1
	if expectedRebirthCount > 0 then
		local maxRebirthId = if GameConfig.Rebirth then #GameConfig.Rebirth else 0
		local index = math.min(expectedRebirthCount, maxRebirthId)
		local rebirthConfig = GameConfig.RebirthMap[index]
		if rebirthConfig then
			expectedMultiplier = rebirthConfig.collectMultiple
		end
	end
	local raw = baseAbility * basePaybackTime * (COST_RATE ^ (level - 1))
	local nextIncome = GameConfig.GetBrainrotAbility(baseAbility, level + 1)
	local cap = nextIncome * expectedMultiplier * paybackTime
	return math.ceil(math.min(raw, cap))
end

function GameConfig.GetBrainrotSellPrice(baseAbility: number, level: number): number
	local geoSum = baseAbility * (COST_RATE ^ (level - 1) - 1) / (COST_RATE - 1)
	local capSum = MAX_PAYBACK * GameConfig.GetBrainrotAbility(baseAbility, level) * 2
	local sellBase = baseAbility * 10
	return math.ceil(sellBase + RECOVERY * math.min(geoSum, capSum))
end

export type BrainrotQueueItem = {
	uid: string,
	itemType: number,
	configId: number,
	quality: number,
	level: number,
	chestStoredExp: number?,
	grantTipKey: string?,
	grantExpectedCount: number?,
	grantShopBundleId: number?,
}

export type BrainrotInfo = {
	instanceId: string,
	configId: number,
	level: number,
	acquireTime: number,
}

GameConfig.Brainrots = BrainrotDataModule
GameConfig.BrainrotNameMap = {} :: { [string]: BrainrotData }
GameConfig.BrainrotIdMap = {} :: { [number]: BrainrotData }

for _, config in pairs(BrainrotDataModule) do
	GameConfig.BrainrotNameMap[config.resourceName] = config
	GameConfig.BrainrotIdMap[config.id] = config
end

local function BuildResourceNameCandidates(resourceName: string): { string }
	local candidateMap: { [string]: boolean } = {}
	local candidates: { string } = {}
	local function addCandidate(name: string)
		if name == "" or candidateMap[name] then
			return
		end
		candidateMap[name] = true
		table.insert(candidates, name)
	end
	addCandidate(resourceName)
	addCandidate((string.gsub(resourceName, "_", " ")))
	addCandidate((string.gsub(resourceName, " ", "_")))
	return candidates
end

function GameConfig.GetResourceNameCandidates(resourceName: string): { string }
	return BuildResourceNameCandidates(resourceName)
end

function GameConfig.FindModelByResourceName(folder: Instance?, resourceName: string): Model?
	if not folder or resourceName == "" then
		return nil
	end
	for _, candidateName in ipairs(BuildResourceNameCandidates(resourceName)) do
		local found = folder:FindFirstChild(candidateName)
		if found and found:IsA("Model") then
			return found
		end
	end
	return nil
end

-- Model 或单个 BasePart（如 MeshPart）资源模板；用于 ReplicatedStorage.Models 下非 Model 根实例。
function GameConfig.FindResourceTemplateByResourceName(folder: Instance?, resourceName: string): Instance?
	if not folder or resourceName == "" then
		return nil
	end
	for _, candidateName in ipairs(BuildResourceNameCandidates(resourceName)) do
		local found = folder:FindFirstChild(candidateName)
		if found and (found:IsA("Model") or found:IsA("BasePart")) then
			return found
		end
	end
	return nil
end

-- 单 MeshPart/Part 包成 Model 时：脚底 RootPart、与网格同包围的 VfxInstance（Billboard / 工作台 Prompt 对齐）。
local SinglePartWrapperRootPartSize = Vector3.new(0.2, 0.2, 0.2)

local function WeldPartsRigid(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

-- 将文件夹中的模板克隆为可用于 PivotTo / Motor6D 的 Model（单 BasePart 时包一层并设 PrimaryPart）。
function GameConfig.CloneTemplateAsModel(template: Instance): Model
	if template:IsA("Model") then
		return template:Clone()
	elseif template:IsA("BasePart") then
		local wrapper = Instance.new("Model")
		wrapper.Name = template.Name
		local meshClone = template:Clone() :: BasePart
		meshClone.Parent = wrapper

		local rootPart = Instance.new("Part")
		rootPart.Name = "RootPart"
		rootPart.Size = SinglePartWrapperRootPartSize
		rootPart.Transparency = 1
		rootPart.CanCollide = false
		rootPart.CanQuery = false
		rootPart.CanTouch = false
		rootPart.Massless = true
		rootPart.Anchored = false
		rootPart.CFrame = meshClone.CFrame * CFrame.new(0, -meshClone.Size.Y * 0.5, 0)
		rootPart.Parent = wrapper

		local vfxInstance = Instance.new("Part")
		vfxInstance.Name = "VfxInstance"
		vfxInstance.Size = meshClone.Size
		vfxInstance.CFrame = meshClone.CFrame
		vfxInstance.Transparency = 1
		vfxInstance.CanCollide = false
		vfxInstance.CanQuery = false
		vfxInstance.CanTouch = false
		vfxInstance.Massless = true
		vfxInstance.Anchored = false
		vfxInstance.Parent = wrapper

		wrapper.PrimaryPart = rootPart
		WeldPartsRigid(rootPart, meshClone)
		WeldPartsRigid(meshClone, vfxInstance)

		return wrapper
	end
	warn("[GameConfig] CloneTemplateAsModel: unsupported template type", template:GetFullName(), template.ClassName)
	error("[GameConfig] CloneTemplateAsModel: template must be Model or BasePart")
end

export type CoilData = {
	id: number,
	coilType: number,
	speedValue: number,
	extraJumps: number,
	gravitationalValue: number,
	modelRes: string,
	name_t: string,
	description_t: string,
	iconImageId: string,
	quality: number,
}

GameConfig.Coils = {} :: { [number]: CoilData }
GameConfig.CoilNameMap = {} :: { [string]: CoilData }
GameConfig.CoilIdMap = {} :: { [number]: CoilData }

export type ChestConfigData = {
	id: number,
	name_t: string,
	resourceName: string,
	iconImageId: string,
	quality: number,
	exp: number,
}

export type ChestItemData = ChestConfigData
export type LittleElfChestData = ChestConfigData

GameConfig.Chests = ChestDataModule
GameConfig.ChestIdMap = {} :: { [number]: ChestConfigData }
GameConfig.ChestNameMap = {} :: { [string]: ChestConfigData }

local maxChestId = 0
for chestKey, chestRow in pairs(ChestDataModule) do
	if type(chestKey) == "number" and chestRow and type(chestRow) == "table" then
		local cfg = chestRow :: ChestConfigData
		GameConfig.ChestIdMap[cfg.id] = cfg
		GameConfig.ChestNameMap[cfg.resourceName] = cfg
		if cfg.id > maxChestId then
			maxChestId = cfg.id
		end
	end
end
GameConfig.MaxChestId = maxChestId

-- 兼容旧名：LittleElfChest* 与 Chest* 同数据或同枚举值；新代码请用 ItemType.Chest、RewardType.Chest、ChestIdMap 等。
GameConfig.LittleElfChests = ChestDataModule
GameConfig.LittleElfChestIdMap = GameConfig.ChestIdMap
GameConfig.LittleElfChestNameMap = GameConfig.ChestNameMap

export type ChestRewardPoolEntry = {
	id: number,
	itemType: number,
	itemId: number,
	weight: number,
}

export type ChestRewardPoolData = ChestRewardPoolEntry
export type LittleElfChestRewardPoolData = ChestRewardPoolEntry

GameConfig.ChestRewardPoolMap = {} :: { [number]: { ChestRewardPoolEntry } }
for _, poolRow in pairs(ChestRewardPoolDataModule) do
	local entry = poolRow :: ChestRewardPoolEntry
	local chestTier = entry.id
	if not GameConfig.ChestRewardPoolMap[chestTier] then
		GameConfig.ChestRewardPoolMap[chestTier] = {}
	end
	table.insert(GameConfig.ChestRewardPoolMap[chestTier], entry)
end
GameConfig.LittleElfChestRewardPoolMap = GameConfig.ChestRewardPoolMap

export type ChestWorkbenchRow = {
	id: number,
	type: number,
	name: string,
	initialExp: number,
	initialRate: number,
}

GameConfig.ChestWorkbenchById = {} :: { [number]: ChestWorkbenchRow }
for _, w in pairs(ChestWorkbenchDataModule) do
	local row = w :: ChestWorkbenchRow
	GameConfig.ChestWorkbenchById[row.id] = row
end

GameConfig.WorkbenchType = {
	Manual = 1,
	Auto = 2,
	Place = 3,
}

export type ChestWorkbenchUpgradeRow = {
	rowId: number,
	workbenchId: number,
	upgradeType: number,
	price: number,
	increaseValue: number,
}

GameConfig.ChestWorkbenchUpgradeByRowId = {} :: { [number]: ChestWorkbenchUpgradeRow }
for rowKey, row in pairs(ChestWorkbenchUpgradeDataModule) do
	local rk = if type(rowKey) == "number" then rowKey else tonumber(tostring(rowKey)) or 0
	local r = row :: any
	local parsed: ChestWorkbenchUpgradeRow = {
		rowId = rk,
		workbenchId = r.workbenchId,
		upgradeType = r.upgradeType,
		price = r.price,
		increaseValue = r.increaseValue,
	}
	GameConfig.ChestWorkbenchUpgradeByRowId[rk] = parsed
end

GameConfig.DefaultWorkbenchChestTier = 1
-- 工作台空槽位从无到有生成基础宝箱的间隔（秒）
GameConfig.ChestWorkbenchSpawnIntervalSeconds = 3
GameConfig.FactoryChestsFolderName = "FactoryChests"
GameConfig.ChestWorkbenchCollectionTag = "ChestWorkbench"
GameConfig.ChestWorkbenchSlotPartName = "ChestSlot"
-- 工作台宝箱 ChestInfoUI（Billboard）在自动高度基础上额外上移的 studs（Y）
GameConfig.ChestWorkbenchChestInfoUIBillboardOffsetY = 3
-- 玩家手持 Tool 形态的宝箱 ChestInfoUI（Billboard）在自动高度基础上额外上移的 studs（Y）
GameConfig.ChestCarryingChestInfoUIBillboardOffsetY = 3

export type IslandData = {
	id: number,
	islandName: string,
	itemMinLv: number,
	itemMaxLv: number,
	rebirthCount: number,
	brainrotGenerateCount: number,
	chestGenerateCount: number,
	floatBlockDropCountJudge: number?,
	dropRecoverDelayMin: number?,
	dropRecoverDelayMax: number?,
}

export type IslandEarthquakeData = {
	floatBlockDropCountJudge: number,
	DropRecoverDelayMin: number,
	DropRecoverDelayMax: number,
}

export type IslandSpawnerData = {
	id: number,
	itemType: number,
	itemId: number,
	weight: number,
}

GameConfig.IslandConfigMap = {} :: { [number]: IslandData }
GameConfig.IslandEarthquakeConfigMap = {} :: { [number]: IslandEarthquakeData }
GameConfig.IslandSpawnerMap = {} :: { [number]: { IslandSpawnerData } }

export type RebirthData = {
	id: number,
	count: number,
	collectMultiple: number,
	brickLv: number,
	speedLv: number,
}

GameConfig.Rebirth = {} :: { RebirthData }
GameConfig.RebirthMap = {} :: { [number]: RebirthData }

GameConfig.BrainrotQualityConfig = {
	[1] = { rarity = "Common", image = "rbxassetid://16865599320", textColor = Color3.fromRGB(255, 255, 255) },
	[2] = { rarity = "Uncommon", image = "rbxassetid://16865599320", textColor = Color3.fromRGB(73, 230, 0) },
	[3] = { rarity = "Rare", image = "rbxassetid://16865599122", textColor = Color3.fromRGB(0, 255, 217) },
	[4] = { rarity = "Epic", image = "rbxassetid://16865598960", textColor = Color3.fromRGB(30, 144, 255) },
	[5] = { rarity = "Legendary", image = "rbxassetid://16865598826", textColor = Color3.fromRGB(255, 0, 255) },
	[6] = { rarity = "Mythical", image = "rbxassetid://16865598729", textColor = Color3.fromRGB(136, 0, 255) },
	[7] = { rarity = "Cosmic", image = "rbxassetid://16865598729", textColor = Color3.fromRGB(255, 0, 68) },
	[8] = { rarity = "Secret", image = "rbxassetid://16865598729", textColor = Color3.fromRGB(255, 136, 0) },
	[9] = { rarity = "Celestial", image = "rbxassetid://16865598729", textColor = Color3.fromRGB(255, 234, 1) },
}

GameConfig.RobuxIconText = "\u{E002}"

GameConfig.BrainrotQualityTextMap = {
	[1] = "QualityCommon",
	[2] = "QualityUncommon",
	[3] = "QualityRare",
	[4] = "QualityEpic",
	[5] = "QualityLegendary",
	[6] = "QualityMythical",
	[7] = "QualityCosmic",
	[8] = "QualitySecret",
	[9] = "QualityCelestial",
}

GameConfig.BrainrotLevelTierSize = 30

local brainrotQualityMaxTierForLevelColor = 0
for tierKey in pairs(GameConfig.BrainrotQualityConfig) do
	if type(tierKey) == "number" and tierKey > brainrotQualityMaxTierForLevelColor then
		brainrotQualityMaxTierForLevelColor = tierKey
	end
end

GameConfig.BrainrotLevelTierTextColors = {} :: { [number]: Color3 }
for tier = 1, brainrotQualityMaxTierForLevelColor do
	local qc = GameConfig.BrainrotQualityConfig[tier]
	if qc then
		GameConfig.BrainrotLevelTierTextColors[tier] = qc.textColor
	end
end

function GameConfig.GetBrainrotLevelTierTextColor(level: number): Color3
	local safeLevel = math.max(1, math.floor(level))
	local tierIndex = math.floor(safeLevel / GameConfig.BrainrotLevelTierSize) + 1
	tierIndex = math.min(tierIndex, brainrotQualityMaxTierForLevelColor)
	local c = GameConfig.BrainrotLevelTierTextColors[tierIndex]
	return if c then c else Color3.new(1, 1, 1)
end

GameConfig.Paving = {
	BaseCollapseTime = 10,
	SteppedPenalty = 5,
	MinCollapseTime = 0.5,
	BackBricksMaxVisual = 0,
	BrickSize = Vector3.new(4, 1, 4),
	MaxBatchSize = 15,
	LocalPredictTTL = 1.5,
	BatchInterval = 0.06,
	MaxPendingBatchesDuringEarthquake = 8,
	BatchIntervalDuringEarthquake = 0.06,
	MaxInterpolationSteps = 5,
	MaxInterpolationStepsAtHighSpeed = 10,
	HighSpeedLookaheadMaxFactor = 2.2,
	FirstBrickForceQueueCooldown = 0.12,
	BatchAckTimeout = 0.9,
	MaxPendingBatches = 8,
	OutOfBricksSupportTime = 1.2,
	OutOfBricksSupportRenewThreshold = 0.35,
	OutOfBricksSupportRequestInterval = 0.12,
	DeathThreshold = -10,
	DeathRescueProductId = 3567697241,
	RescueFlightMinLastArrivedIslandId = 5,
	PavingDistanceLimit = 30,
	StationaryRenewalThreshold = 0.9,
	StationaryRenewalMaxRemainingTime = 1,
	StationaryRenewalInterval = 0.2,
	RebirthProductId = 3567723594,
	StartTriggerRefillCooldown = 0.15,
	GroundTouchRefillCooldown = 0.15,
	GroundPollRefillInterval = 2,
	RefillSurfaceRayLength = 80,
	NoPaveWhenFeetBelowSeaStuds = 3,
}

GameConfig.PavingRejectReason = {
	InvalidPayload = "InvalidPayload",
	BatchTooLarge = "BatchTooLarge",
	NotVector3 = "NotVector3",
	SafeZoneBlocked = "SafeZoneBlocked",
	FloatBlockBlocked = "FloatBlockBlocked",
	HeightMismatch = "HeightMismatch",
	DistanceLimit = "DistanceLimit",
	OutOfBricks = "OutOfBricks",
	OccupiedByOther = "OccupiedByOther",
	ServerBackpressure = "ServerBackpressure",
	FallSafePitBlocked = "FallSafePitBlocked",
}

GameConfig.UpgradeHomeInfoUIDistanceLimit = 40
GameConfig.HomePlaceModelInfoUIBillboardPadding = 0.5
GameConfig.HomePlaceModelInfoUIBillboardOffsetY = 5

GameConfig.Earthquake = {
	IntervalMin = 999999,
	IntervalMax = 999999,
	Duration = 0,
	CooldownAfterEnd = 0,
	MinPlayersToTrigger = 99,
	IntenseShakeAmplitude = 0,
	IntenseShakeFrequency = 0,
	PreFallIntenseDuration = 0,
	FallDuration = 0,
	RiseDuration = 0,
	FallOffsetY = 0,
	WarningSeconds = 0,
	PavedBrickDestroyDelayAfterDrop = 0,
	MarkedBrickColor = Color3.fromRGB(255, 0, 25),
	MarkedFloatBlockTransparency = 0.5,
	MarkedPavedBrickTransparency = 0.5,
	MarkedShakeAmplitude = 0,
	MarkedShakeFrequency = 0,
	MarkedPavedShakeAmplitude = 0,
	MarkedPavedShakeFrequency = 0,
	DropExecuteWindowSeconds = 1,
	FractureShardLifeTime = 0.5,
	FractureShardPerBlock = 5,
	ScreenShakeAmplitude = 0,
	ScreenShakeFrequency = 0,
}

GameConfig.Inventory = {
	InitialModelCapacity = 5,
	InitialBricksCapacityLevel = 1,
}

GameConfig.BrainrotRefreshCountdownSeconds = 150

export type UpgradeShopData = {
	id: number,
	name_t: string,
	maxLevel: number,
	abilityList: { [number]: number },
	upgradeCostList: { [number]: number },
}

local function MakeStubShop(skillType: number, name_t: string, ability: number): UpgradeShopData
	return {
		id = skillType,
		name_t = name_t,
		maxLevel = 1,
		abilityList = { [1] = ability },
		upgradeCostList = {},
	}
end

GameConfig.Shop = {
	WalkSpeed = MakeStubShop(GameConfig.SkillType.WalkSpeed, "WalkSpeed", 16),
	MaxBricks = MakeStubShop(GameConfig.SkillType.MaxBricks, "MaxBricks", 500),
	HomeLevel = MakeStubShop(GameConfig.SkillType.HomeLevel, "HomeLevel", 1),
}

export type ShopBundleConfigurationData = {
	id: number,
	type: number,
	canRepurchased: number,
	nameColor: { number },
	productId1: number,
	productId2: number,
	productId3: number,
	price1: number,
	price2: number,
	price3: number,
	beforeDiscountPrice2: number,
	beforeDiscountPrice3: number,
	name_t: string,
	sortId: number,
	bgIconId: string,
	arePaidRandomItemsRestricted: number,
}

export type ShopBundleData = {
	config: ShopBundleConfigurationData,
	rewards: { RewardInfo },
}

GameConfig.ShopBundleById = {} :: { [number]: ShopBundleData }
GameConfig.ShopBundleList = {} :: { number }

export type ShopPaidConfig = {
	WalkSpeed10ProductId: number,
	MaxBricks10ProductId: number,
	BrainrotUpgrade3ProductId: number,
}

GameConfig.ShopPaid = {
	WalkSpeed10ProductId = 3567697343,
	MaxBricks10ProductId = 3567697394,
	BrainrotUpgrade3ProductId = 3568879048,
} :: ShopPaidConfig

export type ModelRarity = "Common" | "Rare" | "Epic" | "Legend"

export type ModelInfo = {
	instanceId: string,
	configId: number,
	rarity: ModelRarity,
	level: number,
	unclaimedYield: number?,
	yieldAccrueStartUnix: number?,
	yieldAccruedSeconds: number?,
}

export type SettingInfo = {
	bgmVolume: number,
	soundEffectVolume: number,
	vibrationOn: boolean,
	decelerationOn: boolean,
}

export type PlayerConfigInfo = {
	arePaidRandomItemsRestricted: boolean,
}

export type PlayerInventorySaveInfo = {
	models: { ModelInfo },
}

export type BrainrotInventoryInfo = {
	ownedBrainrots: { [string]: BrainrotInfo },
	equippedBrainrots: { string },
	brainrotUsingNumMax: number,
}

export type PlayerCarriedInfo = {
	bricks: number,
}

export type GuideProgressSaveInfo = {
	guideStepDoneMap: { [string]: boolean },
	appearedGuideTypeInfo: { [string]: boolean },
}

export type WorkbenchSlotSave = {
	configId: number,
	storedExp: number,
}

export type SingleWorkbenchSave = {
	slots: { [number]: WorkbenchSlotSave? },
}

export type ChestWorkbenchSave = {
	purchasedWorkbenchUpgradeIds: { [string]: boolean },
	workbenches: { [string]: SingleWorkbenchSave },
}

function GameConfig.CreateDefaultChestWorkbenchSave(): ChestWorkbenchSave
	return {
		purchasedWorkbenchUpgradeIds = {},
		workbenches = {},
	}
end

export type PlayerSaveInfo = {
	dataVersion: number,
	firstEnterTime: number,
	firstEnterVersion: string,
	gameTime: number,
	loginDays: number,
	lastOnlineDateUTC: number,
	settingInfo: SettingInfo,
	ownedGamePassList: { number },
	ownedShopBundleMap: { [number]: boolean },
	currencies: { [string]: number },
	inventoryInfo: PlayerInventorySaveInfo,
	homeInfo: {
		level: number,
		placedModels: { [string]: ModelInfo },
	},
	shopInfo: {
		walkSpeedLevel: number,
		maxBricksLevel: number,
		rebirthLevel: number,
	},
	brainrotsInfo: BrainrotInventoryInfo,
	brainrotQueue: { BrainrotQueueItem },
	guideProgressInfo: GuideProgressSaveInfo,
	discoveredIslandIds: { [string]: boolean }?,
	chestWorkbenchSave: ChestWorkbenchSave,
}

export type PlayerInfo = PlayerSaveInfo & {
	playerInfoChanged: boolean,
	timeOfThisLogin: number,
	countryRegion: string,
	lastOnlineDate: DateTimeExtension.DateTimeTable,
	ownedGamePassMap: { [number]: boolean },
	playerConfigInfo: PlayerConfigInfo,
	homeSlot: string,
	carriedInfo: PlayerCarriedInfo,
	lastArrivedIslandId: number,
}

export type ReceiptInfo = {
	PurchaseId: string,
	PlayerId: number,
	ProductId: number,
	PlaceIdWherePurchased: number,
	CurrencySpent: number,
	CurrencyType: Enum.CurrencyType,
}

function GameConfig.CreateDefaultPlayerSaveInfo(): PlayerSaveInfo
	local nowDate: DateTimeExtension.DateTimeTable = DateTimeExtension.GetNowDate()
	return {
		dataVersion = GameConfig.PlayerSaveInfoDataVersion,
		firstEnterTime = DateTime.now().UnixTimestamp,
		firstEnterVersion = GameConfig.GameVersion,
		gameTime = 0,
		loginDays = 1,
		lastOnlineDateUTC = DateTime.fromUniversalTime(nowDate.Year, nowDate.Month, nowDate.Day).UnixTimestamp,
		settingInfo = {
			bgmVolume = 1,
			soundEffectVolume = 1,
			vibrationOn = true,
			decelerationOn = false,
		},
		ownedGamePassList = {},
		ownedShopBundleMap = {},
		currencies = {
			["1"] = 0,
		},
		inventoryInfo = {
			models = {},
		},
		homeInfo = {
			level = 1,
			placedModels = {},
		},
		shopInfo = {
			walkSpeedLevel = 1,
			maxBricksLevel = GameConfig.Inventory.InitialBricksCapacityLevel,
			rebirthLevel = 0,
		},
		brainrotsInfo = {
			ownedBrainrots = {},
			equippedBrainrots = {},
			brainrotUsingNumMax = 3,
		},
		brainrotQueue = {},
		guideProgressInfo = {
			guideStepDoneMap = {},
			appearedGuideTypeInfo = {},
		},
		discoveredIslandIds = {},
		chestWorkbenchSave = GameConfig.CreateDefaultChestWorkbenchSave(),
	}
end

export type ClientLocalPlayerSaveInfo = {
	settingInfo: SettingInfo,
	ownedGamePassList: { number },
	ownedShopBundleMap: { [number]: boolean },
	currencies: { [string]: number },
	inventoryInfo: PlayerInventorySaveInfo,
	homeInfo: {
		level: number,
		placedModels: { [string]: ModelInfo },
	},
	shopInfo: {
		walkSpeedLevel: number,
		maxBricksLevel: number,
		rebirthLevel: number,
	},
	brainrotsInfo: BrainrotInventoryInfo,
	brainrotQueue: { BrainrotQueueItem },
	homeSlot: string,
	guideProgressInfo: GuideProgressSaveInfo,
	chestWorkbenchSave: ChestWorkbenchSave,
}

export type ClientLocalPlayerInfo = ClientLocalPlayerSaveInfo & {
	ownedGamePassMap: { [number]: boolean },
	playerConfigInfo: PlayerConfigInfo,
	carriedInfo: PlayerCarriedInfo,
	currentGuideType: number,
}

export type ClientOtherPlayerSaveInfo = {
	homeSlot: string,
	homeInfo: {
		level: number,
		placedModels: { [string]: ModelInfo },
	},
	rebirthLevel: number?,
}

export type ClientOtherPlayerSyncInfo = ClientOtherPlayerSaveInfo & {}
export type ClientOtherPlayerInfo = ClientOtherPlayerSyncInfo & {}

return GameConfig
