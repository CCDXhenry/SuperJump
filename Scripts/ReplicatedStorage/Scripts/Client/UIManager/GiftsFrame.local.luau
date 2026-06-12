--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))
local TranslationTool = require(coreClientScripts:FindFirstChild("TranslationTool"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))

local localPlayerInfo: GameConfig.ClientLocalPlayerInfo? = ClientGameInfo.GetLocalPlayerInfo()
if localPlayerInfo == nil then
	return
end

local GIFT_CONFIRM_TITLE_COLOR = Color3.fromRGB(0, 255, 0)
local GIFT_REQUEST_TITLE_COLOR = Color3.fromRGB(0, 0, 255)
local TOP_TIP_DEFAULT_COLOR = Color3.fromRGB(255, 255, 255)
local TOP_TIP_SUCCESS_COLOR = Color3.fromRGB(0, 255, 0)
local GIFT_POPUP_COUNTDOWN_TIME = 10
local GIFT_TOP_TIP_DURATION = 5

local giftsFrame: Frame = script.Parent
local popUpTipFrame: Frame? = giftsFrame:FindFirstChild("PopUpTipFrame") :: Frame
local popUpYesButton: TextButton?
local popUpNoButton: TextButton?
local popUpTitleLabel: TextLabel?
local popUpTipInfoLabel: TextLabel?
local popUpTimeLabel: TextLabel?

local activePopUpConnectionYes: RBXScriptConnection?
local activePopUpConnectionNo: RBXScriptConnection?
local popUpCountdownCoroutine: thread?

if popUpTipFrame then
	popUpYesButton = popUpTipFrame:FindFirstChild("YesButton") :: TextButton
	popUpNoButton = popUpTipFrame:FindFirstChild("NoButton") :: TextButton
	popUpTitleLabel = popUpTipFrame:FindFirstChild("TitleLabel") :: TextLabel
	popUpTipInfoLabel = popUpTipFrame:FindFirstChild("TipInfoLabel") :: TextLabel
	if popUpYesButton then
		popUpTimeLabel = popUpYesButton:FindFirstChild("TimeLabel") :: TextLabel
	end
	popUpTipFrame.Visible = false
end

local function HidePopUpTipFrame()
	if popUpTipFrame then
		popUpTipFrame.Visible = false
	end
	if activePopUpConnectionYes then
		activePopUpConnectionYes:Disconnect()
		activePopUpConnectionYes = nil
	end
	if activePopUpConnectionNo then
		activePopUpConnectionNo:Disconnect()
		activePopUpConnectionNo = nil
	end
	if popUpCountdownCoroutine and coroutine.status(popUpCountdownCoroutine) ~= "dead" and popUpCountdownCoroutine ~= coroutine.running() then
		coroutine.close(popUpCountdownCoroutine)
		popUpCountdownCoroutine = nil
	end
end

local function StartPopUpCountdown(targetTimeLabel: TextLabel?, timeoutCallback: () -> ())
	if not targetTimeLabel then
		return
	end
	if popUpCountdownCoroutine and coroutine.status(popUpCountdownCoroutine) ~= "dead" and popUpCountdownCoroutine ~= coroutine.running() then
		coroutine.close(popUpCountdownCoroutine)
	end
	local newCoroutine = coroutine.create(function()
		for i = GIFT_POPUP_COUNTDOWN_TIME, 0, -1 do
			TranslationTool.CustomAutoLocalizeTextLabel(
				targetTimeLabel,
				GameTexts.CountdownFormat.source,
				GameTexts.CountdownFormat.key,
				{ tostring(i) }
			)
			task.wait(1)
		end
		timeoutCallback()
	end)
	popUpCountdownCoroutine = newCoroutine
	coroutine.resume(newCoroutine)
end

local function OnShowGiftConfirmPopup(targetPlayerId: number, targetPlayerName: string, brainrotInstanceId: string, giftName: string)
	if not popUpTipFrame or not popUpYesButton or not popUpNoButton or not popUpTitleLabel or not popUpTipInfoLabel then
		return
	end
	HidePopUpTipFrame()
	popUpTipFrame.Visible = true
	popUpTitleLabel.TextColor3 = GIFT_CONFIRM_TITLE_COLOR

	TranslationTool.CustomAutoLocalizeTextLabel(popUpTitleLabel, GameTexts.GiftConfirmTitle.source, GameTexts.GiftConfirmTitle.key)
	TranslationTool.CustomAutoLocalizeTextLabel(
		popUpTipInfoLabel,
		GameTexts.GiftConfirmBody.source,
		GameTexts.GiftConfirmBody.key,
		{ giftName, targetPlayerName }
	)

	activePopUpConnectionYes = popUpYesButton.MouseButton1Click:Connect(function()
		NetMsg.FireRequestSendGift(targetPlayerId, brainrotInstanceId)
		HidePopUpTipFrame()
		ClientMsg.FireShowTopTipText(
			GameTexts.GiftRequestSent.source,
			TOP_TIP_DEFAULT_COLOR,
			GIFT_TOP_TIP_DURATION,
			{ targetPlayerName },
			GameTexts.GiftRequestSent.key
		)
	end)
	activePopUpConnectionNo = popUpNoButton.MouseButton1Click:Connect(function()
		HidePopUpTipFrame()
	end)
	StartPopUpCountdown(popUpTimeLabel, function()
		HidePopUpTipFrame()
	end)
end

local function OnShowGiftRequestPopup(senderId: number, senderName: string, brainrotName: string, brainrotLevel: number)
	if not popUpTipFrame or not popUpYesButton or not popUpNoButton or not popUpTitleLabel or not popUpTipInfoLabel then
		return
	end
	HidePopUpTipFrame()
	popUpTipFrame.Visible = true
	popUpTitleLabel.TextColor3 = GIFT_REQUEST_TITLE_COLOR

	TranslationTool.CustomAutoLocalizeTextLabel(popUpTitleLabel, GameTexts.GiftRequestTitle.source, GameTexts.GiftRequestTitle.key)
	TranslationTool.CustomAutoLocalizeTextLabel(
		popUpTipInfoLabel,
		GameTexts.GiftRequestBody.source,
		GameTexts.GiftRequestBody.key,
		{ senderName, brainrotName, tostring(brainrotLevel) }
	)

	activePopUpConnectionYes = popUpYesButton.MouseButton1Click:Connect(function()
		NetMsg.FireRequestRespondGift(senderId, true)
		HidePopUpTipFrame()
		ClientMsg.FireShowTopTipText(
			GameTexts.GiftSuccess.source,
			TOP_TIP_SUCCESS_COLOR,
			GIFT_TOP_TIP_DURATION,
			nil,
			GameTexts.GiftSuccess.key
		)
	end)
	activePopUpConnectionNo = popUpNoButton.MouseButton1Click:Connect(function()
		NetMsg.FireRequestRespondGift(senderId, false)
		HidePopUpTipFrame()
	end)
	StartPopUpCountdown(popUpTimeLabel, function()
		HidePopUpTipFrame()
	end)
end

UIAdapter.AddAdaptiveFrame(giftsFrame, UIAdapter.AdaptiveType.FullScreen)

ClientMsg.ConnectShowGiftConfirmPopup(OnShowGiftConfirmPopup)
ClientMsg.ConnectShowGiftRequestPopup(OnShowGiftRequestPopup)
