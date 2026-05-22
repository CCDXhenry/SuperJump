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

local function IsJetpackAffordable(jetpackData: GameConfig.JetpackData): boolean
	local coinCount = localPlayerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0

	if jetpackData.costType == GameConfig.CostType.Coin then
		return coinCount >= jetpackData.costCoin
	elseif jetpackData.costType == GameConfig.CostType.Rb then
		return false -- Rb 通过 ProductPurchase 购买，不由本地判定
	elseif jetpackData.costType == GameConfig.CostType.CoinOrRb then
		return coinCount >= jetpackData.costCoin
	elseif jetpackData.costType == GameConfig.CostType.GroupReward then
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
	local jetpackData = GameConfig.JetpackDataMap[equipIdLookAt]
	if not jetpackData then
		return
	end

	local infoFrame: Frame = thisFrame:FindFirstChild("InfoFrame") :: Frame
	local equipName: TextLabel = infoFrame:FindFirstChild("EquipName") :: TextLabel
	equipName.Text = jetpackData.name_t
	local icon: ImageLabel = infoFrame:FindFirstChild("Icon") :: ImageLabel
	icon.Image = jetpackData.iconImageId
	local fuelValue: TextLabel = infoFrame:FindFirstChild("FuelValue") :: TextLabel
	if fuelValue then
		fuelValue.Text = tostring(jetpackData.fuel)
	end
	local thrustValue: TextLabel = infoFrame:FindFirstChild("ThrustValue") :: TextLabel
	if thrustValue then
		thrustValue.Text = tostring(jetpackData.thrust)
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

	local isOwned = localPlayerInfo.jetpackInventory.ownedList[tostring(equipIdLookAt)]

	if not isOwned then
		if jetpackData.costType == GameConfig.CostType.GroupReward then
			buyBtn.Visible = false
			buyBtn31.Visible = false
			buyBtn32.Visible = false
			groupRewardText.Visible = true
			groupRewardBtn.Visible = true
		elseif jetpackData.costType == GameConfig.CostType.CoinOrRb then
			buyBtn.Visible = false
			buyBtn31.Visible = true
			buyBtn32.Visible = true
			groupRewardText.Visible = false
			groupRewardBtn.Visible = false

			local priceText31: TextLabel = buyBtn31:FindFirstChild("Price") :: TextLabel
			local priceText32: TextLabel = buyBtn32:FindFirstChild("Price") :: TextLabel
			priceText31.Text = NumberExtension.FormatBigNumberAA(jetpackData.costCoin)
			priceText32.Text = NumberExtension.FormatBigNumberAA(jetpackData.costRb)

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

			rb.Visible = (jetpackData.costType == GameConfig.CostType.Rb)
			coin.Visible = (jetpackData.costType == GameConfig.CostType.Coin)
			if jetpackData.costType == GameConfig.CostType.Coin then
				coin.Image = GameConfig.CoinIconImage
				priceText.Text = NumberExtension.FormatBigNumberAA(jetpackData.costCoin)
			else
				coin.Image = GameConfig.RbImage
				priceText.Text = NumberExtension.FormatBigNumberAA(jetpackData.costRb)
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
	elseif localPlayerInfo.jetpackInventory.currentId == tostring(equipIdLookAt) then
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

-- 请求更换火箭背包
local function ChangeJetpack()
	if equipIdLookAt == nil then
		return
	end
	if localPlayerInfo.jetpackInventory.currentId == tostring(equipIdLookAt) then
		return
	end
	NetMsg.FireRequestUpdateJetpackUsing(equipIdLookAt)
end

-- 更新选择框
local function RefreshSelectImage(jetpackId: number, equipBtn: ImageButton)
	if equipIdLookAt == jetpackId then
		if selectImg then
			selectImg.Visible = false
		end
		selectImg = equipBtn:FindFirstChild("SelectImg") :: ImageLabel
		if selectImg then
			selectImg.Visible = true
		end
	end
end

-- 生成选择火箭背包按钮
local function CreateSelectEquipBtn(jetpackId: number, jetpackData: GameConfig.JetpackData): ImageButton
	local equipBtn = equipBtnPre:Clone()
	equipBtn.Parent = scrollingFrame
	equipBtn.Visible = true
	local usingJetpackId = localPlayerInfo.jetpackInventory.currentId
	local equipImg: ImageLabel = equipBtn:FindFirstChild("EquipImg") :: ImageLabel

	-- 刷新背景/装备标志
	if usingJetpackId ~= tostring(jetpackId) then
		equipImg.Visible = false
	else
		equipImg.Visible = true
	end

	-- 刷新锁定标签
	local lockImg: ImageLabel = equipBtn:FindFirstChild("LockImg") :: ImageLabel
	local isOwned = localPlayerInfo.jetpackInventory.ownedList[tostring(jetpackId)]

	if not isOwned then
		lockImg.Visible = true
	else
		lockImg.Visible = false
	end

	local name: TextLabel = equipBtn:FindFirstChild("Name") :: TextLabel
	name.Text = jetpackData.name_t
	local icon: ImageLabel = equipBtn:FindFirstChild("Icon") :: ImageLabel
	icon.Image = jetpackData.iconImageId
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

			if jetpackData.costType == GameConfig.CostType.Coin then
				coin.Visible = true
				price.Visible = true
				price.Text = NumberExtension.FormatBigNumberAA(jetpackData.costCoin)
			elseif jetpackData.costType == GameConfig.CostType.Rb then
				rb.Visible = true
				price.Visible = true
				price.Text = NumberExtension.FormatBigNumberAA(jetpackData.costRb)
			elseif jetpackData.costType == GameConfig.CostType.GroupReward then
				groupReward.Visible = true
			else
				coin.Visible = true
				price.Visible = true
				price.Text = NumberExtension.FormatBigNumberAA(jetpackData.costCoin)
			end
		end
	end

	equipBtn.Activated:Connect(function()
		equipIdLookAt = jetpackId
		RefreshInfoFrame()
		RefreshSelectImage(jetpackId, equipBtn)
	end)

	RefreshSelectImage(jetpackId, equipBtn)

	return equipBtn
end

-- 刷新选择按钮
local function RefreshSelectFrame()
	for _, child in scrollingFrame:GetChildren() do
		if child:IsA("ImageButton") then
			child:Destroy()
		end
	end

	local sortedJetpacks = {} :: { { jetpackId: number, jetpackData: GameConfig.JetpackData } }
	for jetpackId, jetpackData in pairs(GameConfig.JetpackDataMap) do
		table.insert(sortedJetpacks, {
			jetpackId = jetpackId,
			jetpackData = jetpackData,
		})
	end
	table.sort(sortedJetpacks, function(a, b)
		return a.jetpackId < b.jetpackId
	end)

	local equipCount: number = 0
	local selectedBtn: ImageButton = nil
	local usingJetpackId = localPlayerInfo.jetpackInventory.currentId

	for _, sortedJetpack in ipairs(sortedJetpacks) do
		local jetpackId = sortedJetpack.jetpackId
		local jetpackData = sortedJetpack.jetpackData
		local btn: ImageButton = CreateSelectEquipBtn(jetpackId, jetpackData)
		equipCount += 1
		if tostring(jetpackId) == usingJetpackId then
			selectedBtn = btn
		end
	end

	-- 手动更新滑动框尺寸以适配各种屏幕
	scrollingFrame.CanvasSize =
		UDim2.new(0, 0, 0, math.ceil(equipCount / 3) * (uiGridLayout.CellSize.Y.Offset + uiGridLayout.CellPadding.Y.Offset))

	-- 自动滚动到当前火箭背包按钮
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

	-- 请求改变当前火箭背包
	equipBtn.Activated:Connect(function()
		ChangeJetpack()
	end)

	local function OnBuyBtnActivated(currencyType: number)
		if equipIdLookAt == nil then
			return
		end
		local jetpackData = GameConfig.JetpackDataMap[equipIdLookAt]
		if not jetpackData then
			return
		end

		if currencyType == GameConfig.CurrencyType.Coin then
			if localPlayerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] >= jetpackData.costCoin then
				NetMsg.FireRequestBuyJetpack(equipIdLookAt)
			else
				ClientMsg.FireShowGameTip(GameTexts.InsufficientCoin.source, GameConfig.GameTipTweenType.FlyUp)
			end
		elseif currencyType == GameConfig.CurrencyType.Rb then
			if jetpackData.productId and jetpackData.productId > 0 then
				marketplaceService:PromptProductPurchase(players.LocalPlayer, jetpackData.productId)
			else
				warn("No productId for jetpack", equipIdLookAt)
			end
		end
	end

	buyBtn.Activated:Connect(function()
		if equipIdLookAt == nil then
			return
		end
		local jetpackData = GameConfig.JetpackDataMap[equipIdLookAt]
		if not jetpackData then
			return
		end
		if jetpackData.costType == GameConfig.CostType.Coin then
			OnBuyBtnActivated(GameConfig.CurrencyType.Coin)
		elseif jetpackData.costType == GameConfig.CostType.Rb then
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
		groupRewardBtn.Activated:Connect(function()
			if equipIdLookAt == nil then
				return
			end
			local jetpackData = GameConfig.JetpackDataMap[equipIdLookAt]
			if not jetpackData or jetpackData.costType ~= GameConfig.CostType.GroupReward then
				return
			end

			task.spawn(function()
				local success, isInGroup = pcall(function()
					return players.LocalPlayer:IsInGroupAsync(GameConfig.SixcubeGroupId)
				end)
				local canClaim = success and isInGroup
				NetMsg.FireRequestClaimJetpackGroupReward(canClaim)
				if not canClaim then
					ClientMsg.FireShowGameTip("Join the group to get the exclusive jetpack for free!", GameConfig.GameTipTweenType.FlyUp)
				end
			end)
		end)
	end

	equipBtnPre.Visible = false
	equipBtnPre.Parent = nil

	equipIdLookAt = tonumber(localPlayerInfo.jetpackInventory.currentId) or 1
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
NetMsg.ConnectNotifyPlayerJetpackInventoryUpdate(function(inventory: GameConfig.JetpackInventory)
	ClientGameInfo.UpdateJetpackInventory(inventory)
	localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	RefreshFrame()
end)
InitFrame()
marketplaceService.PromptProductPurchaseFinished:Connect(OnPurchaseFinished)
