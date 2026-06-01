--!strict
-- Jetpack 模型节点解析：RootPart / Flame1 / Flame2 可为 Part 或 MeshPart。
local JetpackModelTool = {}

function JetpackModelTool.IsJetpackModelPart(instance: Instance): boolean
	return instance:IsA("Part") or instance:IsA("MeshPart")
end

function JetpackModelTool.FindJetpackModelPart(parent: Instance, partName: string): BasePart?
	local child = parent:FindFirstChild(partName)
	if child ~= nil and JetpackModelTool.IsJetpackModelPart(child) then
		return child :: BasePart
	end
	return nil
end

function JetpackModelTool.ResolvePrimaryPart(jetpackRoot: Model, rootPartName: string, assignPrimaryPart: boolean?): BasePart?
	local primaryPart = jetpackRoot.PrimaryPart
	if primaryPart ~= nil and JetpackModelTool.IsJetpackModelPart(primaryPart) then
		return primaryPart
	end
	local rootPart = JetpackModelTool.FindJetpackModelPart(jetpackRoot, rootPartName)
	if rootPart ~= nil then
		if assignPrimaryPart ~= false then
			jetpackRoot.PrimaryPart = rootPart
		end
		return rootPart
	end
	return nil
end

function JetpackModelTool.IsTemplateReady(template: Model?, rootPartName: string): boolean
	if template == nil or not template:IsA("Model") then
		return false
	end
	return JetpackModelTool.ResolvePrimaryPart(template, rootPartName, false) ~= nil
end

return JetpackModelTool
