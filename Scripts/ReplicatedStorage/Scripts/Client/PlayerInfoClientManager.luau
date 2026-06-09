--!strict
local PlayerInfoClientManager = {}

local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local NumberExtension = require(coreSharedScripts:WaitForChild("NumberExtension"))

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")
local coreClientScripts = coreScripts:WaitForChild("Client")
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local TranslationTool = require(coreClientScripts:WaitForChild("TranslationTool"))
local ClientGameInfo = require(clientScripts:WaitForChild("ClientGameInfo"))
local ClientMsg = require(clientScripts:WaitForChild("ClientMsg"))
local BillboardManager = require(clientScripts:WaitForChild("BillboardManager"))

local localPlayer = players.LocalPlayer
local uiFolder = replicatedStorage:WaitForChild("UI")
local playerInfoUITemplate = uiFolder:WaitForChild("PlayerInfoUI") :: BillboardGui

local JUMP_RUNWAY_BEST_DISTANCE_ATTR = "JumpRunwayBestDistance"
local BILLBOARD_TRACKED_ATTR = "BillboardTracked"
local PLAYER_INFO_UI_NAME = "PlayerInfoUI"
local HEAD_UI_MAX_DISTANCE = 100

type PlayerHeadUiState = {
	billboardGui: BillboardGui?,
	attrConn: RBXScriptConnection?,
}

local playerStateMap: { [number]: PlayerHeadUiState } = {}

local function EnsureBillboardTracked(gui: BillboardGui)
	if gui:GetAttribute(BILLBOARD_TRACKED_ATTR) ~= true then
		gui:SetAttribute(BILLBOARD_TRACKED_ATTR, true)
	end
	BillboardManager.Track(gui)
end

local function SetupBillboardAdaptation(gui: BillboardGui)
	local controller = gui:FindFirstChild("ControllerFrame") :: Frame?
	if controller == nil then
		return
	end

	local uiScale = controller:FindFirstChildOfClass("UIScale")
	if uiScale == nil then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "UIScale"
		uiScale.Parent = controller
	end

	if controller.Size.X.Scale > 0 or controller.Size.Y.Scale > 0 then
		local absSize = controller.AbsoluteSize
		if absSize.X > 0 and absSize.Y > 0 then
			controller.Size = UDim2.fromOffset(absSize.X, absSize.Y)
		end
	end

	EnsureBillboardTracked(gui)
end

local function GetPlayerBestDistance(player: Player): number
	if player == localPlayer then
		local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
		if localPlayerInfo ~= nil then
			return localPlayerInfo.jumpRunwayBestDistance
		end
	end

	local attrValue = player:GetAttribute(JUMP_RUNWAY_BEST_DISTANCE_ATTR)
	if type(attrValue) == "number" then
		return attrValue
	end
	return 0
end

local function GetPlayerDisplayName(player: Player): string
	if player.DisplayName ~= "" then
		return player.DisplayName
	end
	return player.Name
end

local function UpdatePlayerInfoLabels(player: Player, billboardGui: BillboardGui)
	local controllerFrame = billboardGui:FindFirstChild("ControllerFrame") :: Frame?
	if controllerFrame == nil then
		return
	end

	local playerNameLabel = controllerFrame:FindFirstChild("PlayerName") :: TextLabel?
	if playerNameLabel ~= nil then
		playerNameLabel.Text = GetPlayerDisplayName(player)
	end

	local distanceFrame = controllerFrame:FindFirstChild("DistanceFrame") :: Frame?
	local maxDistanceLabel = if distanceFrame ~= nil
		then distanceFrame:FindFirstChild("MaxDistance") :: TextLabel?
		else nil
	if maxDistanceLabel ~= nil then
		local displayDistance = math.max(0, math.floor(GetPlayerBestDistance(player) + 0.5))
		TranslationTool.CustomAutoLocalizeTextLabel(
			maxDistanceLabel,
			GameTexts.JumpRunwayDistanceMeters.source,
			GameTexts.JumpRunwayDistanceMeters.key,
			{ NumberExtension.FormatBigNumberAA(displayDistance) }
		)
	end
end

local function ClearPlayerHeadBillboard(player: Player)
	local state = playerStateMap[player.UserId]
	if state == nil then
		return
	end

	local billboardGui = state.billboardGui
	if billboardGui ~= nil then
		BillboardManager.Untrack(billboardGui)
		billboardGui:Destroy()
		state.billboardGui = nil
	end
end

local function DestroyPlayerHeadUi(player: Player)
	local state = playerStateMap[player.UserId]
	if state == nil then
		return
	end

	if state.attrConn ~= nil then
		state.attrConn:Disconnect()
		state.attrConn = nil
	end

	ClearPlayerHeadBillboard(player)
end

local function AttachPlayerHeadUi(player: Player, character: Model)
	ClearPlayerHeadBillboard(player)

	local adornee = character:FindFirstChild("Head") :: BasePart?
	if adornee == nil then
		adornee = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	if adornee == nil then
		return
	end

	local billboardGui = playerInfoUITemplate:Clone()
	billboardGui.Name = PLAYER_INFO_UI_NAME
	billboardGui.Adornee = adornee
	billboardGui.AlwaysOnTop = false
	billboardGui.MaxDistance = HEAD_UI_MAX_DISTANCE
	billboardGui.Parent = character

	SetupBillboardAdaptation(billboardGui)
	UpdatePlayerInfoLabels(player, billboardGui)

	local state = playerStateMap[player.UserId]
	if state ~= nil then
		state.billboardGui = billboardGui
	end
end

local function RefreshPlayerInfoUi(player: Player)
	local state = playerStateMap[player.UserId]
	if state == nil or state.billboardGui == nil then
		return
	end
	UpdatePlayerInfoLabels(player, state.billboardGui)
end

local function BindPlayer(player: Player)
	if playerStateMap[player.UserId] ~= nil then
		return
	end

	playerStateMap[player.UserId] = {
		billboardGui = nil,
		attrConn = player:GetAttributeChangedSignal(JUMP_RUNWAY_BEST_DISTANCE_ATTR):Connect(function()
			RefreshPlayerInfoUi(player)
		end),
	}

	local function onCharacterAdded(character: Model)
		AttachPlayerHeadUi(player, character)
	end

	local function onCharacterRemoving()
		ClearPlayerHeadBillboard(player)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(onCharacterRemoving)

	if player.Character ~= nil then
		task.defer(onCharacterAdded, player.Character)
	end
end

local function UnbindPlayer(player: Player)
	DestroyPlayerHeadUi(player)
	playerStateMap[player.UserId] = nil
end

function PlayerInfoClientManager.Init()
	for _, player in ipairs(players:GetPlayers()) do
		BindPlayer(player)
	end

	players.PlayerAdded:Connect(BindPlayer)
	players.PlayerRemoving:Connect(UnbindPlayer)

	ClientMsg.ConnectLocalPlayerInfoInit(function()
		RefreshPlayerInfoUi(localPlayer)
	end)

	ClientMsg.ConnectLocalPlayerJumpRunwayBestDistanceUpdate(function()
		RefreshPlayerInfoUi(localPlayer)
	end)
end

return PlayerInfoClientManager
