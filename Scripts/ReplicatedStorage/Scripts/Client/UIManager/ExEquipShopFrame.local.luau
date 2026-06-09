--!strict
local replicatedStorage = game:GetService("ReplicatedStorage")
local scriptsFolder = replicatedStorage:FindFirstChild("Scripts")
local sharedScripts = scriptsFolder:FindFirstChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scriptsFolder:FindFirstChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local UIManager = require(clientScripts:FindFirstChild("UIManager"))
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local GameSoundManager = require(clientScripts:FindFirstChild("GameSoundManager"))
local players = game:GetService("Players")
local marketplaceService = game:GetService("MarketplaceService")
local core = replicatedStorage:FindFirstChild("Core")
local coreScripts = core:FindFirstChild("Scripts")
local coreClientScripts = coreScripts:FindFirstChild("Client")
local sharedScripts2 = coreScripts:FindFirstChild("Shared")
local NumberExtension = require(sharedScripts2:FindFirstChild("NumberExtension"))
local TranslationTool = require(coreClientScripts:FindFirstChild("TranslationTool"))
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local tweenService = game:GetService("TweenService")

if players.LocalPlayer == nil then
	return
end

local thisFrame: Frame = script.Parent
local windowId: string = thisFrame:GetAttribute("WindowId") :: string
local closeButton: ImageButton = thisFrame:FindFirstChild("CloseButton") :: ImageButton
local scrollingFrame: ScrollingFrame = thisFrame:FindFirstChild("ScrollingFrame") :: ScrollingFrame
local equipBtnPre: ImageButton = scrollingFrame:FindFirstChild("EquipItemBtnTemplate") :: ImageButton
local uiGridLayout: UIGridLayout = scrollingFrame:FindFirstChild("UIGridLayout") :: UIGridLayout

local equipIdLookAt: number
local selectImg: ImageLabel

local firstOpenFrame: boolean = true

local localPlayerInfo: GameConfig.ClientLocalPlayerInfo? = ClientGameInfo.GetLocalPlayerInfo()
if localPlayerInfo == nil then
	return
end

local function IsExEquipAffordable(equipData: GameConfig.ExEquipData): boolean
	local coinCount = localPlayerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0

	if equipData.costType == GameConfig.CostType.Coin then
		return coinCount >= equipData.costCoin
	elseif equipData.costType == GameConfig.CostType.Rb then
		return false -- Rb 通过 ProductPurchase 购买，不由本地判定
	elseif equipData.costType == GameConfig.CostType.CoinOrRb then
		return coinCount >= equipData.costCoin
	elseif equipData.costType == GameConfig.CostType.GroupReward then
		return false -- 群组奖励由服务器端验证
	end

	return false
end

local function PlayBuyBtnIntroAnim(buyBtn: ImageButton)
	if buyBtn:GetAttribute("IntroPlayed") then
		return
	end
	buyBtn:SetAttribute("IntroPlayed", true)
	local scale: UIScale = buyBtn:FindFirstChildOfClass("UIScale") :: UIScale

	local tween1 = tweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Scale = 1.1 })
	tween1:Play()
end

local function RefreshInfoFrame()
	if equipIdLookAt == nil then
		return
	end
	local equipData = GameConfig.ExEquipDataMap[equipIdLookAt]
	if not equipData then
		return
	end

	local infoFrame: Frame = thisFrame:FindFirstChild("InfoFrame") :: Frame
	local equipName: TextLabel = infoFrame:FindFirstChild("EquipName") :: TextLabel
	TranslationTool.CustomAutoLocalizeTextLabel(equipName, equipData.name_t, "")
	local icon: ImageLabel = infoFrame:FindFirstChild("Icon") :: ImageLabel
	icon.Image = equipData.iconImageId
	local jumpHeightValue: TextLabel = infoFrame:FindFirstChild("JumpHeightValue") :: TextLabel
	if jumpHeightValue then
		TranslationTool.CustomAutoLocalizeTextLabel(
			jumpHeightValue,
			GameTexts.JumpHeightPerSecond.source,
			GameTexts.JumpHeightPerSecond.key,
			{ NumberExtension.FormatBigNumberAA(equipData.ability) }
		)
	end

	-- 刷新购买按钮
	local buyBtn: ImageButton = infoFrame:FindFirstChild("BuyBtn") :: ImageButton
	local buyBtn31: ImageButton = infoFrame:FindFirstChild("BuyBtn3-1") :: ImageButton
	local buyBtn32: ImageButton = infoFrame:FindFirstChild("BuyBtn3-2") :: ImageButton
	local groupRewardText: TextLabel = infoFrame:FindFirstChild("GroupRewardText") :: TextLabel
	local groupRewardBtn: ImageButton = infoFrame:FindFirstChild("GroupRewardBtn") :: ImageButton
	local equipBtn: ImageButton = infoFrame:FindFirstChild("EquipBtn") :: ImageButton
	local equip: ImageLabel = equipBtn:FindFirstChild("Equip") :: ImageLabel
	local equipped: ImageLabel = equipBtn:FindFirstChild("Equipped") :: ImageLabel

	local isOwned = localPlayerInfo.exEquipInventory.ownedList[tostring(equipIdLookAt)]

	if not isOwned then
		if equipData.costType == GameConfig.CostType.GroupReward then
			buyBtn.Visible = false
			buyBtn31.Visible = false
			buyBtn32.Visible = false
			groupRewardText.Visible = true
			groupRewardBtn.Visible = true
		elseif equipData.costType == GameConfig.CostType.CoinOrRb then
			buyBtn.Visible = false
			buyBtn31.Visible = true
			buyBtn32.Visible = true
			groupRewardText.Visible = false
			groupRewardBtn.Visible = false

			local priceText31: TextLabel = buyBtn31:FindFirstChild("Price") :: TextLabel
			local priceText32: TextLabel = buyBtn32:FindFirstChild("Price") :: TextLabel
			priceText31.Text = NumberExtension.FormatBigNumberAA(equipData.costCoin)
			priceText32.Text = NumberExtension.FormatBigNumberAA(equipData.costRb)

			PlayBuyBtnIntroAnim(buyBtn31)
			PlayBuyBtnIntroAnim(buyBtn32)
		else
			buyBtn.Visible = true
			buyBtn31.Visible = false
			buyBtn32.Visible = false
			groupRewardText.Visible = false
			groupRewardBtn.Visible = false

			local rb: ImageLabel = buyBtn:FindFirstChild("Rb") :: ImageLabel
			local coin: ImageLabel = buyBtn:FindFirstChild("Coin") :: ImageLabel
			local priceText: TextLabel = buyBtn:FindFirstChild("Price") :: TextLabel

			rb.Visible = (equipData.costType == GameConfig.CostType.Rb)
			coin.Visible = (equipData.costType == GameConfig.CostType.Coin)
			if equipData.costType == GameConfig.CostType.Coin then
				coin.Image = GameConfig.CoinIconImage
				priceText.Text = NumberExtension.FormatBigNumberAA(equipData.costCoin)
			else
				coin.Image = GameConfig.RbImage
				priceText.Text = NumberExtension.FormatBigNumberAA(equipData.costRb)
			end

			PlayBuyBtnIntroAnim(buyBtn)
		end
	else
		buyBtn.Visible = false
		buyBtn31.Visible = false
		buyBtn32.Visible = false
		groupRewardText.Visible = false
		groupRewardBtn.Visible = false
		buyBtn:SetAttribute("IntroPlayed", false)
		if buyBtn31 then buyBtn31:SetAttribute("IntroPlayed", false) end
		if buyBtn32 then buyBtn32:SetAttribute("IntroPlayed", false) end

		local function ResetScale(btn: ImageButton)
			local s = btn:FindFirstChildOfClass("UIScale")
			if s then s.Scale = 1 end
		end
		ResetScale(buyBtn)
		if buyBtn31 then ResetScale(buyBtn31) end
		if buyBtn32 then ResetScale(buyBtn32) end
	end

	-- 刷新装备按钮
	if not isOwned then
		equipBtn.Visible = false
		equipBtn.Active = false
	elseif localPlayerInfo.exEquipInventory.currentId == tostring(equipIdLookAt) then
		equipBtn.Visible = true
		equipBtn.Active = false
		equip.Visible = false
		equipped.Visible = true
	else
		equipBtn.Visible = true
		equipBtn.Active = true
		equip.Visible = true
		equipped.Visible = false
	end
end

-- 请求更换器材
local function ChangeExEquip()
	if equipIdLookAt == nil then
		return
	end
	if localPlayerInfo.exEquipInventory.currentId == tostring(equipIdLookAt) then
		return
	end
	NetMsg.FireRequestUpdateExEquipUsing(equipIdLookAt)
end

-- 更新选择框
local function RefreshSelectImage(equipId: number, equipBtn: ImageButton)
	if equipIdLookAt == equipId then
		if selectImg then
			selectImg.Visible = false
		end
		selectImg = equipBtn:FindFirstChild("SelectImg") :: ImageLabel
		if selectImg then
			selectImg.Visible = true
		end
	end
end

-- 生成选择器材按钮
local function CreateSelectEquipBtn(equipId: number, equipData: GameConfig.ExEquipData): ImageButton
	local equipBtn = equipBtnPre:Clone()
	equipBtn.Parent = scrollingFrame
	equipBtn.Visible = true
	equipBtn:SetAttribute("equipId", equipId)
	local usingEquipId = localPlayerInfo.exEquipInventory.currentId
	local equipImg: ImageLabel = equipBtn:FindFirstChild("EquipImg") :: ImageLabel

	-- 刷新背景/装备标志
	if usingEquipId ~= tostring(equipId) then
		equipImg.Visible = false
	else
		equipImg.Visible = true
	end

	-- 刷新锁定标签
	local lockImg: ImageLabel = equipBtn:FindFirstChild("LockImg") :: ImageLabel
	local isOwned = localPlayerInfo.exEquipInventory.ownedList[tostring(equipId)]

	if not isOwned then
		lockImg.Visible = true
	else
		lockImg.Visible = false
	end

	local name: TextLabel = equipBtn:FindFirstChild("Name") :: TextLabel
	TranslationTool.CustomAutoLocalizeTextLabel(name, equipData.name_t, "")
	local icon: ImageLabel = equipBtn:FindFirstChild("Icon") :: ImageLabel
	icon.Image = equipData.iconImageId
	local costFrame: Frame = equipBtn:FindFirstChild("CostFrame") :: Frame
	if costFrame then
		local coin: ImageLabel = costFrame:FindFirstChild("Coin") :: ImageLabel
		local rb: ImageLabel = costFrame:FindFirstChild("Rb") :: ImageLabel
		local price: TextLabel = costFrame:FindFirstChild("Price") :: TextLabel
		local groupReward: TextLabel = costFrame:FindFirstChild("GroupReward") :: TextLabel

		costFrame.Visible = not isOwned
		if not isOwned then
			coin.Visible = false
			rb.Visible = false
			price.Visible = false
			groupReward.Visible = false

			if equipData.costType == GameConfig.CostType.Coin then
				coin.Visible = true
				price.Visible = true
				price.Text = NumberExtension.FormatBigNumberAA(equipData.costCoin)
			elseif equipData.costType == GameConfig.CostType.Rb then
				rb.Visible = true
				price.Visible = true
				price.Text = NumberExtension.FormatBigNumberAA(equipData.costRb)
			elseif equipData.costType == GameConfig.CostType.GroupReward then
				groupReward.Visible = true
			else
				coin.Visible = true
				price.Visible = true
				price.Text = NumberExtension.FormatBigNumberAA(equipData.costCoin)
			end
		end
	end

	equipBtn.Activated:Connect(function()
		equipIdLookAt = equipId
		RefreshInfoFrame()
		RefreshSelectImage(equipId, equipBtn)
	end)

	RefreshSelectImage(equipId, equipBtn)

	return equipBtn
end

-- 刷新选择按钮
local function RefreshSelectFrame()
	for _, child in scrollingFrame:GetChildren() do
		if child:IsA("ImageButton") then
			child:Destroy()
		end
	end

	local sortedEquips = {} :: { { equipId: number, equipData: GameConfig.ExEquipData } }
	for equipId, equipData in pairs(GameConfig.ExEquipDataMap) do
		table.insert(sortedEquips, {
			equipId = equipId,
			equipData = equipData,
		})
	end
	table.sort(sortedEquips, function(a, b)
		return a.equipId < b.equipId
	end)

	local equipCount: number = 0
	local selectedBtn: ImageButton = nil
	local usingEquipId = localPlayerInfo.exEquipInventory.currentId

	for _, sortedEquip in ipairs(sortedEquips) do
		local equipId = sortedEquip.equipId
		local equipData = sortedEquip.equipData
		local btn: ImageButton = CreateSelectEquipBtn(equipId, equipData)
		equipCount += 1
		if tostring(equipId) == usingEquipId then
			selectedBtn = btn
		end
	end

	-- 手动更新滑动框尺寸以适配各种屏幕
	scrollingFrame.CanvasSize =
		UDim2.new(0, 0, 0, math.ceil(equipCount / 3) * (uiGridLayout.CellSize.Y.Offset + uiGridLayout.CellPadding.Y.Offset))

	-- 自动滚动到当前器材按钮
	if selectedBtn then
		if firstOpenFrame then
			firstOpenFrame = false
			task.wait()

			local localY: number = selectedBtn.AbsolutePosition.Y - scrollingFrame.AbsolutePosition.Y + scrollingFrame.CanvasPosition.Y - 200

			local maxY = scrollingFrame.CanvasSize.Y.Offset - scrollingFrame.AbsoluteWindowSize.Y
			local targetY = math.clamp(localY, 0, math.max(maxY, 0))

			local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tween = tweenService:Create(scrollingFrame, tweenInfo, { CanvasPosition = Vector2.new(0, targetY) })
			tween:Play()
		end
	end
end

local function RefreshFrame()
	RefreshSelectFrame()
	RefreshInfoFrame()
end

local function InitFrame()
	local infoFrame: Frame = thisFrame:FindFirstChild("InfoFrame") :: Frame
	local buyBtn: ImageButton = infoFrame:FindFirstChild("BuyBtn") :: ImageButton
	local buyBtn31: ImageButton = infoFrame:FindFirstChild("BuyBtn3-1") :: ImageButton
	local buyBtn32: ImageButton = infoFrame:FindFirstChild("BuyBtn3-2") :: ImageButton
	local groupRewardBtn: ImageButton = infoFrame:FindFirstChild("GroupRewardBtn") :: ImageButton
	local equipBtn: ImageButton = infoFrame:FindFirstChild("EquipBtn") :: ImageButton

	-- 请求改变当前器材
	equipBtn.Activated:Connect(function()
		ChangeExEquip()
	end)

	local function OnBuyBtnActivated(currencyType: number)
		if equipIdLookAt == nil then
			return
		end
		local equipData = GameConfig.ExEquipDataMap[equipIdLookAt]
		if not equipData then
			return
		end

		if currencyType == GameConfig.CurrencyType.Coin then
			if localPlayerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] >= equipData.costCoin then
				NetMsg.FireRequestBuyExEquip(equipIdLookAt)
			else
				ClientMsg.FireShowGameTip(GameTexts.InsufficientCoin.source, GameConfig.GameTipTweenType.FlyUp, GameTexts.InsufficientCoin.key)
			end
		elseif currencyType == GameConfig.CurrencyType.Rb then
			if equipData.productId and equipData.productId > 0 then
				NetMsg.FireRequestBuyExEquipPaid(equipIdLookAt)
			else
				warn("No productId for exEquip", equipIdLookAt)
			end
		end
	end

	local function OnGroupRewardBtnActivated()
		if equipIdLookAt == nil then
			return
		end
		local equipData = GameConfig.ExEquipDataMap[equipIdLookAt]
		if not equipData or equipData.costType ~= GameConfig.CostType.GroupReward then
			return
		end

		task.spawn(function()
			local success, isInGroup = pcall(function()
				return players.LocalPlayer:IsInGroupAsync(GameConfig.SixcubeGroupId)
			end)
			local canClaim = success and isInGroup
			NetMsg.FireRequestClaimGroupReward(canClaim)
			if not canClaim then
				ClientMsg.FireShowGameTip(
					GameTexts.ExEquipGroupRewardJoinHint.source,
					GameConfig.GameTipTweenType.FlyUp,
					GameTexts.ExEquipGroupRewardJoinHint.key
				)
			end
		end)
	end

	buyBtn.Activated:Connect(function()
		if equipIdLookAt == nil then
			return
		end
		local equipData = GameConfig.ExEquipDataMap[equipIdLookAt]
		if not equipData then
			return
		end
		if equipData.costType == GameConfig.CostType.Coin then
			OnBuyBtnActivated(GameConfig.CurrencyType.Coin)
		elseif equipData.costType == GameConfig.CostType.Rb then
			OnBuyBtnActivated(GameConfig.CurrencyType.Rb)
		end
	end)

	if buyBtn31 then
		buyBtn31.Activated:Connect(function()
			OnBuyBtnActivated(GameConfig.CurrencyType.Coin)
		end)
	end

	if buyBtn32 then
		buyBtn32.Activated:Connect(function()
			OnBuyBtnActivated(GameConfig.CurrencyType.Rb)
		end)
	end

	if groupRewardBtn then
		groupRewardBtn.Activated:Connect(OnGroupRewardBtnActivated)
	end

	equipBtnPre.Visible = false
	equipBtnPre.Parent = nil

	equipIdLookAt = tonumber(localPlayerInfo.exEquipInventory.currentId) or 1
	RefreshFrame()
end

local function OnCloseWindow(closeWindowId: string)
	if closeWindowId == windowId then
		UIAdapter.RemoveAdaptiveFrame(thisFrame)
		thisFrame:Destroy()
	end
end

local function OnCloseButtonActivated()
	UIManager.CloseWindow(windowId)
end

local function OnPurchaseFinished(userId: number, productId: number, isPurchased: boolean)
	if userId ~= players.LocalPlayer.UserId then
		return
	end
end

UIAdapter.AddAdaptiveFrame(thisFrame, UIAdapter.AdaptiveType.Center)
ClientMsg.ConnectCloseWindow(OnCloseWindow)
closeButton.Activated:Connect(OnCloseButtonActivated)
ClientMsg.ConnectLocalPlayerInfoInit(function()
	InitFrame()
end)
NetMsg.ConnectNotifyPlayerExEquipInventoryUpdate(function(inventory: GameConfig.ExEquipInventory)
	ClientGameInfo.UpdateExEquipInventory(inventory)
	localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	RefreshFrame()
end)
InitFrame()
marketplaceService.PromptProductPurchaseFinished:Connect(OnPurchaseFinished)
