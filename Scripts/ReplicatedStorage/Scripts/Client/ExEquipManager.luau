--!strict
local ExEquipManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local players: Players = game:GetService("Players")
local workspace: Workspace = game:GetService("Workspace")
local runService: RunService = game:GetService("RunService")
local tweenService: TweenService = game:GetService("TweenService")
local userInputService: UserInputService = game:GetService("UserInputService")
local localPlayer: Player? = players.LocalPlayer

if localPlayer == nil then
	return ExEquipManager
end

local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local NumberExtension = require(coreSharedScripts:FindFirstChild("NumberExtension"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local TranslationTool = require(coreScripts:WaitForChild("Client"):WaitForChild("TranslationTool"))
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local UIManager = require(clientScripts:FindFirstChild("UIManager"))
local BillboardManager = require(clientScripts:FindFirstChild("BillboardManager"))
local GameSoundManager = require(clientScripts:FindFirstChild("GameSoundManager"))

local function GetPlayerControls(): any
	local playerScripts = localPlayer:FindFirstChildOfClass("PlayerScripts")
	if playerScripts == nil then
		return nil
	end
	local playerModuleScript = playerScripts:FindFirstChild("PlayerModule") :: ModuleScript?
	if playerModuleScript == nil then
		return nil
	end
	local ok, mod = pcall(require, playerModuleScript)
	if not ok or mod == nil then
		return nil
	end
	local controls
	local okGet, res = pcall(function()
		return (mod :: any):GetControls()
	end)
	if okGet then
		controls = res
	end
	return controls
end

local uiFolder = replicatedStorage:WaitForChild("UI")
local exercisePopupGuiTemplate = uiFolder:WaitForChild("ExerciseJumpPowerPopupGui") :: BillboardGui

-- 锻炼模式常量
-- 人物躯干高度（HumanoidRootPart 到脚底的参考偏移）
local CHARACTER_TORSO_HEIGHT: number = 3
local ACTIVE_EXERCISE_EQUIP_NAME = "ActiveExerciseEquip"
local EXERCISE_OWNER_USER_ID_ATTR = "ExerciseOwnerUserId"
local EXERCISE_MODEL_WAIT_TIMEOUT: number = 5
-- 锻炼数值浮字对象池大小：允许同时显示多个浮字，超过时复用最早播放的浮字。
local EXERCISE_POPUP_POOL_SIZE: number = 5
-- 浮字完整动画时长，调大则跳出和落下更慢。
local EXERCISE_POPUP_LIFETIME: number = 1.5
-- 浮字初始高度，相对于 HumanoidRootPart。
local EXERCISE_POPUP_START_HEIGHT: number = 2.4
-- 抛物线最高点高度，调大则弹得更高。
local EXERCISE_POPUP_PARABOLA_HEIGHT: number = 1.8
-- 抛物线终点比起点低多少，调大则下落更明显。
local EXERCISE_POPUP_FALL_DISTANCE: number = 0.45
-- 抛物线水平位移的最小/最大距离，影响离开玩家身体的幅度。
local EXERCISE_POPUP_OUT_DISTANCE_MIN: number = 2
local EXERCISE_POPUP_OUT_DISTANCE_MAX: number = 3
-- 随机向上弹出的水平角度范围，360 表示可朝任意水平方向弹出。
local EXERCISE_POPUP_RANDOM_ANGLE_DEGREES: number = 360
-- 第二段淡出开始时间占比，越小越早开始变透明。
local EXERCISE_POPUP_FADE_START_RATIO: number = 0.45
-- R15 默认跑步（507767968 为 Fall，勿混用）
local EXERCISE_TREADMILL_R15_ANIMATION_ID = "rbxassetid://507767714"
local EXERCISE_TREADMILL_R6_ANIMATION_ID = "rbxassetid://180426354"
local EXERCISE_BIKE_ANIMATION_ID = "rbxassetid://78524237347942"
local EXERCISE_BIKE2_ANIMATION_ID = "rbxassetid://94029105754285"
local EXERCISE_BIKE3_ANIMATION_ID = "rbxassetid://78744145986758"
local FULL_ROTATION_RADIANS = math.pi * 2
local ClickRewardConfig = GameConfig.ExerciseClickReward

-- 锻炼模式状态
local isExercising: boolean = false
local exerciseHumanoid: Humanoid? = nil
local exerciseHrp: BasePart? = nil
local exerciseForward: Vector3 = Vector3.zero
local exerciseRunServiceConnection: RBXScriptConnection? = nil
local exerciseInputConnection: RBXScriptConnection? = nil
local exerciseJumpRequestConnection: RBXScriptConnection? = nil
local exercisePrompt: ProximityPrompt? = nil
local exerciseBikeAnimTrack: AnimationTrack? = nil
local exerciseTreadmillAnimTrack: AnimationTrack? = nil
local exercisePopupRandom = Random.new()
local exerciseEquipId: number? = nil
local exerciseClientSessionId: number = 0
local exerciseScaleBarRatio: number = 0
local exerciseScaleBarTween: Tween? = nil
local exerciseScaleBarRatioValue: NumberValue? = nil
local exerciseScaleBarRatioConnection: RBXScriptConnection? = nil
local exerciseScaleBarSequenceId: number = 0
local exerciseScaleBarTweenStartRatio: number = 0
local exerciseDisplayLv: number? = nil
local exerciseControlsDisabled: boolean = false
local clickRewardRandom = Random.new()
local clickRewardSequenceId: number = 0
local clickRewardButtonConnection: RBXScriptConnection? = nil
local clickRewardSwingTween: Tween? = nil
local clickRewardPopupMoveTween: Tween? = nil
local clickRewardPopupTextTween: Tween? = nil
local clickRewardPopupStrokeTween: Tween? = nil
local clickRewardPopupImageTween: Tween? = nil
local clickRewardPendingPopupPosition: UDim2? = nil
local clickRewardPendingMinAddExp: number = 0
local clickRewardExpectedServerAddExp: number = 0
local clickRewardButtonVisible: boolean = false

type BikeFootPedalInfo = {
	footPedal: BasePart,
	initialCFrame: CFrame,
	initialRollerLocalPosition: Vector3,
}

type BikePedalControllerInfo = {
	rollerModel: Model,
	initialRollerModelPivot: CFrame,
	roller1: BasePart,
	roller2: BasePart,
	initialRoller1CFrame: CFrame,
	initialRoller2CFrame: CFrame,
	initialRoller1LocalPosition: Vector3,
	initialRoller2LocalPosition: Vector3,
	footPedal1: BikeFootPedalInfo,
	footPedal2: BikeFootPedalInfo,
}

type ExercisePopupItem = {
	gui: BillboardGui,
	attachment: Attachment?,
	textLabel: TextLabel?,
	stroke: UIStroke?,
	isActive: boolean,
	startedAt: number,
	moveTween: Tween?,
	textTween: Tween?,
	strokeTween: Tween?,
	progressValue: NumberValue?,
	progressConnection: RBXScriptConnection?,
}

local exercisePopupPool: { ExercisePopupItem } = {}
local bikePedalControllerInfo: BikePedalControllerInfo? = nil
local exercisePopupMissingTextWarned = false
local GetExercisePopupParent: () -> PlayerGui? = function()
	return nil
end

--------------------------------------------------------------------
-- 锻炼模式逻辑
--------------------------------------------------------------------

local function GetExercisePopupText(gui: BillboardGui): TextLabel?
	local controllerFrame = gui:FindFirstChild("ControllerFrame")
	if controllerFrame == nil or not controllerFrame:IsA("Frame") then
		local popupText = gui:FindFirstChild("JumpPowerPopupText", true)
		if popupText ~= nil and popupText:IsA("TextLabel") then
			return popupText
		end
		return nil
	end
	local popupText = controllerFrame:FindFirstChild("JumpPowerPopupText", true)
	if popupText ~= nil and popupText:IsA("TextLabel") then
		return popupText
	end
	return nil
end

local function GetExerciseEquipFrame(): Frame?
	local frameRoot = UIManager.GetWindowRoot(UIManager.WindowId.ExEquipFrame)
	if frameRoot == nil or not frameRoot:IsA("Frame") then
		return nil
	end
	return frameRoot
end

local function GetExerciseScaleImage(): ImageLabel?
	local equipFrame = GetExerciseEquipFrame()
	if equipFrame == nil then
		return nil
	end

	local expImage = equipFrame:FindFirstChild("ExpImage")
	if expImage == nil or not expImage:IsA("ImageLabel") then
		return nil
	end
	local scaleBar = expImage:FindFirstChild("ScaleBar")
	if scaleBar == nil or not scaleBar:IsA("ImageLabel") then
		return nil
	end
	local scaleImage = scaleBar:FindFirstChild("Scale")
	if scaleImage == nil or not scaleImage:IsA("ImageLabel") then
		return nil
	end
	return scaleImage
end

local function ApplyExerciseScaleBarRatio(ratio: number)
	local scaleImage = GetExerciseScaleImage()
	if scaleImage == nil then
		return
	end

	local clampedRatio = math.clamp(ratio, 0, 1)
	local currentSize = scaleImage.Size
	scaleImage.Size = UDim2.new(clampedRatio, currentSize.X.Offset, currentSize.Y.Scale, currentSize.Y.Offset)
	exerciseScaleBarRatio = clampedRatio
end

local function StopExerciseScaleBarTween()
	if exerciseScaleBarTween ~= nil then
		exerciseScaleBarTween:Cancel()
		exerciseScaleBarTween = nil
	end
end

local function CleanupExerciseScaleBar()
	exerciseScaleBarSequenceId += 1
	StopExerciseScaleBarTween()
	if exerciseScaleBarRatioConnection ~= nil then
		exerciseScaleBarRatioConnection:Disconnect()
		exerciseScaleBarRatioConnection = nil
	end
	if exerciseScaleBarRatioValue ~= nil then
		exerciseScaleBarRatioValue:Destroy()
		exerciseScaleBarRatioValue = nil
	end
	exerciseDisplayLv = nil
	exerciseScaleBarRatio = 0
end

local function EnsureExerciseScaleBarRatioValue(): NumberValue
	if exerciseScaleBarRatioValue == nil then
		local ratioValue = Instance.new("NumberValue")
		ratioValue.Name = "ExerciseScaleBarRatio"
		ratioValue.Value = exerciseScaleBarRatio
		exerciseScaleBarRatioValue = ratioValue
		exerciseScaleBarRatioConnection = ratioValue:GetPropertyChangedSignal("Value"):Connect(function()
			ApplyExerciseScaleBarRatio(ratioValue.Value)
		end)
	end
	return exerciseScaleBarRatioValue
end

local function TweenExerciseScaleBarToTarget(
	ratioValue: NumberValue,
	targetRatio: number,
	duration: number,
	onComplete: (() -> ())?
)
	StopExerciseScaleBarTween()
	exerciseScaleBarTweenStartRatio = exerciseScaleBarRatio
	ratioValue.Value = exerciseScaleBarRatio
	local sequenceId = exerciseScaleBarSequenceId
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	local tween = tweenService:Create(ratioValue, tweenInfo, { Value = targetRatio })
	exerciseScaleBarTween = tween
	if onComplete ~= nil then
		tween.Completed:Connect(function(playbackState: Enum.PlaybackState)
			if playbackState ~= Enum.PlaybackState.Completed then
				return
			end
			if sequenceId ~= exerciseScaleBarSequenceId or not isExercising then
				return
			end
			onComplete()
		end)
	end
	tween:Play()
end

local function RefreshExerciseInfoLabels(jumpPowerInfo: GameConfig.JumpPowerInfo, requiredExp: number)
	local equipFrame = GetExerciseEquipFrame()
	if equipFrame == nil then
		return
	end

	local expImage = equipFrame:FindFirstChild("ExpImage")
	if expImage == nil or not expImage:IsA("ImageLabel") then
		return
	end

	local lvLabel = expImage:FindFirstChild("LvLabel") :: TextLabel?
	local expLabel = expImage:FindFirstChild("ExpLabel") :: TextLabel?
	if lvLabel ~= nil then
		TranslationTool.CustomAutoLocalizeTextLabel(
			lvLabel,
			GameTexts.LevelWithNumberCompact.source,
			GameTexts.LevelWithNumberCompact.key,
			{ tostring(jumpPowerInfo.lv) }
		)
	end
	if expLabel ~= nil then
		TranslationTool.CustomAutoLocalizeTextLabel(
			expLabel,
			GameTexts.ChestWorkbenchExpProgress.source,
			GameTexts.ChestWorkbenchExpProgress.key,
			{
				NumberExtension.FormatBigNumberAA(jumpPowerInfo.exp),
				NumberExtension.FormatBigNumberAA(requiredExp),
			}
		)
	end
end

local function GetLocalExerciseBuffInfo(): GameConfig.BuffInfo?
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil then
		return nil
	end
	return localPlayerInfo.buffInfo
end

local function GetLocalExerciseJumpPowerInterval(): number
	return GameConfig.GetExerciseJumpPowerInterval(GetLocalExerciseBuffInfo())
end

local function ApplyExerciseAnimationSpeed()
	local buffInfo = GetLocalExerciseBuffInfo()
	if exerciseTreadmillAnimTrack ~= nil then
		exerciseTreadmillAnimTrack:AdjustSpeed(GameConfig.GetExerciseTreadmillAnimationSpeed(buffInfo))
	end
	if exerciseBikeAnimTrack ~= nil then
		exerciseBikeAnimTrack:AdjustSpeed(GameConfig.GetExerciseBikeAnimationSpeed(buffInfo))
	end
end

local function RefreshExerciseScaleBarForIntervalChange()
	if not isExercising then
		return
	end

	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil then
		return
	end

	local jumpPowerInfo = localPlayerInfo.jumpPower
	local requiredExp = GameConfig.GetJumpPowerRequiredExp(jumpPowerInfo)
	local targetRatio = if requiredExp > 0 then jumpPowerInfo.exp / requiredExp else 0
	local interval = GetLocalExerciseJumpPowerInterval()
	local ratioValue = EnsureExerciseScaleBarRatioValue()
	local currentRatio = ratioValue.Value

	if math.abs(targetRatio - currentRatio) <= 1e-5 then
		StopExerciseScaleBarTween()
		ApplyExerciseScaleBarRatio(targetRatio)
		return
	end

	local startRatio = exerciseScaleBarTweenStartRatio
	local totalDelta = targetRatio - startRatio
	local remainingDuration = interval
	if math.abs(totalDelta) > 1e-5 then
		remainingDuration = interval * (targetRatio - currentRatio) / totalDelta
	end
	remainingDuration = math.max(remainingDuration, 0)

	exerciseScaleBarSequenceId += 1
	TweenExerciseScaleBarToTarget(ratioValue, targetRatio, remainingDuration, nil)
end

local function ApplyExerciseScaleBarInstant(targetRatio: number)
	exerciseScaleBarSequenceId += 1
	StopExerciseScaleBarTween()
	ApplyExerciseScaleBarRatio(targetRatio)
	if exerciseScaleBarRatioValue ~= nil then
		exerciseScaleBarRatioValue.Value = targetRatio
	end
end

local function UpdateExerciseInfoView(instantScaleBarUpdate: boolean?)
	local equipFrame = GetExerciseEquipFrame()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if equipFrame == nil or localPlayerInfo == nil then
		return
	end

	local equipData = if exerciseEquipId ~= nil then GameConfig.ExEquipDataMap[exerciseEquipId] else nil
	local speedLabel = equipFrame:FindFirstChild("ExSpeedLabel") :: TextLabel?
	if speedLabel ~= nil then
		local speedValue = if equipData ~= nil then equipData.ability else 0
		TranslationTool.CustomAutoLocalizeTextLabel(
			speedLabel,
			GameTexts.PowerBonusWithNumber.source,
			GameTexts.PowerBonusWithNumber.key,
			{ NumberExtension.FormatBigNumberAA(speedValue) }
		)
	end

	local jumpPowerInfo = localPlayerInfo.jumpPower
	local requiredExp = GameConfig.GetJumpPowerRequiredExp(jumpPowerInfo)
	local targetRatio = if requiredExp > 0 then jumpPowerInfo.exp / requiredExp else 0
	local interval = GetLocalExerciseJumpPowerInterval()

	if exerciseDisplayLv == nil then
		exerciseDisplayLv = jumpPowerInfo.lv
		RefreshExerciseInfoLabels(jumpPowerInfo, requiredExp)
		ApplyExerciseScaleBarRatio(targetRatio)
		return
	end

	if jumpPowerInfo.lv > exerciseDisplayLv then
		exerciseDisplayLv = jumpPowerInfo.lv
		RefreshExerciseInfoLabels(jumpPowerInfo, requiredExp)
		if instantScaleBarUpdate then
			ApplyExerciseScaleBarInstant(targetRatio)
			return
		end
		exerciseScaleBarSequenceId += 1
		ApplyExerciseScaleBarRatio(0)
		if targetRatio <= 1e-5 then
			StopExerciseScaleBarTween()
			return
		end
		local ratioValue = EnsureExerciseScaleBarRatioValue()
		ratioValue.Value = 0
		TweenExerciseScaleBarToTarget(ratioValue, targetRatio, interval, nil)
		return
	end

	exerciseDisplayLv = jumpPowerInfo.lv
	RefreshExerciseInfoLabels(jumpPowerInfo, requiredExp)
	if instantScaleBarUpdate then
		ApplyExerciseScaleBarInstant(targetRatio)
		return
	end
	exerciseScaleBarSequenceId += 1
	local ratioValue = EnsureExerciseScaleBarRatioValue()
	if math.abs(targetRatio - exerciseScaleBarRatio) <= 1e-5 then
		StopExerciseScaleBarTween()
		ApplyExerciseScaleBarRatio(targetRatio)
		return
	end
	TweenExerciseScaleBarToTarget(ratioValue, targetRatio, interval, nil)
end

local function StopExercisePopupTweens(item: ExercisePopupItem)
	if item.moveTween ~= nil then
		item.moveTween:Cancel()
		item.moveTween = nil
	end
	if item.textTween ~= nil then
		item.textTween:Cancel()
		item.textTween = nil
	end
	if item.strokeTween ~= nil then
		item.strokeTween:Cancel()
		item.strokeTween = nil
	end
	if item.progressConnection ~= nil then
		item.progressConnection:Disconnect()
		item.progressConnection = nil
	end
	if item.progressValue ~= nil then
		item.progressValue:Destroy()
		item.progressValue = nil
	end
end

local function ReleaseExercisePopupItem(item: ExercisePopupItem)
	StopExercisePopupTweens(item)
	BillboardManager.Untrack(item.gui)
	item.gui.Enabled = false
	item.gui.Adornee = nil
	item.gui.Parent = nil
	item.isActive = false
	item.startedAt = 0

	if item.attachment ~= nil and item.attachment.Parent ~= nil then
		item.attachment:Destroy()
	end
	item.attachment = nil
	item.textLabel = nil
	item.stroke = nil
end

local function EnsureExercisePopupPool()
	if #exercisePopupPool > 0 then
		return
	end

	for popupIndex: number = 1, EXERCISE_POPUP_POOL_SIZE do
		local gui = exercisePopupGuiTemplate:Clone()
		gui.Name = `ExerciseJumpPowerPopupGui_{popupIndex}`
		gui.Enabled = false
		gui.Adornee = nil
		gui.Parent = nil

		table.insert(exercisePopupPool, {
			gui = gui,
			attachment = nil,
			textLabel = nil,
			stroke = nil,
			isActive = false,
			startedAt = 0,
			moveTween = nil,
			textTween = nil,
			strokeTween = nil,
			progressValue = nil,
			progressConnection = nil,
		})
	end
end

local function GetExercisePopupItem(): ExercisePopupItem?
	EnsureExercisePopupPool()

	for _, item: ExercisePopupItem in exercisePopupPool do
		if not item.isActive then
			return item
		end
	end

	local oldestItem: ExercisePopupItem? = nil
	for _, item: ExercisePopupItem in exercisePopupPool do
		if oldestItem == nil or item.startedAt < oldestItem.startedAt then
			oldestItem = item
		end
	end

	if oldestItem ~= nil then
		ReleaseExercisePopupItem(oldestItem)
	end
	return oldestItem
end

local function CleanupExercisePopups()
	for _, item: ExercisePopupItem in exercisePopupPool do
		ReleaseExercisePopupItem(item)
	end
end

local function GetExercisePopupAdornee(): BasePart?
	local character: Model? = localPlayer.Character
	if character == nil then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

GetExercisePopupParent = function(): PlayerGui?
	return localPlayer:FindFirstChildOfClass("PlayerGui")
end

local function GetRandomPopupDirection(adornee: BasePart): Vector3
	local angleRange = math.rad(EXERCISE_POPUP_RANDOM_ANGLE_DEGREES)
	local angle = exercisePopupRandom:NextNumber(-angleRange / 2, angleRange / 2)
	local baseForward = if exerciseForward.Magnitude > 0 then exerciseForward.Unit else adornee.CFrame.LookVector
	local baseRight = adornee.CFrame.RightVector
	local direction = baseForward * math.cos(angle) + baseRight * math.sin(angle)
	if direction.Magnitude <= 0 then
		return baseForward
	end
	return direction.Unit
end

local function ShowExerciseJumpPowerPopup(addAmount: number)
	if not isExercising or addAmount <= 0 then
		return
	end

	local adornee = GetExercisePopupAdornee()
	if adornee == nil then
		return
	end

	local popupParent = GetExercisePopupParent()
	if popupParent == nil then
		return
	end

	local item = GetExercisePopupItem()
	if item == nil then
		return
	end

	local textLabel = GetExercisePopupText(item.gui)
	if textLabel == nil then
		if not exercisePopupMissingTextWarned then
			exercisePopupMissingTextWarned = true
			warn("[ExEquipManager] ExerciseJumpPowerPopupGui missing JumpPowerPopupText")
		end
		return
	end

	local displayText = string.format("+%s", NumberExtension.FormatBigNumberAA(addAmount))
	local popupAttachment = Instance.new("Attachment")
	popupAttachment.Name = "ExerciseJumpPowerPopupAttachment"
	popupAttachment.Position = Vector3.new(0, EXERCISE_POPUP_START_HEIGHT, 0)
	popupAttachment.Parent = adornee

	local stroke: UIStroke? = textLabel:FindFirstChild("PopupStroke") :: UIStroke?
	textLabel.Text = displayText
	textLabel.TextTransparency = 0
	if stroke ~= nil then
		stroke.Transparency = 0
	end

	item.gui.Adornee = popupAttachment
	item.gui.Enabled = true
	item.gui.Parent = popupParent
	item.attachment = popupAttachment
	item.textLabel = textLabel
	item.stroke = stroke
	item.isActive = true
	item.startedAt = os.clock()

	BillboardManager.Track(item.gui)

	local popupDirection = GetRandomPopupDirection(adornee)
	local outDistance = exercisePopupRandom:NextNumber(EXERCISE_POPUP_OUT_DISTANCE_MIN, EXERCISE_POPUP_OUT_DISTANCE_MAX)
	local startPosition = Vector3.new(0, EXERCISE_POPUP_START_HEIGHT, 0)
	local progressValue = Instance.new("NumberValue")
	progressValue.Name = "ExerciseJumpPowerPopupProgress"
	progressValue.Value = 0
	item.progressValue = progressValue
	item.progressConnection = progressValue:GetPropertyChangedSignal("Value"):Connect(function()
		local progress = math.clamp(progressValue.Value, 0, 1)
		local horizontalOffset = popupDirection * outDistance * progress
		local parabolaOffsetY = EXERCISE_POPUP_PARABOLA_HEIGHT * 4 * progress * (1 - progress)
			- EXERCISE_POPUP_FALL_DISTANCE * progress
		popupAttachment.Position = startPosition + horizontalOffset + Vector3.new(0, parabolaOffsetY, 0)
	end)

	local moveTweenInfo = TweenInfo.new(EXERCISE_POPUP_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeTweenInfo = TweenInfo.new(
		EXERCISE_POPUP_LIFETIME * (1 - EXERCISE_POPUP_FADE_START_RATIO),
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)

	local moveTween = tweenService:Create(progressValue, moveTweenInfo, { Value = 1 })
	local textTween = tweenService:Create(textLabel, fadeTweenInfo, { TextTransparency = 1 })
	item.moveTween = moveTween
	item.textTween = textTween

	if stroke ~= nil then
		item.strokeTween = tweenService:Create(stroke, fadeTweenInfo, { Transparency = 1 })
	end

	moveTween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		if playbackState == Enum.PlaybackState.Completed and item.isActive and item.attachment == popupAttachment then
			ReleaseExercisePopupItem(item)
		end
	end)

	moveTween:Play()
	task.delay(EXERCISE_POPUP_LIFETIME * EXERCISE_POPUP_FADE_START_RATIO, function()
		if item.isActive and item.attachment == popupAttachment then
			textTween:Play()
			if item.strokeTween ~= nil then
				item.strokeTween:Play()
			end
		end
	end)
end

local QueueNextExerciseClickReward: ((number) -> ())? = nil
local ShowExerciseClickRewardPopup: ((number) -> ())? = nil

local function GetExerciseClickRewardFrame(): Frame?
	local equipFrame = GetExerciseEquipFrame()
	if equipFrame == nil then
		return nil
	end

	local clickRewardFrame = equipFrame:FindFirstChild("ClickRewardFrame")
	if clickRewardFrame == nil or not clickRewardFrame:IsA("Frame") then
		return nil
	end
	return clickRewardFrame
end

local function GetExerciseClickRewardButton(): ImageButton?
	local clickRewardFrame = GetExerciseClickRewardFrame()
	if clickRewardFrame == nil then
		return nil
	end

	local imageButton = clickRewardFrame:FindFirstChild("ImageButton")
	if imageButton == nil or not imageButton:IsA("ImageButton") then
		return nil
	end
	return imageButton
end

local function GetExerciseClickRewardPopupText(): TextLabel?
	local clickRewardFrame = GetExerciseClickRewardFrame()
	if clickRewardFrame == nil then
		return nil
	end

	local popupText = clickRewardFrame:FindFirstChild("JumpPowerPopupText")
	if popupText == nil or not popupText:IsA("TextLabel") then
		return nil
	end
	return popupText
end

local function StopExerciseClickRewardSwing()
	if clickRewardSwingTween ~= nil then
		clickRewardSwingTween:Cancel()
		clickRewardSwingTween = nil
	end
end

local function StopExerciseClickRewardPopupTweens()
	if clickRewardPopupMoveTween ~= nil then
		clickRewardPopupMoveTween:Cancel()
		clickRewardPopupMoveTween = nil
	end
	if clickRewardPopupTextTween ~= nil then
		clickRewardPopupTextTween:Cancel()
		clickRewardPopupTextTween = nil
	end
	if clickRewardPopupStrokeTween ~= nil then
		clickRewardPopupStrokeTween:Cancel()
		clickRewardPopupStrokeTween = nil
	end
	if clickRewardPopupImageTween ~= nil then
		clickRewardPopupImageTween:Cancel()
		clickRewardPopupImageTween = nil
	end
end

local function HideExerciseClickRewardButton()
	StopExerciseClickRewardSwing()
	if clickRewardButtonConnection ~= nil then
		clickRewardButtonConnection:Disconnect()
		clickRewardButtonConnection = nil
	end

	local imageButton = GetExerciseClickRewardButton()
	if imageButton ~= nil then
		imageButton.Visible = false
		imageButton.Active = false
		imageButton.Rotation = 0
	end
	clickRewardButtonVisible = false
end

local function HideExerciseClickRewardPopup()
	StopExerciseClickRewardPopupTweens()

	local popupText = GetExerciseClickRewardPopupText()
	if popupText ~= nil then
		popupText.Visible = false
		popupText.TextTransparency = 0
		local stroke = popupText:FindFirstChild("PopupStroke") :: UIStroke?
		if stroke ~= nil then
			stroke.Transparency = 0
		end
		local imageLabel = popupText:FindFirstChild("ImageLabel") :: ImageLabel?
		if imageLabel ~= nil then
			imageLabel.ImageTransparency = 0
		end
	end
end

local function CleanupExerciseClickReward()
	clickRewardSequenceId += 1
	HideExerciseClickRewardButton()
	HideExerciseClickRewardPopup()
	clickRewardPendingPopupPosition = nil
	clickRewardPendingMinAddExp = 0
	clickRewardExpectedServerAddExp = 0
end

local function OnExerciseClickRewardButtonActivated()
	if not isExercising then
		return
	end

	local imageButton = GetExerciseClickRewardButton()
	if imageButton == nil or not clickRewardButtonVisible then
		return
	end

	local equipData = if exerciseEquipId ~= nil then GameConfig.ExEquipDataMap[exerciseEquipId] else nil
	if equipData == nil then
		return
	end

	GameSoundManager.PlayExClickSound()
	clickRewardPendingPopupPosition = imageButton.Position
	local rewardAddExp = equipData.ability * ClickRewardConfig.RewardMultiplier
	clickRewardPendingMinAddExp = rewardAddExp
	clickRewardExpectedServerAddExp = rewardAddExp
	local showExerciseClickRewardPopup = ShowExerciseClickRewardPopup
	if showExerciseClickRewardPopup ~= nil then
		showExerciseClickRewardPopup(rewardAddExp)
	end
	HideExerciseClickRewardButton()
	NetMsg.FireRequestExerciseClickReward()
	local queueNextExerciseClickReward = QueueNextExerciseClickReward
	if queueNextExerciseClickReward ~= nil then
		queueNextExerciseClickReward(exerciseClientSessionId)
	end
end

local function PlayExerciseClickRewardSwing(imageButton: ImageButton)
	StopExerciseClickRewardSwing()
	imageButton.Rotation = -ClickRewardConfig.SwingRotation
	local swingTweenInfo = TweenInfo.new(
		ClickRewardConfig.SwingDuration,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,
		true
	)
	local swingTween = tweenService:Create(imageButton, swingTweenInfo, { Rotation = ClickRewardConfig.SwingRotation })
	clickRewardSwingTween = swingTween
	swingTween:Play()
end

local function ShowExerciseClickRewardButton()
	local imageButton = GetExerciseClickRewardButton()
	if imageButton == nil then
		return
	end

	HideExerciseClickRewardButton()
	imageButton:SetAttribute("SkipButtonClickSound", true)
	local randomX = clickRewardRandom:NextNumber(ClickRewardConfig.EdgePaddingScale, 1 - ClickRewardConfig.EdgePaddingScale)
	local randomY = clickRewardRandom:NextNumber(ClickRewardConfig.EdgePaddingScale, 1 - ClickRewardConfig.EdgePaddingScale)
	imageButton.AnchorPoint = Vector2.new(0.5, 0.5)
	imageButton.Position = UDim2.fromScale(randomX, randomY)
	imageButton.Visible = true
	imageButton.Active = true
	clickRewardButtonVisible = true
	clickRewardButtonConnection = imageButton.Activated:Connect(OnExerciseClickRewardButtonActivated)
	PlayExerciseClickRewardSwing(imageButton)
end

ShowExerciseClickRewardPopup = function(addExp: number)
	local popupPosition = clickRewardPendingPopupPosition
	if popupPosition == nil then
		return
	end

	local popupText = GetExerciseClickRewardPopupText()
	if popupText == nil then
		return
	end

	StopExerciseClickRewardPopupTweens()
	local imageButton = GetExerciseClickRewardButton()
	local stroke = popupText:FindFirstChild("PopupStroke") :: UIStroke?
	local imageLabel = popupText:FindFirstChild("ImageLabel") :: ImageLabel?
	local targetPosition = UDim2.new(
		popupPosition.X.Scale,
		popupPosition.X.Offset,
		popupPosition.Y.Scale,
		popupPosition.Y.Offset + ClickRewardConfig.PopupFloatOffsetY
	)

	popupText.AnchorPoint = Vector2.new(0.5, 0.5)
	popupText.Position = popupPosition
	if imageButton ~= nil and popupText.ZIndex <= imageButton.ZIndex then
		popupText.ZIndex = imageButton.ZIndex + 1
	end
	popupText.Text = string.format("+%s", NumberExtension.FormatBigNumberAA(addExp))
	popupText.TextTransparency = 0
	popupText.Visible = true
	if stroke ~= nil then
		stroke.Transparency = 0
	end
	if imageLabel ~= nil then
		imageLabel.ImageTransparency = 0
	end

	local moveTweenInfo = TweenInfo.new(ClickRewardConfig.PopupLifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeTweenInfo = TweenInfo.new(
		ClickRewardConfig.PopupLifetime * (1 - ClickRewardConfig.PopupFadeStartRatio),
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	clickRewardPopupMoveTween = tweenService:Create(popupText, moveTweenInfo, { Position = targetPosition })
	clickRewardPopupTextTween = tweenService:Create(popupText, fadeTweenInfo, { TextTransparency = 1 })
	if stroke ~= nil then
		clickRewardPopupStrokeTween = tweenService:Create(stroke, fadeTweenInfo, { Transparency = 1 })
	end
	if imageLabel ~= nil then
		clickRewardPopupImageTween = tweenService:Create(imageLabel, fadeTweenInfo, { ImageTransparency = 1 })
	end

	local moveTween = clickRewardPopupMoveTween :: Tween
	moveTween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		if playbackState == Enum.PlaybackState.Completed and clickRewardPopupMoveTween == moveTween then
			HideExerciseClickRewardPopup()
		end
	end)

	moveTween:Play()
	task.delay(ClickRewardConfig.PopupLifetime * ClickRewardConfig.PopupFadeStartRatio, function()
		if clickRewardPopupMoveTween ~= moveTween then
			return
		end
		if clickRewardPopupTextTween ~= nil then
			clickRewardPopupTextTween:Play()
		end
		if clickRewardPopupStrokeTween ~= nil then
			clickRewardPopupStrokeTween:Play()
		end
		if clickRewardPopupImageTween ~= nil then
			clickRewardPopupImageTween:Play()
		end
	end)
	clickRewardPendingPopupPosition = nil
	clickRewardPendingMinAddExp = 0
end

local function TryShowExerciseClickRewardPopup(addExp: number): boolean
	if clickRewardExpectedServerAddExp > 0 and addExp >= clickRewardExpectedServerAddExp then
		clickRewardExpectedServerAddExp = 0
		return true
	end
	if clickRewardPendingPopupPosition == nil or addExp < clickRewardPendingMinAddExp then
		return false
	end
	local showExerciseClickRewardPopup = ShowExerciseClickRewardPopup
	if showExerciseClickRewardPopup ~= nil then
		showExerciseClickRewardPopup(addExp)
	end
	return true
end

QueueNextExerciseClickReward = function(clientSessionId: number)
	clickRewardSequenceId += 1
	local sequenceId = clickRewardSequenceId
	local delaySeconds = clickRewardRandom:NextNumber(ClickRewardConfig.DelayMin, ClickRewardConfig.DelayMax)
	task.delay(delaySeconds, function()
		if sequenceId ~= clickRewardSequenceId then
			return
		end
		if not isExercising or exerciseClientSessionId ~= clientSessionId then
			return
		end
		if clickRewardButtonVisible then
			return
		end
		ShowExerciseClickRewardButton()
	end)
end

local function FindDirectBasePart(parent: Instance, childName: string): BasePart?
	local child = parent:FindFirstChild(childName)
	if child ~= nil and child:IsA("BasePart") then
		return child
	end
	return nil
end

local function IsBikeExEquipType(exEquipType: number): boolean
	return exEquipType == GameConfig.ExEquipType.Bike
		or exEquipType == GameConfig.ExEquipType.Bike2
		or exEquipType == GameConfig.ExEquipType.Bike3
end

local function GetExerciseBikeAnimationId(equipData: GameConfig.ExEquipData): string
	if equipData.type == GameConfig.ExEquipType.Bike2 then
		return EXERCISE_BIKE2_ANIMATION_ID
	end
	if equipData.type == GameConfig.ExEquipType.Bike3 then
		return EXERCISE_BIKE3_ANIMATION_ID
	end
	return EXERCISE_BIKE_ANIMATION_ID
end

local function CreateBikeFootPedalInfo(initialRollerModelPivot: CFrame, footPedal: BasePart): BikeFootPedalInfo?
	local initialRollerLocalPosition = initialRollerModelPivot:PointToObjectSpace(footPedal.Position)
	local radiusMagnitude = Vector2.new(initialRollerLocalPosition.Y, initialRollerLocalPosition.Z).Magnitude
	if radiusMagnitude <= 0.001 then
		warn("[ExEquipManager] Bike pedal is too close to roller axis")
		return nil
	end

	return {
		footPedal = footPedal,
		initialCFrame = footPedal.CFrame,
		initialRollerLocalPosition = initialRollerLocalPosition,
	}
end

local function SetupBikePedalController(equipmentModel: Model): BikePedalControllerInfo?
	local rollerModel = equipmentModel:FindFirstChild("Roller")
	if rollerModel == nil or not rollerModel:IsA("Model") then
		return nil
	end

	local roller1 = FindDirectBasePart(rollerModel, "Roller1")
	local roller2 = FindDirectBasePart(rollerModel, "Roller2")
	if roller1 == nil or roller2 == nil then
		warn("[ExEquipManager] Bike missing Roller1/Roller2")
		return nil
	end

	local initialRollerModelPivot = rollerModel:GetPivot()
	local footPedal1 = FindDirectBasePart(equipmentModel, "FootPedal1") or roller1
	local footPedal2 = FindDirectBasePart(equipmentModel, "FootPedal2") or roller2
	local pedal1 = CreateBikeFootPedalInfo(initialRollerModelPivot, footPedal1)
	local pedal2 = CreateBikeFootPedalInfo(initialRollerModelPivot, footPedal2)
	if pedal1 == nil or pedal2 == nil then
		return nil
	end

	return {
		rollerModel = rollerModel,
		initialRollerModelPivot = initialRollerModelPivot,
		roller1 = roller1,
		roller2 = roller2,
		initialRoller1CFrame = roller1.CFrame,
		initialRoller2CFrame = roller2.CFrame,
		initialRoller1LocalPosition = initialRollerModelPivot:PointToObjectSpace(roller1.Position),
		initialRoller2LocalPosition = initialRollerModelPivot:PointToObjectSpace(roller2.Position),
		footPedal1 = pedal1,
		footPedal2 = pedal2,
	}
end

local function UpdateBikeRollerPartPosition(roller: BasePart, initialCFrame: CFrame, initialRollerLocalPosition: Vector3, rollerModelPivot: CFrame)
	if roller.Parent == nil then
		return
	end

	local rollerPosition = rollerModelPivot:PointToWorldSpace(initialRollerLocalPosition)
	roller.CFrame = CFrame.new(rollerPosition) * initialCFrame.Rotation
end

local function UpdateBikeFootPedalPosition(pedalInfo: BikeFootPedalInfo, rollerModelPivot: CFrame)
	if pedalInfo.footPedal.Parent == nil then
		return
	end

	local footPedalPosition = rollerModelPivot:PointToWorldSpace(pedalInfo.initialRollerLocalPosition)
	pedalInfo.footPedal.CFrame = CFrame.new(footPedalPosition) * pedalInfo.initialCFrame.Rotation
end

local function UpdateBikePedalController()
	local controllerInfo = bikePedalControllerInfo
	if controllerInfo == nil or controllerInfo.rollerModel.Parent == nil then
		return
	end

	local bikeAnimTrack = exerciseBikeAnimTrack
	if bikeAnimTrack == nil or bikeAnimTrack.Length <= 0 then
		return
	end

	local cycleRatio = (bikeAnimTrack.TimePosition % bikeAnimTrack.Length) / bikeAnimTrack.Length
	local angle = cycleRatio * FULL_ROTATION_RADIANS
	local rollerModelPivot = controllerInfo.initialRollerModelPivot * CFrame.Angles(angle, 0, 0)
	controllerInfo.rollerModel:PivotTo(rollerModelPivot)
	UpdateBikeRollerPartPosition(
		controllerInfo.roller1,
		controllerInfo.initialRoller1CFrame,
		controllerInfo.initialRoller1LocalPosition,
		rollerModelPivot
	)
	UpdateBikeRollerPartPosition(
		controllerInfo.roller2,
		controllerInfo.initialRoller2CFrame,
		controllerInfo.initialRoller2LocalPosition,
		rollerModelPivot
	)
	UpdateBikeFootPedalPosition(controllerInfo.footPedal1, rollerModelPivot)
	UpdateBikeFootPedalPosition(controllerInfo.footPedal2, rollerModelPivot)
end

local function CleanupBikePedalController()
	bikePedalControllerInfo = nil
end

local function ReleaseExerciseCharacterPhysics()
	local humanoid = exerciseHumanoid
	local hrp = exerciseHrp
	CleanupBikePedalController()

	if humanoid == nil then
		return
	end

	if exerciseBikeAnimTrack ~= nil then
		exerciseBikeAnimTrack:Stop(0)
		exerciseBikeAnimTrack:Destroy()
		exerciseBikeAnimTrack = nil
	end
	if exerciseTreadmillAnimTrack ~= nil then
		exerciseTreadmillAnimTrack:Stop(0)
		exerciseTreadmillAnimTrack:Destroy()
		exerciseTreadmillAnimTrack = nil
	end

	if hrp ~= nil then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end

	humanoid:Move(Vector3.zero, false)
	humanoid.AutoRotate = true
	humanoid.PlatformStand = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end)
end

local function StopExerciseInternal()
	exerciseClientSessionId += 1

	if exerciseRunServiceConnection ~= nil then
		exerciseRunServiceConnection:Disconnect()
		exerciseRunServiceConnection = nil
	end

	if exerciseInputConnection ~= nil then
		exerciseInputConnection:Disconnect()
		exerciseInputConnection = nil
	end
	if exerciseJumpRequestConnection ~= nil then
		exerciseJumpRequestConnection:Disconnect()
		exerciseJumpRequestConnection = nil
	end

	ReleaseExerciseCharacterPhysics()

	-- 延迟一帧恢复控制，避免 PlatformStand 解除瞬间与输入/动画冲突
	if exerciseControlsDisabled then
		task.defer(function()
			local controls = GetPlayerControls()
			if controls ~= nil then
				pcall(function()
					controls:Enable()
				end)
			end
		end)
	end
	exerciseControlsDisabled = false

	-- 恢复器材 Prompt 按钮（模型由服务端销毁，仅做兜底）
	if exercisePrompt ~= nil and exercisePrompt.Parent ~= nil then
		exercisePrompt.Enabled = true
	end
	exercisePrompt = nil

	-- 关闭锻炼 UI
	CleanupExerciseScaleBar()
	CleanupExerciseClickReward()
	UIManager.CloseWindow(UIManager.WindowId.ExEquipFrame)
	CleanupExercisePopups()

	isExercising = false
	ClientGameInfo.SetExercising(false)
	exerciseHumanoid = nil
	exerciseHrp = nil
	exerciseForward = Vector3.zero
	exerciseEquipId = nil
end

local function StopExerciseWithServerRequest()
	if isExercising then
		NetMsg.FireRequestStopExercise()
	end
	StopExerciseInternal()
end

local function GetExercisePromptFromModel(exerciseModel: Model): ProximityPrompt?
	local promptAttachment: Attachment? = exerciseModel:FindFirstChild("Attachment") :: Attachment?
	if promptAttachment == nil then
		return nil
	end
	return promptAttachment:FindFirstChild("ProximityPrompt") :: ProximityPrompt?
end

local function IsLocalActiveExerciseModel(instance: Instance): boolean
	if not instance:IsA("Model") then
		return false
	end
	if instance.Name == ACTIVE_EXERCISE_EQUIP_NAME then
		return true
	end
	return instance:GetAttribute(EXERCISE_OWNER_USER_ID_ATTR) == localPlayer.UserId
end

local function FindLocalActiveExerciseModel(): Model?
	local character = localPlayer.Character
	if character ~= nil then
		local namedModel = character:FindFirstChild(ACTIVE_EXERCISE_EQUIP_NAME)
		if namedModel ~= nil and namedModel:IsA("Model") then
			return namedModel
		end
		for _, child in character:GetChildren() do
			if IsLocalActiveExerciseModel(child) then
				return child
			end
		end
	end

	for _, child in workspace:GetChildren() do
		if IsLocalActiveExerciseModel(child) then
			return child
		end
	end
	return nil
end

local function WaitForLocalActiveExerciseModel(): Model?
	local existingModel = FindLocalActiveExerciseModel()
	if existingModel ~= nil then
		return existingModel
	end

	local foundModel: Model? = nil
	local childAddedConnections: { RBXScriptConnection } = {}
	local startTime = os.clock()

	local function OnPotentialExerciseModelAdded(child: Instance)
		if IsLocalActiveExerciseModel(child) then
			foundModel = child
		end
	end

	table.insert(childAddedConnections, workspace.ChildAdded:Connect(OnPotentialExerciseModelAdded))

	local character = localPlayer.Character
	if character ~= nil then
		table.insert(childAddedConnections, character.ChildAdded:Connect(OnPotentialExerciseModelAdded))
	end

	while foundModel == nil and os.clock() - startTime < EXERCISE_MODEL_WAIT_TIMEOUT do
		foundModel = FindLocalActiveExerciseModel()
		if foundModel ~= nil then
			break
		end
		task.wait()
	end

	for _, connection in childAddedConnections do
		connection:Disconnect()
	end
	return foundModel
end

local function GetOrCreateAnimator(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

local function GetExerciseTreadmillAnimationId(humanoid: Humanoid): string
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		return EXERCISE_TREADMILL_R6_ANIMATION_ID
	end
	return EXERCISE_TREADMILL_R15_ANIMATION_ID
end

local function GetBikeLowerTorsoOffset(character: Model, hrp: BasePart): Vector3
	local lowerTorso: BasePart? = character:FindFirstChild("LowerTorso") :: BasePart?
	if lowerTorso == nil then
		return Vector3.zero
	end

	local hrpRootAttachment: Attachment? = hrp:FindFirstChild("RootRigAttachment") :: Attachment?
	local lowerTorsoRootAttachment: Attachment? = lowerTorso:FindFirstChild("RootRigAttachment") :: Attachment?
	if hrpRootAttachment ~= nil and lowerTorsoRootAttachment ~= nil then
		return hrp.CFrame:VectorToWorldSpace(hrpRootAttachment.Position - lowerTorsoRootAttachment.Position)
	end

	return lowerTorso.Position - hrp.Position
end

local function GetExerciseStandCFrame(equipmentModel: Model, equipData: GameConfig.ExEquipData, character: Model, hrp: BasePart): CFrame
	local modelRootPart: BasePart? = equipmentModel.PrimaryPart
	local rootCf: CFrame
	if modelRootPart ~= nil then
		rootCf = modelRootPart.CFrame
	else
		rootCf = equipmentModel:GetPivot()
	end

	local forwardZ: Vector3 = -rootCf.LookVector
	local rootPos: Vector3 = rootCf.Position

	-- 获取 LowerTorso 相对于 HumanoidRootPart 的偏移量（用于将 LowerTorso 对齐到 Attachment）
	local lowerTorsoOffset: Vector3 = Vector3.zero
	local lowerTorso: BasePart? = character:FindFirstChild("LowerTorso") :: BasePart?
	if lowerTorso ~= nil and hrp ~= nil then
		lowerTorsoOffset = if IsBikeExEquipType(equipData.type) then GetBikeLowerTorsoOffset(character, hrp) else lowerTorso.Position - hrp.Position
	end

	-- 根据器材类型确定站立位置和高度
	local standPos: Vector3
	if equipData.type == GameConfig.ExEquipType.Treadmill or IsBikeExEquipType(equipData.type) then
		-- type == 1/2：模型下有 ExerciseAttachment 标记站立位置和高度
		local exerciseAttachment: Attachment? = equipmentModel:FindFirstChild("ExerciseAttachment") :: Attachment?
		if exerciseAttachment ~= nil then
			local attachPos: Vector3 = exerciseAttachment.WorldPosition
			if IsBikeExEquipType(equipData.type) then
				-- Bike 类型：将玩家的 LowerTorso 对齐到 Attachment 位置
				standPos = attachPos - lowerTorsoOffset
			else
				-- type == 1（Treadmill）：人物站立，需要躯干高度偏移
				standPos = Vector3.new(attachPos.X, attachPos.Y + CHARACTER_TORSO_HEIGHT, attachPos.Z)
			end
		else
			-- 没有 Attachment 时用 PrimaryPart 的位置作为兜底
			standPos = Vector3.new(rootPos.X, rootPos.Y + CHARACTER_TORSO_HEIGHT, rootPos.Z)
		end
	else
		-- 其他类型：用 Raycast 向下检测器材顶面确定站立高度
		local rayOrigin: Vector3 = rootPos + Vector3.new(0, 10, 0)
		local rayDirection: Vector3 = Vector3.new(0, -20, 0)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Include
		rayParams.FilterDescendantsInstances = { equipmentModel }

		local rayResult = workspace:Raycast(rayOrigin, rayDirection, rayParams)

		local modelTopY: number
		if rayResult ~= nil then
			modelTopY = rayResult.Position.Y
		else
			-- 兜底：用模型包围盒的上表面
			local cframe: CFrame, size: Vector3 = equipmentModel:GetBoundingBox()
			modelTopY = cframe.Y + size.Y / 2
		end
		standPos = Vector3.new(rootPos.X, modelTopY + CHARACTER_TORSO_HEIGHT, rootPos.Z)
	end
	return CFrame.lookAt(standPos, standPos + forwardZ)
end

--------------------------------------------------------------------
-- 锻炼模式逻辑
--------------------------------------------------------------------

local function StartExercise(equipId: number)
	if ClientGameInfo.IsInJumpRunway() then
		NetMsg.FireRequestStopExercise()
		return
	end

	-- 若本地状态未清干净，先清理再开始，避免 Heartbeat 叠加
	if isExercising or exerciseRunServiceConnection ~= nil then
		StopExerciseInternal()
	end

	local character: Model? = localPlayer.Character
	if character == nil then
		return
	end

	local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
	local hrp: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid == nil or hrp == nil then
		return
	end

	local equipData = GameConfig.ExEquipDataMap[equipId]
	if equipData == nil then
		return
	end

	local equipmentModel = WaitForLocalActiveExerciseModel()
	if equipmentModel == nil then
		warn("[ExEquipManager] Server exercise model not found")
		NetMsg.FireRequestStopExercise()
		return
	end

	isExercising = true
	ClientGameInfo.SetExercising(true)

	local standCf = GetExerciseStandCFrame(equipmentModel, equipData, character, hrp)
	local standPos: Vector3 = standCf.Position
	local forwardZ: Vector3 = standCf.LookVector

	-- 直接通过 CFrame 精确定位，避免物理碰撞导致穿模
	hrp.CFrame = standCf
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	-- 参考 RunwaySession 控制方式
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, userInputService.TouchEnabled)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)

	-- 移动端需要保留 Roblox 默认跳跃按钮，用跳跃按钮触发退出锻炼。
	exerciseControlsDisabled = false
	if not userInputService.TouchEnabled then
		local controls = GetPlayerControls()
		if controls ~= nil then
			pcall(function()
				controls:Disable()
				exerciseControlsDisabled = true
			end)
		end
	end

	-- 进入锻炼时收起所有 Tool
	humanoid:UnequipTools()
	if _G.BackpackFrameManager then
		(_G.BackpackFrameManager :: any).SetEquippedIndex(0)
	end

	-- 隐藏器材 Prompt 按钮
	exercisePrompt = GetExercisePromptFromModel(equipmentModel)
	if exercisePrompt ~= nil then
		exercisePrompt.Enabled = false
	end

	-- 记录状态
	isExercising = true
	exerciseHumanoid = humanoid
	exerciseHrp = hrp
	exerciseForward = forwardZ
	exerciseEquipId = equipId
	EnsureExercisePopupPool()
	CleanupBikePedalController()
	if IsBikeExEquipType(equipData.type) then
		bikePedalControllerInfo = SetupBikePedalController(equipmentModel)
	end

	exerciseClientSessionId += 1
	local clientSessionId = exerciseClientSessionId

	-- 打开锻炼 UI
	UIManager.OpenWindow(UIManager.WindowId.ExEquipFrame)
	CleanupExerciseClickReward()
	UpdateExerciseInfoView()
	local queueNextExerciseClickReward = QueueNextExerciseClickReward
	if queueNextExerciseClickReward ~= nil then
		queueNextExerciseClickReward(clientSessionId)
	end

	-- 站立稳定：前几帧保持 CFrame 精确定位，防止物理引擎推开人物
	local settleFrames: number = 0
	local settleThreshold: number = 5

	exerciseRunServiceConnection = runService.Heartbeat:Connect(function()
		if not isExercising or exerciseClientSessionId ~= clientSessionId or exerciseHumanoid == nil or exerciseHrp == nil then
			return
		end

		if settleFrames < settleThreshold then
			-- 稳定阶段：每帧强制拉回精确位置，等待物理碰撞体安顿
			exerciseHrp.CFrame = CFrame.lookAt(standPos, standPos + forwardZ)
			settleFrames += 1
			return
		end

		-- 稳定结束，锁定站立高度
		exerciseHrp.CFrame = CFrame.lookAt(standPos, standPos + forwardZ)

		local character = exerciseHumanoid.Parent
		if character ~= nil and character:IsA("Model") then
			for _, child in character:GetChildren() do
				if child:IsA("Tool") then
					exerciseHumanoid:UnequipTools()
					if _G.BackpackFrameManager then
						(_G.BackpackFrameManager :: any).SetEquippedIndex(0)
					end
					break
				end
			end
		end

		if equipData.type == GameConfig.ExEquipType.Treadmill then
			-- Treadmill 类型：播放固定跑步动画（保留 R6/R15 兼容）
			if exerciseTreadmillAnimTrack == nil then
				local animator = GetOrCreateAnimator(exerciseHumanoid)
				local treadmillAnim = Instance.new("Animation")
				treadmillAnim.AnimationId = GetExerciseTreadmillAnimationId(exerciseHumanoid)
				exerciseTreadmillAnimTrack = animator:LoadAnimation(treadmillAnim)
				exerciseTreadmillAnimTrack.Looped = true
				exerciseTreadmillAnimTrack:Play()
				ApplyExerciseAnimationSpeed()
			end
		elseif IsBikeExEquipType(equipData.type) then
			-- Bike 类型：播放专属骑行动画
			if exerciseBikeAnimTrack == nil then
				local animator = GetOrCreateAnimator(exerciseHumanoid)
				local bikeAnim = Instance.new("Animation")
				bikeAnim.AnimationId = GetExerciseBikeAnimationId(equipData)
				exerciseBikeAnimTrack = animator:LoadAnimation(bikeAnim)
				exerciseBikeAnimTrack.Looped = true
				exerciseBikeAnimTrack:Play()
				ApplyExerciseAnimationSpeed()
			end
			UpdateBikePedalController()
		end
	end)

	exerciseInputConnection = userInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
		if gameProcessedEvent then
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Space then
			if isExercising then
				StopExerciseWithServerRequest()
			end
		end
	end)

	exerciseJumpRequestConnection = userInputService.JumpRequest:Connect(function()
		if isExercising then
			StopExerciseWithServerRequest()
		end
	end)
end

local function StopExercise()
	if not isExercising then
		return
	end
	StopExerciseInternal()
end

--------------------------------------------------------------------
-- 初始化
--------------------------------------------------------------------

function ExEquipManager.Init()
	-- 监听库存更新
	NetMsg.ConnectNotifyPlayerExEquipInventoryUpdate(function(inventory: GameConfig.ExEquipInventory)
		ClientGameInfo.UpdateExEquipInventory(inventory)
		if isExercising then
			local currentId = tonumber(inventory.currentId)
			if exerciseEquipId ~= currentId then
				StopExerciseWithServerRequest()
			end
		end
	end)

	-- 监听锻炼模式通知
	NetMsg.ConnectNotifyExerciseStart(function(equipId: number)
		StartExercise(equipId)
	end)
	NetMsg.ConnectNotifyExerciseEnd(function()
		StopExercise()
	end)

	-- 监听 JumpPower 更新
	NetMsg.ConnectNotifyPlayerJumpPowerUpdate(function(jumpPowerInfo: GameConfig.JumpPowerInfo, addExp: number)
		local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
		local previousLv = if localPlayerInfo ~= nil then localPlayerInfo.jumpPower.lv else jumpPowerInfo.lv
		local isClickRewardUpdate = clickRewardExpectedServerAddExp > 0 and addExp >= clickRewardExpectedServerAddExp
		ClientGameInfo.UpdateJumpPower(jumpPowerInfo, addExp)
		UpdateExerciseInfoView(isClickRewardUpdate)
		if not TryShowExerciseClickRewardPopup(addExp) then
			ShowExerciseJumpPowerPopup(addExp)
		end
		if jumpPowerInfo.lv > previousLv then
			GameSoundManager.PlayUpgradeAbilitySound()
			NetMsg.FireRequestCompleteGuideStep(GameConfig.GuideStepKey.ExEquipUseFinished)
		end
	end)

	ClientMsg.ConnectCurrentGuideTypeChanged(function()
		if ClientGameInfo.IsInJumpRunway() then
			StopExerciseWithServerRequest()
		end
	end)

	ClientMsg.ConnectLocalPlayerBuffInfoUpdate(function()
		if not isExercising then
			return
		end
		ApplyExerciseAnimationSpeed()
		RefreshExerciseScaleBarForIntervalChange()
	end)

	-- 角色死亡/移除时退出锻炼模式
	localPlayer.CharacterRemoving:Connect(function()
		StopExerciseWithServerRequest()
		CleanupExercisePopups()
	end)
	localPlayer.CharacterAdded:Connect(function(_character: Model)
		-- 如果还在锻炼状态（实际不应发生），清理状态
		StopExerciseWithServerRequest()
		CleanupExercisePopups()
	end)
end

return ExEquipManager
