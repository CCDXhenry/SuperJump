--!strict
local PlayerInteractClientManager = {}

local players = game:GetService("Players")
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local TranslationTool = require(coreClientScripts:FindFirstChild("TranslationTool"))

local localPlayer = players.LocalPlayer

-- 常量定义
local FAILURE_TIPS_COLOR = Color3.fromRGB(255, 0, 0) -- 红色
local FAILURE_TIPS_DURATION = 3

local isPromptControlReady = false
local isEarlyInitDone = false

local function HasBrainrot(character: Model?): boolean
	if not character then return false end
	if character:FindFirstChild("CarryingBrainrot") then return true end
	local tool = character:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("BrainrotUID") then return true end
	return false
end

local function DisableLocalPlayerInteractPrompt(character: Model?)
	if not character then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local attachment = hrp:FindFirstChild("PlayerInteractAttachment")
	if not attachment then
		return
	end
	local prompt = attachment:FindFirstChild("PlayerInteractPrompt") :: ProximityPrompt?
	if prompt then
		prompt.Enabled = false
	end
end

local function BindLocalCharacterPromptHide(character: Model)
	DisableLocalPlayerInteractPrompt(character)
	local hrp = character:WaitForChild("HumanoidRootPart", 5)
	if not hrp then
		return
	end
	local attachment = hrp:WaitForChild("PlayerInteractAttachment", 5)
	if not attachment then
		return
	end
	DisableLocalPlayerInteractPrompt(character)
	attachment.ChildAdded:Connect(function(child: Instance)
		if child.Name == "PlayerInteractPrompt" then
			(child :: ProximityPrompt).Enabled = false
		end
	end)
end

local function UpdateInteractionPrompts()
	local localCharacter = localPlayer.Character
	local hasLocalBrainrot = if GameConfig.EnablePlayerGift and isPromptControlReady then HasBrainrot(localCharacter) else false
	
	for _, otherPlayer in ipairs(players:GetPlayers()) do
		if otherPlayer.Character then
			local hrp = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local attachment = hrp:FindFirstChild("PlayerInteractAttachment")
				if attachment then
					local prompt = attachment:FindFirstChild("PlayerInteractPrompt") :: ProximityPrompt?
					if prompt then
						if otherPlayer.UserId == localPlayer.UserId then
							prompt.Enabled = false
							continue
						end
						if not isPromptControlReady or not GameConfig.EnablePlayerGift then
							prompt.Enabled = false
							continue
						end
						local hasOtherBrainrot = HasBrainrot(otherPlayer.Character)
						local canGift = hasLocalBrainrot and not hasOtherBrainrot
						prompt.Enabled = canGift
						if canGift then
							TranslationTool.CustomAutoLocalizeProximityPrompt(prompt, GameTexts.GiftAction.source, GameTexts.GiftAction.key)
						end
					end
				end
			end
		end
	end
end

function PlayerInteractClientManager.InitEarly()
	if isEarlyInitDone then
		return
	end
	isEarlyInitDone = true

	if localPlayer.Character then
		task.spawn(BindLocalCharacterPromptHide, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(function(character: Model)
		task.spawn(BindLocalCharacterPromptHide, character)
	end)

	runService.Heartbeat:Connect(function()
		UpdateInteractionPrompts()
	end)
end

function PlayerInteractClientManager.Init()
	isPromptControlReady = true
	UpdateInteractionPrompts()

	if GameConfig.EnablePlayerGift then
		NetMsg.ConnectNotifyShowGiftConfirm(function(targetPlayerId: number, targetPlayerName: string, brainrotInstanceId: string, giftName: string)
			ClientMsg.FireShowGiftConfirmPopup(targetPlayerId, targetPlayerName, brainrotInstanceId, giftName)
		end)

		NetMsg.ConnectNotifyReceiveGiftRequest(function(senderId: number, senderName: string, brainrotName: string, brainrotLevel: number)
			ClientMsg.FireShowGiftRequestPopup(senderId, senderName, brainrotName, brainrotLevel)
		end)

		NetMsg.ConnectNotifyGiftResult(function(isSuccess: boolean, message: string?)
			if not isSuccess then
				ClientMsg.FireShowTopTipText(
					GameTexts.GiftFailedFormat.source,
					FAILURE_TIPS_COLOR,
					FAILURE_TIPS_DURATION,
					{ message or "error" },
					GameTexts.GiftFailedFormat.key
				)
			end
		end)
	end
end

return PlayerInteractClientManager
