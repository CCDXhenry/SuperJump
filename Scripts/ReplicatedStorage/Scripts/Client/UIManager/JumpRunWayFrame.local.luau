--!strict
-- JumpRunWayFrame：跑道会话 HUD；RatingText 显隐复用 + 砸入缩放 + 变色淡出

local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")
local runService = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")
local core = replicatedStorage:WaitForChild("Core")
local coreClientScripts = core:WaitForChild("Scripts"):WaitForChild("Client")
local coreSharedScripts = core:WaitForChild("Scripts"):WaitForChild("Shared")

local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local PlayerExtension = require(coreSharedScripts:WaitForChild("PlayerExtension"))
local NumberExtension = require(coreSharedScripts:WaitForChild("NumberExtension"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local ClientMsg = require(clientScripts:WaitForChild("ClientMsg"))
local ClientGameInfo = require(clientScripts:WaitForChild("ClientGameInfo"))
local ChaserClientManager = require(clientScripts:WaitForChild("JumpRunway"):WaitForChild("ChaserClientManager"))
local TranslationTool = require(coreClientScripts:WaitForChild("TranslationTool"))
local UIAdapter = require(coreClientScripts:WaitForChild("UIAdapter"))

type RatingTextEntry = { source: string, key: string }
type TakeoffRatingBarPayload = {
	visible: boolean,
	progressRatio: number,
	leftOkEndRatio: number,
	perfectSplitRatio: number,
	perfectEndRatio: number,
	rightOkEndRatio: number,
}

local RATING_ROOT_ZINDEX = 92
local TipTextPopOffset = UDim2.new(0, 0, 0, -18)
local TipTextTotalSec = 1.35
local TakeoffRatingBarLeftOkColor = Color3.fromRGB(70, 220, 95)
local TakeoffRatingBarPerfectColor = Color3.fromRGB(255, 204, 45)
local TakeoffRatingBarRightOkColor = Color3.fromRGB(70, 220, 95)
local TakeoffRatingBarLateColor = Color3.fromRGB(255, 82, 82)

local cfg = GameConfig.JumpRunway

local localPlayer = players.LocalPlayer

local TICK_INTERVAL_M = 100
local VISIBLE_TICK_COUNT = 4
local TICK_POOL_COUNT = VISIBLE_TICK_COUNT + 1
local WINDOW_SPAN_M = TICK_INTERVAL_M * VISIBLE_TICK_COUNT
local SCROLL_AT_RATIO = 0.75
local MIN_TICK_CANVAS_SCALE_X = 2

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
local speedLabel: TextLabel? = nil
local speedValue: TextLabel? = nil
local tipText: TextLabel? = nil
local tipTextBasePosition: UDim2? = nil
local tipTextBaseRotation: number? = nil
local latestDistanceStuds = 0
local latestDistanceHudVisible = false
local latestDistanceCanShow = false
local tipDistanceHoldActive = false

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

local movementBarBg: ImageLabel? = nil
local myselfImage: ImageLabel? = nil
local playerImage: ImageLabel? = nil
local ticksScroll: ScrollingFrame? = nil
local tickLabels: { TextLabel } = {}
local tickLabelPosY: UDim = UDim.new(0.5, 0)
local tickLabelBaseSize: UDim2 = UDim2.fromScale(0.12, 0.4)
local myselfImageBaseY: UDim? = nil
local windowStartM = 0
local movementBarInitialized = false
local movementBarLastDistance = 0
local takeoffRatingBarBg: Frame? = nil
local takeoffRatingRegionsFrame: Frame? = nil
local takeoffLeftOkFrame: Frame? = nil
local takeoffPerfectFrame: Frame? = nil
local takeoffRightOkFrame: Frame? = nil
local takeoffLateFrame: Frame? = nil
local takeoffPerfectSplitFrame: Frame? = nil
local takeoffMarkerFrame: Frame? = nil

local function IsEscapeHudExemptGui(gui: GuiObject): boolean
	if redScreen ~= nil and gui == redScreen then
		return true
	end
	if movementBarBg ~= nil and gui == movementBarBg then
		return true
	end
	return false
end

local function LocalizeDistanceMeters(label: TextLabel, meters: number)
	local metersWhole = math.max(0, math.floor(meters + 0.5))
	TranslationTool.CustomAutoLocalizeTextLabel(
		label,
		GameTexts.JumpRunwayDistanceMeters.source,
		GameTexts.JumpRunwayDistanceMeters.key,
		{ tostring(metersWhole) }
	)
end

local function GetTickSpacingPx(): number
	if ticksScroll == nil then
		return 1
	end
	local w = ticksScroll.AbsoluteSize.X
	if w < 4 then
		return 1
	end
	return w / VISIBLE_TICK_COUNT
end

local function MetersToCanvasPx(meters: number, spacing: number): number
	return (meters / TICK_INTERVAL_M) * spacing
end

local function ResolveUDimScale(value: UDim, absoluteSize: number, fallbackScale: number): number
	if absoluteSize <= 0 then
		if value.Scale ~= 0 then
			return value.Scale
		end
		return fallbackScale
	end
	return value.Scale + value.Offset / absoluteSize
end

local function ResolveTickLabelSizeScale(canvasScaleX: number): UDim2
	if ticksScroll == nil then
		return tickLabelBaseSize
	end
	local scrollSize = ticksScroll.AbsoluteSize
	return UDim2.fromScale(
		ResolveUDimScale(tickLabelBaseSize.X, scrollSize.X, 0.12) / math.max(canvasScaleX, 0.001),
		ResolveUDimScale(tickLabelBaseSize.Y, scrollSize.Y, 0.4)
	)
end

-- 刻度在画布上的绝对坐标；滚动使「当前距离」对齐玩家锚点
local function ComputeMovementBarScroll(distanceStuds: number): (number, number)
	local spacing = GetTickSpacingPx()
	local viewportW = if ticksScroll then ticksScroll.AbsoluteSize.X else 0
	local pinPx = SCROLL_AT_RATIO * viewportW
	local pinDistanceM = WINDOW_SPAN_M * SCROLL_AT_RATIO
	local distancePx = MetersToCanvasPx(distanceStuds, spacing)

	if distanceStuds < pinDistanceM then
		return 0, math.clamp((distanceStuds / pinDistanceM) * SCROLL_AT_RATIO, 0, SCROLL_AT_RATIO)
	end
	return distancePx - pinPx, SCROLL_AT_RATIO
end

local function ApplyMyselfMarkerScale(markerScaleX: number)
	if myselfImage == nil then
		return
	end
	local yScale = if myselfImageBaseY then myselfImageBaseY.Scale else 0.5
	local yOffset = if myselfImageBaseY then myselfImageBaseY.Offset else 0
	myselfImage.Position = UDim2.new(math.clamp(markerScaleX, 0, 1), 0, yScale, yOffset)
end

local function UpdateTickRuler(distanceStuds: number, canvasX: number)
	if ticksScroll == nil then
		return
	end
	local spacing = GetTickSpacingPx()
	local leftEdgeM = math.max(0, (canvasX / spacing) * TICK_INTERVAL_M)
	local firstTickM = math.floor(leftEdgeM / TICK_INTERVAL_M) * TICK_INTERVAL_M
	windowStartM = firstTickM
	local canvasScaleX = math.max(
		(distanceStuds + WINDOW_SPAN_M + TICK_INTERVAL_M * 2) / WINDOW_SPAN_M,
		MIN_TICK_CANVAS_SCALE_X
	)
	local canvasSpanM = WINDOW_SPAN_M * canvasScaleX
	local tickSize = ResolveTickLabelSizeScale(canvasScaleX)
	local tickPosYScale = ResolveUDimScale(tickLabelPosY, ticksScroll.AbsoluteSize.Y, 0.5)

	for i, label in tickLabels do
		local meters = windowStartM + (i - 1) * TICK_INTERVAL_M
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(meters / canvasSpanM, tickPosYScale)
		label.Size = tickSize
		if meters <= 0 then
			label.Text = ""
		else
			LocalizeDistanceMeters(label, meters)
		end
		label.Visible = true
	end

	ticksScroll.CanvasSize = UDim2.fromScale(canvasScaleX, 1)
end

local function ApplyMovementBarFromDistance(distanceStuds: number)
	if ticksScroll == nil then
		return
	end
	local canvasX, markerScaleX = ComputeMovementBarScroll(distanceStuds)
	ticksScroll.CanvasPosition = Vector2.new(math.max(0, canvasX), 0)
	UpdateTickRuler(distanceStuds, math.max(0, canvasX))
	ApplyMyselfMarkerScale(markerScaleX)
end

local function ResetMovementBarState(distanceStuds: number)
	windowStartM = 0
	if ticksScroll then
		ticksScroll.CanvasPosition = Vector2.zero
	end
	ApplyMovementBarFromDistance(distanceStuds)
end

local function OnMovementBarHidden()
	movementBarInitialized = false
end

local function UpdateMovementBar(distanceStuds: number)
	if movementBarBg == nil or myselfImage == nil or ticksScroll == nil then
		return
	end
	movementBarLastDistance = distanceStuds
	if not movementBarInitialized then
		movementBarInitialized = true
		ResetMovementBarState(distanceStuds)
		return
	end
	ApplyMovementBarFromDistance(distanceStuds)
end

local function BuildTickLabelPool(template: TextLabel)
	table.clear(tickLabels)
	for i = 1, TICK_POOL_COUNT do
		local label = template:Clone()
		label.Name = "TickLabel" .. tostring(i)
		label.Visible = true
		label.Parent = ticksScroll
		tickLabels[i] = label
	end
	template.Visible = false
end

local function ConfigureDistanceTicksScroll(scroll: ScrollingFrame, bar: ImageLabel)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 0
	scroll.ScrollingEnabled = false
	scroll.ClipsDescendants = true
	scroll.AnchorPoint = Vector2.new(0, 0)
	scroll.Position = UDim2.fromScale(0, 0)
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.ZIndex = bar.ZIndex + 1
end

local function EnsureDistanceTicksScroll(bar: ImageLabel, template: TextLabel): ScrollingFrame
	local existing = bar:FindFirstChild("DistanceTicksScroll")
	if existing and existing:IsA("ScrollingFrame") then
		ConfigureDistanceTicksScroll(existing, bar)
		if template.Parent ~= existing then
			template.Parent = existing
		end
		return existing
	end
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "DistanceTicksScroll"
	scroll.Parent = bar
	ConfigureDistanceTicksScroll(scroll, bar)
	template.Parent = scroll
	return scroll
end

local function ResolveMovementBar()
	local bar = thisFrame:FindFirstChild("MovementBarBg")
	if bar == nil or not bar:IsA("ImageLabel") then
		warn("[JumpRunWayFrame] MovementBarBg missing or not ImageLabel")
		return
	end
	movementBarBg = bar
	movementBarBg.Visible = false

	local marker = movementBarBg:FindFirstChild("MyselfImage")
	if marker == nil or not marker:IsA("ImageLabel") then
		warn("[JumpRunWayFrame] MovementBarBg.MyselfImage missing or not ImageLabel")
		return
	end
	myselfImage = marker
	if myselfImage.Parent ~= movementBarBg then
		myselfImage.Parent = movementBarBg
	end
	myselfImage.AnchorPoint = Vector2.new(0.5, 0.5)
	myselfImageBaseY = myselfImage.Position.Y
	myselfImage.ZIndex = movementBarBg.ZIndex + 10

	local portrait = myselfImage:FindFirstChild("PlayerImage")
	if portrait == nil or not portrait:IsA("ImageLabel") then
		warn("[JumpRunWayFrame] MovementBarBg.MyselfImage.PlayerImage missing or not ImageLabel")
		return
	end
	playerImage = portrait
	local headUrl = PlayerExtension.GetPlayerHeadImage(localPlayer.UserId, Enum.ThumbnailSize.Size100x100)
	if headUrl ~= "" then
		playerImage.Image = headUrl
	end

	local template = movementBarBg:FindFirstChild("TickLabelTemplate")
	if template == nil or not template:IsA("TextLabel") then
		local legacy = movementBarBg:FindFirstChild("TextLabel")
		if legacy and legacy:IsA("TextLabel") then
			legacy.Name = "TickLabelTemplate"
			template = legacy
		end
	end
	if template == nil or not template:IsA("TextLabel") then
		warn("[JumpRunWayFrame] MovementBarBg.TickLabelTemplate missing or not TextLabel")
		return
	end
	tickLabelPosY = template.Position.Y
	tickLabelBaseSize = template.Size

	ticksScroll = EnsureDistanceTicksScroll(movementBarBg, template)
	BuildTickLabelPool(template)
	task.defer(function()
		if ticksScroll ~= nil and movementBarLastDistance > 0 then
			ApplyMovementBarFromDistance(movementBarLastDistance)
		elseif ticksScroll ~= nil then
			ApplyMovementBarFromDistance(0)
		end
	end)
end

local function ConfigureTakeoffSegment(frame: Frame, color: Color3, zIndex: number)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
end

local function EnsureTakeoffSegment(parent: Frame, name: string, color: Color3, zIndex: number): Frame
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Frame") then
		ConfigureTakeoffSegment(existing, color, zIndex)
		return existing
	end
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Parent = parent
	ConfigureTakeoffSegment(frame, color, zIndex)
	return frame
end

local function EnsureTakeoffRatingBarCorner(parent: GuiObject, radius: UDim)
	local corner = parent:FindFirstChildOfClass("UICorner") :: UICorner?
	if corner == nil then
		corner = Instance.new("UICorner")
		corner.Parent = parent
	end
	corner.CornerRadius = radius
end

local function EnsureTakeoffRatingBarStroke(parent: GuiObject)
	local stroke = parent:FindFirstChildOfClass("UIStroke") :: UIStroke?
	if stroke == nil then
		stroke = Instance.new("UIStroke")
		stroke.Parent = parent
	end
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 3
	stroke.Transparency = 0.15
end

local function ResolveTakeoffRatingBar()
	local bar = thisFrame:FindFirstChild("TakeoffRatingBarBg")
	if bar == nil or not bar:IsA("Frame") then
		warn("[JumpRunWayFrame] TakeoffRatingBarBg missing or not Frame")
		return
	end
	takeoffRatingBarBg = bar
	takeoffRatingBarBg.Visible = false
	takeoffRatingBarBg.ClipsDescendants = false
	takeoffRatingBarBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	takeoffRatingBarBg.BackgroundTransparency = 0.35
	takeoffRatingBarBg.BorderSizePixel = 0
	takeoffRatingBarBg.ZIndex = math.max(takeoffRatingBarBg.ZIndex, RATING_ROOT_ZINDEX + 2)
	EnsureTakeoffRatingBarCorner(takeoffRatingBarBg, UDim.new(0.35, 0))
	EnsureTakeoffRatingBarStroke(takeoffRatingBarBg)

	local regions = takeoffRatingBarBg:FindFirstChild("RegionsFrame")
	if regions == nil or not regions:IsA("Frame") then
		regions = Instance.new("Frame")
		regions.Name = "RegionsFrame"
		regions.Parent = takeoffRatingBarBg
	end
	takeoffRatingRegionsFrame = regions
	takeoffRatingRegionsFrame.BackgroundTransparency = 1
	takeoffRatingRegionsFrame.BorderSizePixel = 0
	takeoffRatingRegionsFrame.ClipsDescendants = true
	takeoffRatingRegionsFrame.Position = UDim2.fromScale(0.02, 0.18)
	takeoffRatingRegionsFrame.Size = UDim2.fromScale(0.96, 0.64)
	takeoffRatingRegionsFrame.ZIndex = takeoffRatingBarBg.ZIndex + 1
	EnsureTakeoffRatingBarCorner(takeoffRatingRegionsFrame, UDim.new(0.28, 0))

	local segmentZIndex = takeoffRatingRegionsFrame.ZIndex + 1
	takeoffLeftOkFrame = EnsureTakeoffSegment(
		takeoffRatingRegionsFrame,
		"LeftOkFrame",
		TakeoffRatingBarLeftOkColor,
		segmentZIndex
	)
	takeoffPerfectFrame = EnsureTakeoffSegment(
		takeoffRatingRegionsFrame,
		"PerfectFrame",
		TakeoffRatingBarPerfectColor,
		segmentZIndex
	)
	takeoffRightOkFrame = EnsureTakeoffSegment(
		takeoffRatingRegionsFrame,
		"RightOkFrame",
		TakeoffRatingBarRightOkColor,
		segmentZIndex
	)
	takeoffLateFrame = EnsureTakeoffSegment(
		takeoffRatingRegionsFrame,
		"LateFrame",
		TakeoffRatingBarLateColor,
		segmentZIndex
	)

	local split = takeoffRatingRegionsFrame:FindFirstChild("PerfectSplitFrame")
	if split == nil or not split:IsA("Frame") then
		split = Instance.new("Frame")
		split.Name = "PerfectSplitFrame"
		split.Parent = takeoffRatingRegionsFrame
	end
	takeoffPerfectSplitFrame = split
	takeoffPerfectSplitFrame.AnchorPoint = Vector2.new(0.5, 0)
	takeoffPerfectSplitFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	takeoffPerfectSplitFrame.BackgroundTransparency = 0.12
	takeoffPerfectSplitFrame.BorderSizePixel = 0
	takeoffPerfectSplitFrame.Position = UDim2.fromScale(0.5, 0)
	takeoffPerfectSplitFrame.Size = UDim2.fromScale(0.008, 1)
	takeoffPerfectSplitFrame.ZIndex = segmentZIndex + 1

	local marker = takeoffRatingBarBg:FindFirstChild("MarkerFrame")
	if marker == nil or not marker:IsA("Frame") then
		marker = Instance.new("Frame")
		marker.Name = "MarkerFrame"
		marker.Parent = takeoffRatingBarBg
	end
	takeoffMarkerFrame = marker
	takeoffMarkerFrame.AnchorPoint = Vector2.new(0.5, 1)
	takeoffMarkerFrame.Position = UDim2.fromScale(0, 0.08)
	takeoffMarkerFrame.Size = UDim2.fromScale(0.032, 0.5)
	takeoffMarkerFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	takeoffMarkerFrame.BackgroundTransparency = 0
	takeoffMarkerFrame.BorderSizePixel = 0
	takeoffMarkerFrame.ZIndex = takeoffRatingBarBg.ZIndex + 8
	EnsureTakeoffRatingBarCorner(takeoffMarkerFrame, UDim.new(0.25, 0))
	EnsureTakeoffRatingBarStroke(takeoffMarkerFrame)
end

local function ApplyTakeoffSegmentFrame(frame: Frame?, startRatio: number, endRatio: number)
	if frame == nil then
		return
	end
	local startClamped = math.clamp(startRatio, 0, 1)
	local endClamped = math.clamp(math.max(endRatio, startClamped), 0, 1)
	frame.Position = UDim2.fromScale(startClamped, 0)
	frame.Size = UDim2.fromScale(endClamped - startClamped, 1)
	frame.Visible = endClamped > startClamped
end

local function HideTakeoffRatingBar()
	if takeoffRatingBarBg ~= nil then
		takeoffRatingBarBg.Visible = false
	end
end

local function RefreshTakeoffRatingBar(payload: TakeoffRatingBarPayload)
	if takeoffRatingBarBg == nil or takeoffMarkerFrame == nil then
		return
	end
	if escapeHudModeActive or not payload.visible then
		HideTakeoffRatingBar()
		return
	end

	local leftOkEndRatio = math.clamp(payload.leftOkEndRatio, 0, 1)
	local perfectEndRatio = math.clamp(math.max(payload.perfectEndRatio, leftOkEndRatio), 0, 1)
	local rightOkEndRatio = math.clamp(math.max(payload.rightOkEndRatio, perfectEndRatio), 0, 1)
	local perfectSplitRatio = math.clamp(payload.perfectSplitRatio, leftOkEndRatio, perfectEndRatio)
	ApplyTakeoffSegmentFrame(takeoffLeftOkFrame, 0, leftOkEndRatio)
	ApplyTakeoffSegmentFrame(takeoffPerfectFrame, leftOkEndRatio, perfectEndRatio)
	ApplyTakeoffSegmentFrame(takeoffRightOkFrame, perfectEndRatio, rightOkEndRatio)
	ApplyTakeoffSegmentFrame(takeoffLateFrame, rightOkEndRatio, 1)
	if takeoffPerfectSplitFrame ~= nil then
		takeoffPerfectSplitFrame.Position = UDim2.fromScale(perfectSplitRatio, 0)
		takeoffPerfectSplitFrame.Visible = perfectEndRatio > leftOkEndRatio
	end

	local markerRatio = math.clamp(payload.progressRatio, 0, 1)
	takeoffMarkerFrame.Position = UDim2.fromScale(markerRatio, 0.08)
	takeoffRatingBarBg.Visible = true
end

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
		if child:IsA("GuiObject") and not IsEscapeHudExemptGui(child) then
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
		if movementBarBg ~= nil then
			movementBarBg.Visible = false
			OnMovementBarHidden()
		end
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

local function HideMovementBarForRunwayExit()
	if movementBarBg ~= nil then
		movementBarBg.Visible = false
		OnMovementBarHidden()
	end
end

local function StopEscapeRedScreen()
	DisconnectEscapeRedScreen()
	if redScreen ~= nil then
		redScreen.Visible = false
		redScreen.ImageTransparency = 1
	end
	SetEscapeHudMode(false)
	HideMovementBarForRunwayExit()
	HideTakeoffRatingBar()
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

local function ResolveSpeedValue()
	local speed = thisFrame:FindFirstChild("Speed")
	if speed == nil or not speed:IsA("TextLabel") then
		warn("[JumpRunWayFrame] Speed missing or not TextLabel")
		return
	end
	speedLabel = speed :: TextLabel
	local value = speed:FindFirstChild("Value")
	if value == nil or not value:IsA("TextLabel") then
		warn("[JumpRunWayFrame] Speed.Value missing or not TextLabel")
		return
	end
	speedValue = value :: TextLabel
	speedLabel.Visible = cfg.DEBUG
	speedValue.Visible = cfg.DEBUG
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
	tipDistanceHoldActive = false
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

local function ApplyDistanceHudVisibility()
	local shouldShowDistance = latestDistanceHudVisible
		or (tipDistanceHoldActive and latestDistanceCanShow and latestDistanceStuds > 0)
	if distanceLabel ~= nil then
		distanceLabel.Visible = shouldShowDistance
	end
	if distanceValue ~= nil then
		distanceValue.Visible = shouldShowDistance
		if shouldShowDistance then
			LocalizeDistanceMeters(distanceValue, latestDistanceStuds)
		end
	end
end

local function RefreshRunwayStats(
	distanceStuds: number,
	currentFuel: number,
	maxFuel: number,
	fuelVisible: boolean,
	distanceVisible: boolean,
	horizontalSpeed: number?
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

	local isEscapePhase = ClientGameInfo.IsInJumpRunwayEscapePhase()
	local inRunwayHud = ClientGameInfo.IsInJumpRunway() and not isEscapePhase and distanceStuds > 0
	local distanceHudVisible = inRunwayHud and distanceVisible
	if distanceStuds > 0 then
		latestDistanceStuds = distanceStuds
	end
	latestDistanceHudVisible = distanceHudVisible
	latestDistanceCanShow = inRunwayHud
	local speedHudVisible = inRunwayHud and cfg.DEBUG
	ApplyDistanceHudVisibility()
	if speedLabel ~= nil then
		speedLabel.Visible = speedHudVisible
	end
	if speedValue ~= nil then
		speedValue.Visible = speedHudVisible
		if speedHudVisible then
			TranslationTool.CustomAutoLocalizeTextLabel(
				speedValue,
				GameTexts.JumpRunwaySpeedMetersPerSecond.source,
				GameTexts.JumpRunwaySpeedMetersPerSecond.key,
				{ NumberExtension.FormatBigNumberAA(math.max(0, horizontalSpeed or 0)) }
			)
		end
	end

	if movementBarBg ~= nil then
		if distanceHudVisible then
			movementBarBg.Visible = true
			UpdateMovementBar(distanceStuds)
		else
			movementBarBg.Visible = false
			OnMovementBarHidden()
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
	tipDistanceHoldActive = true
	ApplyDistanceHudVisibility()
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
				tipDistanceHoldActive = false
				ApplyDistanceHudVisibility()
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
	HideTakeoffRatingBar()
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
	HideTakeoffRatingBar()
	BeginPresentation(GameTexts.JumpRunwayWindowRatingMiss)
end

local function OnCloseWindow(closeWindowId: string)
	if closeWindowId ~= windowId then
		return
	end
	StopEscapeRedScreen()
	OnMovementBarHidden()
	HideTakeoffRatingBar()
	CancelRatingPresentationOnly()
	CancelTipPresentationOnly()
	if activeRatingText then
		TranslationTool.RemoveCustomAutoLocalizeGui(activeRatingText)
		activeRatingText = nil
	end
	UIAdapter.RemoveAdaptiveFrame(thisFrame)
	thisFrame:Destroy()
end

ResolveRedScreen()
ResolveMovementBar()
ResolveTakeoffRatingBar()
ResolveFuelSizeBar()
ResolveDistanceValue()
ResolveSpeedValue()
ResolveTipText()

ClientMsg.ConnectJumpRunWayRefreshStats(RefreshRunwayStats)
ClientMsg.ConnectJumpRunWayRefreshTakeoffRatingBar(RefreshTakeoffRatingBar)
ClientMsg.ConnectJumpRunWayShowRatingTier(ShowRatingTier)
ClientMsg.ConnectJumpRunWayShowMiss(ShowMiss)
ClientMsg.ConnectJumpRunWayShowNewRecordTip(ShowNewRecordTip)
ClientMsg.ConnectJumpRunWayEnterEscapeHudMode(function()
	SetEscapeHudMode(true)
end)
ClientMsg.ConnectJumpRunWayStartEscapeRedScreen(StartEscapeRedScreen)
ClientMsg.ConnectJumpRunWayStopEscapeRedScreen(StopEscapeRedScreen)
ClientMsg.ConnectCurrentGuideTypeChanged(function()
	if ClientGameInfo.IsInJumpRunway() or ClientGameInfo.IsInJumpRunwayEscapePhase() then
		return
	end
	HideMovementBarForRunwayExit()
	HideTakeoffRatingBar()
end)
ClientMsg.ConnectCloseWindow(OnCloseWindow)

UIAdapter.AddAdaptiveFrame(thisFrame, UIAdapter.AdaptiveType.FullScreen)
