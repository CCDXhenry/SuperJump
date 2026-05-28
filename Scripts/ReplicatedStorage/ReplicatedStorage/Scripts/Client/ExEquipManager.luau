--!strict
local ExEquipManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local players: Players = game:GetService("Players")
local workspace: Workspace = game:GetService("Workspace")
local runService: RunService = game:GetService("RunService")
local tweenService: TweenService = game:GetService("TweenService")
local userInputService: UserInputService = game:GetService("UserInputService")
local localPlayer: Player? = players.LocalPlayer

if localPlayer == nil then
	return ExEquipManager
end

local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local NumberExtension = require(coreSharedScripts:FindFirstChild("NumberExtension"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local UIManager = require(clientScripts:FindFirstChild("UIManager"))
local BillboardManager = require(clientScripts:FindFirstChild("BillboardManager"))

local function GetPlayerControls(): any
	local playerScripts = localPlayer:FindFirstChildOfClass("PlayerScripts")
	if playerScripts == nil then
		return nil
	end
	local playerModuleScript = playerScripts:FindFirstChild("PlayerModule") :: ModuleScript?
	if playerModuleScript == nil then
		return nil
	end
	local ok, mod = pcall(require, playerModuleScript)
	if not ok or mod == nil then
		return nil
	end
	local controls
	local okGet, res = pcall(function()
		return (mod :: any):GetControls()
	end)
	if okGet then
		controls = res
	end
	return controls
end

local uiFolder = replicatedStorage:WaitForChild("UI")
local exercisePopupGuiTemplate = uiFolder:WaitForChild("ExerciseJumpPowerPopupGui") :: BillboardGui

-- 锻炼模式常量
-- 人物躯干高度（HumanoidRootPart 到脚底的参考偏移）
local CHARACTER_TORSO_HEIGHT: number = 3
local EXERCISE_OWNER_USER_ID_ATTR = "ExerciseOwnerUserId"
local EXERCISE_MODEL_WAIT_TIMEOUT: number = 5
-- 锻炼数值浮字对象池大小：允许同时显示多个浮字，超过时复用最早播放的浮字。
local EXERCISE_POPUP_POOL_SIZE: number = 5
-- 浮字完整动画时长，调大则跳出和落下更慢。
local EXERCISE_POPUP_LIFETIME: number = 1.5
-- 浮字初始高度，相对于 HumanoidRootPart。
local EXERCISE_POPUP_START_HEIGHT: number = 2.4
-- 抛物线最高点高度，调大则弹得更高。
local EXERCISE_POPUP_PARABOLA_HEIGHT: number = 1.8
-- 抛物线终点比起点低多少，调大则下落更明显。
local EXERCISE_POPUP_FALL_DISTANCE: number = 0.45
-- 抛物线水平位移的最小/最大距离，影响离开玩家身体的幅度。
local EXERCISE_POPUP_OUT_DISTANCE_MIN: number = 2
local EXERCISE_POPUP_OUT_DISTANCE_MAX: number = 3
-- 随机向上弹出的水平角度范围，360 表示可朝任意水平方向弹出。
local EXERCISE_POPUP_RANDOM_ANGLE_DEGREES: number = 360
-- 第二段淡出开始时间占比，越小越早开始变透明。
local EXERCISE_POPUP_FADE_START_RATIO: number = 0.45

-- 锻炼模式状态
local isExercising: boolean = false
local exerciseHumanoid: Humanoid? = nil
local exerciseHrp: BasePart? = nil
local exerciseForward: Vector3 = Vector3.zero
local exerciseRunServiceConnection: RBXScriptConnection? = nil
local exerciseInputConnection: RBXScriptConnection? = nil
local exercisePrompt: ProximityPrompt? = nil
local exerciseBikeAnimTrack: AnimationTrack? = nil
local exercisePopupRandom = Random.new()
local exerciseEquipId: number? = nil

type ExercisePopupItem = {
	gui: BillboardGui,
	attachment: Attachment?,
	textLabel: TextLabel?,
	stroke: UIStroke?,
	isActive: boolean,
	startedAt: number,
	moveTween: Tween?,
	textTween: Tween?,
	strokeTween: Tween?,
	progressValue: NumberValue?,
	progressConnection: RBXScriptConnection?,
}

local exercisePopupPool: { ExercisePopupItem } = {}
local GetExercisePopupParent: () -> PlayerGui? = function()
	return nil
end

--------------------------------------------------------------------
-- 锻炼模式逻辑
--------------------------------------------------------------------

local function GetExercisePopupText(gui: BillboardGui): TextLabel?
	local controllerFrame = gui:FindFirstChild("ControllerFrame")
	if controllerFrame == nil or not controllerFrame:IsA("Frame") then
		return nil
	end
	return controllerFrame:FindFirstChild("JumpPowerPopupText") :: TextLabel?
end

local function GetExerciseEquipFrame(): Frame?
	local frameRoot = UIManager.GetWindowRoot(UIManager.WindowId.ExEquipFrame)
	if frameRoot == nil or not frameRoot:IsA("Frame") then
		return nil
	end
	return frameRoot
end

local function SetExerciseInfoScaleBar(ratio: number)
	local equipFrame = GetExerciseEquipFrame()
	if equipFrame == nil then
		return
	end

	local expImage = equipFrame:FindFirstChild("ExpImage")
	if expImage == nil or not expImage:IsA("ImageLabel") then
		return
	end
	local scaleBar = expImage:FindFirstChild("ScaleBar")
	if scaleBar == nil or not scaleBar:IsA("ImageLabel") then
		return
	end
	local scaleImage = scaleBar:FindFirstChild("Scale")
	if scaleImage == nil or not scaleImage:IsA("ImageLabel") then
		return
	end

	local currentSize = scaleImage.Size
	scaleImage.Size = UDim2.new(math.clamp(ratio, 0, 1), currentSize.X.Offset, currentSize.Y.Scale, currentSize.Y.Offset)
end

local function UpdateExerciseInfoView()
	local equipFrame = GetExerciseEquipFrame()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if equipFrame == nil or localPlayerInfo == nil then
		return
	end

	local equipData = if exerciseEquipId ~= nil then GameConfig.ExEquipDataMap[exerciseEquipId] else nil
	local speedLabel = equipFrame:FindFirstChild("ExSpeedLabel") :: TextLabel?
	if speedLabel ~= nil then
		local speedValue = if equipData ~= nil then equipData.ability else 0
		speedLabel.Text = string.format("%s Speed", NumberExtension.FormatBigNumberAA(speedValue))
	end

	local expImage = equipFrame:FindFirstChild("ExpImage")
	if expImage == nil or not expImage:IsA("ImageLabel") then
		return
	end

	local jumpPowerInfo = localPlayerInfo.jumpPower
	local requiredExp = GameConfig.GetJumpPowerRequiredExp(jumpPowerInfo)
	local lvLabel = expImage:FindFirstChild("LvLabel") :: TextLabel?
	local expLabel = expImage:FindFirstChild("ExpLabel") :: TextLabel?
	if lvLabel ~= nil then
		lvLabel.Text = string.format("Lv%d", jumpPowerInfo.lv)
	end
	if expLabel ~= nil then
		expLabel.Text = string.format(
			"%s/%s",
			NumberExtension.FormatBigNumberAA(jumpPowerInfo.exp),
			NumberExtension.FormatBigNumberAA(requiredExp)
		)
	end
	SetExerciseInfoScaleBar(if requiredExp > 0 then jumpPowerInfo.exp / requiredExp else 0)
end

local function StopExercisePopupTweens(item: ExercisePopupItem)
	if item.moveTween ~= nil then
		item.moveTween:Cancel()
		item.moveTween = nil
	end
	if item.textTween ~= nil then
		item.textTween:Cancel()
		item.textTween = nil
	end
	if item.strokeTween ~= nil then
		item.strokeTween:Cancel()
		item.strokeTween = nil
	end
	if item.progressConnection ~= nil then
		item.progressConnection:Disconnect()
		item.progressConnection = nil
	end
	if item.progressValue ~= nil then
		item.progressValue:Destroy()
		item.progressValue = nil
	end
end

local function ReleaseExercisePopupItem(item: ExercisePopupItem)
	StopExercisePopupTweens(item)
	BillboardManager.Untrack(item.gui)
	item.gui.Enabled = false
	item.gui.Adornee = nil
	item.gui.Parent = nil
	item.isActive = false
	item.startedAt = 0

	if item.attachment ~= nil and item.attachment.Parent ~= nil then
		item.attachment:Destroy()
	end
	item.attachment = nil
	item.textLabel = nil
	item.stroke = nil
end

local function EnsureExercisePopupPool()
	if #exercisePopupPool > 0 then
		return
	end

	for popupIndex: number = 1, EXERCISE_POPUP_POOL_SIZE do
		local gui = exercisePopupGuiTemplate:Clone()
		gui.Name = `ExerciseJumpPowerPopupGui_{popupIndex}`
		gui.Enabled = false
		gui.Adornee = nil
		gui.Parent = nil

		table.insert(exercisePopupPool, {
			gui = gui,
			attachment = nil,
			textLabel = nil,
			stroke = nil,
			isActive = false,
			startedAt = 0,
			moveTween = nil,
			textTween = nil,
			strokeTween = nil,
			progressValue = nil,
			progressConnection = nil,
		})
	end
end

local function GetExercisePopupItem(): ExercisePopupItem?
	EnsureExercisePopupPool()

	for _, item: ExercisePopupItem in exercisePopupPool do
		if not item.isActive then
			return item
		end
	end

	local oldestItem: ExercisePopupItem? = nil
	for _, item: ExercisePopupItem in exercisePopupPool do
		if oldestItem == nil or item.startedAt < oldestItem.startedAt then
			oldestItem = item
		end
	end

	if oldestItem ~= nil then
		ReleaseExercisePopupItem(oldestItem)
	end
	return oldestItem
end

local function CleanupExercisePopups()
	for _, item: ExercisePopupItem in exercisePopupPool do
		ReleaseExercisePopupItem(item)
	end
end

local function GetExercisePopupAdornee(): BasePart?
	local character: Model? = localPlayer.Character
	if character == nil then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

GetExercisePopupParent = function(): PlayerGui?
	return localPlayer:FindFirstChildOfClass("PlayerGui")
end

local function GetRandomPopupDirection(adornee: BasePart): Vector3
	local angleRange = math.rad(EXERCISE_POPUP_RANDOM_ANGLE_DEGREES)
	local angle = exercisePopupRandom:NextNumber(-angleRange / 2, angleRange / 2)
	local baseForward = if exerciseForward.Magnitude > 0 then exerciseForward.Unit else adornee.CFrame.LookVector
	local baseRight = adornee.CFrame.RightVector
	local direction = baseForward * math.cos(angle) + baseRight * math.sin(angle)
	if direction.Magnitude <= 0 then
		return baseForward
	end
	return direction.Unit
end

local function ShowExerciseJumpPowerPopup(addAmount: number)
	if not isExercising or addAmount <= 0 then
		return
	end

	local adornee = GetExercisePopupAdornee()
	if adornee == nil then
		return
	end

	local popupParent = GetExercisePopupParent()
	if popupParent == nil then
		return
	end

	local item = GetExercisePopupItem()
	if item == nil then
		return
	end

	local textLabel = GetExercisePopupText(item.gui)
	if textLabel == nil then
		warn("[ExEquipManager] ExerciseJumpPowerPopupGui missing ControllerFrame.JumpPowerPopupText")
		return
	end

	local displayText = string.format("+%s", NumberExtension.FormatBigNumberAA(addAmount))
	local popupAttachment = Instance.new("Attachment")
	popupAttachment.Name = "ExerciseJumpPowerPopupAttachment"
	popupAttachment.Position = Vector3.new(0, EXERCISE_POPUP_START_HEIGHT, 0)
	popupAttachment.Parent = adornee

	local stroke: UIStroke? = textLabel:FindFirstChild("PopupStroke") :: UIStroke?
	textLabel.Text = displayText
	textLabel.TextTransparency = 0
	if stroke ~= nil then
		stroke.Transparency = 0
	end

	item.gui.Adornee = popupAttachment
	item.gui.Enabled = true
	item.gui.Parent = popupParent
	item.attachment = popupAttachment
	item.textLabel = textLabel
	item.stroke = stroke
	item.isActive = true
	item.startedAt = os.clock()

	BillboardManager.Track(item.gui)

	local popupDirection = GetRandomPopupDirection(adornee)
	local outDistance = exercisePopupRandom:NextNumber(EXERCISE_POPUP_OUT_DISTANCE_MIN, EXERCISE_POPUP_OUT_DISTANCE_MAX)
	local startPosition = Vector3.new(0, EXERCISE_POPUP_START_HEIGHT, 0)
	local progressValue = Instance.new("NumberValue")
	progressValue.Name = "ExerciseJumpPowerPopupProgress"
	progressValue.Value = 0
	item.progressValue = progressValue
	item.progressConnection = progressValue:GetPropertyChangedSignal("Value"):Connect(function()
		local progress = math.clamp(progressValue.Value, 0, 1)
		local horizontalOffset = popupDirection * outDistance * progress
		local parabolaOffsetY = EXERCISE_POPUP_PARABOLA_HEIGHT * 4 * progress * (1 - progress)
			- EXERCISE_POPUP_FALL_DISTANCE * progress
		popupAttachment.Position = startPosition + horizontalOffset + Vector3.new(0, parabolaOffsetY, 0)
	end)

	local moveTweenInfo = TweenInfo.new(EXERCISE_POPUP_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeTweenInfo = TweenInfo.new(
		EXERCISE_POPUP_LIFETIME * (1 - EXERCISE_POPUP_FADE_START_RATIO),
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)

	local moveTween = tweenService:Create(progressValue, moveTweenInfo, { Value = 1 })
	local textTween = tweenService:Create(textLabel, fadeTweenInfo, { TextTransparency = 1 })
	item.moveTween = moveTween
	item.textTween = textTween

	if stroke ~= nil then
		item.strokeTween = tweenService:Create(stroke, fadeTweenInfo, { Transparency = 1 })
	end

	moveTween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		if playbackState == Enum.PlaybackState.Completed and item.isActive and item.attachment == popupAttachment then
			ReleaseExercisePopupItem(item)
		end
	end)

	moveTween:Play()
	task.delay(EXERCISE_POPUP_LIFETIME * EXERCISE_POPUP_FADE_START_RATIO, function()
		if item.isActive and item.attachment == popupAttachment then
			textTween:Play()
			if item.strokeTween ~= nil then
				item.strokeTween:Play()
			end
		end
	end)
end

local function StopExerciseInternal()
	if exerciseRunServiceConnection ~= nil then
		exerciseRunServiceConnection:Disconnect()
		exerciseRunServiceConnection = nil
	end

	if exerciseInputConnection ~= nil then
		exerciseInputConnection:Disconnect()
		exerciseInputConnection = nil
	end

	if exerciseHumanoid ~= nil then
		exerciseHumanoid.AutoRotate = true
		exerciseHumanoid.PlatformStand = false
		exerciseHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		exerciseHumanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
		exerciseHumanoid:Move(Vector3.zero, false)
	end

	-- 恢复玩家控制
	local controls = GetPlayerControls()
	if controls ~= nil then
		pcall(function()
			controls:Enable()
		end)
	end

	-- 恢复器材 Prompt 按钮（模型由服务端销毁，仅做兜底）
	if exercisePrompt ~= nil and exercisePrompt.Parent ~= nil then
		exercisePrompt.Enabled = true
	end
	exercisePrompt = nil

	-- 停止 Bike 专属动画
	if exerciseBikeAnimTrack ~= nil then
		exerciseBikeAnimTrack:Stop()
		exerciseBikeAnimTrack:Destroy()
		exerciseBikeAnimTrack = nil
	end

	-- 关闭锻炼 UI
	UIManager.CloseWindow(UIManager.WindowId.ExEquipFrame)
	CleanupExercisePopups()

	isExercising = false
	ClientGameInfo.SetExercising(false)
	exerciseHumanoid = nil
	exerciseHrp = nil
	exerciseForward = Vector3.zero
	exerciseEquipId = nil
end

local function StopExerciseWithServerRequest()
	if isExercising then
		NetMsg.FireRequestStopExercise()
	end
	StopExerciseInternal()
end

local function GetExercisePromptFromModel(exerciseModel: Model): ProximityPrompt?
	local promptAttachment: Attachment? = exerciseModel:FindFirstChild("Attachment") :: Attachment?
	if promptAttachment == nil then
		return nil
	end
	return promptAttachment:FindFirstChild("ProximityPrompt") :: ProximityPrompt?
end

local function FindLocalActiveExerciseModel(): Model?
	for _, child in workspace:GetChildren() do
		if child:IsA("Model") and child:GetAttribute(EXERCISE_OWNER_USER_ID_ATTR) == localPlayer.UserId then
			return child
		end
	end
	return nil
end

local function WaitForLocalActiveExerciseModel(): Model?
	local existingModel = FindLocalActiveExerciseModel()
	if existingModel ~= nil then
		return existingModel
	end

	local foundModel: Model? = nil
	local childAddedConnection: RBXScriptConnection? = nil
	local startTime = os.clock()

	childAddedConnection = workspace.ChildAdded:Connect(function(child: Instance)
		if not child:IsA("Model") then
			return
		end
		if child:GetAttribute(EXERCISE_OWNER_USER_ID_ATTR) == localPlayer.UserId then
			foundModel = child
		end
	end)

	while foundModel == nil and os.clock() - startTime < EXERCISE_MODEL_WAIT_TIMEOUT do
		foundModel = FindLocalActiveExerciseModel()
		if foundModel ~= nil then
			break
		end
		task.wait()
	end

	if childAddedConnection ~= nil then
		childAddedConnection:Disconnect()
	end
	return foundModel
end

local function GetExerciseStandCFrame(equipmentModel: Model, equipData: GameConfig.ExEquipData, character: Model, hrp: BasePart): CFrame
	local modelRootPart: BasePart? = equipmentModel.PrimaryPart
	local rootCf: CFrame
	if modelRootPart ~= nil then
		rootCf = modelRootPart.CFrame
	else
		rootCf = equipmentModel:GetPivot()
	end

	local forwardZ: Vector3 = -rootCf.LookVector
	local rootPos: Vector3 = rootCf.Position

	-- 获取 LowerTorso 相对于 HumanoidRootPart 的偏移量（用于将 LowerTorso 对齐到 Attachment）
	local lowerTorsoOffset: Vector3 = Vector3.zero
	local lowerTorso: BasePart? = character:FindFirstChild("LowerTorso") :: BasePart?
	if lowerTorso ~= nil and hrp ~= nil then
		lowerTorsoOffset = lowerTorso.Position - hrp.Position
	end

	-- 根据器材类型确定站立位置和高度
	local standPos: Vector3
	if equipData.type == 1 or equipData.type == 2 then
		-- type == 1/2：模型下有 ExerciseAttachment 标记站立位置和高度
		local exerciseAttachment: Attachment? = equipmentModel:FindFirstChild("ExerciseAttachment") :: Attachment?
		if exerciseAttachment ~= nil then
			local attachPos: Vector3 = exerciseAttachment.WorldPosition
			if equipData.type == 2 then
				-- type == 2（Bike）：将玩家的 LowerTorso 对齐到 Attachment 位置
				standPos = attachPos - lowerTorsoOffset
			else
				-- type == 1（Treadmill）：人物站立，需要躯干高度偏移
				standPos = Vector3.new(attachPos.X, attachPos.Y + CHARACTER_TORSO_HEIGHT, attachPos.Z)
			end
		else
			-- 没有 Attachment 时用 PrimaryPart 的位置作为兜底
			standPos = Vector3.new(rootPos.X, rootPos.Y + CHARACTER_TORSO_HEIGHT, rootPos.Z)
		end
	else
		-- 其他类型：用 Raycast 向下检测器材顶面确定站立高度
		local rayOrigin: Vector3 = rootPos + Vector3.new(0, 10, 0)
		local rayDirection: Vector3 = Vector3.new(0, -20, 0)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Include
		rayParams.FilterDescendantsInstances = { equipmentModel }

		local rayResult = workspace:Raycast(rayOrigin, rayDirection, rayParams)

		local modelTopY: number
		if rayResult ~= nil then
			modelTopY = rayResult.Position.Y
		else
			-- 兜底：用模型包围盒的上表面
			local cframe: CFrame, size: Vector3 = equipmentModel:GetBoundingBox()
			modelTopY = cframe.Y + size.Y / 2
		end
		standPos = Vector3.new(rootPos.X, modelTopY + CHARACTER_TORSO_HEIGHT, rootPos.Z)
	end
	return CFrame.lookAt(standPos, standPos + forwardZ)
end

--------------------------------------------------------------------
-- 锻炼模式逻辑
--------------------------------------------------------------------

local function StartExercise(equipId: number)
	if ClientGameInfo.IsInJumpRunway() then
		NetMsg.FireRequestStopExercise()
		return
	end

	-- 如果已在锻炼中，则忽略后续的开始请求，防止竞态条件
	if isExercising then
		return
	end

	local character: Model? = localPlayer.Character
	if character == nil then
		return
	end

	local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
	local hrp: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid == nil or hrp == nil then
		return
	end

	local equipData = GameConfig.ExEquipDataMap[equipId]
	if equipData == nil then
		return
	end

	local equipmentModel = WaitForLocalActiveExerciseModel()
	if equipmentModel == nil then
		warn("[ExEquipManager] Server exercise model not found")
		NetMsg.FireRequestStopExercise()
		return
	end

	isExercising = true
	ClientGameInfo.SetExercising(true)

	local standCf = GetExerciseStandCFrame(equipmentModel, equipData, character, hrp)
	local standPos: Vector3 = standCf.Position
	local forwardZ: Vector3 = standCf.LookVector

	-- 直接通过 CFrame 精确定位，避免物理碰撞导致穿模
	hrp.CFrame = standCf
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	-- 参考 RunwaySession 控制方式
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)

	-- 禁用玩家输入，禁止 WASD/跳跃/移动
	local controls = GetPlayerControls()
	if controls ~= nil then
		pcall(function()
			controls:Disable()
		end)
	end

	-- 隐藏器材 Prompt 按钮
	exercisePrompt = GetExercisePromptFromModel(equipmentModel)
	if exercisePrompt ~= nil then
		exercisePrompt.Enabled = false
	end

	-- 记录状态
	isExercising = true
	exerciseHumanoid = humanoid
	exerciseHrp = hrp
	exerciseForward = forwardZ
	exerciseEquipId = equipId
	EnsureExercisePopupPool()

	-- 打开锻炼 UI
	UIManager.OpenWindow(UIManager.WindowId.ExEquipFrame)
	UpdateExerciseInfoView()

	-- 站立稳定：前几帧保持 CFrame 精确定位，防止物理引擎推开人物
	local settleFrames: number = 0
	local settleThreshold: number = 5

	exerciseRunServiceConnection = runService.Heartbeat:Connect(function()
		if not isExercising or exerciseHumanoid == nil or exerciseHrp == nil then
			return
		end

		if settleFrames < settleThreshold then
			-- 稳定阶段：每帧强制拉回精确位置，等待物理碰撞体安顿
			exerciseHrp.CFrame = CFrame.lookAt(standPos, standPos + forwardZ)
			settleFrames += 1
			return
		end

		-- 稳定结束，锁定站立高度
		exerciseHrp.CFrame = CFrame.lookAt(standPos, standPos + forwardZ)

		if equipData.type == 2 then
			-- Bike 类型：播放专属骑行动画
			if exerciseBikeAnimTrack == nil then
				local animator: Animator? = exerciseHumanoid:FindFirstChildOfClass("Animator")
				if animator ~= nil then
					local bikeAnim = Instance.new("Animation")
					bikeAnim.AnimationId = "rbxassetid://78744145986758"
					exerciseBikeAnimTrack = animator:LoadAnimation(bikeAnim)
					exerciseBikeAnimTrack.Looped = true
					exerciseBikeAnimTrack:Play()
				end
			end
		else
			-- 其他类型：强制走/跑状态产生动画
			if exerciseHumanoid:GetState() ~= Enum.HumanoidStateType.Running
				and exerciseHumanoid:GetState() ~= Enum.HumanoidStateType.RunningNoPhysics then
				pcall(function()
					exerciseHumanoid:ChangeState(Enum.HumanoidStateType.Running)
				end)
			end
			exerciseHumanoid:Move(exerciseForward, false)
		end
	end)

	exerciseInputConnection = userInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
		if gameProcessedEvent then
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Space then
			if isExercising then
				NetMsg.FireRequestStopExercise()
			end
		end
	end)
end

local function StopExercise()
	if not isExercising then
		return
	end
	StopExerciseInternal()
end

--------------------------------------------------------------------
-- 初始化
--------------------------------------------------------------------

function ExEquipManager.Init()
	-- 监听库存更新
	NetMsg.ConnectNotifyPlayerExEquipInventoryUpdate(function(inventory: GameConfig.ExEquipInventory)
		ClientGameInfo.UpdateExEquipInventory(inventory)
		if isExercising then
			local currentId = tonumber(inventory.currentId) or 1
			if exerciseEquipId ~= currentId then
				StopExerciseWithServerRequest()
			end
		end
	end)

	-- 监听锻炼模式通知
	NetMsg.ConnectNotifyExerciseStart(function(equipId: number)
		StartExercise(equipId)
	end)
	NetMsg.ConnectNotifyExerciseEnd(function()
		StopExercise()
	end)

	-- 监听 JumpPower 更新
	NetMsg.ConnectNotifyPlayerJumpPowerUpdate(function(jumpPowerInfo: GameConfig.JumpPowerInfo, addExp: number)
		ClientGameInfo.UpdateJumpPower(jumpPowerInfo, addExp)
		UpdateExerciseInfoView()
		ShowExerciseJumpPowerPopup(addExp)
	end)

	ClientMsg.ConnectCurrentGuideTypeChanged(function()
		if ClientGameInfo.IsInJumpRunway() then
			StopExerciseWithServerRequest()
		end
	end)

	-- 角色死亡/移除时退出锻炼模式
	localPlayer.CharacterRemoving:Connect(function()
		StopExerciseWithServerRequest()
		CleanupExercisePopups()
	end)
	localPlayer.CharacterAdded:Connect(function(_character: Model)
		-- 如果还在锻炼状态（实际不应发生），清理状态
		StopExerciseWithServerRequest()
		CleanupExercisePopups()
	end)
end

return ExEquipManager
