--!strict
local BrainrotVariantVisualTool = {}

local replicatedStorage = game:GetService("ReplicatedStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))

local modelsFolder = replicatedStorage:WaitForChild("Models")
local variantEffectFolder = modelsFolder:FindFirstChild("BrainrotVariantEffect")
	or modelsFolder:WaitForChild("BrainrotVariantEffect")

local VariantEffectInstanceName = "VariantEffect"
local VariantEffectWeldName = "VariantEffectWeld"
local IslandVisualWeldName = "IslandVisualWeld"
local VariantColorValueName = "VariantColor"
local VisualModelVfxInstanceName = "VfxInstance"

local variantLabelColorCache: { [number]: Color3 } = {}

local function FindVariantColorValue(variantTemplate: Instance): Color3Value?
	if variantTemplate:IsA("BasePart") then
		local variantColor = variantTemplate:FindFirstChild(VariantColorValueName)
		if variantColor and variantColor:IsA("Color3Value") then
			return variantColor
		end
	end
	for _, descendant in ipairs(variantTemplate:GetDescendants()) do
		if descendant.Name == VariantColorValueName and descendant:IsA("Color3Value") then
			return descendant
		end
	end
	return nil
end

local function GetVisualModelVfxInstance(visualModel: Model): BasePart?
	local vfxInstance = visualModel:FindFirstChild(VisualModelVfxInstanceName, true)
	if vfxInstance and vfxInstance:IsA("BasePart") then
		return vfxInstance
	end
	return nil
end

local function GetVariantAttachPart(visualModel: Model): BasePart?
	local fakeRootPart = visualModel:FindFirstChild("FakeRootPart")
	if fakeRootPart and fakeRootPart:IsA("BasePart") then
		return fakeRootPart
	end
	local rootPart = visualModel:FindFirstChild("RootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end
	local primaryPart = visualModel.PrimaryPart
	if primaryPart and primaryPart:IsA("BasePart") then
		return primaryPart
	end
	return visualModel:FindFirstChildWhichIsA("BasePart")
end

local function ConfigureEffectPartPhysics(part: BasePart)
	part.CanCollide = false
	part.Anchored = false
	part.Massless = true
	part.CanQuery = false
	part.CanTouch = false
end

local function ConfigureEffectModelPhysics(effectModel: Model)
	for _, descendant in ipairs(effectModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			ConfigureEffectPartPhysics(descendant)
		end
	end
end

local function ResolveVariantFxAlignCFrame(visualModel: Model): CFrame?
	local vfxInstance = GetVisualModelVfxInstance(visualModel)
	if vfxInstance then
		return vfxInstance.CFrame
	end
	local attachPart = GetVariantAttachPart(visualModel)
	if attachPart then
		return attachPart.CFrame
	end
	return nil
end

local function BuildVariantEffectModel(template: Instance): (Model?, BasePart?)
	if template:IsA("BasePart") then
		local effectModel = Instance.new("Model")
		local effectPart = template:Clone()
		ConfigureEffectPartPhysics(effectPart)
		for _, descendant in ipairs(effectPart:GetDescendants()) do
			if descendant:IsA("BasePart") then
				ConfigureEffectPartPhysics(descendant)
			end
		end
		effectPart.Parent = effectModel
		effectModel.PrimaryPart = effectPart
		return effectModel, effectPart
	end

	if template:IsA("Model") then
		local effectModel = template:Clone()
		ConfigureEffectModelPhysics(effectModel)
		local effectRoot = effectModel.PrimaryPart or effectModel:FindFirstChildWhichIsA("BasePart")
		if effectRoot and effectRoot:IsA("BasePart") then
			effectModel.PrimaryPart = effectRoot
			return effectModel, effectRoot
		end
		effectModel:Destroy()
	end

	return nil, nil
end

local function WeldEffectModelToVisual(visualModel: Model, effectModel: Model, effectRoot: BasePart): boolean
	local alignCFrame = ResolveVariantFxAlignCFrame(visualModel)
	local assemblyAnchor = GetVariantAttachPart(visualModel)
	if alignCFrame == nil or assemblyAnchor == nil then
		return false
	end

	effectModel.Name = VariantEffectInstanceName
	effectModel.Parent = visualModel
	effectModel:PivotTo(alignCFrame)

	local existingWeld = assemblyAnchor:FindFirstChild(VariantEffectWeldName)
	if existingWeld then
		existingWeld:Destroy()
	end

	local weld = Instance.new("Weld")
	weld.Name = VariantEffectWeldName
	weld.Part0 = assemblyAnchor
	weld.Part1 = effectRoot
	weld.C0 = assemblyAnchor.CFrame:ToObjectSpace(effectRoot.CFrame)
	weld.C1 = CFrame.new()
	weld.Parent = assemblyAnchor
	return true
end

function BrainrotVariantVisualTool.GetVariantLabelColor(variantId: number): Color3?
	if variantId <= 0 then
		return nil
	end
	return variantLabelColorCache[variantId]
end

local function BuildVariantLabelColorCache()
	for variantId, variantCfg in pairs(GameConfig.BrainrotVariantIdMap) do
		local template = GameConfig.FindResourceTemplateByResourceName(variantEffectFolder, variantCfg.resourceName)
		if template == nil then
			warn(
				"[BrainrotVariantVisualTool] Variant color template not found:",
				variantCfg.resourceName,
				"candidates:",
				table.concat(GameConfig.GetResourceNameCandidates(variantCfg.resourceName), ", ")
			)
		else
			local variantColorValue = FindVariantColorValue(template)
			if variantColorValue == nil then
				warn(
					"[BrainrotVariantVisualTool] VariantColor not found on template:",
					variantCfg.resourceName,
					template:GetFullName()
				)
			else
				variantLabelColorCache[variantId] = variantColorValue.Value
			end
		end
	end
end

function BrainrotVariantVisualTool.ApplyVariantLabel(controller: Instance, variantId: number?)
	local variantLabel = controller:FindFirstChild("VariantLabel") :: TextLabel?
	if variantLabel == nil then
		return
	end
	if variantId == nil or variantId <= 0 then
		variantLabel.Visible = false
		return
	end
	local variantCfg = GameConfig.GetBrainrotVariant(variantId)
	if variantCfg == nil then
		variantLabel.Visible = false
		return
	end
	variantLabel.Visible = true
	variantLabel.Text = variantCfg.name_t or ""
	local labelColor = BrainrotVariantVisualTool.GetVariantLabelColor(variantId)
	if labelColor then
		variantLabel.TextColor3 = labelColor
	end
end

function BrainrotVariantVisualTool.GetVisualCarryWeldPart(visualModel: Model, _variantId: number): BasePart?
	return GetVariantAttachPart(visualModel)
end

function BrainrotVariantVisualTool.ApplyVisualCarryWeld(carryPart: BasePart, visualModel: Model, _variantId: number)
	local existingWeld = carryPart:FindFirstChild(IslandVisualWeldName)
	if existingWeld then
		existingWeld:Destroy()
	end
	local weldPart1 = BrainrotVariantVisualTool.GetVisualCarryWeldPart(visualModel, 0)
	if weldPart1 == nil then
		return
	end
	local weld = Instance.new("Weld")
	weld.Name = IslandVisualWeldName
	weld.Part0 = carryPart
	weld.Part1 = weldPart1
	weld.C0 = carryPart.CFrame:ToObjectSpace(weldPart1.CFrame)
	weld.C1 = CFrame.new()
	weld.Parent = carryPart
end

function BrainrotVariantVisualTool.ClearVariantEffect(visualModel: Model)
	local existing = visualModel:FindFirstChild(VariantEffectInstanceName)
	if existing then
		existing:Destroy()
	end
	local assemblyAnchor = GetVariantAttachPart(visualModel)
	if assemblyAnchor then
		local existingWeld = assemblyAnchor:FindFirstChild(VariantEffectWeldName)
		if existingWeld then
			existingWeld:Destroy()
		end
	end
end

function BrainrotVariantVisualTool.AttachVariantEffect(visualModel: Model, variantId: number)
	if variantId <= 0 then
		BrainrotVariantVisualTool.ClearVariantEffect(visualModel)
		return
	end
	local variantCfg = GameConfig.GetBrainrotVariant(variantId)
	if variantCfg == nil then
		return
	end
	local template = GameConfig.FindResourceTemplateByResourceName(variantEffectFolder, variantCfg.resourceName)
	if template == nil then
		warn(
			"[BrainrotVariantVisualTool] Variant effect not found:",
			variantCfg.resourceName,
			"candidates:",
			table.concat(GameConfig.GetResourceNameCandidates(variantCfg.resourceName), ", ")
		)
		return
	end

	BrainrotVariantVisualTool.ClearVariantEffect(visualModel)

	local effectModel, effectRoot = BuildVariantEffectModel(template)
	if effectModel == nil or effectRoot == nil then
		warn(
			"[BrainrotVariantVisualTool] AttachVariantEffect: failed to build effect model:",
			variantCfg.resourceName,
			template:GetFullName()
		)
		return
	end

	if not WeldEffectModelToVisual(visualModel, effectModel, effectRoot) then
		effectModel:Destroy()
		warn("[BrainrotVariantVisualTool] AttachVariantEffect: failed to weld effect on", visualModel:GetFullName())
		return
	end
end

BuildVariantLabelColorCache()

return BrainrotVariantVisualTool
