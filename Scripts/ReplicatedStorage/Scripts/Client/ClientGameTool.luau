--!strict
local ClientGameTool = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

function ClientGameTool.SetRewardIconImage(rewardIconImage: ImageLabel, rewardType: number, rewardId: number)
	if rewardType == GameConfig.RewardType.Currency then
		if rewardId == GameConfig.CurrencyType.Coin then
			rewardIconImage.Image = GameConfig.CoinIconImage
		end
		return
	end
	if rewardType == GameConfig.RewardType.Brainrot then
		local brainrotData = GameConfig.BrainrotIdMap[rewardId]
		rewardIconImage.Image = if brainrotData then brainrotData.iconImageId else ""
		return
	end
	if rewardType == GameConfig.RewardType.Coil then
		local coilData = GameConfig.CoilIdMap[rewardId]
		rewardIconImage.Image = if coilData then coilData.iconImageId else ""
		return
	end
	if rewardType == GameConfig.RewardType.LittleElfChest then
		local chestData = GameConfig.LittleElfChestIdMap[rewardId]
		rewardIconImage.Image = if chestData then chestData.iconImageId else ""
		return
	end
	if rewardType == GameConfig.RewardType.Buff then
		local buffData = GameConfig.BuffIdMap[rewardId]
		rewardIconImage.Image = if buffData then buffData.iconImageId else ""
		return
	end
	if rewardType == GameConfig.RewardType.Jetpack then
		local jetpackData = GameConfig.JetpackDataMap[rewardId]
		rewardIconImage.Image = if jetpackData then jetpackData.iconImageId else ""
		return
	end
	if rewardType == GameConfig.RewardType.ExEquip then
		local equipData = GameConfig.ExEquipDataMap[rewardId]
		rewardIconImage.Image = if equipData then equipData.iconImageId else ""
		return
	end
	rewardIconImage.Image = ""
end

function ClientGameTool.GetCountDownText(countDown: number): string
	local second = math.floor(countDown % 60)
	local minute = math.floor(countDown / 60 % 60)
	local hour = math.floor(countDown / 60 / 60)
	local hourText = ""
	local minuteText = ""
	local secondText = ""
	if hour > 0 then
		if hour < 10 then
			hourText = "0"
		end
		hourText = hourText .. hour .. ":"
	end
	if minute < 10 then
		minuteText = "0"
	end
	minuteText = minuteText .. minute .. ":"
	if second < 10 then
		secondText = "0"
	end
	secondText = secondText .. second
	return hourText .. minuteText .. secondText
end

return ClientGameTool
