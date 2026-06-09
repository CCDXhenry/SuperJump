--!strict
local runService = game:GetService("RunService")

local BillboardManager = {}
local infoGuis: { BillboardGui } = {}
local infoGuiIndexMap: { [BillboardGui]: number } = {}
local MAX_INFO_UI_SCALE = 1.2

local function RemoveInfoGuiByIndex(index: number)
	local lastIndex = #infoGuis
	local removedGui = infoGuis[index]
	local lastGui = infoGuis[lastIndex]
	if index ~= lastIndex then
		infoGuis[index] = lastGui
		infoGuiIndexMap[lastGui] = index
	end
	infoGuis[lastIndex] = nil
	infoGuiIndexMap[removedGui] = nil
end

local function RemoveInfoGui(gui: BillboardGui)
	local index = infoGuiIndexMap[gui]
	if index == nil then
		return
	end
	RemoveInfoGuiByIndex(index)
end

local function UpdateSingleInfoScale(infoUI: BillboardGui)
	local controllerFrame = infoUI:FindFirstChild("ControllerFrame")
	if controllerFrame == nil or not controllerFrame:IsA("Frame") then
		return
	end
	local uiScale = controllerFrame:FindFirstChild("UIScale")
	if uiScale == nil or not uiScale:IsA("UIScale") then
		return
	end
	local controllerWidth = controllerFrame.Size.X.Offset
	local controllerHeight = controllerFrame.Size.Y.Offset
	if controllerWidth <= 0 or controllerHeight <= 0 then
		return
	end
	local rawScale = math.min(
		infoUI.AbsoluteSize.X / controllerWidth,
		infoUI.AbsoluteSize.Y / controllerHeight
	)
	local nextScale = math.min(rawScale, MAX_INFO_UI_SCALE)
	if math.abs(uiScale.Scale - nextScale) > 0.001 then
		uiScale.Scale = nextScale
	end
end

local function UpdateAllInfoScales()
	local index = 1
	while index <= #infoGuis do
		local infoUI = infoGuis[index]
		if infoUI.Parent == nil then
			RemoveInfoGuiByIndex(index)
			continue
		end

		local adornee = infoUI.Adornee
		-- Adornee 在类型定义里可能为非可选 Instance；仅用 Parent 判断是否仍挂在场景里
		if not adornee.Parent then
			RemoveInfoGuiByIndex(index)
			infoUI:Destroy()
			continue
		end

		UpdateSingleInfoScale(infoUI)
		index += 1
	end
end

function BillboardManager.Track(gui: BillboardGui)
	if infoGuiIndexMap[gui] ~= nil then
		return
	end
	table.insert(infoGuis, gui)
	infoGuiIndexMap[gui] = #infoGuis
	UpdateSingleInfoScale(gui)
end

function BillboardManager.Untrack(gui: BillboardGui)
	RemoveInfoGui(gui)
end

runService.RenderStepped:Connect(UpdateAllInfoScales)

return BillboardManager
