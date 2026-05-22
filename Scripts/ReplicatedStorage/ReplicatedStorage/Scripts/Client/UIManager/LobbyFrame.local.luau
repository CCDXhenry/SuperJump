--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local scriptsFolder = core:WaitForChild("Scripts")
local sharedScripts = scriptsFolder:WaitForChild("Shared")
local NumberExtension = require(sharedScripts:FindFirstChild("NumberExtension"))
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts_game = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts_game:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts_game:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local uiManagerScript = clientScripts:WaitForChild("UIManager")
local UIManager = require(uiManagerScript)
local RunwaySession = require(clientScripts:FindFirstChild("JumpRunway"):FindFirstChild("RunwaySession"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local TranslationTool = require(core:WaitForChild("Scripts"):WaitForChild("Client"):FindFirstChild("TranslationTool"))
local GameTexts = require(sharedScripts_game:FindFirstChild("GameTexts"))
local userInputService = game:GetService("UserInputService")
local tweenService: TweenService = game:GetService("TweenService")

local lobbyFrame: Frame = script.Parent
local coinFrame: Frame = lobbyFrame:FindFirstChild("CoinFrame") :: Frame
local coinCountText: TextLabel = coinFrame:FindFirstChild("CoinCountText") :: TextLabel
local guideText: TextLabel = lobbyFrame:FindFirstChild("GuideText") :: TextLabel
guideText.Visible = false
local mainGuideText: LocalScript = uiManagerScript:FindFirstChild("MainGuideText") :: LocalScript
local guideTextScript: LocalScript = mainGuideText:Clone()
guideTextScript.Parent = guideText

local walkSpeedFrame: Frame = lobbyFrame:FindFirstChild("WalkSpeedFrame") :: Frame
local walkSpeedText: TextLabel = walkSpeedFrame:FindFirstChild("NumberText") :: TextLabel
local maxFuelFrame: Frame = lobbyFrame:FindFirstChild("MaxFuelFrame") :: Frame
local maxFuelText: TextLabel = maxFuelFrame:FindFirstChild("NumberText") :: TextLabel
local maxThrustFrame: Frame = lobbyFrame:FindFirstChild("MaxThrustFrame") :: Frame
local maxThrustText: TextLabel = maxThrustFrame:FindFirstChild("NumberText") :: TextLabel
local decelerationButton: ImageButton? = lobbyFrame:FindFirstChild("DecelerationButton") :: ImageButton?
local decelerationButtonTextLabel: TextLabel? = if decelerationButton then (decelerationButton:FindFirstChild("TextLabel") :: TextLabel?) else nil
local bottomButtonsFrame = lobbyFrame:FindFirstChild("BottomButtonsFrame")
local exEquipButton: ImageButton? = lobbyFrame:FindFirstChild("ExEquipButton") :: ImageButton?
local jetpackButton: ImageButton? = lobbyFrame:FindFirstChild("JetpackButton") :: ImageButton?
local rebirthFrame: Frame? = (lobbyFrame:FindFirstChild("RebirthFrame") or (if bottomButtonsFrame then bottomButtonsFrame:FindFirstChild("RebirthFrame") else nil)) :: Frame?
local rebirthButton: GuiButton? = if rebirthFrame then (rebirthFrame:FindFirstChild("Button") :: any) else nil
local rebirthNumberText: TextLabel? = if rebirthFrame then (rebirthFrame:FindFirstChild("NumberText") :: TextLabel?) else nil
local storeBundleEntryFrame: Frame? = (lobbyFrame:FindFirstChild("StoreBundleFrame") or (if bottomButtonsFrame then bottomButtonsFrame:FindFirstChild("StoreBundleFrame") else nil)) :: Frame?
local storeBundleButton: GuiButton? = if storeBundleEntryFrame then (storeBundleEntryFrame:FindFirstChild("Button") :: any) else nil

local walkSpeedAddButton: GuiButton? = walkSpeedFrame:FindFirstChild("AddButton") :: any
local maxFuelAddButton: GuiButton? = maxFuelFrame:FindFirstChild("AddButton") :: any
local maxThrustAddButton: GuiButton? = maxThrustFrame:FindFirstChild("AddButton") :: any

-- JumpPowerFrame
local jumpPowerFrame: Frame? = lobbyFrame:FindFirstChild("JumpPowerFrame") :: Frame?
local jumpPowerText: TextLabel? = if jumpPowerFrame then jumpPowerFrame:FindFirstChild("NumberText") :: TextLabel? else nil
local jumpPowerAddButton: GuiButton? = if jumpPowerFrame then jumpPowerFrame:FindFirstChild("AddButton") :: any else nil
local jumpPowerFloatingText: TextLabel? = if jumpPowerFrame then jumpPowerFrame:FindFirstChild("FloatingText") :: TextLabel? else nil
local jumpPowerFloatingTemplate: TextLabel? = if jumpPowerFrame then jumpPowerFrame:FindFirstChild("FloatingTemplate") :: TextLabel? else nil

local defaultWalkSpeedColor = walkSpeedText.TextColor3
local humSpeedConnection: RBXScriptConnection? = nil
local DecelerationOnImage = GameConfig.DecelerationOnImage
local DecelerationOffImage = GameConfig.DecelerationOffImage
local DecelerationButtonShowSpeed = GameConfig.DecelerationButtonShowSpeed
local localPlayer = game:GetService("Players").LocalPlayer

-- RebirthFrame 红点（感叹号圆圈）
local rebirthRedPoint: GuiObject? = if rebirthFrame then (rebirthFrame:FindFirstChild("RedPoint") :: GuiObject?) else nil
if rebirthRedPoint == nil and rebirthFrame then
	rebirthRedPoint = rebirthFrame:FindFirstChild("RedPointFrame") :: GuiObject?
end
if rebirthRedPoint == nil and rebirthFrame then
	rebirthRedPoint = rebirthFrame:FindFirstChild("RedPointCircle") :: GuiObject?
end

local DEFAULT_REBIRTH_REQUIRED_LEVEL = 1

local function IsRebirthRedPointConditionMet(): boolean
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil then
		return false
	end

	local rebirthLevel = localPlayerInfo.shopInfo.rebirthLevel or 0
	local nextRebirthData = GameConfig.RebirthMap[rebirthLevel + 1]
	if not nextRebirthData then
		return false
	end

	local currentSpeedLevel = localPlayerInfo.shopInfo.walkSpeedLevel or DEFAULT_REBIRTH_REQUIRED_LEVEL
	return currentSpeedLevel >= nextRebirthData.speedLv
end

local function RefreshRebirthRedPointView()
	if rebirthRedPoint == nil then
		return
	end
	rebirthRedPoint.Visible = IsRebirthRedPointConditionMet()
end

local function GetIsDecelerationOn(): boolean
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil then
		return false
	end
	return localPlayerInfo.settingInfo.decelerationOn == true
end

local function RefreshDecelerationButtonImage()
	if decelerationButton == nil then
		return
	end
	decelerationButton.Image = if GetIsDecelerationOn() then DecelerationOnImage else DecelerationOffImage
end

local function RefreshDecelerationButtonText()
	if decelerationButtonTextLabel == nil then
		return
	end
	local textData = if GetIsDecelerationOn() then GameTexts.DecelerationOn else GameTexts.DecelerationOff
	TranslationTool.CustomAutoLocalizeTextLabel(decelerationButtonTextLabel, textData.source, textData.key)
end

local function RefreshDecelerationButtonView()
	RefreshDecelerationButtonImage()
	RefreshDecelerationButtonText()
end

local function RefreshDecelerationButtonVisible(levelSpeed: number)
	if decelerationButton == nil then
		return
	end
	decelerationButton.Visible = levelSpeed > DecelerationButtonShowSpeed
end

local function ToggleDecelerationOn()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil then
		return
	end
	local newDecelerationOn = not (localPlayerInfo.settingInfo.decelerationOn == true)
	localPlayerInfo.settingInfo.decelerationOn = newDecelerationOn
	RefreshDecelerationButtonView()
	NetMsg.FireRequestSetDecelerationOn(newDecelerationOn)
end

if walkSpeedAddButton then
	walkSpeedAddButton.Activated:Connect(function()
		UIManager.OpenWindow(UIManager.WindowId.UpgradeShop)
	end)
end

if maxFuelAddButton then
	maxFuelAddButton.Activated:Connect(function()
		UIManager.OpenWindow(UIManager.WindowId.JetpackShop)
	end)
end

if maxThrustAddButton then
	maxThrustAddButton.Activated:Connect(function()
		UIManager.OpenWindow(UIManager.WindowId.JetpackShop)
	end)
end

if jumpPowerAddButton then
	jumpPowerAddButton.Activated:Connect(function()
		UIManager.OpenWindow(UIManager.WindowId.ExEquipShop)
	end)
end

if rebirthButton then
	rebirthButton.Activated:Connect(function()
		UIManager.OpenWindow(UIManager.WindowId.Rebirth)
	end)
end

if storeBundleButton then
	storeBundleButton.Activated:Connect(function()
		UIManager.OpenWindow(UIManager.WindowId.StoreBundle)
	end)
end

if exEquipButton then
	exEquipButton.Activated:Connect(function()
		UIManager.OpenWindow(UIManager.WindowId.ExEquipShop)
	end)
end

if jetpackButton then
	jetpackButton.Activated:Connect(function()
		UIManager.OpenWindow(UIManager.WindowId.JetpackShop)
	end)
end

if decelerationButton then
	decelerationButton.Activated:Connect(function()
		ToggleDecelerationOn()
	end)
end

userInputService.InputBegan:Connect(function(inputObject: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end
	if inputObject.KeyCode ~= Enum.KeyCode.T then
		return
	end
	ToggleDecelerationOn()
end)

--刷新金币数量
local function RefreshCoinCountText()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not localPlayerInfo then
		return
	end
	local coinAmount: number = localPlayerInfo.currencies["1"] or 0
	coinCountText.Text = NumberExtension.FormatBigNumberAA(coinAmount)
end

--刷新升级数值
local function RefreshUpgradeValues()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not localPlayerInfo then
		return
	end

	-- WalkSpeed
	local walkSpeedLevel = localPlayerInfo.shopInfo.walkSpeedLevel or 1

	local isDecelerationOn = localPlayerInfo.settingInfo.decelerationOn == true
	local targetWalkSpeedLevel = if isDecelerationOn then 1 else walkSpeedLevel
	local walkSpeedConfig = GameConfig.Shop.WalkSpeed
	local levelSpeed = 16
	local baseSpeed = 16
	if walkSpeedConfig then
		levelSpeed = walkSpeedConfig.abilityList[walkSpeedLevel]
			or walkSpeedConfig.abilityList[walkSpeedConfig.maxLevel]
			or walkSpeedConfig.abilityList[1]
		baseSpeed = walkSpeedConfig.abilityList[targetWalkSpeedLevel]
			or walkSpeedConfig.abilityList[walkSpeedConfig.maxLevel]
			or walkSpeedConfig.abilityList[1]
	end

	local char = localPlayer.Character
	local currentSpeed = baseSpeed
	local isBuffed = false
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			currentSpeed = hum.WalkSpeed
			if currentSpeed > baseSpeed + 0.1 then
				isBuffed = true
			end
		end
	end

	if isBuffed then
		walkSpeedText.Text = NumberExtension.FormatBigNumberAA(currentSpeed)
		walkSpeedText.TextColor3 = Color3.new(0, 1, 0) -- Green
	else
		walkSpeedText.Text = NumberExtension.FormatBigNumberAA(baseSpeed)
		walkSpeedText.TextColor3 = defaultWalkSpeedColor
	end
	RefreshDecelerationButtonVisible(levelSpeed)

	-- MaxFuel: 从火箭背包库存读取（跑道模式中显示实时燃料）
	local jetpackCurrentId = localPlayerInfo.jetpackInventory.currentId or "1"
	local jetpackData = GameConfig.JetpackDataMap[tonumber(jetpackCurrentId)]
	local maxFuelValue = if jetpackData then jetpackData.fuel else 0
	local isRunwayMode = UIManager.IsWindowShowing(UIManager.WindowId.JumpRunWayFrame)
	if isRunwayMode then
		local currentFuel = RunwaySession.GetCurrentFuel()
		maxFuelText.Text = string.format("%.1fs/%.0fs", currentFuel, maxFuelValue)
		-- 按燃料比例设置颜色：>66% 绿, >33% 黄, <=33% 红
		local fuelRatio = if maxFuelValue > 0 then currentFuel / maxFuelValue else 0
		if fuelRatio > 0.66 then
			maxFuelText.TextColor3 = Color3.fromRGB(80, 255, 120) -- 绿色
		elseif fuelRatio > 0.33 then
			maxFuelText.TextColor3 = Color3.fromRGB(255, 220, 30) -- 黄色
		else
			maxFuelText.TextColor3 = Color3.fromRGB(255, 60, 60) -- 红色
		end
	else
		maxFuelText.Text = string.format("%.0fs/%.0fs", maxFuelValue, maxFuelValue)
		maxFuelText.TextColor3 = defaultWalkSpeedColor
	end

	-- MaxThrust: 从火箭背包库存读取
	local maxThrustValue = if jetpackData then jetpackData.thrust else 0
	maxThrustText.Text = string.format("+%s", NumberExtension.FormatBigNumberAA(maxThrustValue))

	-- JumpPower
	if jumpPowerText then
		local jumpPowerValue = localPlayerInfo.jumpPower or GameConfig.JumpPowerDefaultValue
		jumpPowerText.Text = NumberExtension.FormatBigNumberAA(jumpPowerValue)
	end
end

local function ShowJumpPowerFloatingText(addAmount: number)
	if jumpPowerFloatingTemplate == nil or jumpPowerFrame == nil then
		return
	end
	local displayText = string.format("+%s", NumberExtension.FormatBigNumberAA(addAmount))

	local floatingText: TextLabel = jumpPowerFloatingTemplate:Clone()
	floatingText.Name = "FloatingText"
	floatingText.Text = displayText
	floatingText.TextTransparency = 0
	floatingText.Visible = true
	floatingText.ZIndex = 10
	floatingText.Parent = jumpPowerFrame

	local uiStroke: UIStroke? = floatingText:FindFirstChildOfClass("UIStroke") :: UIStroke?
	if uiStroke then
		uiStroke.Transparency = 0
	end

	local startPos = floatingText.Position
	local tweenInfo = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local goal: { [string]: any } = {
		Position = UDim2.new(startPos.X.Scale, startPos.X.Offset, startPos.Y.Scale, startPos.Y.Offset - 40),
		TextTransparency = 1,
	}
	local tween = tweenService:Create(floatingText, tweenInfo, goal)
	tween.Completed:Connect(function()
		floatingText:Destroy()
	end)
	tween:Play()

	if uiStroke then
		local strokeTween = tweenService:Create(uiStroke, tweenInfo, { Transparency = 1 })
		strokeTween:Play()
	end
end

local function RefreshView()
	RefreshCoinCountText()
	RefreshUpgradeValues()
end

local function RefreshRebirthDisplay()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not localPlayerInfo or not rebirthNumberText then
		return
	end
	local rebirthLevel = localPlayerInfo.shopInfo.rebirthLevel or 0
	TranslationTool.CustomAutoLocalizeTextLabel(
		rebirthNumberText,
		GameTexts.RebirthCountBracket.source,
		GameTexts.RebirthCountBracket.key,
		{ tostring(rebirthLevel) }
	)
end

local function OnLocalPlayerCoinCountChanged()
	RefreshCoinCountText()
end

local function OnLocalPlayerInfoInit()
	RefreshView()
	RefreshRebirthDisplay()
	RefreshDecelerationButtonView()
	RefreshRebirthRedPointView()
end

local function ConnectHumanoid(char: Model)
	local hum = char:WaitForChild("Humanoid", 5) :: Humanoid
	if hum then
		if humSpeedConnection then humSpeedConnection:Disconnect() end
		humSpeedConnection = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			RefreshUpgradeValues()
		end)
		RefreshUpgradeValues()
	end
end

localPlayer.CharacterAdded:Connect(ConnectHumanoid)
if localPlayer.Character then
	task.spawn(function()
		ConnectHumanoid(localPlayer.Character)
	end)
end

local function OnLocalPlayerSkillLevelChanged(skillType: number, level: number)
	RefreshUpgradeValues()
	if skillType == GameConfig.SkillType.RebirthLevel then
		RefreshRebirthDisplay()
		RefreshDecelerationButtonView()
	end

	if skillType == GameConfig.SkillType.RebirthLevel
		or skillType == GameConfig.SkillType.WalkSpeed
	then
		RefreshRebirthRedPointView()
	end
end

UIAdapter.AddAdaptiveFrame(lobbyFrame, UIAdapter.AdaptiveType.FullScreen)

RefreshView()
RefreshRebirthDisplay()
RefreshDecelerationButtonView()
RefreshRebirthRedPointView()

ClientMsg.ConnectLocalPlayerCurrencyUpdate(OnLocalPlayerCoinCountChanged)
ClientMsg.ConnectLocalPlayerInfoInit(OnLocalPlayerInfoInit)
ClientMsg.ConnectLocalPlayerSkillLevelUpdate(OnLocalPlayerSkillLevelChanged)
ClientMsg.ConnectLocalPlayerJumpPowerUpdate(function(newValue: number, addAmount: number)
	if jumpPowerText then
		jumpPowerText.Text = NumberExtension.FormatBigNumberAA(newValue)
	end
	ShowJumpPowerFloatingText(addAmount)
end)

-- 火箭背包库存更新时刷新显示
ClientMsg.ConnectLocalPlayerJetpackInventoryUpdate(function()
	RefreshUpgradeValues()
end)

-- 跑道模式中轮询实时燃料显示
local runService: RunService = game:GetService("RunService")
local lastDisplayedFuel: number = -1
runService.Heartbeat:Connect(function()
	if UIManager.IsWindowShowing(UIManager.WindowId.JumpRunWayFrame) then
		local currentFuel = RunwaySession.GetCurrentFuel()
		if math.abs(currentFuel - lastDisplayedFuel) > 0.05 then
			lastDisplayedFuel = currentFuel
			RefreshUpgradeValues()
		end
	else
		lastDisplayedFuel = -1
	end
end)

-- 监听跑道窗口打开/关闭来启停轮询
ClientMsg.ConnectCloseWindow(function(windowId: string)
	if windowId == UIManager.WindowId.JumpRunWayFrame then
		RefreshUpgradeValues()
	end
end)
