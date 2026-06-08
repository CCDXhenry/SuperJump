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
local tweenService: TweenService = game:GetService("TweenService")

local lobbyFrame: Frame = script.Parent
local coinFrame: Frame = lobbyFrame:FindFirstChild("CoinFrame") :: Frame
local coinCountText: TextLabel = coinFrame:FindFirstChild("CoinCountText") :: TextLabel
local guideText: TextLabel = lobbyFrame:FindFirstChild("GuideText") :: TextLabel
guideText.Visible = false
local mainGuideText: LocalScript = uiManagerScript:FindFirstChild("MainGuideText") :: LocalScript
local guideTextScript: LocalScript = mainGuideText:Clone()
guideTextScript.Parent = guideText

local buffsFrame: Frame? = lobbyFrame:FindFirstChild("BuffsFrame") :: Frame?
if buffsFrame then
	local mainBuffsFrameScript: LocalScript? = uiManagerScript:FindFirstChild("MainBuffsFrame") :: LocalScript?
	if mainBuffsFrameScript then
		local buffsFrameScript: LocalScript = mainBuffsFrameScript:Clone()
		buffsFrameScript.Parent = buffsFrame
	end
end

local walkSpeedFrame: Frame = lobbyFrame:FindFirstChild("WalkSpeedFrame") :: Frame
local walkSpeedText: TextLabel = walkSpeedFrame:FindFirstChild("NumberText") :: TextLabel
local maxFuelFrame: Frame = lobbyFrame:FindFirstChild("MaxFuelFrame") :: Frame
local maxFuelText: TextLabel = maxFuelFrame:FindFirstChild("NumberText") :: TextLabel
local maxThrustFrame: Frame = lobbyFrame:FindFirstChild("MaxThrustFrame") :: Frame
local maxThrustText: TextLabel = maxThrustFrame:FindFirstChild("NumberText") :: TextLabel
local decelerationButton: ImageButton? = lobbyFrame:FindFirstChild("DecelerationButton") :: ImageButton?
if decelerationButton then
	decelerationButton.Visible = false
end
local bottomButtonsFrame = lobbyFrame:FindFirstChild("BottomButtonsFrame")
local exEquipButton: ImageButton? = lobbyFrame:FindFirstChild("ExEquipButton") :: ImageButton?
local jetpackButton: ImageButton? = lobbyFrame:FindFirstChild("JetpackButton") :: ImageButton?
local rebirthFrame: Frame? = (lobbyFrame:FindFirstChild("RebirthFrame") or (if bottomButtonsFrame then bottomButtonsFrame:FindFirstChild("RebirthFrame") else nil)) :: Frame?
local rebirthButton: GuiButton? = if rebirthFrame then (rebirthFrame:FindFirstChild("Button") :: any) else nil
local rebirthNumberText: TextLabel? = if rebirthFrame then (rebirthFrame:FindFirstChild("NumberText") :: TextLabel?) else nil
local storeBundleEntryFrame: Frame? = (lobbyFrame:FindFirstChild("StoreBundleFrame") or (if bottomButtonsFrame then bottomButtonsFrame:FindFirstChild("StoreBundleFrame") else nil)) :: Frame?
local storeBundleButton: GuiButton? = if storeBundleEntryFrame then (storeBundleEntryFrame:FindFirstChild("Button") :: any) else nil
local teleHomeButton: ImageButton? = lobbyFrame:FindFirstChild("TeleHomeButton") :: ImageButton?
local teleShopButton: ImageButton? = lobbyFrame:FindFirstChild("TeleShopButton") :: ImageButton?

local walkSpeedAddButton: GuiButton? = walkSpeedFrame:FindFirstChild("AddButton") :: any
local maxFuelAddButton: GuiButton? = maxFuelFrame:FindFirstChild("AddButton") :: any
local maxThrustAddButton: GuiButton? = maxThrustFrame:FindFirstChild("AddButton") :: any

-- JumpPowerFrame
local jumpPowerFrame: Frame? = lobbyFrame:FindFirstChild("JumpPowerFrame") :: Frame?
local jumpPowerText: TextLabel? = if jumpPowerFrame then jumpPowerFrame:FindFirstChild("NumberText") :: TextLabel? else nil
local jumpPowerAddButton: GuiButton? = if jumpPowerFrame then jumpPowerFrame:FindFirstChild("AddButton") :: any else nil
local jumpPowerFloatingText: TextLabel? = if jumpPowerFrame then jumpPowerFrame:FindFirstChild("FloatingText") :: TextLabel? else nil
--local jumpPowerFloatingTemplate: TextLabel? = if jumpPowerFrame then jumpPowerFrame:FindFirstChild("FloatingTemplate") :: TextLabel? else nil

local defaultWalkSpeedColor = walkSpeedText.TextColor3
local humSpeedConnection: RBXScriptConnection? = nil
local localPlayer = game:GetService("Players").LocalPlayer

-- RebirthFrame 红点（感叹号圆圈）
local rebirthRedPoint: GuiObject? = if rebirthFrame then (rebirthFrame:FindFirstChild("RedPoint") :: GuiObject?) else nil
if rebirthRedPoint == nil and rebirthFrame then
	rebirthRedPoint = rebirthFrame:FindFirstChild("RedPointFrame") :: GuiObject?
end
if rebirthRedPoint == nil and rebirthFrame then
	rebirthRedPoint = rebirthFrame:FindFirstChild("RedPointCircle") :: GuiObject?
end

local function IsInJumpRunwaySession(): boolean
	return ClientGameInfo.IsInJumpRunway() or ClientGameInfo.IsInJumpRunwayEscapePhase()
end

local function RefreshTeleportButtonsVisible()
	local visible = not IsInJumpRunwaySession()
	if teleHomeButton then
		teleHomeButton.Visible = visible
	end
	if teleShopButton then
		teleShopButton.Visible = visible
	end
end

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

	local currentJumpPowerLevel = localPlayerInfo.jumpPower.lv
	return currentJumpPowerLevel >= nextRebirthData.jumppowerLv
end

local function RefreshRebirthRedPointView()
	if rebirthRedPoint == nil then
		return
	end
	rebirthRedPoint.Visible = IsRebirthRedPointConditionMet()
end

local RefreshUpgradeValues: () -> ()

local function ResolveLocalBaseWalkSpeed(): number
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil then
		return 16
	end
	local isDecelerationOn = ClientGameInfo.IsEffectiveDecelerationOn()
	local walkSpeedLevel = localPlayerInfo.shopInfo.walkSpeedLevel or 1
	local targetLevel = if isDecelerationOn then 1 else walkSpeedLevel
	local walkSpeedConfig = GameConfig.Shop.WalkSpeed
	if walkSpeedConfig == nil then
		return 16
	end
	return walkSpeedConfig.abilityList[targetLevel]
		or walkSpeedConfig.abilityList[walkSpeedConfig.maxLevel]
		or walkSpeedConfig.abilityList[1]
		or 16
end

local function ApplyLocalWalkSpeedFromSettings()
	if IsInJumpRunwaySession() or ClientGameInfo.IsExercising() then
		return
	end
	local char = localPlayer.Character
	if char == nil then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum == nil then
		return
	end
	hum.WalkSpeed = ResolveLocalBaseWalkSpeed()
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

if teleHomeButton then
	teleHomeButton.Activated:Connect(function()
		if IsInJumpRunwaySession() then
			return
		end
		NetMsg.FireRequestTeleportToHome()
	end)
end

if teleShopButton then
	teleShopButton.Activated:Connect(function()
		if IsInJumpRunwaySession() then
			return
		end
		NetMsg.FireRequestTeleportToShop()
	end)
end

local function RefreshJumpPowerText(jumpPowerLevel: number)
	if jumpPowerText == nil then
		return
	end
	TranslationTool.CustomAutoLocalizeTextLabel(
		jumpPowerText,
		GameTexts.LevelWithNumberCompact.source,
		GameTexts.LevelWithNumberCompact.key,
		{ tostring(jumpPowerLevel) }
	)
end

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
function RefreshUpgradeValues()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not localPlayerInfo then
		return
	end

	-- WalkSpeed
	local walkSpeedLevel = localPlayerInfo.shopInfo.walkSpeedLevel or 1

	local isDecelerationOn = ClientGameInfo.IsEffectiveDecelerationOn()
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
	if char and not IsInJumpRunwaySession() then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			currentSpeed = hum.WalkSpeed
			if currentSpeed > baseSpeed + 0.1 then
				isBuffed = true
			end
		end
	end

	if isDecelerationOn then
		walkSpeedText.Text = NumberExtension.FormatBigNumberAA(baseSpeed)
		walkSpeedText.TextColor3 = Color3.fromRGB(255, 60, 60)
	elseif isBuffed then
		walkSpeedText.Text = NumberExtension.FormatBigNumberAA(currentSpeed)
		walkSpeedText.TextColor3 = Color3.new(0, 1, 0) -- Green
	else
		walkSpeedText.Text = NumberExtension.FormatBigNumberAA(baseSpeed)
		walkSpeedText.TextColor3 = defaultWalkSpeedColor
	end
	-- MaxFuel: 从火箭背包库存读取（跑道模式中显示实时燃料）
	local jetpackCurrentId = localPlayerInfo.jetpackInventory.currentId or "1"
	local jetpackData = GameConfig.JetpackDataMap[tonumber(jetpackCurrentId)]
	local maxFuelValue = if jetpackData then jetpackData.fuel else 0
	local isRunwayMode = UIManager.IsWindowShowing(UIManager.WindowId.JumpRunWayFrame)
		and not ClientGameInfo.IsInJumpRunwayEscapePhase()
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
	local maxThrustValue = GameConfig.GetJetpackThrustPercent(jetpackData)
	maxThrustText.Text = string.format("+%s%%", NumberExtension.FormatBigNumberAA(maxThrustValue))

	-- JumpPower
	RefreshJumpPowerText(localPlayerInfo.jumpPower.lv)
end

-- local function ShowJumpPowerFloatingText(addAmount: number)
-- 	if jumpPowerFloatingTemplate == nil or jumpPowerFrame == nil then
-- 		return
-- 	end
-- 	local displayText = string.format("+%s", NumberExtension.FormatBigNumberAA(addAmount))

-- 	local floatingText: TextLabel = jumpPowerFloatingTemplate:Clone()
-- 	floatingText.Name = "FloatingText"
-- 	floatingText.Text = displayText
-- 	floatingText.TextTransparency = 0
-- 	floatingText.Visible = true
-- 	floatingText.ZIndex = 10
-- 	floatingText.Parent = jumpPowerFrame

-- 	local uiStroke: UIStroke? = floatingText:FindFirstChildOfClass("UIStroke") :: UIStroke?
-- 	if uiStroke then
-- 		uiStroke.Transparency = 0
-- 	end

-- 	local startPos = floatingText.Position
-- 	local tweenInfo = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- 	local goal: { [string]: any } = {
-- 		Position = UDim2.new(startPos.X.Scale, startPos.X.Offset, startPos.Y.Scale, startPos.Y.Offset - 40),
-- 		TextTransparency = 1,
-- 	}
-- 	local tween = tweenService:Create(floatingText, tweenInfo, goal)
-- 	tween.Completed:Connect(function()
-- 		floatingText:Destroy()
-- 	end)
-- 	tween:Play()

-- 	if uiStroke then
-- 		local strokeTween = tweenService:Create(uiStroke, tweenInfo, { Transparency = 1 })
-- 		strokeTween:Play()
-- 	end
-- end

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
	end

	if skillType == GameConfig.SkillType.RebirthLevel then
		RefreshRebirthRedPointView()
	end
end

UIAdapter.AddAdaptiveFrame(lobbyFrame, UIAdapter.AdaptiveType.FullScreen)

RefreshView()
RefreshRebirthDisplay()
RefreshRebirthRedPointView()

ClientMsg.ConnectLocalPlayerCurrencyUpdate(OnLocalPlayerCoinCountChanged)
ClientMsg.ConnectLocalPlayerInfoInit(OnLocalPlayerInfoInit)
ClientMsg.ConnectLocalPlayerSkillLevelUpdate(OnLocalPlayerSkillLevelChanged)
ClientMsg.ConnectLocalPlayerJumpPowerUpdate(function(jumpPowerInfo: GameConfig.JumpPowerInfo, addAmount: number)
	RefreshJumpPowerText(jumpPowerInfo.lv)
	RefreshRebirthRedPointView()
	--ShowJumpPowerFloatingText(addAmount)
end)

-- 火箭背包库存更新时刷新显示
ClientMsg.ConnectLocalPlayerJetpackInventoryUpdate(function()
	RefreshUpgradeValues()
end)

ClientMsg.ConnectCurrentGuideTypeChanged(function()
	RefreshTeleportButtonsVisible()
	ApplyLocalWalkSpeedFromSettings()
	RefreshUpgradeValues()
end)
RefreshTeleportButtonsVisible()

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
