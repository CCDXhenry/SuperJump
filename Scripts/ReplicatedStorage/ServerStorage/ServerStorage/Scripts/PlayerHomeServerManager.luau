--!strict
local serverStorage = game:GetService("ServerStorage")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local players = game:GetService("Players")
local marketplaceService = game:GetService("MarketplaceService")
local httpService = game:GetService("HttpService")

local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:WaitForChild("ServerGameInfo"))
local BrainrotQueueManager = require(serverScripts:WaitForChild("BrainrotQueueManager"))
local AnalyticsTool = require(serverScripts:WaitForChild("AnalyticsTool"))

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))

local PlayerHomeServerManager = {}

local LogPrefix = "[PlayerHomeServerManager]"

local YIELD_UPDATE_INTERVAL = 1
local YIELD_BROADCAST_INTERVAL = 60

local homesFolder: Folder
local availableSlots: { string } = {}
local yieldUpdateAccumulator = 0
local yieldBroadcastAccumulator = 0
local basePlotsCount = 0

local initDone = false
local DebugRunId = "runway_pullback_probe_1"

local function DebugEmit(hypothesisId: string, location: string, message: string, data: { [string]: any }?)
	local payload = {
		sessionId = "6f8203",
		runId = DebugRunId,
		hypothesisId = hypothesisId,
		location = location,
		message = message,
		data = data or {},
		timestamp = DateTime.now().UnixTimestampMillis,
	}
	pcall(function()
		httpService:RequestAsync({
			Url = "http://127.0.0.1:7477/ingest/d880235d-ec65-4b2d-88e2-c8b819ceca93",
			Method = "POST",
			Compress = Enum.HttpCompression.None,
			Headers = {
				["Content-Type"] = "application/json",
				["X-Debug-Session-Id"] = "6f8203",
			},
			Body = httpService:JSONEncode(payload),
		})
	end)
	local okEncode, encoded = pcall(function()
		return httpService:JSONEncode(payload)
	end)
	if okEncode then
		warn("[DBG6f8203] " .. encoded)
	end
end

local function ensurePlayersHomeFolder(): Folder
	local existing = workspace:FindFirstChild("PlayersHome")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "PlayersHome"
	folder.Parent = workspace
	return folder
end

local function initSlots()
	table.clear(availableSlots)
	basePlotsCount = 0
	for _, child in ipairs(homesFolder:GetChildren()) do
		if child.Name:match("^Player%d+$") then
			table.insert(availableSlots, child.Name)

			if basePlotsCount == 0 then
				local lv1 = child:FindFirstChild("Lv1")
				if lv1 then
					local count = 0
					for _, sub in ipairs(lv1:GetChildren()) do
						if sub.Name:match("^PlaceModel%d+$") then
							count += 1
						end
					end
					basePlotsCount = count
				end
			end
		end
	end
	table.sort(availableSlots)
end

local function setupPlayerRespawn(player: Player, slotName: string)
	local slotModel = homesFolder:FindFirstChild(slotName)
	if slotModel then
		local teleportPoint = slotModel:FindFirstChild("TeleportPoint")
		if teleportPoint then
			local spawnLocation = teleportPoint:FindFirstChild("SpawnLocation") :: SpawnLocation?
			if spawnLocation then
				player.RespawnLocation = spawnLocation
				if player.Character then
					local hrp = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if hrp then
						task.defer(function()
							if player:GetAttribute("JumpRunwayActive") == true then
								-- #region agent log
								DebugEmit("H3", "PlayerHomeServerManager:setupPlayerRespawn:initTeleport", "home_init_teleport_blocked_by_runway_active", {
									playerUserId = player.UserId,
								})
								-- #endregion
								return
							end
							hrp.CFrame = spawnLocation.CFrame * CFrame.new(0, 3, 0)
						end)
					end
				end
			end
		end
	end

	player.CharacterAdded:Connect(function(char)
		local hrp = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
		if hrp and slotModel then
			local teleportPoint = slotModel:FindFirstChild("TeleportPoint")
			if teleportPoint then
				local spawnLocation = teleportPoint:FindFirstChild("SpawnLocation") :: SpawnLocation?
				if spawnLocation then
					task.defer(function()
						if player:GetAttribute("JumpRunwayActive") == true then
							-- #region agent log
							DebugEmit("H3", "PlayerHomeServerManager:setupPlayerRespawn:characterAdded", "home_characterAdded_teleport_blocked_by_runway_active", {
								playerUserId = player.UserId,
							})
							-- #endregion
							return
						end
						hrp.CFrame = spawnLocation.CFrame * CFrame.new(0, 3, 0)
					end)
				end
			end
		end
	end)
end

local function onPlayerAdded(player: Player)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		task.spawn(function()
			while player.Parent do
				local pi = ServerGameInfo.GetPlayerInfo(player)
				if pi then
					onPlayerAdded(player)
					break
				end
				task.wait(0.5)
			end
		end)
		return
	end

	if #availableSlots == 0 then
		player:Kick("Server is full, no home slots available.")
		return
	end

	local slotName = availableSlots[1]
	table.remove(availableSlots, 1)

	ServerGameInfo.SetPlayerHomeSlot(player, slotName)

	setupPlayerRespawn(player, slotName)
	print(LogPrefix, "Assigned slot", slotName, "to", player.Name)
end

local function onRequestPlaceHomeModel(player: Player, instanceId: string, pointIndex: number)
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		warn(LogPrefix, "OnRequestPlaceHomeModel failed: playerInfo not found for", player.Name)
		return
	end

	local maxPoints = playerInfo.homeInfo.level * (if basePlotsCount > 0 then basePlotsCount else 6)
	if pointIndex < 1 or pointIndex > maxPoints then
		warn(
			LogPrefix,
			"OnRequestPlaceHomeModel failed: invalid pointIndex",
			pointIndex,
			"maxPoints for level",
			playerInfo.homeInfo.level,
			"is",
			maxPoints
		)
		return
	end
	if playerInfo.homeInfo.placedModels[tostring(pointIndex)] ~= nil then
		warn(LogPrefix, "OnRequestPlaceHomeModel failed: pointIndex occupied", pointIndex)
		return
	end

	local modelIndex: number? = nil
	local targetModel: GameConfig.ModelInfo? = nil
	for i, model in ipairs(playerInfo.inventoryInfo.models) do
		if model.instanceId == instanceId then
			targetModel = model
			modelIndex = i
			break
		end
	end

	if targetModel and modelIndex then
		if not GameConfig.BrainrotIdMap[targetModel.configId] then
			warn(
				LogPrefix,
				"OnRequestPlaceHomeModel rejected: configId is not Brainrot for",
				player.Name,
				"configId",
				targetModel.configId
			)
			return
		end

		table.remove(playerInfo.inventoryInfo.models, modelIndex)

		ServerGameInfo.UpdatePlayerPlacedModel(player, pointIndex, targetModel)

		AnalyticsTool.LogModelPlace(player, targetModel.configId, targetModel.level)

		print(LogPrefix, "Player", player.Name, "placed model", instanceId, "at point", pointIndex)
	else
		warn(LogPrefix, "OnRequestPlaceHomeModel failed: targetModel not in inventory", instanceId)
	end
end

local function onRequestUpgradeModel(player: Player, pointIndex: number, levelAdd: number?, isPaidIntent: boolean?)
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		warn(LogPrefix, "OnRequestUpgradeModel failed: playerInfo not found for", player.Name)
		return
	end

	local model = playerInfo.homeInfo.placedModels[tostring(pointIndex)]
	if not model then
		warn(LogPrefix, "OnRequestUpgradeModel failed: no model at point", pointIndex)
		return
	end
	local brainrotData = GameConfig.BrainrotIdMap[model.configId]
	if not brainrotData then
		warn(LogPrefix, "OnRequestUpgradeModel failed: brainrotData not found for configId", model.configId)
		return
	end

	local cost = GameConfig.GetBrainrotUpgradeCost(brainrotData.baseAbility, model.level)
	local currentGold = playerInfo.currencies["1"] or 0

	if isPaidIntent == true then
		if currentGold >= cost then
			-- gold sufficient: fall through to normal upgrade
		else
			ServerGameInfo.SetPendingBrainrotPaidUpgrade(player, pointIndex, levelAdd or 3)
			print(LogPrefix, "Recorded pending paid brainrot upgrade for", player.Name, "at point", pointIndex, "levelAdd", levelAdd or 3)
			return
		end
	end

	if currentGold >= cost then
		local configIdBefore = model.configId
		ServerGameInfo.UpdatePlayerCurrency(
			player,
			GameConfig.CurrencyType.Coin,
			-cost,
			GameConfig.ItemCountChangeReason.SpendOnUpgradeBrainrot
		)

		ServerGameInfo.UpgradePlacedModel(player, pointIndex)

		local modelAfter = playerInfo.homeInfo.placedModels[tostring(pointIndex)]
		if modelAfter then
			AnalyticsTool.LogModelUpgrade(player, configIdBefore, modelAfter.level)
		end

		local levelShown = if modelAfter then modelAfter.level else model.level
		print(LogPrefix, "Player", player.Name, "upgraded model at point", pointIndex, "to level", levelShown)
	else
		warn(LogPrefix, "OnRequestUpgradeModel failed: insufficient currency for", player.Name)
	end
end

local function onRequestSellModel(player: Player, pointIndex: number)
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		warn(LogPrefix, "OnRequestSellModel failed: playerInfo not found for", player.Name)
		return
	end

	local model = playerInfo.homeInfo.placedModels[tostring(pointIndex)]
	if not model then
		warn(LogPrefix, "OnRequestSellModel failed: no model at point", pointIndex)
		return
	end

	local brainrotData = GameConfig.BrainrotIdMap[model.configId]
	if not brainrotData then
		warn(LogPrefix, "OnRequestSellModel failed: brainrotData not found for configId", model.configId)
		return
	end

	local returnVal = GameConfig.GetBrainrotSellPrice(brainrotData.baseAbility, model.level)
	local sellConfigId = model.configId
	local sellLevel = model.level

	ServerGameInfo.UpdatePlayerCurrency(player, GameConfig.CurrencyType.Coin, returnVal, GameConfig.ItemCountChangeReason.GainFromSellModel)

	ServerGameInfo.UpdatePlayerPlacedModel(player, pointIndex, nil :: any)

	AnalyticsTool.LogModelSell(player, 1, returnVal, { sellConfigId }, { sellLevel })

	print(LogPrefix, "Player", player.Name, "sold model at point", pointIndex, "for", returnVal)
end

local function getActiveBrainrotForPickup(plr: Player): Instance?
	local char = plr.Character
	if not char then
		return nil
	end
	local tool = char:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("BrainrotUID") then
		if tool:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
			return tool
		end
		return nil
	end
	local carrying = char:FindFirstChild("CarryingBrainrot")
	if carrying and carrying:GetAttribute("BrainrotUID") then
		if carrying:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
			return carrying
		end
		return nil
	end
	return nil
end

local function onRequestPickupHomeModel(player: Player, pointIndex: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return
	end

	local model = playerInfo.homeInfo.placedModels[tostring(pointIndex)]
	if not model then
		warn(LogPrefix, "OnRequestPickupHomeModel failed: no model at point", pointIndex)
		return
	end

	local brainrotData = GameConfig.BrainrotIdMap[model.configId]
	if not brainrotData then
		return
	end

	local heldBrainrot = getActiveBrainrotForPickup(player)

	if heldBrainrot then
		local heldConfigId = tonumber(heldBrainrot:GetAttribute("ConfigId"))
		local heldQuality = tonumber(heldBrainrot:GetAttribute("Quality")) or 1
		local heldLevel = tonumber(heldBrainrot:GetAttribute("Level")) or 1
		local heldUid = heldBrainrot:GetAttribute("BrainrotUID") :: string?

		if heldConfigId and heldUid then
			if heldBrainrot:IsA("Tool") then
				if not BrainrotQueueManager.RemoveItem(player, heldUid) then
					return
				end
			else
				if not heldBrainrot.Parent then
					return
				end
			end

			local oldConfigId = model.configId
			local oldLevel = (model :: any).level or 1
			local oldQuality = (model :: any).quality or 1

			heldBrainrot:Destroy()

			local heldQualityCfg = GameConfig.BrainrotQualityConfig[heldQuality]
			local defaultQualityCfg = GameConfig.BrainrotQualityConfig[1]
			local newPlacedData = {
				configId = heldConfigId,
				level = heldLevel,
				quality = heldQuality,
				instanceId = heldUid or httpService:GenerateGUID(false),
				rarity = if heldQualityCfg then heldQualityCfg.rarity else if defaultQualityCfg then defaultQualityCfg.rarity else "Common",
			}
			ServerGameInfo.UpdatePlayerPlacedModel(player, pointIndex, newPlacedData :: any)

			if BrainrotQueueManager.AddItem(player, oldConfigId, oldQuality, oldLevel, true, nil, false) then
				AnalyticsTool.LogModelHold(player, oldConfigId, oldLevel)
			end

			return
		end
	end

	local configId = model.configId
	local level = (model :: any).level or 1
	local quality = (model :: any).quality or 1
	ServerGameInfo.UpdatePlayerPlacedModel(player, pointIndex, nil :: any)

	if BrainrotQueueManager.AddItem(player, configId, quality, level, true, nil, false) then
		AnalyticsTool.LogModelHold(player, configId, level)
	end
end

local function onRequestClaimYield(player: Player, targetPlayerId: number, pointIndex: number)
	ServerGameInfo.ClaimModelYield(player, targetPlayerId, pointIndex)
end

local function onHeartbeat(dt: number)
	yieldUpdateAccumulator += dt
	yieldBroadcastAccumulator += dt

	if yieldUpdateAccumulator >= YIELD_UPDATE_INTERVAL then
		yieldUpdateAccumulator -= YIELD_UPDATE_INTERVAL
		for _, player in ipairs(players:GetPlayers()) do
			local playerInfo = ServerGameInfo.GetPlayerInfo(player)
			if playerInfo then
				for pointIndexStr, model in pairs(playerInfo.homeInfo.placedModels) do
					local bData = GameConfig.BrainrotIdMap[model.configId]
					if bData then
						local baseYield = GameConfig.GetBrainrotAbility(bData.baseAbility, model.level)
						local multiplier = ServerGameInfo.GetRebirthMultiplier(player)
						local y = math.ceil(baseYield * multiplier)
						if y > 0 then
							local pointIndex = tonumber(pointIndexStr)
							if pointIndex then
								ServerGameInfo.UpdateModelUnclaimedYield(player, pointIndex, y)
							end
						end
					end
				end
			end
		end
	end

	if yieldBroadcastAccumulator >= YIELD_BROADCAST_INTERVAL then
		yieldBroadcastAccumulator -= YIELD_BROADCAST_INTERVAL
		ServerGameInfo.BroadcastAllPlayersModelYields()
	end
end

local function onPlayerRemoving(player: Player)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo and playerInfo.homeSlot and playerInfo.homeSlot ~= "" then
		table.insert(availableSlots, playerInfo.homeSlot)
		table.sort(availableSlots)
		print(LogPrefix, "Player", player.Name, "left. Returned slot", playerInfo.homeSlot)

		NetMsg.FireNotifyPlayerHomeInfoUpdate(player.UserId, playerInfo.homeSlot, {
			level = 1,
			placedModels = {},
			unclaimedYield = 0,
		})
	end
end

function PlayerHomeServerManager.RestoreHomeModel(player: Player, brainrot: Instance)
	local fromHomeSlot = brainrot:GetAttribute("FromHomeSlot")
	local fromPointIndex = brainrot:GetAttribute("FromPointIndex") :: number?
	local originalDataJson = brainrot:GetAttribute("OriginalData")

	if not fromHomeSlot or not fromPointIndex or not originalDataJson then
		brainrot:Destroy()
		return
	end

	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo or playerInfo.homeSlot ~= fromHomeSlot then
		brainrot:Destroy()
		return
	end

	local ok, originalData = pcall(function()
		return httpService:JSONDecode(originalDataJson)
	end)

	if ok and originalData then
		ServerGameInfo.UpdatePlayerPlacedModel(player, fromPointIndex, originalData)
	end

	brainrot:Destroy()
end

function PlayerHomeServerManager.Init()
	if initDone then
		return
	end
	initDone = true

	homesFolder = ensurePlayersHomeFolder()
	initSlots()

	players.PlayerAdded:Connect(onPlayerAdded)
	players.PlayerRemoving:Connect(onPlayerRemoving)
	runService.Heartbeat:Connect(onHeartbeat)

	NetMsg.ConnectRequestPlaceHomeModel(onRequestPlaceHomeModel)
	NetMsg.ConnectRequestUpgradeModel(onRequestUpgradeModel)
	NetMsg.ConnectRequestSellModel(onRequestSellModel)
	NetMsg.ConnectRequestClaimYield(onRequestClaimYield)
	NetMsg.ConnectRequestPickupHomeModel(onRequestPickupHomeModel)

	NetMsg.ConnectRequestRebirth(function(player: Player)
		ServerGameInfo.ExecuteRebirth(player, false)
	end)

	NetMsg.ConnectRequestPaidRebirth(function(player: Player)
		local playerInfo = ServerGameInfo.GetPlayerInfo(player)
		if not playerInfo then
			return
		end

		local currentRebirthLevel = playerInfo.shopInfo.rebirthLevel or 0
		local nextRebirthCount = currentRebirthLevel + 1
		local nextRebirthConfig = GameConfig.RebirthMap[nextRebirthCount]
		if not nextRebirthConfig then
			return
		end

		if
			playerInfo.shopInfo.walkSpeedLevel >= nextRebirthConfig.speedLv
			and playerInfo.shopInfo.maxBricksLevel >= nextRebirthConfig.brickLv
		then
			marketplaceService:PromptProductPurchase(player, GameConfig.Paving.RebirthProductId)
		end
	end)
end

return PlayerHomeServerManager
