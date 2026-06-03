--!strict
local ChestOpenAnimationManager = {}

local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")
local workspace = game:GetService("Workspace")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local coreClientScripts = coreScripts:WaitForChild("Client")

local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local NumberExtension = require(coreSharedScripts:WaitForChild("NumberExtension"))
local TranslationTool = require(coreClientScripts:WaitForChild("TranslationTool"))
local BillboardManager = require(clientScripts:WaitForChild("BillboardManager"))
local ModelBillboardOffsetTool = require(clientScripts:WaitForChild("ModelBillboardOffsetTool"))
local BrainrotVariantVisualTool = require(clientScripts:WaitForChild("BrainrotVariantVisualTool"))

local actualModels = replicatedStorage:WaitForChild("Models"):WaitForChild("Brainrots")
local modelsFolderForChests = replicatedStorage:WaitForChild("Models")
local factoryChestsFolder = modelsFolderForChests:FindFirstChild("LittleElfChests")
	or modelsFolderForChests:WaitForChild("LittleElfChests")
local littleElfChestsFolder = factoryChestsFolder
local actualChests = factoryChestsFolder
local uiFolder = replicatedStorage:WaitForChild("UI")
local brainrotInfoUIParams = uiFolder:WaitForChild("BrainrotInfoUI") :: BillboardGui
local BILLBOARD_TRACKED_ATTR = "BillboardTracked"

local LogPrefix = "[ChestOpenAnimationManager]"

local function EnsureBillboardTracked(gui: BillboardGui)
	if gui:GetAttribute(BILLBOARD_TRACKED_ATTR) ~= true then
		gui:SetAttribute(BILLBOARD_TRACKED_ATTR, true)
	end
	BillboardManager.Track(gui)
end

-- 开箱动画参数：随机轮播次数。
local RandomCount = 10
-- 开箱动画参数：模型缩小时的接近隐藏比例。
local TinyScale = 0.02
-- 跑道开箱参数：客户端等待服务端最终奖励的最长时间，超时使用本地兜底奖励。
local RunwayMaxOpenAnimationSec = 5
-- 宝箱摇晃参数：时长乘数，1 / 2 表示摇晃速度为原来的 2 倍。
local ChestShakeDurationMultiplier = 1 / 2
-- Brainrot 缩放参数：时长乘数，1 / 1.5 表示缩放速度为原来的 1.5 倍。
local BrainrotOpenScaleDurationMultiplier = 1 / 1.5
-- Brainrot 缩放参数：随机轮播奖励弹出的峰值比例。
local BrainrotRandomRevealScale = 2.5
-- Brainrot 缩放参数：最终奖励弹出的峰值比例。
local BrainrotFinalRevealScale = 3.1
-- Brainrot 缩放参数：最终奖励从峰值回落后的停留比例。
local BrainrotFinalSettleScale = 2.5
-- 跑道开箱参数：宝箱从玩家撞击点向前抛出的距离。
local ChestThrowForwardDistance = 1.0
-- 跑道开箱参数：锁定朝向时 Brainrot 面向镜头的修正角度。
local RunwayChestBrainrotLeftYawRad = math.rad(90)

local playingUidMap: { [string]: boolean } = {}

local function TweenProperty(target: Instance, tweenInfo: TweenInfo, props: { [string]: any })
	local tween = tweenService:Create(target, tweenInfo, props)
	tween:Play()
	tween.Completed:Wait()
end

local function TweenPropertyNoWait(target: Instance, tweenInfo: TweenInfo, props: { [string]: any })
	local tween = tweenService:Create(target, tweenInfo, props)
	tween:Play()
	return tween
end

local function TweenModelScale(model: Model, fromScale: number, toScale: number, duration: number, easingStyle: Enum.EasingStyle, easingDir: Enum.EasingDirection)
	local driver = Instance.new("NumberValue")
	driver.Value = fromScale
	local conn = driver:GetPropertyChangedSignal("Value"):Connect(function()
		if model.Parent then
			model:ScaleTo(driver.Value)
		end
	end)
	model:ScaleTo(fromScale)
	local tween = tweenService:Create(driver, TweenInfo.new(duration, easingStyle, easingDir), { Value = toScale })
	tween:Play()
	tween.Completed:Wait()
	conn:Disconnect()
	driver:Destroy()
	if model.Parent then
		model:ScaleTo(toScale)
	end
end

local function GetBrainrotOpenScaleDuration(duration: number): number
	return duration * BrainrotOpenScaleDurationMultiplier
end

local function GetChestShakeDuration(duration: number): number
	return duration * ChestShakeDurationMultiplier
end

local function ResolveBrainrotTemplateBaseScale(brainrotId: number): number
	local config = GameConfig.BrainrotIdMap[brainrotId]
	if not config then
		return 1
	end
	local template = GameConfig.FindResourceTemplateByResourceName(actualModels, config.resourceName)
	if not template then
		return 1
	end
	return GameConfig.GetBrainrotTemplateBaseScale(template)
end

local function GetBrainrotRevealAnimScale(level: number, animScale: number, templateBaseScale: number): number
	return templateBaseScale * GameConfig.GetBrainrotModelScale(level) * animScale
end

local function CreateOrUpdateInfoUI(
	parentInstance: Instance,
	adornee: BasePart,
	brainrotId: number,
	level: number,
	model: Model?,
	hideTimers: boolean?,
	variantId: number?
)

	local brainrotData = GameConfig.BrainrotIdMap[brainrotId]
	if not brainrotData then
		return
	end

	local qualityCfg = GameConfig.BrainrotQualityConfig[brainrotData.quality]
	local ui = parentInstance:FindFirstChild("BrainrotInfoUI") :: BillboardGui?

	if not ui then
		local clonedUi = brainrotInfoUIParams:Clone() :: BillboardGui
		clonedUi.Name = "BrainrotInfoUI"
		clonedUi.Parent = parentInstance
		EnsureBillboardTracked(clonedUi)
		ui = clonedUi
	end

	if not ui then
		return
	end
	ui.Adornee = adornee
	local offsetY = if model then ModelBillboardOffsetTool.GetVisualOffsetY(model, adornee, 1) else 2
	ui.StudsOffset = Vector3.new(0, offsetY, 0)

	local controller = ui:FindFirstChild("ControllerFrame")
	if not controller then
		return
	end

	local nameLabel = controller:FindFirstChild("NameText") :: TextLabel?
	local levelText = controller:FindFirstChild("LevelText") :: TextLabel?
	local abilityText = controller:FindFirstChild("AbilityText") :: TextLabel?
	local sellPriceText = controller:FindFirstChild("SellPriceText") :: TextLabel?

	if nameLabel then
		nameLabel.Text = brainrotData.name_t or ""
		if qualityCfg then
			nameLabel.TextColor3 = qualityCfg.textColor
		end
	end
	if levelText then
		levelText.Visible = true
		TranslationTool.CustomAutoLocalizeTextLabel(levelText, GameTexts.LevelWithNumber.source, GameTexts.LevelWithNumber.key, { tostring(level) })
		levelText.TextColor3 = GameConfig.GetBrainrotLevelTierTextColor(level)
	end
	if abilityText then
		abilityText.Visible = true
		local ability = GameConfig.GetBrainrotAbilityWithVariant(brainrotData.baseAbility, level, variantId)
		local abilityStr = NumberExtension.FormatBigNumberAA(ability)
		TranslationTool.CustomAutoLocalizeTextLabel(abilityText, GameTexts.YieldPerSecond.source, GameTexts.YieldPerSecond.key, { abilityStr })
	end
	BrainrotVariantVisualTool.ApplyVariantLabel(controller, variantId)
	if sellPriceText then
		sellPriceText.Visible = false
	end

	local shouldHide = hideTimers == true
	local timerTextLabel = controller:FindFirstChild("TimerText") :: TextLabel?
	local timerImgLabel = controller:FindFirstChild("TimerImg") :: ImageLabel?
	if timerTextLabel then
		timerTextLabel.Visible = not shouldHide
	end
	if timerImgLabel then
		timerImgLabel.Visible = not shouldHide
	end
end

local function CreateDisplayModel(tool: Tool, brainrotId: number): (Model?, BasePart?)
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return nil, nil
	end
	local config = GameConfig.BrainrotIdMap[brainrotId]
	if not config then
		return nil, nil
	end
	local template = GameConfig.FindResourceTemplateByResourceName(actualModels, config.resourceName)
	if not template then
		warn(
			LogPrefix,
			"Reward brainrot model not found:",
			config.resourceName,
			"candidates:",
			table.concat(GameConfig.GetResourceNameCandidates(config.resourceName), ", ")
		)
		return nil, nil
	end

	local oldModel = tool:FindFirstChild("OpenAnimDisplayModel")
	if oldModel then
		oldModel:Destroy()
	end

	local visualModel = GameConfig.CloneTemplateAsModel(template)
	visualModel.Name = "OpenAnimDisplayModel"
	local root = visualModel.PrimaryPart or visualModel:FindFirstChild("RootPart") or visualModel:FindFirstChildWhichIsA("BasePart")
	if not root or not root:IsA("BasePart") then
		visualModel:Destroy()
		return nil, nil
	end

	for _, part in ipairs(visualModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Anchored = false
			part.Massless = true
			part.CanQuery = false
			part.CanTouch = false
		end
	end

	visualModel:PivotTo(handle.CFrame)
	visualModel.Parent = tool

	local motor = Instance.new("Motor6D")
	motor.Name = "OpenAnimVisualMotor"
	motor.Part0 = handle
	motor.Part1 = root
	motor.C0 = CFrame.new(0, 1.2, 0)
	motor.Parent = handle

	return visualModel, root
end

local function PickRandomEntry(pool: { any }, lastId: number?): any?
	if #pool <= 0 then
		return nil
	end
	local randomEntry = pool[math.random(1, #pool)]
	if #pool > 1 and lastId then
		while randomEntry.itemId == lastId do
			randomEntry = pool[math.random(1, #pool)]
		end
	end
	return randomEntry
end

local function GetSmallestRewardBrainrotId(rewardPool: { any }): number?
	local smallestId: number? = nil
	for _, entry in ipairs(rewardPool) do
		local itemId = entry.itemId
		if typeof(itemId) == "number" and (smallestId == nil or itemId < (smallestId :: number)) then
			smallestId = itemId
		end
	end
	return smallestId
end

local function CreateAnchoredModelFromConfig(folder: Folder, resourceName: string, parentInst: Instance, modelName: string, targetCFrame: CFrame): (Model?, BasePart?)
	local template = GameConfig.FindResourceTemplateByResourceName(folder, resourceName)
	if not template then
		warn(
			LogPrefix,
			"Anchored model source not found:",
			resourceName,
			"candidates:",
			table.concat(GameConfig.GetResourceNameCandidates(resourceName), ", ")
		)
		return nil, nil
	end
	local model = GameConfig.CloneTemplateAsModel(template)
	model.Name = modelName
	local root = model.PrimaryPart or model:FindFirstChild("RootPart") or model:FindFirstChildWhichIsA("BasePart")
	if not root or not root:IsA("BasePart") then
		model:Destroy()
		return nil, nil
	end
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
		end
	end
	model:PivotTo(targetCFrame)
	model.Parent = parentInst
	return model, root
end

type ResolvedChestOpenContext = {
	chestConfig: any,
	rewardPool: { any },
	chestFolder: Folder,
}

local function ResolveChestConfigAndPool(chestConfigId: number): ResolvedChestOpenContext?
	local littleElfConfig = GameConfig.LittleElfChestIdMap[chestConfigId]
	if littleElfConfig ~= nil and littleElfChestsFolder ~= nil then
		local littleElfPool = GameConfig.LittleElfChestRewardPoolMap[chestConfigId]
		if littleElfPool ~= nil and #littleElfPool > 0 then
			return {
				chestConfig = littleElfConfig,
				rewardPool = littleElfPool,
				chestFolder = littleElfChestsFolder,
			}
		end
	end
	local factoryConfig = GameConfig.LittleElfChestIdMap[chestConfigId]
	if factoryConfig ~= nil then
		local factoryPool = GameConfig.ChestRewardPoolMap[chestConfigId]
		if factoryPool ~= nil and #factoryPool > 0 then
			return {
				chestConfig = factoryConfig,
				rewardPool = factoryPool,
				chestFolder = factoryChestsFolder,
			}
		end
	end
	return nil
end

type PlayInWorldOptions = {
	existingChestModel: Model?,
	lockFacing: boolean?,
	resolveFinalBrainrotId: (() -> number?)?,
	resolveFinalVariantId: (() -> number?)?,
	finalVariantId: number?,
	maxPlayTimeSec: number?,
}

local function PrepareExistingChestForOpenAnim(chestModel: Model, container: Instance, throwCFrame: CFrame): BasePart?
	chestModel.Name = "WorldChestModel"
	local root = chestModel.PrimaryPart or chestModel:FindFirstChild("RootPart") or chestModel:FindFirstChildWhichIsA("BasePart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	for _, part in ipairs(chestModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
		end
	end
	pcall(function()
		chestModel:ScaleTo(1)
	end)
	chestModel:PivotTo(throwCFrame)
	chestModel.Parent = container
	return root
end

local function PlayInWorld(
	uid: string,
	chestConfigId: number,
	chestLevel: number,
	finalBrainrotId: number,
	originCFrame: CFrame,
	options: PlayInWorldOptions?
): number?
	local resolved = ResolveChestConfigAndPool(chestConfigId)
	if not resolved then
		warn(LogPrefix, "PlayInWorld: no chest config/pool for id", chestConfigId)
		return nil
	end
	local chestConfig = resolved.chestConfig
	local rewardPool = resolved.rewardPool
	local chestModelsFolder = resolved.chestFolder

	local throwCFrame = originCFrame * CFrame.new(0, 0, -ChestThrowForwardDistance)
	local lockFacing = options ~= nil and options.lockFacing == true
	local existingChestModel = if options ~= nil then options.existingChestModel else nil
	local container = if existingChestModel ~= nil and existingChestModel.Parent ~= nil then existingChestModel.Parent else workspace
	local startedClock = os.clock()
	local maxPlayTimeSec = RunwayMaxOpenAnimationSec
	if options ~= nil and typeof(options.maxPlayTimeSec) == "number" then
		maxPlayTimeSec = options.maxPlayTimeSec :: number
	end
	if maxPlayTimeSec <= 0 then
		maxPlayTimeSec = RunwayMaxOpenAnimationSec
	end

	local chestModel: Model?
	local chestRoot: BasePart?
	if existingChestModel ~= nil and existingChestModel.Parent ~= nil then
		chestRoot = PrepareExistingChestForOpenAnim(existingChestModel, container, throwCFrame)
		chestModel = if chestRoot ~= nil then existingChestModel else nil
	end
	if chestModel == nil or chestRoot == nil then
		chestModel, chestRoot = CreateAnchoredModelFromConfig(chestModelsFolder, chestConfig.resourceName, container, "WorldChestModel", throwCFrame)
	end
	if not chestModel or not chestRoot then
		return nil
	end

	local yDriver = Instance.new("NumberValue")
	yDriver.Value = 0
	local yawDriver = Instance.new("NumberValue")
	yawDriver.Value = if lockFacing then 0 else math.rad(math.random(-120, 120))

	local function UpdateChestPivot()
		if chestModel and chestModel.Parent then
			chestModel:PivotTo(throwCFrame * CFrame.Angles(0, yawDriver.Value, 0) * CFrame.new(0, yDriver.Value, 0))
		end
	end

	local yConn = yDriver:GetPropertyChangedSignal("Value"):Connect(UpdateChestPivot)
	local yawConn = yawDriver:GetPropertyChangedSignal("Value"):Connect(UpdateChestPivot)
	UpdateChestPivot()

	if not lockFacing then
		TweenPropertyNoWait(yawDriver, TweenInfo.new(GetChestShakeDuration(0.2), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Value = yawDriver.Value + math.rad(math.random(-120, 120)),
		})
	end
	TweenProperty(yDriver, TweenInfo.new(GetChestShakeDuration(0.2), Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = -0.2 })

	TweenModelScale(chestModel, 1, 0.85, GetChestShakeDuration(0.08), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenModelScale(chestModel, 0.85, 1, GetChestShakeDuration(0.08), Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	local leftYaw = math.rad(math.random(25, 50))
	local rightYaw = -leftYaw
	local smallUp1 = 0.55
	local smallUp2 = 0.45

	TweenPropertyNoWait(yawDriver, TweenInfo.new(GetChestShakeDuration(0.16), Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = leftYaw })
	TweenProperty(yDriver, TweenInfo.new(GetChestShakeDuration(0.16), Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = smallUp1 })
	TweenPropertyNoWait(yawDriver, TweenInfo.new(GetChestShakeDuration(0.16), Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 0 })
	TweenProperty(yDriver, TweenInfo.new(GetChestShakeDuration(0.16), Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = -0.2 })

	TweenPropertyNoWait(yawDriver, TweenInfo.new(GetChestShakeDuration(0.12), Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = rightYaw })
	TweenProperty(yDriver, TweenInfo.new(GetChestShakeDuration(0.12), Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = smallUp2 })
	TweenPropertyNoWait(yawDriver, TweenInfo.new(GetChestShakeDuration(0.12), Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 0 })
	TweenProperty(yDriver, TweenInfo.new(GetChestShakeDuration(0.12), Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = -0.2 })

	local bigYaw = math.rad(math.random(120, 160))
	local bigUp1 = 1.0
	local bigUp2 = 0.85

	TweenPropertyNoWait(yawDriver, TweenInfo.new(GetChestShakeDuration(0.18), Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = bigYaw })
	TweenProperty(yDriver, TweenInfo.new(GetChestShakeDuration(0.18), Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = bigUp1 })
	TweenPropertyNoWait(yawDriver, TweenInfo.new(GetChestShakeDuration(0.18), Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 0 })
	TweenProperty(yDriver, TweenInfo.new(GetChestShakeDuration(0.18), Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = -0.2 })

	TweenPropertyNoWait(yawDriver, TweenInfo.new(GetChestShakeDuration(0.18), Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = -bigYaw })
	TweenProperty(yDriver, TweenInfo.new(GetChestShakeDuration(0.18), Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = bigUp2 })
	TweenPropertyNoWait(yawDriver, TweenInfo.new(GetChestShakeDuration(0.18), Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 0 })
	TweenProperty(yDriver, TweenInfo.new(GetChestShakeDuration(0.18), Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = -0.2 })

	TweenModelScale(chestModel, 1, TinyScale, GetChestShakeDuration(0.18), Enum.EasingStyle.Back, Enum.EasingDirection.In)

	yConn:Disconnect()
	yawConn:Disconnect()
	yDriver:Destroy()
	yawDriver:Destroy()

	local displayModel: Model? = nil
	local displayRoot: BasePart? = nil
	local lastId: number? = nil
	local function ShowOne(brainrotId: number, variantId: number, stayAsFinal: boolean)
		local brainrotData = GameConfig.BrainrotIdMap[brainrotId]
		if not brainrotData then
			return
		end
		if displayModel then
			displayModel:Destroy()
			displayModel = nil
			displayRoot = nil
		end
		displayModel, displayRoot = CreateAnchoredModelFromConfig(
			actualModels,
			brainrotData.resourceName,
			container,
			"WorldBrainrotModel",
			throwCFrame
				* CFrame.new(0, 1.2, 0)
				* (if lockFacing then CFrame.Angles(0, RunwayChestBrainrotLeftYawRad, 0) else CFrame.identity)
		)
		if not displayModel or not displayRoot then
			return
		end
		BrainrotVariantVisualTool.AttachVariantEffect(displayModel, variantId)
		local resolvedVariantId = if variantId > 0 then variantId else nil
		CreateOrUpdateInfoUI(displayModel, displayRoot, brainrotId, chestLevel, displayModel, true, resolvedVariantId)
		local templateBaseScale = ResolveBrainrotTemplateBaseScale(brainrotId)
		local revealScale = GetBrainrotRevealAnimScale(chestLevel, BrainrotRandomRevealScale, templateBaseScale)
		local finalRevealScale = GetBrainrotRevealAnimScale(chestLevel, BrainrotFinalRevealScale, templateBaseScale)
		local finalSettleScale = GetBrainrotRevealAnimScale(chestLevel, BrainrotFinalSettleScale, templateBaseScale)
		local tinyScale = GetBrainrotRevealAnimScale(chestLevel, TinyScale, templateBaseScale)
		TweenModelScale(
			displayModel,
			tinyScale,
			revealScale,
			GetBrainrotOpenScaleDuration(0.14),
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out
		)
		if stayAsFinal then
			TweenModelScale(
				displayModel,
				revealScale,
				finalRevealScale,
				GetBrainrotOpenScaleDuration(0.22),
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			)
			TweenModelScale(
				displayModel,
				finalRevealScale,
				finalSettleScale,
				GetBrainrotOpenScaleDuration(0.1),
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			)
			task.wait(0.08)
			TweenModelScale(
				displayModel,
				finalSettleScale,
				tinyScale,
				GetBrainrotOpenScaleDuration(0.18),
				Enum.EasingStyle.Back,
				Enum.EasingDirection.In
			)
			displayModel:Destroy()
			displayModel = nil
			displayRoot = nil
		else
			task.wait(0.05)
			TweenModelScale(
				displayModel,
				revealScale,
				tinyScale,
				GetBrainrotOpenScaleDuration(0.1),
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
		end
	end

	for _ = 1, RandomCount do
		local randomEntry = PickRandomEntry(rewardPool, lastId)
		if not randomEntry then
			break
		end
		local randomId = randomEntry.itemId
		lastId = randomId
		local randomVariantId = GameConfig.RollVariantIdFromEntry(randomEntry)
		ShowOne(randomId, randomVariantId, false)
	end

	local resolvedFinalBrainrotId = finalBrainrotId
	local resolvedFinalVariantId = if options ~= nil and options.finalVariantId then options.finalVariantId else 0
	local resolveFinalBrainrotId = if options ~= nil then options.resolveFinalBrainrotId else nil
	local resolveFinalVariantId = if options ~= nil then options.resolveFinalVariantId else nil
	if resolveFinalBrainrotId ~= nil then
		local deadlineClock = startedClock + maxPlayTimeSec
		while os.clock() < deadlineClock do
			local resolvedId = resolveFinalBrainrotId()
			if resolvedId ~= nil then
				resolvedFinalBrainrotId = resolvedId
				break
			end
			task.wait(0.05)
		end
		if resolvedFinalBrainrotId <= 0 then
			resolvedFinalBrainrotId = GetSmallestRewardBrainrotId(rewardPool) or 0
		end
	end
	if resolveFinalVariantId ~= nil then
		local deadlineClock = startedClock + maxPlayTimeSec
		while os.clock() < deadlineClock do
			local resolvedVariant = resolveFinalVariantId()
			if resolvedVariant ~= nil then
				resolvedFinalVariantId = resolvedVariant
				break
			end
			task.wait(0.05)
		end
	end
	if resolvedFinalBrainrotId > 0 then
		if resolvedFinalVariantId <= 0 then
			local finalEntry = GameConfig.FindLittleElfChestRewardEntry(chestConfigId, resolvedFinalBrainrotId)
			if finalEntry then
				resolvedFinalVariantId = GameConfig.RollVariantIdFromEntry(finalEntry)
			end
		end
		ShowOne(resolvedFinalBrainrotId, resolvedFinalVariantId, true)
	end
	if chestModel and chestModel.Parent then
		chestModel:Destroy()
	end
	return if resolvedFinalBrainrotId > 0 then resolvedFinalBrainrotId else nil
end

function ChestOpenAnimationManager.PlayInWorldAndWait(
	uid: string,
	chestConfigId: number,
	chestLevel: number,
	finalBrainrotId: number,
	originCFrame: CFrame,
	options: PlayInWorldOptions?
): number?
	if playingUidMap[uid] then
		return nil
	end
	playingUidMap[uid] = true
	local selectedBrainrotId: number? = nil
	local ok, err = pcall(function()
		selectedBrainrotId = PlayInWorld(uid, chestConfigId, chestLevel, finalBrainrotId, originCFrame, options)
	end)
	if not ok then
		warn(LogPrefix, "PlayInWorldAndWait failed:", err)
	end
	playingUidMap[uid] = nil
	return selectedBrainrotId
end

function ChestOpenAnimationManager.Play(tool: Tool?, uid: string, chestConfigId: number, chestLevel: number, finalBrainrotId: number, fallbackCFrame: CFrame?)
	if playingUidMap[uid] then
		return
	end
	playingUidMap[uid] = true

	local ok = pcall(function()
		if not tool or not tool.Parent then
			if fallbackCFrame then
				PlayInWorld(uid, chestConfigId, chestLevel, finalBrainrotId, fallbackCFrame)
			end
			return
		end

		local resolved = ResolveChestConfigAndPool(chestConfigId)
		if not resolved then
			return
		end
		local rewardPool = resolved.rewardPool

		local chestModel = tool:FindFirstChild("VisualModel")
		local handle = tool:FindFirstChild("Handle")
		local visualMotor = handle and handle:FindFirstChild("VisualMotor")
		if not chestModel or not chestModel:IsA("Model") or not visualMotor or not visualMotor:IsA("Motor6D") then
			return
		end

		TweenProperty(visualMotor, TweenInfo.new(GetChestShakeDuration(0.2), Enum.EasingStyle.Quad, Enum.EasingDirection.In), { C0 = CFrame.new(0, 0.2, 0) })
		TweenModelScale(chestModel, 1, 0.85, GetChestShakeDuration(0.08), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenModelScale(chestModel, 0.85, 1, GetChestShakeDuration(0.08), Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenProperty(visualMotor, TweenInfo.new(GetChestShakeDuration(0.16), Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { C0 = CFrame.new(0, 1.15, 0) })
		TweenProperty(visualMotor, TweenInfo.new(GetChestShakeDuration(0.16), Enum.EasingStyle.Quad, Enum.EasingDirection.In), { C0 = CFrame.new(0, 0.2, 0) })
		TweenProperty(visualMotor, TweenInfo.new(GetChestShakeDuration(0.12), Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { C0 = CFrame.new(0, 0.75, 0) })
		TweenProperty(visualMotor, TweenInfo.new(GetChestShakeDuration(0.12), Enum.EasingStyle.Quad, Enum.EasingDirection.In), { C0 = CFrame.new(0, 0.2, 0) })

		TweenModelScale(chestModel, 1, TinyScale, GetChestShakeDuration(0.18), Enum.EasingStyle.Back, Enum.EasingDirection.In)

		local lastId: number? = nil
		for _ = 1, RandomCount do
			if not tool.Parent then
				return
			end
			local randomEntry = PickRandomEntry(rewardPool, lastId)
			if not randomEntry then
				return
			end
			local randomId = randomEntry.itemId
			lastId = randomId
			local randomVariantId = GameConfig.RollVariantIdFromEntry(randomEntry)

			local showModel, root = CreateDisplayModel(tool, randomId)
			if not showModel or not root then
				continue
			end

			BrainrotVariantVisualTool.AttachVariantEffect(showModel, randomVariantId)
			local resolvedRandomVariantId = if randomVariantId > 0 then randomVariantId else nil
			CreateOrUpdateInfoUI(tool, root, randomId, chestLevel, showModel, true, resolvedRandomVariantId)
			local templateBaseScale = ResolveBrainrotTemplateBaseScale(randomId)
			local revealScale = GetBrainrotRevealAnimScale(chestLevel, BrainrotRandomRevealScale, templateBaseScale)
			local tinyScale = GetBrainrotRevealAnimScale(chestLevel, TinyScale, templateBaseScale)
			TweenModelScale(
				showModel,
				tinyScale,
				revealScale,
				GetBrainrotOpenScaleDuration(0.14),
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			)
			task.wait(0.05)
			TweenModelScale(
				showModel,
				revealScale,
				tinyScale,
				GetBrainrotOpenScaleDuration(0.1),
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			showModel:Destroy()
		end

		local finalModel, finalRoot = CreateDisplayModel(tool, finalBrainrotId)
		if finalModel and finalRoot then
			local finalEntry = GameConfig.FindLittleElfChestRewardEntry(chestConfigId, finalBrainrotId)
			local finalVariantId = if finalEntry then GameConfig.RollVariantIdFromEntry(finalEntry) else 0
			BrainrotVariantVisualTool.AttachVariantEffect(finalModel, finalVariantId)
			local resolvedFinalVariantId = if finalVariantId > 0 then finalVariantId else nil
			CreateOrUpdateInfoUI(tool, finalRoot, finalBrainrotId, chestLevel, finalModel, true, resolvedFinalVariantId)
			local templateBaseScale = ResolveBrainrotTemplateBaseScale(finalBrainrotId)
			local tinyScale = GetBrainrotRevealAnimScale(chestLevel, TinyScale, templateBaseScale)
			local finalRevealScale = GetBrainrotRevealAnimScale(chestLevel, BrainrotFinalRevealScale, templateBaseScale)
			local finalSettleScale = GetBrainrotRevealAnimScale(chestLevel, BrainrotFinalSettleScale, templateBaseScale)
			TweenModelScale(
				finalModel,
				tinyScale,
				finalRevealScale,
				GetBrainrotOpenScaleDuration(0.22),
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			)
			TweenModelScale(
				finalModel,
				finalRevealScale,
				finalSettleScale,
				GetBrainrotOpenScaleDuration(0.1),
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			)
		end
	end)

	if not ok then
		warn(LogPrefix, "Play failed")
	end

	playingUidMap[uid] = nil
end

return ChestOpenAnimationManager
