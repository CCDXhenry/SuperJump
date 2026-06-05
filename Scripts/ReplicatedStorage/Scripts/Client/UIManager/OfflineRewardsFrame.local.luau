--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local marketplaceService: MarketplaceService = game:GetService("MarketplaceService")
local players: Players = game:GetService("Players")

local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local NumberExtension = require(coreSharedScripts:FindFirstChild("NumberExtension"))
local coreClientScripts = coreScripts:WaitForChild("Client")
local TranslationTool = require(coreClientScripts:FindFirstChild("TranslationTool"))

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local UIManager = require(clientScripts:FindFirstChild("UIManager"))

local offlineRewardsFrame: Frame = script.Parent :: Frame
local mainFrame: Frame = offlineRewardsFrame:FindFirstChild("MainFrame") :: Frame
local numberLabel: TextLabel = mainFrame:FindFirstChild("NumberLabel") :: TextLabel
local payReceiveButton: ImageButton = mainFrame:FindFirstChild("PayReceiveButton") :: ImageButton
local receiveButton: ImageButton = mainFrame:FindFirstChild("ReceiveButton") :: ImageButton
local receiveLabel: TextLabel = payReceiveButton:FindFirstChild("ReceiveLabel") :: TextLabel
local totalValueLabel: TextLabel? = payReceiveButton:FindFirstChild("TotalValueLabel") :: TextLabel?

local isClaiming = false

local function GetRewardInfo(): GameConfig.OfflineRewardInfo?
	return ClientGameInfo.GetOfflineRewardInfo()
end

local function SetButtonEnabled(button: GuiButton, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = enabled
end

local function RefreshView()
	local rewardInfo = GetRewardInfo()
	if rewardInfo == nil or rewardInfo.baseReward <= 0 then
		UIManager.CloseWindow(UIManager.WindowId.OfflineRewards)
		return
	end

	numberLabel.Text = NumberExtension.FormatBigNumberAA(rewardInfo.baseReward)
	TranslationTool.CustomAutoLocalizeTextLabel(
		receiveLabel,
		GameTexts.OfflineRewardReceiveMultiplier.source,
		GameTexts.OfflineRewardReceiveMultiplier.key,
		{ tostring(rewardInfo.paidReceiveMultiplier) }
	)
	if totalValueLabel then
		totalValueLabel.Text = NumberExtension.FormatBigNumberAA(rewardInfo.paidReward)
	end

	local hasProduct = rewardInfo.paidReceiveProductId > 0
	SetButtonEnabled(payReceiveButton, hasProduct)
end

local function ClaimNormalReward()
	if isClaiming then
		return
	end
	isClaiming = true
	SetButtonEnabled(receiveButton, false)
	NetMsg.FireRequestClaimOfflineReward()
end

local function PromptPaidReward()
	local rewardInfo = GetRewardInfo()
	if rewardInfo == nil or rewardInfo.paidReceiveProductId <= 0 then
		return
	end
	marketplaceService:PromptProductPurchase(players.LocalPlayer, rewardInfo.paidReceiveProductId)
end

local function OnCloseWindow(closeWindowId: string)
	if closeWindowId ~= UIManager.WindowId.OfflineRewards then
		return
	end
	offlineRewardsFrame:Destroy()
end

receiveButton.Activated:Connect(ClaimNormalReward)
payReceiveButton.Activated:Connect(PromptPaidReward)
ClientMsg.ConnectCloseWindow(OnCloseWindow)

NetMsg.ConnectNotifyOfflineRewardInfo(function(offlineRewardInfo: GameConfig.OfflineRewardInfo?)
	ClientGameInfo.SetOfflineRewardInfo(offlineRewardInfo)
	RefreshView()
end)

RefreshView()
