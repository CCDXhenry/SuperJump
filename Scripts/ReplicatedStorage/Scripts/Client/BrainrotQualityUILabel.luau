--!strict
local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local TranslationTool = require(coreScripts:WaitForChild("Client"):WaitForChild("TranslationTool"))

local BrainrotQualityUILabel = {}

function BrainrotQualityUILabel.Apply(qualityLabel: TextLabel, quality: number)
	local qualityTextName = GameConfig.BrainrotQualityTextMap[quality]
	local qualityTextData = if qualityTextName then ((GameTexts :: any)[qualityTextName] :: { source: string, key: string }?) else nil
	if qualityTextData then
		TranslationTool.CustomAutoLocalizeTextLabel(qualityLabel, qualityTextData.source, qualityTextData.key, {})
	else
		local qualityCfg = GameConfig.BrainrotQualityConfig[quality]
		if qualityCfg then
			TranslationTool.CustomAutoLocalizeTextLabel(qualityLabel, qualityCfg.rarity, "", {})
		else
			TranslationTool.CustomAutoLocalizeTextLabel(qualityLabel, "", "", {})
		end
	end
	local qualityCfg = GameConfig.BrainrotQualityConfig[quality]
	if qualityCfg then
		qualityLabel.TextColor3 = qualityCfg.textColor
	end
end

return BrainrotQualityUILabel
