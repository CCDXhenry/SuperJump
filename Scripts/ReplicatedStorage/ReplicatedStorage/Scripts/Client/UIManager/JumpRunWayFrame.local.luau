--!strict
-- JumpRunWayFrame：跑道会话 HUD；RatingText 显隐复用 + 砸入缩放 + 变色淡出

local tweenService = game:GetService("TweenService")
local runService = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")
local core = replicatedStorage:WaitForChild("Core")
local coreClientScripts = core:WaitForChild("Scripts"):WaitForChild("Client")

local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local ClientMsg = require(clientScripts:WaitForChild("ClientMsg"))
local ClientGameInfo = require(clientScripts:WaitForChild("ClientGameInfo"))
local ChaserClientManager = require(clientScripts:WaitForChild("JumpRunway"):WaitForChild("ChaserClientManager"))
local TranslationTool = require(coreClientScripts:WaitForChild("TranslationTool"))
local UIAdapter = require(coreClientScripts:WaitForChild("UIAdapter"))

type RatingTextEntry = { source: string, key: string }

local RATING_ROOT_ZINDEX = 92
local TipTextPopOffset = UDim2.new(0, 0, 0, -18)
local TipTextTotalSec = 1.35

local cfg = GameConfig.JumpRunway

local thisFrame = script.Parent :: Frame
local windowId = thisFrame:GetAttribute("WindowId") :: string

thisFrame.ZIndex = RATING_ROOT_ZINDEX

local holder = thisFrame:WaitForChild("Holder") :: Frame
local ratingText = holder:WaitForChild("RatingText") :: TextLabel
ratingText.Visible = false

local fuelBg: ImageLabel? = nil
local fuelMask: Frame? = nil
local fuelMaskBaseSizeY: UDim? = nil
local distanceLabel: TextLabel? = nil
local distanceValue: TextLabel? = nil
local tipText: TextLabel? = nil
local tipTextBasePosition: UDim2? = nil
local tipTextBaseRotation: number? = nil

local presentationToken = 0
local tipPresentationToken = 0
local activeRatingText: TextLabel? = nil
local activeColorConn: RBXScriptConnection? = nil
local activeScaleTween: Tween? = nil
local activeFadeTween: Tween? = nil
local activeTipTweenList: { Tween } = {}

local redScreen: ImageLabel? = nil
local escapeHudVisibleSnapshot: { [GuiObject]: boolean } = {}
local escapeRedScreenToken = 0
local escapeRedScreenConn: RBXScriptConnection? = nil
local escapeHudModeActive = false
local escapePulsePhase = 0
local escapeSmoothedPeriod = 2
local escapeSmoothedTransMin = 0
local escapeSmoothedTransMax = 0.6
-- 周期/透明度区间平滑系数（越大跟得越紧）
local EscapeRedScreenParamSmoothSpeed = 6

local function ResolveRedScreen()
	local screen = thisFrame:FindFirstChild("RedScreen")
	if screen == nil or not screen:IsA("ImageLabel") then
		warn("[JumpRunWayFrame] RedScreen missing or not ImageLabel")
		return
	end
	redScreen = screen :: ImageLabel
	redScreen.Visible = false
	redScreen.ImageTransparency = 1
end

local function CaptureEscapeHudVisibility()
	table.clear(escapeHudVisibleSnapshot)
	for _, child in thisFrame:GetChildren() do
		if child:IsA("GuiObject") and child ~= redScreen then
			escapeHudVisibleSnapshot[child] = child.Visible
		end
	end
end

local function SetEscapeHudMode(enabled: boolean)
	if enabled then
		if escapeHudModeActive then
			return
		end
		escapeHudModeActive = true
		CaptureEscapeHudVisibility()
		for guiObject, _ in escapeHudVisibleSnapshot do
			guiObject.Visible = false
		end
		if redScreen ~= nil then
			redScreen.Visible = false
			redScreen.ImageTransparency = 1
		end
	else
		if not escapeHudModeActive then
			return
		end
		escapeHudModeActive = false
		for guiObject, wasVisible in escapeHudVisibleSnapshot do
			if guiObject.Parent ~= nil then
				guiObject.Visible = wasVisible
			end
		end
		table.clear(escapeHudVisibleSnapshot)
	end
end

local function ResolveEscapeRedScreenDistanceStuds(): number
	local distance = ChaserClientManager.GetHorizontalDistanceToLocalPlayer()
	if distance == nil or distance ~= distance then
		return cfg.ESCAPE_RED_SCREEN_FAR_DISTANCE_STUDS
	end
	return distance
end

local function ComputeEscapeRedScreenDistanceT(distanceStuds: number): number
	local nearDist = cfg.ESCAPE_RED_SCREEN_NEAR_DISTANCE_STUDS
	local farDist = cfg.ESCAPE_RED_SCREEN_FAR_DISTANCE_STUDS
	if typeof(nearDist) ~= "number" or nearDist ~= nearDist then
		nearDist = 50
	end
	if typeof(farDist) ~= "number" or farDist ~= farDist or farDist <= nearDist then
		farDist = nearDist + 1
	end
	return math.clamp((distanceStuds - nearDist) / (farDist - nearDist), 0, 1)
end

local function ResolveEscapeRedScreenNumber(value: any, fallback: number): number
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end
	return value
end

-- 近档：周期 PERIOD_NEAR，透明度在 [MIN_NEAR, MAX_NEAR] 间振荡；远档：周期 PERIOD_FAR，[MIN_FAR, MAX_FAR]
local function ComputeEscapeRedScreenTargets(distanceStuds: number): (number, number, number)
	local t = ComputeEscapeRedScreenDistanceT(distanceStuds)

	local periodNear = ResolveEscapeRedScreenNumber(cfg.ESCAPE_RED_SCREEN_PULSE_PERIOD_NEAR_SEC, 1)
	local periodFar = ResolveEscapeRedScreenNumber(cfg.ESCAPE_RED_SCREEN_PULSE_PERIOD_FAR_SEC, 2)
	if periodNear <= 0 then
		periodNear = 1
	end
	if periodFar <= 0 then
		periodFar = 2
	end
	local period = periodNear + (periodFar - periodNear) * t

	local transMinNear = ResolveEscapeRedScreenNumber(cfg.ESCAPE_RED_SCREEN_PULSE_TRANSPARENCY_MIN_NEAR, 0)
	local transMaxNear = ResolveEscapeRedScreenNumber(cfg.ESCAPE_RED_SCREEN_PULSE_TRANSPARENCY_MAX_NEAR, 0.6)
	local transMinFar = ResolveEscapeRedScreenNumber(cfg.ESCAPE_RED_SCREEN_PULSE_TRANSPARENCY_MIN_FAR, 0.6)
	local transMaxFar = ResolveEscapeRedScreenNumber(cfg.ESCAPE_RED_SCREEN_PULSE_TRANSPARENCY_MAX_FAR, 1)

	local transMin = transMinNear + (transMinFar - transMinNear) * t
	local transMax = transMaxNear + (transMaxFar - transMaxNear) * t
	if transMin > transMax then
		transMin, transMax = transMax, transMin
	end

	return period, math.clamp(transMin, 0, 1), math.clamp(transMax, 0, 1)
end

local function ResetEscapeRedScreenPulseState(distanceStuds: number)
	local period, transMin, transMax = ComputeEscapeRedScreenTargets(distanceStuds)
	escapePulsePhase = 0
	escapeSmoothedPeriod = period
	escapeSmoothedTransMin = transMin
	escapeSmoothedTransMax = transMax
end

local function UpdateEscapeRedScreenTransparency(distanceStuds: number, dt: number): number
	local targetPeriod, targetTransMin, targetTransMax = ComputeEscapeRedScreenTargets(distanceStuds)
	local smoothAlpha = 1 - math.exp(-math.max(0, dt) * EscapeRedScreenParamSmoothSpeed)
	escapeSmoothedPeriod += (targetPeriod - escapeSmoothedPeriod) * smoothAlpha
	escapeSmoothedTransMin += (targetTransMin - escapeSmoothedTransMin) * smoothAlpha
	escapeSmoothedTransMax += (targetTransMax - escapeSmoothedTransMax) * smoothAlpha

	local period = math.max(escapeSmoothedPeriod, 0.05)
	escapePulsePhase += dt * (math.pi * 2 / period)
	local wave = (math.sin(escapePulsePhase) + 1) * 0.5
	local span = escapeSmoothedTransMax - escapeSmoothedTransMin
	return math.clamp(escapeSmoothedTransMin + span * wave, 0, 1)
end

local function DisconnectEscapeRedScreen()
	escapeRedScreenToken += 1
	if escapeRedScreenConn then
		escapeRedScreenConn:Disconnect()
		escapeRedScreenConn = nil
	end
end

local function StopEscapeRedScreen()
	DisconnectEscapeRedScreen()
	if redScreen ~= nil then
		redScreen.Visible = false
		redScreen.ImageTransparency = 1
	end
	SetEscapeHudMode(false)
end

local function StartEscapeRedScreen()
	if redScreen == nil then
		return
	end
	if cfg.ESCAPE_RED_SCREEN_ENABLED ~= true then
		return
	end
	if not ClientGameInfo.IsInJumpRunwayEscapePhase() then
		return
	end
	DisconnectEscapeRedScreen()
	local myToken = escapeRedScreenToken
	local startDistance = ResolveEscapeRedScreenDistanceStuds()
	ResetEscapeRedScreenPulseState(startDistance)
	redScreen.Visible = true
	escapeRedScreenConn = runService.RenderStepped:Connect(function(dt: number)
		if myToken ~= escapeRedScreenToken then
			return
		end
		if not ClientGameInfo.IsInJumpRunwayEscapePhase() then
			StopEscapeRedScreen()
			return
		end
		local distanceStuds = ResolveEscapeRedScreenDistanceStuds()
		redScreen.ImageTransparency = UpdateEscapeRedScreenTransparency(distanceStuds, dt)
	end)
end

local function ResolveFuelSizeBar()
	local bg = thisFrame:FindFirstChild("FuelSizeBarBg")
	if bg == nil or not bg:IsA("ImageLabel") then
		warn("[JumpRunWayFrame] FuelSizeBarBg missing or not ImageLabel")
		return
	end
	fuelBg = bg :: ImageLabel

	local mask = fuelBg:FindFirstChild("MaskFrame")
	if mask == nil or not mask:IsA("Frame") then
		warn("[JumpRunWayFrame] FuelSizeBarBg.MaskFrame missing or not Frame")
		return
	end
	fuelMask = mask :: Frame
	fuelMaskBaseSizeY = fuelMask.Size.Y
end

local function ResolveDistanceValue()
	local distance = thisFrame:FindFirstChild("Distance")
	if distance == nil or not distance:IsA("TextLabel") then
		warn("[JumpRunWayFrame] Distance missing or not TextLabel")
		return
	end
	distanceLabel = distance :: TextLabel

	local value = distanceLabel:FindFirstChild("Value")
	if value == nil or not value:IsA("TextLabel") then
		warn("[JumpRunWayFrame] Distance.Value missing or not TextLabel")
		return
	end
	distanceValue = value :: TextLabel
end

local function ResolveTipText()
	local tip = thisFrame:FindFirstChild("TipText")
	if tip == nil or not tip:IsA("TextLabel") then
		warn("[JumpRunWayFrame] TipText missing or not TextLabel")
		return
	end
	tipText = tip :: TextLabel
	tipTextBasePosition = tipText.Position
	tipTextBaseRotation = tipText.Rotation
	tipText.Visible = false
end

local function ResetTipTextPresentation()
	if tipText == nil then
		return
	end
	if tipTextBasePosition ~= nil then
		tipText.Position = tipTextBasePosition
	end
	if tipTextBaseRotation ~= nil then
		tipText.Rotation = tipTextBaseRotation
	end
	tipText.TextTransparency = 1
	local stroke = tipText:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 1
	end
	local scale = tipText:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 1
	end
end

local function DisconnectColorConn()
	if activeColorConn then
		activeColorConn:Disconnect()
		activeColorConn = nil
	end
end

local function CancelRatingPresentationOnly()
	presentationToken += 1
	if activeScaleTween then
		activeScaleTween:Cancel()
		activeScaleTween = nil
	end
	if activeFadeTween then
		activeFadeTween:Cancel()
		activeFadeTween = nil
	end
	DisconnectColorConn()
end

local function CancelTipPresentationOnly()
	tipPresentationToken += 1
	for _, tween in activeTipTweenList do
		tween:Cancel()
	end
	table.clear(activeTipTweenList)
	ResetTipTextPresentation()
end

local function ApplyRatingText(label: TextLabel, entry: RatingTextEntry)
	label.AutoLocalize = false
	TranslationTool.CustomAutoLocalizeTextLabel(label, entry.source, entry.key)
end

local function ResolveImpactUIScale(label: TextLabel): UIScale?
	local onLabel = label:FindFirstChildOfClass("UIScale")
	if onLabel then
		return onLabel
	end
	local onHolder = holder:FindFirstChildOfClass("UIScale")
	if onHolder then
		return onHolder
	end
	local onRoot = thisFrame:FindFirstChildOfClass("UIScale")
	if onRoot then
		return onRoot
	end
	return nil
end

local function RefreshRunwayStats(
	distanceStuds: number,
	currentFuel: number,
	maxFuel: number,
	fuelVisible: boolean,
	distanceVisible: boolean
)
	local fuelRatio = if maxFuel > 0 then math.clamp(currentFuel / maxFuel, 0, 1) else 0
	if fuelBg ~= nil then
		fuelBg.Visible = fuelVisible and maxFuel > 0
	end
	if fuelMask ~= nil and fuelMaskBaseSizeY ~= nil then
		local currentSize = fuelMask.Size
		local baseSizeY = fuelMaskBaseSizeY :: UDim
		fuelMask.Size = UDim2.new(
			currentSize.X.Scale,
			currentSize.X.Offset,
			baseSizeY.Scale * fuelRatio,
			math.floor(baseSizeY.Offset * fuelRatio + 0.5)
		)
	end

	if distanceLabel ~= nil then
		distanceLabel.Visible = distanceVisible
	end
	if distanceValue ~= nil then
		distanceValue.Visible = distanceVisible
		if distanceVisible then
			distanceValue.Text = string.format("%dm", math.max(0, math.floor(distanceStuds + 0.5)))
		end
	end
end

local function ShowNewRecordTip()
	if tipText == nil then
		return
	end
	CancelTipPresentationOnly()
	local myToken = tipPresentationToken
	local label = tipText :: TextLabel
	local basePosition = tipTextBasePosition or label.Position
	local baseRotation = tipTextBaseRotation or label.Rotation
	label.Visible = true
	label.Position = basePosition + TipTextPopOffset
	label.Rotation = baseRotation - 7
	label.TextTransparency = 1
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 1
	end
	local scale = label:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0.55
	end

	local popInfo = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local settleInfo = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeInfo = TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local textInTween = tweenService:Create(label, popInfo, {
		Position = basePosition,
		Rotation = baseRotation,
		TextTransparency = 0,
	})
	table.insert(activeTipTweenList, textInTween)
	if scale then
		local popTween = tweenService:Create(scale, popInfo, { Scale = 1.12 })
		table.insert(activeTipTweenList, popTween)
		popTween.Completed:Once(function()
			if myToken ~= tipPresentationToken then
				return
			end
			local settleTween = tweenService:Create(scale, settleInfo, { Scale = 1 })
			table.insert(activeTipTweenList, settleTween)
			settleTween:Play()
		end)
		popTween:Play()
	end
	if stroke then
		local strokeInTween = tweenService:Create(stroke, popInfo, { Transparency = 0 })
		table.insert(activeTipTweenList, strokeInTween)
		strokeInTween:Play()
	end
	textInTween.Completed:Once(function()
		task.delay(math.max(0.05, TipTextTotalSec - 0.56), function()
			if myToken ~= tipPresentationToken then
				return
			end
			local fadeTextTween = tweenService:Create(label, fadeInfo, {
				Position = basePosition + TipTextPopOffset,
				TextTransparency = 1,
			})
			table.insert(activeTipTweenList, fadeTextTween)
			if stroke then
				local strokeFadeTween = tweenService:Create(stroke, fadeInfo, { Transparency = 1 })
				table.insert(activeTipTweenList, strokeFadeTween)
				strokeFadeTween:Play()
			end
			fadeTextTween.Completed:Once(function()
				if myToken ~= tipPresentationToken then
					return
				end
				label.Visible = false
			end)
			fadeTextTween:Play()
		end)
	end)
	textInTween:Play()
end

local function BeginPresentation(entry: RatingTextEntry)
	CancelRatingPresentationOnly()
	local myToken = presentationToken

	local totalSec = math.max(0.5, cfg.JUMP_RUNWAY_RATING_UI_TOTAL_SEC)
	local impactSec = math.clamp(cfg.JUMP_RUNWAY_RATING_IMPACT_SEC, 0.08, totalSec * 0.6)
	local fadeSec = math.clamp(cfg.JUMP_RUNWAY_RATING_FADE_SEC, 0.05, totalSec * 0.4)
	local colorCycleSec = math.max(0.05, totalSec - impactSec - fadeSec)

	local label = ratingText
	activeRatingText = label

	label.TextSize = cfg.JUMP_RUNWAY_RATING_TEXT_SIZE
	label.TextTransparency = 0
	label.Visible = true
	label.TextColor3 = Color3.new(1, 1, 1)

	local uiScale = ResolveImpactUIScale(label)
	if uiScale then
		uiScale.Scale = cfg.JUMP_RUNWAY_RATING_IMPACT_START_SCALE
	end

	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end

	TranslationTool.RemoveCustomAutoLocalizeGui(label)
	ApplyRatingText(label, entry)

	local function finishFadeAndHide()
		if myToken ~= presentationToken then
			return
		end
		local fadeInfo = TweenInfo.new(fadeSec, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local twText = tweenService:Create(label, fadeInfo, { TextTransparency = 1 })
		activeFadeTween = twText
		if stroke then
			local twStroke = tweenService:Create(stroke, fadeInfo, { Transparency = 1 })
			twStroke:Play()
		end
		twText.Completed:Once(function()
			if myToken ~= presentationToken then
				return
			end
			activeFadeTween = nil
			TranslationTool.RemoveCustomAutoLocalizeGui(label)
			if activeRatingText == label then
				activeRatingText = nil
			end
			label.Visible = false
		end)
		twText:Play()
	end

	local function startColorCycle()
		activeScaleTween = nil
		if myToken ~= presentationToken then
			return
		end
		local hueStart = os.clock()
		local conn: RBXScriptConnection? = nil
		conn = runService.RenderStepped:Connect(function()
			if myToken ~= presentationToken then
				if conn then
					conn:Disconnect()
				end
				activeColorConn = nil
				return
			end
			local elapsed = os.clock() - hueStart
			if elapsed >= colorCycleSec then
				if conn then
					conn:Disconnect()
				end
				activeColorConn = nil
				finishFadeAndHide()
				return
			end
			local h = (elapsed * cfg.JUMP_RUNWAY_RATING_HUES_PER_SEC) % 1
			label.TextColor3 = Color3.fromHSV(h, 0.93, 1)
		end)
		activeColorConn = conn
	end

	if uiScale then
		local impactInfo = TweenInfo.new(impactSec, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local twScale = tweenService:Create(uiScale, impactInfo, { Scale = 1 })
		activeScaleTween = twScale
		twScale.Completed:Once(startColorCycle)
		twScale:Play()
	else
		startColorCycle()
	end
end

local function ShowRatingTier(tier: number)
	local entry: RatingTextEntry
	if tier <= 1 then
		entry = GameTexts.JumpRunwayWindowRatingPerfect
	elseif tier == 2 then
		entry = GameTexts.JumpRunwayWindowRatingOk
	else
		entry = GameTexts.JumpRunwayWindowRatingLate
	end
	BeginPresentation(entry)
end

local function ShowMiss()
	BeginPresentation(GameTexts.JumpRunwayWindowRatingMiss)
end

local function OnCloseWindow(closeWindowId: string)
	if closeWindowId ~= windowId then
		return
	end
	StopEscapeRedScreen()
	CancelRatingPresentationOnly()
	CancelTipPresentationOnly()
	if activeRatingText then
		TranslationTool.RemoveCustomAutoLocalizeGui(activeRatingText)
		activeRatingText = nil
	end
	UIAdapter.RemoveAdaptiveFrame(thisFrame)
	thisFrame:Destroy()
end

ResolveFuelSizeBar()
ResolveDistanceValue()
ResolveTipText()
ResolveRedScreen()

ClientMsg.ConnectJumpRunWayRefreshStats(RefreshRunwayStats)
ClientMsg.ConnectJumpRunWayShowRatingTier(ShowRatingTier)
ClientMsg.ConnectJumpRunWayShowMiss(ShowMiss)
ClientMsg.ConnectJumpRunWayShowNewRecordTip(ShowNewRecordTip)
ClientMsg.ConnectJumpRunWayEnterEscapeHudMode(function()
	SetEscapeHudMode(true)
end)
ClientMsg.ConnectJumpRunWayStartEscapeRedScreen(StartEscapeRedScreen)
ClientMsg.ConnectJumpRunWayStopEscapeRedScreen(StopEscapeRedScreen)
ClientMsg.ConnectCloseWindow(OnCloseWindow)

UIAdapter.AddAdaptiveFrame(thisFrame, UIAdapter.AdaptiveType.FullScreen)
