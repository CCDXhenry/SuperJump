--!strict
local BrainrotClientManager = {}

local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

local localPlayer = players.LocalPlayer
local holdAnimInstance = Instance.new("Animation")
holdAnimInstance.AnimationId = "rbxassetid://93311785688859" -- 手动替换为双手托举的动作ID
local holdAnimTrack: AnimationTrack? = nil

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local coreClientScripts = coreScripts:WaitForChild("Client")

local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local TranslationTool = require(coreClientScripts:WaitForChild("TranslationTool"))
local BillboardManager = require(scripts:WaitForChild("Client"):WaitForChild("BillboardManager"))
local ModelBillboardOffsetTool = require(scripts:WaitForChild("Client"):WaitForChild("ModelBillboardOffsetTool"))
local NumberExtension = require(coreSharedScripts:WaitForChild("NumberExtension"))
local ChestOpenAnimationManager = require(scripts:WaitForChild("Client"):WaitForChild("ChestOpenAnimationManager"))
local BrainrotVariantVisualTool = require(scripts:WaitForChild("Client"):WaitForChild("BrainrotVariantVisualTool"))
local BrainrotQualityUILabel = require(scripts:WaitForChild("Client"):WaitForChild("BrainrotQualityUILabel"))

local actualModels = replicatedStorage:WaitForChild("Models"):WaitForChild("Brainrots")
local modelsFolderForChests = replicatedStorage:WaitForChild("Models")
local actualChests = modelsFolderForChests:FindFirstChild("LittleElfChests")
	or modelsFolderForChests:WaitForChild("LittleElfChests")
local uIFolder = replicatedStorage:WaitForChild("UI")
local brainrotInfoUIParams = uIFolder:WaitForChild("BrainrotInfoUI") :: BillboardGui
local chestInfoUIParams = (uIFolder:FindFirstChild("ChestInfoUI") or uIFolder:WaitForChild("LittleElfChestInfoUI")) :: BillboardGui
local BILLBOARD_TRACKED_ATTR = "BillboardTracked"
local COUNTDOWN_SECONDS_PER_MINUTE = 60
local characterDescendantConnectionMap: { [Player]: RBXScriptConnection } = {}
local characterAddedConnectionMap: { [Player]: RBXScriptConnection } = {}

local function EnsureBillboardTracked(gui: BillboardGui)
	if gui:GetAttribute(BILLBOARD_TRACKED_ATTR) ~= true then
		gui:SetAttribute(BILLBOARD_TRACKED_ATTR, true)
	end
	BillboardManager.Track(gui)
end

local function GetBrainrotCountdownTextData(remainingSeconds: number): (string, string, { string })
	if remainingSeconds < COUNTDOWN_SECONDS_PER_MINUTE then
		return GameTexts.BrainrotCountdownSecondsOnly.source, GameTexts.BrainrotCountdownSecondsOnly.key, { tostring(remainingSeconds) }
	end

	local minutes = math.floor(remainingSeconds / COUNTDOWN_SECONDS_PER_MINUTE)
	local seconds = remainingSeconds % COUNTDOWN_SECONDS_PER_MINUTE
	return GameTexts.BrainrotCountdownMinutesSeconds.source, GameTexts.BrainrotCountdownMinutesSeconds.key, { tostring(minutes), tostring(seconds) }
end

local AttachInfoUIToModel -- 向前声明
local pendingOpenChestToolMap: { [string]: Tool } = {}
local pendingOpenChestCFrameMap: { [string]: CFrame } = {}
local pendingOpenChestResultMap: { [string]: { brainrotId: number, variantId: number } } = {}

local function ResolveBrainrotDisplayQuality(targetParent: Instance, configId: number, passedQuality: number): number
	local attrQuality = tonumber(targetParent:GetAttribute("Quality"))
	if attrQuality then
		return attrQuality
	end
	if passedQuality > 0 then
		return passedQuality
	end
	local data = GameConfig.BrainrotIdMap[configId]
	return if data then data.quality else 1
end

local function ResolveTargetVariantId(targetPart: BasePart, overrideVariantId: number?): number
	if overrideVariantId ~= nil and overrideVariantId > 0 then
		return overrideVariantId
	end
	return tonumber(targetPart:GetAttribute("VariantId")) or 0
end

local function SyncBrainrotVisualScale(targetPart: BasePart, visualModel: Model)
	local itemType = targetPart:GetAttribute("ItemType") :: number? or GameConfig.ItemType.Brainrot
	if itemType ~= GameConfig.ItemType.Brainrot then
		return
	end
	local level = (targetPart:GetAttribute("Level") :: number) or 1
	GameConfig.ApplyBrainrotModelScale(visualModel, level)
end

local function RefreshVariantUiOnTarget(targetPart: BasePart, overrideVariantId: number?)
	local variantId = ResolveTargetVariantId(targetPart, overrideVariantId)
	local existingVisual = targetPart:FindFirstChild("VisualModel")
	if existingVisual and existingVisual:IsA("Model") then
		local resolvedVariantId = variantId or 0
		SyncBrainrotVisualScale(targetPart, existingVisual)
		BrainrotVariantVisualTool.AttachVariantEffect(existingVisual, resolvedVariantId)
		BrainrotVariantVisualTool.ApplyVisualCarryWeld(targetPart, existingVisual, resolvedVariantId)
	end
	local infoUi = targetPart:FindFirstChild("BrainrotInfoUI")
	if infoUi then
		local controller = infoUi:FindFirstChild("Controller") or infoUi:FindFirstChild("ControllerFrame")
		if controller then
			BrainrotVariantVisualTool.ApplyVariantLabel(controller, variantId)
		end
	end
end

local VariantEffectAttrTrackedName = "VariantEffectAttrTracked"

local function EnsureVariantEffectAttributeTracking(targetPart: BasePart)
	if targetPart:GetAttribute(VariantEffectAttrTrackedName) == true then
		return
	end
	targetPart:SetAttribute(VariantEffectAttrTrackedName, true)
	targetPart:GetAttributeChangedSignal("VariantId"):Connect(function()
		RefreshVariantUiOnTarget(targetPart)
	end)
end

local VisualModelChildTrackedAttr = "VisualModelChildTracked"

local function EnsureVisualModelChildTracking(targetPart: BasePart)
	if targetPart:GetAttribute(VisualModelChildTrackedAttr) == true then
		return
	end
	targetPart:SetAttribute(VisualModelChildTrackedAttr, true)
	targetPart.ChildAdded:Connect(function(child)
		if child.Name == "VisualModel" and child:IsA("Model") then
			RefreshVariantUiOnTarget(targetPart)
		end
	end)
	if targetPart:GetAttribute("BrainrotLevelScaleTracked") ~= true then
		targetPart:SetAttribute("BrainrotLevelScaleTracked", true)
		targetPart:GetAttributeChangedSignal("Level"):Connect(function()
			local visual = targetPart:FindFirstChild("VisualModel")
			if visual and visual:IsA("Model") then
				SyncBrainrotVisualScale(targetPart, visual)
			end
		end)
	end
end

local function SetupVisualBrainrot(targetPart: BasePart, overrideVariantId: number?)
	EnsureVariantEffectAttributeTracking(targetPart)
	EnsureVisualModelChildTracking(targetPart)

	local existingVisual = targetPart:FindFirstChild("VisualModel")
	if existingVisual and existingVisual:IsA("Model") then
		RefreshVariantUiOnTarget(targetPart, overrideVariantId)
		local existingConfigId = targetPart:GetAttribute("ConfigId") :: number?
		if existingConfigId then
			local existingLevel = (targetPart:GetAttribute("Level") :: number) or 1
			local existingItemType = targetPart:GetAttribute("ItemType") :: number? or GameConfig.ItemType.Brainrot
			local existingData = if existingItemType == GameConfig.ItemType.LittleElfChest
				then GameConfig.LittleElfChestIdMap[existingConfigId]
				else GameConfig.BrainrotIdMap[existingConfigId]
			if existingData then
				AttachInfoUIToModel(
					targetPart,
					targetPart :: BasePart,
					existingConfigId,
					existingLevel,
					ResolveBrainrotDisplayQuality(targetPart, existingConfigId, existingData.quality or 1),
					existingVisual
				)
			end
		end
		return
	end

	local configId = targetPart:GetAttribute("ConfigId") :: number?
	local itemType = targetPart:GetAttribute("ItemType") :: number? or GameConfig.ItemType.Brainrot
	if not configId then
		return
	end

	local data: any
	local sourceFolder: Folder?
	if itemType == GameConfig.ItemType.LittleElfChest then
		data = GameConfig.LittleElfChestIdMap[configId]
		sourceFolder = actualChests
	else
		data = GameConfig.BrainrotIdMap[configId]
		sourceFolder = actualModels
	end

	if not data or not sourceFolder then
		return
	end

	local template = GameConfig.FindResourceTemplateByResourceName(sourceFolder, data.resourceName)
	if not template then
		warn(
			"[BrainrotClientManager] Visual source model not found:",
			data.resourceName,
			"candidates:",
			table.concat(GameConfig.GetResourceNameCandidates(data.resourceName), ", ")
		)
		return
	end

	local newVisual = GameConfig.CloneTemplateAsModel(template)
	newVisual.Name = "VisualModel"
	newVisual:SetAttribute("ConfigId", configId)
	newVisual:SetAttribute("ItemType", itemType)

	local targetCFrame = targetPart.CFrame
	newVisual:PivotTo(targetCFrame)

	for _, part in ipairs(newVisual:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			part.CanTouch = false
			part.CanQuery = false
		elseif part:IsA("WeldConstraint") then
			local weldConstraintAny = part :: any
			local isInvalid = weldConstraintAny.Part0 == nil or weldConstraintAny.Part1 == nil
			local isAuto = part.Name == "AutoWeldConstraint"
			if isInvalid or isAuto then
				part:Destroy()
			end
		elseif part:IsA("Weld") then
			local weldAny = part :: any
			local isInvalid = weldAny.Part0 == nil or weldAny.Part1 == nil
			local isAuto = part.Name == "AutoWeld" or part.Name == "AutoWeld_ComponentBridge" or part.Name == "AutoWeld_RootBridge"
			if isInvalid or isAuto then
				part:Destroy()
			end
		end
	end

	local level = (targetPart:GetAttribute("Level") :: number) or 1
	GameConfig.ApplyBrainrotModelScale(
		newVisual,
		level,
		GameConfig.GetBrainrotTemplateBaseScale(template)
	)
	newVisual.Parent = targetPart

	local variantId = ResolveTargetVariantId(targetPart, overrideVariantId)
	BrainrotVariantVisualTool.AttachVariantEffect(newVisual, variantId)
	BrainrotVariantVisualTool.ApplyVisualCarryWeld(targetPart, newVisual, variantId)
	AttachInfoUIToModel(
		targetPart,
		targetPart :: BasePart,
		configId,
		level,
		ResolveBrainrotDisplayQuality(targetPart, configId, data.quality or 1),
		newVisual
	)
end

-- Attach UI
function AttachInfoUIToModel(targetParent: Instance, adornee: BasePart, configId: number, level: number, quality: number, visualModel: Model?)
	local itemType = targetParent:GetAttribute("ItemType") :: number? or GameConfig.ItemType.Brainrot
	quality = ResolveBrainrotDisplayQuality(targetParent, configId, quality)
	local data: any
	if itemType == GameConfig.ItemType.LittleElfChest then
		data = GameConfig.LittleElfChestIdMap[configId]
	else
		data = GameConfig.BrainrotIdMap[configId]
	end

	if not data then
		return
	end

	local uiName = if itemType == GameConfig.ItemType.LittleElfChest then "ChestInfoUI" else "BrainrotInfoUI"
	local newBrainrotUI = (adornee:FindFirstChild(uiName) or targetParent:FindFirstChild(uiName)) :: BillboardGui?
	if not newBrainrotUI then
		newBrainrotUI = if itemType == GameConfig.ItemType.LittleElfChest then chestInfoUIParams:Clone() else brainrotInfoUIParams:Clone()
		newBrainrotUI.Name = uiName
		newBrainrotUI.Parent = adornee
	end
	newBrainrotUI.Adornee = adornee

	local controller = newBrainrotUI:FindFirstChild("Controller") or newBrainrotUI:FindFirstChild("ControllerFrame")
	if controller then
		-- 非工作台槽位上的宝箱（工具/岛屿/携带等）不显示 EXP 条；槽内展示由 ChestWorkbenchClientManager 负责
		if itemType == GameConfig.ItemType.LittleElfChest then
			local expImage = controller:FindFirstChild("ExpImage")
			if expImage and expImage:IsA("GuiObject") then
				expImage.Visible = false
			end
		end

		local nameLabel = controller:FindFirstChild("NameLabel") :: TextLabel?
		local qualityLabel = controller:FindFirstChild("QualityLabel") :: TextLabel?
		local levelText = controller:FindFirstChild("LvLabel") :: TextLabel?
		local abilityText = controller:FindFirstChild("AbilityText") :: TextLabel?
		local sellPriceText = controller:FindFirstChild("SellPriceText") :: TextLabel?
			local timerTextLabel = controller:FindFirstChild("TimerText") :: TextLabel?
			local timerImgLabel = controller:FindFirstChild("TimerImg") :: ImageLabel?

		if nameLabel then
			nameLabel.Text = data.name_t or ""
			-- NameLabel 颜色固定为白色，不随品质变化
			nameLabel.TextColor3 = Color3.new(1, 1, 1)
		end
		if qualityLabel then
			BrainrotQualityUILabel.Apply(qualityLabel, quality)
		end
		if levelText then
			levelText.Visible = true
			TranslationTool.CustomAutoLocalizeTextLabel(levelText, GameTexts.LevelWithNumber.source, GameTexts.LevelWithNumber.key, { tostring(level) })
			levelText.TextColor3 = GameConfig.GetBrainrotLevelTierTextColor(level)
		end
		if abilityText then
			abilityText.Visible = itemType == GameConfig.ItemType.Brainrot
			local variantId = tonumber(targetParent:GetAttribute("VariantId"))
			local ability = if itemType == GameConfig.ItemType.Brainrot
				then GameConfig.GetBrainrotAbilityWithVariant(data.baseAbility, level, variantId)
				else 0
			local abilityStr = NumberExtension.FormatBigNumberAA(ability)
			TranslationTool.CustomAutoLocalizeTextLabel(abilityText, GameTexts.YieldPerSecond.source, GameTexts.YieldPerSecond.key, { abilityStr })
		end
		if itemType == GameConfig.ItemType.Brainrot then
			local variantIdForLabel = tonumber(targetParent:GetAttribute("VariantId"))
			BrainrotVariantVisualTool.ApplyVariantLabel(controller, variantIdForLabel)
		end
		if sellPriceText then
			sellPriceText.Visible = false
		end

			-- Brainrot 独立倒计时显示（每个 brainrot 自己的 UI 都有一份）
			if timerTextLabel and timerImgLabel then
				local function updateTimer()
					local isBrainrot = itemType == GameConfig.ItemType.Brainrot
					if not isBrainrot then
						timerTextLabel.Visible = false
						timerImgLabel.Visible = false
						return
					end

					local remaining = tonumber(adornee:GetAttribute("BrainrotTimerRemainingSeconds")) or 0
					local isIslandBrainrot = targetParent:IsA("BasePart") and targetParent.Name == "IslandBrainrot"
					local visible = isIslandBrainrot and remaining > 0
					timerTextLabel.Visible = visible
					timerImgLabel.Visible = visible
					if visible then
						local source, key, args = GetBrainrotCountdownTextData(remaining)
						TranslationTool.CustomAutoLocalizeTextLabel(timerTextLabel, source, key, args)
					end
				end

				updateTimer()
				adornee:GetAttributeChangedSignal("BrainrotTimerRemainingSeconds"):Connect(function()
					updateTimer()
				end)
			end
	end

	local offsetY = if visualModel then ModelBillboardOffsetTool.GetVisualOffsetY(visualModel, adornee) else 2
	if itemType == GameConfig.ItemType.LittleElfChest and targetParent:IsA("Tool") then
		local extraY = GameConfig.ChestCarryingChestInfoUIBillboardOffsetY
		if typeof(extraY) == "number" then
			offsetY = offsetY + extraY
		end
	end
	newBrainrotUI.StudsOffset = Vector3.new(0, offsetY, 0)
	if newBrainrotUI.Parent ~= adornee and newBrainrotUI.Parent ~= targetParent then
		newBrainrotUI.Parent = adornee
	end
	EnsureBillboardTracked(newBrainrotUI)
end

local function ProcessDescendantAdded(descendant: Instance)
	if descendant:IsA("BasePart") and (descendant.Name == "IslandBrainrot" or descendant.Name == "IslandChest" or descendant.Name == "CarryingBrainrot") then
		SetupVisualBrainrot(descendant :: any)
	elseif descendant:IsA("Tool") and descendant:GetAttribute("BrainrotUID") then
		local visualModel = descendant:WaitForChild("VisualModel", 3) :: Model?
		if visualModel then
			local root = visualModel.PrimaryPart or visualModel:FindFirstChildWhichIsA("BasePart")
			if root then
				local configId = descendant:GetAttribute("ConfigId") :: number
				local level = (descendant:GetAttribute("Level") :: number) or 1
				local quality = (descendant:GetAttribute("Quality") :: number) or 1
				local variantId = tonumber(descendant:GetAttribute("VariantId")) or 0
				BrainrotVariantVisualTool.AttachVariantEffect(visualModel, variantId)
				if descendant:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
					GameConfig.ApplyBrainrotModelScale(visualModel, level)
				end
				AttachInfoUIToModel(
					descendant,
					visualModel.PrimaryPart or visualModel:FindFirstChildWhichIsA("BasePart") or (visualModel:GetChildren()[1] :: any),
					configId,
					level,
					quality,
					visualModel
				)
			end
		end
	end
end

local function DisconnectPlayerCharacterTracking(player: Player)
	local descendantConnection = characterDescendantConnectionMap[player]
	if descendantConnection ~= nil then
		descendantConnection:Disconnect()
		characterDescendantConnectionMap[player] = nil
	end
end

local function TrackPlayerCharacter(player: Player, character: Model)
	DisconnectPlayerCharacterTracking(player)
	for _, desc in ipairs(character:GetDescendants()) do
		ProcessDescendantAdded(desc)
	end
	characterDescendantConnectionMap[player] = character.DescendantAdded:Connect(ProcessDescendantAdded)
end

local function TrackPlayer(player: Player)
	if characterAddedConnectionMap[player] ~= nil then
		return
	end
	if player.Character then
		TrackPlayerCharacter(player, player.Character)
	end
	characterAddedConnectionMap[player] = player.CharacterAdded:Connect(function(character: Model)
		TrackPlayerCharacter(player, character)
	end)
end

local function UntrackPlayer(player: Player)
	DisconnectPlayerCharacterTracking(player)
	local characterAddedConnection = characterAddedConnectionMap[player]
	if characterAddedConnection ~= nil then
		characterAddedConnection:Disconnect()
		characterAddedConnectionMap[player] = nil
	end
end

local function OnLocalToolEquipped(tool: Tool, character: Model)
	local visualModel = tool:FindFirstChild("VisualModel") :: Model?
	if visualModel and tool:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
		local variantId = tonumber(tool:GetAttribute("VariantId")) or 0
		BrainrotVariantVisualTool.AttachVariantEffect(visualModel, variantId)
	end

	-- Motor6D Tween 视觉位置
	local handle = tool:FindFirstChild("Handle")
	if handle then
		local visualMotor = handle:FindFirstChild("VisualMotor") :: Motor6D
		if visualMotor then
			local targetC0 = CFrame.new()
			local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			tweenService:Create(visualMotor, tweenInfo, { C0 = targetC0 }):Play()
		end
	end
end

local function OnLocalToolUnequipped(tool: Tool)
	-- holdAnimInstance is driven by island pickup state (CarryingBrainrot),
	-- not by tool equip/unequip.
end

local isHoldAnimPlaying = false

local function ResetHoldAnimTrack()
	if holdAnimTrack then
		holdAnimTrack:Stop()
	end
	holdAnimTrack = nil
	isHoldAnimPlaying = false
end

local function GetLocalAnimator(character: Model): Animator?
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator") :: Animator?
	return animator
end

local function PlayHoldAnim(character: Model)
	if isHoldAnimPlaying then
		return
	end

	local animator = GetLocalAnimator(character)
	if not animator then
		return
	end

	if not holdAnimTrack then
		holdAnimTrack = animator:LoadAnimation(holdAnimInstance)
		if holdAnimTrack then
			holdAnimTrack.Priority = Enum.AnimationPriority.Action
		end
	end

	if holdAnimTrack then
		holdAnimTrack:Play()
		isHoldAnimPlaying = true
	end
end

local function StopHoldAnim()
	if not isHoldAnimPlaying then
		return
	end

	if holdAnimTrack then
		holdAnimTrack:Stop()
	end
	isHoldAnimPlaying = false
end

local function SetupLocalPlayerCarryingBrainrotTracking(character: Model)
	-- If player is already carrying when we start tracking
	do
		local carrying = character:FindFirstChild("CarryingBrainrot")
		if carrying and carrying:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
			if carrying:IsA("BasePart") then
				SetupVisualBrainrot(carrying)
			end
			PlayHoldAnim(character)
		end
	end

	character.ChildAdded:Connect(function(child)
		if child.Name == "CarryingBrainrot" and child:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
			if child:IsA("BasePart") then
				SetupVisualBrainrot(child)
			end
			PlayHoldAnim(character)
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child.Name == "CarryingBrainrot" and child:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
			StopHoldAnim()
		end
	end)
end

-- 与 JumpRunway BuildLittleElfChestOpenCFrame 一致：保留模板默认朝向，避免手持旋转导致 brainrot 朝向/大小异常
local function BuildToolChestOpenCFrame(chestConfigId: number, worldPos: Vector3): CFrame?
	local chestConfig = GameConfig.LittleElfChestIdMap[chestConfigId]
	if chestConfig == nil then
		return nil
	end
	local template = GameConfig.FindResourceTemplateByResourceName(actualChests, chestConfig.resourceName)
	if template == nil then
		return nil
	end
	local tempModel = GameConfig.CloneTemplateAsModel(template)
	local templatePivot = tempModel:GetPivot()
	tempModel:Destroy()
	return CFrame.new(worldPos) * (templatePivot - templatePivot.Position)
end

local function ResolveToolChestOpenCFrame(tool: Tool, character: Model, chestConfigId: number): CFrame?
	local visualModel = tool:FindFirstChild("VisualModel")
	local worldPos: Vector3? = nil
	if visualModel and visualModel:IsA("Model") then
		worldPos = visualModel:GetPivot().Position
	else
		local handle = tool:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			worldPos = handle.Position
		end
	end
	if worldPos == nil then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			worldPos = (hrp.CFrame * CFrame.new(0, 0, -4)).Position
		end
	end
	if worldPos == nil then
		return nil
	end
	return BuildToolChestOpenCFrame(chestConfigId, worldPos) or CFrame.new(worldPos)
end

local function SetupLocalPlayerToolTracking(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("BrainrotUID") then
			OnLocalToolEquipped(child :: Tool, character)

			-- 如果是宝箱，监听点击
			if child:GetAttribute("ItemType") == GameConfig.ItemType.LittleElfChest then
				local uid = child:GetAttribute("BrainrotUID") :: string
				pendingOpenChestToolMap[uid] = child :: Tool
				local activatedConn: RBXScriptConnection? = nil
				activatedConn = (child :: Tool).Activated:Connect(function()
					pendingOpenChestToolMap[uid] = child :: Tool
					pendingOpenChestResultMap[uid] = nil
					local chestConfigId = (child:GetAttribute("ConfigId") :: number?) or 0
					local openCFrame = ResolveToolChestOpenCFrame(child :: Tool, character, chestConfigId)
					if openCFrame then
						pendingOpenChestCFrameMap[uid] = openCFrame
					end
					local chestOpenAnimLevel = (child:GetAttribute("Level") :: number?) or 1
					if not openCFrame then
						warn("[BrainrotClientManager] Open chest failed: no fallback cframe, uid:", uid)
						return
					end
					if activatedConn then
						activatedConn:Disconnect()
						activatedConn = nil
					end
					task.spawn(function()
						ChestOpenAnimationManager.PlayInWorldAndWait(
							uid,
							chestConfigId,
							chestOpenAnimLevel,
							0,
							openCFrame,
							{
								lockFacing = true,
								faceBrainrotToCamera = true,
								maxPlayTimeSec = 15,
								resolveFinalBrainrotId = function()
									local result = pendingOpenChestResultMap[uid]
									return if result then result.brainrotId else nil
								end,
								resolveFinalVariantId = function()
									local result = pendingOpenChestResultMap[uid]
									return if result then result.variantId else nil
								end,
							}
						)
						if pendingOpenChestResultMap[uid] then
							NetMsg.FireRequestOpenChestGrant(uid)
						end
						pendingOpenChestToolMap[uid] = nil
						pendingOpenChestCFrameMap[uid] = nil
						pendingOpenChestResultMap[uid] = nil
					end)
					NetMsg.FireRequestOpenChest(uid)
				end)
			end
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("BrainrotUID") then
			OnLocalToolUnequipped(child :: Tool)
		end
	end)
end

local function OnNotifyChestOpenResult(uid: string, _chestConfigId: number, _chestLevel: number, finalBrainrotId: number, finalVariantId: number?)
	pendingOpenChestResultMap[uid] = {
		brainrotId = finalBrainrotId,
		variantId = finalVariantId or 0,
	}
end

function BrainrotClientManager.Init()
	for _, player in ipairs(players:GetPlayers()) do
		TrackPlayer(player)
	end
	players.PlayerAdded:Connect(TrackPlayer)
	players.PlayerRemoving:Connect(UntrackPlayer)

	-- Local Player Tool Tracking
	if localPlayer.Character then
		ResetHoldAnimTrack()
		SetupLocalPlayerToolTracking(localPlayer.Character)
		SetupLocalPlayerCarryingBrainrotTracking(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(function(char)
		ResetHoldAnimTrack()
		SetupLocalPlayerToolTracking(char)
		SetupLocalPlayerCarryingBrainrotTracking(char)
	end)

	NetMsg.ConnectNotifyChestOpenResult(OnNotifyChestOpenResult)
end

function BrainrotClientManager.SetupCarryingBrainrotVisual(carryPart: BasePart, variantId: number?)
	local resolvedVariantId = if variantId ~= nil and variantId > 0 then variantId else (tonumber(carryPart:GetAttribute("VariantId")) or 0)
	if resolvedVariantId > 0 then
		carryPart:SetAttribute("VariantId", resolvedVariantId)
	end
	SetupVisualBrainrot(carryPart, if resolvedVariantId > 0 then resolvedVariantId else nil)
	local visualModel = carryPart:FindFirstChild("VisualModel")
	if visualModel and visualModel:IsA("Model") and resolvedVariantId > 0 then
		BrainrotVariantVisualTool.AttachVariantEffect(visualModel, resolvedVariantId)
	end
end

return BrainrotClientManager
