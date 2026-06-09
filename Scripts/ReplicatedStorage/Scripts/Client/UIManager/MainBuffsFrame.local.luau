--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local TranslationTool = require(coreClientScripts:FindFirstChild("TranslationTool"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local userInputService: UserInputService = game:GetService("UserInputService")
local tweenService: TweenService = game:GetService("TweenService")

local BuffIconTweenInfo: TweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 1)

type BuffIconFrameWrapper = {
	buffIconFrame: Frame,
	iconImage: ImageLabel,
	textLabel: TextLabel,
}

type HintFrameWrapper = {
	hintFrame: Frame,
	hintText: TextLabel,
}

local BUFF_ICON_FRAME_NAME_MAP: { [number]: string } = {
	[1] = "ExerciseEfficiencyIconFrame",
	[2] = "CoinEfficiencyIconFrame",
}

local buffsFrame: Frame = script.Parent
local buffIconsFrame: Frame = buffsFrame:FindFirstChild("BuffIconsFrame") :: Frame
local buffHintsFrame: Frame = buffsFrame:FindFirstChild("BuffHintsFrame") :: Frame
buffHintsFrame.Visible = false
local buffHints2Frame: Frame = buffHintsFrame:FindFirstChild("BuffHints2Frame") :: Frame
local buffHintFrameOrigin: Frame = buffHints2Frame:FindFirstChild("BuffHintFrame") :: Frame
buffHintFrameOrigin.Parent = nil

local buffIconFrameWrapperMap: { [number]: BuffIconFrameWrapper } = {}
local buffHintFrameWrapperMap: { [number]: HintFrameWrapper } = {}
local touchingBuffIconsFrameInputObject: InputObject?

local function localizeText(textLabel: TextLabel, textValue: string)
	TranslationTool.CustomAutoLocalizeTextLabel(textLabel, textValue, "")
end

local function GetLocalPlayerInfo(): GameConfig.ClientLocalPlayerInfo?
	return ClientGameInfo.GetLocalPlayerInfo()
end

local function IsBuffOwned(buffId: number): boolean
	local localPlayerInfo = GetLocalPlayerInfo()
	if localPlayerInfo == nil then
		return false
	end
	return localPlayerInfo.buffInfo.ownedBuffMap[tostring(buffId)] == true
end

local function PlayBuffIconFlyInAnimation(buffId: number)
	local iconFrameWrapper = buffIconFrameWrapperMap[buffId]
	if iconFrameWrapper == nil then
		return
	end
	local buffIconFrame = iconFrameWrapper.buffIconFrame
	if buffsFrame.Parent == nil or not buffsFrame.Parent:IsA("GuiObject") then
		return
	end
	local parentGui = buffsFrame.Parent :: GuiObject
	local iconImage = iconFrameWrapper.iconImage
	local textLabel = iconFrameWrapper.textLabel
	local tweenBuffIconFrame: Frame = buffIconFrame:Clone()
	tweenBuffIconFrame.Parent = parentGui
	tweenBuffIconFrame.ZIndex = buffsFrame.ZIndex + 1
	iconImage.Visible = false
	textLabel.Visible = false
	local uiScale: UIScale = Instance.new("UIScale")
	uiScale.Parent = tweenBuffIconFrame
	uiScale.Scale = 2
	local endX: number = (buffIconFrame.AbsolutePosition.X + buffIconFrame.AbsoluteSize.X * 0.5 - parentGui.AbsolutePosition.X) / parentGui.AbsoluteSize.X
	local endY: number = (buffIconFrame.AbsolutePosition.Y + buffIconFrame.AbsoluteSize.Y * 0.5 - parentGui.AbsolutePosition.Y) / parentGui.AbsoluteSize.Y
	local endPos: UDim2 = UDim2.fromScale(endX, endY)
	tweenBuffIconFrame.Position = UDim2.fromScale(0.5, 0.5)
	local tween1: Tween = tweenService:Create(tweenBuffIconFrame, BuffIconTweenInfo, { Position = endPos })
	local tween2: Tween = tweenService:Create(uiScale, BuffIconTweenInfo, { Scale = 1 })
	tween1.Completed:Connect(function()
		tweenBuffIconFrame:Destroy()
		iconImage.Visible = true
		textLabel.Visible = true
	end)
	tween1:Play()
	tween2:Play()
end

local function RefreshBuffIcons(playFlyInBuffId: number?)
	for buffId: number, iconFrameWrapper: BuffIconFrameWrapper in buffIconFrameWrapperMap do
		local hintFrameWrapper: HintFrameWrapper = buffHintFrameWrapperMap[buffId]
		local buffData = GameConfig.BuffIdMap[buffId]
		local owned = IsBuffOwned(buffId)
		if not owned or buffData == nil then
			iconFrameWrapper.buffIconFrame.Visible = false
			hintFrameWrapper.hintFrame.Parent = nil
		else
			iconFrameWrapper.buffIconFrame.Visible = true
			iconFrameWrapper.iconImage.Image = buffData.iconImageId
			iconFrameWrapper.textLabel.Text = string.format("X%d", buffData.buffValue)
			hintFrameWrapper.hintFrame.Parent = buffHints2Frame
		end
	end
	if playFlyInBuffId ~= nil and IsBuffOwned(playFlyInBuffId) then
		PlayBuffIconFlyInAnimation(playFlyInBuffId)
	end
end

local function InitBuffIconFrames()
	for buffId: number, iconFrameName: string in BUFF_ICON_FRAME_NAME_MAP do
		local buffIconFrame: Frame = buffIconsFrame:FindFirstChild(iconFrameName) :: Frame
		local iconImage: ImageLabel = buffIconFrame:FindFirstChild("IconImage") :: ImageLabel
		local textLabel: TextLabel = buffIconFrame:FindFirstChild("Text") :: TextLabel
		buffIconFrameWrapperMap[buffId] = {
			buffIconFrame = buffIconFrame,
			iconImage = iconImage,
			textLabel = textLabel,
		}
		buffIconFrame.Visible = false
	end
end

local function CreateHintFrame(): HintFrameWrapper
	local hintFrame: Frame = buffHintFrameOrigin:Clone()
	local hintText: TextLabel = hintFrame:FindFirstChild("BuffHintText") :: TextLabel
	return {
		hintFrame = hintFrame,
		hintText = hintText,
	}
end

local function InitBuffHintsFrame()
	local layoutOrder = 0
	for buffId: number, _iconFrameName: string in BUFF_ICON_FRAME_NAME_MAP do
		local buffData = GameConfig.BuffIdMap[buffId]
		if buffData == nil then
			continue
		end
		layoutOrder += 1
		local hintFrameWrapper = CreateHintFrame()
		hintFrameWrapper.hintFrame.LayoutOrder = layoutOrder
		localizeText(hintFrameWrapper.hintText, buffData.describe_t)
		buffHintFrameWrapperMap[buffId] = hintFrameWrapper
	end
end

local function OnBuffIconsFrameMouseEnter(_x: number, _y: number)
	if userInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
		buffHintsFrame.Visible = true
	end
end

local function OnBuffIconsFrameMouseLeave(_x: number, _y: number)
	if userInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
		buffHintsFrame.Visible = false
	end
end

local function OnBuffsFrameInputBegan(input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch and touchingBuffIconsFrameInputObject == nil then
		touchingBuffIconsFrameInputObject = input
		task.delay(0.5, function()
			if touchingBuffIconsFrameInputObject == input then
				buffHintsFrame.Visible = true
			end
		end)
	end
end

local function OnUserInputEnded(input: InputObject, _gameProcessedEvent: boolean)
	if input == touchingBuffIconsFrameInputObject then
		buffHintsFrame.Visible = false
		touchingBuffIconsFrameInputObject = nil
	end
end

local function OnLocalPlayerInfoInit()
	RefreshBuffIcons()
end

local function OnLocalPlayerBuffInfoUpdate(_buffInfo: GameConfig.BuffInfo, grantBuffId: number?, _shopBundleId: number?)
	RefreshBuffIcons(grantBuffId)
end

InitBuffIconFrames()
InitBuffHintsFrame()
RefreshBuffIcons()

buffIconsFrame.MouseEnter:Connect(OnBuffIconsFrameMouseEnter)
buffIconsFrame.MouseLeave:Connect(OnBuffIconsFrameMouseLeave)
buffsFrame.InputBegan:Connect(OnBuffsFrameInputBegan)
userInputService.InputEnded:Connect(OnUserInputEnded)

ClientMsg.ConnectLocalPlayerInfoInit(OnLocalPlayerInfoInit)
ClientMsg.ConnectLocalPlayerBuffInfoUpdate(OnLocalPlayerBuffInfoUpdate)
