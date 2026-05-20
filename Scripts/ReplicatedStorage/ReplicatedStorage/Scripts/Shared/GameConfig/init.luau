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
local LittleElfChestDataModule = require(script:WaitForChild("LittleElfChestData"))
local LittleElfChestRewardPoolDataModule = require(script:WaitForChild("LittleElfChestRewardPoolData"))

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

-- 独立数据：小精灵宝箱（JumpRunway 终局奖励用）
GameConfig.LittleElfChests = LittleElfChestDataModule
GameConfig.LittleElfChestIdMap = {} :: { [number]: ChestConfigData }
GameConfig.LittleElfChestNameMap = {} :: { [string]: ChestConfigData }

for leChestKey, leChestRow in pairs(LittleElfChestDataModule) do
	if type(leChestKey) == "number" and leChestRow and type(leChestRow) == "table" then
		local cfg = leChestRow :: ChestConfigData
		GameConfig.LittleElfChestIdMap[cfg.id] = cfg
		GameConfig.LittleElfChestNameMap[cfg.resourceName] = cfg
	end
end

GameConfig.LittleElfChestRewardPoolMap = {} :: { [number]: { ChestRewardPoolEntry } }
for _, poolRow in pairs(LittleElfChestRewardPoolDataModule) do
	local entry = poolRow :: ChestRewardPoolEntry
	local chestTier = entry.id
	if not GameConfig.LittleElfChestRewardPoolMap[chestTier] then
		GameConfig.LittleElfChestRewardPoolMap[chestTier] = {}
	end
	table.insert(GameConfig.LittleElfChestRewardPoolMap[chestTier], entry)
end

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

-- JumpRunway（跑道跳跃）玩法常量；策划常用数值见 GameConfig.JumpRunwayDesigner。
-- 跑道前向轴：StartTrigger 的本地 X 轴在世界空间方向（StartTrigger.CFrame.RightVector）。
-- 物理与状态机由客户端权威驱动；服务端仅会话登记、沿轴样本防作弊与终局距离采纳。
-- JumpRunway 表内按主题分组；常用项由 JumpRunwayDesigner 透传，实现细节注释仍在本表。

-- JumpRunway 策划调参：仅修改本表数值；经 GameConfig.JumpRunway 透传，业务勿直接读此表。
GameConfig.JumpRunwayDesigner = {
	-- ═══════════════════════════════════════
	-- —— ① 会话 / 起跳窗 ——
	-- ═══════════════════════════════════════
	-- 总局可跳次数；↑ 跑道更长、终局冲刺更晚；↓ 更短局
	N_TOTAL_JUMPS = 3,
	-- 单次起跳窗时长(s)；↑ 更容易踩线、节奏更松；↓ 更苛刻
	T_WINDOW = 1.35,
	-- 窗内 Perfect 时间占比上限；↑ Perfect 窗口更宽
	JUMP_WINDOW_RATING_PERFECT_MAX_FRAC = 1 / 3,
	-- 窗内 Ok 时间占比上限；↑ Ok 窗口更宽
	JUMP_WINDOW_RATING_OK_MAX_FRAC = 2 / 3,
	-- 起跳窗慢漂 WalkSpeed；↑ 窗内更易微调站位
	JUMP_WINDOW_WALK_SPEED = 10,

	-- ═══════════════════════════════════════
	-- —— ② 沿轴水平速度 ——
	-- ═══════════════════════════════════════
	-- 首跳前线前 AutoRun 沿轴速；↑ 起跳前冲更快
	FIRST_TAKEOFF_AUTORUN_SPEED = 30,
	-- 段内沿轴 max 初值；↑ 全程更快
	JUMP_SPEED_INITIAL_MAX = 30,
	-- max 与 min 固定差；↑ 段内减速幅度更大
	JUMP_SPEED_MAX_TO_MIN_DELTA = 10,
	-- [1]=Perfect,[2]=Ok,[3]=Late 每次起跳累加 bonus；↑ 踩点好则全程更快
	JUMP_WINDOW_RATING_SPEED_BONUS_BY_TIER = {
		[1] = 20,
		[2] = 10,
		[3] = 5,
	},

	-- ═══════════════════════════════════════
	-- —— ③ 起跳 / 重力 / 贴地 ——
	-- ═══════════════════════════════════════
	-- 冲量起跳目标顶点高度(stud)；↑ 每跳更高、滞空更长
	RUNWAY_JUMP_APEX_STUDS = 15,
	-- 跑道默认有效重力比例；↓ 更飘、顶点更高
	RUNWAY_SESSION_EFFECTIVE_GRAVITY_SCALE = 0.15,
	-- 终局按住冲刺时重力比例；↓ 冲刺段更飘
	RUNWAY_FINAL_DASH_EFFECTIVE_GRAVITY_SCALE = 0.075,
	-- 摔滑 Slide 重力比例；↓ 摔滑更飘
	RUNWAY_SLIDE_EFFECTIVE_GRAVITY_SCALE = 1,
	-- 脚本贴地射线容差(stud)；↑ 更易判贴地
	RUNWAY_SCRIPTED_GROUNDED_MAX_DIST_ABOVE_BASELINE_STUDS = 0,

	-- ═══════════════════════════════════════
	-- —— ④ 终局冲刺 Dash ——
	-- ═══════════════════════════════════════
	-- 冲刺沿轴加速度；↑ 加速更快
	DASH_ACCEL = 10,
	-- 冲刺顶速；↑ 冲刺更快
	DASH_MAX_SPEED = 100,
	-- 冲刺燃料上限(s)；↑ 可冲更久
	DASH_FUEL_MAX = 2.5,
	-- 冲刺向上线加速度；↑ 抬头爬升更强
	DASH_UPWARD_ACCEL = 12,
	-- 冲刺最高竖直速度；↑ 可飞更高
	DASH_UPWARD_VY_MAX = 75,
	-- 松冲刺后额外沿轴速衰减率；↑ 松键收速更快
	FINAL_DASH_ALONG_EXTRA_DECEL_PER_SEC = 0.8,
	-- 终局基础俯仰(度)；↑ 身体更前倾
	RUNWAY_FINAL_PITCH_DEG = 60,
	-- 按住冲刺额外俯仰(度)；↑ 冲刺时更扎头
	RUNWAY_FINAL_DASH_EXTRA_PITCH_DEG = 50,

	-- ═══════════════════════════════════════
	-- —— ⑤ 终局落地（翻滚 + 趴滑）——
	-- ═══════════════════════════════════════

	-- 子阶段 A：相对 Workspace.Gravity 的有效重力比例（VectorForce；与起跳冲量公式对齐）
	RUNWAY_FINAL_LAND_PHASE_A_EFFECTIVE_GRAVITY_SCALE = 0.15,
	-- 子阶段 A：横滚角速度(rad/s)，带符号；为 0 时回退到旧 ROLL_PERIOD/T_pred 推导
	RUNWAY_FINAL_LAND_PHASE_A_ROLL_OMEGA_RAD_PER_SEC = -3,
	-- 子阶段 A：最多弹飞次数；达到后下次触地进趴滑
	RUNWAY_FINAL_LAND_PHASE_A_MAX_POP_COUNT = 4,
	-- 子阶段 A：触地沿轴速低于此值则进趴滑（不再弹飞）
	RUNWAY_FINAL_LAND_PHASE_A_MIN_ALONG_SPEED = 60,
	-- 子阶段 A：第 n 次弹飞沿轴速 = 触地沿轴 × retain^n（n=1 即首次落地已折减）
	RUNWAY_FINAL_LAND_PHASE_A_ALONG_RETAIN_PER_BOUNCE = 0.8,
	-- 子阶段 A：第 n 次弹飞竖直速 = |触地 vy| × retain^n
	RUNWAY_FINAL_LAND_PHASE_A_VY_RETAIN_PER_BOUNCE = 0.4,
	-- 子阶段 A：折减后竖直弹起初速下限（studs/s）
	RUNWAY_FINAL_LAND_PHASE_A_MIN_POP_VY = 10,
	-- 终局落地触地检测：脚下射线距离阈值（stud）；实际落地距离小于此值判定触地
	RUNWAY_FINAL_LAND_TOUCHDOWN_FEET_MAX_DIST_STUDS = 0,
	-- 子阶段 B：趴滑沿轴速度衰减指数（每帧 exp(-brakeK * dt)）；越大停得越快
	RUNWAY_FINAL_LAND_PRONE_SLIDE_BRAKE_EXP = 1.6,
	-- 子阶段 B：趴姿 HRP 相对地面下沉偏移（stud）；越大越贴地，负值则抬高
	RUNWAY_FINAL_LAND_PRONE_GROUND_OFFSET = 0.5,

	-- ═══════════════════════════════════════
	-- —— ⑥ 玩法摄像机 ——
	-- ═══════════════════════════════════════
	-- 玩法摄像机跟随平滑；↑ 跟得更紧
	RUNWAY_CAMERA_SMOOTH_SPEED = 3,
	-- 玩法摄像机 FOV；↑ 视野更广
	RUNWAY_CAMERA_FOV = 60,

	-- ═══════════════════════════════════════
	-- —— ⑦ 终局小精灵宝箱 ——
	-- ═══════════════════════════════════════
	-- 小精灵宝箱的配置 ID（对应 LittleElfChestData 中的 id）
	RUNWAY_CHEST_CONFIG_ID = 1,
	-- 宝箱生成在玩家前方多远（stud）
	RUNWAY_CHEST_SPAWN_AHEAD_STUDS = 3,
	-- 子阶段 B 结束前多少秒生成宝箱
	RUNWAY_CHEST_SPAWN_BEFORE_END_SEC = 4,
	-- 玩家撞击宝箱后向后反弹速度（studs/s）wdsa
	RUNWAY_CHEST_BOUNCE_BACK_SPEED = 12,
	-- 撞击后保持趴姿反弹时长，之后站立等待开箱动画（秒）
	RUNWAY_CHEST_BOUNCE_DELAY_SEC = 0.5,
	-- 开箱动画结束后、触发回城传送前的等待时长（秒）
	RUNWAY_CHEST_POST_OPEN_TELEPORT_DELAY_SEC = 0.5,
}

local jumpRunwayDesigner = GameConfig.JumpRunwayDesigner

GameConfig.JumpRunway = {
	-- —— 会话与诊断 ——
	-- 开发诊断：为 true 时客户端显示调试 HUD、服务端节流打印状态；发布务必保持 false（零额外 GUI/打印开销）
	DEBUG = true,
	N_TOTAL_JUMPS = jumpRunwayDesigner.N_TOTAL_JUMPS,
	RUN_START_COOLDOWN = 0.45,

	-- —— 起跳窗：时间窗、线重叠、预落地、窗内漂移 ——
	-- BeginLine / 链式起跳窗有效时长（秒）；略增可更早、更宽响应（与 PRELAND / OVERLAP_PADDING 配合）
	T_WINDOW = jumpRunwayDesigner.T_WINDOW,
	-- BeginLine 与角色重叠判定：相对线 Part 的 Size 各轴外扩（stud），薄板/高速时比纯 Touched 更早进入起跳窗
	BEGIN_LINE_OVERLAP_PADDING_STUDS = 1.0,
	-- 起跳窗内 deltaT/T_WINDOW：前 1/3 为 Perfect，至 2/3 为 Ok，之后为 Late
	JUMP_WINDOW_RATING_PERFECT_MAX_FRAC = jumpRunwayDesigner.JUMP_WINDOW_RATING_PERFECT_MAX_FRAC,
	JUMP_WINDOW_RATING_OK_MAX_FRAC = jumpRunwayDesigner.JUMP_WINDOW_RATING_OK_MAX_FRAC,
	-- 起跳窗/链式 HUD 武装距离带（仅几何，无 vy）：RaycastFeet 的 dist ≤ baseline + 本值；baseline 在 TryStartLocalRun 采样。未标定时退化为 dist ≤ 本值（绝对 stud）。
	-- IsRunwayPreLanding 另含 RUNWAY_PRELAND_MAX_VY，用于起跳输入等逻辑。
	RUNWAY_PRELAND_MAX_DIST_STUDS = 10,
	RUNWAY_PRELAND_MAX_VY = 4.0,
	-- 起跳窗内：脚本贴地后再过该秒数才切慢漂；此前沿轴脚本推速与当前段 min 对齐（速度连续）
	RUNWAY_JUMPWINDOW_DRIFT_DELAY_AFTER_TOUCH_SEC = 0.1,
	-- 起跳窗慢漂段：水平位移由 Humanoid.WalkSpeed + Move 驱动（与沿轴脚本推速解耦）；竖直仍由脚本同步
	JUMP_WINDOW_WALK_SPEED = jumpRunwayDesigner.JUMP_WINDOW_WALK_SPEED,

	-- —— 起跳窗评级 UI ——
	-- 起跳窗评级浮层：总时长约 2s（砸入 + 变色 + 淡出）
	JUMP_RUNWAY_RATING_UI_TOTAL_SEC = 2,
	JUMP_RUNWAY_RATING_IMPACT_SEC = 0.32,
	JUMP_RUNWAY_RATING_FADE_SEC = 0.18,
	JUMP_RUNWAY_RATING_IMPACT_START_SCALE = 3,
	JUMP_RUNWAY_RATING_TEXT_SIZE = 100,
	JUMP_RUNWAY_RATING_HUES_PER_SEC = 0.9,

	-- —— 状态判定阈值 ——
	V_EPSILON = 0.5,
	VERTICAL_EPSILON = 2.0,
	K_STABLE_FRAMES = 6,

	-- —— 沿轴水平速度：首段 AutoRun、段内 min/max、评级 bonus、空中插值 ——
	-- 第一次起跳前（takeoffCount==0 的 AutoRun）沿轴脚本推速
	FIRST_TAKEOFF_AUTORUN_SPEED = jumpRunwayDesigner.FIRST_TAKEOFF_AUTORUN_SPEED,
	-- 水平速度：每段 max = JUMP_SPEED_INITIAL_MAX + 累计起跳评级 bonus；min = max - JUMP_SPEED_MAX_TO_MIN_DELTA（固定差值）
	JUMP_SPEED_INITIAL_MAX = jumpRunwayDesigner.JUMP_SPEED_INITIAL_MAX,
	JUMP_SPEED_MAX_TO_MIN_DELTA = jumpRunwayDesigner.JUMP_SPEED_MAX_TO_MIN_DELTA,
	-- 与 ComputeJumpWindowRatingTier 一致：1=Perfect，2=Ok，3=Late；每次起跳（含线前首跳配置的 tier）累加对应 bonus
	JUMP_WINDOW_RATING_SPEED_BONUS_BY_TIER = jumpRunwayDesigner.JUMP_WINDOW_RATING_SPEED_BONUS_BY_TIER,
	-- AutoRun 且尚未触碰起跳线时起跳：速度 bonus 使用该 tier（默认 2=Ok）；浮层与之一致
	JUMP_FIRST_TAKEOFF_BEFORE_LINE_SPEED_RATING_TIER = 2,
	-- 插值曲线：目前仅实现 ease_out；其他值按线性回退
	JUMP_SPEED_LERP_CURVE = "ease_out",

	-- —— 起跳竖直、冲量与各阶段有效重力 ——
	-- 客户端冲量起跳：目标近似顶点高度（stud）；vy 使用有效重力 Workspace.Gravity * RUNWAY_SESSION_EFFECTIVE_GRAVITY_SCALE
	RUNWAY_JUMP_APEX_STUDS = jumpRunwayDesigner.RUNWAY_JUMP_APEX_STUDS,
	-- PreSimulation 内保护 vy 不被脚本水平速度覆盖抹掉的时长（秒）
	RUNWAY_JUMP_BOOST_HOLD_SEC = 0.28,
	-- 跑道整局相对 Workspace.Gravity 的有效比例（VectorForce 抵消部分重力；起跳冲量与此对齐）
	RUNWAY_SESSION_EFFECTIVE_GRAVITY_SCALE = jumpRunwayDesigner.RUNWAY_SESSION_EFFECTIVE_GRAVITY_SCALE,
	-- 第 N 跳空中、按住冲刺且燃料>0 时改用该比例；其余跑道阶段（含终局未冲刺）均用 RUNWAY_SESSION_EFFECTIVE_GRAVITY_SCALE
	RUNWAY_FINAL_DASH_EFFECTIVE_GRAVITY_SCALE = jumpRunwayDesigner.RUNWAY_FINAL_DASH_EFFECTIVE_GRAVITY_SCALE,
	-- 摔滑（Slide）阶段：1 表示 VectorForce 不抵消重力，与 Workspace.Gravity 一致；略小于 1 可保留轻微「月球感」
	RUNWAY_SLIDE_EFFECTIVE_GRAVITY_SCALE = jumpRunwayDesigner.RUNWAY_SLIDE_EFFECTIVE_GRAVITY_SCALE,

	-- —— 贴地探测与起点归位 ——
	-- 向下射线最大长度（stud），仅决定 RaycastFeet / 多点贴地能否命中，不作为「是否贴地」的距离阈值
	RUNWAY_GROUND_PROBE_DOWN = 15,
	RUNWAY_GROUND_RAY_ORIGIN_Y = 0.35,
	RUNWAY_GROUND_MIN_NORMAL_Y = 0.25,
	-- IsRunwayScriptedGrounded 射线分支：有 baseline 时 dist < baseline + 本值 视为脚射线贴地；与 RUNWAY_PRELAND_MAX_DIST_STUDS（起跳窗带）分离
	RUNWAY_SCRIPTED_GROUNDED_MAX_DIST_ABOVE_BASELINE_STUDS = jumpRunwayDesigner.RUNWAY_SCRIPTED_GROUNDED_MAX_DIST_ABOVE_BASELINE_STUDS,
	-- IsRunwayScriptedGrounded：FloorMaterial=Air 且脚射线未命中时，若已记录起跑 HRP 世界 Y，且 |当前 HRP.Y - 基准| ≤ 本值（且通过同函数内 vy<12），仍视为贴地。0 关闭仅走射线/状态机回退
	RUNWAY_SCRIPTED_GROUNDED_HRP_Y_DEVIATION_STUDS = 0.5,
	-- StartTrigger 未贴地归位：向下射线起点在 max(HRP.Y, 触发器.Y) 之上额外抬高（stud），避免 HRP 在触发器内时测不到地
	RUNWAY_START_TRIGGER_GROUND_SNAP_PROBE_EXTRA_Y = 1.0,
	-- StartTrigger：IsRunwayScriptedGrounded 为 true 时，仅当 RaycastFeet 距离 ≤ max(本下限, HipHeight*下系数+RUNWAY_GROUND_RAY_ORIGIN_Y) 才跳过垂直归位。起跳中空常被误判贴地；若此处跳过吸附，则即使用 TryStartLocalRun 延后采样，preLandRayBaselineStuds 仍会偏大
	RUNWAY_START_TRIGGER_SKIP_SNAP_HIP_HEIGHT_MULT = 2.25,
	RUNWAY_START_TRIGGER_SKIP_SNAP_MAX_FEET_DIST_STUDS = 4.25,

	-- —— 终局冲刺 Dash（燃料、水平/竖直加速、松键衰减）与俯仰 ——
	DASH_ACCEL = jumpRunwayDesigner.DASH_ACCEL,
	DASH_MAX_SPEED = jumpRunwayDesigner.DASH_MAX_SPEED,
	DASH_FUEL_MAX = jumpRunwayDesigner.DASH_FUEL_MAX,
	DASH_FUEL_DRAIN_PER_SEC = 1.0,
	-- 终局冲刺：除沿前向 DASH_ACCEL 外，每帧叠加向上线加速度（studs/s²）；vy 不超过 DASH_UPWARD_VY_MAX
	DASH_UPWARD_ACCEL = jumpRunwayDesigner.DASH_UPWARD_ACCEL,
	DASH_UPWARD_VY_MAX = jumpRunwayDesigner.DASH_UPWARD_VY_MAX,
	-- 终局：燃料用尽或松冲刺后，叠在水平基底上的 extra 沿轴速度按每帧 (1 - 该值 * dt) 衰减；越小收速越慢（原硬编码 4）
	FINAL_DASH_ALONG_EXTRA_DECEL_PER_SEC = jumpRunwayDesigner.FINAL_DASH_ALONG_EXTRA_DECEL_PER_SEC,
	-- 终局第 N 跳空中：相对跑道水平前向的基础俯仰（度）；按住冲刺且 fuel>0 时叠加 RUNWAY_FINAL_DASH_EXTRA_PITCH_DEG
	RUNWAY_FINAL_PITCH_DEG = jumpRunwayDesigner.RUNWAY_FINAL_PITCH_DEG,
	RUNWAY_FINAL_DASH_EXTRA_PITCH_DEG = jumpRunwayDesigner.RUNWAY_FINAL_DASH_EXTRA_PITCH_DEG,
	-- 俯仰绕局部 X 轴的符号：当前工程下 -1 为跑道前向「前倾」；若变成后仰则改为 1
	RUNWAY_FINAL_PITCH_AXIS_SIGN = -1,
	-- 终局俯仰：PostSimulation 内对目标朝向做指数平滑（越大越快贴目标）；硬贴易与物理/动画打架抽搐
	RUNWAY_FINAL_PITCH_SMOOTH_RATE = 18,
	-- 终局俯仰：对角速度按帧衰减（越大越快消旋）；0 表示仍每帧清零角速度
	RUNWAY_FINAL_PITCH_ANGULAR_DAMP_RATE = 14,

	-- —— 中途摔滑 Slide ——
	SLIDE_DURATION_SEC = 2.0,
	SLIDE_VERTICAL_DAMP = 0.92,

	-- —— 网络采样与防作弊（与 DASH_MAX_SPEED 等数值需一致考虑）——
	-- 客户端→服务端位置采样间隔（秒）；服务端用样本累加权威 maxAlong 并做防作弊检查
	CLIENT_SAMPLE_INTERVAL = 0.08,
	NOTIFY_INTERVAL = 0.12,
	-- 防作弊：允许的沿轴最大瞬时速度（水平投影，见客户端 sampleAlongSpeed）。
	-- 斜坡跑道时若用全量 v·forward 会把垂直速度折进「沿轴速度」，正常 Dash/起跳易被误杀；提高到 ~2×DASH_MAX + 余量。
	ANTI_CHEAT_MAX_ALONG_SPEED = 600,
	-- 防作弊：允许的偏离跑道轴的水平距离（远超此值视为越界/瞬移）。
	-- 起点触发器偏大、玩家从边缘切入时水平偏离常 >18；过严会导致首包起永久拒收、maxAlong 永远不涨。
	ANTI_CHEAT_MAX_PERP_DEVIATION = 48,
	-- 防作弊：单局沿轴成绩硬上限，避免序列化异常或外挂虚报
	ANTI_CHEAT_DISTANCE_HARD_CAP = 4000,
	-- 防作弊：单次样本相对上次「已接受」样本的最大沿轴正向位移余量（与 MAX_ALONG_SPEED 同步放宽）
	ANTI_CHEAT_MAX_DELTA_PER_SAMPLE = 36,

	-- —— 脚下跑道环 FX ——
	-- 脚下跑道环：为 false 时不克隆（无环 FX）
	RUNWAY_RING_ENABLED = true,
	-- 为 true 时克隆后再执行脚本生成的双圆环 SurfaceGui（会移除克隆体上已有 SurfaceGui）；默认 false 以保留 Models.JumpRunwayRing 模板实机层级
	RUNWAY_RING_SCRIPTED_SURFACE_UI = false,
	-- 脚下跑道环（客户端克隆 ReplicatedStorage.Models.JumpRunwayRing）：环中心相对地面命中点的世界 Y 抬升（stud）
	RUNWAY_RING_WORLD_Y_OFFSET = 0,
	-- 为缩放环取的地面高度：竖直向下射线最大长度（stud），需大于空中高度以免测不到地
	RUNWAY_RING_GROUND_RAY_MAX = 512,
	-- 离地高度每增加 1 stud，Size.X/Size.Z 相对模板放大系数（触地 alt≈0 时为原大小）
	RUNWAY_RING_SIZE_PER_STUD_ALT = 0.5,
	-- 仅当 RUNWAY_RING_SCRIPTED_SURFACE_UI 为 true 时由 SetupJumpRunwayRingSurfaceUi 使用
	RUNWAY_RING_UI_PIXELS_PER_STUD = 20,
	RUNWAY_RING_UI_TRACK_STROKE_PX = 15,
	RUNWAY_RING_UI_TRACK_COLOR = Color3.fromRGB(255, 255, 255),
	RUNWAY_RING_UI_FIXED_DIAMETER_PX = 120,
	RUNWAY_RING_UI_FIXED_STROKE_PX = 15,
	RUNWAY_RING_UI_FIXED_COLOR = Color3.fromRGB(255, 220, 80),

	-- —— 成绩条、占位背包与喷气背包模型 ——
	-- 终局 DistanceRecorder（ReplicatedStorage.Models.DistanceRecorder）：相对 HRP 水平朝向前移（stud），底部贴地
	RUNWAY_DISTANCE_RECORDER_FORWARD_STUDS = 1,
	-- 占位火箭背包：相对 UpperTorso（无则 Torso/HRP）局部偏移；+Z 为角色背后
	RUNWAY_ROCKET_BACKPACK_SIZE = Vector3.new(1.4, 1.6, 0.6),
	RUNWAY_ROCKET_BACKPACK_COLOR = Color3.fromRGB(180, 90, 50),
	RUNWAY_ROCKET_BACKPACK_OFFSET_X = 0,
	RUNWAY_ROCKET_BACKPACK_OFFSET_Y = 0.2,
	RUNWAY_ROCKET_BACKPACK_OFFSET_Z = 0.75,
	RUNWAY_ROCKET_BACKPACK_HRP_FALLBACK_OFFSET_X = 0,
	RUNWAY_ROCKET_BACKPACK_HRP_FALLBACK_OFFSET_Y = 0.3,
	RUNWAY_ROCKET_BACKPACK_HRP_FALLBACK_OFFSET_Z = 1.1,
	-- 火箭背包模型（ReplicatedStorage.Models.Jetpack）；为 false 时使用上方占位 Part
	RUNWAY_JETPACK_ENABLED = true,
	RUNWAY_JETPACK_OUTER_MODEL_NAME = "Jetpack",
	RUNWAY_JETPACK_INNER_MODEL_NAME = "Jetpack",
	RUNWAY_JETPACK_MIDDLE_NAME = "Middle",
	RUNWAY_JETPACK_FLAME1_NAME = "Flame1",
	RUNWAY_JETPACK_FLAME2_NAME = "Flame2",
	RUNWAY_JETPACK_FLAME_COLOR_INTERVAL_SEC = 0.5,
	RUNWAY_JETPACK_FLAME_COLOR_RED = Color3.fromRGB(255, 40, 40),
	RUNWAY_JETPACK_FLAME_COLOR_YELLOW = Color3.fromRGB(255, 220, 30),
	-- 为 true 时，终局冲刺粒子关闭时对每个 ParticleEmitter 调用 Clear() 立刻掐尾烟（默认 false）
	RUNWAY_JETPACK_DASH_PARTICLE_CLEAR_ON_IDLE = false,

	-- —— 终局落地：子阶段 A（弹飞 / 空中横滚；独立 PHASE_A_*；重力见 GetRunwayEffectiveGravityScale）——
	-- finalLanding：A 阶段贴地后立即进 B；B 开始时锁趴姿并直接切入沿轴滑行（跳过预落体 stage0）。下方 ROLL_* 仅当 PHASE_A_ROLL_OMEGA_RAD_PER_SEC==0 时用于横滚推导；T_pred 仍供旧 ω 与时间预估。
	RUNWAY_FINAL_LAND_TUMBLE_NO_POP_ROLL_SEC = 0.85,
	-- 横滚角速度：>0 时每圈周期固定为该秒数（omega=2π/period），与弹道 T_pred 解耦；为 0 时用 T_pred 经 RUNWAY_FINAL_LAND_TUMBLE_ROLL_T_REF_* clamp 后算 omega
	RUNWAY_FINAL_LAND_TUMBLE_ROLL_PERIOD_SEC = 0,
	-- 当 ROLL_PERIOD_SEC<=0：T_ref = clamp(T_pred, MIN, MAX)，omega = 2π/T_ref * OMEGA_SCALE；MAX 过小会加快翻滚（缓解大 POP_APEX 导致一圈过慢）
	RUNWAY_FINAL_LAND_TUMBLE_ROLL_T_REF_MIN_SEC = 0.12,
	RUNWAY_FINAL_LAND_TUMBLE_ROLL_T_REF_MAX_SEC = 4,
	RUNWAY_FINAL_LAND_TUMBLE_ROLL_OMEGA_SCALE = 1,
	-- 横滚绕世界侧轴旋转的符号：1 或 -1，与跑道朝向配合；反向时改为相反数
	RUNWAY_FINAL_LAND_TUMBLE_ROLL_SIGN = -1,
	-- 子阶段 A 独立弹跳/重力/横滚 ω / 沿轴（部分项仅在 JumpRunway 表维护，已从 JumpRunwayDesigner 策划表移除）
	RUNWAY_FINAL_LAND_PHASE_A_EFFECTIVE_GRAVITY_SCALE = jumpRunwayDesigner.RUNWAY_FINAL_LAND_PHASE_A_EFFECTIVE_GRAVITY_SCALE,
	RUNWAY_FINAL_LAND_PHASE_A_ROLL_OMEGA_RAD_PER_SEC = jumpRunwayDesigner.RUNWAY_FINAL_LAND_PHASE_A_ROLL_OMEGA_RAD_PER_SEC,
	RUNWAY_FINAL_LAND_PHASE_A_MAX_POP_COUNT = jumpRunwayDesigner.RUNWAY_FINAL_LAND_PHASE_A_MAX_POP_COUNT,
	RUNWAY_FINAL_LAND_PHASE_A_MIN_ALONG_SPEED = jumpRunwayDesigner.RUNWAY_FINAL_LAND_PHASE_A_MIN_ALONG_SPEED,
	RUNWAY_FINAL_LAND_PHASE_A_ALONG_RETAIN_PER_BOUNCE = jumpRunwayDesigner.RUNWAY_FINAL_LAND_PHASE_A_ALONG_RETAIN_PER_BOUNCE,
	RUNWAY_FINAL_LAND_PHASE_A_VY_RETAIN_PER_BOUNCE = jumpRunwayDesigner.RUNWAY_FINAL_LAND_PHASE_A_VY_RETAIN_PER_BOUNCE,
	RUNWAY_FINAL_LAND_PHASE_A_MIN_POP_VY = jumpRunwayDesigner.RUNWAY_FINAL_LAND_PHASE_A_MIN_POP_VY,
	RUNWAY_FINAL_LAND_PHASE_A_TOUCHDOWN_SCRIPT_MAX_VY = -6,
	RUNWAY_FINAL_LAND_PHASE_A_TOUCHDOWN_FULLBODY_MAX_ABS_VY = 85,
	RUNWAY_FINAL_LAND_PHASE_A_TOUCHDOWN_FEET_MAX_ABOVE_BASELINE_STUDS = 0,
	RUNWAY_FINAL_LAND_PHASE_A_TOUCHDOWN_FEET_FALLBACK_MAX_DIST_STUDS = 4,
	-- 终局翻滚：为 true 时 A 阶段脚本水平速仅保留沿跑道前向（侧向清零）；为 false 时首帧侧向乘 0.35 后按帧衰减
	RUNWAY_FINAL_LAND_TUMBLE_ZERO_PERP = true,
	-- 终局 A：多点贴地（相对 HRP 局部偏移向下 Raycast）；每点须命中且命中距离 ≤ 该值（stud）才算「全身贴地」，避免水平姿态下单点误触地
	RUNWAY_FINAL_LAND_FULL_BODY_GROUND_MAX_DIST_STUDS = 1.35,
	-- 终局落地触地检测：脚下射线距离阈值（stud），独立于 RUNWAY_SCRIPTED_GROUNDED_MAX_DIST_ABOVE_BASELINE_STUDS
	RUNWAY_FINAL_LAND_TOUCHDOWN_FEET_MAX_DIST_STUDS = jumpRunwayDesigner.RUNWAY_FINAL_LAND_TOUCHDOWN_FEET_MAX_DIST_STUDS,

	-- 子阶段 B 滑行速度衰减指数（每帧 exp(-brakeK * dt)）
	RUNWAY_FINAL_LAND_PRONE_SLIDE_BRAKE_EXP = jumpRunwayDesigner.RUNWAY_FINAL_LAND_PRONE_SLIDE_BRAKE_EXP,
	-- 子阶段 B 趴姿 HRP 相对地面下沉偏移（stud）
	RUNWAY_FINAL_LAND_PRONE_GROUND_OFFSET = jumpRunwayDesigner.RUNWAY_FINAL_LAND_PRONE_GROUND_OFFSET,

	-- 终局趴滑（子阶段 B）地面滑行痕迹：客户端克隆 ReplicatedStorage.Models.SlideTracePart（长方 Part，长边沿 Size.X 对齐跑道方向；内嵌 SurfaceGui 等 UI）。模板仅存在于 Studio 同步资源，仓库不存实例。
	RUNWAY_SLIDE_TRACE_ENABLED = true,
	RUNWAY_SLIDE_TRACE_MAX_SEC = 5,
	-- 沿跑道累积位移达到 「本比例 × SlideTracePart.Size.X」 时在地面落一段锚定拷贝（保证连续）
	RUNWAY_SLIDE_TRACE_STAMP_AT_ALONG_FRAC = 0.75,
	RUNWAY_SLIDE_TRACE_MAX_SEGMENTS = 64,
	-- 贴地点沿地法线抬高，减轻与地面 Z-fight
	RUNWAY_SLIDE_TRACE_GROUND_NORMAL_LIFT_STUDS = 0.035,
	-- 痕迹中心相对 HRP 在贴地前向轴上的偏移（studs；负值偏后）
	RUNWAY_SLIDE_TRACE_HRP_ALONG_OFFSET_STUDS = 0,

	-- —— 玩法摄像机 ——
	-- 跑道摄像机：玩法期间客户端 Scriptable 插值跟随，仅影响本地表现
	RUNWAY_CAMERA_BACK_OFFSET = 20,
	RUNWAY_CAMERA_RIGHT_OFFSET = 10,
	RUNWAY_CAMERA_HEIGHT_OFFSET = 8,
	RUNWAY_CAMERA_LOOK_AHEAD = 10,
	RUNWAY_CAMERA_LOOK_HEIGHT = 0,
	RUNWAY_CAMERA_SMOOTH_SPEED = jumpRunwayDesigner.RUNWAY_CAMERA_SMOOTH_SPEED,
	RUNWAY_CAMERA_FOV = jumpRunwayDesigner.RUNWAY_CAMERA_FOV,

	-- —— 终局小精灵宝箱 ——
	RUNWAY_CHEST_CONFIG_ID = jumpRunwayDesigner.RUNWAY_CHEST_CONFIG_ID,
	RUNWAY_CHEST_SPAWN_AHEAD_STUDS = jumpRunwayDesigner.RUNWAY_CHEST_SPAWN_AHEAD_STUDS,
	RUNWAY_CHEST_SPAWN_BEFORE_END_SEC = jumpRunwayDesigner.RUNWAY_CHEST_SPAWN_BEFORE_END_SEC,
	RUNWAY_CHEST_BOUNCE_BACK_SPEED = jumpRunwayDesigner.RUNWAY_CHEST_BOUNCE_BACK_SPEED,
	RUNWAY_CHEST_BOUNCE_DELAY_SEC = jumpRunwayDesigner.RUNWAY_CHEST_BOUNCE_DELAY_SEC,
	RUNWAY_CHEST_POST_OPEN_TELEPORT_DELAY_SEC = jumpRunwayDesigner.RUNWAY_CHEST_POST_OPEN_TELEPORT_DELAY_SEC,
}

--- 跑道单段跳跃水平限速：max = JUMP_SPEED_INITIAL_MAX + cumulativeRatingBonus（clamp 至 ANTI_CHEAT_MAX_ALONG_SPEED）；min = max - JUMP_SPEED_MAX_TO_MIN_DELTA。
--- segmentIndex 保留供调用方语义对齐（第 k 段对应 takeoffCount==k），当前与 max/min 数值无关。
function GameConfig.GetJumpRunwayJumpSpeedLimitsForSegment(_segmentIndex: number, cumulativeRatingBonus: number): (number, number)
	local jr = GameConfig.JumpRunway
	local initial = jr.JUMP_SPEED_INITIAL_MAX
	if typeof(initial) ~= "number" or initial ~= initial then
		initial = 0
	end
	local delta = jr.JUMP_SPEED_MAX_TO_MIN_DELTA
	if typeof(delta) ~= "number" or delta ~= delta then
		delta = 0
	end
	delta = math.max(0, delta)
	local bonus = cumulativeRatingBonus
	if typeof(bonus) ~= "number" or bonus ~= bonus then
		bonus = 0
	end
	bonus = math.max(0, bonus)
	local maxSpd = initial + bonus
	local cap = jr.ANTI_CHEAT_MAX_ALONG_SPEED
	if typeof(cap) == "number" and cap == cap and cap > 0 then
		maxSpd = math.min(maxSpd, cap)
	end
	local minSpd = math.max(0, maxSpd - delta)
	return maxSpd, minSpd
end

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
