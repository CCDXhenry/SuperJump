--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))

local function PlayerSaveInfoVersionUpdate1(playerSaveInfo: any)
	-- 工厂玩法停用，不再初始化 chestWorkbenchSave
	-- if playerSaveInfo.chestWorkbenchSave == nil then
	-- 	playerSaveInfo.chestWorkbenchSave = GameConfig.CreateDefaultChestWorkbenchSave()
	-- end
	playerSaveInfo.dataVersion = 1
end

return PlayerSaveInfoVersionUpdate1