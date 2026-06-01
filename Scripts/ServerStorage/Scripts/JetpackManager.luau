--!strict
local JetpackManager = {}

local marketplaceService: MarketplaceService = game:GetService("MarketplaceService")
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local AnalyticsTool = require(serverScripts:FindFirstChild("AnalyticsTool"))

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

local LOG_PREFIX = "[JetpackManager]"

local function LogInfo(message: string)
	print(string.format("%s %s", LOG_PREFIX, message))
end

local function CanAffordJetpack(playerInfo: GameConfig.PlayerInfo, jetpackData: GameConfig.JetpackData): boolean
	local coinKey = tostring(GameConfig.CurrencyType.Coin)
	local currentCoins = playerInfo.currencies[coinKey] or 0
	local coinCost = jetpackData.costCoin

	if jetpackData.costType == GameConfig.CostType.Coin or jetpackData.costType == GameConfig.CostType.CoinOrRb then
		return currentCoins >= coinCost
	end
	return false
end

local function SpendJetpackCost(player: Player, jetpackData: GameConfig.JetpackData)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local coinKey = tostring(GameConfig.CurrencyType.Coin)
	local currentCoins = playerInfo.currencies[coinKey] or 0
	local coinCost = jetpackData.costCoin

	if
		(jetpackData.costType == GameConfig.CostType.Coin or jetpackData.costType == GameConfig.CostType.CoinOrRb)
		and currentCoins >= coinCost
	then
		ServerGameInfo.UpdatePlayerCurrency(player, GameConfig.CurrencyType.Coin, -coinCost, GameConfig.ItemCountChangeReason.GainFromPurchase)
	end
end

local function GetMoneyCount(playerInfo: GameConfig.PlayerInfo): number
	return playerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
end

-- 处理客户端购买火箭背包请求
function JetpackManager.OnRequestBuyJetpack(player: Player, jetpackId: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local jetpackData = GameConfig.JetpackDataMap[jetpackId]
	if jetpackData == nil then
		warn(string.format("%s Jetpack data not found for id: %d", LOG_PREFIX, jetpackId))
		return
	end

	local jetpackIdStr = tostring(jetpackId)
	if playerInfo.jetpackInventory.ownedList[jetpackIdStr] then
		LogInfo(string.format("BuyRejected userId=%d reason=already_owned jetpackId=%d", player.UserId, jetpackId))
		return
	end

	if CanAffordJetpack(playerInfo, jetpackData) then
		LogInfo(string.format("BuyAccepted userId=%d jetpackId=%d coinCost=%d costType=%d", player.UserId, jetpackId, jetpackData.costCoin, jetpackData.costType))
		SpendJetpackCost(player, jetpackData)
		-- 添加火箭背包
		ServerGameInfo.AddJetpackToInventory(player, jetpackIdStr)
		-- 自动装备
		JetpackManager.OnRequestUpdateJetpackUsing(player, jetpackId)
		AnalyticsTool.LogJetpackGet(player, jetpackId, GetMoneyCount(playerInfo), 0)
	else
		local rejectReason = "insufficient_currency"
		if jetpackData.costType == GameConfig.CostType.Rb then
			rejectReason = "rb_purchase_only"
		elseif jetpackData.costType == GameConfig.CostType.GroupReward then
			rejectReason = "group_reward_only"
		end
		LogInfo(string.format("BuyRejected userId=%d reason=%s jetpackId=%d", player.UserId, rejectReason, jetpackId))
	end
end

function JetpackManager.OnRequestBuyJetpackPaid(player: Player, jetpackId: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local jetpackData = GameConfig.JetpackDataMap[jetpackId]
	if jetpackData == nil or jetpackData.productId <= 0 then
		warn(string.format("%s PaidBuyRejected userId=%d reason=invalid_product jetpackId=%d", LOG_PREFIX, player.UserId, jetpackId))
		return
	end

	if playerInfo.jetpackInventory.ownedList[tostring(jetpackId)] then
		LogInfo(string.format("PaidBuyRejected userId=%d reason=already_owned jetpackId=%d", player.UserId, jetpackId))
		return
	end

	if not ServerGameInfo.SetPendingPaidShopItem(player, GameConfig.ItemType.Jetpack, jetpackId, jetpackData.productId) then
		LogInfo(string.format("PaidBuyRejected userId=%d reason=pending_failed jetpackId=%d", player.UserId, jetpackId))
		return
	end

	marketplaceService:PromptProductPurchase(player, jetpackData.productId)
end

-- 处理客户端更换火箭背包请求
function JetpackManager.OnRequestUpdateJetpackUsing(player: Player, jetpackId: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local jetpackIdStr = tostring(jetpackId)
	if not playerInfo.jetpackInventory.ownedList[jetpackIdStr] then
		warn(string.format("%s EquipRejected userId=%d reason=not_owned jetpackId=%d", LOG_PREFIX, player.UserId, jetpackId))
		return
	end

	LogInfo(string.format("EquipAccepted userId=%d jetpackId=%d", player.UserId, jetpackId))
	ServerGameInfo.SetCurrentJetpack(player, jetpackIdStr)
end

-- 处理客户端领取群组火箭背包奖励请求
function JetpackManager.OnRequestClaimJetpackGroupReward(player: Player, isInGroup: boolean)
	if not isInGroup then
		return
	end

	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	-- 取所有 costType == GroupReward 的火箭背包 ID
	local groupRewardJetpackIdList: { number } = {}
	for _, jetpackData in GameConfig.JetpackDataMap do
		if jetpackData.costType == GameConfig.CostType.GroupReward then
			table.insert(groupRewardJetpackIdList, jetpackData.id)
		end
	end

	if #groupRewardJetpackIdList == 0 then
		warn(string.format("%s Group reward jetpack list is empty", LOG_PREFIX))
		return
	end

	-- 检查是否至少有一个群组奖励火箭背包未拥有，避免重复通知
	local hasAnyToClaim = false
	for _, rewardJetpackId in ipairs(groupRewardJetpackIdList) do
		local jetpackIdStr = tostring(rewardJetpackId)
		if not playerInfo.jetpackInventory.ownedList[jetpackIdStr] then
			hasAnyToClaim = true
			break
		end
	end

	if not hasAnyToClaim then
		LogInfo(string.format("GroupReward already claimed all userId=%d", player.UserId))
		return
	end

	for _, rewardJetpackId in ipairs(groupRewardJetpackIdList) do
		ServerGameInfo.AddJetpackToInventory(player, tostring(rewardJetpackId))
	end
	LogInfo(string.format("GroupRewardClaimed userId=%d count=%d", player.UserId, #groupRewardJetpackIdList))
end

function JetpackManager.Init()
	NetMsg.ConnectRequestBuyJetpack(JetpackManager.OnRequestBuyJetpack)
	NetMsg.ConnectRequestBuyJetpackPaid(JetpackManager.OnRequestBuyJetpackPaid)
	NetMsg.ConnectRequestUpdateJetpackUsing(JetpackManager.OnRequestUpdateJetpackUsing)
	NetMsg.ConnectRequestClaimJetpackGroupReward(JetpackManager.OnRequestClaimJetpackGroupReward)
	LogInfo("Init success")
end

return JetpackManager
