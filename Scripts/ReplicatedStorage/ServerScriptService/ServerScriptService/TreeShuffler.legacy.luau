-- TreeShuffler: Shuffles tree & stone folders between zones on server startup
local treeFolder = workspace:FindFirstChild("tree")
local zoneFolder = workspace:FindFirstChild("Ground") and workspace.Ground:FindFirstChild("Zone")

if not treeFolder or not zoneFolder then
    warn("[TreeShuffler] tree folder or Ground.Zone not found!")
    return
end

print("[TreeShuffler] Initiating environment prop (trees & stones) shuffle...")

-- 1. Gather all zone parts and tree sub-folders
local zoneParts = {}
for _, child in ipairs(zoneFolder:GetChildren()) do
    if child:IsA("BasePart") then
        zoneParts[child.Name] = child
    end
end

local originalFolders = {}
local validZoneNames = {}
for _, child in ipairs(treeFolder:GetChildren()) do
    if child:IsA("Folder") and zoneParts[child.Name] then
        originalFolders[child.Name] = child
        table.insert(validZoneNames, child.Name)
    end
end

if #validZoneNames == 0 then
    warn("[TreeShuffler] No valid zone folders found under workspace.tree!")
    return
end

-- 2. Create shuffled list of target zones
local targetZoneNames = {unpack(validZoneNames)}
local rng = Random.new()

-- Fisher-Yates shuffle
for i = #targetZoneNames, 2, -1 do
    local j = rng:NextInteger(1, i)
    targetZoneNames[i], targetZoneNames[j] = targetZoneNames[j], targetZoneNames[i]
end

-- 3. Create a temporary container folder
local tempContainer = Instance.new("Folder")
tempContainer.Name = "TempTreeShuffleContainer"
tempContainer.Parent = workspace

-- 4. Move and transform trees & stones into new temp folders
for i, originName in ipairs(validZoneNames) do
    local targetName = targetZoneNames[i]
    
    local originPart = zoneParts[originName]
    local targetPart = zoneParts[targetName]
    local originSubFolder = originalFolders[originName]
    
    -- Create the new folder under temp container
    local newSubFolder = Instance.new("Folder")
    newSubFolder.Name = targetName
    newSubFolder.Parent = tempContainer
    
    -- Calculate transformation CFrame
    local originCFrameInv = originPart.CFrame:Inverse()
    local targetCFrame = targetPart.CFrame
    
    for _, item in ipairs(originSubFolder:GetChildren()) do
        if item:IsA("Model") or item:IsA("BasePart") then
            local relCFrame = originCFrameInv * item:GetPivot()
            local newCFrame = targetCFrame * relCFrame
            
            item:PivotTo(newCFrame)
            item.Parent = newSubFolder
        end
    end
end

-- 5. Clear old folders under workspace.tree
treeFolder:ClearAllChildren()

-- 6. Move new folders from temp container to workspace.tree and clean up
for _, folder in ipairs(tempContainer:GetChildren()) do
    folder.Parent = treeFolder
end
tempContainer:Destroy()

print("[TreeShuffler] Successfully shuffled " .. tostring(#validZoneNames) .. " environment zones (trees & stones) on server startup!")
