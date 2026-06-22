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

local cfg = GameConfig.JumpRunway

local localPlayer = players.LocalPlayer

local SCROLL_AT_RATIO = 0.75
local ZoneSegmentNamePrefix = "ZoneSegment_"
local MovementBarLegacyEndFadeImageName = "EndFadeImage"
local MovementBarEndFadeFrameName = "EndFadeFrame"
local MovementBarFadeGroupName = "MovementFadeGroup"
local MovementBarEndFadeStartRatio = 0.78
local MissingRunZoneWarnedMap = {} :: { [string]: boolean }

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
local zoneSegmentsScroll: ScrollingFrame? = nil
local zoneSegmentTemplate: ImageLabel? = nil
local myselfImageBaseY: UDim? = nil
local movementBarInitialized = false
local movementBarLastDistance = 0
local movementBarTotalDistance = 0
local movementBarPixelsPerMeter = 1
local movementBarSizeConn: RBXScriptConnection? = nil
local movementBarDebugLastPrintClock = 0
local MovementBarDebugPrintIntervalSec = 0.5
local takeoffRatingBarBg: Frame? = nil
local takeoffBarBgImage: ImageLabel? = nil
local takeoffPerfectImage: ImageLabel? = nil
local takeoffPerfectSplitImage: ImageLabel? = nil
local takeoffTriangleImage: ImageLabel? = nil
local takeoffMarkerImage: ImageLabel? = nil
local takeoffPerfectImageBaseY: UDim? = nil
local takeoffPerfectImageBaseSizeY: UDim? = nil
local takeoffPerfectSplitImageBaseY: UDim? = nil
local takeoffTriangleImageBaseY: UDim? = nil
local takeoffMarkerImageBaseY: UDim? = nil
local takeoffRatingBarUiSessionActive = false
local takeoffRatingBarUiFrozenPayload: TakeoffRatingBarPayload? = nil

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

local function GetGroundZoneFolder(): Folder?
	local ground = workspace:FindFirstChild("Ground")
	if ground == nil then
		ground = workspace:FindFirstChild("ground")
	end
	if ground == nil then
		return nil
	end
	local zoneFolder = ground:FindFirstChild("Zone")
	if zoneFolder and zoneFolder:IsA("Folder") then
		return zoneFolder
	end
	return nil
end

local function ResolveZoneDisplayName(resourceName: string): string
	local runZone = GameConfig.GetRunZoneByResourceName(resourceName)
	if runZone ~= nil then
		return runZone.name_t
	end
	if not MissingRunZoneWarnedMap[resourceName] then
		MissingRunZoneWarnedMap[resourceName] = true
		warn("[JumpRunWayFrame] RunZoneData missing for " .. resourceName)
	end
	return resourceName
end

local function ResolveZoneStyle(resourceName: string): any
	local styleMap = GameConfig.JumpRunwayMovementBarZoneStyleMap
	if styleMap == nil then
		return nil
	end
	return styleMap[resourceName]
end

local function ClearZoneSegment(segment: ImageLabel)
	for _, child in ipairs(segment:GetChildren()) do
		if child:IsA("UIGradient") then
			child:Destroy()
		end
	end
end

local function ApplyZoneSegmentStyle(segment: ImageLabel, resourceName: string, fallbackColor: Color3)
	ClearZoneSegment(segment)
	local style = ResolveZoneStyle(resourceName)
	if style == nil then
		segment.ImageColor3 = fallbackColor
		return
	end

	-- 已配置样式时保持 ImageColor3 为白色，颜色由 UIGradient 呈现
	segment.ImageColor3 = Color3.new(1, 1, 1)

	if type(style.gradient) == "table" and #style.gradient >= 2 then
		local keypoints = {}
		local lastIndex = #style.gradient
		for i, gradientColor in ipairs(style.gradient) do
			if typeof(gradientColor) == "Color3" then
				table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(lastIndex - 1, 1), gradientColor))
			end
		end
		if #keypoints < 2 then
			return
		end

		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(keypoints)
		if type(style.rotation) == "number" then
			gradient.Rotation = style.rotation
		end
		gradient.Parent = segment
		return
	end

	if typeof(style.color) == "Color3" then
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(style.color)
		gradient.Parent = segment
	end
end

local function ApplyMyselfMarkerOffset(markerOffsetX: number): number?
	if myselfImage == nil then
		return nil
	end
	local yScale = if myselfImageBaseY then myselfImageBaseY.Scale else 0.5
	local yOffset = if myselfImageBaseY then myselfImageBaseY.Offset else 0
	local markerParentScaleX = 0
	if movementBarBg ~= nil and zoneSegmentsScroll ~= nil then
		local markerScreenOffsetX = markerOffsetX + zoneSegmentsScroll.AbsolutePosition.X - movementBarBg.AbsolutePosition.X
		markerParentScaleX = markerScreenOffsetX / math.max(movementBarBg.AbsoluteSize.X, 1)
	else
		markerParentScaleX = markerOffsetX
	end
	markerParentScaleX = math.clamp(markerParentScaleX, 0, 1)
	myselfImage.Position = UDim2.new(markerParentScaleX, 0, yScale, yOffset)
	return markerParentScaleX
end

local function GetMovementBarCanvasScaleX(): number
	local template = zoneSegmentTemplate
	if template ~= nil and template.Size.X.Offset > 0 and template.AbsoluteSize.X > 0 then
		return template.AbsoluteSize.X / template.Size.X.Offset
	end
	return 1
end

local function PrintMovementBarDebug(reason: string, distanceStuds: number, canvasX: number?, markerOffsetX: number?, markerParentScaleX: number?)
	if cfg.MOVEMENT_BAR_DEBUG ~= true then
		return
	end
	local nowClock = os.clock()
	if nowClock - movementBarDebugLastPrintClock < MovementBarDebugPrintIntervalSec then
		return
	end
	movementBarDebugLastPrintClock = nowClock

	local barSize = if movementBarBg ~= nil then movementBarBg.AbsoluteSize else Vector2.zero
	local barPos = if movementBarBg ~= nil then movementBarBg.AbsolutePosition else Vector2.zero
	local scrollSize = if zoneSegmentsScroll ~= nil then zoneSegmentsScroll.AbsoluteSize else Vector2.zero
	local scrollPos = if zoneSegmentsScroll ~= nil then zoneSegmentsScroll.AbsolutePosition else Vector2.zero
	local scrollCanvasSize = if zoneSegmentsScroll ~= nil then zoneSegmentsScroll.CanvasSize else UDim2.new()
	local scrollCanvasPos = if zoneSegmentsScroll ~= nil then zoneSegmentsScroll.CanvasPosition else Vector2.zero
	local markerPos = if myselfImage ~= nil then myselfImage.Position else UDim2.new()
	local markerAbsPos = if myselfImage ~= nil then myselfImage.AbsolutePosition else Vector2.zero
	local markerAbsSize = if myselfImage ~= nil then myselfImage.AbsoluteSize else Vector2.zero
	local templateSize = if zoneSegmentTemplate ~= nil then zoneSegmentTemplate.Size else UDim2.new()
	local templateAbsSize = if zoneSegmentTemplate ~= nil then zoneSegmentTemplate.AbsoluteSize else Vector2.zero
	local canvasScaleX = GetMovementBarCanvasScaleX()

	warn(
		string.format(
			"[JumpRunWayFrame][MovementBar] reason=%s dist=%.2f total=%.2f pxPerStud=%.4f canvasScaleX=%.4f canvasX=%s markerOffset=%s markerParentScale=%s "
				.. "barPos=(%.1f,%.1f) barSize=(%.1f,%.1f) scrollPos=(%.1f,%.1f) scrollSize=(%.1f,%.1f) "
				.. "canvasSizeX={%.4f,%d} canvasPos=(%.1f,%.1f) templateSizeX={%.4f,%d} templateAbsX=%.1f markerPosX={%.4f,%d} markerAbs=(%.1f,%.1f %.1fx%.1f)",
			reason,
			distanceStuds,
			movementBarTotalDistance,
			movementBarPixelsPerMeter,
			canvasScaleX,
			if canvasX ~= nil then string.format("%.1f", canvasX) else "nil",
			if markerOffsetX ~= nil then string.format("%.1f", markerOffsetX) else "nil",
			if markerParentScaleX ~= nil then string.format("%.4f", markerParentScaleX) else "nil",
			barPos.X,
			barPos.Y,
			barSize.X,
			barSize.Y,
			scrollPos.X,
			scrollPos.Y,
			scrollSize.X,
			scrollSize.Y,
			scrollCanvasSize.X.Scale,
			scrollCanvasSize.X.Offset,
			scrollCanvasPos.X,
			scrollCanvasPos.Y,
			templateSize.X.Scale,
			templateSize.X.Offset,
			templateAbsSize.X,
			markerPos.X.Scale,
			markerPos.X.Offset,
			markerAbsPos.X,
			markerAbsPos.Y,
			markerAbsSize.X,
			markerAbsSize.Y
		)
	)
end

local function ComputeMovementBarScroll(distanceStuds: number): (number, number)
	local scroll = zoneSegmentsScroll
	if scroll == nil then
		return 0, 0
	end
	local canvasScaleX = GetMovementBarCanvasScaleX()
	local viewportScreenW = scroll.AbsoluteSize.X
	local viewportCanvasW = viewportScreenW / math.max(canvasScaleX, 0.001)
	local contentCanvasW = movementBarTotalDistance * movementBarPixelsPerMeter
	local canvasW = math.max(contentCanvasW, viewportCanvasW)
	local maxCanvasX = math.max(canvasW - viewportCanvasW, 0)
	if movementBarTotalDistance <= 0 or viewportCanvasW <= 0 then
		return 0, 0
	end

	local distanceRatio = math.clamp(distanceStuds / movementBarTotalDistance, 0, 1)
	local distanceCanvasX = distanceRatio * contentCanvasW
	local targetMarkerCanvasX = SCROLL_AT_RATIO * viewportCanvasW
	local canvasX = math.clamp(distanceCanvasX - targetMarkerCanvasX, 0, maxCanvasX)
	local markerCanvasOffsetX = math.clamp(distanceCanvasX - canvasX, 0, viewportCanvasW)
	local canvasScreenX = canvasX * canvasScaleX
	local markerScreenOffsetX = markerCanvasOffsetX * canvasScaleX
	return canvasScreenX, markerScreenOffsetX
end

local function ApplyMovementBarFromDistance(distanceStuds: number)
	if zoneSegmentsScroll == nil then
		return
	end
	local canvasX, markerOffsetX = ComputeMovementBarScroll(distanceStuds)
	zoneSegmentsScroll.CanvasPosition = Vector2.new(math.max(0, canvasX), 0)
	local markerParentScaleX = ApplyMyselfMarkerOffset(markerOffsetX)
	PrintMovementBarDebug("apply", distanceStuds, canvasX, markerOffsetX, markerParentScaleX)
end

local function ResetMovementBarState(distanceStuds: number)
	if zoneSegmentsScroll then
		zoneSegmentsScroll.CanvasPosition = Vector2.zero
	end
	ApplyMovementBarFromDistance(distanceStuds)
end

local function OnMovementBarHidden()
	movementBarInitialized = false
end

local function DisconnectMovementBarSizeConn()
	if movementBarSizeConn then
		movementBarSizeConn:Disconnect()
		movementBarSizeConn = nil
	end
end

local function UpdateMovementBar(distanceStuds: number)
	if movementBarBg == nil or myselfImage == nil or zoneSegmentsScroll == nil then
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

local function ConfigureZoneSegmentsScroll(scroll: ScrollingFrame, parent: GuiObject)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 0
	scroll.ScrollingEnabled = false
	scroll.ClipsDescendants = true
	scroll.AnchorPoint = Vector2.new(0, 0)
	scroll.Position = UDim2.fromScale(0, 0)
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.ZIndex = parent.ZIndex + 1
end

local function ResolveZoneSegmentsScroll(parent: GuiObject): ScrollingFrame?
	local existing = parent:FindFirstChild("ZoneSegmentsScroll")
	if existing and existing:IsA("ScrollingFrame") then
		ConfigureZoneSegmentsScroll(existing, parent)
		return existing
	end

	warn("[JumpRunWayFrame] MovementBarBg.MovementFadeGroup.ZoneSegmentsScroll missing or not ScrollingFrame")
	return nil
end

local function ResolveMovementBarFadeGroup(bar: ImageLabel): CanvasGroup?
	local legacy = bar:FindFirstChild(MovementBarLegacyEndFadeImageName)
	if legacy ~= nil then
		legacy:Destroy()
	end

	local legacyFadeFrame = bar:FindFirstChild(MovementBarEndFadeFrameName)
	if legacyFadeFrame ~= nil then
		legacyFadeFrame:Destroy()
	end

	local existing = bar:FindFirstChild(MovementBarFadeGroupName)
	if existing == nil or not existing:IsA("CanvasGroup") then
		warn("[JumpRunWayFrame] MovementBarBg.MovementFadeGroup missing or not CanvasGroup")
		return nil
	end
	local fadeGroup = existing

	fadeGroup.BackgroundTransparency = 1
	fadeGroup.BorderSizePixel = 0
	fadeGroup.AnchorPoint = Vector2.new(0, 0)
	fadeGroup.Position = UDim2.fromScale(0, 0)
	fadeGroup.Size = UDim2.fromScale(1, 1)
	fadeGroup.ZIndex = bar.ZIndex + 1
	fadeGroup.Visible = true

	local gradient = fadeGroup:FindFirstChildOfClass("UIGradient")
	if gradient == nil then
		warn("[JumpRunWayFrame] MovementBarBg.MovementFadeGroup.UIGradient missing")
		return nil
	end
	gradient.Rotation = 0
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(MovementBarEndFadeStartRatio, 0),
		NumberSequenceKeypoint.new(1, 1),
	})

	return fadeGroup
end

local function ResolveZoneSegmentTemplate(scroll: ScrollingFrame): ImageLabel?
	local template = scroll:FindFirstChild("ZoneSegment")
	if template == nil or not template:IsA("ImageLabel") then
		warn("[JumpRunWayFrame] MovementBarBg.MovementFadeGroup.ZoneSegmentsScroll.ZoneSegment missing or not ImageLabel")
		return nil
	end
	template.Visible = false
	return template
end

local function ClearZoneSegments(scroll: ScrollingFrame)
	for _, child in ipairs(scroll:GetChildren()) do
		if child.Name:sub(1, #ZoneSegmentNamePrefix) == ZoneSegmentNamePrefix then
			child:Destroy()
		end
	end
end

local function ApplyZoneSegmentLabel(segment: ImageLabel, displayName: string)
	local label = segment:FindFirstChild("ZoneNameText")
	if label == nil or not label:IsA("TextLabel") then
		warn("[JumpRunWayFrame] ZoneSegment.ZoneNameText missing or not TextLabel")
		return
	end
	label.AutoLocalize = false
	TranslationTool.CustomAutoLocalizeTextLabel(label, displayName, "")
end

local function CreateZoneSegment(scroll: ScrollingFrame, part: BasePart, startOffsetX: number, widthOffsetX: number)
	local template = zoneSegmentTemplate
	if template == nil then
		return
	end
	local segment = template:Clone()
	segment.Name = ZoneSegmentNamePrefix .. part.Name
	segment.AnchorPoint = Vector2.new(0, 0)
	segment.Position = UDim2.new(0, math.floor(startOffsetX + 0.5), 0, 0)
	segment.Size = UDim2.new(0, math.max(1, math.floor(widthOffsetX + 0.5)), 1, 0)
	segment.Visible = true
	segment.Parent = scroll
	ApplyZoneSegmentStyle(segment, part.Name, part.Color)
	ApplyZoneSegmentLabel(segment, ResolveZoneDisplayName(part.Name))
end

local function ResolveZoneSegmentTemplateWidthOffset(): number
	local template = zoneSegmentTemplate
	if template == nil then
		return 0
	end
	return template.Size.X.Offset
end

local function RebuildZoneSegments()
	local scroll = zoneSegmentsScroll
	if scroll == nil then
		return
	end
	ClearZoneSegments(scroll)
	movementBarTotalDistance = 0

	local zoneFolder = GetGroundZoneFolder()
	if zoneFolder == nil then
		warn("[JumpRunWayFrame] Workspace.Ground.Zone missing")
		return
	end

	local zoneParts = {}
	for _, child in ipairs(zoneFolder:GetChildren()) do
		if child:IsA("BasePart") and child.Size.X > 0 then
			table.insert(zoneParts, child)
		end
	end
	table.sort(zoneParts, function(a: BasePart, b: BasePart)
		local ax = a.Position.X - a.Size.X * 0.5
		local bx = b.Position.X - b.Size.X * 0.5
		if math.abs(ax - bx) > 0.001 then
			return ax < bx
		end
		return a.Name < b.Name
	end)

	for _, part in ipairs(zoneParts) do
		movementBarTotalDistance += part.Size.X
	end
	if movementBarTotalDistance <= 0 then
		warn("[JumpRunWayFrame] Workspace.Ground.Zone has no valid BasePart")
		return
	end

	local firstZonePart = zoneParts[1]
	local templateWidthOffset = ResolveZoneSegmentTemplateWidthOffset()
	if firstZonePart == nil or templateWidthOffset <= 0 then
		warn("[JumpRunWayFrame] ZoneSegment template Size.X.Offset must be greater than 0")
		return
	end

	movementBarPixelsPerMeter = templateWidthOffset / firstZonePart.Size.X
	local canvasWidthOffset = math.max(1, math.floor(movementBarTotalDistance * movementBarPixelsPerMeter + 0.5))
	scroll.CanvasSize = UDim2.new(0, canvasWidthOffset, 1, 0)
	local startDistance = 0
	for _, part in ipairs(zoneParts) do
		local startOffsetX = startDistance * movementBarPixelsPerMeter
		local widthOffsetX = part.Size.X * movementBarPixelsPerMeter
		CreateZoneSegment(scroll, part, startOffsetX, widthOffsetX)
		startDistance += part.Size.X
	end
	PrintMovementBarDebug("rebuild", movementBarLastDistance, nil, nil, nil)
end

local function ResolveMovementBar()
	local bar = thisFrame:FindFirstChild("MovementBarBg")
	if bar == nil or not bar:IsA("ImageLabel") then
		warn("[JumpRunWayFrame] MovementBarBg missing or not ImageLabel")
		return
	end
	movementBarBg = bar
	movementBarBg.Visible = false
	movementBarBg.BackgroundTransparency = 1
	movementBarBg.ClipsDescendants = false

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

	local legacy = movementBarBg:FindFirstChild("TextLabel")
	if legacy and legacy:IsA("TextLabel") then
		legacy.Visible = false
	end

	local movementFadeGroup = ResolveMovementBarFadeGroup(movementBarBg)
	if movementFadeGroup == nil then
		return
	end
	zoneSegmentsScroll = ResolveZoneSegmentsScroll(movementFadeGroup)
	if zoneSegmentsScroll == nil then
		return
	end
	zoneSegmentTemplate = ResolveZoneSegmentTemplate(zoneSegmentsScroll :: ScrollingFrame)
	RebuildZoneSegments()
	DisconnectMovementBarSizeConn()
	movementBarSizeConn = (zoneSegmentsScroll :: ScrollingFrame):GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		RebuildZoneSegments()
		ApplyMovementBarFromDistance(movementBarLastDistance)
	end)
	task.defer(function()
		if zoneSegmentsScroll ~= nil and movementBarLastDistance > 0 then
			ApplyMovementBarFromDistance(movementBarLastDistance)
		elseif zoneSegmentsScroll ~= nil then
			ApplyMovementBarFromDistance(0)
		end
	end)
end

local function ResolveTakeoffImage(parent: GuiObject, name: string): ImageLabel?
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("ImageLabel") then
		return existing
	end
	warn("[JumpRunWayFrame] TakeoffRatingBarBg." .. name .. " missing or not ImageLabel")
	return nil
end

local function IsTakeoffRatingBarReady(): boolean
	return takeoffRatingBarBg ~= nil
		and takeoffBarBgImage ~= nil
		and takeoffPerfectImage ~= nil
		and takeoffPerfectSplitImage ~= nil
		and takeoffTriangleImage ~= nil
		and takeoffMarkerImage ~= nil
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
	takeoffRatingBarBg.BackgroundTransparency = 1
	takeoffRatingBarBg.BorderSizePixel = 0
	takeoffRatingBarBg.ZIndex = math.max(takeoffRatingBarBg.ZIndex, RATING_ROOT_ZINDEX + 2)

	takeoffBarBgImage = ResolveTakeoffImage(takeoffRatingBarBg, "BarBgImage")
	takeoffPerfectImage = ResolveTakeoffImage(takeoffRatingBarBg, "PerfectImage")
	takeoffPerfectSplitImage = ResolveTakeoffImage(takeoffRatingBarBg, "SplitWhiteImage")
	takeoffTriangleImage = ResolveTakeoffImage(takeoffRatingBarBg, "TriangleImage")
	takeoffMarkerImage = ResolveTakeoffImage(takeoffRatingBarBg, "MarkerCircleImage")

	local perfectImage = takeoffPerfectImage
	local perfectSplitImage = takeoffPerfectSplitImage
	local triangleImage = takeoffTriangleImage
	local markerImage = takeoffMarkerImage
	if takeoffBarBgImage == nil or perfectImage == nil or perfectSplitImage == nil or triangleImage == nil or markerImage == nil then
		return
	end

	takeoffPerfectImageBaseY = perfectImage.Position.Y
	takeoffPerfectImageBaseSizeY = perfectImage.Size.Y
	takeoffPerfectSplitImageBaseY = perfectSplitImage.Position.Y
	takeoffTriangleImageBaseY = triangleImage.Position.Y
	takeoffMarkerImageBaseY = markerImage.Position.Y
end

local function ResetTakeoffRatingBarUiSession()
	takeoffRatingBarUiSessionActive = false
	takeoffRatingBarUiFrozenPayload = nil
end

local function HideTakeoffRatingBar()
	if takeoffRatingBarBg ~= nil then
		takeoffRatingBarBg.Visible = false
	end
	ResetTakeoffRatingBarUiSession()
end

local function ApplyTakeoffRatingBarLayout(payload: TakeoffRatingBarPayload)
	local bar = takeoffRatingBarBg
	local perfectImage = takeoffPerfectImage
	local perfectSplitImage = takeoffPerfectSplitImage
	local triangleImage = takeoffTriangleImage
	local markerImage = takeoffMarkerImage
	if bar == nil or takeoffBarBgImage == nil or perfectImage == nil or perfectSplitImage == nil or triangleImage == nil or markerImage == nil then
		return
	end
	local leftOkEndRatio = math.clamp(payload.leftOkEndRatio, 0, 1)
	local perfectEndRatio = math.clamp(math.max(payload.perfectEndRatio, leftOkEndRatio), 0, 1)
	local perfectSplitRatio = math.clamp(payload.perfectSplitRatio, leftOkEndRatio, perfectEndRatio)
	local perfectWidth = perfectEndRatio - leftOkEndRatio
	local hasPerfectRegion = perfectWidth > 0
	local perfectY = if takeoffPerfectImageBaseY ~= nil then takeoffPerfectImageBaseY else perfectImage.Position.Y
	local perfectSizeY = if takeoffPerfectImageBaseSizeY ~= nil then takeoffPerfectImageBaseSizeY else perfectImage.Size.Y
	local splitY = if takeoffPerfectSplitImageBaseY ~= nil then takeoffPerfectSplitImageBaseY else perfectSplitImage.Position.Y
	local triangleY = if takeoffTriangleImageBaseY ~= nil then takeoffTriangleImageBaseY else triangleImage.Position.Y
	perfectImage.Position = UDim2.new(leftOkEndRatio, 0, perfectY.Scale, perfectY.Offset)
	perfectImage.Size = UDim2.new(perfectWidth, 0, perfectSizeY.Scale, perfectSizeY.Offset)
	perfectImage.Visible = hasPerfectRegion
	perfectSplitImage.Position = UDim2.new(perfectSplitRatio, 0, splitY.Scale, splitY.Offset)
	perfectSplitImage.Visible = hasPerfectRegion
	triangleImage.Position = UDim2.new(perfectSplitRatio, 0, triangleY.Scale, triangleY.Offset)
	triangleImage.Visible = hasPerfectRegion
	local markerRatio = math.clamp(payload.progressRatio, 0, 1)
	local markerY = if takeoffMarkerImageBaseY ~= nil then takeoffMarkerImageBaseY else markerImage.Position.Y
	markerImage.Position = UDim2.new(markerRatio, 0, markerY.Scale, markerY.Offset)
	bar.Visible = true
end

local function RefreshTakeoffRatingBar(payload: TakeoffRatingBarPayload)
	local bar = takeoffRatingBarBg
	local markerImage = takeoffMarkerImage
	if not IsTakeoffRatingBarReady() or bar == nil or markerImage == nil then
		return
	end
	if escapeHudModeActive or not payload.visible then
		HideTakeoffRatingBar()
		return
	end
	if takeoffRatingBarUiSessionActive and takeoffRatingBarUiFrozenPayload ~= nil then
		local markerRatio = math.clamp(payload.progressRatio, 0, 1)
		local markerY = if takeoffMarkerImageBaseY ~= nil then takeoffMarkerImageBaseY else markerImage.Position.Y
		markerImage.Position = UDim2.new(markerRatio, 0, markerY.Scale, markerY.Offset)
		bar.Visible = true
		return
	end
	takeoffRatingBarUiFrozenPayload = {
		visible = true,
		progressRatio = math.clamp(payload.progressRatio, 0, 1),
		leftOkEndRatio = math.clamp(payload.leftOkEndRatio, 0, 1),
		perfectSplitRatio = math.clamp(payload.perfectSplitRatio, 0, 1),
		perfectEndRatio = math.clamp(payload.perfectEndRatio, 0, 1),
		rightOkEndRatio = math.clamp(payload.rightOkEndRatio, 0, 1),
	}
	takeoffRatingBarUiSessionActive = true
	ApplyTakeoffRatingBarLayout(takeoffRatingBarUiFrozenPayload :: TakeoffRatingBarPayload)
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
	local shouldShowDistance = latestDistanceHudVisible or (tipDistanceHoldActive and latestDistanceCanShow and latestDistanceStuds > 0)
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
		fuelMask.Size = UDim2.new(currentSize.X.Scale, currentSize.X.Offset, baseSizeY.Scale * fuelRatio, math.floor(baseSizeY.Offset * fuelRatio + 0.5))
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
	DisconnectMovementBarSizeConn()
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
