--!strict
-- JumpRunWayFrame：跑道会话内由 UIManager.OpenWindow 挂载；RatingText 仅显隐 + 砸入缩放 + 变色淡出
-- 根 Frame 的 Position/AnchorPoint 以 ReplicatedStorage.UI.JumpRunWayFrame 模板为准

local JumpRunWayFrame = {}

local tweenService = game:GetService("TweenService")
local runService = game:GetService("RunService")

local replicatedStorage = game:GetService("ReplicatedStorage")
local uiFolder = replicatedStorage:WaitForChild("UI")
local jumpRunWayFrameTemplate = uiFolder:WaitForChild("JumpRunWayFrame")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")
local core = replicatedStorage:WaitForChild("Core")
local coreClientScripts = core:WaitForChild("Scripts"):WaitForChild("Client")

local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local TranslationTool = require(coreClientScripts:WaitForChild("TranslationTool"))
local UIManager = require(clientScripts:WaitForChild("UIManager"))

type RatingTextEntry = { source: string, key: string }

local cfg = GameConfig.JumpRunway
local WINDOW_ID = UIManager.WindowId.JumpRunWayFrame
local TipTextPopOffset = UDim2.new(0, 0, 0, -18)
local TipTextTotalSec = 1.35

local presentationToken = 0
local tipPresentationToken = 0
local activeRatingText: TextLabel? = nil
local activeColorConn: RBXScriptConnection? = nil
local activeScaleTween: Tween? = nil
local activeFadeTween: Tween? = nil
local activeTipTweenList: { Tween } = {}
local initializedTipText: TextLabel? = nil
local fuelMaskBaseSizeYMap: { [Frame]: UDim } = {}

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
end

local function ApplyRatingText(label: TextLabel, entry: RatingTextEntry)
	label.AutoLocalize = false
	TranslationTool.CustomAutoLocalizeTextLabel(label, entry.source, entry.key)
end

local function ResolveFuelSizeBar(root: Frame): (ImageLabel?, Frame?)
	local bg = root:FindFirstChild("FuelSizeBarBg")
	if bg == nil or not bg:IsA("ImageLabel") then
		warn("[JumpRunWayFrame] FuelSizeBarBg missing or not ImageLabel")
		return nil, nil
	end
	local bgLabel = bg :: ImageLabel

	local mask = bgLabel:FindFirstChild("MaskFrame")
	if mask == nil or not mask:IsA("Frame") then
		warn("[JumpRunWayFrame] FuelSizeBarBg.MaskFrame missing or not Frame")
		return bgLabel, nil
	end
	local maskFrame = mask :: Frame
	if fuelMaskBaseSizeYMap[maskFrame] == nil then
		fuelMaskBaseSizeYMap[maskFrame] = maskFrame.Size.Y
	end
	return bgLabel, maskFrame
end

local function ResolveDistanceValue(root: Frame): (TextLabel?, TextLabel?)
	local distance = root:FindFirstChild("Distance")
	if distance == nil or not distance:IsA("TextLabel") then
		warn("[JumpRunWayFrame] Distance missing or not TextLabel")
		return nil, nil
	end
	local distanceLabel = distance :: TextLabel

	local value = distanceLabel:FindFirstChild("Value")
	if value == nil or not value:IsA("TextLabel") then
		warn("[JumpRunWayFrame] Distance.Value missing or not TextLabel")
		return distanceLabel, nil
	end
	return distanceLabel, value :: TextLabel
end

local function ResolveTipText(root: Frame): TextLabel?
	local tip = root:FindFirstChild("TipText")
	if tip == nil or not tip:IsA("TextLabel") then
		warn("[JumpRunWayFrame] TipText missing or not TextLabel")
		return nil
	end
	local tipText = tip :: TextLabel
	if initializedTipText ~= tipText then
		tipText.Visible = false
		initializedTipText = tipText
	end
	return tipText
end

local function ResolveRootFrame(): Frame?
	if not jumpRunWayFrameTemplate:IsA("Frame") then
		warn("[JumpRunWayFrame] ReplicatedStorage.UI.JumpRunWayFrame must be a Frame")
		return nil
	end
	JumpRunWayFrame.EnsureSession()
	local rootAny = UIManager.GetWindowRoot(WINDOW_ID)
	if rootAny == nil or not rootAny:IsA("Frame") then
		warn("[JumpRunWayFrame] JumpRunWay window not available after OpenWindow")
		return nil
	end
	return rootAny :: Frame
end

local function ResolveRunwayHudWidgets(rootFrame: Frame): (ImageLabel?, Frame?, TextLabel?, TextLabel?, TextLabel?)
	local fuelBg, fuelMask = ResolveFuelSizeBar(rootFrame)
	local distanceLabel, distanceValue = ResolveDistanceValue(rootFrame)
	local tipText = ResolveTipText(rootFrame)
	return fuelBg, fuelMask, distanceLabel, distanceValue, tipText
end

local function ResolveImpactUIScale(label: TextLabel, holder: Frame, root: Frame): UIScale?
	local onLabel = label:FindFirstChildOfClass("UIScale")
	if onLabel then
		return onLabel
	end
	local onHolder = holder:FindFirstChildOfClass("UIScale")
	if onHolder then
		return onHolder
	end
	local onRoot = root:FindFirstChildOfClass("UIScale")
	if onRoot then
		return onRoot
	end
	return nil
end

function JumpRunWayFrame.EnsureSession()
	local hostGui = UIManager.GetGameScreenGui()
	if hostGui == nil or hostGui.Parent == nil then
		warn("[JumpRunWayFrame] GameScreenGui not ready (UIManager.Init not called yet)")
		return
	end
	if not UIManager.IsWindowShowing(WINDOW_ID) then
		UIManager.OpenWindow(WINDOW_ID)
	end
end

function JumpRunWayFrame.EndSession()
	CancelRatingPresentationOnly()
	CancelTipPresentationOnly()
	initializedTipText = nil
	table.clear(fuelMaskBaseSizeYMap)
	if activeRatingText then
		TranslationTool.RemoveCustomAutoLocalizeGui(activeRatingText)
		activeRatingText = nil
	end
	if UIManager.IsWindowShowing(WINDOW_ID) then
		UIManager.CloseWindow(WINDOW_ID)
	end
end

function JumpRunWayFrame.RefreshRunwayStats(distanceStuds: number, currentFuel: number, maxFuel: number, fuelVisible: boolean, distanceVisible: boolean)
	local rootFrame = ResolveRootFrame()
	if rootFrame == nil then
		return
	end
	local fuelBg, fuelMask, distanceLabel, distanceValue, _tipText = ResolveRunwayHudWidgets(rootFrame)
	local fuelRatio = if maxFuel > 0 then math.clamp(currentFuel / maxFuel, 0, 1) else 0
	if fuelBg ~= nil then
		fuelBg.Visible = fuelVisible and maxFuel > 0
	end
	if fuelMask ~= nil then
		local currentSize = fuelMask.Size
		local baseSizeY = fuelMaskBaseSizeYMap[fuelMask] or currentSize.Y
		fuelMaskBaseSizeYMap[fuelMask] = baseSizeY
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
		distanceValue.Text = string.format("%dm", math.max(0, math.floor(distanceStuds + 0.5)))
	end
end

function JumpRunWayFrame.ShowNewRecordTip()
	local rootFrame = ResolveRootFrame()
	if rootFrame == nil then
		return
	end
	local _fuelBg, _fuelMask, _distanceLabel, _distanceValue, tipText = ResolveRunwayHudWidgets(rootFrame)
	if tipText == nil then
		return
	end
	CancelTipPresentationOnly()
	local myToken = tipPresentationToken
	local basePosition = tipText.Position
	local baseRotation = tipText.Rotation
	tipText.Visible = true
	tipText.Position = basePosition + TipTextPopOffset
	tipText.Rotation = baseRotation - 7
	tipText.TextTransparency = 1
	local stroke = tipText:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 1
	end
	local scale = tipText:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0.55
	end

	local popInfo = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local settleInfo = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeInfo = TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local textInTween = tweenService:Create(tipText, popInfo, {
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
			local fadeTextTween = tweenService:Create(tipText, fadeInfo, {
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
				tipText.Visible = false
			end)
			fadeTextTween:Play()
		end)
	end)
	textInTween:Play()
end

local function BeginPresentation(entry: RatingTextEntry)
	CancelRatingPresentationOnly()
	local myToken = presentationToken

	local rootFrame = ResolveRootFrame()
	if rootFrame == nil then
		return
	end

	local totalSec = math.max(0.5, cfg.JUMP_RUNWAY_RATING_UI_TOTAL_SEC)
	local impactSec = math.clamp(cfg.JUMP_RUNWAY_RATING_IMPACT_SEC, 0.08, totalSec * 0.6)
	local fadeSec = math.clamp(cfg.JUMP_RUNWAY_RATING_FADE_SEC, 0.05, totalSec * 0.4)
	local colorCycleSec = math.max(0.05, totalSec - impactSec - fadeSec)

	local holder = rootFrame:WaitForChild("Holder") :: Frame
	local label = holder:WaitForChild("RatingText") :: TextLabel
	activeRatingText = label

	label.TextSize = cfg.JUMP_RUNWAY_RATING_TEXT_SIZE
	label.TextTransparency = 0
	label.Visible = true
	label.TextColor3 = Color3.new(1, 1, 1)

	local uiScale = ResolveImpactUIScale(label, holder, rootFrame)
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

function JumpRunWayFrame.ShowRatingTier(tier: number)
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

function JumpRunWayFrame.ShowMiss()
	BeginPresentation(GameTexts.JumpRunwayWindowRatingMiss)
end

return JumpRunWayFrame
