--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local runService: RunService = game:GetService("RunService")
local userInputService: UserInputService = game:GetService("UserInputService")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local TranslationTool = require(coreClientScripts:FindFirstChild("TranslationTool"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local GuideManager = require(clientScripts:FindFirstChild("GuideManager"))

local guideText: TextLabel = script.Parent

local GUIDE_TEXT_PULSE_MIN_SCALE = 0.9
local GUIDE_TEXT_PULSE_MAX_TRANSPARENCY = 0.45
local GUIDE_TEXT_PULSE_PERIOD_SEC = 0.9

local guideTextScale: UIScale = (guideText:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")) :: UIScale
if guideTextScale.Parent ~= guideText then
	guideTextScale.Parent = guideText
end

local guideTextPulseConn: RBXScriptConnection? = nil
local guideTextPulsePhase = 0
local lastAnimatedGuideTextKey = -1
local lastTeleShopGuideTextActive: boolean? = nil

local function CancelGuideTextPulse()
	if guideTextPulseConn ~= nil then
		guideTextPulseConn:Disconnect()
		guideTextPulseConn = nil
	end
	guideTextPulsePhase = 0
end

local function StopGuideTextAni()
	CancelGuideTextPulse()
	guideTextScale.Scale = 1
	guideText.TextTransparency = 0
	local uiStroke = guideText:FindFirstChildOfClass("UIStroke")
	if uiStroke then
		uiStroke.Transparency = 0
	end
	lastAnimatedGuideTextKey = -1
end

local function IsShopTutorialGuideType(guideType: number): boolean
	return guideType == GameConfig.GuideType.TutorialJetpackBuy
		or guideType == GameConfig.GuideType.TutorialExEquipBuy
		or guideType == GameConfig.GuideType.TutorialWalkSpeedUpgrade
end

local function IsShowingTeleShopGuideText(guideType: number): boolean
	return IsShopTutorialGuideType(guideType) and GuideManager.ShouldGuideTeleShopFirst(guideType)
end

local function GetGuideTextAnimationKey(guideType: number): number
	if IsShowingTeleShopGuideText(guideType) then
		return guideType * 10 + 1
	end
	return guideType * 10
end

local function UpdateGuideTextPulse(dt: number)
	guideTextPulsePhase += dt * (math.pi * 2 / GUIDE_TEXT_PULSE_PERIOD_SEC)
	local wave = (math.cos(guideTextPulsePhase) + 1) * 0.5
	local scaleSpan = 1 - GUIDE_TEXT_PULSE_MIN_SCALE
	guideTextScale.Scale = GUIDE_TEXT_PULSE_MIN_SCALE + scaleSpan * wave
	local transparency = GUIDE_TEXT_PULSE_MAX_TRANSPARENCY * (1 - wave)
	guideText.TextTransparency = transparency
	local uiStroke = guideText:FindFirstChildOfClass("UIStroke")
	if uiStroke then
		uiStroke.Transparency = transparency
	end
end

local function StartGuideTextAni()
	CancelGuideTextPulse()
	guideTextPulsePhase = 0
	UpdateGuideTextPulse(0)
	guideTextPulseConn = runService.RenderStepped:Connect(UpdateGuideTextPulse)
end

local function GetCurrentInputSuffix(): string
	local lastInputType = userInputService:GetLastInputType()
	if lastInputType.Name:match("^Gamepad") then
		return "Gamepad"
	end
	if lastInputType == Enum.UserInputType.Touch then
		return "Touch"
	end
	if lastInputType == Enum.UserInputType.MouseButton1
		or lastInputType == Enum.UserInputType.MouseButton2
		or lastInputType == Enum.UserInputType.MouseMovement
		or lastInputType == Enum.UserInputType.MouseWheel
	then
		return "Mouse"
	end
	if userInputService.TouchEnabled and not userInputService.KeyboardEnabled then
		return "Touch"
	end
	if userInputService.GamepadEnabled and not userInputService.KeyboardEnabled then
		return "Gamepad"
	end
	return "Keyboard"
end

local function GetGuideTextConfig(currentGuideType: number): { source: string, key: string }?
	if IsShowingTeleShopGuideText(currentGuideType) then
		return GameTexts.GuideTutorialTeleShop
	end
	if currentGuideType == GameConfig.GuideType.TutorialBeginLineJump then
		return GameTexts["GuideTutorialBeginLineJump" .. GetCurrentInputSuffix()] :: { source: string, key: string }?
	end
	if currentGuideType == GameConfig.GuideType.TutorialLandingJump then
		return GameTexts["GuideTutorialLandingJump" .. GetCurrentInputSuffix()] :: { source: string, key: string }?
	end
	if currentGuideType == GameConfig.GuideType.TutorialFinalDash then
		return GameTexts["GuideTutorialFinalDash" .. GetCurrentInputSuffix()] :: { source: string, key: string }?
	end
	local textKey = GameConfig.GuideTextKeyMap[currentGuideType]
	return if textKey then (GameTexts[textKey] :: { source: string, key: string }) else nil
end

local function RefreshGuideText()
	if ClientGameInfo.GetLocalPlayerInfo() == nil then
		guideText.Visible = false
		StopGuideTextAni()
		return
	end
	if ClientGameInfo.IsExercising() then
		guideText.Visible = false
		StopGuideTextAni()
		return
	end
	local currentGuideType = ClientGameInfo.GetCurrentGuideType()
	if currentGuideType == GameConfig.GuideType.None then
		guideText.Visible = false
		StopGuideTextAni()
		return
	end

	local textConfig = GetGuideTextConfig(currentGuideType)
	if textConfig == nil then
		guideText.Visible = false
		StopGuideTextAni()
		return
	end

	guideText.Visible = true
	TranslationTool.CustomAutoLocalizeTextLabel(guideText, textConfig.source, textConfig.key)
	local animationKey = GetGuideTextAnimationKey(currentGuideType)
	if lastAnimatedGuideTextKey ~= animationKey then
		StartGuideTextAni()
		lastAnimatedGuideTextKey = animationKey
	end
end

local function OnCurrentGuideTypeChanged()
	RefreshGuideText()
end

ClientMsg.ConnectLocalPlayerInfoInit(function()
	RefreshGuideText()
end)

ClientMsg.ConnectCurrentGuideTypeChanged(OnCurrentGuideTypeChanged)

userInputService.LastInputTypeChanged:Connect(function()
	RefreshGuideText()
end)

ClientMsg.ConnectLocalPlayerCurrencyUpdate(function()
	RefreshGuideText()
end)

runService.RenderStepped:Connect(function()
	local currentGuideType = ClientGameInfo.GetCurrentGuideType()
	if not IsShopTutorialGuideType(currentGuideType) then
		lastTeleShopGuideTextActive = nil
		return
	end
	local teleShopGuideTextActive = IsShowingTeleShopGuideText(currentGuideType)
	if teleShopGuideTextActive == lastTeleShopGuideTextActive then
		return
	end
	lastTeleShopGuideTextActive = teleShopGuideTextActive
	RefreshGuideText()
end)

RefreshGuideText()
