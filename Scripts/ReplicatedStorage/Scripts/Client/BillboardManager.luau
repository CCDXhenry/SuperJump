--!strict
local runService = game:GetService("RunService")

local BillboardManager = {}

type InfoGuiState = {
	index: number,
	controllerFrame: Frame?,
	shouldRestoreControllerVisible: boolean,
	lastWaitReason: string?,
}

local infoGuis: { BillboardGui } = {}
local infoGuiStateMap: { [BillboardGui]: InfoGuiState } = {}
local MAX_INFO_UI_SCALE = 1.2
local MIN_VALID_INFO_UI_SCALE = 0.01
local UPDATE_INTERVAL_SECONDS = 0.01
local MAX_UPDATES_PER_STEP = 24
local DEBUG_LOG_ENABLED = false
local updateElapsedSeconds = 0
local updateCursorIndex = 1

local function FormatVector2(value: Vector2): string
	return string.format("%.1f, %.1f", value.X, value.Y)
end

local function FormatUDim2Offset(value: UDim2): string
	return string.format("%d, %d", value.X.Offset, value.Y.Offset)
end

local function GetDebugName(inst: Instance): string
	local ok, fullName = pcall(function()
		return inst:GetFullName()
	end)
	if ok and type(fullName) == "string" then
		return fullName
	end
	return inst.Name
end

local function DebugLog(message: string)
	if not DEBUG_LOG_ENABLED then
		return
	end
	print(`[BillboardManager] {message}`)
end

local function GetBillboardPixelSize(infoUI: BillboardGui, useSizeFallback: boolean): Vector2?
	local absoluteSize = infoUI.AbsoluteSize
	if absoluteSize.X > 0 and absoluteSize.Y > 0 then
		return absoluteSize
	end

	if not useSizeFallback then
		return nil
	end

	local size = infoUI.Size
	if size.X.Offset > 0 and size.Y.Offset > 0 then
		return Vector2.new(size.X.Offset, size.Y.Offset)
	end

	return nil
end

local function GetControllerFrame(infoUI: BillboardGui): Frame?
	local controllerFrame = infoUI:FindFirstChild("ControllerFrame")
	if controllerFrame == nil or not controllerFrame:IsA("Frame") then
		return nil
	end
	return controllerFrame
end

local function CanScaleControllerFrame(controllerFrame: Frame): boolean
	local uiScale = controllerFrame:FindFirstChild("UIScale")
	return uiScale ~= nil
		and uiScale:IsA("UIScale")
		and controllerFrame.Size.X.Offset > 0
		and controllerFrame.Size.Y.Offset > 0
end

local function RestoreControllerVisible(infoUI: BillboardGui, state: InfoGuiState, reason: string)
	if not state.shouldRestoreControllerVisible then
		return
	end

	state.shouldRestoreControllerVisible = false
	state.lastWaitReason = nil
	local controllerFrame = state.controllerFrame
	if controllerFrame ~= nil and controllerFrame.Parent ~= nil then
		controllerFrame.Visible = true
		DebugLog(`restore ControllerFrame visible: gui={GetDebugName(infoUI)} reason={reason}`)
	end
end

local function RemoveInfoGuiByIndex(index: number)
	local lastIndex = #infoGuis
	local removedGui = infoGuis[index]
	local removedGuiState = infoGuiStateMap[removedGui]
	if removedGuiState ~= nil then
		RestoreControllerVisible(removedGui, removedGuiState, "removed")
	end
	local lastGui = infoGuis[lastIndex]
	if index ~= lastIndex then
		infoGuis[index] = lastGui
		local lastGuiState = infoGuiStateMap[lastGui]
		if lastGuiState ~= nil then
			lastGuiState.index = index
		end
	end
	infoGuis[lastIndex] = nil
	infoGuiStateMap[removedGui] = nil
end

local function RemoveInfoGui(gui: BillboardGui)
	local state = infoGuiStateMap[gui]
	if state == nil then
		return
	end
	RemoveInfoGuiByIndex(state.index)
end

local function UpdateSingleInfoScale(infoUI: BillboardGui, useSizeFallback: boolean): (boolean, string)
	local controllerFrame = GetControllerFrame(infoUI)
	if controllerFrame == nil then
		return false, "missing ControllerFrame"
	end
	local uiScale = controllerFrame:FindFirstChild("UIScale")
	if uiScale == nil or not uiScale:IsA("UIScale") then
		return false, "missing UIScale"
	end
	local controllerWidth = controllerFrame.Size.X.Offset
	local controllerHeight = controllerFrame.Size.Y.Offset
	if controllerWidth <= 0 or controllerHeight <= 0 then
		return false, `invalid ControllerFrame offset={FormatUDim2Offset(controllerFrame.Size)}`
	end
	local billboardSize = GetBillboardPixelSize(infoUI, useSizeFallback)
	if billboardSize == nil then
		return false,
			`invalid Billboard size absolute={FormatVector2(infoUI.AbsoluteSize)} offset={FormatUDim2Offset(infoUI.Size)} fallback={tostring(useSizeFallback)}`
	end
	local rawScale = math.min(
		billboardSize.X / controllerWidth,
		billboardSize.Y / controllerHeight
	)
	if rawScale < MIN_VALID_INFO_UI_SCALE then
		return false, `rawScale too small raw={string.format("%.4f", rawScale)}`
	end
	local nextScale = math.min(rawScale, MAX_INFO_UI_SCALE)
	if math.abs(uiScale.Scale - nextScale) > 0.001 then
		local oldScale = uiScale.Scale
		uiScale.Scale = nextScale
		DebugLog(
			`scale changed: gui={GetDebugName(infoUI)} old={string.format("%.4f", oldScale)} new={string.format("%.4f", nextScale)} raw={string.format("%.4f", rawScale)} billboardAbs={FormatVector2(infoUI.AbsoluteSize)} billboardOffset={FormatUDim2Offset(infoUI.Size)} controllerOffset={FormatUDim2Offset(controllerFrame.Size)} fallback={tostring(useSizeFallback)} visible={tostring(controllerFrame.Visible)}`
		)
	end
	return true, "ok"
end

local function RestoreControllerVisibleIfReady(infoUI: BillboardGui, state: InfoGuiState)
	if not state.shouldRestoreControllerVisible then
		return
	end

	local success, reason = UpdateSingleInfoScale(infoUI, false)
	if success then
		RestoreControllerVisible(infoUI, state, "scale ready")
	elseif state.lastWaitReason ~= reason then
		state.lastWaitReason = reason
		DebugLog(`wait restore: gui={GetDebugName(infoUI)} reason={reason}`)
	end
end

local function UpdateInfoScalesStep()
	local count = #infoGuis
	if count <= 0 then
		updateCursorIndex = 1
		return
	end
	if updateCursorIndex > count then
		updateCursorIndex = 1
	end

	local updated = 0
	while updated < MAX_UPDATES_PER_STEP and updateCursorIndex <= #infoGuis do
		local index = updateCursorIndex
		local infoUI = infoGuis[index]
		if infoUI.Parent == nil then
			RemoveInfoGuiByIndex(index)
			continue
		end

		local adornee = infoUI.Adornee
		-- BillboardGui 可以直接挂在 Part/Attachment 下；只有显式 Adornee 失效时才清理。
		if adornee ~= nil and not adornee.Parent then
			RemoveInfoGuiByIndex(index)
			infoUI:Destroy()
			continue
		end

		local state = infoGuiStateMap[infoUI]
		if state ~= nil and state.shouldRestoreControllerVisible then
			RestoreControllerVisibleIfReady(infoUI, state)
		elseif infoUI.Enabled then
			UpdateSingleInfoScale(infoUI, true)
		end
		updateCursorIndex += 1
		updated += 1
	end
end

local function OnRenderStepped(deltaTime: number)
	updateElapsedSeconds += deltaTime
	if updateElapsedSeconds < UPDATE_INTERVAL_SECONDS then
		return
	end
	updateElapsedSeconds = 0
	UpdateInfoScalesStep()
end

function BillboardManager.Track(gui: BillboardGui)
	if infoGuiStateMap[gui] ~= nil then
		return
	end
	table.insert(infoGuis, gui)
	local controllerFrame = GetControllerFrame(gui)
	local state: InfoGuiState = {
		index = #infoGuis,
		controllerFrame = controllerFrame,
		shouldRestoreControllerVisible = controllerFrame ~= nil
			and controllerFrame.Visible
			and CanScaleControllerFrame(controllerFrame),
		lastWaitReason = nil,
	}
	infoGuiStateMap[gui] = state
	DebugLog(
		`track: gui={GetDebugName(gui)} hideController={tostring(state.shouldRestoreControllerVisible)} guiEnabled={tostring(gui.Enabled)} billboardAbs={FormatVector2(gui.AbsoluteSize)} billboardOffset={FormatUDim2Offset(gui.Size)} controllerOffset={if controllerFrame ~= nil then FormatUDim2Offset(controllerFrame.Size) else "missing"}`
	)
	if state.shouldRestoreControllerVisible and controllerFrame ~= nil then
		controllerFrame.Visible = false
		DebugLog(`hide ControllerFrame before first stable scale: gui={GetDebugName(gui)}`)
	end

	if state.shouldRestoreControllerVisible then
		RestoreControllerVisibleIfReady(gui, state)
	else
		UpdateSingleInfoScale(gui, true)
	end
end

function BillboardManager.Untrack(gui: BillboardGui)
	RemoveInfoGui(gui)
end

runService.RenderStepped:Connect(OnRenderStepped)

return BillboardManager
