--!strict
-- 集中管理 ReplicatedStorage.Sounds 模板音效；播放走 SoundTool（不修改 SoundTool 源码）。
local GameSoundManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local SoundTool = require(coreSharedScripts:FindFirstChild("SoundTool"))

local soundsFolder: Folder = replicatedStorage:WaitForChild("Sounds") :: Folder
local openChestStartSound: Sound? = nil
local jettingSound: Sound? = nil
local missingSoundWarnedMap: { [string]: boolean } = {}

local function getTemplateSound(name: string): Sound?
	local inst = soundsFolder:FindFirstChild(name)
	if inst and inst:IsA("Sound") then
		return inst
	end
	if missingSoundWarnedMap[name] ~= true then
		missingSoundWarnedMap[name] = true
		warn("[GameSoundManager] Missing Sound in ReplicatedStorage.Sounds:", name)
	end
	return nil
end

local function playGlobalFromName(soundName: string)
	local template = getTemplateSound(soundName)
	if template then
		SoundTool.PlayGlobalSoundEffect(template, false)
	end
end

function GameSoundManager.PlayUpgradeAbilitySound()
	playGlobalFromName("UpgradeAbilitySound")
end

function GameSoundManager.PlayUpgradeHomeSound()
	playGlobalFromName("UpgradeHomeSound")
end

function GameSoundManager.PlaySellSound()
	playGlobalFromName("SellSound")
end

function GameSoundManager.PlayPickUpOrPutDownSound()
	playGlobalFromName("PickUpOrPutDownSound")
end

function GameSoundManager.PlayButtonClickSound()
	playGlobalFromName("ButtonClickSound")
end

function GameSoundManager.PlayJumpRunwayTakeoffSound()
	playGlobalFromName("JumpSound1")
	playGlobalFromName("JumpSound11")
end

function GameSoundManager.PlayJumpRunwayFinalTakeoffSound()
	playGlobalFromName("JumpSound2")
	playGlobalFromName("JumpSound21")
end

function GameSoundManager.PlayOpenChestStartSound()
	if openChestStartSound ~= nil and openChestStartSound.Parent ~= nil then
		return
	end
	local template = getTemplateSound("OpenChestSound1")
	if template == nil then
		return
	end
	openChestStartSound = SoundTool.PlayGlobalSoundEffect(template, true)
end

function GameSoundManager.StopOpenChestStartSound()
	if openChestStartSound == nil then
		return
	end
	SoundTool.StopDesignatedSoundEffect(openChestStartSound)
	openChestStartSound = nil
end

function GameSoundManager.PlayOpenChestRewardSound()
	GameSoundManager.StopOpenChestStartSound()
	playGlobalFromName("OpenChestSound2")
end

function GameSoundManager.PlayImpactSound()
	playGlobalFromName("ImpactSound")
end

function GameSoundManager.PlayJettingSound()
	if jettingSound ~= nil and jettingSound.Parent ~= nil then
		return
	end
	local template = getTemplateSound("JettingSound")
	if template == nil then
		return
	end
	jettingSound = SoundTool.PlayGlobalSoundEffect(template, true)
end

function GameSoundManager.StopJettingSound()
	if jettingSound == nil then
		return
	end
	SoundTool.StopDesignatedSoundEffect(jettingSound)
	jettingSound = nil
end

return GameSoundManager
