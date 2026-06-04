--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local UIManager = require(clientScripts:FindFirstChild("UIManager"))

local thisFrame: Frame = script.Parent :: Frame
local windowId: string = thisFrame:GetAttribute("WindowId") :: string
local closeButton: ImageButton = thisFrame:FindFirstChild("CloseButton") :: ImageButton

closeButton.Visible = false

local function OnCloseWindow(closeWindowId: string)
	if closeWindowId == windowId then
		UIAdapter.RemoveAdaptiveFrame(thisFrame)
		thisFrame:Destroy()
	end
end

UIAdapter.AddAdaptiveFrame(thisFrame, UIAdapter.AdaptiveType.FullScreen)
ClientMsg.ConnectCloseWindow(OnCloseWindow)

-- 服务端主动结束锻炼时的兜底关闭
NetMsg.ConnectNotifyExerciseEnd(function()
	UIManager.CloseWindow(windowId)
end)
