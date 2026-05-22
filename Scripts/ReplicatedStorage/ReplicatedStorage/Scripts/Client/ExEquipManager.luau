--!strict
local ExEquipManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local players: Players = game:GetService("Players")
local workspace: Workspace = game:GetService("Workspace")
local runService: RunService = game:GetService("RunService")
local localPlayer: Player? = players.LocalPlayer

if localPlayer == nil then
	return ExEquipManager
end

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local UIManager = require(clientScripts:FindFirstChild("UIManager"))

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

local modelsFolder = replicatedStorage:FindFirstChild("Models")
local exEquipModelsFolder: Folder? = if modelsFolder ~= nil then modelsFolder:FindFirstChild("ExEquip") :: Folder? else nil

-- 锻炼模式常量
-- 人物躯干高度（HumanoidRootPart 到脚底的参考偏移）
local CHARACTER_TORSO_HEIGHT: number = 3

-- 锻炼模式状态
local isExercising: boolean = false
local exerciseHumanoid: Humanoid? = nil
local exerciseHrp: BasePart? = nil
local exerciseForward: Vector3 = Vector3.zero
local exerciseRunServiceConnection: RBXScriptConnection? = nil
local exercisePrompt: ProximityPrompt? = nil
local exerciseBikeAnimTrack: AnimationTrack? = nil

--------------------------------------------------------------------
-- 锻炼模式逻辑
--------------------------------------------------------------------

local function StopExerciseInternal()
	if exerciseRunServiceConnection ~= nil then
		exerciseRunServiceConnection:Disconnect()
		exerciseRunServiceConnection = nil
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

	-- 恢复器材 Prompt 按钮
	if exercisePrompt ~= nil then
		exercisePrompt.Enabled = true
		exercisePrompt = nil
	end

	-- 停止 Bike 专属动画
	if exerciseBikeAnimTrack ~= nil then
		exerciseBikeAnimTrack:Stop()
		exerciseBikeAnimTrack:Destroy()
		exerciseBikeAnimTrack = nil
	end

	-- 关闭锻炼 UI
	UIManager.CloseWindow(UIManager.WindowId.ExEquipFrame)

	isExercising = false
	exerciseHumanoid = nil
	exerciseHrp = nil
	exerciseForward = Vector3.zero
end

--------------------------------------------------------------------
-- 模型替换逻辑
--------------------------------------------------------------------

local function GetExercise1Model(): Model?
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil then
		return nil
	end

	local homeSlot = localPlayerInfo.homeSlot
	if homeSlot == nil or homeSlot == "" then
		return nil
	end

	local homesFolder = workspace:FindFirstChild("PlayersHome")
	if homesFolder == nil then
		return nil
	end

	local slotModel: Model? = homesFolder:FindFirstChild(homeSlot) :: Model?
	if slotModel == nil then
		return nil
	end

	local exerciseArea: Model? = slotModel:FindFirstChild("ExerciseArea") :: Model?
	if exerciseArea == nil then
		return nil
	end

	return exerciseArea:FindFirstChild("Exercise1") :: Model?
end

local function GetExercisePromptFromModel(exerciseModel: Model): ProximityPrompt?
	local promptAttachment: Attachment? = exerciseModel:FindFirstChild("Attachment") :: Attachment?
	if promptAttachment == nil then
		return nil
	end
	return promptAttachment:FindFirstChild("ProximityPrompt") :: ProximityPrompt?
end

local function DoReplace(exEquipId: number, equipData: GameConfig.ExEquipData, exercise1: Model)
	if exEquipModelsFolder == nil then
		return
	end

	local sourceModel = exEquipModelsFolder:FindFirstChild(equipData.resourceName) :: Model?
	if sourceModel == nil then
		return
	end

	-- 记录 Exercise1 的 Parent 和完整变换（位置+朝向）
	local exerciseArea: Instance? = exercise1.Parent
	local targetCf: CFrame = exercise1:GetPivot()

	-- 将源模型 Clone 到 Workspace，原封不动对齐到旧模型的位置和朝向
	local newModel: Model = sourceModel:Clone()
	newModel.Name = "Exercise1"
	newModel.Parent = exerciseArea
	newModel:PivotTo(targetCf)

	-- 销毁旧的 Exercise1
	exercise1:Destroy()

	-- 绑定锻炼 Prompt
	local promptAttachment: Attachment? = newModel:FindFirstChild("Attachment") :: Attachment?
	if promptAttachment ~= nil then
		local prompt: ProximityPrompt? = promptAttachment:FindFirstChild("ProximityPrompt") :: ProximityPrompt?
		if prompt ~= nil then
			prompt.Triggered:Connect(function(triggerPlayer: Player)
				if triggerPlayer ~= localPlayer then
					return
				end
				if isExercising then
					NetMsg.FireRequestStopExercise()
				else
					NetMsg.FireRequestStartExercise(exEquipId)
				end
			end)
		end
	end
end

local function ReplaceExEquipModel(exEquipId: number)
	-- 切换器材时自动退出当前锻炼模式
	if isExercising then
		StopExerciseInternal()
	end

	local equipData = GameConfig.ExEquipDataMap[exEquipId]
	if equipData == nil then
		return
	end

	local exercise1 = GetExercise1Model()
	if exercise1 == nil then
		-- Exercise1 还没准备好，延迟重试
		task.spawn(function()
			local retryCount = 0
			while retryCount < 60 do
				task.wait(0.5)
				exercise1 = GetExercise1Model()
				if exercise1 ~= nil then
					break
				end
				retryCount += 1
			end
			if exercise1 == nil then
				return
			end
			DoReplace(exEquipId, equipData, exercise1)
		end)
		return
	end

	DoReplace(exEquipId, equipData, exercise1)
end

--------------------------------------------------------------------
-- 锻炼模式逻辑
--------------------------------------------------------------------

local function StartExercise(equipId: number)
	-- 如果已在锻炼中，先停止
	if isExercising then
		StopExerciseInternal()
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

	-- 从 Exercise1 下找到实际克隆的器材模型来计算位置
	local exercise1 = GetExercise1Model()
	if exercise1 == nil then
		return
	end

	local equipmentModel: Model = exercise1

	-- 计算器材模型的实际位置和 Z 轴正方向
	local modelRootPart: BasePart? = equipmentModel.PrimaryPart
	local rootCf: CFrame
	if modelRootPart ~= nil then
		rootCf = modelRootPart.CFrame
	else
		rootCf = equipmentModel:GetModelCFrame()
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

	-- 直接通过 CFrame 精确定位，避免物理碰撞导致穿模
	hrp.CFrame = CFrame.lookAt(standPos, standPos + forwardZ)
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
	exercisePrompt = GetExercisePromptFromModel(exercise1)
	if exercisePrompt ~= nil then
		exercisePrompt.Enabled = false
	end

	-- 打开锻炼 UI
	UIManager.OpenWindow(UIManager.WindowId.ExEquipFrame)

	-- 记录状态
	isExercising = true
	exerciseHumanoid = humanoid
	exerciseHrp = hrp
	exerciseForward = forwardZ

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
	-- 立即尝试初始替换（此时 LocalPlayerInfoInit 已触发，直接使用当前信息）
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo ~= nil then
		ReplaceExEquipModel(tonumber(localPlayerInfo.exEquipInventory.currentId) or 1)
	end

	-- 监听库存更新
	NetMsg.ConnectNotifyPlayerExEquipInventoryUpdate(function(inventory: GameConfig.ExEquipInventory)
		ClientGameInfo.UpdateExEquipInventory(inventory)
		ReplaceExEquipModel(tonumber(inventory.currentId) or 1)
	end)

	-- 监听家园信息更新（homeSlot 可能异步就绪）
	ClientMsg.ConnectPlayerHomeInfoUpdate(function(_playerId: number, _homeSlot: string, _homeInfo: any, _rebirthLevel: number?)
		local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
		if localPlayerInfo ~= nil then
			ReplaceExEquipModel(tonumber(localPlayerInfo.exEquipInventory.currentId) or 1)
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
	NetMsg.ConnectNotifyPlayerJumpPowerUpdate(function(newValue: number, addAmount: number)
		ClientGameInfo.UpdateJumpPower(newValue, addAmount)
	end)

	-- 角色死亡/移除时退出锻炼模式
	localPlayer.CharacterRemoving:Connect(function()
		StopExercise()
	end)
	localPlayer.CharacterAdded:Connect(function(_character: Model)
		-- 如果还在锻炼状态（实际不应发生），清理状态
		StopExercise()
	end)
end

return ExEquipManager
