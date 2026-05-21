--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = ReplicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local sharedScripts = scripts:WaitForChild("Shared")

local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local ClientMsg = require(clientScripts:WaitForChild("ClientMsg"))
local UIManager = require(clientScripts:WaitForChild("UIManager"))
local ClientGameInfo = require(clientScripts:WaitForChild("ClientGameInfo"))
local GameSoundManager = require(clientScripts:WaitForChild("GameSoundManager"))
local players: Players = game:GetService("Players")
local marketplaceService: MarketplaceService = game:GetService("MarketplaceService")
local core = ReplicatedStorage:WaitForChild("Core")
local NumberExtension = require(core:WaitForChild("Scripts"):WaitForChild("Shared"):WaitForChild("NumberExtension"))
local TranslationTool = require(core:WaitForChild("Scripts"):WaitForChild("Client"):WaitForChild("TranslationTool"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:WaitForChild("UIAdapter"))

local thisFrame = script.Parent :: Frame
local windowId = thisFrame:GetAttribute("WindowId") :: string

local closeButton = thisFrame:WaitForChild("CloseButton") :: ImageButton
local scrollingFrame = thisFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame

local upgradeWalkSpeedFrame1 = scrollingFrame:WaitForChild("UpgradeWalkSpeedFrame1") :: Frame
local upgradeWalkSpeedFrame10 = scrollingFrame:WaitForChild("UpgradeWalkSpeedFrame10") :: Frame
local upgradeMaxFuelFrame1 = scrollingFrame:WaitForChild("UpgradeMaxFuelFrame1") :: Frame
local upgradeMaxFuelFrame10 = scrollingFrame:WaitForChild("UpgradeMaxFuelFrame10") :: Frame
local upgradeMaxThrustSpeedFrame1 = scrollingFrame:WaitForChild("UpgradeMaxThrustSpeedFrame1") :: Frame
local upgradeMaxThrustSpeedFrame10 = scrollingFrame:WaitForChild("UpgradeMaxThrustSpeedFrame10") :: Frame
local uiListLayout = scrollingFrame:WaitForChild("UIListLayout") :: UIListLayout

closeButton.Activated:Connect(function()
	UIManager.CloseWindow(windowId)
end)

local UpgradeSuccessTipColor = Color3.fromRGB(80, 255, 120)

local warnedMissingAbilityList: { [string]: boolean } = {}

-- 按 skillType 映射对应的 GameTexts
local ABILITY_TIP_TEXTS: { [number]: { source: string, key: string } } = {
	[GameConfig.SkillType.WalkSpeed] = GameTexts.UpgradeSpeedLevelIncreased,
	[GameConfig.SkillType.MaxFuel] = GameTexts.UpgradeFuelLevelIncreased,
	[GameConfig.SkillType.MaxThrust] = GameTexts.UpgradeThrustLevelIncreased,
}

local ABILITY_VALUE_TEXTS: { [number]: { source: string, key: string } } = {
	[GameConfig.SkillType.WalkSpeed] = GameTexts.SpeedWithNumber,
	[GameConfig.SkillType.MaxFuel] = GameTexts.FuelWithNumber,
	[GameConfig.SkillType.MaxThrust] = GameTexts.ThrustWithNumber,
}

local function showUpgradeTip(skillType: number, level: number)
	local tipText = ABILITY_TIP_TEXTS[skillType]
	if tipText then
		ClientMsg.FireShowGameTip(
			tipText.source,
			GameConfig.GameTipTweenType.FlyUp,
			tipText.key,
			{ tostring(level) },
			UpgradeSuccessTipColor
		)
	end
end

local function getCostAndLimit(abilityName: string, currentLevel: number, levelAdd: number)
	local shopData = GameConfig.Shop[abilityName]
	local totalCost = 0
	local nextLevel = currentLevel or 1
	for i = 1, levelAdd do
		local cost = shopData.upgradeCostList[nextLevel]
		if not cost then
			return false, totalCost, nextLevel
		end
		totalCost += cost
		nextLevel += 1
	end
	return true, totalCost, nextLevel
end

local function refreshFrame(frame: Frame, skillType: number, levelAdd: number)
	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not playerInfo then
		return
	end

	local abilityInfo = GameConfig.ShopAbilityByType[skillType]
	if not abilityInfo then
		return
	end

	local abilityName = abilityInfo.abilityName
	local currentLevel = (playerInfo.shopInfo :: any)[abilityInfo.levelField] or 1

	local oldNumberLabel = frame:WaitForChild("OldNumberLabel") :: TextLabel
	local newNumberLabel = frame:WaitForChild("NewNumberLabel") :: TextLabel
	local imageButton = frame:WaitForChild("ImageButton") :: ImageButton
	local textLabel = imageButton:WaitForChild("TextLabel") :: TextLabel

	local shopData = GameConfig.Shop[abilityInfo.shopKey]

	local maxLevel = shopData.maxLevel
	if typeof(currentLevel) ~= "number" or currentLevel ~= currentLevel then
		currentLevel = 1
	else
		currentLevel = math.clamp(math.floor(currentLevel), 1, maxLevel)
	end

	local currentValue = shopData.abilityList[currentLevel]
	if currentValue == nil then
		currentValue = shopData.abilityList[maxLevel] or shopData.abilityList[1]
	end
	local currentValueStr = NumberExtension.FormatBigNumberAA(currentValue)

	local valueText = ABILITY_VALUE_TEXTS[skillType]
	if valueText then
		TranslationTool.CustomAutoLocalizeTextLabel(oldNumberLabel, valueText.source, valueText.key, { currentValueStr })
	end

	local canUpgrade, totalCost, targetLevel = getCostAndLimit(abilityName, currentLevel, levelAdd)
	local nextValue = if canUpgrade then shopData.abilityList[targetLevel] else nil
	if canUpgrade and nextValue ~= nil then
		local nextValueStr = NumberExtension.FormatBigNumberAA(nextValue)

		if valueText then
			TranslationTool.CustomAutoLocalizeTextLabel(newNumberLabel, valueText.source, valueText.key, { nextValueStr })
		end

		TranslationTool.CustomAutoLocalizeTextLabel(textLabel, NumberExtension.FormatBigNumberAA(totalCost))

		local currentCoin = playerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
		if currentCoin >= totalCost then
			imageButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		else
			imageButton.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
		end
	else
		if canUpgrade and nextValue == nil then
			local warnKey = abilityName .. "_" .. tostring(targetLevel)
			if not warnedMissingAbilityList[warnKey] then
				warnedMissingAbilityList[warnKey] = true
				warn("[UpgradeShopFrame] abilityList missing for upgrade preview:", abilityName, "targetLevel", targetLevel)
			end
		end
		TranslationTool.CustomAutoLocalizeTextLabel(newNumberLabel, GameTexts.MaxLevel.source, GameTexts.MaxLevel.key)
		TranslationTool.CustomAutoLocalizeTextLabel(textLabel, GameTexts.MaxLevel.source, GameTexts.MaxLevel.key)
		imageButton.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
	end
end

local function refreshAll()
	refreshFrame(upgradeWalkSpeedFrame1, GameConfig.SkillType.WalkSpeed, 1)
	refreshFrame(upgradeWalkSpeedFrame10, GameConfig.SkillType.WalkSpeed, 10)
	refreshFrame(upgradeMaxFuelFrame1, GameConfig.SkillType.MaxFuel, 1)
	refreshFrame(upgradeMaxFuelFrame10, GameConfig.SkillType.MaxFuel, 10)
	refreshFrame(upgradeMaxThrustSpeedFrame1, GameConfig.SkillType.MaxThrust, 1)
	refreshFrame(upgradeMaxThrustSpeedFrame10, GameConfig.SkillType.MaxThrust, 10)
end

local function updateCanvas()
	scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, uiListLayout.AbsoluteContentSize.Y * 2.5)
end
uiListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
updateCanvas()

local function bindButton(frame: Frame, skillType: number, levelAdd: number)
	local imageButton = frame:WaitForChild("ImageButton") :: ImageButton
	imageButton:SetAttribute("SkipButtonClickSound", true)
	imageButton.Activated:Connect(function()
		local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
		if not playerInfo then
			return
		end

		local abilityInfo = GameConfig.ShopAbilityByType[skillType]
		if not abilityInfo then
			return
		end

		local abilityName = abilityInfo.abilityName
		local currentLevel = (playerInfo.shopInfo :: any)[abilityInfo.levelField] or 1
		local canUpgrade, totalCost = getCostAndLimit(abilityName, currentLevel, levelAdd)

		if canUpgrade then
			local currentCoin = playerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
			if currentCoin >= totalCost then
				GameSoundManager.PlayUpgradeAbilitySound()
				NetMsg.SendRequestUpgradeSkill(skillType, levelAdd)
			else
				ClientMsg.FireShowGameTip(GameTexts.InsufficientCoin.source, GameConfig.GameTipTweenType.FlyUp, GameTexts.InsufficientCoin.key)
			end
		end
	end)
end

local function getMaxUpgradeableSteps(abilityName: string, currentLevel: number, levelAdd: number): number
	local shopData = GameConfig.Shop[abilityName]
	local nextLevel = currentLevel
	local steps = 0
	for _ = 1, levelAdd do
		local upgradeCost = shopData.upgradeCostList[nextLevel]
		if upgradeCost == nil then
			break
		end
		steps += 1
		nextLevel += 1
	end
	return steps
end

local function bindPaymentButton(frame: Frame, skillType: number, levelAdd: number, productId: number)
	local paymentButton = frame:WaitForChild("PaymentButton") :: any
	paymentButton.Activated:Connect(function()
		local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
		if not playerInfo then
			return
		end

		local abilityInfo = GameConfig.ShopAbilityByType[skillType]
		if not abilityInfo then
			return
		end

		local abilityName = abilityInfo.abilityName
		local currentLevel = (playerInfo.shopInfo :: any)[abilityInfo.levelField] or 1

		local maxSteps = getMaxUpgradeableSteps(abilityName, currentLevel, levelAdd)
		if maxSteps <= 0 then
			ClientMsg.FireShowGameTip(GameTexts.MaxLevel.source, GameConfig.GameTipTweenType.FlyUp, GameTexts.MaxLevel.key)
			return
		end

		if productId == 0 then
			warn(`[UpgradeShopFrame] ShopPaid productId is 0 for {abilityName}`)
			return
		end

		if not players.LocalPlayer then
			return
		end

		marketplaceService:PromptProductPurchase(players.LocalPlayer, productId)
	end)
end

bindButton(upgradeWalkSpeedFrame1, GameConfig.SkillType.WalkSpeed, 1)
bindButton(upgradeWalkSpeedFrame10, GameConfig.SkillType.WalkSpeed, 10)
bindButton(upgradeMaxFuelFrame1, GameConfig.SkillType.MaxFuel, 1)
bindButton(upgradeMaxFuelFrame10, GameConfig.SkillType.MaxFuel, 10)
bindButton(upgradeMaxThrustSpeedFrame1, GameConfig.SkillType.MaxThrust, 1)
bindButton(upgradeMaxThrustSpeedFrame10, GameConfig.SkillType.MaxThrust, 10)

bindPaymentButton(upgradeWalkSpeedFrame10, GameConfig.SkillType.WalkSpeed, 10, GameConfig.ShopPaid.WalkSpeed10ProductId)
bindPaymentButton(upgradeMaxFuelFrame10, GameConfig.SkillType.MaxFuel, 10, GameConfig.ShopPaid.MaxFuel10ProductId)
bindPaymentButton(upgradeMaxThrustSpeedFrame10, GameConfig.SkillType.MaxThrust, 10, GameConfig.ShopPaid.MaxThrust10ProductId)

local function OnCloseWindow(windowId: string)
	if windowId == thisFrame:GetAttribute("WindowId") then
		UIAdapter.RemoveAdaptiveFrame(thisFrame)
		thisFrame:Destroy()
	end
end

ClientMsg.ConnectLocalPlayerSkillLevelUpdate(function(skillType, level)
	refreshAll()
	if ABILITY_TIP_TEXTS[skillType] then
		showUpgradeTip(skillType, level)
	end
end)

ClientMsg.ConnectLocalPlayerCurrencyUpdate(function()
	refreshAll()
end)

ClientMsg.ConnectCloseWindow(OnCloseWindow)
refreshAll()

UIAdapter.AddAdaptiveFrame(thisFrame, UIAdapter.AdaptiveType.FullScreen)
