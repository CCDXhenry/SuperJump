--!strict
-- JumpRunWayFrame 窗口壳：与 WindowConfigs 配对；CloseWindow 时自毁（与 SellShop / UpgradeShop 一致）

local thisFrame = script.Parent :: Frame
local windowId = thisFrame:GetAttribute("WindowId") :: string

local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:WaitForChild("ClientMsg"))

local RATING_ROOT_ZINDEX = 92

thisFrame.ZIndex = RATING_ROOT_ZINDEX

local holder = thisFrame:WaitForChild("Holder") :: Frame
local ratingText = holder:WaitForChild("RatingText") :: TextLabel
ratingText.Visible = false

local function OnCloseWindow(closeWindowId: string)
	if closeWindowId == windowId then
		thisFrame:Destroy()
	end
end

ClientMsg.ConnectCloseWindow(OnCloseWindow)
