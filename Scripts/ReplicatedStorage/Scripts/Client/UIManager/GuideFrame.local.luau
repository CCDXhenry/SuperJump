--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local runService: RunService = game:GetService("RunService")
local players: Players = game:GetService("Players")
local localPlayer: Player? = players.LocalPlayer
if localPlayer == nil then
	warn("[GuideFrame] LocalPlayer is nil at module load")
end
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local tweenService: TweenService = game:GetService("TweenService")
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local GuideManager = require(clientScripts:FindFirstChild("GuideManager"))

local guideFrame: Frame = script.Parent
guideFrame.AnchorPoint = Vector2.new(0.5, 0.5)

local fingerImage: ImageLabel = guideFrame:WaitForChild("FingerImage") :: ImageLabel
local fingerImageScale: UIScale = fingerImage:WaitForChild("UIScale") :: UIScale
local operationTypeValue: IntValue = guideFrame:WaitForChild("OperationType") :: IntValue

local FINGER_PULSE_MIN_SCALE = 0.78
local FINGER_SHOP_SCROLL_ITEM_SCALE = 0.5
local FINGER_PULSE_TWEEN_INFO: TweenInfo =
	TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local FINGER_CLONE_NAME = "GuideFingerClone"
local FINGER_ZINDEX_BOOST = 50
local FINGER_PARENT_ZINDEX = 99

local fingerPulseTween: Tween? = nil
local fingerClone: ImageLabel? = nil
local fingerZIndexTarget: GuiObject? = nil
local fingerZIndexOriginal: number? = nil

local function RestoreFingerParentZIndex()
	if fingerZIndexTarget ~= nil and fingerZIndexOriginal ~= nil then
		fingerZIndexTarget.ZIndex = fingerZIndexOriginal
	end
	fingerZIndexTarget = nil
	fingerZIndexOriginal = nil
end

local function StopGuideAni()
	if fingerPulseTween ~= nil then
		fingerPulseTween:Cancel()
		fingerPulseTween = nil
	end
	if fingerClone ~= nil then
		fingerClone:Destroy()
		fingerClone = nil
	end
	RestoreFingerParentZIndex()
	fingerImage.Visible = false
	fingerImageScale.Scale = 1
end

local function StartPulseOnScale(scaleObj: UIScale, baseScale: number?)
	local scale = baseScale or 1
	if fingerPulseTween ~= nil then
		fingerPulseTween:Cancel()
		fingerPulseTween = nil
	end
	scaleObj.Scale = scale
	fingerPulseTween = tweenService:Create(
		scaleObj,
		FINGER_PULSE_TWEEN_INFO,
		{ Scale = scale * FINGER_PULSE_MIN_SCALE }
	)
	fingerPulseTween:Play()
end

local function GetShopScrollingFrameFingerScale(btn: GuiButton): number
	local parent = btn.Parent
	if parent ~= nil and parent:IsA("ScrollingFrame") then
		return FINGER_SHOP_SCROLL_ITEM_SCALE
	end
	return 1
end

-- 将 FingerImage 克隆到 target 子级，在目标局部中心做缩放动画
local function MountFingerCloneUnder(target: GuiObject, fingerBaseScale: number?)
	StopGuideAni()
	fingerZIndexTarget = target
	fingerZIndexOriginal = target.ZIndex
	target.ZIndex = FINGER_PARENT_ZINDEX
	local clone = fingerImage:Clone()
	clone.Name = FINGER_CLONE_NAME
	clone.Visible = true
	clone.ZIndex = target.ZIndex + FINGER_ZINDEX_BOOST
	clone.Parent = target
	fingerImage.Visible = false
	fingerClone = clone
	local scale = clone:WaitForChild("UIScale") :: UIScale
	StartPulseOnScale(scale, fingerBaseScale)
end

local function IsGuiVisibleChain(gui: GuiObject): boolean
	local current: Instance? = gui
	while current ~= nil and current:IsA("GuiObject") do
		if not (current :: GuiObject).Visible then
			return false
		end
		current = current.Parent
	end
	return true
end

-- BottomButtonsFrame 下仅 Brainrot 槽位可引导去放置展台：按队列找第一个 Brainrot 对应槽位
local function FindLobbyBrainrotSlotButton(): GuiButton?
	if localPlayer == nil then
		return nil
	end
	local playerGui = localPlayer:FindFirstChild("PlayerGui") :: PlayerGui?
	if playerGui == nil then
		return nil
	end
	local screenGui = playerGui:FindFirstChild("GameScreenGui") :: ScreenGui?
	if screenGui == nil then
		return nil
	end
	local lobby = screenGui:FindFirstChild("LobbyFrame") :: Frame?
	if lobby == nil then
		return nil
	end
	local bottom = lobby:FindFirstChild("BottomButtonsFrame") :: Frame?
	if bottom == nil then
		return nil
	end
	local queue = ClientGameInfo.GetBrainrotQueue()
	for _, item in ipairs(queue) do
		if (item.itemType or GameConfig.ItemType.Brainrot) ~= GameConfig.ItemType.Brainrot then
			continue
		end
		for _, child in bottom:GetChildren() do
			if not child:IsA("GuiButton") then
				continue
			end
			if child:GetAttribute("slotType") ~= "Brainrot" then
				continue
			end
			local uid = child:GetAttribute("uid")
			if uid ~= nil and tostring(uid) == tostring(item.uid) then
				return child :: GuiButton
			end
		end
	end
	return nil
end

local function GetPlaceModelIndexFromUpgradeAdornee(adornee: BasePart): string?
	local current: Instance? = adornee
	while current ~= nil do
		local idxStr = string.match(current.Name, "^PlaceModel(%d+)$")
		if idxStr ~= nil then
			return idxStr
		end
		current = current.Parent
	end
	return nil
end

-- 展台 UpgradeUI（PlayerGui 内 SurfaceGui）上可负担升级的 ClickButton，优先离玩家最近
local function FindBrainrotUpgradeClickButton(): GuiButton?
	if localPlayer == nil then
		return nil
	end
	local localInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localInfo == nil or localInfo.homeSlot == nil or localInfo.homeSlot == "" then
		return nil
	end
	local playerGui = localPlayer:FindFirstChild("PlayerGui") :: PlayerGui?
	if playerGui == nil then
		return nil
	end
	local coinCount = localInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
	local character = localPlayer.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local origin = if hrp then hrp.Position else nil

	local bestBtn: GuiButton? = nil
	local bestDist = math.huge
	local fallbackBtn: GuiButton? = nil

	for _, gui in ipairs(playerGui:GetChildren()) do
		if not gui:IsA("SurfaceGui") or gui.Name ~= "UpgradeUI" or not gui.Enabled then
			continue
		end
		local adornee = gui.Adornee
		if adornee == nil or not adornee:IsA("BasePart") then
			continue
		end
		local pointIndexStr = GetPlaceModelIndexFromUpgradeAdornee(adornee)
		if pointIndexStr == nil then
			continue
		end
		local placed = localInfo.homeInfo.placedModels[pointIndexStr]
		if placed == nil then
			continue
		end
		local brainrotData = GameConfig.BrainrotIdMap[placed.configId]
		if brainrotData == nil then
			continue
		end
		local upgradeCost = GameConfig.GetBrainrotUpgradeCost(brainrotData.baseAbility, placed.level)
		if coinCount < upgradeCost then
			continue
		end
		local clickBtn = gui:FindFirstChild("ClickButton", true)
		if clickBtn == nil or not clickBtn:IsA("GuiButton") then
			continue
		end
		if not IsGuiVisibleChain(clickBtn) then
			continue
		end
		if fallbackBtn == nil then
			fallbackBtn = clickBtn
		end
		if origin ~= nil then
			local dist = ((adornee :: BasePart).Position - origin).Magnitude
			if dist < bestDist then
				bestDist = dist
				bestBtn = clickBtn
			end
		end
	end
	return bestBtn or fallbackBtn
end

local function FindUpgradeShopWalkSpeedButton(): GuiButton?
	if localPlayer == nil then
		return nil
	end
	local playerGui = localPlayer:FindFirstChild("PlayerGui") :: PlayerGui?
	if playerGui == nil then
		return nil
	end
	local screenGui = playerGui:FindFirstChild("GameScreenGui") :: ScreenGui?
	if screenGui == nil then
		return nil
	end
	local shopFrame = screenGui:FindFirstChild("UpgradeShopFrame", true) :: Frame?
	if shopFrame == nil then
		return nil
	end
	local scroll = shopFrame:FindFirstChild("ScrollingFrame") :: ScrollingFrame?
	if scroll == nil then
		return nil
	end
	local row = scroll:FindFirstChild("UpgradeWalkSpeedFrame1") :: Frame?
	if row == nil then
		return nil
	end
	local imgBtn = row:FindFirstChild("ImageButton")
	if imgBtn and imgBtn:IsA("GuiButton") then
		return imgBtn
	end
	return nil
end

local function FindGameScreenGui(): ScreenGui?
	if localPlayer == nil then
		return nil
	end
	local playerGui = localPlayer:FindFirstChild("PlayerGui") :: PlayerGui?
	if playerGui == nil then
		return nil
	end
	return playerGui:FindFirstChild("GameScreenGui") :: ScreenGui?
end

local function FindShopFrame(windowFrameName: string): Frame?
	local screenGui = FindGameScreenGui()
	if screenGui == nil then
		return nil
	end
	local frame = screenGui:FindFirstChild(windowFrameName, true)
	if frame ~= nil and frame:IsA("Frame") then
		return frame
	end
	return nil
end

local function FindShopBuyButton(windowFrameName: string): GuiButton?
	local shopFrame = FindShopFrame(windowFrameName)
	if shopFrame == nil then
		return nil
	end
	local infoFrame = shopFrame:FindFirstChild("InfoFrame")
	if infoFrame == nil or not infoFrame:IsA("Frame") then
		return nil
	end
	local coinOrRbBuyBtn = infoFrame:FindFirstChild("BuyBtn3-1")
	if coinOrRbBuyBtn ~= nil and coinOrRbBuyBtn:IsA("GuiButton") and coinOrRbBuyBtn.Visible then
		return coinOrRbBuyBtn
	end
	local buyBtn = infoFrame:FindFirstChild("BuyBtn")
	if buyBtn ~= nil and buyBtn:IsA("GuiButton") and buyBtn.Visible then
		return buyBtn
	end
	return nil
end

local function GetLocalCoinCount(): number
	local localInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localInfo == nil then
		return 0
	end
	return localInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
end

local function FindSelectedShopItemButton(windowFrameName: string): GuiButton?
	local shopFrame = FindShopFrame(windowFrameName)
	if shopFrame == nil then
		return nil
	end
	local scrollingFrame = shopFrame:FindFirstChild("ScrollingFrame")
	if scrollingFrame == nil or not scrollingFrame:IsA("ScrollingFrame") then
		return nil
	end
	for _, child in scrollingFrame:GetChildren() do
		if child:IsA("GuiButton") and child.Visible then
			local selectImg = child:FindFirstChild("SelectImg")
			if selectImg and selectImg:IsA("GuiObject") and selectImg.Visible then
				return child
			end
		end
	end
	return nil
end

local function CanAffordJetpackByCoin(jetpackId: number): boolean
	local jetpackData = GameConfig.JetpackDataMap[jetpackId]
	if jetpackData == nil then
		return false
	end
	local localInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localInfo == nil then
		return false
	end
	if localInfo.jetpackInventory.ownedList[tostring(jetpackId)] == true then
		return false
	end
	local coinCount = GetLocalCoinCount()
	if jetpackData.costType == GameConfig.CostType.Coin or jetpackData.costType == GameConfig.CostType.CoinOrRb then
		return coinCount >= jetpackData.costCoin
	end
	return false
end

local function CanAffordExEquipByCoin(equipId: number): boolean
	local equipData = GameConfig.ExEquipDataMap[equipId]
	if equipData == nil then
		return false
	end
	local localInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localInfo == nil then
		return false
	end
	if localInfo.exEquipInventory.ownedList[tostring(equipId)] == true then
		return false
	end
	local coinCount = GetLocalCoinCount()
	if equipData.costType == GameConfig.CostType.Coin or equipData.costType == GameConfig.CostType.CoinOrRb then
		return coinCount >= equipData.costCoin
	end
	return false
end

local function FindFirstItemButtonByOrder(windowFrameName: string): GuiButton?
	local shopFrame = FindShopFrame(windowFrameName)
	if shopFrame == nil then
		return nil
	end
	local scrollingFrame = shopFrame:FindFirstChild("ScrollingFrame")
	if scrollingFrame == nil or not scrollingFrame:IsA("ScrollingFrame") then
		return nil
	end
	local bestButton: GuiButton? = nil
	local bestOrder = math.huge
	for _, child in scrollingFrame:GetChildren() do
		if child:IsA("GuiButton") and child.Visible then
			if child.LayoutOrder < bestOrder then
				bestButton = child
				bestOrder = child.LayoutOrder
			end
		end
	end
	return bestButton
end

local function FindJetpackGuideButton(): GuiButton?
	local selectedBtn = FindSelectedShopItemButton("JetpackShopFrame")
	if selectedBtn ~= nil then
		local selectedId = selectedBtn:GetAttribute("equipId")
		if typeof(selectedId) == "number" and CanAffordJetpackByCoin(selectedId) then
			return FindShopBuyButton("JetpackShopFrame")
		end
	end

	local firstBtn = FindFirstItemButtonByOrder("JetpackShopFrame")
	if firstBtn ~= nil then
		local firstId = firstBtn:GetAttribute("equipId")
		if typeof(firstId) == "number" and CanAffordJetpackByCoin(firstId) then
			return firstBtn
		end
	end
	return nil
end

local function FindExEquipItemButtonById(equipId: number): GuiButton?
	local shopFrame = FindShopFrame("ExEquipShopFrame")
	if shopFrame == nil then
		return nil
	end
	local scrollingFrame = shopFrame:FindFirstChild("ScrollingFrame")
	if scrollingFrame == nil or not scrollingFrame:IsA("ScrollingFrame") then
		return nil
	end
	for _, child in scrollingFrame:GetChildren() do
		if child:IsA("GuiButton") and child.Visible then
			local childEquipId = child:GetAttribute("equipId")
			if typeof(childEquipId) == "number" and childEquipId == equipId then
				return child
			end
		end
	end
	return nil
end

local function FindExEquipGuideButton(): GuiButton?
	local targetEquipId = GuideManager.GetCurrentExEquipBuyGuideTargetId()
	if targetEquipId == nil or not CanAffordExEquipByCoin(targetEquipId) then
		return nil
	end

	local selectedBtn = FindSelectedShopItemButton("ExEquipShopFrame")
	if selectedBtn ~= nil then
		local selectedId = selectedBtn:GetAttribute("equipId")
		if typeof(selectedId) == "number" and selectedId == targetEquipId then
			return FindShopBuyButton("ExEquipShopFrame")
		end
	end

	return FindExEquipItemButtonById(targetEquipId)
end

local function ResolveShopTutorialGuideButton(guideType: number): GuiButton?
	if guideType == GameConfig.GuideType.TutorialJetpackBuy then
		return FindJetpackGuideButton()
	end
	if guideType == GameConfig.GuideType.TutorialExEquipBuy then
		return FindExEquipGuideButton()
	end
	if guideType == GameConfig.GuideType.TutorialWalkSpeedUpgrade then
		return FindUpgradeShopWalkSpeedButton()
	end
	return nil
end

local function FindExEquipBackpackSlotButton(): GuiButton?
	local screenGui = FindGameScreenGui()
	if screenGui == nil then
		return nil
	end
	local lobby = screenGui:FindFirstChild("LobbyFrame") :: Frame?
	if lobby == nil then
		return nil
	end
	local bottom = lobby:FindFirstChild("BottomButtonsFrame") :: Frame?
	if bottom == nil then
		return nil
	end
	for _, child in bottom:GetChildren() do
		if child:IsA("GuiButton") and child:GetAttribute("slotType") == "ExEquip" then
			return child
		end
	end
	return nil
end

local function IsOutsideRunwaySessionGuideType(guideType: number): boolean
	return guideType == GameConfig.GuideType.TutorialBrainrotCollect
		or guideType == GameConfig.GuideType.TutorialBrainrotUpgrade
		or guideType == GameConfig.GuideType.TutorialBrainrotIslandTeleport
		or guideType == GameConfig.GuideType.TutorialJetpackBuy
		or guideType == GameConfig.GuideType.TutorialExEquipBuy
		or guideType == GameConfig.GuideType.TutorialExEquipUse
		or guideType == GameConfig.GuideType.TutorialWalkSpeedUpgrade
end

local function ShouldSuppressOutsideRunwaySessionGuide(guideType: number): boolean
	if not IsOutsideRunwaySessionGuideType(guideType) then
		return false
	end
	return ClientGameInfo.IsInJumpRunway() or ClientGameInfo.IsInJumpRunwayEscapePhase()
end

local function RefreshGuideFrame()
	if localPlayer == nil then
		guideFrame.Visible = false
		StopGuideAni()
		return
	end
	local localInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localInfo == nil then
		guideFrame.Visible = false
		StopGuideAni()
		return
	end
	if ClientGameInfo.IsExercising() then
		guideFrame.Visible = false
		StopGuideAni()
		return
	end

	local guideType = ClientGameInfo.GetCurrentGuideType()
	if guideType == GameConfig.GuideType.None or ShouldSuppressOutsideRunwaySessionGuide(guideType) then
		guideFrame.Visible = false
		StopGuideAni()
		return
	end

	operationTypeValue.Value = guideType

	if guideType == GameConfig.GuideType.TutorialBrainrotPickup then
		guideFrame.Visible = false
		StopGuideAni()
		return
	end

	if guideType == GameConfig.GuideType.TutorialBrainrotPlace then
		guideFrame.Visible = false
		StopGuideAni()
		return
	end

	if guideType == GameConfig.GuideType.TutorialBrainrotIslandTeleport then
		guideFrame.Visible = false
		StopGuideAni()
		return
	end

	if guideType == GameConfig.GuideType.TutorialBrainrotPlaceSlot then
		local slotBtn = FindLobbyBrainrotSlotButton()
		if slotBtn == nil or not IsGuiVisibleChain(slotBtn) then
			guideFrame.Visible = false
			StopGuideAni()
			return
		end
		MountFingerCloneUnder(slotBtn)
		guideFrame.Visible = false
		return
	end

	if guideType == GameConfig.GuideType.TutorialJetpackBuy
		or guideType == GameConfig.GuideType.TutorialExEquipBuy
	then
		local guideBtn = ResolveShopTutorialGuideButton(guideType)
		if guideBtn == nil or not IsGuiVisibleChain(guideBtn) then
			guideFrame.Visible = false
			StopGuideAni()
			return
		end
		MountFingerCloneUnder(guideBtn, GetShopScrollingFrameFingerScale(guideBtn))
		guideFrame.Visible = false
		return
	end

	if guideType == GameConfig.GuideType.TutorialExEquipUse then
		local slotBtn = FindExEquipBackpackSlotButton()
		if slotBtn == nil or not IsGuiVisibleChain(slotBtn) then
			guideFrame.Visible = false
			StopGuideAni()
			return
		end
		MountFingerCloneUnder(slotBtn)
		guideFrame.Visible = false
		return
	end

	if guideType == GameConfig.GuideType.TutorialWalkSpeedUpgrade then
		local guideBtn = ResolveShopTutorialGuideButton(guideType)
		if guideBtn == nil or not IsGuiVisibleChain(guideBtn) then
			guideFrame.Visible = false
			StopGuideAni()
			return
		end
		MountFingerCloneUnder(guideBtn)
		guideFrame.Visible = false
		return
	end

	if guideType == GameConfig.GuideType.TutorialBrainrotUpgrade then
		local guideBtn = FindBrainrotUpgradeClickButton()
		if guideBtn == nil or not IsGuiVisibleChain(guideBtn) then
			guideFrame.Visible = false
			StopGuideAni()
			return
		end
		MountFingerCloneUnder(guideBtn)
		guideFrame.Visible = false
		return
	end

	guideFrame.Visible = false
	StopGuideAni()
end

guideFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if not guideFrame.Visible then
		local t = ClientGameInfo.GetCurrentGuideType()
		if t == GameConfig.GuideType.TutorialBrainrotPlaceSlot
			or t == GameConfig.GuideType.TutorialBrainrotUpgrade
			or t == GameConfig.GuideType.TutorialJetpackBuy
			or t == GameConfig.GuideType.TutorialExEquipBuy
			or t == GameConfig.GuideType.TutorialExEquipUse
			or t == GameConfig.GuideType.TutorialWalkSpeedUpgrade
		then
			return
		end
		StopGuideAni()
	end
end)

ClientMsg.ConnectLocalPlayerInfoInit(function()
	RefreshGuideFrame()
end)

ClientMsg.ConnectCurrentGuideTypeChanged(function()
	RefreshGuideFrame()
end)

local function UpdateFingerOnTrackedButton(
	resolveButton: () -> GuiButton?,
	resolveFingerBaseScale: ((GuiButton) -> number)?
)
	local btn = resolveButton()
	if btn == nil or not IsGuiVisibleChain(btn) then
		StopGuideAni()
		return
	end
	local fingerBaseScale = if resolveFingerBaseScale then resolveFingerBaseScale(btn) else 1
	if fingerClone == nil or fingerClone.Parent ~= btn then
		MountFingerCloneUnder(btn, fingerBaseScale)
	end
end

runService.RenderStepped:Connect(function()
	if localPlayer == nil then
		return
	end
	if ClientGameInfo.IsExercising() then
		StopGuideAni()
		return
	end
	local t = ClientGameInfo.GetCurrentGuideType()
	if ShouldSuppressOutsideRunwaySessionGuide(t) then
		StopGuideAni()
		return
	end
	if t == GameConfig.GuideType.TutorialBrainrotPlaceSlot then
		UpdateFingerOnTrackedButton(FindLobbyBrainrotSlotButton)
	elseif t == GameConfig.GuideType.TutorialJetpackBuy
		or t == GameConfig.GuideType.TutorialExEquipBuy
		or t == GameConfig.GuideType.TutorialWalkSpeedUpgrade
	then
		UpdateFingerOnTrackedButton(function()
			return ResolveShopTutorialGuideButton(t)
		end, GetShopScrollingFrameFingerScale)
	elseif t == GameConfig.GuideType.TutorialExEquipUse then
		UpdateFingerOnTrackedButton(FindExEquipBackpackSlotButton)
	elseif t == GameConfig.GuideType.TutorialBrainrotUpgrade then
		UpdateFingerOnTrackedButton(FindBrainrotUpgradeClickButton)
	end
end)

RefreshGuideFrame()
