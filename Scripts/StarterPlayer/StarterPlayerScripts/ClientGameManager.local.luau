--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local SoundTool = require(coreSharedScripts:FindFirstChild("SoundTool"))
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
--local GraphicsPerformanceGuard = require(clientScripts:WaitForChild("GraphicsPerformanceGuard"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local UIManager = require(clientScripts:FindFirstChild("UIManager"))
local players = game:GetService("Players")
local HomeClientManager = require(clientScripts:FindFirstChild("HomeClientManager"))
local ShopClientManager = require(clientScripts:WaitForChild("ShopClientManager"))
local PlayerInteractClientManager = require(clientScripts:WaitForChild("PlayerInteractClientManager"))
local BrainrotClientManager = require(clientScripts:WaitForChild("BrainrotClientManager"))
--local ChestWorkbenchClientManager = require(clientScripts:WaitForChild("ChestWorkbenchClientManager"))
local GuideManager = require(clientScripts:WaitForChild("GuideManager"))
local JumpRunwayClientManager = require(clientScripts:WaitForChild("JumpRunwayClientManager"))
local TeleportPortalClientManager = require(clientScripts:WaitForChild("TeleportPortalClientManager"))
local LobbyTeleportClientManager = require(clientScripts:WaitForChild("LobbyTeleportClientManager"))
local ExEquipManager = require(clientScripts:WaitForChild("ExEquipManager"))
local JetpackClientManager = require(clientScripts:WaitForChild("JetpackClientManager"))
local GroupRewardClientManager = require(clientScripts:WaitForChild("GroupRewardClientManager"))
local FriendRewardClientManager = require(clientScripts:WaitForChild("FriendRewardClientManager"))
local PlayerInfoClientManager = require(clientScripts:WaitForChild("PlayerInfoClientManager"))
local LeaderboardClient = require(clientScripts:WaitForChild("LeaderboardClient"))
local IdleInputClientManager = require(clientScripts:FindFirstChild("IdleInputClientManager"))
-- JumpRunway：尽早绑定 NotifyJumpRunwayState，避免服务端开局 FireClient 时客户端尚未 OnClientEvent 导致队列耗尽

local starterGui: StarterGui = game:GetService("StarterGui")
local contentProvider: ContentProvider = game:GetService("ContentProvider")
local modelOriginsFolder: Folder? = replicatedStorage:FindFirstChild("Models") :: Folder?
local uiOriginsFolder: Folder? = replicatedStorage:FindFirstChild("UI") :: Folder?
local soundOriginsFolder: Folder? = workspace:FindFirstChild("Sounds") :: Folder?
local replicatedSoundOriginsFolder: Folder? = replicatedStorage:FindFirstChild("Sounds") :: Folder?

local DesignScreenSize: Vector2 = Vector2.new(1920, 1080)
local GameTipZIndex: number = 2000
local soundsFolder: Folder = workspace:FindFirstChild("Sounds")
local bgmSound: Sound = soundsFolder:FindFirstChild("BGM") :: Sound
local PreloadAssets: () -> ()
local PreloadPriority = {
	P0 = 1,
	P1 = 2,
	P2 = 3,
}
local PreloadBatchSize: number = 50
local PreloadBatchYieldSeconds: number = 0.05
local PreloadSlowBatchWarnSeconds: number = 30
local PreloadMeshAssetsEnabled: boolean = true
local PreloadOverrideDebugEnabled: boolean = false
local PreloadFailureSampleCount: number = 5
local PreloadP0MaxWaitSeconds: number = 1.5
local PreloadPriorityOverrideByPath: { [string]: number } = {
	["ReplicatedStorage.Models.GuideArrow.ArrowBeam"] = PreloadPriority.P0,
}
local PreloadPriorityOverrideByAssetId: { [string]: number } = {
	["rbxassetid://17111819175"] = PreloadPriority.P0,
}
local PreloadP0UiFrameNameMap: { [string]: boolean } = {
	GameFrame = true,
	LobbyFrame = true,
	GameTipFrame = true,
	GiftsFrame = true,
	[GameConfig.GuideAssetName.UiFrame] = true,
}
local PreloadP1UiFrameNameMap: { [string]: boolean } = {
	OfflineRewardsFrame = true,
	OnlineRewardFrame = true,
	[UIManager.WindowId.JumpRunWayFrame] = true,
}
local preloadP0Complete = false

type PreloadAssetBucketMap = { [number]: { Instance } }
type PreloadAssetEntry = {
	instance: Instance,
	priority: number,
}
type PreloadAssetEntryMap = { [string]: PreloadAssetEntry }

local function GetPreloadPriorityName(priority: number): string
	if priority == PreloadPriority.P0 then
		return "P0"
	end
	if priority == PreloadPriority.P1 then
		return "P1"
	end
	return "P2"
end

local function GetInstanceDebugPath(instance: Instance): string
	local nameList: { string } = {}
	local current: Instance? = instance
	while current ~= nil and current ~= game do
		table.insert(nameList, 1, current.Name)
		current = current.Parent
	end
	return table.concat(nameList, ".")
end

local function GetTopLevelChildName(root: Instance?, instance: Instance): string?
	if root == nil or not instance:IsDescendantOf(root) then
		return nil
	end

	local current = instance
	while current.Parent ~= nil and current.Parent ~= root do
		current = current.Parent
	end

	if current.Parent == root then
		return current.Name
	end
	return nil
end

local function GetDefaultPreloadPriority(instance: Instance): number
	local uiRootName = GetTopLevelChildName(uiOriginsFolder, instance)
	if uiRootName ~= nil then
		if PreloadP0UiFrameNameMap[uiRootName] then
			return PreloadPriority.P0
		end
		if PreloadP1UiFrameNameMap[uiRootName] then
			return PreloadPriority.P1
		end
	end

	local modelRootName = GetTopLevelChildName(modelOriginsFolder, instance)
	if modelRootName ~= nil then
		if modelRootName == GameConfig.GuideAssetName.ModelArrow then
			return PreloadPriority.P0
		end
		return PreloadPriority.P2
	end

	if instance:IsA("Sound") and instance.Name == "BGM" then
		return PreloadPriority.P0
	end

	return PreloadPriority.P2
end

local function ResolvePreloadPriority(instance: Instance, assetId: string?, defaultPriority: number): (number, string?)
	local instancePath = GetInstanceDebugPath(instance)
	local pathPriority = PreloadPriorityOverrideByPath[instancePath]
	if pathPriority ~= nil then
		return pathPriority, string.format("path=%s", instancePath)
	end

	if assetId ~= nil and assetId ~= "" then
		local assetPriority = PreloadPriorityOverrideByAssetId[assetId]
		if assetPriority ~= nil then
			return assetPriority, string.format("assetId=%s", assetId)
		end
	end

	return defaultPriority, nil
end

local function EnsurePreloadBucket(assetBucketMap: PreloadAssetBucketMap, priority: number): { Instance }
	local bucket = assetBucketMap[priority]
	if bucket == nil then
		bucket = {}
		assetBucketMap[priority] = bucket
	end
	return bucket
end

local function RemovePreloadInstanceFromBucket(assetBucketMap: PreloadAssetBucketMap, priority: number, targetInstance: Instance)
	local bucket = assetBucketMap[priority]
	if bucket == nil then
		return
	end
	for index, bucketInstance in ipairs(bucket) do
		if bucketInstance == targetInstance then
			table.remove(bucket, index)
			return
		end
	end
end

local function RegisterPreloadAssetInstance(
	assetBucketMap: PreloadAssetBucketMap,
	assetEntryMap: PreloadAssetEntryMap,
	assetId: string,
	priority: number,
	createInstance: () -> Instance
)
	if assetId == "" then
		return
	end

	local existingEntry = assetEntryMap[assetId]
	if existingEntry ~= nil then
		if priority < existingEntry.priority then
			RemovePreloadInstanceFromBucket(assetBucketMap, existingEntry.priority, existingEntry.instance)
			table.insert(EnsurePreloadBucket(assetBucketMap, priority), existingEntry.instance)
			existingEntry.priority = priority
		end
		return
	end

	local newInstance = createInstance()
	assetEntryMap[assetId] = {
		instance = newInstance,
		priority = priority,
	}
	table.insert(EnsurePreloadBucket(assetBucketMap, priority), newInstance)
end

local function WaitForPreloadP0Completion(): boolean
	if preloadP0Complete then
		return true
	end

	local deadline = os.clock() + PreloadP0MaxWaitSeconds
	while not preloadP0Complete and os.clock() < deadline do
		task.wait()
	end

	if preloadP0Complete then
		return true
	end

	warn(string.format("[ClientGameManager] PreloadAssets P0 wait timeout after %.2fs", PreloadP0MaxWaitSeconds))
	return false
end

local function TryOpenOfflineRewardsWindow()
	local offlineRewardInfo = ClientGameInfo.GetOfflineRewardInfo()
	if offlineRewardInfo == nil or offlineRewardInfo.baseReward <= 0 then
		return
	end
	if UIManager.GetGameScreenGui() == nil then
		return
	end
	UIManager.OpenWindow(UIManager.WindowId.OfflineRewards)
end

local function InitUI()
	local playerGui: PlayerGui = players.LocalPlayer:WaitForChild("PlayerGui")
	local gameScreenGui: ScreenGui = playerGui:WaitForChild("GameScreenGui") :: ScreenGui
	--禁用默认工具栏
	starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	--设置窗口容器
	UIManager.Init(gameScreenGui)
	-- 创建主界面
	UIManager.CreateFrame("GameFrame", "GameFrame", gameScreenGui, 0)
	local lobbyFrame = UIManager.CreateFrame("LobbyFrame", "LobbyFrame", gameScreenGui, 0) :: Frame
	-- 创建游戏提示界面
	UIManager.CreateFrame("GameTipFrame", "GameTipFrame", gameScreenGui, GameTipZIndex)
	UIManager.CreateFrame("GiftsFrame", "GiftsFrame", gameScreenGui, GameTipZIndex)
	-- 引导手指层（低于 GameTip，高于 Lobby）
	UIManager.CreateFrame(GameConfig.GuideAssetName.UiFrame, "GuideFrame", gameScreenGui, 1500)

	-- 创建背包界面 (逻辑已集成到 LobbyFrame.BottomButtonsFrame)
	-- UIManager.CreateFrame("BackpackFrame", "BackpackFrame", gameScreenGui, 10)
	local backpackScriptOrigin = scripts:WaitForChild("Client"):WaitForChild("UIManager"):FindFirstChild("BackpackFrame")
	if backpackScriptOrigin then
		local backpackScript = backpackScriptOrigin:Clone() :: any
		backpackScript.Parent = lobbyFrame
	end

	--UI适配器初始化
	UIAdapter.Init(DesignScreenSize, gameScreenGui.AbsoluteSize)
	gameScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		UIAdapter.OnScreenSizeChange(gameScreenGui.AbsoluteSize)
	end)

	-- 初始化系统经理
	JumpRunwayClientManager.Init()
	TeleportPortalClientManager.Init()
	LobbyTeleportClientManager.Init()
	HomeClientManager.Init()
	ShopClientManager.Init()
	PlayerInteractClientManager.Init()
	BrainrotClientManager.Init()
	--ChestWorkbenchClientManager.Init()
	ExEquipManager.Init()
	JetpackClientManager.Init()
	GroupRewardClientManager.Init()
	if GameConfig.EnableFriendOnlineBuff then
		FriendRewardClientManager.Init()
	end
	PlayerInfoClientManager.Init()
	LeaderboardClient.Init()
	GuideManager.Init()
	-- JumpRunwayClientManager 已在脚本加载时 Init（见上方），勿仅放在 InitUI 以免晚于服务端推送
	-- 初始化背包输入控制
	local BackpackInputManager = require(clientScripts:WaitForChild("BackpackInputManager"))
	BackpackInputManager.Init()
	TryOpenOfflineRewardsWindow()
end

--通知客户端玩家信息初始化
local function OnNotifyPlayerInfoInit(
	localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo },
	playerConfigInfo: GameConfig.PlayerConfigInfo
)
	ClientGameInfo.InitPlayerInfo(localPlayerSaveInfo, otherPlayerSaveInfoMap, playerConfigInfo)
	local localPlayerInfo: GameConfig.ClientLocalPlayerInfo? = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo ~= nil then
		SoundTool.SetBGMVolumn(localPlayerInfo.settingInfo.bgmVolume)
		SoundTool.SetSoundEffectVolume(localPlayerInfo.settingInfo.soundEffectVolume)
	end
	SoundTool.PlayBGM(bgmSound)
	-- 玩家信息就绪后初始化UI/系统
	task.spawn(function()
		WaitForPreloadP0Completion()
		InitUI()
	end)
end

PreloadAssets = function()
	local preloadStartTime = os.clock()
	local assetBucketMap: PreloadAssetBucketMap = {}
	local meshMap: PreloadAssetEntryMap = {}
	local decalMap: PreloadAssetEntryMap = {}
	local imageMap: PreloadAssetEntryMap = {}
	local soundMap: PreloadAssetEntryMap = {}
	local animationMap: PreloadAssetEntryMap = {}
	local failedAssetList: { string } = {}
	local failedAssetCount = 0
	local overrideLogMap: { [string]: boolean } = {}
	local folderList: { Instance } = {}
	if modelOriginsFolder ~= nil then
		table.insert(folderList, modelOriginsFolder)
	end
	if soundOriginsFolder ~= nil then
		table.insert(folderList, soundOriginsFolder)
	end
	if replicatedSoundOriginsFolder ~= nil then
		table.insert(folderList, replicatedSoundOriginsFolder)
	end
	if uiOriginsFolder ~= nil then
		table.insert(folderList, uiOriginsFolder)
	end

	local function AddMesh(meshId: string, priority: number)
		if not PreloadMeshAssetsEnabled then
			return
		end
		RegisterPreloadAssetInstance(assetBucketMap, meshMap, meshId, priority, function()
			local specialMesh = Instance.new("SpecialMesh")
			specialMesh.MeshId = meshId
			return specialMesh
		end)
	end

	local function AddDecal(textureId: string, priority: number)
		RegisterPreloadAssetInstance(assetBucketMap, decalMap, textureId, priority, function()
			local decal = Instance.new("Decal")
			decal.Texture = textureId
			return decal
		end)
	end

	local function AddImage(imageId: string, priority: number)
		RegisterPreloadAssetInstance(assetBucketMap, imageMap, imageId, priority, function()
			local image = Instance.new("ImageLabel")
			image.Image = imageId
			return image
		end)
	end

	local function AddSound(soundId: string, priority: number)
		RegisterPreloadAssetInstance(assetBucketMap, soundMap, soundId, priority, function()
			local sound = Instance.new("Sound")
			sound.SoundId = soundId
			return sound
		end)
	end

	local function AddAnimation(animationId: string, priority: number)
		RegisterPreloadAssetInstance(assetBucketMap, animationMap, animationId, priority, function()
			local animation = Instance.new("Animation")
			animation.AnimationId = animationId
			return animation
		end)
	end

	local function RegisterAssetForPreload(instance: Instance, assetType: string, assetId: string, defaultPriority: number)
		if assetId == "" then
			return
		end

		local resolvedPriority, overrideSource = ResolvePreloadPriority(instance, assetId, defaultPriority)
		if overrideSource ~= nil and PreloadOverrideDebugEnabled then
			local overrideKey = string.format("%s|%s|%s", overrideSource, assetType, assetId)
			if overrideLogMap[overrideKey] == nil then
				overrideLogMap[overrideKey] = true
				warn(string.format(
					"[ClientGameManager] PreloadAssets override hit %s assetType=%s assetId=%s default=%s resolved=%s",
					overrideSource,
					assetType,
					assetId,
					GetPreloadPriorityName(defaultPriority),
					GetPreloadPriorityName(resolvedPriority)
				))
			end
		end

		if assetType == "Mesh" then
			AddMesh(assetId, resolvedPriority)
		elseif assetType == "Decal" then
			AddDecal(assetId, resolvedPriority)
		elseif assetType == "Image" then
			AddImage(assetId, resolvedPriority)
		elseif assetType == "Sound" then
			AddSound(assetId, resolvedPriority)
		elseif assetType == "Animation" then
			AddAnimation(assetId, resolvedPriority)
		end
	end

	local function RegisterConfigImageForPreload(imageId: string, defaultPriority: number)
		if imageId == "" then
			return
		end

		local resolvedPriority, overrideSource = ResolvePreloadPriority(script, imageId, defaultPriority)
		if overrideSource ~= nil and PreloadOverrideDebugEnabled then
			local overrideKey = string.format("%s|Image|%s", overrideSource, imageId)
			if overrideLogMap[overrideKey] == nil then
				overrideLogMap[overrideKey] = true
				warn(string.format(
					"[ClientGameManager] PreloadAssets override hit %s assetType=Image assetId=%s default=%s resolved=%s",
					overrideSource,
					imageId,
					GetPreloadPriorityName(defaultPriority),
					GetPreloadPriorityName(resolvedPriority)
				))
			end
		end

		AddImage(imageId, resolvedPriority)
	end

	local function PreloadBucket(priority: number)
		local priorityName = GetPreloadPriorityName(priority)
		local assetList = assetBucketMap[priority]
		if assetList == nil or #assetList == 0 then
			warn(string.format("[ClientGameManager] PreloadAssets %s complete. candidates=0 failed=0 elapsed=0.00s", priorityName))
			return
		end

		local bucketStartTime = os.clock()
		local bucketFailedAssetCount = 0
		local batchStartIndex = 1
		local batchIndex = 0
		while batchStartIndex <= #assetList do
			batchIndex += 1
			local batchList: { Instance } = {}
			local batchEndIndex = math.min(batchStartIndex + PreloadBatchSize - 1, #assetList)
			for assetIndex = batchStartIndex, batchEndIndex do
				table.insert(batchList, assetList[assetIndex])
			end

			local batchStartTime = os.clock()
			local preloadSuccess, preloadErr = pcall(function()
				contentProvider:PreloadAsync(batchList, function(assetId: string, assetFetchStatus: Enum.AssetFetchStatus)
					if assetFetchStatus ~= Enum.AssetFetchStatus.Success then
						failedAssetCount += 1
						bucketFailedAssetCount += 1
						if failedAssetCount <= PreloadFailureSampleCount then
							table.insert(failedAssetList, string.format("%s:%s", assetId, assetFetchStatus.Name))
						end
					end
				end)
			end)
			local batchElapsedTime = os.clock() - batchStartTime

			if not preloadSuccess then
				warn(string.format("[ClientGameManager] PreloadAssets %s batch failed: %d %s", priorityName, batchIndex, tostring(preloadErr)))
			elseif batchElapsedTime >= PreloadSlowBatchWarnSeconds then
				warn(string.format(
					"[ClientGameManager] PreloadAssets %s slow batch=%d size=%d elapsed=%.2fs",
					priorityName,
					batchIndex,
					#batchList,
					batchElapsedTime
				))
			end

			table.clear(batchList)
			batchStartIndex = batchEndIndex + 1
			if batchStartIndex <= #assetList then
				task.wait(PreloadBatchYieldSeconds)
			end
		end

		local bucketElapsedTime = os.clock() - bucketStartTime
		print(string.format(
			"[ClientGameManager] PreloadAssets %s complete. candidates=%d failed=%d elapsed=%.2fs",
			priorityName,
			#assetList,
			bucketFailedAssetCount,
			bucketElapsedTime
		))
	end

	for _, folder: Instance in folderList do
		for _, descendant: Instance in folder:GetDescendants() do
			local defaultPriority = GetDefaultPreloadPriority(descendant)
			if descendant:IsA("MeshPart") then
				RegisterAssetForPreload(descendant, "Mesh", descendant.MeshId, defaultPriority)
				RegisterAssetForPreload(descendant, "Decal", descendant.TextureID, defaultPriority)
			elseif descendant:IsA("SpecialMesh") then
				RegisterAssetForPreload(descendant, "Mesh", descendant.MeshId, defaultPriority)
				RegisterAssetForPreload(descendant, "Decal", descendant.TextureId, defaultPriority)
			elseif descendant:IsA("Decal") then
				RegisterAssetForPreload(descendant, "Decal", descendant.Texture, defaultPriority)
			elseif descendant:IsA("Texture") then
				RegisterAssetForPreload(descendant, "Decal", descendant.Texture, defaultPriority)
			elseif descendant:IsA("Sound") then
				RegisterAssetForPreload(descendant, "Sound", descendant.SoundId, defaultPriority)
			elseif descendant:IsA("Animation") then
				RegisterAssetForPreload(descendant, "Animation", descendant.AnimationId, defaultPriority)
			elseif descendant:IsA("ParticleEmitter") then
				RegisterAssetForPreload(descendant, "Decal", descendant.Texture, defaultPriority)
			elseif descendant:IsA("Beam") then
				RegisterAssetForPreload(descendant, "Decal", descendant.Texture, defaultPriority)
			elseif descendant:IsA("ImageLabel") then
				RegisterAssetForPreload(descendant, "Image", descendant.Image, defaultPriority)
			elseif descendant:IsA("ImageButton") then
				RegisterAssetForPreload(descendant, "Image", descendant.Image, defaultPriority)
			end
		end
	end
	--预加载GameConfig图片资源
	local otherImageList: { string } = {}
	table.insert(otherImageList, GameConfig.CoinIconImage)
	table.insert(otherImageList, GameConfig.RbImage)
	table.insert(otherImageList, GameConfig.DecelerationOnImage)
	table.insert(otherImageList, GameConfig.DecelerationOffImage)
	for _, buffData in pairs(GameConfig.Buffs) do
		RegisterConfigImageForPreload(buffData.iconImageId, PreloadPriority.P1)
	end
	for _, bgIconId in pairs(GameConfig.ShopBundleBgIconIdById) do
		RegisterConfigImageForPreload(bgIconId, PreloadPriority.P1)
	end

	for _, otherImage: string in otherImageList do
		RegisterConfigImageForPreload(otherImage, PreloadPriority.P0)
	end

	PreloadBucket(PreloadPriority.P0)
	preloadP0Complete = true
	PreloadBucket(PreloadPriority.P1)
	PreloadBucket(PreloadPriority.P2)

	local allAssetList: { Instance } = {}
	for _, priority in ipairs({ PreloadPriority.P0, PreloadPriority.P1, PreloadPriority.P2 }) do
		local bucket = assetBucketMap[priority]
		if bucket ~= nil then
			for _, instance: Instance in ipairs(bucket) do
				table.insert(allAssetList, instance)
			end
		end
	end

	for _, instance: Instance in ipairs(allAssetList) do
		instance:Destroy()
	end
	table.clear(allAssetList)

	local elapsedTime = os.clock() - preloadStartTime
	local totalAssetCount = 0
	for _, priority in ipairs({ PreloadPriority.P0, PreloadPriority.P1, PreloadPriority.P2 }) do
		local bucket = assetBucketMap[priority]
		if bucket ~= nil then
			totalAssetCount += #bucket
		end
	end
	if elapsedTime >= PreloadSlowBatchWarnSeconds then
		warn(string.format("[ClientGameManager] PreloadAssets complete. candidates=%d failed=%d elapsed=%.2fs", totalAssetCount, failedAssetCount, elapsedTime))
	end
	if failedAssetCount > 0 then
		warn(string.format(
			"[ClientGameManager] PreloadAssets failed. candidates=%d failed=%d sample=%s",
			totalAssetCount,
			failedAssetCount,
			table.concat(failedAssetList, ", ")
		))
	end
	table.clear(failedAssetList)
end

local function OnNotifyPlayersOtherPlayerInfoInit(playerId: number, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo)
	if playerId ~= players.LocalPlayer.UserId then
		ClientGameInfo.InitOtherPlayerInfo(playerId, otherPlayerSaveInfo)
	end
end

local function OnNotifyPlayerAcquiredGamePass(gamePassId: number)
	ClientGameInfo.SetLocalPlayerGamePassAcquired(gamePassId)
end

NetMsg.ConnectNotifyPlayerInfoInit(OnNotifyPlayerInfoInit)
NetMsg.ConnectNotifyPlayersOtherPlayerInfoInit(OnNotifyPlayersOtherPlayerInfoInit)
NetMsg.ConnectNotifyPlayerAcquiredGamePass(OnNotifyPlayerAcquiredGamePass)

--GraphicsPerformanceGuard.Init()

-- 监听库存同步消息 (持有物/持久化)
NetMsg.ConnectNotifyPlayerInventoryUpdate(function(inventoryInfo: GameConfig.PlayerInventorySaveInfo)
	ClientGameInfo.UpdateInventory(inventoryInfo)
end)

-- 监听 Brainrot 背包队列更新
NetMsg.ConnectNotifyBrainrotQueueUpdate(function(queue: { GameConfig.BrainrotQueueItem })
	ClientGameInfo.UpdateBrainrotQueue(queue)
end)

-- 监听搬运同步消息 (瞬态)
NetMsg.ConnectNotifyPlayerCarriedUpdate(function(carriedInfo: GameConfig.PlayerCarriedInfo)
	ClientGameInfo.UpdateCarriedInfo(carriedInfo)
end)

NetMsg.ConnectNotifyPlayerSkillLevelUpdate(function(skillType, level)
	ClientGameInfo.UpdateSkillLevel(skillType, level)
end)

-- 监听家园信息更新
NetMsg.ConnectNotifyPlayerHomeInfoUpdate(function(playerId: number, homeSlot: string, homeInfo: any, rebirthLevel: number?)
	ClientGameInfo.UpdatePlayerHomeInfo(playerId, homeSlot, homeInfo, rebirthLevel)
end)

-- 监听模型收益更新
NetMsg.ConnectNotifyAllPlayersModelYields(function(allYields: { [string]: { [string]: number } })
	ClientGameInfo.UpdateAllPlayersModelYields(allYields)
end)

--监听货币更新
NetMsg.ConnectNotifyPlayerCurrencyUpdate(function(currencyType, totalAmount, lastChange, reason)
	ClientGameInfo.UpdateCurrency(currencyType, totalAmount, lastChange, reason)
end)

NetMsg.ConnectNotifyOfflineRewardInfo(function(offlineRewardInfo: GameConfig.OfflineRewardInfo?)
	ClientGameInfo.SetOfflineRewardInfo(offlineRewardInfo)
	if offlineRewardInfo ~= nil and offlineRewardInfo.baseReward > 0 then
		TryOpenOfflineRewardsWindow()
	elseif UIManager.GetGameScreenGui() ~= nil then
		UIManager.CloseWindow(UIManager.WindowId.OfflineRewards)
	end
end)

NetMsg.ConnectNotifyPlayerBuffInfoUpdate(function(buffInfo: GameConfig.BuffInfo, grantBuffId: number?, shopBundleId: number?)
	ClientGameInfo.UpdateBuffInfo(buffInfo, grantBuffId, shopBundleId)
end)

-- 监听网络层出的游戏提示
NetMsg.ConnectNotifyShowGameTip(function(tipContentSource, tweenType, tipContentKey, tipContentArgs, textColor)
	ClientMsg.FireShowGameTip(tipContentSource, tweenType, tipContentKey, tipContentArgs, textColor)
end)

NetMsg.ConnectNotifyPlayerRewardUpdate(function(indexs, stateNew, rewardType)
	ClientGameInfo.UpdateRewardState(indexs, stateNew, rewardType)
end)

NetMsg.ConnectNotifyPlayersInitPlayerRewardInfo(function(rewardInfo)
	ClientGameInfo.InitPlayerRewardInfo(rewardInfo)
end)

NetMsg.ConnectNotifyPlayerNewDay(function(_lastLoginTime, _gameTime, startGameTick)
	ClientGameInfo.UpdateStartGameTick(startGameTick)
end)

-- 客户端启动时立即异步预加载资源，不阻塞初始化流程
task.spawn(function()
	PreloadAssets()
end)

IdleInputClientManager.Init()
-- 尽早隐藏自身赠礼按钮，避免玩家信息与资源加载完成前 ProximityPrompt 闪现
PlayerInteractClientManager.InitEarly()
