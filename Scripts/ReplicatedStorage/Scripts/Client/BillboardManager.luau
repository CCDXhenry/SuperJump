--!strict
local runService = game:GetService("RunService")

local BillboardManager = {}

type InfoGuiState = {
	index: number,
	controllerFrame: Frame?,
	isWaitingForStableScale: boolean,
	didHideControllerForWait: boolean,
	wasEnabled: boolean,
	lastBillboardSize: Vector2?,
	stableBillboardSizeFrameCount: number,
	lastWaitReason: string?,
	waitStartedAt: number?,
	postRestoreStableFrames: number,
}

local infoGuis: { BillboardGui } = {}
local infoGuiStateMap: { [BillboardGui]: InfoGuiState } = {}
local MAX_INFO_UI_SCALE = 1.2
local MIN_VALID_INFO_UI_SCALE = 0.01
-- 等待显示前，BillboardGui.AbsoluteSize 需连续稳定的渲染帧数（配合 ProcessWaitingGuis 每帧采样）。
-- 用于过滤 MaxDistance 进入视野时首帧尺寸异常，避免在未稳定时应用 UIScale 并显示。
local STABLE_INFO_SIZE_FRAME_COUNT = 3
local INFO_SIZE_EPSILON = 0.5
local INFO_SIZE_MAX_CHANGE_RATIO = 0.05
local MAX_STABLE_WAIT_SECONDS = 0.4
-- ControllerFrame 恢复可见后，仍需尺寸稳定才允许更新 UIScale 的帧数。
-- 防止显示瞬间 AbsoluteSize 再次跳变导致 UIScale 立刻修正而产生闪屏。
local POST_RESTORE_STABLE_FRAME_COUNT = 3
local UPDATE_INTERVAL_SECONDS = 0.01
local MAX_UPDATES_PER_STEP = 90
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
	return uiScale ~= nil and uiScale:IsA("UIScale") and controllerFrame.Size.X.Offset > 0 and controllerFrame.Size.Y.Offset > 0
end

local function IsSameBillboardSize(left: Vector2, right: Vector2): boolean
	return math.abs(left.X - right.X) <= INFO_SIZE_EPSILON and math.abs(left.Y - right.Y) <= INFO_SIZE_EPSILON
end

local function GetBillboardSizeChangeRatio(left: Vector2, right: Vector2): number
	local maxDim = math.max(left.X, left.Y, right.X, right.Y, 1)
	local dx = math.abs(left.X - right.X)
	local dy = math.abs(left.Y - right.Y)
	return math.max(dx, dy) / maxDim
end

local function ResetStableBillboardSize(state: InfoGuiState)
	state.lastBillboardSize = nil
	state.stableBillboardSizeFrameCount = 0
	state.lastWaitReason = nil
end

local function IsBillboardSizeStable(state: InfoGuiState, billboardSize: Vector2): boolean
	local lastBillboardSize = state.lastBillboardSize
	if lastBillboardSize ~= nil then
		if GetBillboardSizeChangeRatio(lastBillboardSize, billboardSize) > INFO_SIZE_MAX_CHANGE_RATIO then
			state.lastBillboardSize = billboardSize
			state.stableBillboardSizeFrameCount = 1
			return false
		end
		if IsSameBillboardSize(lastBillboardSize, billboardSize) then
			state.stableBillboardSizeFrameCount += 1
		else
			state.lastBillboardSize = billboardSize
			state.stableBillboardSizeFrameCount = 1
		end
	else
		state.lastBillboardSize = billboardSize
		state.stableBillboardSizeFrameCount = 1
	end
	return state.stableBillboardSizeFrameCount >= STABLE_INFO_SIZE_FRAME_COUNT
end

local RestoreControllerVisible: (BillboardGui, InfoGuiState, string) -> ()
local CancelStableScaleWait: (BillboardGui, InfoGuiState, string) -> ()
local FinishStableScaleWait: (BillboardGui, InfoGuiState, string) -> ()
local UpdateSingleInfoScale: (BillboardGui, boolean, InfoGuiState?, boolean) -> (boolean, string)
local RestoreControllerVisibleIfReady: (BillboardGui, InfoGuiState) -> ()
local RefreshEnabledStableScaleWait: (BillboardGui, InfoGuiState) -> ()

local function BeginStableScaleWait(infoUI: BillboardGui, state: InfoGuiState, controllerFrame: Frame, reason: string)
	state.controllerFrame = controllerFrame
	state.isWaitingForStableScale = true
	if state.waitStartedAt == nil then
		state.waitStartedAt = os.clock()
	end
	ResetStableBillboardSize(state)
	if controllerFrame.Visible then
		controllerFrame.Visible = false
		state.didHideControllerForWait = true
		DebugLog(`hide ControllerFrame before stable scale: gui={GetDebugName(infoUI)} reason={reason}`)
	end
end

RestoreControllerVisible = function(infoUI: BillboardGui, state: InfoGuiState, reason: string)
	if not state.didHideControllerForWait then
		return
	end

	local controllerFrame = state.controllerFrame
	if controllerFrame == nil or controllerFrame.Parent == nil then
		return
	end

	state.didHideControllerForWait = false
	state.lastWaitReason = nil
	controllerFrame.Visible = true
	DebugLog(`restore ControllerFrame visible: gui={GetDebugName(infoUI)} reason={reason}`)
end

CancelStableScaleWait = function(infoUI: BillboardGui, state: InfoGuiState, reason: string)
	if not state.isWaitingForStableScale then
		return
	end

	state.isWaitingForStableScale = false
	state.waitStartedAt = nil
	ResetStableBillboardSize(state)
	RestoreControllerVisible(infoUI, state, reason)
end

FinishStableScaleWait = function(infoUI: BillboardGui, state: InfoGuiState, reason: string)
	state.isWaitingForStableScale = false
	state.waitStartedAt = nil
	state.postRestoreStableFrames = POST_RESTORE_STABLE_FRAME_COUNT
	ResetStableBillboardSize(state)
	RestoreControllerVisible(infoUI, state, reason)
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

UpdateSingleInfoScale = function(infoUI: BillboardGui, useSizeFallback: boolean, state: InfoGuiState?, requireStableSize: boolean): (boolean, string)
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
	local needsStableSize = requireStableSize
	if state ~= nil and state.postRestoreStableFrames > 0 then
		needsStableSize = true
	end
	if needsStableSize and state ~= nil and not IsBillboardSizeStable(state, billboardSize) then
		return false, `waiting stable Billboard size current={FormatVector2(billboardSize)} frames={state.stableBillboardSizeFrameCount}`
	end
	local rawScale = math.min(billboardSize.X / controllerWidth, billboardSize.Y / controllerHeight)
	if rawScale < MIN_VALID_INFO_UI_SCALE then
		return false, `rawScale too small raw={string.format("%.4f", rawScale)}`
	end
	local nextScale = math.min(rawScale, MAX_INFO_UI_SCALE)
	if math.abs(uiScale.Scale - nextScale) > 0.001 then
		local oldScale = uiScale.Scale
		uiScale.Scale = nextScale
		DebugLog(
			`scale changed: gui={GetDebugName(infoUI)} old={string.format("%.4f", oldScale)} new={string.format("%.4f", nextScale)} raw={string.format(
				"%.4f",
				rawScale
			)} billboardAbs={FormatVector2(infoUI.AbsoluteSize)} billboardOffset={FormatUDim2Offset(infoUI.Size)} controllerOffset={FormatUDim2Offset(
				controllerFrame.Size
			)} fallback={tostring(useSizeFallback)} visible={tostring(controllerFrame.Visible)}`
		)
	end
	if state ~= nil and state.postRestoreStableFrames > 0 then
		state.postRestoreStableFrames -= 1
	end
	return true, "ok"
end

RestoreControllerVisibleIfReady = function(infoUI: BillboardGui, state: InfoGuiState)
	if not state.isWaitingForStableScale then
		return
	end

	local waitStartedAt = state.waitStartedAt
	if waitStartedAt ~= nil and os.clock() - waitStartedAt >= MAX_STABLE_WAIT_SECONDS then
		UpdateSingleInfoScale(infoUI, false, state, false)
		FinishStableScaleWait(infoUI, state, "wait timeout")
		return
	end

	local success, reason = UpdateSingleInfoScale(infoUI, false, state, true)
	if success then
		FinishStableScaleWait(infoUI, state, "scale ready")
	elseif state.lastWaitReason ~= reason then
		state.lastWaitReason = reason
		DebugLog(`wait restore: gui={GetDebugName(infoUI)} reason={reason}`)
	end
end

RefreshEnabledStableScaleWait = function(infoUI: BillboardGui, state: InfoGuiState)
	local wasEnabled = state.wasEnabled
	local isEnabled = infoUI.Enabled
	state.wasEnabled = isEnabled

	if wasEnabled and not isEnabled then
		if state.isWaitingForStableScale then
			CancelStableScaleWait(infoUI, state, "disabled")
		end
		return
	end

	if wasEnabled or not isEnabled then
		return
	end

	local controllerFrame = GetControllerFrame(infoUI)
	if controllerFrame ~= nil and CanScaleControllerFrame(controllerFrame) then
		BeginStableScaleWait(infoUI, state, controllerFrame, "enabled")
	end
end

local function ProcessWaitingGuis()
	local index = #infoGuis
	while index >= 1 do
		local infoUI = infoGuis[index]
		if infoUI.Parent == nil then
			RemoveInfoGuiByIndex(index)
			index -= 1
			continue
		end

		local adornee = infoUI.Adornee :: Instance?
		if adornee ~= nil and adornee.Parent == nil then
			RemoveInfoGuiByIndex(index)
			infoUI:Destroy()
			index -= 1
			continue
		end

		local state = infoGuiStateMap[infoUI]
		if state ~= nil then
			RefreshEnabledStableScaleWait(infoUI, state)
		end
		if state ~= nil and state.isWaitingForStableScale then
			RestoreControllerVisibleIfReady(infoUI, state)
		end
		index -= 1
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

		local adornee = infoUI.Adornee :: Instance?
		-- BillboardGui 可以直接挂在 Part/Attachment 下；只有显式 Adornee 失效时才清理。
		if adornee ~= nil and adornee.Parent == nil then
			RemoveInfoGuiByIndex(index)
			infoUI:Destroy()
			continue
		end

		local state = infoGuiStateMap[infoUI]
		if state ~= nil then
			RefreshEnabledStableScaleWait(infoUI, state)
		end
		if state ~= nil and state.isWaitingForStableScale then
			updateCursorIndex += 1
			updated += 1
			continue
		end
		if infoUI.Enabled then
			local requireStableSize = state ~= nil and state.postRestoreStableFrames > 0
			UpdateSingleInfoScale(infoUI, false, state, requireStableSize)
		end
		updateCursorIndex += 1
		updated += 1
	end
end

local function OnRenderStepped(deltaTime: number)
	ProcessWaitingGuis()

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
	local shouldWaitForStableScale = gui.Enabled and controllerFrame ~= nil and CanScaleControllerFrame(controllerFrame)
	local state: InfoGuiState = {
		index = #infoGuis,
		controllerFrame = controllerFrame,
		isWaitingForStableScale = false,
		didHideControllerForWait = false,
		wasEnabled = gui.Enabled,
		lastBillboardSize = nil,
		stableBillboardSizeFrameCount = 0,
		lastWaitReason = nil,
		waitStartedAt = nil,
		postRestoreStableFrames = 0,
	}
	infoGuiStateMap[gui] = state
	DebugLog(
		`track: gui={GetDebugName(gui)} waitStableScale={tostring(shouldWaitForStableScale)} guiEnabled={tostring(gui.Enabled)} billboardAbs={FormatVector2(
			gui.AbsoluteSize
		)} billboardOffset={FormatUDim2Offset(gui.Size)} controllerOffset={if controllerFrame ~= nil
			then FormatUDim2Offset(controllerFrame.Size)
			else "missing"}`
	)

	if shouldWaitForStableScale and controllerFrame ~= nil then
		BeginStableScaleWait(gui, state, controllerFrame, "track")
		RestoreControllerVisibleIfReady(gui, state)
	else
		UpdateSingleInfoScale(gui, false, state, false)
	end
end

function BillboardManager.Untrack(gui: BillboardGui)
	RemoveInfoGui(gui)
end

runService.RenderStepped:Connect(OnRenderStepped)

return BillboardManager
