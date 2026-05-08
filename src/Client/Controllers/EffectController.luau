-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)

--
local Effects = script.Parent.Parent.Effects

--
local RunEffect = BridgeNet2.ReferenceBridge("RunEffect")

--
local EffectController = {
	_effects = {},
}

function EffectController:RunEffect(effect: string, ...)
	local effectModule = self._effects[effect]
	if not effectModule then
		warn("Effect not found:", effect)
		return
	end

	return effectModule(...)
end

function EffectController:OnInit()
	local EffectsFolder = Instance.new("Folder")
	EffectsFolder.Name = "Effects"
	EffectsFolder.Parent = workspace

	for _, v in Effects:GetChildren() do
		local effect = require(v)
		self._effects[v.Name] = effect
	end
end

function EffectController:OnStart()
	RunEffect:Connect(function(data: { any })
		self:RunEffect(table.unpack(data))
	end)
end

return EffectController
