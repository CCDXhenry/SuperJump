--!strict
-- 火箭背包客户端管理器：装备后作为装饰品常驻穿戴；跑道玩法进行中由 RunwaySession 接管（含冲刺特效），逃生阶段仍显示装饰。
local JetpackClientManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local players: Players = game:GetService("Players")
local localPlayer: Player? = players.LocalPlayer

if localPlayer == nil then
	return JetpackClientManager
end

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local RunwaySession = require(clientScripts:FindFirstChild("JumpRunway"):FindFirstChild("RunwaySession"))

local cfg = GameConfig.JumpRunway

local DecorationModelName = "PlayerJetpackDecoration"
local DecorationFallbackPartName = "PlayerJetpackDecorationFallback"

local decorationVisualRoot: Model? = nil
local decorationFallbackPart: BasePart? = nil
local decorationFallbackWarned = false
local decorationTemplateWarned = false

-- 跑道玩法进行中（非逃生）：使用 RunwaySession 火箭背包；逃生阶段与大厅一样用装饰。
local function IsJumpRunwayActiveGameplay(): boolean
	return ClientGameInfo.IsInJumpRunway() and not ClientGameInfo.IsInJumpRunwayEscapePhase()
end

local function HasEquippedJetpack(): boolean
	local info = ClientGameInfo.GetLocalPlayerInfo()
	if info == nil then
		return false
	end
	local currentId = info.jetpackInventory.currentId
	if currentId == nil or currentId == "" then
		return false
	end
	local jetpackData = GameConfig.JetpackDataMap[tonumber(currentId)]
	return jetpackData ~= nil
end

local function DestroyRunwayJetpackModel()
	if RunwaySession.DestroyJumpRunwayRocketBackpack then
		RunwaySession.DestroyJumpRunwayRocketBackpack()
	end
end

local function DestroyPlayerJetpackDecoration()
	if decorationVisualRoot ~= nil then
		decorationVisualRoot:Destroy()
		decorationVisualRoot = nil
	end
	if decorationFallbackPart ~= nil then
		decorationFallbackPart:Destroy()
		decorationFallbackPart = nil
	end
end

local function ConfigureDecorationJetpackBaseParts(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local bp = d :: BasePart
			bp.Anchored = false
			bp.CanCollide = false
			bp.CanQuery = false
			bp.Massless = true
		end
	end
end

local function DisableDecorationParticleEmitters(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			local pe = d :: ParticleEmitter
			pe.Enabled = false
			pe:Clear()
		end
	end
end

local function JetpackPartsShareWeldConstraint(a: BasePart, b: BasePart): boolean
	for _, ch in a:GetChildren() do
		if ch:IsA("WeldConstraint") then
			local w = ch :: WeldConstraint
			if w.Part0 == b or w.Part1 == b then
				return true
			end
		end
	end
	for _, ch in b:GetChildren() do
		if ch:IsA("WeldConstraint") then
			local w = ch :: WeldConstraint
			if w.Part0 == a or w.Part1 == a then
				return true
			end
		end
	end
	return false
end

local function WeldAllDecorationJetpackPartsToPrimaryPart(jetpackRoot: Model, primaryPart: BasePart)
	for _, d in jetpackRoot:GetDescendants() do
		if d:IsA("BasePart") then
			local bp = d :: BasePart
			if bp ~= primaryPart and not JetpackPartsShareWeldConstraint(bp, primaryPart) then
				local w = Instance.new("WeldConstraint")
				w.Part0 = primaryPart
				w.Part1 = bp
				w.Parent = bp
			end
		end
	end
end

local function GetCharacterAttachParts(character: Model): (BasePart?, BasePart?, BasePart?)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp == nil then
		return nil, nil, nil
	end
	local torso = character:FindFirstChild("UpperTorso") :: BasePart?
	if torso == nil then
		torso = character:FindFirstChild("Torso") :: BasePart?
	end
	local attachPart = torso or hrp
	return hrp, torso, attachPart
end

local function CreateDecorationFallbackPart(character: Model, hrp: BasePart, torso: BasePart?, attachPart: BasePart)
	local p = Instance.new("Part")
	p.Name = DecorationFallbackPartName
	p.Size = cfg.RUNWAY_ROCKET_BACKPACK_SIZE
	p.Color = cfg.RUNWAY_ROCKET_BACKPACK_COLOR
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.Massless = true
	p.Parent = character
	if torso ~= nil then
		p.CFrame = torso.CFrame
			* CFrame.new(
				cfg.RUNWAY_ROCKET_BACKPACK_OFFSET_X,
				cfg.RUNWAY_ROCKET_BACKPACK_OFFSET_Y,
				cfg.RUNWAY_ROCKET_BACKPACK_OFFSET_Z
			)
	else
		if not decorationFallbackWarned then
			decorationFallbackWarned = true
			warn("[JetpackClientManager] No UpperTorso/Torso; jetpack decoration welded to HumanoidRootPart.")
		end
		p.CFrame = hrp.CFrame
			* CFrame.new(
				cfg.RUNWAY_ROCKET_BACKPACK_HRP_FALLBACK_OFFSET_X,
				cfg.RUNWAY_ROCKET_BACKPACK_HRP_FALLBACK_OFFSET_Y,
				cfg.RUNWAY_ROCKET_BACKPACK_HRP_FALLBACK_OFFSET_Z
			)
	end
	local w = Instance.new("WeldConstraint")
	w.Part0 = attachPart
	w.Part1 = p
	w.Parent = p
	decorationFallbackPart = p
end

local function IsJetpackOuterTemplateReady(outerTemplate: Model?): boolean
	if outerTemplate == nil or not outerTemplate:IsA("Model") then
		return false
	end
	return outerTemplate.PrimaryPart ~= nil
end

local function TryResolveEquippedJetpackTemplate(): Model?
	local info = ClientGameInfo.GetLocalPlayerInfo()
	if info == nil then
		return nil
	end
	local currentIdStr = info.jetpackInventory.currentId
	if currentIdStr == nil or currentIdStr == "" then
		return nil
	end
	local currentId = tonumber(currentIdStr)
	if currentId == nil then
		return nil
	end
	local jetpackData = GameConfig.JetpackDataMap[currentId]
	if jetpackData == nil then
		return nil
	end
	local modelsFolder = replicatedStorage:FindFirstChild("Models")
	local jetpackFolder = if modelsFolder then modelsFolder:FindFirstChild("Jetpack") :: Folder? else nil
	if jetpackFolder == nil then
		return nil
	end
	local outerTemplate = jetpackFolder:FindFirstChild(jetpackData.resourceName) :: Model?
	if not IsJetpackOuterTemplateReady(outerTemplate) then
		return nil
	end
	return outerTemplate
end

local function TryResolveDefaultJetpackTemplate(): Model?
	local modelsFolder = replicatedStorage:FindFirstChild("Models")
	local outerTemplate = if modelsFolder
		then modelsFolder:FindFirstChild(cfg.RUNWAY_JETPACK_OUTER_MODEL_NAME) :: Model?
		else nil
	if not IsJetpackOuterTemplateReady(outerTemplate) then
		return nil
	end
	return outerTemplate
end

local function EnsurePlayerJetpackDecoration(character: Model)
	if not HasEquippedJetpack() then
		return
	end
	if decorationVisualRoot ~= nil and decorationVisualRoot.Parent ~= nil then
		return
	end
	if decorationFallbackPart ~= nil and decorationFallbackPart.Parent ~= nil then
		return
	end

	DestroyPlayerJetpackDecoration()

	local hrp, torso, attachPart = GetCharacterAttachParts(character)
	if hrp == nil or attachPart == nil then
		return
	end

	local useJetpackTemplate = cfg.RUNWAY_JETPACK_ENABLED == true
	if useJetpackTemplate then
		local outerTemplate = TryResolveEquippedJetpackTemplate()
		if outerTemplate == nil then
			outerTemplate = TryResolveDefaultJetpackTemplate()
		end
		if outerTemplate ~= nil then
			local clone = outerTemplate:Clone() :: Model
			clone.Name = DecorationModelName
			clone.Parent = character
			ConfigureDecorationJetpackBaseParts(clone)
			DisableDecorationParticleEmitters(clone)
			local primaryPart = clone.PrimaryPart
			if primaryPart == nil then
				clone:Destroy()
				if not decorationTemplateWarned then
					decorationTemplateWarned = true
					warn("[JetpackClientManager] Jetpack clone missing PrimaryPart; using fallback Part.")
				end
				CreateDecorationFallbackPart(character, hrp, torso, attachPart)
				return
			end
			WeldAllDecorationJetpackPartsToPrimaryPart(clone, primaryPart)
			if torso ~= nil then
				primaryPart.CFrame = torso.CFrame
					* CFrame.new(
						cfg.RUNWAY_ROCKET_BACKPACK_OFFSET_X,
						cfg.RUNWAY_ROCKET_BACKPACK_OFFSET_Y,
						cfg.RUNWAY_ROCKET_BACKPACK_OFFSET_Z
					)
			else
				primaryPart.CFrame = hrp.CFrame
					* CFrame.new(
						cfg.RUNWAY_ROCKET_BACKPACK_HRP_FALLBACK_OFFSET_X,
						cfg.RUNWAY_ROCKET_BACKPACK_HRP_FALLBACK_OFFSET_Y,
						cfg.RUNWAY_ROCKET_BACKPACK_HRP_FALLBACK_OFFSET_Z
					)
			end
			local w = Instance.new("WeldConstraint")
			w.Part0 = attachPart
			w.Part1 = primaryPart
			w.Parent = primaryPart
			decorationVisualRoot = clone
			return
		end
		if not decorationTemplateWarned then
			decorationTemplateWarned = true
			warn("[JetpackClientManager] Jetpack template missing; using fallback Part.")
		end
	end

	CreateDecorationFallbackPart(character, hrp, torso, attachPart)
end

local function RefreshPlayerJetpackDecoration()
	DestroyPlayerJetpackDecoration()
	if IsJumpRunwayActiveGameplay() then
		return
	end
	if not HasEquippedJetpack() then
		return
	end
	local character = localPlayer.Character
	if character == nil then
		return
	end
	EnsurePlayerJetpackDecoration(character)
end

local function OnJetpackInventoryUpdateFromServer(jetpackInventory: GameConfig.JetpackInventory)
	ClientGameInfo.UpdateJetpackInventory(jetpackInventory)
end

local function OnJetpackInventoryUpdateLocal(_jetpackInventory: GameConfig.JetpackInventory)
	if IsJumpRunwayActiveGameplay() then
		DestroyRunwayJetpackModel()
		local character = localPlayer.Character
		if character ~= nil and RunwaySession.EnsureJumpRunwayRocketBackpack then
			RunwaySession.EnsureJumpRunwayRocketBackpack(character)
		end
		return
	end
	RefreshPlayerJetpackDecoration()
end

local function OnLocalPlayerInfoInit()
	RefreshPlayerJetpackDecoration()
end

local function OnJumpRunwayStateMayHaveChanged()
	if IsJumpRunwayActiveGameplay() then
		DestroyPlayerJetpackDecoration()
		return
	end
	RefreshPlayerJetpackDecoration()
end

local function OnCharacterAdded(character: Model)
	task.defer(function()
		if character.Parent == nil then
			return
		end
		RefreshPlayerJetpackDecoration()
	end)
end

function JetpackClientManager.Init()
	NetMsg.ConnectNotifyPlayerJetpackInventoryUpdate(function(inventory: GameConfig.JetpackInventory)
		OnJetpackInventoryUpdateFromServer(inventory)
	end)
	ClientMsg.ConnectLocalPlayerJetpackInventoryUpdate(OnJetpackInventoryUpdateLocal)
	ClientMsg.ConnectLocalPlayerInfoInit(OnLocalPlayerInfoInit)
	ClientMsg.ConnectCurrentGuideTypeChanged(OnJumpRunwayStateMayHaveChanged)
	localPlayer.CharacterAdded:Connect(OnCharacterAdded)
	if localPlayer.Character ~= nil then
		RefreshPlayerJetpackDecoration()
	end
end

return JetpackClientManager
