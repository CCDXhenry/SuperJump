--!strict
-- 客户端模型渲染预热：在屏幕外短暂实例化并等待若干帧，降低首次真实显示的 GPU/Shader 卡顿。
local RenderWarmupManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))

export type WarmupPrepareModel = (model: Model) -> ()

export type WarmupRequestOptions = {
	priority: number?,
	frameCount: number?,
	warmupCFrame: CFrame?,
	prepareModel: WarmupPrepareModel?,
}

export type WarmupRequest = {
	key: string,
	template: Instance,
	priority: number?,
	frameCount: number?,
	warmupCFrame: CFrame?,
	prepareModel: WarmupPrepareModel?,
}

local Priority = {
	P0 = 1,
	P1 = 2,
	P2 = 3,
}

local DefaultFrameCount: number = 2
local DefaultWarmupCFrame: CFrame = CFrame.new(0, -5000, 0)
local WarmupFolderName: string = "ClientRenderWarmup"

local warmupFolder: Folder? = nil
local requestMap: { [string]: WarmupRequest } = {}
local completedKeyMap: { [string]: boolean } = {}
local bucketCompleteMap: { [number]: boolean } = {}
local bucketRunningMap: { [number]: boolean } = {}

RenderWarmupManager.Priority = Priority

local function GetWarmupFolder(): Folder
	if warmupFolder ~= nil and warmupFolder.Parent ~= nil then
		return warmupFolder
	end

	local existing = workspace:FindFirstChild(WarmupFolderName)
	if existing ~= nil and existing:IsA("Folder") then
		warmupFolder = existing
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = WarmupFolderName
	folder.Parent = workspace
	warmupFolder = folder
	return folder
end

local function ResolvePriority(priority: number?): number
	if priority == Priority.P0 or priority == Priority.P1 or priority == Priority.P2 then
		return priority
	end
	return Priority.P2
end

local function ConfigureWarmupModel(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local part = descendant :: BasePart
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
		end
	end
end

local function WaitFrames(frameCount: number)
	local safeFrameCount = math.max(1, math.floor(frameCount))
	for _ = 1, safeFrameCount do
		task.wait()
	end
end

local function WarmupSingleRequest(request: WarmupRequest): boolean
	if completedKeyMap[request.key] then
		return true
	end

	local cloneSuccess, cloneResult = pcall(function()
		return GameConfig.CloneTemplateAsModel(request.template)
	end)
	if not cloneSuccess or cloneResult == nil then
		warn(string.format(
			"[RenderWarmupManager] Warmup clone failed key=%s template=%s err=%s",
			request.key,
			request.template:GetFullName(),
			tostring(cloneResult)
		))
		return false
	end

	local warmupModel = cloneResult :: Model
	warmupModel.Name = string.format("Warmup_%s", request.key)

	if request.prepareModel ~= nil then
		local prepareSuccess, prepareErr = pcall(request.prepareModel, warmupModel)
		if not prepareSuccess then
			warn(string.format(
				"[RenderWarmupManager] Warmup prepareModel failed key=%s err=%s",
				request.key,
				tostring(prepareErr)
			))
			warmupModel:Destroy()
			return false
		end
	end

	ConfigureWarmupModel(warmupModel)
	warmupModel:PivotTo(request.warmupCFrame or DefaultWarmupCFrame)
	warmupModel.Parent = GetWarmupFolder()

	WaitFrames(request.frameCount or DefaultFrameCount)
	warmupModel:Destroy()
	completedKeyMap[request.key] = true
	return true
end

function RenderWarmupManager.Register(request: WarmupRequest): boolean
	if request.key == "" then
		warn("[RenderWarmupManager] Register skipped: empty key")
		return false
	end
	if request.template.Parent == nil then
		warn(string.format("[RenderWarmupManager] Register skipped: template missing parent key=%s", request.key))
		return false
	end

	local normalizedRequest: WarmupRequest = {
		key = request.key,
		template = request.template,
		priority = ResolvePriority(request.priority),
		frameCount = request.frameCount,
		warmupCFrame = request.warmupCFrame,
		prepareModel = request.prepareModel,
	}

	local existingRequest = requestMap[request.key]
	if existingRequest ~= nil then
		local existingPriority = ResolvePriority(existingRequest.priority)
		local newPriority = normalizedRequest.priority :: number
		if newPriority >= existingPriority then
			return true
		end
	end

	requestMap[request.key] = normalizedRequest
	completedKeyMap[request.key] = false
	return true
end

function RenderWarmupManager.RegisterResourceTemplate(
	folder: Instance?,
	resourceName: string,
	key: string,
	options: WarmupRequestOptions?
): boolean
	if folder == nil or resourceName == "" or key == "" then
		return false
	end

	local template = GameConfig.FindResourceTemplateByResourceName(folder, resourceName)
	if template == nil then
		warn(string.format(
			"[RenderWarmupManager] RegisterResourceTemplate missing template resourceName=%s folder=%s",
			resourceName,
			folder:GetFullName()
		))
		return false
	end

	return RenderWarmupManager.Register({
		key = key,
		template = template,
		priority = options and options.priority,
		frameCount = options and options.frameCount,
		warmupCFrame = options and options.warmupCFrame,
		prepareModel = options and options.prepareModel,
	})
end

function RenderWarmupManager.IsKeyComplete(key: string): boolean
	return completedKeyMap[key] == true
end

function RenderWarmupManager.IsBucketComplete(priority: number): boolean
	return bucketCompleteMap[priority] == true
end

function RenderWarmupManager.IsBucketRunning(priority: number): boolean
	return bucketRunningMap[priority] == true
end

function RenderWarmupManager.RunBucket(priority: number): number
	if bucketCompleteMap[priority] or bucketRunningMap[priority] then
		return 0
	end

	bucketRunningMap[priority] = true
	local bucketStartTime = os.clock()
	local candidateCount = 0
	local successCount = 0
	local failedCount = 0

	for _, request in pairs(requestMap) do
		if ResolvePriority(request.priority) ~= priority then
			continue
		end
		if completedKeyMap[request.key] then
			continue
		end

		candidateCount += 1
		if WarmupSingleRequest(request) then
			successCount += 1
		else
			failedCount += 1
		end
	end

	bucketRunningMap[priority] = false
	bucketCompleteMap[priority] = true

	print(string.format(
		"[RenderWarmupManager] RunBucket %s complete. candidates=%d success=%d failed=%d elapsed=%.2fs",
		if priority == Priority.P0 then "P0" elseif priority == Priority.P1 then "P1" else "P2",
		candidateCount,
		successCount,
		failedCount,
		os.clock() - bucketStartTime
	))

	return successCount
end

function RenderWarmupManager.RunAll()
	for _, priority in ipairs({ Priority.P0, Priority.P1, Priority.P2 }) do
		RenderWarmupManager.RunBucket(priority)
	end
end

function RenderWarmupManager.WaitForBucket(priority: number, maxWaitSeconds: number?): boolean
	if RenderWarmupManager.IsBucketComplete(priority) then
		return true
	end

	local deadline = os.clock() + (maxWaitSeconds or 5)
	while not RenderWarmupManager.IsBucketComplete(priority) and os.clock() < deadline do
		task.wait()
	end

	if RenderWarmupManager.IsBucketComplete(priority) then
		return true
	end

	warn(string.format(
		"[RenderWarmupManager] WaitForBucket timeout priority=%d after %.2fs",
		priority,
		maxWaitSeconds or 5
	))
	return false
end

return RenderWarmupManager
