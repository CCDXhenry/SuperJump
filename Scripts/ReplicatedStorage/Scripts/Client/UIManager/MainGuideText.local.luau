--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
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

local guideText: TextLabel = script.Parent

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
		return
	end
	if ClientGameInfo.IsExercising() then
		guideText.Visible = false
		return
	end
	local currentGuideType = ClientGameInfo.GetCurrentGuideType()
	if currentGuideType == GameConfig.GuideType.None then
		guideText.Visible = false
		return
	end

	local textConfig = GetGuideTextConfig(currentGuideType)
	if textConfig == nil then
		guideText.Visible = false
		return
	end

	guideText.Visible = true
	TranslationTool.CustomAutoLocalizeTextLabel(guideText, textConfig.source, textConfig.key)
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

RefreshGuideText()
