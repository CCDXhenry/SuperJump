--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local ClientScripts = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Client")
local SharedScripts = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")

local Core = ReplicatedStorage:WaitForChild("Core")
local CoreScripts = Core:WaitForChild("Scripts")
local CoreClientScripts = CoreScripts:WaitForChild("Client")
local CoreSharedScripts = CoreScripts:WaitForChild("Shared")

local ClientGameInfo = require(ClientScripts:WaitForChild("ClientGameInfo"))
local ClientMsg = require(ClientScripts:WaitForChild("ClientMsg"))
local UIManager = require(ClientScripts:WaitForChild("UIManager"))
local BillboardManager = require(ClientScripts:WaitForChild("BillboardManager"))
local TranslationTool = require(CoreClientScripts:WaitForChild("TranslationTool"))
local NumberExtension = require(CoreSharedScripts:WaitForChild("NumberExtension"))
local GameConfig = require(SharedScripts:WaitForChild("GameConfig"))
local GameTexts = require(SharedScripts:WaitForChild("GameTexts"))
local NetMsg = require(SharedScripts:WaitForChild("NetMsg"))

local ShopClientManager = {}
local SHOP_MODEL_FOLDER_NAME = "ShopModel"
local SHOP_MODEL_NAMES = {"SellShop", "JetpackShop", "ExEquipShop", "NewPack", "ProPack", "Jetpack299R"}
local SHOP_WAIT_TIMEOUT = 10
local PROMPT_BOUND_ATTR = "ShopPromptWindowBound"
local BILLBOARD_TRACKED_ATTR = "BillboardTracked"
local ShopBundleIdAttribute = "id"
local ShopBundleProductIndexAttribute = "productIndex"
local ShopJetpackIdAttribute = "JetpackId"
local MinShopBundleProductIndex = 1
local MaxShopBundleProductIndex = 3

-- Removed unused getSkillData and getLevel

local function updatePrompts()
	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not playerInfo then
		return
	end

	-- SellBrainrotPrompt logic removed from updatePrompts since it uses a UI now.
end

local function EnsureBillboardTracked(gui: BillboardGui)
	if gui:GetAttribute(BILLBOARD_TRACKED_ATTR) ~= true then
		gui:SetAttribute(BILLBOARD_TRACKED_ATTR, true)
	end
	BillboardManager.Track(gui)
end

local function parsePositiveInt(attrValue: unknown): number?
	if type(attrValue) == "number" then
		local n = attrValue :: number
		if n > 0 and n == math.floor(n) then
			return n
		end
	elseif type(attrValue) == "string" then
		local n = tonumber(attrValue)
		if n and n > 0 and n == math.floor(n) then
			return n
		end
	end
	return nil
end

local function SetupJetpackAbilityBillboard(shopModel: Model, controllerFrame: Frame)
	local jetpackId = parsePositiveInt(shopModel:GetAttribute(ShopJetpackIdAttribute))
	if jetpackId == nil then
		return
	end

	local jetpackData = GameConfig.JetpackDataMap[jetpackId]
	if jetpackData == nil then
		warn(`[ShopClientManager] Jetpack id {jetpackId} not found (Workspace.{shopModel.Name})`)
		return
	end

	local textLable = controllerFrame:FindFirstChild("TextLable") :: TextLabel?
	if textLable then
		TranslationTool.CustomAutoLocalizeTextLabel(textLable, jetpackData.name_t, "")
	end

	-- local priceText = controllerFrame:FindFirstChild("PriceText") :: TextLabel?
	-- if priceText then
	-- 	if jetpackData.costType == GameConfig.CostType.Rb and jetpackData.costRb > 0 then
	-- 		priceText.Text = NumberExtension.FormatBigNumberAA(jetpackData.costRb)
	-- 	elseif jetpackData.costType == GameConfig.CostType.Coin and jetpackData.costCoin > 0 then
	-- 		priceText.Text = NumberExtension.FormatBigNumberAA(jetpackData.costCoin)
	-- 	else
	-- 		priceText.Text = ""
	-- 	end
	-- end

	local jackAbilityFrame = controllerFrame:FindFirstChild("JackAbilityFrame") :: Frame?
	if jackAbilityFrame == nil then
		return
	end

	local fuelValue = jackAbilityFrame:FindFirstChild("FuelValue") :: TextLabel?
	if fuelValue then
		TranslationTool.CustomAutoLocalizeTextLabel(
			fuelValue,
			GameTexts.FuelWithNumber.source,
			GameTexts.FuelWithNumber.key,
			{ tostring(jetpackData.fuel) }
		)
	end

	local thrustValue = jackAbilityFrame:FindFirstChild("ThrustValue") :: TextLabel?
	if thrustValue then
		thrustValue.Text = string.format(
			"+%s%%",
			NumberExtension.FormatBigNumberAA(GameConfig.GetJetpackThrustPercent(jetpackData))
		)
	end
end

local function SetupEquipBoxGuiAdaptation(shopModel: Model)
	local guidePart = shopModel:WaitForChild("GuidePart", SHOP_WAIT_TIMEOUT)
	if not guidePart then
		warn(`[ShopClientManager] GuidePart not found in Workspace.{shopModel.Name}`)
		return
	end

	local equipBoxGuiObj = guidePart:WaitForChild("EquipBoxGui", SHOP_WAIT_TIMEOUT)
	if not equipBoxGuiObj or not equipBoxGuiObj:IsA("BillboardGui") then
		warn(`[ShopClientManager] EquipBoxGui missing or not BillboardGui in Workspace.{shopModel.Name}.GuidePart`)
		return
	end
	local equipBoxGui = equipBoxGuiObj :: BillboardGui
	local controllerFrame = equipBoxGui:FindFirstChild("ControllerFrame") :: Frame?
	if not controllerFrame then
		--warn(`[ShopClientManager] ControllerFrame not found in Workspace.{shopModel.Name}.GuidePart.EquipBoxGui`)
		return
	end

	local uiScale = controllerFrame:FindFirstChildOfClass("UIScale") :: UIScale?
	if uiScale == nil then
		local newUiScale = Instance.new("UIScale")
		newUiScale.Name = "UIScale"
		newUiScale.Parent = controllerFrame
	end

	if controllerFrame.Size.X.Scale > 0 or controllerFrame.Size.Y.Scale > 0 then
		local absSize = controllerFrame.AbsoluteSize
		if absSize.X > 0 and absSize.Y > 0 then
			controllerFrame.Size = UDim2.fromOffset(absSize.X, absSize.Y)
		end
	end

	EnsureBillboardTracked(equipBoxGui)
	SetupJetpackAbilityBillboard(shopModel, controllerFrame)
end

local function getBundleProductId(bundleConfig: GameConfig.ShopBundleConfigurationData, productIndex: number): number
	if productIndex == 1 then
		return bundleConfig.productId1
	end
	if productIndex == 2 then
		return bundleConfig.productId2
	end
	if productIndex == 3 then
		return bundleConfig.productId3
	end
	return 0
end

local function shouldBlockShopBundleForPaidRandomPolicy(
	bundleData: GameConfig.ShopBundleData,
	playerInfo: GameConfig.ClientLocalPlayerInfo
): boolean
	if bundleData.config.arePaidRandomItemsRestricted == 0 then
		return false
	end
	return playerInfo.playerConfigInfo.arePaidRandomItemsRestricted == true
end

-- Direct purchase when Model attributes id + productIndex (1–3) are set; true = handled, skip OpenWindow.
local function tryPromptShopBundleDirectPurchase(shopModel: Model): boolean
	local bundleId = parsePositiveInt(shopModel:GetAttribute(ShopBundleIdAttribute))
	local productIndex = parsePositiveInt(shopModel:GetAttribute(ShopBundleProductIndexAttribute))
	if bundleId == nil or productIndex == nil then
		return false
	end
	if productIndex < MinShopBundleProductIndex or productIndex > MaxShopBundleProductIndex then
		return false
	end

	local bundleData = GameConfig.ShopBundleById[bundleId]
	if bundleData == nil then
		warn(`[ShopClientManager] Shop bundle id {bundleId} not found (Workspace.{shopModel.Name})`)
		return true
	end

	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if playerInfo == nil then
		return true
	end

	if shouldBlockShopBundleForPaidRandomPolicy(bundleData, playerInfo) then
		local tip = GameTexts.ShopBundlePurchaseRestrictedByPolicy
		ClientMsg.FireShowGameTip(tip.source, GameConfig.GameTipTweenType.FlyUp, tip.key)
		return true
	end

	local canRepurchased = bundleData.config.canRepurchased
	local owned = playerInfo.ownedShopBundleMap ~= nil and playerInfo.ownedShopBundleMap[tostring(bundleId)] == true
	if canRepurchased == 0 and owned then
		local tip = GameTexts.ShopBundleAlreadyPurchased
		ClientMsg.FireShowGameTip(tip.source, GameConfig.GameTipTweenType.FlyUp, tip.key)
		return true
	end

	local productId = getBundleProductId(bundleData.config, productIndex)
	if productId <= 0 then
		warn(
			`[ShopClientManager] Invalid productId for bundle {bundleId} productIndex {productIndex} (Workspace.{shopModel.Name})`
		)
		return true
	end

	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		return true
	end
	MarketplaceService:PromptProductPurchase(localPlayer, productId)
	return true
end

-- Direct purchase when Model attribute JetpackId is set; true = handled, skip OpenWindow.
local function tryPromptJetpackDirectPurchase(shopModel: Model): boolean
	local jetpackId = parsePositiveInt(shopModel:GetAttribute(ShopJetpackIdAttribute))
	if jetpackId == nil then
		return false
	end

	local jetpackData = GameConfig.JetpackDataMap[jetpackId]
	if jetpackData == nil then
		warn(`[ShopClientManager] Jetpack id {jetpackId} not found (Workspace.{shopModel.Name})`)
		return true
	end
	if jetpackData.productId <= 0 or jetpackData.costType ~= GameConfig.CostType.Rb then
		warn(`[ShopClientManager] Jetpack {jetpackId} is not a paid Robux product (Workspace.{shopModel.Name})`)
		return true
	end

	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if playerInfo == nil then
		return true
	end
	if playerInfo.jetpackInventory.ownedList[tostring(jetpackId)] then
		local tip = GameTexts.JetpackAlreadyPurchased
		ClientMsg.FireShowGameTip(tip.source, GameConfig.GameTipTweenType.FlyUp, tip.key)
		return true
	end

	NetMsg.FireRequestBuyJetpackPaid(jetpackId)
	return true
end

local function findShopProximityPrompt(shopModel: Model, rootPart: Instance): ProximityPrompt?
	local openShopAttachment = rootPart:FindFirstChild("OpenShopAttachment")
	if openShopAttachment then
		local promptObj = openShopAttachment:FindFirstChild("ProximityPrompt")
		if promptObj and promptObj:IsA("ProximityPrompt") then
			return promptObj
		end
	end

	local rootPrompt = rootPart:FindFirstChild("ProximityPrompt")
	if rootPrompt and rootPrompt:IsA("ProximityPrompt") then
		return rootPrompt
	end

	for _, descendant in rootPart:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			return descendant
		end
	end

	for _, descendant in shopModel:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			return descendant
		end
	end

	return nil
end

local function BindPromptByWindowId(shopModel: Model)
	local rootPart = shopModel:WaitForChild("RootPart", SHOP_WAIT_TIMEOUT)
	if not rootPart then
		warn(`[ShopClientManager] RootPart not found in Workspace.{shopModel.Name}`)
		return
	end

	local prompt: ProximityPrompt? = nil
	local deadline = os.clock() + SHOP_WAIT_TIMEOUT
	while os.clock() < deadline and prompt == nil do
		prompt = findShopProximityPrompt(shopModel, rootPart)
		if prompt == nil then
			task.wait(0.1)
		end
	end
	if prompt == nil then
		warn(
			`[ShopClientManager] ProximityPrompt not found under Workspace.{shopModel.Name} (expected RootPart.OpenShopAttachment.ProximityPrompt or RootPart.ProximityPrompt)`
		)
		return
	end
	if prompt:GetAttribute(PROMPT_BOUND_ATTR) == true then
		return
	end
	prompt:SetAttribute(PROMPT_BOUND_ATTR, true)

	prompt.Triggered:Connect(function()
		if tryPromptShopBundleDirectPurchase(shopModel) then
			return
		end
		if tryPromptJetpackDirectPurchase(shopModel) then
			return
		end
		local windowIdAttr = shopModel:GetAttribute("WindowId")
		local windowId = if type(windowIdAttr) == "string" then windowIdAttr else ""
		if windowId == "" then
			warn(`[ShopClientManager] WindowId is missing/empty on Workspace.{shopModel.Name}`)
			return
		end
		UIManager.OpenWindow(windowId)
	end)
end

local function InitShopModel(modelName: string)
	local shopModelFolder = Workspace:WaitForChild(SHOP_MODEL_FOLDER_NAME, SHOP_WAIT_TIMEOUT)
	if not shopModelFolder or not shopModelFolder:IsA("Folder") then
		warn(`[ShopClientManager] Workspace.{SHOP_MODEL_FOLDER_NAME} not found or not a Folder`)
		return
	end

	local shopModelObj = shopModelFolder:WaitForChild(modelName, SHOP_WAIT_TIMEOUT)
	if not shopModelObj or not shopModelObj:IsA("Model") then
		warn(`[ShopClientManager] Workspace.{SHOP_MODEL_FOLDER_NAME}.{modelName} not found or not a Model`)
		return
	end
	local shopModel = shopModelObj :: Model
	BindPromptByWindowId(shopModel)
	SetupEquipBoxGuiAdaptation(shopModel)
end

function ShopClientManager.Init()
	for _, modelName in ipairs(SHOP_MODEL_NAMES) do
		task.spawn(function()
			InitShopModel(modelName)
		end)
	end

	-- Listen for character changes to update SellBrainrotPrompt
	local function onCharacter(char: Model)
		local function update()
			updatePrompts()
		end
		char.ChildAdded:Connect(update)
		char.ChildRemoved:Connect(update)
		update()
	end
	game.Players.LocalPlayer.CharacterAdded:Connect(onCharacter)
	if game.Players.LocalPlayer.Character then
		onCharacter(game.Players.LocalPlayer.Character)
	end

	-- Listen for data changes to update ActionText
	ClientMsg.ConnectLocalPlayerSkillLevelUpdate(function(skillType, level)
		updatePrompts()
	end)

	ClientMsg.ConnectLocalPlayerInfoInit(function()
		updatePrompts()
	end)

	-- Initial update
	updatePrompts()
end

return ShopClientManager
