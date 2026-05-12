--!strict
-- 工作台存档键：优先 WorkbenchSaveKey；否则 WorkbenchId；同槽多台同 Id 时自动加后缀，与 ChestWorkbenchManager.BuildRegistry 一致。
local ChestWorkbenchSaveKeyUtil = {}

local function collectSortedWorkbenchSiblings(parent: Instance): { Model }
	local list: { Model } = {}
	for _, ch in parent:GetChildren() do
		if ch:IsA("Model") then
			table.insert(list, ch)
		end
	end
	table.sort(list, function(a, b)
		if a.Name == b.Name then
			return a:GetFullName() < b:GetFullName()
		end
		return a.Name < b.Name
	end)
	return list
end

function ChestWorkbenchSaveKeyUtil.ResolveSaveKey(workbenchModel: Model): string
	local attrSave = workbenchModel:GetAttribute("WorkbenchSaveKey") :: string?
	if attrSave and attrSave ~= "" then
		return attrSave
	end
	local wcfgId = tonumber(workbenchModel:GetAttribute("WorkbenchId")) or 1
	local parent = workbenchModel.Parent
	if parent == nil then
		return tostring(wcfgId)
	end
	local siblings = collectSortedWorkbenchSiblings(parent)
	local sameConfigNoKey = 0
	for _, m in ipairs(siblings) do
		local sk = m:GetAttribute("WorkbenchSaveKey") :: string?
		if (not sk or sk == "") and (tonumber(m:GetAttribute("WorkbenchId")) or 1) == wcfgId then
			sameConfigNoKey += 1
		end
	end
	if sameConfigNoKey <= 1 then
		return tostring(wcfgId)
	end
	local idxInGroup = 0
	for _, m in ipairs(siblings) do
		local sk = m:GetAttribute("WorkbenchSaveKey") :: string?
		if (not sk or sk == "") and (tonumber(m:GetAttribute("WorkbenchId")) or 1) == wcfgId then
			idxInGroup += 1
			if m == workbenchModel then
				if idxInGroup == 1 then
					return tostring(wcfgId)
				end
				return tostring(wcfgId) .. "_" .. tostring(idxInGroup)
			end
		end
	end
	return tostring(wcfgId)
end

return ChestWorkbenchSaveKeyUtil
