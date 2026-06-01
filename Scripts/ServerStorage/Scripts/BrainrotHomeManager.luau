--!strict
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage = game:GetService("ServerStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))

local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:WaitForChild("ServerGameInfo"))
local BrainrotQueueManager = require(serverScripts:WaitForChild("BrainrotQueueManager"))
local AnalyticsTool = require(serverScripts:WaitForChild("AnalyticsTool"))

local BrainrotHomeManager = {}

local LogPrefix = "[BrainrotHomeManager]"

local initDone = false

local function getActiveBrainrot(player: Player): Instance?
	local character = player.Character
	if not character then
		return nil
	end

	local carrying = character:FindFirstChild("CarryingBrainrot")
	if carrying and carrying:GetAttribute("BrainrotUID") then
		if carrying:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
			return carrying
		end
		return nil
	end

	local equippedTool = character:FindFirstChildOfClass("Tool")
	if equippedTool and equippedTool:GetAttribute("BrainrotUID") then
		if equippedTool:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
			return equippedTool
		end
	end

	return nil
end

local function destroyBrainrotToolsByUid(player: Player, uid: string)
	local char = player.Character
	if char then
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("BrainrotUID") == uid then
				child:Destroy()
			end
		end
	end
	for _, child in ipairs(player.Backpack:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("BrainrotUID") == uid then
			child:Destroy()
		end
	end
end

local function sellOneActiveBrainrot(player: Player, suppressAnalytics: boolean?): (boolean, number?, number?, number?)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return false
	end
	local carryingBrainrot = getActiveBrainrot(player)
	if not carryingBrainrot then
		return false
	end
	local configId = carryingBrainrot:GetAttribute("ConfigId")
	if not configId then
		return false
	end
	local uid = carryingBrainrot:GetAttribute("BrainrotUID") :: string?
	if not uid then
		return false
	end

	if carryingBrainrot:IsA("Tool") then
		if not BrainrotQueueManager.RemoveItem(player, uid) then
			return false
		end
	else
		if not carryingBrainrot.Parent then
			return false
		end
	end

	local brainrotConfig = GameConfig.BrainrotIdMap[tonumber(configId) or 0]
	if not brainrotConfig then
		return false
	end
	local currentLevel = tonumber(carryingBrainrot:GetAttribute("Level")) or 1
	local sellPrice = GameConfig.GetBrainrotSellPrice(brainrotConfig.baseAbility, currentLevel)
	local configIdNum = tonumber(configId) or 0

	ServerGameInfo.UpdatePlayerCurrency(player, GameConfig.CurrencyType.Coin, sellPrice, GameConfig.ItemCountChangeReason.GainFromSellModel)
	if not suppressAnalytics then
		AnalyticsTool.LogModelSell(player, 1, sellPrice, { configIdNum }, { currentLevel })
	end
	carryingBrainrot:Destroy()

	return true, sellPrice, configIdNum, currentLevel
end

local function sellOneQueuedBrainrotByUid(player: Player, uid: string, suppressAnalytics: boolean?): (boolean, number?, number?, number?)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return false
	end
	local item: GameConfig.BrainrotQueueItem? = nil
	for _, q in ipairs(playerInfo.brainrotQueue) do
		if q.uid == uid and q.itemType == GameConfig.ItemType.Brainrot then
			item = q
			break
		end
	end
	if not item then
		return false
	end
	local brainrotConfig = GameConfig.BrainrotIdMap[item.configId]
	if not brainrotConfig then
		return false
	end
	destroyBrainrotToolsByUid(player, uid)
	if not BrainrotQueueManager.RemoveItem(player, uid) then
		return false
	end
	local sellPrice = GameConfig.GetBrainrotSellPrice(brainrotConfig.baseAbility, item.level)
	ServerGameInfo.UpdatePlayerCurrency(player, GameConfig.CurrencyType.Coin, sellPrice, GameConfig.ItemCountChangeReason.GainFromSellModel)
	if not suppressAnalytics then
		AnalyticsTool.LogModelSell(player, 1, sellPrice, { item.configId }, { item.level })
	end
	return true, sellPrice, item.configId, item.level
end

local function onRequestSellAllBrainrotInQueue(player: Player)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return
	end

	local hadAnyBrainrotInQueue = false
	for _, item in ipairs(playerInfo.brainrotQueue) do
		if item.itemType == GameConfig.ItemType.Brainrot then
			hadAnyBrainrotInQueue = true
			break
		end
	end
	if not getActiveBrainrot(player) and not hadAnyBrainrotInQueue then
		return
	end

	local totalMoney = 0
	local modelIdList: { number } = {}
	local levelList: { number } = {}

	local soldActive, priceA, idA, lvA = sellOneActiveBrainrot(player, true)
	if soldActive and priceA ~= nil and idA ~= nil and lvA ~= nil then
		totalMoney += priceA
		table.insert(modelIdList, idA)
		table.insert(levelList, lvA)
	end

	playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return
	end

	local uidsToSell: { string } = {}
	for _, item in ipairs(playerInfo.brainrotQueue) do
		if item.itemType == GameConfig.ItemType.Brainrot then
			table.insert(uidsToSell, item.uid)
		end
	end

	for _, uid in ipairs(uidsToSell) do
		local ok, p, cid, lv = sellOneQueuedBrainrotByUid(player, uid, true)
		if ok and p ~= nil and cid ~= nil and lv ~= nil then
			totalMoney += p
			table.insert(modelIdList, cid)
			table.insert(levelList, lv)
		end
	end

	local totalCount = #modelIdList
	if totalCount > 0 then
		AnalyticsTool.LogModelSell(player, totalCount, totalMoney, modelIdList, levelList)
	end
end

local function onRequestPlaceCarryingBrainrot(player: Player, pointIndex: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return
	end

	local carryingBrainrot = getActiveBrainrot(player)
	if carryingBrainrot then
		local configId = carryingBrainrot:GetAttribute("ConfigId")
		local quality = carryingBrainrot:GetAttribute("Quality") or 2

		if configId then
			local uid = carryingBrainrot:GetAttribute("BrainrotUID") :: string?
			if not uid then
				return
			end

			local itemType = carryingBrainrot:GetAttribute("ItemType") :: number?
			if itemType ~= GameConfig.ItemType.Brainrot then
				warn(LogPrefix, "OnRequestPlaceCarryingBrainrot rejected: itemType is not Brainrot for", player.Name, "itemType", itemType)
				return
			end

			if carryingBrainrot:IsA("Tool") then
				if not BrainrotQueueManager.RemoveItem(player, uid) then
					return
				end
			else
				if not carryingBrainrot.Parent then
					return
				end
			end

			local qualityCfg = GameConfig.BrainrotQualityConfig[quality :: number]
			local defaultQualityCfg = GameConfig.BrainrotQualityConfig[1]
			local rarity: GameConfig.ModelRarity = (
				if qualityCfg then qualityCfg.rarity else if defaultQualityCfg then defaultQualityCfg.rarity else "Common"
			) :: any
			local placedLevel = tonumber(carryingBrainrot:GetAttribute("Level")) or 1
			local variantId = tonumber(carryingBrainrot:GetAttribute("VariantId"))
			local resolvedVariantId = if variantId and variantId > 0 then variantId else nil

			ServerGameInfo.UpdatePlayerPlacedModel(player, pointIndex, {
				instanceId = "brainrot_" .. tostring(math.floor(os.clock() * 1000)),
				configId = tonumber(configId) or 1,
				level = placedLevel,
				rarity = rarity,
				variantId = resolvedVariantId,
			})

			AnalyticsTool.LogModelPlace(player, tonumber(configId) or 1, placedLevel)

			carryingBrainrot:Destroy()
		end
	end
end

local function onRequestSellCarryingBrainrot(player: Player)
	sellOneActiveBrainrot(player)
end

function BrainrotHomeManager.Init()
	if initDone then
		return
	end
	initDone = true

	NetMsg.ConnectRequestPlaceCarryingBrainrot(onRequestPlaceCarryingBrainrot)
	NetMsg.ConnectRequestSellCarryingBrainrot(onRequestSellCarryingBrainrot)
	NetMsg.ConnectRequestSellAllBrainrotInQueue(onRequestSellAllBrainrotInQueue)
end

return BrainrotHomeManager
