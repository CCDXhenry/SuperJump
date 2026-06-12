--!strict
-- 工厂玩法已完全移除：ChestWorkbench / Island / 铺砖/地震等表已删除。
local GameConfig = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local DateTimeExtension = require(coreSharedScripts:FindFirstChild("DateTimeExtension"))
local BrainrotDataModule = require(script:WaitForChild("BrainrotData"))
local BrainrotVariantDataModule = require(script:WaitForChild("BrainrotVariantData"))
local LittleElfChestDataModule = require(script:WaitForChild("LittleElfChestData"))
local LittleElfChestRewardPoolDataModule = require(script:WaitForChild("LittleElfChestRewardPoolData"))
local UpgradeShopRawData = require(script:WaitForChild("UpgradeShopData"))
local ExEquipDataModule = require(script:WaitForChild("ExEquipData"))
local ExStatsDataModule = require(script:WaitForChild("ExStatsData"))
local JetpackDataModule = require(script:WaitForChild("JetpackData"))
local MonsterDataModule = require(script:WaitForChild("MonsterData"))
local RebirthDataModule = require(script:WaitForChild("RebirthData"))
local BuffDataModule = require(script:WaitForChild("BuffData"))
local ShopBundleConfigurationDataModule = require(script:WaitForChild("ShopBundleConfigurationData"))
local ShopBundleDataModule = require(script:WaitForChild("ShopBundleData"))

GameConfig.GameVersion = "1.0.0"
GameConfig.ABTestVersion = "1.0.0"
GameConfig.PlayerSaveInfoDataVersion = 1
GameConfig.GameId = 10269142148

if game.GameId == GameConfig.GameId then
	GameConfig.GamePlaceId = 112238403443830
	GameConfig.ClearDataStorePlaceId = 100721633507021
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
	TutorialBrainrotPlaceSlot = 5,
	TutorialBrainrotIslandTeleport = 6,
	TutorialBrainrotCollect = 7,
	TutorialBrainrotUpgrade = 8,
	TutorialWalkSpeedUpgrade = 9,
	TutorialStartTrigger = 10,
	TutorialBeginLineJump = 11,
	TutorialLandingJump = 12,
	TutorialJetpackBuy = 13,
	TutorialFinalDash = 14,
	TutorialExEquipBuy = 15,
	TutorialExEquipUse = 16,
	TutorialJetpackRunwayRetry = 17,
	TutorialJumpPowerRunwayRetry = 18,
}

GameConfig.GuideStepKey = {
	BrainrotPlaceFinished = "BrainrotPlaceFinished",
	BrainrotCollectFinished = "BrainrotCollectFinished",
	BrainrotUpgradeFinished = "BrainrotUpgradeFinished",
	ChaserKillExperienced = "ChaserKillExperienced",
	WalkSpeedUpgradeFinished = "WalkSpeedUpgradeFinished",
	StartTriggerFinished = "StartTriggerFinished",
	BeginLineJumpFinished = "BeginLineJumpFinished",
	LandingJumpFinished = "LandingJumpFinished",
	JetpackBuyFinished = "JetpackBuyFinished",
	JetpackRunwayRetryFinished = "JetpackRunwayRetryFinished",
	FinalDashFinished = "FinalDashFinished",
	ExEquipBuyFinished = "ExEquipBuyFinished",
	ExEquipUseFinished = "ExEquipUseFinished",
	JumpPowerRunwayRetryFinished = "JumpPowerRunwayRetryFinished",
}

GameConfig.GuideTargetJetpackId = 1
GameConfig.GuideTargetExEquipId = 1
-- 升级速度引导：最远跳跃距离需超过该值（与跑道 HUD 同 stud 语义，显示后缀 m）
GameConfig.GuideWalkSpeedUpgradeMinBestDistance = 300
-- 商城引导：与目标商城距离超过该值时，先引导点击 Lobby TeleShopButton 传送
GameConfig.GuideShopTeleportDistanceThreshold = 100

-- 工厂玩法停用
-- GameConfig.GuideWorldAnchorName = {
-- 	Workbench = "Workbench",
-- }

GameConfig.GuideTextKeyMap = {
	[GameConfig.GuideType.TutorialBrainrotPickup] = "GuideTutorialBrainrotPickup",
	[GameConfig.GuideType.TutorialBrainrotPlace] = "GuideTutorialBrainrotPlace",
	[GameConfig.GuideType.TutorialBrainrotPlaceSlot] = "GuideTutorialBrainrotPlaceSlot",
	[GameConfig.GuideType.TutorialBrainrotIslandTeleport] = "GuideTutorialBrainrotIslandTeleport",
	[GameConfig.GuideType.TutorialBrainrotCollect] = "GuideTutorialBrainrotCollect",
	[GameConfig.GuideType.TutorialBrainrotUpgrade] = "GuideTutorialBrainrotUpgrade",
	[GameConfig.GuideType.TutorialWalkSpeedUpgrade] = "GuideTutorialWalkSpeedUpgrade",
	[GameConfig.GuideType.TutorialStartTrigger] = "GuideTutorialStartTrigger",
	[GameConfig.GuideType.TutorialBeginLineJump] = "GuideTutorialBeginLineJump",
	[GameConfig.GuideType.TutorialLandingJump] = "GuideTutorialLandingJump",
	[GameConfig.GuideType.TutorialJetpackBuy] = "GuideTutorialJetpackBuy",
	[GameConfig.GuideType.TutorialFinalDash] = "GuideTutorialFinalDash",
	[GameConfig.GuideType.TutorialExEquipBuy] = "GuideTutorialExEquipBuy",
	[GameConfig.GuideType.TutorialExEquipUse] = "GuideTutorialExEquipUse",
	[GameConfig.GuideType.TutorialJetpackRunwayRetry] = "GuideTutorialJetpackRunwayRetry",
	[GameConfig.GuideType.TutorialJumpPowerRunwayRetry] = "GuideTutorialJumpPowerRunwayRetry",
}

GameConfig.GuideAssetName = {
	UiFrame = "GuideFrame",
	ModelArrow = "GuideArrow",
}

GameConfig.GuideArrowYOffset = 4
GameConfig.GuidePlacementBoothPath = {
	BoothFolderName = "Booth",
	BoothModelName = "BoothModel",
	CollectPartName = "CollectPart",
	UpgradePartName = "UpgradePart",
}

GameConfig.SixcubeGroupId = 33977495

export type GroupRewardBrainrotConfig = {
	brainrotId: number,
	variantId: number,
}

GameConfig.GroupRewardBrainrot = {
	brainrotId = 10,
	variantId = 3,
} :: GroupRewardBrainrotConfig

function GameConfig.GetGroupRewardBrainrotConfig(): GroupRewardBrainrotConfig
	return GameConfig.GroupRewardBrainrot
end

export type RewardInfo = {
	id: number?,
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
	LittleElfChest = 4,
	Buff = 5,
	Jetpack = 6,
}

GameConfig.CurrencyType = {
	Coin = 1,
}

GameConfig.CostType = {
	Coin = 1,
	Rb = 2,
	CoinOrRb = 3,
	GroupReward = 4,
	StorePurchase = 5,
}

GameConfig.SkillType = {
	WalkSpeed = 1,
	HomeLevel = 2,
	RebirthLevel = 3,
	JumpPower = 6,
}

export type ShopAbilityInfo = {
	abilityName: string,
	shopKey: string,
	levelField: string,
}

GameConfig.ShopAbilityByType = {} :: { [number]: ShopAbilityInfo }
GameConfig.ShopAbilityByType[GameConfig.SkillType.WalkSpeed] = {
	abilityName = "WalkSpeed",
	shopKey = "WalkSpeed",
	levelField = "walkSpeedLevel",
}

GameConfig.ExEquipType = {
	Treadmill = 1,
	Bike = 2,
	Bike2 = 3,
	Bike3 = 4,
}

GameConfig.ExStatsType = {
	JumpPower = 1,
}

GameConfig.JetpackType = {
	Basic = 1,
}

GameConfig.ItemType = {
	Brainrot = 1,
	Coil = 2,
	LittleElfChest = 3,
	ExEquip = 4,
	Jetpack = 5,
}

GameConfig.BuffType = {
	ExerciseEfficiency = 1,
	CoinEfficiency = 2,
}

GameConfig.BuffMethod = {
	Multiplier = 1,
	ExtraValue = 2,
}

GameConfig.ModelGetSource = {
	Island = 1,
	LittleElfChest = 2,
	Shop = 3,
	PlayerGift = 4,
}

GameConfig.EnablePlayerGift = true
GameConfig.PlayerRespawnTime = 1

-- 排行榜
GameConfig.LeaderboardCategory = {
	WeeklyDistance = "WeeklyDistance",
}
GameConfig.LeaderboardUpdateInterval = 10 * 60
GameConfig.LeaderboardDisplayCount = 20
GameConfig.LeaderboardWeekStartUnixUtc = 1780617600 -- 2025-01-07 05:00:00 UTC (Tuesday 00:00 EST, fixed UTC-5)
GameConfig.LeaderboardWeekDurationSeconds = 7 * 24 * 60 * 60
GameConfig.LeaderboardDataVersion = "v1"

-- 无操作自动重连当前服务器
GameConfig.IdleWarnSec = 14 * 60 --开始提示“即将重连”
GameConfig.IdleTeleportSec = 15 * 60 --无操作多久后触发重连
GameConfig.IdleTeleportCooldownSec = 20 --两次重连请求/执行之间的最短间隔

-- Lobby 传送（Home / Shop）落地后角色与摄像机朝向
GameConfig.LobbyTeleportFacingDirection = Vector3.new(-1, 0, 0)

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
	GainFromOfflineReward = 1006,
	SpendOnUpgradeBrainrot = 2001,
	SpendOnUpgradeHome = 2002,
	SpendOnUpgradeWalkSpeed = 2003,
	SpendOnUpgradeJetpackFuel = 2004,
	SpendOnUpgradeJetpackThrust = 2005,
}

-- 离线奖励
export type OfflineRewardsConfig = {
	MinOfflineSeconds: number,
	MaxOfflineSeconds: number,
	BaseRewardMultiplier: number,
	PaidReceiveMultiplier: number,
	PaidReceiveProductId: number,
}

GameConfig.OfflineRewards = {
	MinOfflineSeconds = 300, -- 最短离线时长(秒)，低于此不弹窗
	MaxOfflineSeconds = 3 * 60 * 60, -- 离线累计上限(秒)，最多按3小时计
	BaseRewardMultiplier = 1 / 3, -- 基础金币奖励倍率（相对家园每秒产出×离线时长）
	PaidReceiveMultiplier = 10, -- 付费领取倍率（相对基础奖励）
	PaidReceiveProductId = 3602750413, -- 付费领取 Developer Product ID
} :: OfflineRewardsConfig

export type OfflineRewardInfo = {
	offlineSeconds: number,
	rewardPerSecond: number,
	baseReward: number,
	paidReward: number,
	paidReceiveMultiplier: number,
	paidReceiveProductId: number,
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

export type RebirthData = {
	id: number,
	count: number,
	collectMultiple: number,
	jumppowerLv: number,
}

GameConfig.Rebirth = {} :: { RebirthData }
GameConfig.RebirthMap = {} :: { [number]: RebirthData }

for _, rawData in pairs(RebirthDataModule) do
	local rebirthData: RebirthData = {
		id = rawData.id,
		count = rawData.count,
		collectMultiple = rawData.collectMultiple,
		jumppowerLv = rawData.jumppowerLv,
	}
	GameConfig.RebirthMap[rebirthData.id] = rebirthData
	table.insert(GameConfig.Rebirth, rebirthData)
end
table.sort(GameConfig.Rebirth, function(a, b)
	return a.id < b.id
end)

function GameConfig.GetBrainrotAbility(baseAbility: number, level: number): number
	local linear = level + baseAbility - 1
	local expo = math.ceil(baseAbility * (1.2 ^ (level - 1)))
	return math.max(linear, expo)
end

export type BrainrotVariantConfigData = {
	id: number,
	coinBonusPercent: number,
	resourceName: string,
	name_t: string,
}

function GameConfig.GetBrainrotVariant(variantId: number?): BrainrotVariantConfigData?
	if variantId == nil or variantId <= 0 then
		return nil
	end
	return GameConfig.BrainrotVariantIdMap[variantId]
end

function GameConfig.GetBrainrotAbilityWithVariant(baseAbility: number, level: number, variantId: number?): number
	local ability = GameConfig.GetBrainrotAbility(baseAbility, level)
	local variant = GameConfig.GetBrainrotVariant(variantId)
	if variant == nil then
		return ability
	end
	return math.ceil(ability * (1 + variant.coinBonusPercent / 100))
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
	variantId: number?,
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

GameConfig.BrainrotVariants = BrainrotVariantDataModule
GameConfig.BrainrotVariantIdMap = {} :: { [number]: BrainrotVariantConfigData }
for _, variantRow in pairs(BrainrotVariantDataModule) do
	if type(variantRow) == "table" and variantRow.id ~= nil then
		local variantCfg = variantRow :: BrainrotVariantConfigData
		GameConfig.BrainrotVariantIdMap[variantCfg.id] = variantCfg
	end
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

export type LittleElfChestConfigData = {
	id: number,
	resourceName: string,
	iconImageId: string,
	name_t: string,
	quality: number,
	distance: number,
	onlyPay: number?,
}

export type LittleElfChestData = LittleElfChestConfigData

-- 独立数据：小精灵宝箱（JumpRunway 终局奖励用）
GameConfig.LittleElfChests = LittleElfChestDataModule
GameConfig.LittleElfChestIdMap = {} :: { [number]: LittleElfChestConfigData }
GameConfig.LittleElfChestNameMap = {} :: { [string]: LittleElfChestConfigData }

for leChestKey, leChestRow in pairs(LittleElfChestDataModule) do
	if type(leChestKey) == "number" and leChestRow and type(leChestRow) == "table" then
		local cfg = leChestRow :: LittleElfChestConfigData
		GameConfig.LittleElfChestIdMap[cfg.id] = cfg
		GameConfig.LittleElfChestNameMap[cfg.resourceName] = cfg
	end
end

GameConfig.LittleElfChestRewardPoolMap = {} :: { [number]: { LittleElfChestRewardPoolEntry } }
for _, poolRow in pairs(LittleElfChestRewardPoolDataModule) do
	local entry = poolRow :: LittleElfChestRewardPoolEntry
	local chestTier = entry.id
	if not GameConfig.LittleElfChestRewardPoolMap[chestTier] then
		GameConfig.LittleElfChestRewardPoolMap[chestTier] = {}
	end
	table.insert(GameConfig.LittleElfChestRewardPoolMap[chestTier], entry)
end
GameConfig.ChestRewardPoolMap = GameConfig.LittleElfChestRewardPoolMap

export type LittleElfChestRewardPoolEntry = {
	id: number,
	itemType: number,
	itemId: number,
	weight: number,
	variantList: { number }?,
	variantWeight: { [number]: number }?,
}

function GameConfig.FindLittleElfChestRewardEntry(chestConfigId: number, brainrotId: number): LittleElfChestRewardPoolEntry?
	local rewardPool = GameConfig.LittleElfChestRewardPoolMap[chestConfigId]
	if rewardPool == nil then
		return nil
	end
	for _, entry in ipairs(rewardPool) do
		if entry.itemId == brainrotId then
			return entry
		end
	end
	return nil
end

function GameConfig.IsLittleElfChestAvailableForJumpRunway(chestConfig: LittleElfChestConfigData?): boolean
	return chestConfig ~= nil and chestConfig.onlyPay ~= 1
end

function GameConfig.RollVariantIdFromEntry(entry: LittleElfChestRewardPoolEntry): number
	local variantList = entry.variantList
	if variantList == nil or #variantList == 0 then
		return 0
	end
	local variantWeight = entry.variantWeight
	local totalWeight = 0
	for i = 1, #variantList do
		local w = if variantWeight then variantWeight[i] or 0 else 1
		if w > 0 then
			totalWeight += w
		end
	end
	if totalWeight <= 0 then
		return variantList[1]
	end
	local roll = math.random(1, totalWeight)
	local cumulative = 0
	for i = 1, #variantList do
		local w = if variantWeight then variantWeight[i] or 0 else 1
		if w > 0 then
			cumulative += w
			if roll <= cumulative then
				return variantList[i]
			end
		end
	end
	return variantList[1]
end

export type LittleElfChestRewardPoolData = LittleElfChestRewardPoolEntry

export type BuffData = {
	id: number,
	buffType: number,
	buffMethod: number,
	buffValue: number,
	name_t: string,
	describe_t: string,
	iconImageId: string,
}

export type BuffInfo = {
	ownedBuffMap: { [string]: boolean },
}

GameConfig.Buffs = BuffDataModule
GameConfig.BuffIdMap = {} :: { [number]: BuffData }
for _, buffRow in pairs(BuffDataModule) do
	if type(buffRow) == "table" and type(buffRow.id) == "number" then
		local buffData = buffRow :: BuffData
		GameConfig.BuffIdMap[buffData.id] = buffData
	end
end

function GameConfig.CreateDefaultBuffInfo(): BuffInfo
	return {
		ownedBuffMap = {},
	}
end

function GameConfig.GetBuffMultiplier(buffInfo: BuffInfo?, buffType: number): number
	if buffInfo == nil then
		return 1
	end
	local multiplier = 1
	for buffIdKey, owned in pairs(buffInfo.ownedBuffMap) do
		if owned ~= true then
			continue
		end
		local buffId = tonumber(buffIdKey)
		if buffId == nil then
			continue
		end
		local buffData = GameConfig.BuffIdMap[buffId]
		if buffData ~= nil and buffData.buffType == buffType and buffData.buffMethod == GameConfig.BuffMethod.Multiplier then
			multiplier *= math.max(buffData.buffValue, 1)
		end
	end
	return multiplier
end

export type ExEquipData = {
	id: number,
	resourceName: string,
	iconImageId: string,
	name_t: string,
	costCoin: number,
	productId: number,
	costRb: number,
	ability: number,
	costType: number,
	quality: number,
	type: number,
}

export type ExEquipInventory = {
	currentId: string,
	ownedList: { [string]: boolean },
}

GameConfig.ExEquipDataMap = {} :: { [number]: ExEquipData }
for _, data in ExEquipDataModule do
	GameConfig.ExEquipDataMap[data.id] = data :: ExEquipData
end

export type ExStatsData = {
	type: number,
	exp: number,
	ability: number,
	lv: number,
	name_t: string,
}

export type JumpPowerInfo = {
	type: number,
	lv: number,
	exp: number,
}

GameConfig.ExStats = ExStatsDataModule
GameConfig.ExStatsDataByTypeLvMap = {} :: { [number]: { [number]: ExStatsData } }
for _, data in ExStatsDataModule do
	local exStatsData = data :: ExStatsData
	if GameConfig.ExStatsDataByTypeLvMap[exStatsData.type] == nil then
		GameConfig.ExStatsDataByTypeLvMap[exStatsData.type] = {}
	end
	GameConfig.ExStatsDataByTypeLvMap[exStatsData.type][exStatsData.lv] = exStatsData
end

function GameConfig.CreateDefaultJumpPowerInfo(): JumpPowerInfo
	return {
		type = GameConfig.ExStatsType.JumpPower,
		lv = 1,
		exp = 0,
	}
end

function GameConfig.GetJumpPowerStatsData(jumpPowerInfo: JumpPowerInfo): ExStatsData?
	local statsMap = GameConfig.ExStatsDataByTypeLvMap[jumpPowerInfo.type]
	if statsMap == nil then
		return nil
	end
	return statsMap[jumpPowerInfo.lv]
end

function GameConfig.GetJumpPowerAbility(jumpPowerInfo: JumpPowerInfo): number
	local statsData = GameConfig.GetJumpPowerStatsData(jumpPowerInfo)
	return if statsData ~= nil then statsData.ability else GameConfig.JumpPowerDefaultValue
end

function GameConfig.GetJumpPowerRequiredExp(jumpPowerInfo: JumpPowerInfo): number
	local statsData = GameConfig.GetJumpPowerStatsData(jumpPowerInfo)
	return if statsData ~= nil then statsData.exp else 0
end

export type JetpackData = {
	id: number,
	resourceName: string,
	iconImageId: string,
	name_t: string,
	costCoin: number,
	productId: number,
	costRb: number,
	fuel: number,
	thrust: number,
	costType: number,
	quality: number,
}

export type JetpackInventory = {
	currentId: string,
	ownedList: { [string]: boolean },
}

GameConfig.JetpackDataMap = {} :: { [number]: JetpackData }
for _, data in JetpackDataModule do
	GameConfig.JetpackDataMap[data.id] = data :: JetpackData
end

function GameConfig.GetJetpackThrustPercent(jetpackData: JetpackData?): number
	if jetpackData == nil then
		return 100
	end
	local thrustValue = jetpackData.thrust
	if typeof(thrustValue) ~= "number" or thrustValue ~= thrustValue then
		return 100
	end
	return math.max(0, thrustValue)
end

export type MonsterData = {
	id: number,
	resourceName: string,
	distance: number,
	name_t: string,
	moveSpeed: number,
}

GameConfig.Monsters = MonsterDataModule
GameConfig.MonsterIdMap = {} :: { [number]: MonsterData }
GameConfig.MonsterDistanceList = {} :: { MonsterData }

for _, data in pairs(MonsterDataModule) do
	if type(data) == "table" and type(data.id) == "number" then
		local cfgData = data :: MonsterData
		GameConfig.MonsterIdMap[cfgData.id] = cfgData
		table.insert(GameConfig.MonsterDistanceList, cfgData)
	end
end
table.sort(GameConfig.MonsterDistanceList, function(a: MonsterData, b: MonsterData): boolean
	return a.distance < b.distance
end)

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
-- Brainrot 模型缩放：每升 1 级在当前尺寸上复利增加的百分比（1 表示每级 ×1.01）
GameConfig.BrainrotLevelScalePercentPerLevel = 1
-- VisualModel 上缓存 Models 目录模板原始 GetScale()，避免等级缩放覆盖资源初始大小
GameConfig.BrainrotTemplateBaseScaleAttributeName = "BrainrotTemplateBaseScale"

function GameConfig.GetBrainrotModelScale(level: number): number
	local safeLevel = math.max(1, math.floor(level))
	local perLevelMultiplier = 1 + GameConfig.BrainrotLevelScalePercentPerLevel / 100
	return perLevelMultiplier ^ (safeLevel - 1)
end

-- 读取 Models/Brainrots 中模板在目录里配置的原始缩放（Model:GetScale）
function GameConfig.GetBrainrotTemplateBaseScale(template: Instance): number
	if template:IsA("Model") then
		local templateScale = template:GetScale()
		if templateScale > 0 then
			return templateScale
		end
	end
	return 1
end

function GameConfig.ApplyBrainrotModelScale(model: Model, level: number, templateBaseScale: number?)
	local baseScale: number
	if templateBaseScale ~= nil then
		baseScale = templateBaseScale
	else
		local stored = model:GetAttribute(GameConfig.BrainrotTemplateBaseScaleAttributeName)
		if typeof(stored) == "number" and stored > 0 then
			baseScale = stored
		else
			baseScale = model:GetScale()
			if baseScale <= 0 then
				baseScale = 1
			end
		end
	end
	model:SetAttribute(GameConfig.BrainrotTemplateBaseScaleAttributeName, baseScale)
	model:ScaleTo(baseScale * GameConfig.GetBrainrotModelScale(level))
end

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
	RebirthProductId = 3602583476,
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
	T_WINDOW = 1.5,
	-- 起跳输入最小间隔(s)；↑ 更防连点误触，↓ 响应更快
	JUMP_INPUT_COOLDOWN_SEC = 0.5,
	-- 窗内 Perfect 时间占比上限；↑ Perfect 窗口更宽
	JUMP_WINDOW_RATING_PERFECT_MAX_FRAC = 2 / 3,
	-- 窗内 Ok 时间占比上限；↑ Ok 窗口更宽
	JUMP_WINDOW_RATING_OK_MAX_FRAC = 4 / 5,
	-- BeginLine 前固定 Perfect 距离（stud）；距起跳线 ≤ 此值时线前起跳直接 Perfect
	RUNWAY_BEGIN_LINE_PERFECT_DISTANCE_STUDS = 10,
	-- 起跳窗/链式 HUD 武装距离带（stud）；距地 ≤ 此值进入 Ok 预备区
	RUNWAY_PRELAND_MAX_DIST_STUDS = 20,
	-- 链式 Perfect 近地区起点高度（stud）；PRELAND 到此为 Ok 插值，此高度到贴地为 Perfect 插值
	RUNWAY_CHAIN_WINDOW_START_HEIGHT_STUDS = 3.5,
	-- 起跳窗慢漂 WalkSpeed；↑ 窗内更易微调站位
	JUMP_WINDOW_WALK_SPEED = 2,

	-- ═══════════════════════════════════════
	-- —— ② 沿轴水平速度 ——
	-- ═══════════════════════════════════════
	-- 默认跳跃力
	DEFAULT_JUMP_POWER = 16,
	-- 跳跃力锻炼间隔
	JUMP_POWER_EXERCISE_INTERVAL = 1,
	-- 跑步机锻炼固定跑步动画速度（等效 WalkSpeed，用于 AdjustSpeed 计算）
	EXERCISE_RUN_WALK_SPEED = 20,
	-- JumpRunway 分阶段真实位移日志；用于公式校准，发布默认关闭
	RUNWAY_DISTANCE_LOG_ENABLED = false,
	-- 首跳前线前 AutoRun 沿轴速；↑ 起跳前冲更快
	FIRST_TAKEOFF_AUTORUN_SPEED = 16,
	-- max 到 min 的降速比例（相对本次起跳前最终减速完的速度）；↑ 段内减速幅度更大
	JUMP_SPEED_REDUCTION_RATIO = 0.3,
	-- 每跳评级速度 bonus；外层 [jumpIndex]，内层 [1]=Perfect,[2]=Ok,[3]=Late。
	-- 每次起跳增加 bonus（相对本次起跳前最终减速完的速度重新计算）；↑ 踩点好则全程更快
	JUMP_WINDOW_RATING_SPEED_BONUS_BY_TIER = {
		[1] = {
			[1] = 0.5,
			[2] = 0.3,
			[3] = 0.17,
		},
		[2] = {
			[1] = 0.7,
			[2] = 0.5,
			[3] = 0.3,
		},
		[3] = {
			[1] = 1,
			[2] = 0.7,
			[3] = 0.5,
		},
	},

	-- ═══════════════════════════════════════
	-- —— ③ 起跳 / 重力 / 贴地 ——
	-- ═══════════════════════════════════════
	-- 竖直速度相对于水平速度基准的比例（0~1 或 >1）；vy = jumpPower * 本值
	JUMP_VERTICAL_RATIO = 0.4,
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
	DASH_UPWARD_ACCEL = 196.2 * 0.075,
	-- 冲刺最高竖直速度；↑ 可飞更高
	DASH_UPWARD_VY_MAX = 0,
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
	-- 趴滑统一线性减速度（studs/s^2）；终局 B 与 MISS 共用，滑行距离 = v0^2 / (2a)
	RUNWAY_PRONE_SLIDE_DECELERATION = 20,
	-- 终局趴滑：竖直落地速度相对标准竖直速度的额外减速度倍率；0 表示不加成
	RUNWAY_FINAL_LAND_VERTICAL_DECELERATION_RATIO = 0.5,
	-- 终局趴滑：竖直速度加成比例上限，避免极端碰撞导致滑行距离过短
	RUNWAY_FINAL_LAND_VERTICAL_DECELERATION_MAX_RATIO = 2,
	-- MISS 趴滑固定初始速度（studs/s）
	RUNWAY_MISS_SLIDE_START_SPEED = 30,
	-- 终局趴滑：HRP 中心离地高度（stud）；越大玩家视角越高
	RUNWAY_FINAL_LAND_PRONE_HRP_GROUND_HEIGHT = 1.7,
	-- MISS 趴滑：HRP 中心离地高度（stud）；独立于终局趴滑
	RUNWAY_MISS_SLIDE_PRONE_HRP_GROUND_HEIGHT = 1,
	-- 终局撞宝箱后趴姿回弹：HRP 中心离地高度（stud）；独立于 MISS 回弹
	RUNWAY_FINAL_LAND_CHEST_BOUNCE_PRONE_HRP_GROUND_HEIGHT = 1.7,
	-- MISS 撞宝箱后趴姿回弹：HRP 中心离地高度（stud）；用于和 MISS 滑行高度对齐
	RUNWAY_CHEST_BOUNCE_PRONE_HRP_GROUND_HEIGHT = 1,
	-- 撞宝箱后站立等待：额外站立高度偏移（stud）；默认 0 表示按 Humanoid + HRP 半高真实站立
	RUNWAY_CHEST_STAND_HRP_GROUND_EXTRA_HEIGHT = 0,
	-- 跳跃/终局趴滑撞树检测开关
	RUNWAY_TREE_HIT_ENABLED = true,
	-- 跳跃/趴滑撞树前向检测距离（stud）
	RUNWAY_TREE_HIT_CHECK_DISTANCE_STUDS = 5,
	-- 撞击强度达到此值时擦碰减速；0=完全侧擦，1=正面撞击
	RUNWAY_TREE_HIT_SLOW_DOT_THRESHOLD = 0.18,
	-- 撞击强度达到此值时反弹
	RUNWAY_TREE_HIT_BOUNCE_DOT_THRESHOLD = 0.58,
	-- 擦碰后保留的当前水平速度比例
	RUNWAY_TREE_HIT_SLOW_SPEED_SCALE = 0.65,
	-- 反弹水平速度 = 当前水平速度 * 此比例
	RUNWAY_TREE_HIT_BOUNCE_SPEED_SCALE = 0.55,
	-- 反弹水平速度下限
	RUNWAY_TREE_HIT_BOUNCE_MIN_SPEED = 18,
	-- 反弹向上速度
	RUNWAY_TREE_HIT_BOUNCE_UP_VY = 18,
	-- 撞树处理冷却，避免连续帧重复触发
	RUNWAY_TREE_HIT_COOLDOWN_SEC = 0.25,
	-- 反弹后停止时，宝箱直接刷新在玩家面朝方向前方距离（stud）
	RUNWAY_TREE_HIT_DIRECT_OPEN_CHEST_AHEAD_STUDS = 15,
	-- 撞树反弹趴滑：HRP 中心离地高度（stud）；越大趴滑时人物越高
	RUNWAY_OBSTACLE_BOUNCE_SLIDE_PRONE_HRP_GROUND_HEIGHT = 1.7,
	-- 最远距离记录墙体 Y 轴高度（stud）
	BEST_DISTANCE_WALL_HEIGHT_Y = 1.14,

	-- ═══════════════════════════════════════
	-- —— ⑥ 玩法摄像机 ——
	-- ═══════════════════════════════════════
	-- 玩法摄像机跟随平滑；↑ 跟得更紧
	RUNWAY_CAMERA_SMOOTH_SPEED = 3,
	-- 撞树/障碍反弹阶段摄像机跟随平滑；↑ 反弹时跟得更紧，避免人物出屏
	RUNWAY_CAMERA_BOUNCE_SMOOTH_SPEED = 14,
	-- 玩法摄像机 FOV；↑ 视野更广
	RUNWAY_CAMERA_FOV = 60,
	-- 解除脚本摄像机后过渡回玩家控制的插值时长（秒）；0 表示立即恢复
	RUNWAY_CAMERA_RELEASE_TRANSITION_SEC = 0.35,

	-- ═══════════════════════════════════════
	-- —— ⑦ 终局小精灵宝箱 ——
	-- ═══════════════════════════════════════
	-- 小精灵宝箱的配置 ID（对应 LittleElfChestData 中的 id）
	RUNWAY_CHEST_CONFIG_ID = 1,
	-- 旧字段：宝箱生成距离现在由脚本滑行总距离决定，保留字段避免配置兼容问题
	RUNWAY_CHEST_SPAWN_AHEAD_STUDS = 3,
	-- 旧字段：宝箱现在在 B 段入口直接贴地生成，不再按结束前时间生成
	RUNWAY_CHEST_SPAWN_BEFORE_END_SEC = 4,
	-- 小精灵宝箱水平命中半径（stud）；越小越贴近宝箱才触发撞击
	RUNWAY_CHEST_HIT_HORIZONTAL_MAX_DIST_STUDS = 5,
	-- 小精灵宝箱撞击速度（studs/s）；滑到宝箱时保留该末速度，撞击后也用该速度反弹并按统一趴滑减速度减速
	RUNWAY_CHEST_HIT_SPEED = 15,
	-- 开箱最终 brainrot 弹出后的展示停留时长（秒）
	RUNWAY_CHEST_FINAL_REWARD_HOLD_SEC = 0.3,
	-- 玩家举起最终 brainrot 后的展示停留时长（秒）；结束后才创建追击者
	RUNWAY_CHEST_CARRY_PRESENT_HOLD_SEC = 0.5,
	-- 开箱时摄像机向后拉远距离（stud）；↑ 镜头更远
	RUNWAY_CHEST_CAMERA_BACK_OFFSET = 50,
	-- 开箱时摄像机俯仰角度（度）；正数俯视、负数仰视；绝对值 ↑ 俯仰越明显
	RUNWAY_CHEST_CAMERA_PITCH_DEG = 2,
	-- 开箱时摄像机 FOV；↑ 视野更广
	RUNWAY_CHEST_CAMERA_FOV = 50,

	-- ═══════════════════════════════════════
	-- —— ⑧ 逃生红屏 ——
	-- ═══════════════════════════════════════
	-- 逃生阶段红屏总开关
	ESCAPE_RED_SCREEN_ENABLED = true,
	-- 与追击者水平距离：最近参考（stud）；≤ 此值按最近档闪烁
	ESCAPE_RED_SCREEN_NEAR_DISTANCE_STUDS = 50,
	-- 与追击者水平距离：最远参考（stud）；≥ 此值按最远档闪烁
	ESCAPE_RED_SCREEN_FAR_DISTANCE_STUDS = 200,
	-- 最近档（≤ NEAR_DISTANCE）正弦脉冲周期（秒）
	ESCAPE_RED_SCREEN_PULSE_PERIOD_NEAR_SEC = 0.5,
	-- 最远档（≥ FAR_DISTANCE）正弦脉冲周期（秒）
	ESCAPE_RED_SCREEN_PULSE_PERIOD_FAR_SEC = 1,
	-- 最近档闪烁透明度区间 [MIN, MAX]
	ESCAPE_RED_SCREEN_PULSE_TRANSPARENCY_MIN_NEAR = 0,
	ESCAPE_RED_SCREEN_PULSE_TRANSPARENCY_MAX_NEAR = 0.3,
	-- 最远档闪烁透明度区间 [MIN, MAX]（随距离从最近档区间线性平移到此）
	ESCAPE_RED_SCREEN_PULSE_TRANSPARENCY_MIN_FAR = 0.3,
	ESCAPE_RED_SCREEN_PULSE_TRANSPARENCY_MAX_FAR = 0.6,
}

local jumpRunwayDesigner = GameConfig.JumpRunwayDesigner

GameConfig.JumpPowerDefaultValue = jumpRunwayDesigner.DEFAULT_JUMP_POWER -- 默认跳跃力
GameConfig.JumpPowerExerciseInterval = jumpRunwayDesigner.JUMP_POWER_EXERCISE_INTERVAL -- 跳跃力锻炼间隔
GameConfig.ExerciseRunWalkSpeed = jumpRunwayDesigner.EXERCISE_RUN_WALK_SPEED -- 跑步机锻炼固定跑步动画速度

local EXERCISE_RUN_ANIM_WALK_SPEED_REFERENCE = 16

function GameConfig.GetExerciseJumpPowerInterval(buffInfo: BuffInfo?): number
	local multiplier = GameConfig.GetBuffMultiplier(buffInfo, GameConfig.BuffType.ExerciseEfficiency)
	return GameConfig.JumpPowerExerciseInterval / multiplier
end

function GameConfig.GetExerciseAnimationSpeedScale(buffInfo: BuffInfo?): number
	return GameConfig.GetBuffMultiplier(buffInfo, GameConfig.BuffType.ExerciseEfficiency)
end

function GameConfig.GetExerciseTreadmillAnimationSpeed(buffInfo: BuffInfo?): number
	local scale = GameConfig.GetExerciseAnimationSpeedScale(buffInfo)
	return (GameConfig.ExerciseRunWalkSpeed / EXERCISE_RUN_ANIM_WALK_SPEED_REFERENCE) * scale
end

function GameConfig.GetExerciseBikeAnimationSpeed(buffInfo: BuffInfo?): number
	return GameConfig.GetExerciseAnimationSpeedScale(buffInfo)
end
GameConfig.ExerciseClickReward = {
	-- 点击奖励按钮每次出现的最短等待时间（秒）
	DelayMin = 5,
	-- 点击奖励按钮每次出现的最长等待时间（秒）
	DelayMax = 10,
	-- 点击奖励获得的锻炼值倍率，按当前器材 ability 乘以此倍率发放
	RewardMultiplier = 2,
	-- 服务端允许两次点击奖励领取之间的最小间隔（秒），用于防止客户端频繁请求
	ServerMinInterval = 5,
	-- 按钮左右摇摆动画的最大旋转角度
	SwingRotation = 12,
	-- 按钮单次摇摆 tween 时长（秒）
	SwingDuration = 0.18,
	-- 点击奖励飘字从出现到隐藏的总时长（秒）
	PopupLifetime = 1.6,
	-- 飘字动画经过总时长的该比例后开始淡出
	PopupFadeStartRatio = 0.35,
	-- 飘字相对按钮位置向上漂浮的 Y 轴像素偏移，负数表示向上
	PopupFloatOffsetY = -80,
	-- 按钮随机位置距离奖励区域边缘的比例留白
	EdgePaddingScale = 0.08,
}

GameConfig.JumpRunway = {
	-- —— 会话与诊断 ——
	-- 开发诊断：为 true 时客户端显示调试 HUD、服务端节流打印状态；发布务必保持 false（零额外 GUI/打印开销）
	DEBUG = false,
	-- 分阶段真实位移日志：独立于 DEBUG，用于公式校准
	RUNWAY_DISTANCE_LOG_ENABLED = jumpRunwayDesigner.RUNWAY_DISTANCE_LOG_ENABLED,
	N_TOTAL_JUMPS = jumpRunwayDesigner.N_TOTAL_JUMPS,
	RUN_START_COOLDOWN = 0.45,

	-- —— 起跳窗：时间窗、线重叠、预落地、窗内漂移 ——
	-- BeginLine / 链式起跳窗有效时长（秒）；略增可更早、更宽响应（与 PRELAND / OVERLAP_PADDING 配合）
	T_WINDOW = jumpRunwayDesigner.T_WINDOW,
	-- 起跳输入最小间隔（秒），防止快速连点在同一物理窗口内触发多次起跳
	JUMP_INPUT_COOLDOWN_SEC = jumpRunwayDesigner.JUMP_INPUT_COOLDOWN_SEC,
	-- BeginLine 与角色重叠判定：相对线 Part 的 Size 各轴外扩（stud），薄板/高速时比纯 Touched 更早进入起跳窗
	BEGIN_LINE_OVERLAP_PADDING_STUDS = 1.0,
	-- 起跳窗内 deltaT/T_WINDOW：前 1/3 为 Perfect，至 2/3 为 Ok，之后为 Late
	JUMP_WINDOW_RATING_PERFECT_MAX_FRAC = jumpRunwayDesigner.JUMP_WINDOW_RATING_PERFECT_MAX_FRAC,
	JUMP_WINDOW_RATING_OK_MAX_FRAC = jumpRunwayDesigner.JUMP_WINDOW_RATING_OK_MAX_FRAC,
	-- BeginLine 前固定 Perfect 距离（stud）
	RUNWAY_BEGIN_LINE_PERFECT_DISTANCE_STUDS = jumpRunwayDesigner.RUNWAY_BEGIN_LINE_PERFECT_DISTANCE_STUDS,
	-- 起跳窗/链式 HUD 武装距离带（仅几何，无 vy）：RaycastFeet 的 dist ≤ baseline + 本值；baseline 在 TryStartLocalRun 采样。未标定时退化为 dist ≤ 本值（绝对 stud）。
	-- IsRunwayPreLanding 另含 RUNWAY_PRELAND_MAX_VY，用于起跳输入等逻辑。
	RUNWAY_PRELAND_MAX_DIST_STUDS = jumpRunwayDesigner.RUNWAY_PRELAND_MAX_DIST_STUDS,
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
	-- 水平速度：每段 max = jumpPower + 累计起跳评级 bonus；min = max - 本次起跳前最终减速完的速度 * JUMP_SPEED_REDUCTION_RATIO
	JUMP_SPEED_REDUCTION_RATIO = jumpRunwayDesigner.JUMP_SPEED_REDUCTION_RATIO,
	-- 与 ComputeJumpWindowRatingTier 一致：外层 [jumpIndex]，内层 1=Perfect，2=Ok，3=Late；每次起跳基于起跳前最终速度计算对应 bonus
	JUMP_WINDOW_RATING_SPEED_BONUS_BY_TIER = jumpRunwayDesigner.JUMP_WINDOW_RATING_SPEED_BONUS_BY_TIER,
	-- —— 起跳竖直、冲量与各阶段有效重力 ——
	-- 竖直速度 = jumpPower * JUMP_VERTICAL_RATIO；原 jumpPower 绝对值改为水平速度基准
	JUMP_VERTICAL_RATIO = jumpRunwayDesigner.JUMP_VERTICAL_RATIO,
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
	-- 链式起跳窗口近地区起点高度(stud)：PRELAND 到此为 Ok 插值，此高度到贴地为 Perfect 插值
	RUNWAY_CHAIN_WINDOW_START_HEIGHT_STUDS = jumpRunwayDesigner.RUNWAY_CHAIN_WINDOW_START_HEIGHT_STUDS,
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
	-- 跑道普通阶段被障碍碰撞打歪后，HRP 朝向回正到跑道前向的插值速率
	RUNWAY_ORIENTATION_CORRECT_RATE = 18,

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
	ANTI_CHEAT_DISTANCE_HARD_CAP = 45000,
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
	-- AutoRun 且未过 BeginLine 时，最远端 Ring 缩放倍率（在 StartTrigger 处最大，接近 BeginLine 时线性降至 1x）
	-- 缩放区间自动取 StartTrigger 到 BeginLine 的沿跑道距离
	-- AutoRun 且未过 BeginLine 时，最远端 Ring 缩放倍率（距 BeginLine 足够远时最大，到达时恢复 1x）
	RUNWAY_RING_BEGINLINE_MAX_MULTIPLIER = 5,
	-- 仅当 RUNWAY_RING_SCRIPTED_SURFACE_UI 为 true 时由 SetupJumpRunwayRingSurfaceUi 使用
	RUNWAY_RING_UI_PIXELS_PER_STUD = 20,
	RUNWAY_RING_UI_TRACK_STROKE_PX = 15,
	RUNWAY_RING_UI_TRACK_COLOR = Color3.fromRGB(255, 255, 255),
	RUNWAY_RING_UI_FIXED_DIAMETER_PX = 120,
	RUNWAY_RING_UI_FIXED_STROKE_PX = 15,
	RUNWAY_RING_UI_FIXED_COLOR = Color3.fromRGB(255, 220, 80),
	-- 脚下跑道环：脚线距离驱动的目标色（绿/黄/红）与显示平滑
	RUNWAY_RING_COLOR_GREEN = Color3.fromRGB(70, 210, 90),
	RUNWAY_RING_COLOR_YELLOW = Color3.fromRGB(255, 220, 80),
	RUNWAY_RING_COLOR_RED = Color3.fromRGB(255, 55, 55),
	RUNWAY_RING_COLOR_SMOOTH_RATE = 14,
	-- 0 表示在 maxPreLand 上方使用 (PRELAND_MAX - CHAIN_START) 作为绿→黄过渡宽度
	RUNWAY_RING_COLOR_GREEN_FADE_ABOVE_PRELAND_STUDS = 0,

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
	-- 火箭背包模型（ReplicatedStorage.Models.Jetpack）；RootPart/Flame1/Flame2 可为 Part 或 MeshPart；为 false 时使用上方占位 Part
	RUNWAY_JETPACK_ENABLED = true,
	RUNWAY_JETPACK_OUTER_MODEL_NAME = "Jetpack",
	RUNWAY_JETPACK_ROOT_PART_NAME = "RootPart",
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
	RUNWAY_FINAL_LAND_PHASE_A_GROUNDED_STUCK_SEC = 0.35,
	RUNWAY_FINAL_LAND_PHASE_A_MAX_SEC = 6,
	RUNWAY_FINAL_LAND_PHASE_A_GROUNDED_BRAKE_EXP = 2.4,
	RUNWAY_FINAL_LAND_PHASE_A_LOOSE_TOUCHDOWN_HIP_MULT = 1.5,
	RUNWAY_FINAL_LAND_PHASE_A_TOUCHDOWN_FEET_MAX_ABOVE_BASELINE_STUDS = 0,
	RUNWAY_FINAL_LAND_PHASE_A_TOUCHDOWN_FEET_FALLBACK_MAX_DIST_STUDS = 4,
	-- 终局翻滚：为 true 时 A 阶段脚本水平速仅保留沿跑道前向（侧向清零）；为 false 时首帧侧向乘 0.35 后按帧衰减
	RUNWAY_FINAL_LAND_TUMBLE_ZERO_PERP = true,
	-- 终局 A：多点贴地（相对 HRP 局部偏移向下 Raycast）；每点须命中且命中距离 ≤ 该值（stud）才算「全身贴地」，避免水平姿态下单点误触地
	RUNWAY_FINAL_LAND_FULL_BODY_GROUND_MAX_DIST_STUDS = 1.35,
	-- 终局落地触地检测：脚下射线距离阈值（stud），独立于 RUNWAY_SCRIPTED_GROUNDED_MAX_DIST_ABOVE_BASELINE_STUDS
	RUNWAY_FINAL_LAND_TOUCHDOWN_FEET_MAX_DIST_STUDS = jumpRunwayDesigner.RUNWAY_FINAL_LAND_TOUCHDOWN_FEET_MAX_DIST_STUDS,

	-- 趴滑统一线性减速度（studs/s^2）；终局 B 与 MISS 共用
	RUNWAY_PRONE_SLIDE_DECELERATION = jumpRunwayDesigner.RUNWAY_PRONE_SLIDE_DECELERATION,
	-- 终局趴滑：竖直落地速度相对标准竖直速度的额外减速度倍率
	RUNWAY_FINAL_LAND_VERTICAL_DECELERATION_RATIO = jumpRunwayDesigner.RUNWAY_FINAL_LAND_VERTICAL_DECELERATION_RATIO,
	-- 终局趴滑：竖直速度加成比例上限
	RUNWAY_FINAL_LAND_VERTICAL_DECELERATION_MAX_RATIO = jumpRunwayDesigner.RUNWAY_FINAL_LAND_VERTICAL_DECELERATION_MAX_RATIO,
	-- MISS 趴滑固定初始速度（studs/s）
	RUNWAY_MISS_SLIDE_START_SPEED = jumpRunwayDesigner.RUNWAY_MISS_SLIDE_START_SPEED,
	-- 终局趴滑：HRP 中心离地高度（stud）
	RUNWAY_FINAL_LAND_PRONE_HRP_GROUND_HEIGHT = jumpRunwayDesigner.RUNWAY_FINAL_LAND_PRONE_HRP_GROUND_HEIGHT,
	-- MISS 趴滑：HRP 中心离地高度（stud）
	RUNWAY_MISS_SLIDE_PRONE_HRP_GROUND_HEIGHT = jumpRunwayDesigner.RUNWAY_MISS_SLIDE_PRONE_HRP_GROUND_HEIGHT,
	-- 终局撞宝箱后趴姿回弹：HRP 中心离地高度（stud）
	RUNWAY_FINAL_LAND_CHEST_BOUNCE_PRONE_HRP_GROUND_HEIGHT = jumpRunwayDesigner.RUNWAY_FINAL_LAND_CHEST_BOUNCE_PRONE_HRP_GROUND_HEIGHT,
	-- MISS 撞宝箱后趴姿回弹：HRP 中心离地高度（stud）
	RUNWAY_CHEST_BOUNCE_PRONE_HRP_GROUND_HEIGHT = jumpRunwayDesigner.RUNWAY_CHEST_BOUNCE_PRONE_HRP_GROUND_HEIGHT,
	-- 撞宝箱后站立等待：额外站立高度偏移（stud）
	RUNWAY_CHEST_STAND_HRP_GROUND_EXTRA_HEIGHT = jumpRunwayDesigner.RUNWAY_CHEST_STAND_HRP_GROUND_EXTRA_HEIGHT,

	-- 终局趴滑（子阶段 B）地面滑行痕迹：客户端克隆 ReplicatedStorage.Models.SlideTraceTrail（AnchorPart + 双 Attachment + Trail）。模板仅存在于 Studio 同步资源，仓库不存实例。
	RUNWAY_SLIDE_TRACE_ENABLED = true,
	-- Trail 残留秒数（与 RunwaySlideTraceDestroyAfterEndSec 对齐）
	RUNWAY_SLIDE_TRACE_LIFETIME = 5,
	-- 最小采样长度，避免静止时噪点
	RUNWAY_SLIDE_TRACE_MIN_LENGTH = 0.2,
	-- 禁用 Trail 后额外等待再 Destroy（应 >= LIFETIME）
	RUNWAY_SLIDE_TRACE_FADEOUT_BUFFER_SEC = 5,
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
	RUNWAY_CAMERA_BOUNCE_SMOOTH_SPEED = jumpRunwayDesigner.RUNWAY_CAMERA_BOUNCE_SMOOTH_SPEED,
	RUNWAY_CAMERA_FOV = jumpRunwayDesigner.RUNWAY_CAMERA_FOV,
	RUNWAY_CAMERA_RELEASE_TRANSITION_SEC = jumpRunwayDesigner.RUNWAY_CAMERA_RELEASE_TRANSITION_SEC,

	-- —— 终局小精灵宝箱 ——
	RUNWAY_CHEST_CONFIG_ID = jumpRunwayDesigner.RUNWAY_CHEST_CONFIG_ID,
	RUNWAY_CHEST_SPAWN_AHEAD_STUDS = jumpRunwayDesigner.RUNWAY_CHEST_SPAWN_AHEAD_STUDS,
	RUNWAY_CHEST_SPAWN_BEFORE_END_SEC = jumpRunwayDesigner.RUNWAY_CHEST_SPAWN_BEFORE_END_SEC,
	RUNWAY_CHEST_HIT_HORIZONTAL_MAX_DIST_STUDS = jumpRunwayDesigner.RUNWAY_CHEST_HIT_HORIZONTAL_MAX_DIST_STUDS,
	RUNWAY_CHEST_HIT_SPEED = jumpRunwayDesigner.RUNWAY_CHEST_HIT_SPEED,
	RUNWAY_CHEST_FINAL_REWARD_HOLD_SEC = jumpRunwayDesigner.RUNWAY_CHEST_FINAL_REWARD_HOLD_SEC,
	RUNWAY_CHEST_CARRY_PRESENT_HOLD_SEC = jumpRunwayDesigner.RUNWAY_CHEST_CARRY_PRESENT_HOLD_SEC,
	RUNWAY_CHEST_CAMERA_BACK_OFFSET = jumpRunwayDesigner.RUNWAY_CHEST_CAMERA_BACK_OFFSET,
	RUNWAY_CHEST_CAMERA_PITCH_DEG = jumpRunwayDesigner.RUNWAY_CHEST_CAMERA_PITCH_DEG,
	RUNWAY_CHEST_CAMERA_FOV = jumpRunwayDesigner.RUNWAY_CHEST_CAMERA_FOV,
	-- 旧字段：B 段不再追宝箱，保留字段避免配置兼容问题
	RUNWAY_CHEST_SLIDE_MIN_CHASE_SPEED = 16,
	-- 旧字段：B 段不再追宝箱，保留字段避免配置兼容问题
	RUNWAY_CHEST_SLIDE_MAX_CHASE_SPEED = 30,
	-- 旧字段：宝箱距离现在由脚本滑行总距离决定，保留字段避免配置兼容问题
	RUNWAY_CHEST_SLIDE_DISTANCE_BASE_STUDS = 32,
	-- 旧字段：宝箱距离现在由脚本滑行总距离决定，保留字段避免配置兼容问题
	RUNWAY_CHEST_SLIDE_DISTANCE_MIN_STUDS = 36,
	-- 旧字段：宝箱距离现在由脚本滑行总距离决定，保留字段避免配置兼容问题
	RUNWAY_CHEST_SLIDE_DISTANCE_MAX_STUDS = 96,
	-- 旧字段：宝箱距离现在由脚本滑行总距离决定，保留字段避免配置兼容问题
	RUNWAY_CHEST_SLIDE_DISTANCE_DECAY_REFERENCE_JUMP_POWER = 80,
	-- 旧字段：宝箱距离现在由脚本滑行总距离决定，保留字段避免配置兼容问题
	RUNWAY_CHEST_SLIDE_DISTANCE_MULTIPLIER = 1,
	-- 宝箱落点/贴地射线起点抬高距离（stud）；用于从障碍物高度向下找真实地面
	RUNWAY_CHEST_GROUND_RAYCAST_HEIGHT_STUDS = 256,
	-- 宝箱落点/贴地射线向下检测距离（stud）
	RUNWAY_CHEST_GROUND_RAYCAST_DISTANCE_STUDS = 512,
	-- 跳跃/终局趴滑撞树：擦碰减速、正面反弹
	RUNWAY_TREE_HIT_ENABLED = jumpRunwayDesigner.RUNWAY_TREE_HIT_ENABLED,
	RUNWAY_TREE_HIT_CHECK_DISTANCE_STUDS = jumpRunwayDesigner.RUNWAY_TREE_HIT_CHECK_DISTANCE_STUDS,
	RUNWAY_TREE_HIT_SLOW_DOT_THRESHOLD = jumpRunwayDesigner.RUNWAY_TREE_HIT_SLOW_DOT_THRESHOLD,
	RUNWAY_TREE_HIT_BOUNCE_DOT_THRESHOLD = jumpRunwayDesigner.RUNWAY_TREE_HIT_BOUNCE_DOT_THRESHOLD,
	RUNWAY_TREE_HIT_SLOW_SPEED_SCALE = jumpRunwayDesigner.RUNWAY_TREE_HIT_SLOW_SPEED_SCALE,
	RUNWAY_TREE_HIT_BOUNCE_SPEED_SCALE = jumpRunwayDesigner.RUNWAY_TREE_HIT_BOUNCE_SPEED_SCALE,
	RUNWAY_TREE_HIT_BOUNCE_MIN_SPEED = jumpRunwayDesigner.RUNWAY_TREE_HIT_BOUNCE_MIN_SPEED,
	RUNWAY_TREE_HIT_BOUNCE_UP_VY = jumpRunwayDesigner.RUNWAY_TREE_HIT_BOUNCE_UP_VY,
	RUNWAY_TREE_HIT_COOLDOWN_SEC = jumpRunwayDesigner.RUNWAY_TREE_HIT_COOLDOWN_SEC,
	RUNWAY_TREE_HIT_DIRECT_OPEN_CHEST_AHEAD_STUDS = jumpRunwayDesigner.RUNWAY_TREE_HIT_DIRECT_OPEN_CHEST_AHEAD_STUDS,
	RUNWAY_OBSTACLE_BOUNCE_SLIDE_PRONE_HRP_GROUND_HEIGHT = jumpRunwayDesigner.RUNWAY_OBSTACLE_BOUNCE_SLIDE_PRONE_HRP_GROUND_HEIGHT,
	-- 最远距离记录墙体 Y 轴高度（stud）
	BEST_DISTANCE_WALL_HEIGHT_Y = jumpRunwayDesigner.BEST_DISTANCE_WALL_HEIGHT_Y,

	-- —— 追擊者 Chaser ——
	-- 追击者基础移动速度（stud/s）
	CHASER_SPEED = 16,
	-- 追击者生成在玩家跑道前方的距离（stud）
	CHASER_SPAWN_AHEAD_STUDS = 100,
	-- 追击者消失淡出时长（秒）
	CHASER_FADE_DURATION_SEC = 1.5,
	-- 追击者开始追玩家前的总等待时长（秒，含定身阶段）
	CHASER_START_DELAY_SEC = 3,
	-- 追击者创建后保持不动的定身时长（秒，须 <= CHASER_START_DELAY_SEC）
	CHASER_FREEZE_AFTER_SPAWN_SEC = 1.5,
	-- 摄像机插值移动到追击者镜头的时长（秒）
	CHASER_CAMERA_FOCUS_TRANSITION_SEC = 1,
	-- 摄像机对准追击者后保持的时长（秒）
	CHASER_CAMERA_FOCUS_HOLD_SEC = 1,
	-- 摄像机从追击者镜头插值回玩家 home 视角的时长（秒）
	CHASER_CAMERA_RETURN_HOME_TRANSITION_SEC = 1,
	-- 追击者镜头距离追击者 HumanoidRootPart 的水平距离（stud）
	CHASER_CAMERA_FOCUS_DISTANCE_STUDS = 50,
	-- 追击者镜头相对追击者 HumanoidRootPart 的右侧偏移（stud）
	CHASER_CAMERA_FOCUS_RIGHT_OFFSET_STUDS = 0,
	-- 追击者镜头相对追击者 HumanoidRootPart 的高度偏移（stud）
	CHASER_CAMERA_FOCUS_HEIGHT_OFFSET_STUDS = 6,
	-- 追击者穿过树木时的速度倍率
	CHASER_TREE_SLOW_SCALE = 0.5,
	-- 追击者碰到树木后的减速持续时长（秒）
	CHASER_TREE_SLOW_DURATION_SEC = 0.35,

	-- —— 逃生红屏 ——
	ESCAPE_RED_SCREEN_ENABLED = jumpRunwayDesigner.ESCAPE_RED_SCREEN_ENABLED,
	ESCAPE_RED_SCREEN_NEAR_DISTANCE_STUDS = jumpRunwayDesigner.ESCAPE_RED_SCREEN_NEAR_DISTANCE_STUDS,
	ESCAPE_RED_SCREEN_FAR_DISTANCE_STUDS = jumpRunwayDesigner.ESCAPE_RED_SCREEN_FAR_DISTANCE_STUDS,
	ESCAPE_RED_SCREEN_PULSE_PERIOD_NEAR_SEC = jumpRunwayDesigner.ESCAPE_RED_SCREEN_PULSE_PERIOD_NEAR_SEC,
	ESCAPE_RED_SCREEN_PULSE_PERIOD_FAR_SEC = jumpRunwayDesigner.ESCAPE_RED_SCREEN_PULSE_PERIOD_FAR_SEC,
	ESCAPE_RED_SCREEN_PULSE_TRANSPARENCY_MIN_NEAR = jumpRunwayDesigner.ESCAPE_RED_SCREEN_PULSE_TRANSPARENCY_MIN_NEAR,
	ESCAPE_RED_SCREEN_PULSE_TRANSPARENCY_MAX_NEAR = jumpRunwayDesigner.ESCAPE_RED_SCREEN_PULSE_TRANSPARENCY_MAX_NEAR,
	ESCAPE_RED_SCREEN_PULSE_TRANSPARENCY_MIN_FAR = jumpRunwayDesigner.ESCAPE_RED_SCREEN_PULSE_TRANSPARENCY_MIN_FAR,
	ESCAPE_RED_SCREEN_PULSE_TRANSPARENCY_MAX_FAR = jumpRunwayDesigner.ESCAPE_RED_SCREEN_PULSE_TRANSPARENCY_MAX_FAR,

	RUNWAY_BLOCKED_FORWARD_RAY_DISTANCE = 3.5,
	RUNWAY_BLOCKED_MIN_STUCK_SEC = 0.35,
	RUNWAY_BLOCKED_MAX_ALONG_SPEED = 2.5,
	RUNWAY_BLOCKED_MIN_PROGRESS_STUDS = 0.35,
	RUNWAY_JUMP_WINDOW_GROUNDED_HOLD_SEC = 0.12,
}

GameConfig.Exercise = {
	DEBUG = false,
}

--- 跑道单段跳跃水平限速：max = baseSpeed + cumulativeRatingBonus（clamp 至 ANTI_CHEAT_MAX_ALONG_SPEED）；min = max - reductionDelta。
--- baseSpeed 可选参数，若传入则作为水平速度基准（来自 jumpPower）；不传时回退为 0。
--- reductionDelta 可选参数，来自本次起跳前最终减速完的速度 * JUMP_SPEED_REDUCTION_RATIO；不传时回退为 0。
--- segmentIndex 保留供调用方语义对齐（第 k 段对应 takeoffCount==k），当前与 max/min 数值无关。
function GameConfig.GetJumpRunwayJumpSpeedLimitsForSegment(
	_segmentIndex: number,
	cumulativeRatingBonus: number,
	baseSpeed: number?,
	reductionDelta: number?
): (number, number)
	local jr = GameConfig.JumpRunway
	local initial = baseSpeed or 0
	if typeof(initial) ~= "number" or initial ~= initial then
		initial = 0
	end
	local delta = reductionDelta or 0
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

-- 根据玩家移动距离获取对应的小精灵宝箱配置（取 distance <= 当前距离的最大 distance 条目）
function GameConfig.GetLittleElfChestByDistance(distance: number): LittleElfChestConfigData?
	local chests = GameConfig.LittleElfChests
	if typeof(chests) ~= "table" then
		return nil
	end
	local best: LittleElfChestConfigData? = nil
	for _, row in pairs(chests) do
		if type(row) == "table" then
			local chestConfig = row :: LittleElfChestConfigData
			if
				type(chestConfig.distance) == "number"
				and chestConfig.distance <= distance
				and GameConfig.IsLittleElfChestAvailableForJumpRunway(chestConfig)
			then
				if best == nil or chestConfig.distance > best.distance then
					best = chestConfig
				end
			end
		end
	end
	return best
end

-- 根据玩家移动距离获取对应的怪物配置（取 distance <= 当前距离的最大 distance 条目）
function GameConfig.GetMonsterByDistance(distance: number): MonsterData?
	local list = GameConfig.MonsterDistanceList
	if typeof(list) ~= "table" or #list == 0 then
		return nil
	end
	-- 二分查找最后一个 distance <= 当前距离的条目
	local lo = 1
	local hi = #list
	local best: MonsterData? = nil
	while lo <= hi do
		local mid = math.floor((lo + hi) / 2)
		local entry = list[mid]
		if entry.distance <= distance then
			best = entry
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	return best
end

GameConfig.UpgradeHomeInfoUIDistanceLimit = 40
GameConfig.HomePlaceModelInfoUIBillboardPadding = 0.5
GameConfig.HomePlaceModelInfoUIBillboardOffsetY = 5

GameConfig.Inventory = {
	InitialModelCapacity = 5,
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

local function BuildShopFromRawData()
	-- 遍历 UpgradeShopData 原始数据，按 type 分组构建 GameConfig.Shop 条目
	-- type=1 → WalkSpeed, type=2 → HomeLevel
	local shopBuilders: { [number]: { abilityList: { [number]: number }, upgradeCostList: { [number]: number }, name_t: string } } = {}
	for _, entry in ipairs(UpgradeShopRawData) do
		local t = entry["type"]
		if t == nil then
			continue
		end
		local lv = entry["lv"]
		if lv == nil then
			continue
		end
		local builder = shopBuilders[t]
		if builder == nil then
			local nameLookup = {
				[1] = "WalkSpeed",
				[2] = "HomeLevel",
			}
			local name_t = nameLookup[t]
			if name_t == nil then
				continue
			end
			builder = { abilityList = {}, upgradeCostList = {}, name_t = name_t }
			shopBuilders[t] = builder
		end
		builder.abilityList[lv] = entry["ability"]
		builder.upgradeCostList[lv] = entry["upgradeCost"]
	end

	local typeToShopKey = {
		[1] = "WalkSpeed",
		[2] = "HomeLevel",
	}
	for t, builder in pairs(shopBuilders) do
		local shopKey = typeToShopKey[t]
		if shopKey and GameConfig.Shop[shopKey] then
			local maxLevel = 0
			for lv in pairs(builder.abilityList) do
				if lv > maxLevel then
					maxLevel = lv
				end
			end
			GameConfig.Shop[shopKey].maxLevel = maxLevel
			GameConfig.Shop[shopKey].abilityList = builder.abilityList
			GameConfig.Shop[shopKey].upgradeCostList = builder.upgradeCostList
		end
	end
end

GameConfig.Shop = {
	WalkSpeed = MakeStubShop(GameConfig.SkillType.WalkSpeed, "WalkSpeed", 16),
	HomeLevel = MakeStubShop(GameConfig.SkillType.HomeLevel, "HomeLevel", 1),
}
BuildShopFromRawData()

GameConfig.ShopBundleBgIconIdById = {
	[1] = "rbxassetid://77886307507247",
	[2] = "rbxassetid://83983663285653",
	[3] = "rbxassetid://140006926894911",
	[4] = "rbxassetid://131609692287978",
	[5] = "rbxassetid://123495708111145",
} :: { [number]: string }

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

local shopBundleRewardsById: { [number]: { RewardInfo } } = {}
for _, rewardRow in pairs(ShopBundleDataModule) do
	if type(rewardRow) ~= "table" or type(rewardRow.id) ~= "number" then
		continue
	end
	local bundleId = rewardRow.id
	local reward = rewardRow :: RewardInfo
	if shopBundleRewardsById[bundleId] == nil then
		shopBundleRewardsById[bundleId] = {}
	end
	table.insert(shopBundleRewardsById[bundleId], reward)
end

local sortedShopBundleConfigs: { ShopBundleConfigurationData } = {}
for _, configRow in pairs(ShopBundleConfigurationDataModule) do
	if type(configRow) ~= "table" or type(configRow.id) ~= "number" then
		continue
	end
	local bundleConfig = configRow :: ShopBundleConfigurationData
	local bgIconId = GameConfig.ShopBundleBgIconIdById[bundleConfig.id]
	if bgIconId ~= nil then
		bundleConfig.bgIconId = bgIconId
	end
	GameConfig.ShopBundleById[bundleConfig.id] = {
		config = bundleConfig,
		rewards = shopBundleRewardsById[bundleConfig.id] or {},
	}
	table.insert(sortedShopBundleConfigs, bundleConfig)
end

table.sort(sortedShopBundleConfigs, function(a: ShopBundleConfigurationData, b: ShopBundleConfigurationData): boolean
	if a.sortId == b.sortId then
		return a.id < b.id
	end
	return a.sortId < b.sortId
end)

for _, bundleConfig in ipairs(sortedShopBundleConfigs) do
	table.insert(GameConfig.ShopBundleList, bundleConfig.id)
end

GameConfig.JetpackShopBundleIdByJetpackId = {} :: { [number]: number }
for bundleId, bundleData in pairs(GameConfig.ShopBundleById) do
	for _, reward in ipairs(bundleData.rewards) do
		if reward.rewardType == GameConfig.RewardType.Jetpack then
			GameConfig.JetpackShopBundleIdByJetpackId[reward.rewardId] = bundleId
		end
	end
end

function GameConfig.GetJetpackShopBundleConfig(jetpackId: number): ShopBundleConfigurationData?
	local bundleId = GameConfig.JetpackShopBundleIdByJetpackId[jetpackId]
	if bundleId == nil then
		return nil
	end
	local bundleData = GameConfig.ShopBundleById[bundleId]
	return if bundleData ~= nil then bundleData.config else nil
end

export type ShopPaidConfig = {
	WalkSpeed10ProductId: number,
	BrainrotUpgrade3ProductId: number,
}

GameConfig.ShopPaid = {
	WalkSpeed10ProductId = 3602583384,
	BrainrotUpgrade3ProductId = 3602583510,
} :: ShopPaidConfig

export type ModelRarity = "Common" | "Rare" | "Epic" | "Legend"

export type ModelInfo = {
	instanceId: string,
	configId: number,
	rarity: ModelRarity,
	level: number,
	variantId: number?,
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

export type PlayerCarriedInfo = {} -- bricks 已废弃

export type GuideProgressSaveInfo = {
	guideStepDoneMap: { [string]: boolean },
	appearedGuideTypeInfo: { [string]: boolean },
}

export type ShopInfo = {
	walkSpeedLevel: number,
	rebirthLevel: number,
}

export type PlayerSaveInfo = {
	dataVersion: number,
	firstEnterTime: number,
	firstEnterVersion: string,
	gameTime: number,
	loginDays: number,
	lastOnlineDateUTC: number,
	settingInfo: SettingInfo,
	ownedGamePassList: { number },
	ownedShopBundleMap: { [string]: boolean },
	currencies: { [string]: number },
	inventoryInfo: PlayerInventorySaveInfo,
	homeInfo: {
		level: number,
		placedModels: { [string]: ModelInfo },
	},
	shopInfo: ShopInfo,
	jumpPower: JumpPowerInfo,
	jumpRunwayBestDistance: number,
	jumpRunwayJumpCount: number,
	jumpRunwayWeeklyBestDistance: number,
	jumpRunwayWeeklyBestDistanceWeekIndex: number,
	brainrotsInfo: BrainrotInventoryInfo,
	brainrotQueue: { BrainrotQueueItem },
	exEquipInventory: ExEquipInventory,
	jetpackInventory: JetpackInventory,
	buffInfo: BuffInfo,
	guideProgressInfo: GuideProgressSaveInfo,
	discoveredIslandIds: { [string]: boolean }?,
	hasClaimedGroupReward: boolean,
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
	leaderboardChanges: { [string]: boolean }?,
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
			rebirthLevel = 0,
		},
		jumpPower = GameConfig.CreateDefaultJumpPowerInfo(),
		jumpRunwayBestDistance = 0,
		jumpRunwayJumpCount = 0,
		jumpRunwayWeeklyBestDistance = 0,
		jumpRunwayWeeklyBestDistanceWeekIndex = 0,
		brainrotsInfo = {
			ownedBrainrots = {},
			equippedBrainrots = {},
			brainrotUsingNumMax = 3,
		},
		brainrotQueue = {},
		exEquipInventory = {
			currentId = "",
			ownedList = {},
		},
		jetpackInventory = {
			currentId = "",
			ownedList = {},
		},
		buffInfo = GameConfig.CreateDefaultBuffInfo(),
		guideProgressInfo = {
			guideStepDoneMap = {},
			appearedGuideTypeInfo = {},
		},
		discoveredIslandIds = {},
		hasClaimedGroupReward = false,
	}
end

export type ClientLocalPlayerSaveInfo = {
	settingInfo: SettingInfo,
	ownedGamePassList: { number },
	ownedShopBundleMap: { [string]: boolean },
	currencies: { [string]: number },
	inventoryInfo: PlayerInventorySaveInfo,
	homeInfo: {
		level: number,
		placedModels: { [string]: ModelInfo },
	},
	shopInfo: ShopInfo,
	jumpPower: JumpPowerInfo,
	jumpRunwayBestDistance: number,
	jumpRunwayJumpCount: number,
	brainrotsInfo: BrainrotInventoryInfo,
	brainrotQueue: { BrainrotQueueItem },
	exEquipInventory: ExEquipInventory,
	jetpackInventory: JetpackInventory,
	buffInfo: BuffInfo,
	homeSlot: string,
	guideProgressInfo: GuideProgressSaveInfo,
	hasClaimedGroupReward: boolean,
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
