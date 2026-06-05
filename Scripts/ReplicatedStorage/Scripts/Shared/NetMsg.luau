--!strict
export type JumpRunwayStatePayload = {
	phase: number,
	distance: number,
	windowRemainSec: number?,
	fuel: number,
	takeoffCount: number,
	ratingTier: number?,
	finalScore: number?,
	runwayForward: Vector3,
	runwayOrigin: Vector3?,
}

-- 客户端→服务端的统一上报载荷
--   kind=1 Input  : 起跳/冲刺按键状态（可选附带 clientPhase 供服端日志）
--   kind=2 Sample : 周期性物理样本（沿轴距离、速度、偏离、是否着地；可选 clientPhase）
--   kind=3 Final  : 客户端报告本局结束（落地稳定），服务端据此锁定（成绩以服端样本 maxAlong 为准）
--   kind=4 Start  : 客户端权威开局（跑道轴、原点、沿轴 baseline），服端仅登记会话并做后续样本校验
export type JumpRunwayInputReport = {
	kind: number,
	jumpPressed: boolean?,
	dashHeld: boolean?,
	sampleAlong: number?,
	sampleAlongSpeed: number?,
	samplePerpMag: number?,
	grounded: boolean?,
	finalAlong: number?,
	clientClock: number?,
	clientPhase: number?,
	alongBaseline: number?,
	runwayForward: Vector3?,
	runwayOrigin: Vector3?,
}

local NetMsg = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local runService: RunService = game:GetService("RunService")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local remoteEventsFolder: Folder = replicatedStorage:FindFirstChild("RemoteEvents") :: Folder

local function GetOrCreateRemoteEvent(eventName: string): RemoteEvent?
	local existing = remoteEventsFolder:FindFirstChild(eventName)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if runService:IsServer() then
		local created = Instance.new("RemoteEvent")
		created.Name = eventName
		created.Parent = remoteEventsFolder
		return created
	end
	local waited = remoteEventsFolder:WaitForChild(eventName, 10)
	if waited and waited:IsA("RemoteEvent") then
		return waited
	end
	warn("[NetMsg] RemoteEvent missing:", eventName)
	return nil
end

local requestSetBGMVolumeEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSetBGMVolume") :: RemoteEvent
local requestSetSoundEffectVolumeEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSetSoundEffectVolume") :: RemoteEvent
local requestSetVibrationsOnOffStateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSetVibrationsOnOffState") :: RemoteEvent
local requestSetDecelerationOnEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSetDecelerationOn") :: RemoteEvent
local requestTeleportToHomeEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestTeleportToHome") :: RemoteEvent
local requestTeleportToShopEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestTeleportToShop") :: RemoteEvent
local notifyPlayerInfoInitEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerInfoInit") :: RemoteEvent
local notifyPlayersOtherPlayerInfoInitEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayersOtherPlayerInfoInit") :: RemoteEvent
local notifyPlayerAcquiredGamePassEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerAcquiredGamePass") :: RemoteEvent
local notifyPlayerHomeInfoUpdateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerHomeInfoUpdate") :: RemoteEvent
local notifyAllPlayersModelYieldsEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyAllPlayersModelYields") :: RemoteEvent

-- [抓模型] 游戏通信
local requestPlaceBrickBatchEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestPlaceBrickBatch") :: RemoteEvent
local requestPickupModelEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestPickupModel") :: RemoteEvent
local requestPlaceHomeModelEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestPlaceHomeModel") :: RemoteEvent
local requestUpgradeModelEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestUpgradeModel") :: RemoteEvent
local requestSellModelEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSellModel") :: RemoteEvent
local requestBuyShopUpgradeEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestBuyShopUpgrade") :: RemoteEvent
local requestUpgradeSkillEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestUpgradeSkill") :: RemoteEvent
local requestClaimYieldEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestClaimYield") :: RemoteEvent
local requestPickupHomeModelEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestPickupHomeModel") :: RemoteEvent
local requestStartPavingEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestStartPaving") :: RemoteEvent
local notifyPlaceBrickBatchResultEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlaceBrickBatchResult") :: RemoteEvent
local requestPlaceCarryingBrainrotEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestPlaceCarryingBrainrot") :: RemoteEvent
local requestSellCarryingBrainrotEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSellCarryingBrainrot") :: RemoteEvent
local requestSellAllBrainrotInQueueEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSellAllBrainrotInQueue") :: RemoteEvent
local notifyPlayerInventoryUpdateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerInventoryUpdate") :: RemoteEvent
local notifyPlayerSkillLevelUpdateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerSkillLevelUpdate") :: RemoteEvent
local notifyPlayerCarriedUpdateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerCarriedUpdate") :: RemoteEvent
local notifyPlayerCurrencyUpdateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerCurrencyUpdate") :: RemoteEvent
local requestClaimOfflineRewardEvent: RemoteEvent? = GetOrCreateRemoteEvent("RequestClaimOfflineReward")
local notifyOfflineRewardInfoEvent: RemoteEvent? = GetOrCreateRemoteEvent("NotifyOfflineRewardInfo")

-- Gifting
local requestSendGiftEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSendGift") :: RemoteEvent
local notifyReceiveGiftRequestEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyReceiveGiftRequest") :: RemoteEvent
local requestRespondGiftEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestRespondGift") :: RemoteEvent
local notifyGiftResultEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyGiftResult") :: RemoteEvent
local notifyShowGiftConfirmEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyShowGiftConfirm") :: RemoteEvent
local notifyBrainrotQueueUpdateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyBrainrotQueueUpdate") :: RemoteEvent
local notifyShowGameTipEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyShowGameTip") :: RemoteEvent
local notifyRescueStartEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyRescueStart") :: RemoteEvent
local requestOpenChestEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestOpenChest") :: RemoteEvent
local notifyChestOpenResultEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyChestOpenResult") :: RemoteEvent
local notifyGuideProgressInfoEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("NotifyGuideProgressInfo") :: RemoteEvent?
local requestCompleteGuideStepEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestCompleteGuideStep") :: RemoteEvent?

-- Rebirth
local requestRebirthEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestRebirth") :: RemoteEvent
local requestPaidRebirthEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestPaidRebirth") :: RemoteEvent

-- Earthquake
local notifyEarthquakeStateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyEarthquakeState") :: RemoteEvent
local notifyEarthquakeJudgeDropEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyEarthquakeJudgeDrop") :: RemoteEvent
local notifyEarthquakeRecoverEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyEarthquakeRecover") :: RemoteEvent
local notifyEarthquakeWarningEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyEarthquakeWarning") :: RemoteEvent

-- Chest workbench (optional RemoteEvents — create under ReplicatedStorage.RemoteEvents in Studio)
local requestWorkbenchManualEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestWorkbenchManual") :: RemoteEvent?
local requestPurchaseWorkbenchUpgradeEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestPurchaseWorkbenchUpgrade") :: RemoteEvent?
local requestPlaceChestOnWorkbenchSlotEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestPlaceChestOnWorkbenchSlot") :: RemoteEvent?
local requestPickupChestFromWorkbenchSlotEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestPickupChestFromWorkbenchSlot") :: RemoteEvent?
local notifyWorkbenchSlotsUpdateEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("NotifyWorkbenchSlotsUpdate") :: RemoteEvent?

-- JumpRunway：在 Studio 的 ReplicatedStorage.RemoteEvents 下创建 `NotifyJumpRunwayState`、`RequestJumpRunwayInput`
local notifyJumpRunwayStateEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("NotifyJumpRunwayState") :: RemoteEvent?
local requestJumpRunwayInputEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestJumpRunwayInput") :: RemoteEvent?

-- JumpRunway BestDistance：客户端上报最远距离记录
local requestJumpRunwayBestDistanceEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestJumpRunwayBestDistance") :: RemoteEvent?

-- JumpRunway LittleElfChest：请求/通知小精灵宝箱奖励
local requestJumpRunwayLittleElfChestRewardEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestJumpRunwayLittleElfChestReward") :: RemoteEvent?
local requestJumpRunwayLittleElfChestGrantEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestJumpRunwayLittleElfChestGrant") :: RemoteEvent?
local requestJumpRunwayLittleElfChestStartCarryEvent: RemoteEvent? =
	remoteEventsFolder:FindFirstChild("RequestJumpRunwayLittleElfChestStartCarry") :: RemoteEvent?
local notifyJumpRunwayLittleElfChestRewardEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("NotifyJumpRunwayLittleElfChestReward") :: RemoteEvent?

-- ExEquip 锻炼器材
local requestBuyExEquipEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestBuyExEquip") :: RemoteEvent?
local requestBuyExEquipPaidEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestBuyExEquipPaid") :: RemoteEvent?
local requestUpdateExEquipUsingEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestUpdateExEquipUsing") :: RemoteEvent?
local notifyPlayerExEquipInventoryUpdateEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("NotifyPlayerExEquipInventoryUpdate") :: RemoteEvent?
local requestClaimGroupRewardEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestClaimGroupReward") :: RemoteEvent?

-- 锻炼模式
local requestStartExerciseEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestStartExercise") :: RemoteEvent?
local requestStopExerciseEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestStopExercise") :: RemoteEvent?
local requestExerciseClickRewardEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestExerciseClickReward") :: RemoteEvent?
local notifyExerciseStartEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("NotifyExerciseStart") :: RemoteEvent?
local notifyExerciseEndEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("NotifyExerciseEnd") :: RemoteEvent?

-- JumpPower 更新（服务端→客户端）
local notifyJumpPowerUpdateEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("NotifyJumpPowerUpdate") :: RemoteEvent?

--客户端请求设置背景音乐音量
function NetMsg.FireRequestSetBGMVolume(volume: number)
	requestSetBGMVolumeEvent:FireServer(volume)
end

function NetMsg.ConnectRequestSetBGMVolume(callback: (player: Player, volume: number) -> ())
	requestSetBGMVolumeEvent.OnServerEvent:Connect(callback)
end

--客户端请求设置音效音量
function NetMsg.FireRequestSetSoundEffectVolume(volume: number)
	requestSetSoundEffectVolumeEvent:FireServer(volume)
end

function NetMsg.ConnectRequestSetSoundEffectVolume(callback: (player: Player, volume: number) -> ())
	requestSetSoundEffectVolumeEvent.OnServerEvent:Connect(callback)
end

--客户端请求设置振动开关状态
function NetMsg.FireRequestSetVibrationsOnOffState(vibrationsOn: boolean)
	requestSetVibrationsOnOffStateEvent:FireServer(vibrationsOn)
end

function NetMsg.ConnectRequestSetVibrationsOnOffState(callback: (player: Player, vibrationsOn: boolean) -> ())
	requestSetVibrationsOnOffStateEvent.OnServerEvent:Connect(callback)
end

--客户端请求设置减速开关状态
function NetMsg.FireRequestSetDecelerationOn(decelerationOn: boolean)
	requestSetDecelerationOnEvent:FireServer(decelerationOn)
end

function NetMsg.ConnectRequestSetDecelerationOn(callback: (player: Player, decelerationOn: boolean) -> ())
	requestSetDecelerationOnEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求传送到 Home TeleportPoint
function NetMsg.FireRequestTeleportToHome()
	requestTeleportToHomeEvent:FireServer()
end

function NetMsg.ConnectRequestTeleportToHome(callback: (player: Player) -> ())
	requestTeleportToHomeEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求传送到 Shop TeleportPoint
function NetMsg.FireRequestTeleportToShop()
	requestTeleportToShopEvent:FireServer()
end

function NetMsg.ConnectRequestTeleportToShop(callback: (player: Player) -> ())
	requestTeleportToShopEvent.OnServerEvent:Connect(callback)
end

--通知客户端玩家信息初始化完成
function NetMsg.FireNotifyPlayerInfoInit(
	player: Player,
	localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo },
	playerConfigInfo: GameConfig.PlayerConfigInfo
)
	notifyPlayerInfoInitEvent:FireClient(player, localPlayerSaveInfo, otherPlayerSaveInfoMap, playerConfigInfo)
end

function NetMsg.ConnectNotifyPlayerInfoInit(callback: (
	localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo },
	playerConfigInfo: GameConfig.PlayerConfigInfo
) -> ())
	notifyPlayerInfoInitEvent.OnClientEvent:Connect(callback)
end

--通知客户端其他玩家信息初始化完成
function NetMsg.FireNotifyPlayersOtherPlayerInfoInit(playerId: number, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo)
	notifyPlayersOtherPlayerInfoInitEvent:FireAllClients(playerId, otherPlayerSaveInfo)
end

function NetMsg.ConnectNotifyPlayersOtherPlayerInfoInit(callback: (playerId: number, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo) -> ())
	notifyPlayersOtherPlayerInfoInitEvent.OnClientEvent:Connect(callback)
end

--通知客户端玩家获得了通行证
function NetMsg.FireNotifyPlayerAcquiredGamePass(player: Player, gamePassId: number)
	print("[NetMsg] FireNotifyPlayerAcquiredGamePass for player", player.Name, "gamePassId", gamePassId)
	notifyPlayerAcquiredGamePassEvent:FireClient(player, gamePassId)
end

function NetMsg.ConnectNotifyPlayerAcquiredGamePass(callback: (gamePassId: number) -> ())
	notifyPlayerAcquiredGamePassEvent.OnClientEvent:Connect(callback)
end

--通知所有客户端更新在线玩家的房子信息
function NetMsg.FireNotifyPlayerHomeInfoUpdate(playerId: number, homeSlot: string, homeInfo: any, rebirthLevel: number?)
	--print("[NetMsg] FireNotifyPlayerHomeInfoUpdate for playerId", playerId)
	notifyPlayerHomeInfoUpdateEvent:FireAllClients(playerId, homeSlot, homeInfo, rebirthLevel)
end

function NetMsg.ConnectNotifyPlayerHomeInfoUpdate(callback: (playerId: number, homeSlot: string, homeInfo: any, rebirthLevel: number?) -> ())
	notifyPlayerHomeInfoUpdateEvent.OnClientEvent:Connect(callback)
end

--通知全服玩家模型收益更新 (深度优化版：单次广播同步所有玩家数值)
function NetMsg.FireNotifyAllPlayersModelYields(allYields: { [string]: { [string]: number } })
	notifyAllPlayersModelYieldsEvent:FireAllClients(allYields)
end

function NetMsg.ConnectNotifyAllPlayersModelYields(callback: (allYields: { [string]: { [string]: number } }) -> ())
	notifyAllPlayersModelYieldsEvent.OnClientEvent:Connect(callback)
end

-- 客户端请求批量放置砖块 (跑酷)
function NetMsg.FireRequestPlaceBrickBatch(positions: { Vector3 }, batchId: number?, clientSentAt: number?, isEarthquakeMarkActive: boolean?)
	--print("[NetMsg] FireRequestPlaceBrickBatch with", #positions, "points")
	requestPlaceBrickBatchEvent:FireServer(positions, batchId, clientSentAt, isEarthquakeMarkActive)
end
function NetMsg.ConnectRequestPlaceBrickBatch(callback: (
	player: Player,
	positions: { Vector3 },
	batchId: number?,
	clientSentAt: number?,
	isEarthquakeMarkActive: boolean?
) -> ())
	requestPlaceBrickBatchEvent.OnServerEvent:Connect(callback)
end

function NetMsg.FireNotifyPlaceBrickBatchResult(
	player: Player,
	batchId: number,
	acceptedIndexes: { number },
	rejectedList: { { index: number, reason: string } },
	serverBricks: number,
	serverNow: number?
)
	notifyPlaceBrickBatchResultEvent:FireClient(player, batchId, acceptedIndexes, rejectedList, serverBricks, serverNow or os.clock())
end

function NetMsg.ConnectNotifyPlaceBrickBatchResult(callback: (
	batchId: number,
	acceptedIndexes: { number },
	rejectedList: { { index: number, reason: string } },
	serverBricks: number,
	serverNow: number
) -> ())
	notifyPlaceBrickBatchResultEvent.OnClientEvent:Connect(callback)
end

-- 客户端请求拾取模型
function NetMsg.FireRequestPickupModel(instanceId: string)
	print("[NetMsg] FireRequestPickupModel", instanceId)
	requestPickupModelEvent:FireServer(instanceId)
end
function NetMsg.ConnectRequestPickupModel(callback: (player: Player, instanceId: string) -> ())
	requestPickupModelEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求放置模型到家园展台
function NetMsg.FireRequestPlaceHomeModel(instanceId: string, pointIndex: number)
	print("[NetMsg] FireRequestPlaceHomeModel", instanceId, "at pointIndex", pointIndex)
	requestPlaceHomeModelEvent:FireServer(instanceId, pointIndex)
end
function NetMsg.ConnectRequestPlaceHomeModel(callback: (player: Player, instanceId: string, pointIndex: number) -> ())
	requestPlaceHomeModelEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求升级家园展台模型
function NetMsg.FireRequestUpgradeModel(pointIndex: number, levelAdd: number?, isPaidIntent: boolean?)
	print("[NetMsg] FireRequestUpgradeModel at pointIndex", pointIndex, "levelAdd", levelAdd, "isPaidIntent", isPaidIntent)
	requestUpgradeModelEvent:FireServer(pointIndex, levelAdd, isPaidIntent)
end
function NetMsg.ConnectRequestUpgradeModel(callback: (player: Player, pointIndex: number, levelAdd: number?, isPaidIntent: boolean?) -> ())
	requestUpgradeModelEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求出售家园展台模型
function NetMsg.FireRequestSellModel(pointIndex: number)
	print("[NetMsg] FireRequestSellModel at pointIndex", pointIndex)
	requestSellModelEvent:FireServer(pointIndex)
end
function NetMsg.ConnectRequestSellModel(callback: (player: Player, pointIndex: number) -> ())
	requestSellModelEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求购买商店升级
function NetMsg.FireRequestBuyShopUpgrade(upgradeType: string)
	print("[NetMsg] FireRequestBuyShopUpgrade", upgradeType)
	requestBuyShopUpgradeEvent:FireServer(upgradeType)
end
function NetMsg.ConnectRequestBuyShopUpgrade(callback: (player: Player, upgradeType: string) -> ())
	requestBuyShopUpgradeEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求领取展示台收益 (由触碰本地 CollectPart 触发)
function NetMsg.FireRequestClaimYield(targetPlayerId: number, pointIndex: number)
	--print("[NetMsg] FireRequestClaimYield from target", targetPlayerId, "plot", pointIndex)
	requestClaimYieldEvent:FireServer(targetPlayerId, pointIndex)
end
function NetMsg.ConnectRequestClaimYield(callback: (player: Player, targetPlayerId: number, pointIndex: number) -> ())
	requestClaimYieldEvent.OnServerEvent:Connect(callback)
end

function NetMsg.FireRequestClaimOfflineReward()
	if requestClaimOfflineRewardEvent == nil then
		return
	end
	requestClaimOfflineRewardEvent:FireServer()
end

function NetMsg.ConnectRequestClaimOfflineReward(callback: (player: Player) -> ())
	if requestClaimOfflineRewardEvent == nil then
		return
	end
	requestClaimOfflineRewardEvent.OnServerEvent:Connect(callback)
end

function NetMsg.FireNotifyOfflineRewardInfo(player: Player, offlineRewardInfo: GameConfig.OfflineRewardInfo?)
	if notifyOfflineRewardInfoEvent == nil then
		return
	end
	notifyOfflineRewardInfoEvent:FireClient(player, offlineRewardInfo)
end

function NetMsg.ConnectNotifyOfflineRewardInfo(callback: (offlineRewardInfo: GameConfig.OfflineRewardInfo?) -> ())
	if notifyOfflineRewardInfoEvent == nil then
		return
	end
	notifyOfflineRewardInfoEvent.OnClientEvent:Connect(callback)
end

-- 客户端请求从家园展台拾取模型
function NetMsg.FireRequestPickupHomeModel(pointIndex: number)
	--print("[NetMsg] FireRequestPickupHomeModel at pointIndex", pointIndex)
	requestPickupHomeModelEvent:FireServer(pointIndex)
end
function NetMsg.ConnectRequestPickupHomeModel(callback: (player: Player, pointIndex: number) -> ())
	requestPickupHomeModelEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求触发铺砖模式 (触碰 StartTrigger)
function NetMsg.FireRequestStartPaving()
	--print("[NetMsg] FireRequestStartPaving")
	requestStartPavingEvent:FireServer()
end
function NetMsg.ConnectRequestStartPaving(callback: (player: Player) -> ())
	requestStartPavingEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求放置正在搬运的宠物
function NetMsg.FireRequestPlaceCarryingBrainrot(pointIndex: number)
	--print("[NetMsg] FireRequestPlaceCarryingBrainrot at pointIndex", pointIndex)
	requestPlaceCarryingBrainrotEvent:FireServer(pointIndex)
end
function NetMsg.ConnectRequestPlaceCarryingBrainrot(callback: (player: Player, pointIndex: number) -> ())
	requestPlaceCarryingBrainrotEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求出售正在搬运的宠物
function NetMsg.FireRequestSellCarryingBrainrot()
	print("[NetMsg] FireRequestSellCarryingBrainrot")
	requestSellCarryingBrainrotEvent:FireServer()
end
function NetMsg.ConnectRequestSellCarryingBrainrot(callback: (player: Player) -> ())
	requestSellCarryingBrainrotEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求出售手上（若有）及背包队列中所有 Brainrot
function NetMsg.FireRequestSellAllBrainrotInQueue()
	print("[NetMsg] FireRequestSellAllBrainrotInQueue")
	requestSellAllBrainrotInQueueEvent:FireServer()
end

function NetMsg.ConnectRequestSellAllBrainrotInQueue(callback: (player: Player) -> ())
	requestSellAllBrainrotInQueueEvent.OnServerEvent:Connect(callback)
end

-- 通知客户端玩家库存更新 (持久化部分)
function NetMsg.FireNotifyPlayerInventoryUpdate(player: Player, inventoryInfo: GameConfig.PlayerInventorySaveInfo)
	print("[NetMsg] FireNotifyPlayerInventoryUpdate for player", player.Name)
	notifyPlayerInventoryUpdateEvent:FireClient(player, inventoryInfo)
end
function NetMsg.ConnectNotifyPlayerInventoryUpdate(callback: (inventoryInfo: GameConfig.PlayerInventorySaveInfo) -> ())
	notifyPlayerInventoryUpdateEvent.OnClientEvent:Connect(callback)
end

-- 通知客户端玩家搬运信息更新 (瞬态)
function NetMsg.FireNotifyPlayerCarriedUpdate(player: Player, carriedInfo: GameConfig.PlayerCarriedInfo)
	--print("[NetMsg] FireNotifyPlayerCarriedUpdate for player", player.Name)
	notifyPlayerCarriedUpdateEvent:FireClient(player, carriedInfo)
end
function NetMsg.ConnectNotifyPlayerCarriedUpdate(callback: (carriedInfo: GameConfig.PlayerCarriedInfo) -> ())
	notifyPlayerCarriedUpdateEvent.OnClientEvent:Connect(callback)
end

--通知玩家货币更新
function NetMsg.FireNotifyPlayerCurrencyUpdate(player: Player, currencyType: number, totalAmount: number, lastChange: number, reason: number)
	notifyPlayerCurrencyUpdateEvent:FireClient(player, currencyType, totalAmount, lastChange, reason)
end

function NetMsg.ConnectNotifyPlayerCurrencyUpdate(callback: (currencyType: number, totalAmount: number, lastChange: number, reason: number) -> ())
	notifyPlayerCurrencyUpdateEvent.OnClientEvent:Connect(callback)
end

--客户端发送升级请求
function NetMsg.SendRequestUpgradeSkill(skillType: number, levelAdd: number?)
	requestUpgradeSkillEvent:FireServer(skillType, levelAdd or 1)
end

--服务端连接升级请求
function NetMsg.ConnectRequestUpgradeSkill(callback: (player: Player, skillType: number, levelAdd: number) -> ())
	requestUpgradeSkillEvent.OnServerEvent:Connect(callback)
end

--服务端通知技能等级更新
function NetMsg.FireNotifyPlayerSkillLevelUpdate(player: Player, skillType: number, level: number)
	notifyPlayerSkillLevelUpdateEvent:FireClient(player, skillType, level)
end

--客户端连接技能等级更新通知
function NetMsg.ConnectNotifyPlayerSkillLevelUpdate(callback: (skillType: number, level: number) -> ())
	notifyPlayerSkillLevelUpdateEvent.OnClientEvent:Connect(callback)
end

--客户端发送送礼请求
function NetMsg.FireRequestSendGift(targetPlayerId: number, brainrotInstanceId: string)
	print("[NetMsg] FireRequestSendGift to target", targetPlayerId, "brainrot", brainrotInstanceId)
	requestSendGiftEvent:FireServer(targetPlayerId, brainrotInstanceId)
end

function NetMsg.ConnectRequestSendGift(callback: (player: Player, targetPlayerId: number, brainrotInstanceId: string) -> ())
	requestSendGiftEvent.OnServerEvent:Connect(callback)
end

--服务端通知玩家收到送礼请求
function NetMsg.FireNotifyReceiveGiftRequest(player: Player, senderId: number, senderName: string, brainrotName: string, brainrotLevel: number)
	notifyReceiveGiftRequestEvent:FireClient(player, senderId, senderName, brainrotName, brainrotLevel)
end

function NetMsg.ConnectNotifyReceiveGiftRequest(callback: (senderId: number, senderName: string, brainrotName: string, brainrotLevel: number) -> ())
	notifyReceiveGiftRequestEvent.OnClientEvent:Connect(callback)
end

--客户端回应送礼请求
function NetMsg.FireRequestRespondGift(senderId: number, isAccepted: boolean)
	print("[NetMsg] FireRequestRespondGift to sender", senderId, "accepted", isAccepted)
	requestRespondGiftEvent:FireServer(senderId, isAccepted)
end

function NetMsg.ConnectRequestRespondGift(callback: (player: Player, senderId: number, isAccepted: boolean) -> ())
	requestRespondGiftEvent.OnServerEvent:Connect(callback)
end

--服务端通知送礼结果
function NetMsg.FireNotifyGiftResult(player: Player, isSuccess: boolean, message: string?)
	notifyGiftResultEvent:FireClient(player, isSuccess, message)
end

function NetMsg.ConnectNotifyGiftResult(callback: (isSuccess: boolean, message: string?) -> ())
	notifyGiftResultEvent.OnClientEvent:Connect(callback)
end

--服务端通知发件人打开确认弹窗
function NetMsg.FireNotifyShowGiftConfirm(player: Player, targetPlayerId: number, targetPlayerName: string, brainrotInstanceId: string, giftName: string)
	notifyShowGiftConfirmEvent:FireClient(player, targetPlayerId, targetPlayerName, brainrotInstanceId, giftName)
end

function NetMsg.ConnectNotifyShowGiftConfirm(callback: (targetPlayerId: number, targetPlayerName: string, brainrotInstanceId: string, giftName: string) -> ())
	notifyShowGiftConfirmEvent.OnClientEvent:Connect(callback)
end

-- 服务端通知玩家 Brainrot 背包队列更新
function NetMsg.FireNotifyBrainrotQueueUpdate(player: Player, queue: { GameConfig.BrainrotQueueItem })
	--print("[NetMsg] FireNotifyBrainrotQueueUpdate for player", player.Name, "count:", #queue)
	notifyBrainrotQueueUpdateEvent:FireClient(player, queue)
end

function NetMsg.ConnectNotifyBrainrotQueueUpdate(callback: (queue: { GameConfig.BrainrotQueueItem }) -> ())
	notifyBrainrotQueueUpdateEvent.OnClientEvent:Connect(callback)
end

-- 服务端通知客户端显示游戏提示
function NetMsg.FireNotifyShowGameTip(
	player: Player,
	tipContentSource: string,
	tweenType: number,
	tipContentKey: string?,
	tipContentArgs: { string }?,
	textColor: Color3?
)
	notifyShowGameTipEvent:FireClient(player, tipContentSource, tweenType, tipContentKey, tipContentArgs, textColor)
end

function NetMsg.ConnectNotifyShowGameTip(callback: (
	tipContentSource: string,
	tweenType: number,
	tipContentKey: string?,
	tipContentArgs: { string }?,
	textColor: Color3?
) -> ())
	notifyShowGameTipEvent.OnClientEvent:Connect(callback)
end

-- 服务端通知客户端开始飞行救援
function NetMsg.FireNotifyRescueStart(player: Player)
	notifyRescueStartEvent:FireClient(player)
end

function NetMsg.ConnectNotifyRescueStart(callback: () -> ())
	notifyRescueStartEvent.OnClientEvent:Connect(callback)
end

-- 客户端请求开启宝箱
function NetMsg.FireRequestOpenChest(uid: string)
	print("[NetMsg] FireRequestOpenChest", uid)
	requestOpenChestEvent:FireServer(uid)
end

function NetMsg.FireRequestOpenChestGrant(uid: string)
	requestOpenChestEvent:FireServer(uid, "grant")
end

function NetMsg.ConnectRequestOpenChest(callback: (player: Player, uid: string, action: string?) -> ())
	requestOpenChestEvent.OnServerEvent:Connect(function(player: Player, uid: any, action: any)
		if type(uid) ~= "string" then
			return
		end
		callback(player, uid, if type(action) == "string" then action else nil)
	end)
end

-- 服务端通知客户端宝箱开箱结果（权威结果）
function NetMsg.FireNotifyChestOpenResult(
	player: Player,
	uid: string,
	chestConfigId: number,
	chestLevel: number,
	finalBrainrotId: number,
	finalVariantId: number?
)
	notifyChestOpenResultEvent:FireClient(player, uid, chestConfigId, chestLevel, finalBrainrotId, finalVariantId)
end

function NetMsg.ConnectNotifyChestOpenResult(
	callback: (
		uid: string,
		chestConfigId: number,
		chestLevel: number,
		finalBrainrotId: number,
		finalVariantId: number?
	) -> ()
)
	notifyChestOpenResultEvent.OnClientEvent:Connect(callback)
end

-- 客户端请求重生
function NetMsg.FireRequestRebirth()
	print("[NetMsg] FireRequestRebirth")
	requestRebirthEvent:FireServer()
end

function NetMsg.ConnectRequestRebirth(callback: (player: Player) -> ())
	requestRebirthEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求付费重生
function NetMsg.FireRequestPaidRebirth()
	print("[NetMsg] FireRequestPaidRebirth")
	requestPaidRebirthEvent:FireServer()
end

function NetMsg.ConnectRequestPaidRebirth(callback: (player: Player) -> ())
	requestPaidRebirthEvent.OnServerEvent:Connect(callback)
end

-- 服务端广播地震开始/结束状态
function NetMsg.FireNotifyEarthquakeState(earthquakeId: number, isStart: boolean, duration: number, judgeCount: number)
	notifyEarthquakeStateEvent:FireAllClients(earthquakeId, isStart, duration, judgeCount)
end

function NetMsg.FireNotifyEarthquakeStateToPlayer(player: Player, earthquakeId: number, isStart: boolean, duration: number, judgeCount: number)
	notifyEarthquakeStateEvent:FireClient(player, earthquakeId, isStart, duration, judgeCount)
end

function NetMsg.ConnectNotifyEarthquakeState(callback: (earthquakeId: number, isStart: boolean, duration: number, judgeCount: number) -> ())
	notifyEarthquakeStateEvent.OnClientEvent:Connect(callback)
end

-- 服务端广播地震预警（距开始剩余秒数）
function NetMsg.FireNotifyEarthquakeWarning(earthquakeId: number, secondsUntilStart: number)
	notifyEarthquakeWarningEvent:FireAllClients(earthquakeId, secondsUntilStart)
end

function NetMsg.FireNotifyEarthquakeWarningToPlayer(player: Player, earthquakeId: number, secondsUntilStart: number)
	notifyEarthquakeWarningEvent:FireClient(player, earthquakeId, secondsUntilStart)
end

function NetMsg.ConnectNotifyEarthquakeWarning(callback: (earthquakeId: number, secondsUntilStart: number) -> ())
	notifyEarthquakeWarningEvent.OnClientEvent:Connect(callback)
end

-- 服务端广播本轮判定掉落结果
function NetMsg.FireNotifyEarthquakeJudgeDrop(earthquakeId: number, judgeIndex: number, droppedFloatBlocks: { any }, droppedPavedBricks: { any })
	notifyEarthquakeJudgeDropEvent:FireAllClients(earthquakeId, judgeIndex, droppedFloatBlocks, droppedPavedBricks)
end

function NetMsg.FireNotifyEarthquakeJudgeDropToPlayer(
	player: Player,
	earthquakeId: number,
	judgeIndex: number,
	droppedFloatBlocks: { any },
	droppedPavedBricks: { any }
)
	notifyEarthquakeJudgeDropEvent:FireClient(player, earthquakeId, judgeIndex, droppedFloatBlocks, droppedPavedBricks)
end

function NetMsg.ConnectNotifyEarthquakeJudgeDrop(
	callback: (earthquakeId: number, judgeIndex: number, droppedFloatBlocks: { any }, droppedPavedBricks: { any }) -> ()
)
	notifyEarthquakeJudgeDropEvent.OnClientEvent:Connect(callback)
end

-- 服务端广播地震回浮结果
function NetMsg.FireNotifyEarthquakeRecover(earthquakeId: number, recoverFloatBlocks: { any }, recoverPavedBricks: { any })
	notifyEarthquakeRecoverEvent:FireAllClients(earthquakeId, recoverFloatBlocks, recoverPavedBricks)
end

function NetMsg.ConnectNotifyEarthquakeRecover(callback: (earthquakeId: number, recoverFloatBlocks: { any }, recoverPavedBricks: { any }) -> ())
	notifyEarthquakeRecoverEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireNotifyGuideProgressInfo(player: Player, guideProgressInfo: GameConfig.GuideProgressSaveInfo)
	if notifyGuideProgressInfoEvent == nil then
		return
	end
	notifyGuideProgressInfoEvent:FireClient(player, guideProgressInfo)
end

function NetMsg.ConnectNotifyGuideProgressInfo(callback: (guideProgressInfo: GameConfig.GuideProgressSaveInfo) -> ())
	if notifyGuideProgressInfoEvent == nil then
		return
	end
	notifyGuideProgressInfoEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireRequestCompleteGuideStep(stepKey: string)
	if requestCompleteGuideStepEvent == nil then
		return
	end
	requestCompleteGuideStepEvent:FireServer(stepKey)
end

function NetMsg.ConnectRequestCompleteGuideStep(callback: (player: Player, stepKey: string) -> ())
	if requestCompleteGuideStepEvent == nil then
		return
	end
	requestCompleteGuideStepEvent.OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) ~= "string" then
			return
		end
		callback(player, payload)
	end)
end

function NetMsg.GetRequestWorkbenchManualEvent(): RemoteEvent?
	return requestWorkbenchManualEvent
end

function NetMsg.GetRequestPurchaseWorkbenchUpgradeEvent(): RemoteEvent?
	return requestPurchaseWorkbenchUpgradeEvent
end

function NetMsg.GetRequestPlaceChestOnWorkbenchSlotEvent(): RemoteEvent?
	return requestPlaceChestOnWorkbenchSlotEvent
end

function NetMsg.GetRequestPickupChestFromWorkbenchSlotEvent(): RemoteEvent?
	return requestPickupChestFromWorkbenchSlotEvent
end

function NetMsg.GetNotifyWorkbenchSlotsUpdateEvent(): RemoteEvent?
	return notifyWorkbenchSlotsUpdateEvent
end

function NetMsg.FireRequestWorkbenchManual(instanceKey: string)
	if requestWorkbenchManualEvent then
		requestWorkbenchManualEvent:FireServer(instanceKey)
	end
end

function NetMsg.FireRequestPurchaseWorkbenchUpgrade(upgradeRowId: number, workbenchSaveKey: string?)
	if requestPurchaseWorkbenchUpgradeEvent then
		if workbenchSaveKey ~= nil and workbenchSaveKey ~= "" then
			requestPurchaseWorkbenchUpgradeEvent:FireServer(upgradeRowId, workbenchSaveKey)
		else
			requestPurchaseWorkbenchUpgradeEvent:FireServer(upgradeRowId)
		end
	end
end

function NetMsg.FireRequestPlaceChestOnWorkbenchSlot(instanceKey: string, slotIndex: number, chestUid: string)
	if requestPlaceChestOnWorkbenchSlotEvent then
		requestPlaceChestOnWorkbenchSlotEvent:FireServer(instanceKey, slotIndex, chestUid)
	end
end

function NetMsg.FireRequestPickupChestFromWorkbenchSlot(instanceKey: string, slotIndex: number)
	if requestPickupChestFromWorkbenchSlotEvent then
		requestPickupChestFromWorkbenchSlotEvent:FireServer(instanceKey, slotIndex)
	end
end

function NetMsg.ConnectNotifyWorkbenchSlotsUpdate(callback: (instanceKey: string, payload: { [string]: any }) -> ())
	if notifyWorkbenchSlotsUpdateEvent == nil then
		return
	end
	notifyWorkbenchSlotsUpdateEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireNotifyJumpRunwayState(player: Player, payload: JumpRunwayStatePayload)
	if notifyJumpRunwayStateEvent == nil then
		return
	end
	notifyJumpRunwayStateEvent:FireClient(player, payload)
end

function NetMsg.ConnectNotifyJumpRunwayState(callback: (payload: JumpRunwayStatePayload) -> ())
	if notifyJumpRunwayStateEvent == nil then
		return
	end
	notifyJumpRunwayStateEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireRequestJumpRunwayInput(report: JumpRunwayInputReport)
	if requestJumpRunwayInputEvent == nil then
		return
	end
	-- 单参 FireServer(table)：与 Connect 端一致；服务端 JumpRunwayServerManager 会对别名/封装再归一化
	requestJumpRunwayInputEvent:FireServer(report)
end

function NetMsg.ConnectRequestJumpRunwayInput(callback: (player: Player, report: JumpRunwayInputReport) -> ())
	if requestJumpRunwayInputEvent == nil then
		return
	end
	requestJumpRunwayInputEvent.OnServerEvent:Connect(function(player: Player, payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		callback(player, payload :: JumpRunwayInputReport)
	end)
end

function NetMsg.JumpRunwayRemotesExist(): boolean
	return notifyJumpRunwayStateEvent ~= nil and requestJumpRunwayInputEvent ~= nil
end

-- JumpRunway LittleElfChest Reward
-- 在 Studio 的 ReplicatedStorage.RemoteEvents 下创建 `RequestJumpRunwayLittleElfChestReward`、`NotifyJumpRunwayLittleElfChestReward`
local warnedJumpRunwayLittleElfChestRemotesOnce = false

local function WarnJumpRunwayLittleElfChestRemotesMissingOnce()
	if warnedJumpRunwayLittleElfChestRemotesOnce then
		return
	end
	warnedJumpRunwayLittleElfChestRemotesOnce = true
	warn(
		"[NetMsg] RemoteEvents missing (RequestJumpRunwayLittleElfChestReward / RequestJumpRunwayLittleElfChestGrant / RequestJumpRunwayLittleElfChestStartCarry / NotifyJumpRunwayLittleElfChestReward). "
			.. "Create them under ReplicatedStorage.RemoteEvents."
	)
end

-- 客户端上报撞击：服务端 Roll 并 FireNotifyJumpRunwayLittleElfChestReward（仅此一次下行通知）
function NetMsg.FireRequestJumpRunwayLittleElfChestReward(chestConfigId: number)
	if requestJumpRunwayLittleElfChestRewardEvent == nil then
		WarnJumpRunwayLittleElfChestRemotesMissingOnce()
		return
	end
	requestJumpRunwayLittleElfChestRewardEvent:FireServer(chestConfigId)
end

function NetMsg.ConnectRequestJumpRunwayLittleElfChestReward(callback: (player: Player, chestConfigId: number) -> ())
	if requestJumpRunwayLittleElfChestRewardEvent == nil then
		WarnJumpRunwayLittleElfChestRemotesMissingOnce()
		return
	end
	requestJumpRunwayLittleElfChestRewardEvent.OnServerEvent:Connect(function(player: Player, payload: any)
		if typeof(payload) ~= "number" then
			return
		end
		callback(player, payload :: number)
	end)
end

-- 客户端开箱动画播完后请求服务端创建头顶携带态 brainrot
-- JumpRunway BestDistance：客户端上报当前沿轴距离，服务端判断是否更新最远记录
function NetMsg.FireRequestJumpRunwayBestDistance(distance: number)
	if requestJumpRunwayBestDistanceEvent == nil then
		warn("[NetMsg] RequestJumpRunwayBestDistance RemoteEvent missing. Create it under ReplicatedStorage.RemoteEvents.")
		return
	end
	requestJumpRunwayBestDistanceEvent:FireServer(distance)
end

function NetMsg.ConnectRequestJumpRunwayBestDistance(callback: (player: Player, distance: number) -> ())
	if requestJumpRunwayBestDistanceEvent == nil then
		return
	end
	requestJumpRunwayBestDistanceEvent.OnServerEvent:Connect(function(player: Player, payload: any)
		local distance = if typeof(payload) == "number" then payload :: number else nil
		if distance == nil then
			return
		end
		callback(player, distance)
	end)
end

function NetMsg.FireRequestJumpRunwayLittleElfChestStartCarry(brainrotId: number?, chestConfigId: number?)
	if requestJumpRunwayLittleElfChestStartCarryEvent == nil then
		WarnJumpRunwayLittleElfChestRemotesMissingOnce()
		return
	end
	requestJumpRunwayLittleElfChestStartCarryEvent:FireServer(brainrotId, chestConfigId)
end

function NetMsg.ConnectRequestJumpRunwayLittleElfChestStartCarry(callback: (player: Player, brainrotId: number?, chestConfigId: number?) -> ())
	if requestJumpRunwayLittleElfChestStartCarryEvent == nil then
		WarnJumpRunwayLittleElfChestRemotesMissingOnce()
		return
	end
	requestJumpRunwayLittleElfChestStartCarryEvent.OnServerEvent:Connect(function(player: Player, brainrotId: any, chestConfigId: any)
		local resolvedBrainrotId = if typeof(brainrotId) == "number" then brainrotId :: number else nil
		local resolvedChestConfigId = if typeof(chestConfigId) == "number" then chestConfigId :: number else nil
		callback(player, resolvedBrainrotId, resolvedChestConfigId)
	end)
end

-- 客户端跑回 StartTrigger 后请求服务端将 pending brainrot 入背包
function NetMsg.FireRequestJumpRunwayLittleElfChestGrant()
	if requestJumpRunwayLittleElfChestGrantEvent == nil then
		WarnJumpRunwayLittleElfChestRemotesMissingOnce()
		return
	end
	requestJumpRunwayLittleElfChestGrantEvent:FireServer()
end

function NetMsg.ConnectRequestJumpRunwayLittleElfChestGrant(callback: (player: Player) -> ())
	if requestJumpRunwayLittleElfChestGrantEvent == nil then
		WarnJumpRunwayLittleElfChestRemotesMissingOnce()
		return
	end
	requestJumpRunwayLittleElfChestGrantEvent.OnServerEvent:Connect(function(player: Player)
		callback(player)
	end)
end

-- 服务端通知客户端 JumpRunway 小精灵宝箱开箱奖励结果
function NetMsg.FireNotifyJumpRunwayLittleElfChestReward(player: Player, brainrotId: number, chestConfigId: number, chestLevel: number, variantId: number)
	if notifyJumpRunwayLittleElfChestRewardEvent == nil then
		WarnJumpRunwayLittleElfChestRemotesMissingOnce()
		return
	end
	notifyJumpRunwayLittleElfChestRewardEvent:FireClient(player, brainrotId, chestConfigId, chestLevel, variantId)
end

function NetMsg.ConnectNotifyJumpRunwayLittleElfChestReward(callback: (brainrotId: number, chestConfigId: number, chestLevel: number, variantId: number) -> ())
	if notifyJumpRunwayLittleElfChestRewardEvent == nil then
		WarnJumpRunwayLittleElfChestRemotesMissingOnce()
		return
	end
	notifyJumpRunwayLittleElfChestRewardEvent.OnClientEvent:Connect(callback)
end

-- ExEquip: 客户端请求购买器材
function NetMsg.FireRequestBuyExEquip(equipId: number)
	if requestBuyExEquipEvent == nil then
		return
	end
	requestBuyExEquipEvent:FireServer(equipId)
end

function NetMsg.ConnectRequestBuyExEquip(callback: (player: Player, equipId: number) -> ())
	if requestBuyExEquipEvent == nil then
		return
	end
	requestBuyExEquipEvent.OnServerEvent:Connect(callback)
end

-- ExEquip: 客户端请求 R 币购买器材
function NetMsg.FireRequestBuyExEquipPaid(equipId: number)
	if requestBuyExEquipPaidEvent == nil then
		return
	end
	requestBuyExEquipPaidEvent:FireServer(equipId)
end

function NetMsg.ConnectRequestBuyExEquipPaid(callback: (player: Player, equipId: number) -> ())
	if requestBuyExEquipPaidEvent == nil then
		return
	end
	requestBuyExEquipPaidEvent.OnServerEvent:Connect(callback)
end

-- ExEquip: 客户端请求装备器材
function NetMsg.FireRequestUpdateExEquipUsing(equipId: number)
	if requestUpdateExEquipUsingEvent == nil then
		return
	end
	requestUpdateExEquipUsingEvent:FireServer(equipId)
end

function NetMsg.ConnectRequestUpdateExEquipUsing(callback: (player: Player, equipId: number) -> ())
	if requestUpdateExEquipUsingEvent == nil then
		return
	end
	requestUpdateExEquipUsingEvent.OnServerEvent:Connect(callback)
end

-- ExEquip: 服务端通知客户端器材库存更新
function NetMsg.FireNotifyPlayerExEquipInventoryUpdate(player: Player, inventory: GameConfig.ExEquipInventory)
	if notifyPlayerExEquipInventoryUpdateEvent == nil then
		return
	end
	notifyPlayerExEquipInventoryUpdateEvent:FireClient(player, inventory)
end

function NetMsg.ConnectNotifyPlayerExEquipInventoryUpdate(callback: (inventory: GameConfig.ExEquipInventory) -> ())
	if notifyPlayerExEquipInventoryUpdateEvent == nil then
		return
	end
	notifyPlayerExEquipInventoryUpdateEvent.OnClientEvent:Connect(callback)
end

-- ExEquip: 客户端请求领取群组奖励
function NetMsg.FireRequestClaimGroupReward(isInGroup: boolean)
	if requestClaimGroupRewardEvent == nil then
		return
	end
	requestClaimGroupRewardEvent:FireServer(isInGroup)
end

function NetMsg.ConnectRequestClaimGroupReward(callback: (player: Player, isInGroup: boolean) -> ())
	if requestClaimGroupRewardEvent == nil then
		return
	end
	requestClaimGroupRewardEvent.OnServerEvent:Connect(callback)
end

-- 锻炼模式：客户端请求开始锻炼
function NetMsg.FireRequestStartExercise(equipId: number)
	if requestStartExerciseEvent == nil then
		return
	end
	requestStartExerciseEvent:FireServer(equipId)
end

function NetMsg.ConnectRequestStartExercise(callback: (player: Player, equipId: number) -> ())
	if requestStartExerciseEvent == nil then
		return
	end
	requestStartExerciseEvent.OnServerEvent:Connect(callback)
end

-- 锻炼模式：客户端请求结束锻炼
function NetMsg.FireRequestStopExercise()
	if requestStopExerciseEvent == nil then
		return
	end
	requestStopExerciseEvent:FireServer()
end

function NetMsg.ConnectRequestStopExercise(callback: (player: Player) -> ())
	if requestStopExerciseEvent == nil then
		return
	end
	requestStopExerciseEvent.OnServerEvent:Connect(callback)
end

-- 锻炼模式：客户端请求点击奖励
function NetMsg.FireRequestExerciseClickReward()
	if requestExerciseClickRewardEvent == nil then
		return
	end
	requestExerciseClickRewardEvent:FireServer()
end

function NetMsg.ConnectRequestExerciseClickReward(callback: (player: Player) -> ())
	if requestExerciseClickRewardEvent == nil then
		return
	end
	requestExerciseClickRewardEvent.OnServerEvent:Connect(callback)
end

-- 锻炼模式：服务端通知开始锻炼
function NetMsg.FireNotifyExerciseStart(player: Player, equipId: number)
	if notifyExerciseStartEvent == nil then
		return
	end
	notifyExerciseStartEvent:FireClient(player, equipId)
end

function NetMsg.ConnectNotifyExerciseStart(callback: (equipId: number) -> ())
	if notifyExerciseStartEvent == nil then
		return
	end
	notifyExerciseStartEvent.OnClientEvent:Connect(callback)
end

-- 锻炼模式：服务端通知结束锻炼
function NetMsg.FireNotifyExerciseEnd(player: Player)
	if notifyExerciseEndEvent == nil then
		return
	end
	notifyExerciseEndEvent:FireClient(player)
end

function NetMsg.ConnectNotifyExerciseEnd(callback: () -> ())
	if notifyExerciseEndEvent == nil then
		return
	end
	notifyExerciseEndEvent.OnClientEvent:Connect(callback)
end

-- Jetpack: 客户端请求购买火箭背包
local requestBuyJetpackEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestBuyJetpack") :: RemoteEvent?
local requestBuyJetpackPaidEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestBuyJetpackPaid") :: RemoteEvent?
local requestUpdateJetpackUsingEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestUpdateJetpackUsing") :: RemoteEvent?
local notifyPlayerJetpackInventoryUpdateEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("NotifyPlayerJetpackInventoryUpdate") :: RemoteEvent?
local requestClaimJetpackGroupRewardEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("RequestClaimJetpackGroupReward") :: RemoteEvent?

-- JumpPower 更新（服务端→客户端）
function NetMsg.FireNotifyPlayerJumpPowerUpdate(player: Player, jumpPowerInfo: GameConfig.JumpPowerInfo, addExp: number)
	if notifyJumpPowerUpdateEvent == nil then
		return
	end
	notifyJumpPowerUpdateEvent:FireClient(player, jumpPowerInfo, addExp)
end

function NetMsg.ConnectNotifyPlayerJumpPowerUpdate(callback: (jumpPowerInfo: GameConfig.JumpPowerInfo, addExp: number) -> ())
	if notifyJumpPowerUpdateEvent == nil then
		return
	end
	notifyJumpPowerUpdateEvent.OnClientEvent:Connect(callback)
end

-- Jetpack: 客户端请求购买火箭背包
function NetMsg.FireRequestBuyJetpack(jetpackId: number)
	if requestBuyJetpackEvent == nil then
		return
	end
	requestBuyJetpackEvent:FireServer(jetpackId)
end

function NetMsg.ConnectRequestBuyJetpack(callback: (player: Player, jetpackId: number) -> ())
	if requestBuyJetpackEvent == nil then
		return
	end
	requestBuyJetpackEvent.OnServerEvent:Connect(callback)
end

-- Jetpack: 客户端请求 R 币购买火箭背包
function NetMsg.FireRequestBuyJetpackPaid(jetpackId: number)
	if requestBuyJetpackPaidEvent == nil then
		return
	end
	requestBuyJetpackPaidEvent:FireServer(jetpackId)
end

function NetMsg.ConnectRequestBuyJetpackPaid(callback: (player: Player, jetpackId: number) -> ())
	if requestBuyJetpackPaidEvent == nil then
		return
	end
	requestBuyJetpackPaidEvent.OnServerEvent:Connect(callback)
end

-- Jetpack: 客户端请求装备火箭背包
function NetMsg.FireRequestUpdateJetpackUsing(jetpackId: number)
	if requestUpdateJetpackUsingEvent == nil then
		return
	end
	requestUpdateJetpackUsingEvent:FireServer(jetpackId)
end

function NetMsg.ConnectRequestUpdateJetpackUsing(callback: (player: Player, jetpackId: number) -> ())
	if requestUpdateJetpackUsingEvent == nil then
		return
	end
	requestUpdateJetpackUsingEvent.OnServerEvent:Connect(callback)
end

-- Jetpack: 服务端通知客户端火箭背包库存更新
function NetMsg.FireNotifyPlayerJetpackInventoryUpdate(player: Player, inventory: GameConfig.JetpackInventory)
	if notifyPlayerJetpackInventoryUpdateEvent == nil then
		return
	end
	notifyPlayerJetpackInventoryUpdateEvent:FireClient(player, inventory)
end

function NetMsg.ConnectNotifyPlayerJetpackInventoryUpdate(callback: (inventory: GameConfig.JetpackInventory) -> ())
	if notifyPlayerJetpackInventoryUpdateEvent == nil then
		return
	end
	notifyPlayerJetpackInventoryUpdateEvent.OnClientEvent:Connect(callback)
end

-- Jetpack: 客户端请求领取群组火箭背包奖励
function NetMsg.FireRequestClaimJetpackGroupReward(isInGroup: boolean)
	if requestClaimJetpackGroupRewardEvent == nil then
		return
	end
	requestClaimJetpackGroupRewardEvent:FireServer(isInGroup)
end

function NetMsg.ConnectRequestClaimJetpackGroupReward(callback: (player: Player, isInGroup: boolean) -> ())
	if requestClaimJetpackGroupRewardEvent == nil then
		return
	end
	requestClaimJetpackGroupRewardEvent.OnServerEvent:Connect(callback)
end

return NetMsg
