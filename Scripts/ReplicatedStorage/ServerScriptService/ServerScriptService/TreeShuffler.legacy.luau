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
local activeZones = {}
for _, child in ipairs(zoneFolder:GetChildren()) do
    if child:IsA("BasePart") then
        local index = tonumber(child.Name:match("%d+"))
        if index then
            zoneParts[child.Name] = child
            table.insert(activeZones, { name = child.Name, part = child, index = index })
        end
    end
end
table.sort(activeZones, function(a, b) return a.index < b.index end)

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
    
    local originCFrameInv = originPart.CFrame:Inverse()
    local targetCFrame = targetPart.CFrame
    local originL = originPart.Size.X
    local targetL = targetPart.Size.X
    
    -- Gather original items
    local origItems = {}
    for _, item in ipairs(originSubFolder:GetChildren()) do
        if item:IsA("Model") or item:IsA("BasePart") then
            table.insert(origItems, item)
        end
    end
    
    if #origItems > 0 then
        -- Calculate target quantity based on size ratio
        local target_count = math.round(#origItems * (targetL / originL))
        if targetName == "Zone1" or targetName == "Zone2" or targetName == "Zone3" then
            target_count = math.round(target_count / 2)
        end
        target_count = math.max(1, target_count) -- ensure at least 1 item
        
        if target_count <= #origItems then
            -- Shuffle origItems to pick randomly without repeating
            local selectedItems = {unpack(origItems)}
            for k = #selectedItems, 2, -1 do
                local r = rng:NextInteger(1, k)
                selectedItems[k], selectedItems[r] = selectedItems[r], selectedItems[k]
            end
            
            for k = 1, target_count do
                local item = selectedItems[k]
                local relCFrame = originCFrameInv * item:GetPivot()
                local localX = relCFrame.Position.X * (targetL / originL)
                localX = math.clamp(localX, -targetL/2 + 2, targetL/2 - 2)
                
                local newRelCFrame = CFrame.new(localX, relCFrame.Position.Y, relCFrame.Position.Z) * (relCFrame - relCFrame.Position)
                local newCFrame = targetCFrame * newRelCFrame
                
                item:PivotTo(newCFrame)
                item.Parent = newSubFolder
            end
        else
            -- We need to duplicate items
            -- First place all original items scaled
            for _, item in ipairs(origItems) do
                local relCFrame = originCFrameInv * item:GetPivot()
                local localX = relCFrame.Position.X * (targetL / originL)
                localX = math.clamp(localX, -targetL/2 + 2, targetL/2 - 2)
                
                local newRelCFrame = CFrame.new(localX, relCFrame.Position.Y, relCFrame.Position.Z) * (relCFrame - relCFrame.Position)
                local newCFrame = targetCFrame * newRelCFrame
                
                item:PivotTo(newCFrame)
                item.Parent = newSubFolder
            end
            
            -- Then clone extra items to fill target_count
            local extra_to_clone = target_count - #origItems
            for k = 1, extra_to_clone do
                -- Pick a random original item
                local baseItem = origItems[rng:NextInteger(1, #origItems)]
                local clonedItem = baseItem:Clone()
                
                local relCFrame = originCFrameInv * baseItem:GetPivot()
                -- Generate a completely random X position within target zone boundaries
                local localX = rng:NextNumber(-targetL/2 + 2, targetL/2 - 2)
                
                local newRelCFrame = CFrame.new(localX, relCFrame.Position.Y, relCFrame.Position.Z) * (relCFrame - relCFrame.Position)
                local newCFrame = targetCFrame * newRelCFrame
                
                clonedItem:PivotTo(newCFrame)
                clonedItem.Parent = newSubFolder
            end
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

-- 7. Randomize zone floor texture colors sequentially (ensuring no consecutive repeats)
local presets = {
    Color3.fromRGB(0, 230, 255),    -- Neon Cyan
    Color3.fromRGB(120, 255, 0),    -- Bright Lime
    Color3.fromRGB(180, 70, 255),   -- Electric Purple
    Color3.fromRGB(255, 90, 200),   -- Candy Pink
    Color3.fromRGB(255, 220, 0),    -- Sunny Yellow
    Color3.fromRGB(255, 130, 0),    -- Vibrant Orange
    Color3.fromRGB(0, 160, 255),    -- Sky Blue
    Color3.fromRGB(0, 255, 170)     -- Bright Mint
}

local lastColorIndex = 0
for _, zoneInfo in ipairs(activeZones) do
    local part = zoneInfo.part
    local texture = part:FindFirstChild("Texture")
    if texture and texture:IsA("Texture") then
        local colorIndex
        repeat
            colorIndex = rng:NextInteger(1, #presets)
        until colorIndex ~= lastColorIndex
        
        lastColorIndex = colorIndex
        texture.Color3 = presets[colorIndex]
    end
end

print("[TreeShuffler] Successfully shuffled " .. tostring(#validZoneNames) .. " environment zones (trees & stones) and randomized floor colors on server startup!")
