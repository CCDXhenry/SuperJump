--!strict
local players = game:GetService("Players")
local runService = game:GetService("RunService")

local BillboardManager = {}

type InfoGuiState = {
	index: number,
	visibleIndex: number?,
	controllerFrame: Frame?,
	uiScale: UIScale?,
	visibleDistance: number?,
	isDistanceVisible: boolean,
	isControllerVisible: boolean,
	wasEnabled: boolean,
	lastBillboardSize: Vector2?,
	stableBillboardSizeFrameCount: number,
	scaleWaitStartedAt: number?,
	lastScaleWaitReason: string?,
}

local infoGuis: { BillboardGui } = {}
local visibleInfoGuis: { BillboardGui } = {}
local infoGuiStateMap: { [BillboardGui]: InfoGuiState } = {}
local localPlayer = players.LocalPlayer
local VISIBLE_DISTANCE_ATTR = "VisibleDistance"
local MAX_INFO_UI_SCALE = 1.2
local MIN_VALID_INFO_UI_SCALE = 0.01
local STABLE_INFO_SIZE_FRAME_COUNT = 1
local INFO_SIZE_EPSILON = 0.5
local INFO_SIZE_MAX_CHANGE_RATIO = 0.05
local MAX_SCALE_READY_WAIT_SECONDS = 0.5
local UPDATE_INTERVAL_SECONDS = 0.01
local DISTANCE_VISIBILITY_INTERVAL_SECONDS = 0.05
local DISTANCE_VISIBILITY_HYSTERESIS_STUDS = 5
local MAX_UPDATES_PER_STEP = 90
local DEBUG_LOG_ENABLED = false
local updateElapsedSeconds = 0
local distanceVisibilityElapsedSeconds = 0
local distanceVisibilityCursorIndex = 1

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

local function GetStateControllerFrame(infoUI: BillboardGui, state: InfoGuiState): Frame?
	local controllerFrame = state.controllerFrame
	if controllerFrame ~= nil and controllerFrame.Parent ~= nil then
		return controllerFrame
	end
	controllerFrame = GetControllerFrame(infoUI)
	state.controllerFrame = controllerFrame
	state.uiScale = nil
	return controllerFrame
end

local function GetStateUIScale(infoUI: BillboardGui, state: InfoGuiState): UIScale?
	local controllerFrame = GetStateControllerFrame(infoUI, state)
	if controllerFrame == nil then
		return nil
	end

	local uiScale = state.uiScale
	if uiScale ~= nil and uiScale.Parent == controllerFrame then
		return uiScale
	end

	local foundUIScale = controllerFrame:FindFirstChild("UIScale")
	if foundUIScale == nil or not foundUIScale:IsA("UIScale") then
		state.uiScale = nil
		return nil
	end

	state.uiScale = foundUIScale
	return foundUIScale
end

local function SetControllerFrameVisibleIfChanged(controllerFrame: Frame, visible: boolean)
	if controllerFrame.Visible ~= visible then
		controllerFrame.Visible = visible
	end
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

local function ResetScaleReadiness(state: InfoGuiState)
	state.lastBillboardSize = nil
	state.stableBillboardSizeFrameCount = 0
	state.scaleWaitStartedAt = nil
	state.lastScaleWaitReason = nil
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

local function GetInstanceWorldPosition(inst: Instance?): Vector3?
	if inst == nil then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst.Position
	end
	if inst:IsA("Attachment") then
		return inst.WorldPosition
	end
	return nil
end

local function GetBillboardWorldPosition(infoUI: BillboardGui): Vector3?
	local adornee = infoUI.Adornee :: Instance?
	local adorneePosition = GetInstanceWorldPosition(adornee)
	if adorneePosition ~= nil then
		return adorneePosition
	end
	return GetInstanceWorldPosition(infoUI.Parent)
end

local function GetLocalPlayerRootPosition(): Vector3?
	local character = localPlayer.Character
	if character == nil then
		return nil
	end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart == nil or not humanoidRootPart:IsA("BasePart") then
		return nil
	end
	return humanoidRootPart.Position
end

local function GetVisibleDistance(infoUI: BillboardGui): number?
	local attrValue = infoUI:GetAttribute(VISIBLE_DISTANCE_ATTR)
	if type(attrValue) == "number" and attrValue > 0 then
		return attrValue
	end
	local maxDistance = infoUI.MaxDistance
	if maxDistance > 0 then
		return maxDistance
	end
	return nil
end

local function RefreshMaxDistanceOverride(infoUI: BillboardGui, state: InfoGuiState)
	local maxDistance = infoUI.MaxDistance
	if maxDistance <= 0 then
		return
	end
	state.visibleDistance = maxDistance
	infoUI.MaxDistance = 0
end

local function IsInfoGuiDistanceVisible(infoUI: BillboardGui, state: InfoGuiState): boolean
	local visibleDistance = state.visibleDistance
	if visibleDistance == nil then
		return true
	end
	local rootPosition = GetLocalPlayerRootPosition()
	local guiPosition = GetBillboardWorldPosition(infoUI)
	if rootPosition == nil or guiPosition == nil then
		return false
	end
	local distanceLimit = if state.isDistanceVisible then visibleDistance + DISTANCE_VISIBILITY_HYSTERESIS_STUDS else visibleDistance
	local offset = rootPosition - guiPosition
	return offset:Dot(offset) <= distanceLimit * distanceLimit
end

local function AddVisibleInfoGui(infoUI: BillboardGui, state: InfoGuiState)
	if state.visibleIndex ~= nil then
		return
	end
	table.insert(visibleInfoGuis, infoUI)
	state.visibleIndex = #visibleInfoGuis
end

local function RemoveVisibleInfoGuiByIndex(visibleIndex: number)
	local lastIndex = #visibleInfoGuis
	local lastGui = visibleInfoGuis[lastIndex]
	if visibleIndex ~= lastIndex then
		visibleInfoGuis[visibleIndex] = lastGui
		local lastGuiState = infoGuiStateMap[lastGui]
		if lastGuiState ~= nil then
			lastGuiState.visibleIndex = visibleIndex
		end
	end
	visibleInfoGuis[lastIndex] = nil
end

local function RemoveVisibleInfoGui(state: InfoGuiState)
	local visibleIndex = state.visibleIndex
	if visibleIndex == nil then
		return
	end

	RemoveVisibleInfoGuiByIndex(visibleIndex)
	state.visibleIndex = nil
end

local function RefreshDistanceVisibility(infoUI: BillboardGui, state: InfoGuiState)
	local isVisible = infoUI.Enabled and IsInfoGuiDistanceVisible(infoUI, state)
	if isVisible then
		if not state.isDistanceVisible then
			state.isDistanceVisible = true
			state.isControllerVisible = false
			ResetScaleReadiness(state)
			AddVisibleInfoGui(infoUI, state)
		end
		return
	end

	state.isDistanceVisible = false
	RemoveVisibleInfoGui(state)
	local controllerFrame = GetStateControllerFrame(infoUI, state)
	if controllerFrame == nil then
		return
	end
	state.isControllerVisible = false
	ResetScaleReadiness(state)
	SetControllerFrameVisibleIfChanged(controllerFrame, false)
end

local UpdateSingleInfoScale: (BillboardGui, InfoGuiState, boolean) -> (boolean, string)
local RefreshControllerFrameVisibility: (BillboardGui, InfoGuiState) -> ()
local RefreshEnabledDistanceVisibility: (BillboardGui, InfoGuiState) -> ()

local function RemoveInfoGuiByIndex(index: number)
	local lastIndex = #infoGuis
	local removedGui = infoGuis[index]
	local removedGuiState = infoGuiStateMap[removedGui]
	if removedGuiState ~= nil then
		RemoveVisibleInfoGui(removedGuiState)
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

UpdateSingleInfoScale = function(infoUI: BillboardGui, state: InfoGuiState, useSizeFallback: boolean): (boolean, string)
	local controllerFrame = GetStateControllerFrame(infoUI, state)
	if controllerFrame == nil then
		return false, "missing ControllerFrame"
	end
	local uiScale = GetStateUIScale(infoUI, state)
	if uiScale == nil then
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
	return true, "ok"
end

RefreshControllerFrameVisibility = function(infoUI: BillboardGui, state: InfoGuiState)
	local controllerFrame = GetStateControllerFrame(infoUI, state)
	if controllerFrame == nil then
		return
	end

	if not infoUI.Enabled or not state.isDistanceVisible then
		state.isControllerVisible = false
		ResetScaleReadiness(state)
		SetControllerFrameVisibleIfChanged(controllerFrame, false)
		return
	end

	if state.isControllerVisible then
		return
	end

	SetControllerFrameVisibleIfChanged(controllerFrame, false)
	if state.scaleWaitStartedAt == nil then
		state.scaleWaitStartedAt = os.clock()
	end

	local billboardSize = GetBillboardPixelSize(infoUI, false)
	local isStable = billboardSize ~= nil and IsBillboardSizeStable(state, billboardSize)
	local waitStartedAt = state.scaleWaitStartedAt
	local didTimeout = waitStartedAt ~= nil and os.clock() - waitStartedAt >= MAX_SCALE_READY_WAIT_SECONDS

	local success = false
	local reason = "waiting stable Billboard size"
	if isStable then
		success, reason = UpdateSingleInfoScale(infoUI, state, false)
	elseif didTimeout then
		success, reason = UpdateSingleInfoScale(infoUI, state, true)
	end

	if success then
		state.isControllerVisible = true
		ResetScaleReadiness(state)
		SetControllerFrameVisibleIfChanged(controllerFrame, true)
	elseif state.lastScaleWaitReason ~= reason then
		state.lastScaleWaitReason = reason
		DebugLog(`wait first visible scale: gui={GetDebugName(infoUI)} reason={reason}`)
	end
end

RefreshEnabledDistanceVisibility = function(infoUI: BillboardGui, state: InfoGuiState)
	local wasEnabled = state.wasEnabled
	local isEnabled = infoUI.Enabled
	state.wasEnabled = isEnabled

	if wasEnabled and not isEnabled then
		RefreshDistanceVisibility(infoUI, state)
		return
	end

	if wasEnabled or not isEnabled then
		return
	end

	RefreshDistanceVisibility(infoUI, state)
end

local function UpdateDistanceVisibilityStep()
	local count = #infoGuis
	if count <= 0 then
		distanceVisibilityCursorIndex = 1
		return
	end
	if distanceVisibilityCursorIndex > count then
		distanceVisibilityCursorIndex = 1
	end

	local updated = 0
	while updated < MAX_UPDATES_PER_STEP and distanceVisibilityCursorIndex <= #infoGuis do
		local index = distanceVisibilityCursorIndex
		local infoUI = infoGuis[index]
		if infoUI.Parent == nil then
			RemoveInfoGuiByIndex(index)
			continue
		end

		local adornee = infoUI.Adornee :: Instance?
		if adornee ~= nil and adornee.Parent == nil then
			RemoveInfoGuiByIndex(index)
			infoUI:Destroy()
			continue
		end

		local state = infoGuiStateMap[infoUI]
		if state ~= nil then
			RefreshMaxDistanceOverride(infoUI, state)
			RefreshEnabledDistanceVisibility(infoUI, state)
			RefreshDistanceVisibility(infoUI, state)
			RefreshControllerFrameVisibility(infoUI, state)
		end

		distanceVisibilityCursorIndex += 1
		updated += 1
	end
end

local function UpdateInfoScalesStep()
	local index = #visibleInfoGuis
	while index >= 1 do
		local infoUI = visibleInfoGuis[index]
		local state = infoGuiStateMap[infoUI]
		if state == nil or infoUI.Parent == nil then
			if state ~= nil then
				RemoveInfoGuiByIndex(state.index)
			else
				RemoveVisibleInfoGuiByIndex(index)
			end
			index -= 1
			continue
		end

		local adornee = infoUI.Adornee :: Instance?
		if adornee ~= nil and adornee.Parent == nil then
			RemoveInfoGuiByIndex(state.index)
			infoUI:Destroy()
			index -= 1
			continue
		end

		RefreshEnabledDistanceVisibility(infoUI, state)
		if infoUI.Enabled and state.isDistanceVisible then
			RefreshControllerFrameVisibility(infoUI, state)
			if state.isControllerVisible then
				UpdateSingleInfoScale(infoUI, state, false)
			end
		end
		index -= 1
	end
end

local function OnRenderStepped(deltaTime: number)
	distanceVisibilityElapsedSeconds += deltaTime
	if distanceVisibilityElapsedSeconds >= DISTANCE_VISIBILITY_INTERVAL_SECONDS then
		distanceVisibilityElapsedSeconds = 0
		UpdateDistanceVisibilityStep()
	end

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
	local visibleDistance = GetVisibleDistance(gui)
	gui.MaxDistance = 0
	local state: InfoGuiState = {
		index = #infoGuis,
		visibleIndex = nil,
		controllerFrame = controllerFrame,
		uiScale = nil,
		visibleDistance = visibleDistance,
		isDistanceVisible = false,
		isControllerVisible = false,
		wasEnabled = gui.Enabled,
		lastBillboardSize = nil,
		stableBillboardSizeFrameCount = 0,
		scaleWaitStartedAt = nil,
		lastScaleWaitReason = nil,
	}
	infoGuiStateMap[gui] = state
	RefreshDistanceVisibility(gui, state)
	RefreshControllerFrameVisibility(gui, state)
	DebugLog(
		`track: gui={GetDebugName(gui)} guiEnabled={tostring(gui.Enabled)} distanceVisible={tostring(state.isDistanceVisible)} visibleDistance={tostring(
			visibleDistance
		)} billboardAbs={FormatVector2(gui.AbsoluteSize)} billboardOffset={FormatUDim2Offset(gui.Size)} controllerOffset={if controllerFrame ~= nil
			then FormatUDim2Offset(controllerFrame.Size)
			else "missing"}`
	)

	if gui.Enabled and state.isControllerVisible then
		UpdateSingleInfoScale(gui, state, false)
	end
end

function BillboardManager.Untrack(gui: BillboardGui)
	RemoveInfoGui(gui)
end

runService.RenderStepped:Connect(OnRenderStepped)

return BillboardManager
