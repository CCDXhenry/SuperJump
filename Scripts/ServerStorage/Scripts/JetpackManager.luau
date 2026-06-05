--!strict
local JetpackManager = {}

local marketplaceService: MarketplaceService = game:GetService("MarketplaceService")
local players: Players = game:GetService("Players")
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local ServerMsg = require(serverScripts:FindFirstChild("ServerMsg"))
local AnalyticsTool = require(serverScripts:FindFirstChild("AnalyticsTool"))

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

local LOG_PREFIX = "[JetpackManager]"
local JetpackModelName = "JumpRunwayJetpackClone"
local JetpackFallbackPartName = "JumpRunwayRocketBackpack"
local JetpackServerCreatedAttr = "JumpRunwayJetpackServerCreated"
local JetpackIdAttr = "JetpackId"
local characterAddedConnMap: { [number]: RBXScriptConnection } = {}
local currentJetpackIdChangedConnMap: { [number]: RBXScriptConnection } = {}

local cfg = GameConfig.JumpRunway

local function LogInfo(message: string)
	print(string.format("%s %s", LOG_PREFIX, message))
end

local function IsJetpackModelPart(instance: Instance): boolean
	return instance:IsA("Part") or instance:IsA("MeshPart")
end

local function FindJetpackModelPart(parent: Instance, partName: string): BasePart?
	local child = parent:FindFirstChild(partName)
	if child ~= nil and IsJetpackModelPart(child) then
		return child :: BasePart
	end
	return nil
end

local function ResolveJetpackPrimaryPart(jetpackRoot: Model, assignPrimaryPart: boolean?): BasePart?
	local primaryPart = jetpackRoot.PrimaryPart
	if primaryPart ~= nil and IsJetpackModelPart(primaryPart) then
		return primaryPart
	end
	local rootPart = FindJetpackModelPart(jetpackRoot, cfg.RUNWAY_JETPACK_ROOT_PART_NAME)
	if rootPart ~= nil then
		if assignPrimaryPart ~= false then
			jetpackRoot.PrimaryPart = rootPart
		end
		return rootPart
	end
	return nil
end

local function IsJetpackTemplateReady(template: Model?): boolean
	if template == nil or not template:IsA("Model") then
		return false
	end
	return ResolveJetpackPrimaryPart(template, false) ~= nil
end

local function ConfigureJetpackBaseParts(root: Instance)
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

local function WeldAllJetpackPartsToPrimaryPart(jetpackRoot: Model, primaryPart: BasePart)
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

local function ResolveEquippedJetpackTemplate(player: Player): Model?
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return nil
	end
	local currentIdStr = playerInfo.jetpackInventory.currentId
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
	if not IsJetpackTemplateReady(outerTemplate) then
		return nil
	end
	return outerTemplate
end

local function ResolveDefaultJetpackTemplate(): Model?
	local modelsFolder = replicatedStorage:FindFirstChild("Models")
	local outerTemplate = if modelsFolder
		then modelsFolder:FindFirstChild(cfg.RUNWAY_JETPACK_OUTER_MODEL_NAME) :: Model?
		else nil
	if not IsJetpackTemplateReady(outerTemplate) then
		return nil
	end
	return outerTemplate
end

local function DisableJetpackParticleEmitters(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			local pe = d :: ParticleEmitter
			pe.Enabled = false
			pe:Clear()
		end
	end
end

local function CollectJetpackDashParticleEmitters(character: Model): { ParticleEmitter }
	local list: { ParticleEmitter } = {}
	local jetpackModel = character:FindFirstChild(JetpackModelName)
	if jetpackModel == nil or not jetpackModel:IsA("Model") then
		return list
	end
	local seen: { [ParticleEmitter]: boolean } = {}
	for _, flameName in { cfg.RUNWAY_JETPACK_FLAME1_NAME, cfg.RUNWAY_JETPACK_FLAME2_NAME } do
		local flame = FindJetpackModelPart(jetpackModel, flameName)
		if flame == nil then
			continue
		end
		for _, d in flame:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				local pe = d :: ParticleEmitter
				if not seen[pe] then
					seen[pe] = true
					table.insert(list, pe)
				end
			end
		end
	end
	return list
end

local function DestroyPlayerJetpack(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	local jetpackModel = character:FindFirstChild(JetpackModelName)
	if jetpackModel ~= nil and jetpackModel:GetAttribute(JetpackServerCreatedAttr) == true then
		jetpackModel:Destroy()
	end
	local fallbackPart = character:FindFirstChild(JetpackFallbackPartName)
	if fallbackPart ~= nil and fallbackPart:GetAttribute(JetpackServerCreatedAttr) == true then
		fallbackPart:Destroy()
	end
end

local function CreateFallbackJetpack(character: Model, hrp: BasePart, torso: BasePart?, attachPart: BasePart, jetpackId: string)
	local p = Instance.new("Part")
	p.Name = JetpackFallbackPartName
	p:SetAttribute(JetpackServerCreatedAttr, true)
	p:SetAttribute(JetpackIdAttr, jetpackId)
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
end

function JetpackManager.EnsurePlayerJetpack(player: Player)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil or playerInfo.jetpackInventory.currentId == "" then
		DestroyPlayerJetpack(player)
		return
	end
	local currentJetpackId = playerInfo.jetpackInventory.currentId
	local character = player.Character
	if character == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid == nil or hrp == nil or humanoid.Health <= 0 then
		return
	end
	local existingModel = character:FindFirstChild(JetpackModelName)
	if
		existingModel ~= nil
		and existingModel:GetAttribute(JetpackServerCreatedAttr) == true
		and existingModel:GetAttribute(JetpackIdAttr) == currentJetpackId
	then
		return
	end
	local existingFallback = character:FindFirstChild(JetpackFallbackPartName)
	if
		existingFallback ~= nil
		and existingFallback:GetAttribute(JetpackServerCreatedAttr) == true
		and existingFallback:GetAttribute(JetpackIdAttr) == currentJetpackId
	then
		return
	end
	DestroyPlayerJetpack(player)
	local torso = character:FindFirstChild("UpperTorso") :: BasePart?
	if torso == nil then
		torso = character:FindFirstChild("Torso") :: BasePart?
	end
	local attachPart = torso or hrp
	local outerTemplate = if cfg.RUNWAY_JETPACK_ENABLED == true then ResolveEquippedJetpackTemplate(player) else nil
	if outerTemplate == nil and cfg.RUNWAY_JETPACK_ENABLED == true then
		outerTemplate = ResolveDefaultJetpackTemplate()
	end
	if outerTemplate == nil then
		CreateFallbackJetpack(character, hrp, torso, attachPart, currentJetpackId)
		return
	end
	local clone = outerTemplate:Clone() :: Model
	clone.Name = JetpackModelName
	clone:SetAttribute(JetpackServerCreatedAttr, true)
	clone:SetAttribute(JetpackIdAttr, currentJetpackId)
	clone.Parent = character
	ConfigureJetpackBaseParts(clone)
	DisableJetpackParticleEmitters(clone)
	local primaryPart = ResolveJetpackPrimaryPart(clone)
	if primaryPart == nil then
		clone:Destroy()
		CreateFallbackJetpack(character, hrp, torso, attachPart, currentJetpackId)
		return
	end
	WeldAllJetpackPartsToPrimaryPart(clone, primaryPart)
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
end

function JetpackManager.SetPlayerJetpackDashParticlesEnabled(player: Player, enabled: boolean)
	local character = player.Character
	if character == nil then
		return
	end
	for _, pe in CollectJetpackDashParticleEmitters(character) do
		if pe.Parent ~= nil then
			pe.Enabled = enabled
			if not enabled and cfg.RUNWAY_JETPACK_DASH_PARTICLE_CLEAR_ON_IDLE then
				pe:Clear()
			end
		end
	end
end

local function BindPlayerJetpack(player: Player)
	if characterAddedConnMap[player.UserId] ~= nil then
		return
	end
	characterAddedConnMap[player.UserId] = player.CharacterAdded:Connect(function(character: Model)
		task.defer(function()
			if character.Parent ~= nil then
				JetpackManager.EnsurePlayerJetpack(player)
			end
		end)
	end)
	currentJetpackIdChangedConnMap[player.UserId] = player:GetAttributeChangedSignal("CurrentJetpackId"):Connect(function()
		JetpackManager.EnsurePlayerJetpack(player)
	end)
	if player.Character ~= nil then
		task.defer(JetpackManager.EnsurePlayerJetpack, player)
	end
end

local function OnPlayerInfoInit(player: Player)
	BindPlayerJetpack(player)
	JetpackManager.EnsurePlayerJetpack(player)
end

local function OnPlayerRemoving(player: Player)
	local conn = characterAddedConnMap[player.UserId]
	if conn ~= nil then
		conn:Disconnect()
		characterAddedConnMap[player.UserId] = nil
	end
	local attrConn = currentJetpackIdChangedConnMap[player.UserId]
	if attrConn ~= nil then
		attrConn:Disconnect()
		currentJetpackIdChangedConnMap[player.UserId] = nil
	end
	DestroyPlayerJetpack(player)
end

local function CanAffordJetpack(playerInfo: GameConfig.PlayerInfo, jetpackData: GameConfig.JetpackData): boolean
	local coinKey = tostring(GameConfig.CurrencyType.Coin)
	local currentCoins = playerInfo.currencies[coinKey] or 0
	local coinCost = jetpackData.costCoin

	if jetpackData.costType == GameConfig.CostType.Coin or jetpackData.costType == GameConfig.CostType.CoinOrRb then
		return currentCoins >= coinCost
	end
	return false
end

local function SpendJetpackCost(player: Player, jetpackData: GameConfig.JetpackData)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local coinKey = tostring(GameConfig.CurrencyType.Coin)
	local currentCoins = playerInfo.currencies[coinKey] or 0
	local coinCost = jetpackData.costCoin

	if
		(jetpackData.costType == GameConfig.CostType.Coin or jetpackData.costType == GameConfig.CostType.CoinOrRb)
		and currentCoins >= coinCost
	then
		ServerGameInfo.UpdatePlayerCurrency(player, GameConfig.CurrencyType.Coin, -coinCost, GameConfig.ItemCountChangeReason.GainFromPurchase)
	end
end

local function GetMoneyCount(playerInfo: GameConfig.PlayerInfo): number
	return playerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
end

-- 处理客户端购买火箭背包请求
function JetpackManager.OnRequestBuyJetpack(player: Player, jetpackId: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local jetpackData = GameConfig.JetpackDataMap[jetpackId]
	if jetpackData == nil then
		warn(string.format("%s Jetpack data not found for id: %d", LOG_PREFIX, jetpackId))
		return
	end

	local jetpackIdStr = tostring(jetpackId)
	if playerInfo.jetpackInventory.ownedList[jetpackIdStr] then
		LogInfo(string.format("BuyRejected userId=%d reason=already_owned jetpackId=%d", player.UserId, jetpackId))
		return
	end

	if CanAffordJetpack(playerInfo, jetpackData) then
		LogInfo(string.format("BuyAccepted userId=%d jetpackId=%d coinCost=%d costType=%d", player.UserId, jetpackId, jetpackData.costCoin, jetpackData.costType))
		SpendJetpackCost(player, jetpackData)
		-- 添加火箭背包
		ServerGameInfo.AddJetpackToInventory(player, jetpackIdStr)
		-- 自动装备
		JetpackManager.OnRequestUpdateJetpackUsing(player, jetpackId)
		AnalyticsTool.LogJetpackGet(player, jetpackId, GetMoneyCount(playerInfo), 0)
	else
		local rejectReason = "insufficient_currency"
		if jetpackData.costType == GameConfig.CostType.Rb then
			rejectReason = "rb_purchase_only"
		elseif jetpackData.costType == GameConfig.CostType.GroupReward then
			rejectReason = "group_reward_only"
		elseif jetpackData.costType == GameConfig.CostType.StorePurchase then
			rejectReason = "store_purchase_only"
		end
		LogInfo(string.format("BuyRejected userId=%d reason=%s jetpackId=%d", player.UserId, rejectReason, jetpackId))
	end
end

function JetpackManager.OnRequestBuyJetpackPaid(player: Player, jetpackId: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local jetpackData = GameConfig.JetpackDataMap[jetpackId]
	if jetpackData == nil or jetpackData.productId <= 0 then
		warn(string.format("%s PaidBuyRejected userId=%d reason=invalid_product jetpackId=%d", LOG_PREFIX, player.UserId, jetpackId))
		return
	end

	if playerInfo.jetpackInventory.ownedList[tostring(jetpackId)] then
		LogInfo(string.format("PaidBuyRejected userId=%d reason=already_owned jetpackId=%d", player.UserId, jetpackId))
		return
	end

	if not ServerGameInfo.SetPendingPaidShopItem(player, GameConfig.ItemType.Jetpack, jetpackId, jetpackData.productId) then
		LogInfo(string.format("PaidBuyRejected userId=%d reason=pending_failed jetpackId=%d", player.UserId, jetpackId))
		return
	end

	marketplaceService:PromptProductPurchase(player, jetpackData.productId)
end

-- 处理客户端更换火箭背包请求
function JetpackManager.OnRequestUpdateJetpackUsing(player: Player, jetpackId: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local jetpackIdStr = tostring(jetpackId)
	if not playerInfo.jetpackInventory.ownedList[jetpackIdStr] then
		warn(string.format("%s EquipRejected userId=%d reason=not_owned jetpackId=%d", LOG_PREFIX, player.UserId, jetpackId))
		return
	end

	LogInfo(string.format("EquipAccepted userId=%d jetpackId=%d", player.UserId, jetpackId))
	ServerGameInfo.SetCurrentJetpack(player, jetpackIdStr)
	JetpackManager.EnsurePlayerJetpack(player)
end

-- 处理客户端领取群组火箭背包奖励请求
function JetpackManager.OnRequestClaimJetpackGroupReward(player: Player, isInGroup: boolean)
	if not isInGroup then
		return
	end

	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	-- 取所有 costType == GroupReward 的火箭背包 ID
	local groupRewardJetpackIdList: { number } = {}
	for _, jetpackData in GameConfig.JetpackDataMap do
		if jetpackData.costType == GameConfig.CostType.GroupReward then
			table.insert(groupRewardJetpackIdList, jetpackData.id)
		end
	end

	if #groupRewardJetpackIdList == 0 then
		warn(string.format("%s Group reward jetpack list is empty", LOG_PREFIX))
		return
	end

	-- 检查是否至少有一个群组奖励火箭背包未拥有，避免重复通知
	local hasAnyToClaim = false
	for _, rewardJetpackId in ipairs(groupRewardJetpackIdList) do
		local jetpackIdStr = tostring(rewardJetpackId)
		if not playerInfo.jetpackInventory.ownedList[jetpackIdStr] then
			hasAnyToClaim = true
			break
		end
	end

	if not hasAnyToClaim then
		LogInfo(string.format("GroupReward already claimed all userId=%d", player.UserId))
		return
	end

	for _, rewardJetpackId in ipairs(groupRewardJetpackIdList) do
		ServerGameInfo.AddJetpackToInventory(player, tostring(rewardJetpackId))
	end
	LogInfo(string.format("GroupRewardClaimed userId=%d count=%d", player.UserId, #groupRewardJetpackIdList))
end

function JetpackManager.Init()
	ServerMsg.ConnectPlayerInfoInit(OnPlayerInfoInit)
	NetMsg.ConnectRequestBuyJetpack(JetpackManager.OnRequestBuyJetpack)
	NetMsg.ConnectRequestBuyJetpackPaid(JetpackManager.OnRequestBuyJetpackPaid)
	NetMsg.ConnectRequestUpdateJetpackUsing(JetpackManager.OnRequestUpdateJetpackUsing)
	NetMsg.ConnectRequestClaimJetpackGroupReward(JetpackManager.OnRequestClaimJetpackGroupReward)
	players.PlayerRemoving:Connect(OnPlayerRemoving)
	for _, player in ipairs(players:GetPlayers()) do
		if ServerGameInfo.GetPlayerInfo(player) ~= nil then
			OnPlayerInfoInit(player)
		end
	end
	LogInfo("Init success")
end

return JetpackManager
