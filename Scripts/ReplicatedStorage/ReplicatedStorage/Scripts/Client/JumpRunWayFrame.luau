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

local presentationToken = 0
local activeRatingText: TextLabel? = nil
local activeColorConn: RBXScriptConnection? = nil
local activeScaleTween: Tween? = nil
local activeFadeTween: Tween? = nil

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

local function ApplyRatingText(label: TextLabel, entry: RatingTextEntry)
	label.AutoLocalize = false
	TranslationTool.CustomAutoLocalizeTextLabel(label, entry.source, entry.key)
end

local function ResolveImpactUIScale(label: TextLabel, holder: Frame, root: Frame): UIScale
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
	local created = Instance.new("UIScale")
	created.Parent = holder
	return created
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
	if activeRatingText then
		TranslationTool.RemoveCustomAutoLocalizeGui(activeRatingText)
		activeRatingText = nil
	end
	if UIManager.IsWindowShowing(WINDOW_ID) then
		UIManager.CloseWindow(WINDOW_ID)
	end
end

local function BeginPresentation(entry: RatingTextEntry)
	CancelRatingPresentationOnly()
	local myToken = presentationToken

	if not jumpRunWayFrameTemplate:IsA("Frame") then
		warn("[JumpRunWayFrame] ReplicatedStorage.UI.JumpRunWayFrame must be a Frame")
		return
	end

	JumpRunWayFrame.EnsureSession()
	local rootAny = UIManager.GetWindowRoot(WINDOW_ID)
	if rootAny == nil or not rootAny:IsA("Frame") then
		warn("[JumpRunWayFrame] JumpRunWay window not available after OpenWindow")
		return
	end
	local rootFrame = rootAny :: Frame

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
	uiScale.Scale = cfg.JUMP_RUNWAY_RATING_IMPACT_START_SCALE

	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end

	TranslationTool.RemoveCustomAutoLocalizeGui(label)
	ApplyRatingText(label, entry)

	local impactInfo = TweenInfo.new(impactSec, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local twScale = tweenService:Create(uiScale, impactInfo, { Scale = 1 })
	activeScaleTween = twScale

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

	twScale.Completed:Once(function()
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
	end)

	twScale:Play()
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
