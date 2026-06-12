--!strict
local ClientMsg = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local bindableEventsFolder: Folder = replicatedStorage:WaitForChild("BindableEvents") :: Folder
local closeWindowEvent: BindableEvent = bindableEventsFolder:FindFirstChild("CloseWindow") :: BindableEvent
local localPlayerInfoInitEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerInfoInit") :: BindableEvent
local otherPlayerInfoInitEvent: BindableEvent = bindableEventsFolder:FindFirstChild("OtherPlayerInfoInit") :: BindableEvent
local localPlayerAcquiredGamePassEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerAcquiredGamePass") :: BindableEvent
local localPlayerInventoryUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerInventoryUpdate") :: BindableEvent
local localPlayerCarriedUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerCarriedUpdate") :: BindableEvent
local playerHomeInfoUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("PlayerHomeInfoUpdate") :: BindableEvent
local allPlayersModelYieldsUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("AllPlayersModelYieldsUpdate") :: BindableEvent
local localPlayerCurrencyUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerCurrencyUpdate") :: BindableEvent
local localPlayerSkillLevelUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerSkillLevelUpdate") :: BindableEvent
local showGameTipEvent: BindableEvent = bindableEventsFolder:FindFirstChild("ShowGameTip") :: BindableEvent
local showAddRewardsTipEvent: BindableEvent = bindableEventsFolder:FindFirstChild("ShowAddRewardsTip") :: BindableEvent
local currentGuideTypeChangedEvent: BindableEvent = bindableEventsFolder:FindFirstChild("CurrentGuideTypeChanged") :: BindableEvent

-- Gifting UI events
local showGiftConfirmPopupEvent: BindableEvent = bindableEventsFolder:FindFirstChild("ShowGiftConfirmPopup") :: BindableEvent
local showGiftRequestPopupEvent: BindableEvent = bindableEventsFolder:FindFirstChild("ShowGiftRequestPopup") :: BindableEvent
local showTopTipTextEvent: BindableEvent = bindableEventsFolder:FindFirstChild("ShowTopTipText") :: BindableEvent
local brainrotQueueUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("BrainrotQueueUpdate") :: BindableEvent
local localPlayerExEquipInventoryUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerExEquipInventoryUpdate") :: BindableEvent
local localPlayerJetpackInventoryUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerJetpackInventoryUpdate") :: BindableEvent
local earthquakeUiUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("EarthquakeUiUpdate") :: BindableEvent
local localPlayerJumpPowerUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerJumpPowerUpdate") :: BindableEvent
local jumpRunWayRefreshStatsEvent: BindableEvent = bindableEventsFolder:FindFirstChild("JumpRunWayRefreshStats") :: BindableEvent
local jumpRunWayShowRatingTierEvent: BindableEvent = bindableEventsFolder:FindFirstChild("JumpRunWayShowRatingTier") :: BindableEvent
local jumpRunWayShowMissEvent: BindableEvent = bindableEventsFolder:FindFirstChild("JumpRunWayShowMiss") :: BindableEvent
local jumpRunWayShowNewRecordTipEvent: BindableEvent = bindableEventsFolder:FindFirstChild("JumpRunWayShowNewRecordTip") :: BindableEvent

local function EnsureBindableEvent(eventName: string): BindableEvent
	local existing = bindableEventsFolder:FindFirstChild(eventName)
	if existing and existing:IsA("BindableEvent") then
		return existing
	end
	local created = Instance.new("BindableEvent")
	created.Name = eventName
	created.Parent = bindableEventsFolder
	return created
end

local localPlayerBuffInfoUpdateEvent: BindableEvent = EnsureBindableEvent("LocalPlayerBuffInfoUpdate")
local jumpRunWayEnterEscapeHudModeEvent: BindableEvent =
	EnsureBindableEvent("JumpRunWayEnterEscapeHudMode")
local jumpRunWayStartEscapeRedScreenEvent: BindableEvent =
	EnsureBindableEvent("JumpRunWayStartEscapeRedScreen")
local jumpRunWayStopEscapeRedScreenEvent: BindableEvent =
	EnsureBindableEvent("JumpRunWayStopEscapeRedScreen")
local localPlayerClaimedGroupRewardEvent: BindableEvent = EnsureBindableEvent("LocalPlayerClaimedGroupReward")
local localPlayerFriendsPlayingSameGameCountChangedEvent: BindableEvent =
	EnsureBindableEvent("LocalPlayerFriendsPlayingSameGameCountChanged")
local localPlayerJumpRunwayBestDistanceUpdateEvent: BindableEvent =
	EnsureBindableEvent("LocalPlayerJumpRunwayBestDistanceUpdate")

--关闭窗口事件
function ClientMsg.FireCloseWindow(windowName: string)
	closeWindowEvent:Fire(windowName)
end

function ClientMsg.ConnectCloseWindow(callback: (windowName: string) -> ())
	closeWindowEvent.Event:Connect(callback)
end

--自己的玩家信息初始化事件
function ClientMsg.FireLocalPlayerInfoInit()
	localPlayerInfoInitEvent:Fire()
end

function ClientMsg.ConnectLocalPlayerInfoInit(callback: () -> ())
	localPlayerInfoInitEvent.Event:Connect(callback)
end

--其他玩家的信息初始化事件
function ClientMsg.FireOtherPlayerInfoInit(playerId: number)
	otherPlayerInfoInitEvent:Fire(playerId)
end

function ClientMsg.ConnectOtherPlayerInfoInit(callback: (playerId: number) -> ())
	otherPlayerInfoInitEvent.Event:Connect(callback)
end

--自己获得了通行证
function ClientMsg.FireLocalPlayerAcquiredGamePass(gamePassId: number)
	localPlayerAcquiredGamePassEvent:Fire(gamePassId)
end

function ClientMsg.ConnectLocalPlayerAcquiredGamePass(callback: (gamePassId: number) -> ())
	localPlayerAcquiredGamePassEvent.Event:Connect(callback)
end

--本地玩家库存更新
function ClientMsg.FireLocalPlayerInventoryUpdate(inventoryInfo: GameConfig.PlayerInventorySaveInfo)
	localPlayerInventoryUpdateEvent:Fire(inventoryInfo)
end

function ClientMsg.ConnectLocalPlayerInventoryUpdate(callback: (inventoryInfo: GameConfig.PlayerInventorySaveInfo) -> ())
	localPlayerInventoryUpdateEvent.Event:Connect(callback)
end

--本地玩家搬运信息更新
function ClientMsg.FireLocalPlayerCarriedUpdate(carriedInfo: GameConfig.PlayerCarriedInfo)
	localPlayerCarriedUpdateEvent:Fire(carriedInfo)
end

function ClientMsg.ConnectLocalPlayerCarriedUpdate(callback: (carriedInfo: GameConfig.PlayerCarriedInfo) -> ())
	localPlayerCarriedUpdateEvent.Event:Connect(callback)
end

--玩家家园信息更新
function ClientMsg.FirePlayerHomeInfoUpdate(playerId: number, homeSlot: string, homeInfo: any, rebirthLevel: number?)
	playerHomeInfoUpdateEvent:Fire(playerId, homeSlot, homeInfo, rebirthLevel)
end

function ClientMsg.ConnectPlayerHomeInfoUpdate(callback: (playerId: number, homeSlot: string, homeInfo: any, rebirthLevel: number?) -> ())
	playerHomeInfoUpdateEvent.Event:Connect(callback)
end

--所有玩家模型收益更新
function ClientMsg.FireAllPlayersModelYieldsUpdate(allYields: { [string]: { [string]: number } })
	allPlayersModelYieldsUpdateEvent:Fire(allYields)
end

function ClientMsg.ConnectAllPlayersModelYieldsUpdate(callback: (allYields: { [string]: { [string]: number } }) -> ())
	allPlayersModelYieldsUpdateEvent.Event:Connect(callback)
end

--本地玩家货币更新
function ClientMsg.FireLocalPlayerCurrencyUpdate()
	localPlayerCurrencyUpdateEvent:Fire()
end

function ClientMsg.ConnectLocalPlayerCurrencyUpdate(callback: () -> ())
	localPlayerCurrencyUpdateEvent.Event:Connect(callback)
end

--显示游戏提示
function ClientMsg.FireShowGameTip(tipContentSource: string, tweenType: number, tipContentKey: string?, tipContentArgs: {string}?, textColor: Color3?)
	showGameTipEvent:Fire(tipContentSource, tweenType, tipContentKey, tipContentArgs, textColor)
end

function ClientMsg.ConnectShowGameTip(callback: (tipContentSource: string, tweenType: number,
	tipContentKey: string?, tipContentArgs: {string}?, textColor: Color3?) -> ())
	showGameTipEvent.Event:Connect(callback)
end

--显示获得奖励提示
function ClientMsg.FireShowAddRewardsTip(rewardInfoList: {GameConfig.RewardInfo})
	showAddRewardsTipEvent:Fire(rewardInfoList)
end

function ClientMsg.ConnectShowAddRewardsTip(callback: (rewardInfoList: {GameConfig.RewardInfo}) -> ())
	showAddRewardsTipEvent.Event:Connect(callback)
end

--当前引导类型改变
function ClientMsg.FireCurrentGuideTypeChanged()
	currentGuideTypeChangedEvent:Fire()
end

function ClientMsg.ConnectCurrentGuideTypeChanged(callback: () -> ())
	currentGuideTypeChangedEvent.Event:Connect(callback)
end

--触发本地玩家技能等级更新
function ClientMsg.FireLocalPlayerSkillLevelUpdate(skillType: number, level: number)
	localPlayerSkillLevelUpdateEvent:Fire(skillType, level)
end

--连接本地玩家技能等级更新
function ClientMsg.ConnectLocalPlayerSkillLevelUpdate(callback: (skillType: number, level: number) -> ())
	localPlayerSkillLevelUpdateEvent.Event:Connect(callback)
end

--显示发送礼物确认弹窗
function ClientMsg.FireShowGiftConfirmPopup(targetPlayerId: number, targetPlayerName: string, brainrotInstanceId: string, giftName: string)
	showGiftConfirmPopupEvent:Fire(targetPlayerId, targetPlayerName, brainrotInstanceId, giftName)
end

function ClientMsg.ConnectShowGiftConfirmPopup(callback: (targetPlayerId: number, targetPlayerName: string, brainrotInstanceId: string, giftName: string) -> ())
	showGiftConfirmPopupEvent.Event:Connect(callback)
end

--显示收到礼物请求弹窗
function ClientMsg.FireShowGiftRequestPopup(senderId: number, senderName: string, brainrotName: string, brainrotLevel: number)
	showGiftRequestPopupEvent:Fire(senderId, senderName, brainrotName, brainrotLevel)
end

function ClientMsg.ConnectShowGiftRequestPopup(callback: (senderId: number, senderName: string, brainrotName: string, brainrotLevel: number) -> ())
	showGiftRequestPopupEvent.Event:Connect(callback)
end

--显示头顶UI提示
function ClientMsg.FireShowTopTipText(textSource: string, color: Color3, duration: number, args: {string}?, key: string?)
	showTopTipTextEvent:Fire(textSource, color, duration, args, key)
end

function ClientMsg.ConnectShowTopTipText(callback: (textSource: string, color: Color3, duration: number, args: {string}?, key: string?) -> ())
	showTopTipTextEvent.Event:Connect(callback)
end

-- 地震 UI：phase 为 "warning" | "active" | "hide"；countdownSeconds 为预警距开始剩余秒数，或地震进行中剩余时长（秒）
function ClientMsg.FireEarthquakeUiUpdate(phase: string, countdownSeconds: number?)
	earthquakeUiUpdateEvent:Fire(phase, countdownSeconds)
end

function ClientMsg.ConnectEarthquakeUiUpdate(callback: (phase: string, countdownSeconds: number?) -> ())
	earthquakeUiUpdateEvent.Event:Connect(callback)
end

-- Brainrot 背包队列更新
function ClientMsg.FireBrainrotQueueUpdate(queue: { GameConfig.BrainrotQueueItem })
	brainrotQueueUpdateEvent:Fire(queue)
end

function ClientMsg.ConnectBrainrotQueueUpdate(callback: (queue: { GameConfig.BrainrotQueueItem }) -> ())
	brainrotQueueUpdateEvent.Event:Connect(callback)
end

-- 本地玩家锻炼器材库存更新
function ClientMsg.FireLocalPlayerExEquipInventoryUpdate(inventory: GameConfig.ExEquipInventory)
	if localPlayerExEquipInventoryUpdateEvent then
		localPlayerExEquipInventoryUpdateEvent:Fire(inventory)
	end
end

function ClientMsg.ConnectLocalPlayerExEquipInventoryUpdate(callback: (inventory: GameConfig.ExEquipInventory) -> ())
	if localPlayerExEquipInventoryUpdateEvent then
		localPlayerExEquipInventoryUpdateEvent.Event:Connect(callback)
	end
end

-- 本地玩家火箭背包库存更新
function ClientMsg.FireLocalPlayerJetpackInventoryUpdate(inventory: GameConfig.JetpackInventory)
	if localPlayerJetpackInventoryUpdateEvent then
		localPlayerJetpackInventoryUpdateEvent:Fire(inventory)
	end
end

function ClientMsg.ConnectLocalPlayerJetpackInventoryUpdate(callback: (inventory: GameConfig.JetpackInventory) -> ())
	if localPlayerJetpackInventoryUpdateEvent then
		localPlayerJetpackInventoryUpdateEvent.Event:Connect(callback)
	end
end

function ClientMsg.FireLocalPlayerBuffInfoUpdate(buffInfo: GameConfig.BuffInfo, grantBuffId: number?, shopBundleId: number?)
	localPlayerBuffInfoUpdateEvent:Fire(buffInfo, grantBuffId, shopBundleId)
end

function ClientMsg.ConnectLocalPlayerBuffInfoUpdate(callback: (buffInfo: GameConfig.BuffInfo, grantBuffId: number?, shopBundleId: number?) -> ())
	localPlayerBuffInfoUpdateEvent.Event:Connect(callback)
end

function ClientMsg.FireLocalPlayerFriendsPlayingSameGameCountChanged(friendsPlayingSameGameCount: number)
	localPlayerFriendsPlayingSameGameCountChangedEvent:Fire(friendsPlayingSameGameCount)
end

function ClientMsg.ConnectLocalPlayerFriendsPlayingSameGameCountChanged(callback: (friendsPlayingSameGameCount: number) -> ())
	localPlayerFriendsPlayingSameGameCountChangedEvent.Event:Connect(callback)
end

-- JumpPower 更新
function ClientMsg.FireLocalPlayerJumpPowerUpdate(jumpPowerInfo: GameConfig.JumpPowerInfo, addExp: number)
	if localPlayerJumpPowerUpdateEvent then
		localPlayerJumpPowerUpdateEvent:Fire(jumpPowerInfo, addExp)
	end
end

function ClientMsg.ConnectLocalPlayerJumpPowerUpdate(callback: (jumpPowerInfo: GameConfig.JumpPowerInfo, addExp: number) -> ())
	if localPlayerJumpPowerUpdateEvent then
		localPlayerJumpPowerUpdateEvent.Event:Connect(callback)
	end
end

-- 跑道 HUD：刷新距离/燃料/实时速度
function ClientMsg.FireJumpRunWayRefreshStats(
	distanceStuds: number,
	currentFuel: number,
	maxFuel: number,
	fuelVisible: boolean,
	distanceVisible: boolean,
	horizontalSpeed: number?
)
	if jumpRunWayRefreshStatsEvent then
		jumpRunWayRefreshStatsEvent:Fire(distanceStuds, currentFuel, maxFuel, fuelVisible, distanceVisible, horizontalSpeed)
	end
end

function ClientMsg.ConnectJumpRunWayRefreshStats(callback: (
	distanceStuds: number,
	currentFuel: number,
	maxFuel: number,
	fuelVisible: boolean,
	distanceVisible: boolean,
	horizontalSpeed: number?
) -> ())
	if jumpRunWayRefreshStatsEvent then
		jumpRunWayRefreshStatsEvent.Event:Connect(callback)
	end
end

-- 跑道 HUD：评级动画
function ClientMsg.FireJumpRunWayShowRatingTier(tier: number)
	if jumpRunWayShowRatingTierEvent then
		jumpRunWayShowRatingTierEvent:Fire(tier)
	end
end

function ClientMsg.ConnectJumpRunWayShowRatingTier(callback: (tier: number) -> ())
	if jumpRunWayShowRatingTierEvent then
		jumpRunWayShowRatingTierEvent.Event:Connect(callback)
	end
end

-- 跑道 HUD：Miss 动画
function ClientMsg.FireJumpRunWayShowMiss()
	if jumpRunWayShowMissEvent then
		jumpRunWayShowMissEvent:Fire()
	end
end

function ClientMsg.ConnectJumpRunWayShowMiss(callback: () -> ())
	if jumpRunWayShowMissEvent then
		jumpRunWayShowMissEvent.Event:Connect(callback)
	end
end

-- 跑道 HUD：新纪录 Tip
function ClientMsg.FireJumpRunWayShowNewRecordTip()
	if jumpRunWayShowNewRecordTipEvent then
		jumpRunWayShowNewRecordTipEvent:Fire()
	end
end

function ClientMsg.ConnectJumpRunWayShowNewRecordTip(callback: () -> ())
	if jumpRunWayShowNewRecordTipEvent then
		jumpRunWayShowNewRecordTipEvent.Event:Connect(callback)
	end
end

-- 跑道逃生：隐藏 HUD，保留窗口实例
function ClientMsg.FireJumpRunWayEnterEscapeHudMode()
	jumpRunWayEnterEscapeHudModeEvent:Fire()
end

function ClientMsg.ConnectJumpRunWayEnterEscapeHudMode(callback: () -> ())
	jumpRunWayEnterEscapeHudModeEvent.Event:Connect(callback)
end

-- 跑道逃生：镜头序列结束后启动红屏闪烁
function ClientMsg.FireJumpRunWayStartEscapeRedScreen()
	jumpRunWayStartEscapeRedScreenEvent:Fire()
end

function ClientMsg.ConnectJumpRunWayStartEscapeRedScreen(callback: () -> ())
	jumpRunWayStartEscapeRedScreenEvent.Event:Connect(callback)
end

-- 跑道逃生：停止红屏并恢复 HUD
function ClientMsg.FireJumpRunWayStopEscapeRedScreen()
	jumpRunWayStopEscapeRedScreenEvent:Fire()
end

function ClientMsg.ConnectJumpRunWayStopEscapeRedScreen(callback: () -> ())
	jumpRunWayStopEscapeRedScreenEvent.Event:Connect(callback)
end

function ClientMsg.FireLocalPlayerClaimedGroupReward()
	localPlayerClaimedGroupRewardEvent:Fire()
end

function ClientMsg.ConnectLocalPlayerClaimedGroupReward(callback: () -> ())
	localPlayerClaimedGroupRewardEvent.Event:Connect(callback)
end

function ClientMsg.FireLocalPlayerJumpRunwayBestDistanceUpdate(distance: number)
	localPlayerJumpRunwayBestDistanceUpdateEvent:Fire(distance)
end

function ClientMsg.ConnectLocalPlayerJumpRunwayBestDistanceUpdate(callback: (distance: number) -> ())
	localPlayerJumpRunwayBestDistanceUpdateEvent.Event:Connect(callback)
end

return ClientMsg
