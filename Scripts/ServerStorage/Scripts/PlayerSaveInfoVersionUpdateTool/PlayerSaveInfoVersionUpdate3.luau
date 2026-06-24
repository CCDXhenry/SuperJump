--!strict

local function PlayerSaveInfoVersionUpdate3(playerSaveInfo: any)
	if playerSaveInfo.jumpRunwayMaxZoneId == nil then
		playerSaveInfo.jumpRunwayMaxZoneId = 0
	end
	playerSaveInfo.dataVersion = 3
end

return PlayerSaveInfoVersionUpdate3
