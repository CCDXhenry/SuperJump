--!strict
local GroupRewardClientManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local players: Players = game:GetService("Players")
local runService: RunService = game:GetService("RunService")
local workspace: Workspace = game:GetService("Workspace")

local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local TranslationTool = require(coreClientScripts:FindFirstChild("TranslationTool"))
local SoundTool = require(coreSharedScripts:FindFirstChild("SoundTool"))

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local BillboardManager = require(clientScripts:FindFirstChild("BillboardManager"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local BrainrotVariantVisualTool = require(clientScripts:FindFirstChild("BrainrotVariantVisualTool"))

local ROTATION_SPEED = math.rad(30)
local HOVER_AMPLITUDE = 0.4
local HOVER_SPEED = 2
local HINT_DISTANCE = 10
local SUCCESS_COLOR = Color3.fromRGB(0, 255, 0)
local DISPLAY_MODEL_NAME = "Model"

local groupRewardModel: Model?
local displayModel: Model?
local rootPart: Part?
local billboardGui: BillboardGui?
local originModelCFrame: CFrame?
local hasShownHint = false
local hasShownSuccessTip = false

local function HasClaimedGroupReward(): boolean
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil then
		return false
	end

	return localPlayerInfo.hasClaimedGroupReward
end

local function RefreshTipText()
	if not billboardGui then
		return
	end

	local controllerFrame = billboardGui:FindFirstChild("ControllerFrame")
	if not controllerFrame then
		return
	end

	local tipText1 = controllerFrame:FindFirstChild("TipText1") :: TextLabel?
	local tipText2 = controllerFrame:FindFirstChild("TipText2") :: TextLabel?
	local tipText3 = controllerFrame:FindFirstChild("TipText3") :: TextLabel?
	local hasClaimed = HasClaimedGroupReward()

	if tipText1 and tipText2 and tipText3 then
		if hasClaimed then
			tipText1.Visible = false
			tipText3.Visible = false
			TranslationTool.CustomAutoLocalizeTextLabel(
				tipText2,
				GameTexts.GroupRewardTipClaimed.source,
				GameTexts.GroupRewardTipClaimed.key
			)
		else
			tipText1.Visible = true
			tipText3.Visible = true
			TranslationTool.CustomAutoLocalizeTextLabel(tipText1, GameTexts.GroupRewardTip1.source, GameTexts.GroupRewardTip1.key)
			TranslationTool.CustomAutoLocalizeTextLabel(tipText2, GameTexts.GroupRewardTip2.source, GameTexts.GroupRewardTip2.key)
			TranslationTool.CustomAutoLocalizeTextLabel(tipText3, GameTexts.GroupRewardTip3.source, GameTexts.GroupRewardTip3.key)
		end
	end
end

local function PlayClaimSuccessHint()
	if hasShownSuccessTip then
		return
	end
	hasShownSuccessTip = true

	ClientMsg.FireShowGameTip(
		GameTexts.GroupRewardClaimSuccess.source,
		GameConfig.GameTipTweenType.StayFlyUp,
		GameTexts.GroupRewardClaimSuccess.key,
		nil,
		SUCCESS_COLOR
	)

	local soundFolder = replicatedStorage:FindFirstChild("Sounds")
	local getCoinSound = if soundFolder then soundFolder:FindFirstChild("GetCoinSound") :: Sound? else nil
	if getCoinSound then
		SoundTool.PlayGlobalSoundEffect(getCoinSound, false)
	end
end

local function CheckAndShowSuccessTip()
	if HasClaimedGroupReward() then
		RefreshTipText()
	end
end

local function UpdateHint(_deltaTime: number)
	if not rootPart or not players.LocalPlayer.Character then
		return
	end

	local char = players.LocalPlayer.Character
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	local dist = (hrp.Position - rootPart.Position).Magnitude
	if dist < HINT_DISTANCE then
		if not hasShownHint and not HasClaimedGroupReward() then
			hasShownHint = true
			task.spawn(function()
				local success, isInGroup = pcall(function()
					return players.LocalPlayer:IsInGroupAsync(GameConfig.SixcubeGroupId)
				end)

				if success and isInGroup then
					NetMsg.FireRequestClaimGroupReward(true)
					PlayClaimSuccessHint()
				else
					ClientMsg.FireShowGameTip(
						GameTexts.GroupRewardJoinHint.source,
						GameConfig.GameTipTweenType.FlyUp,
						GameTexts.GroupRewardJoinHint.key
					)
				end
			end)
		end
	else
		hasShownHint = false
	end
end

local function AnimateDisplayModel(_deltaTime: number)
	if not (displayModel and originModelCFrame) then
		return
	end

	local t = os.clock()
	local steadyRotateCF = CFrame.Angles(0, t * ROTATION_SPEED, 0)
	local hoverHeight = math.sin(t * HOVER_SPEED) * HOVER_AMPLITUDE

	displayModel:PivotTo(originModelCFrame * CFrame.new(0, hoverHeight, 0) * steadyRotateCF)
end

local function OnRenderStepped(deltaTime: number)
	AnimateDisplayModel(deltaTime)
	UpdateHint(deltaTime)
end

local function ConfigureDisplayModelPhysics(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
end

local function InitDisplayModel()
	if not groupRewardModel then
		return
	end

	local groupRewardConfig = GameConfig.GetGroupRewardBrainrotConfig()
	local brainrotData = GameConfig.BrainrotIdMap[groupRewardConfig.brainrotId]
	if brainrotData == nil then
		warn("[GroupRewardClientManager] Group reward brainrot data not found:", groupRewardConfig.brainrotId)
		return
	end

	local brainrotsFolder = replicatedStorage:WaitForChild("Models"):WaitForChild("Brainrots")
	local sourceTemplate = GameConfig.FindResourceTemplateByResourceName(brainrotsFolder, brainrotData.resourceName)
	if sourceTemplate == nil then
		warn("[GroupRewardClientManager] Source model not found for display:", brainrotData.resourceName)
		return
	end

	local existingModel = groupRewardModel:FindFirstChild(DISPLAY_MODEL_NAME) :: Model?
	if existingModel == nil then
		return
	end

	local oldPivot = existingModel:GetPivot()
	local newModel = GameConfig.CloneTemplateAsModel(sourceTemplate)
	newModel.Name = DISPLAY_MODEL_NAME
	newModel.Parent = groupRewardModel
	newModel:PivotTo(oldPivot)

	existingModel:Destroy()
	displayModel = newModel
	originModelCFrame = oldPivot

	GameConfig.ApplyBrainrotModelScale(
		displayModel,
		1,
		GameConfig.GetBrainrotTemplateBaseScale(sourceTemplate)
	)
	BrainrotVariantVisualTool.AttachVariantEffect(displayModel, groupRewardConfig.variantId)
	ConfigureDisplayModelPhysics(displayModel)
end

function GroupRewardClientManager.Init()
	groupRewardModel = workspace:FindFirstChild("GroupRewardModel") :: Model?
	if not groupRewardModel then
		return
	end

	displayModel = groupRewardModel:FindFirstChild(DISPLAY_MODEL_NAME) :: Model?
	rootPart = groupRewardModel:FindFirstChild("RootPart") :: Part?

	if rootPart then
		local guiAttachment = rootPart:FindFirstChild("GuiAttachment")
		if guiAttachment then
			billboardGui = guiAttachment:FindFirstChild("Gui") :: BillboardGui?
		end
	end

	if displayModel then
		originModelCFrame = displayModel:GetPivot()
	end

	InitDisplayModel()

	if billboardGui then
		BillboardManager.Track(billboardGui)
	end

	RefreshTipText()

	runService:BindToRenderStep(
		"GroupRewardClientManager.RenderStepped",
		Enum.RenderPriority.Camera.Value + 1,
		OnRenderStepped
	)

	ClientMsg.ConnectLocalPlayerInfoInit(function()
		RefreshTipText()
		CheckAndShowSuccessTip()
	end)

	ClientMsg.ConnectLocalPlayerClaimedGroupReward(function()
		RefreshTipText()
	end)
end

return GroupRewardClientManager
