--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local NumberExtension = require(coreSharedScripts:WaitForChild("NumberExtension"))
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:WaitForChild("UIAdapter"))
local TranslationTool = require(coreClientScripts:WaitForChild("TranslationTool"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local ClientGameTool = require(clientScripts:FindFirstChild("ClientGameTool"))
local UIManager = require(clientScripts:WaitForChild("UIManager"))
local ClientMsg = require(clientScripts:WaitForChild("ClientMsg"))
local sharedScripts = scripts:WaitForChild("Shared")
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local ClientGameInfo = require(clientScripts:WaitForChild("ClientGameInfo"))

local thisFrame: Frame = script.Parent
local windowId: string = thisFrame:GetAttribute("WindowId") :: string
local closeButton: ImageButton = thisFrame:WaitForChild("CloseButton") :: ImageButton
local gridFrame = thisFrame:WaitForChild("GridFrame") :: Frame
local rewardFramePre = gridFrame:WaitForChild("RewardFrame") :: Frame
local rewardButtonTexts: { [number]: TextLabel } = {}
local rewardButtons: { [number]: ImageButton } = {}

if ClientGameInfo.GetLocalPlayerInfo() == nil then
	return
end

local function IsRewardClaimable(localPlayerInfo: GameConfig.ClientLocalPlayerInfo, index: number): boolean
	local state = localPlayerInfo.rewardInfo.onlineRewardStateInfo[tostring(index)]
	if state == GameConfig.RewardState.HasGot then
		return false
	end
	if state == GameConfig.RewardState.CanGet then
		return true
	end
	return ClientGameInfo.GetTodayGameTimeNow() >= GameConfig.OnlineRewardDataList[index].unlockTime
end

local function CollectClaimableIndexes(localPlayerInfo: GameConfig.ClientLocalPlayerInfo): { number }
	local indexs: { number } = {}
	for i = 1, #GameConfig.OnlineRewardDataList do
		if IsRewardClaimable(localPlayerInfo, i) then
			table.insert(indexs, i)
		end
	end
	return indexs
end

-- Reserved for a future claim-all button; connect via Activated:Connect(_ClaimAllClaimableRewards).
local function _ClaimAllClaimableRewards()
	local currentPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if currentPlayerInfo == nil then
		return
	end
	local indexs = CollectClaimableIndexes(currentPlayerInfo)
	if #indexs == 0 then
		return
	end
	NetMsg.FireRequestUpdateReward(indexs, GameConfig.RewardState.HasGot, GameConfig.RewardEnum.onlineTime)
end

local function UpdateFrame()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil then
		return
	end
	for i = 1, #GameConfig.OnlineRewardDataList do
		local buttonText = rewardButtonTexts[i]
		local button = rewardButtons[i]
		if buttonText == nil or button == nil then
			continue
		end
		if IsRewardClaimable(localPlayerInfo, i) then
			button.ImageColor3 = Color3.new(0, 1, 0)
			buttonText.Text = "CLAIM"
			button.Active = true
		elseif localPlayerInfo.rewardInfo.onlineRewardStateInfo[tostring(i)] == GameConfig.RewardState.HasGot then
			button.Active = false
			buttonText.Text = "CLAIMED"
			button.ImageColor3 = Color3.new(0.3, 0.3, 0.3)
			local rewardFrame = button.Parent :: Frame
			local tickImage = rewardFrame:WaitForChild("TickImage") :: ImageLabel
			tickImage.Visible = true
		else
			button.Active = false
			button.ImageColor3 = Color3.new(1, 1, 1)
		end
	end
end

local function UpdateWaitText()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil then
		return
	end
	local todayGameTimeNow = ClientGameInfo.GetTodayGameTimeNow()
	for i = #GameConfig.OnlineRewardDataList, 1, -1 do
		local buttonText = rewardButtonTexts[i]
		if buttonText == nil then
			continue
		end
		local unlockTime = GameConfig.OnlineRewardDataList[i].unlockTime
		if
			todayGameTimeNow < unlockTime
			and localPlayerInfo.rewardInfo.onlineRewardStateInfo[tostring(i)] == nil
		then
			buttonText.Text = ClientGameTool.GetCountDownText(math.floor(unlockTime - todayGameTimeNow))
		end
	end
end

local function InitFrame()
	rewardFramePre.Visible = false
	for i, reward in GameConfig.OnlineRewardDataList do
		local rewardFrame = rewardFramePre:Clone()
		rewardFrame.Parent = gridFrame
		rewardFrame.Visible = true
		local currencyRewardImage: ImageLabel = rewardFrame:WaitForChild("RewardImage") :: ImageLabel
		local petFrame: Frame = rewardFrame:FindFirstChild("PetFrame") :: Frame
		local petRewardImage: ImageLabel = petFrame:FindFirstChild("Icon") :: ImageLabel
		local petName: TextLabel = petFrame:FindFirstChild("Name") :: TextLabel
		local petAbility: TextLabel = petFrame:FindFirstChild("Ability") :: TextLabel
		local rewardImage: ImageLabel
		if reward.rewardType == GameConfig.RewardType.Brainrot then
			local brainrotData = GameConfig.BrainrotIdMap[reward.rewardId]
			currencyRewardImage.Visible = false
			rewardImage = petRewardImage
			if brainrotData then
				TranslationTool.CustomAutoLocalizeTextLabel(petName, brainrotData.name_t, "")
				petAbility.Text = "x" .. NumberExtension.FormatBigNumberAA(brainrotData.baseAbility)
			end
		elseif reward.rewardType == GameConfig.RewardType.Currency then
			petFrame.Visible = false
			rewardImage = currencyRewardImage
		else
			petFrame.Visible = false
			rewardImage = currencyRewardImage
		end
		local countText = rewardFrame:WaitForChild("CountText") :: TextLabel
		ClientGameTool.SetRewardIconImage(rewardImage, reward.rewardType, reward.rewardId)
		countText.Text = "x" .. NumberExtension.FormatBigNumberAA(reward.rewardCount)
		if reward.rewardType == GameConfig.RewardType.Brainrot and reward.rewardCount == 1 then
			countText.Text = ""
		end
		local getRewardButton = rewardFrame:WaitForChild("GetRewardButton") :: ImageButton
		local buttonText = getRewardButton:WaitForChild("Text") :: TextLabel
		rewardButtonTexts[i] = buttonText
		rewardButtons[i] = getRewardButton
		getRewardButton.Activated:Connect(function()
			local currentPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
			if currentPlayerInfo == nil then
				return
			end
			if not IsRewardClaimable(currentPlayerInfo, i) then
				return
			end
			NetMsg.FireRequestUpdateReward({ i }, GameConfig.RewardState.HasGot, GameConfig.RewardEnum.onlineTime)
		end)
		if i == #GameConfig.OnlineRewardDataList then
			local bgImage = rewardFrame:WaitForChild("BgImage") :: ImageLabel
			bgImage.Image = "rbxassetid://131884504077448"
		end
	end
	UpdateFrame()
end

local function OnCloseButtonActivated()
	UIManager.CloseWindow(windowId)
end

local function OnCloseWindow(closeWindowId: string)
	if closeWindowId == windowId then
		UIAdapter.RemoveAdaptiveFrame(thisFrame)
		thisFrame:Destroy()
	end
end

local function OnRewardUpdate(stateNew: number, rewardType: number)
	if rewardType ~= GameConfig.RewardEnum.onlineTime then
		return
	end
	UpdateFrame()
end

UIAdapter.AddAdaptiveFrame(thisFrame, UIAdapter.AdaptiveType.Center)
InitFrame()
closeButton.Activated:Connect(OnCloseButtonActivated)
ClientMsg.ConnectCloseWindow(OnCloseWindow)
ClientMsg.ConnectRewardUpdate(OnRewardUpdate)
NetMsg.ConnectNotifyPlayerNewDay(OnCloseButtonActivated)

while true do
	UpdateFrame()
	UpdateWaitText()
	task.wait(1)
end
