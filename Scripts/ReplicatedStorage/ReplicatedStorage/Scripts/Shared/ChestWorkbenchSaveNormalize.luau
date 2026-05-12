--!strict
-- 将 chestWorkbenchSave 规范为：purchasedWorkbenchUpgradeIds 仅在顶层，键为 rowId 字符串（JSON object）。
-- 合并历史上误写在 workbenches[*].purchasedWorkbenchUpgradeIds 的数据；兼容 number/string 键来源。
local ChestWorkbenchSaveNormalize = {}

local hasWarnedInvalidPurchasedEntry = false

local function parsePurchasedRowIdKey(k: any): number?
	local rowId: number?
	if type(k) == "number" then
		rowId = k
	elseif type(k) == "string" then
		rowId = tonumber(k)
	else
		return nil
	end
	if rowId == nil then
		return nil
	end
	if rowId < 1 or rowId % 1 ~= 0 then
		return nil
	end
	return rowId
end

local function purchasedValueIsSet(v: any): boolean
	return v == true or v == 1 or v == "true"
end

local function warnInvalidPurchasedEntry(k: any, v: any)
	if hasWarnedInvalidPurchasedEntry then
		return
	end
	hasWarnedInvalidPurchasedEntry = true
	warn(
		"[ChestWorkbenchSaveNormalize] Ignore invalid purchasedWorkbenchUpgradeIds entry; expected string rowId map, keyType=",
		typeof(k),
		" valueType=",
		typeof(v)
	)
end

local function mergePurchasedInto(dst: { [string]: boolean }, src: any)
	if type(src) ~= "table" then
		return
	end
	local t = src :: { [any]: any }
	for k, v in pairs(t) do
		local rowId = parsePurchasedRowIdKey(k)
		if rowId then
			if purchasedValueIsSet(v) then
				dst[tostring(rowId)] = true
			end
		elseif v ~= nil then
			warnInvalidPurchasedEntry(k, v)
		end
	end
end

function ChestWorkbenchSaveNormalize.Apply(save: any)
	if type(save) ~= "table" then
		return
	end
	if save.workbenches == nil or type(save.workbenches) ~= "table" then
		save.workbenches = {}
	end
	local merged: { [string]: boolean } = {}
	mergePurchasedInto(merged, save.purchasedWorkbenchUpgradeIds)
	for _, wbAny in pairs(save.workbenches :: { [any]: any }) do
		if type(wbAny) == "table" then
			local wb = wbAny :: { [any]: any }
			mergePurchasedInto(merged, wb.purchasedWorkbenchUpgradeIds)
			wb.purchasedWorkbenchUpgradeIds = nil
		end
	end
	save.purchasedWorkbenchUpgradeIds = merged
end

return ChestWorkbenchSaveNormalize
