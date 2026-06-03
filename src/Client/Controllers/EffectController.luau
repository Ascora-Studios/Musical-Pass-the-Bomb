-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)

--
local Effects = script.Parent.Parent.Effects

--

--
local EffectController = {
	RunEffectEvent = BridgeNet2.ReferenceBridge("RunEffect"),
	ReplicateEffectEvent = BridgeNet2.ReferenceBridge("ReplicateEffect"),

	_effects = {},
}

function EffectController:RunEffect(effect: string, data: { any }, replicate: boolean?)
	local effectModule = self._effects[effect]
	if not effectModule then
		warn("Effect not found:", effect)
		return
	end

	local isTable = typeof(data) == "table"
	if not isTable then
		data = { data }
	end

	if replicate then
		self.ReplicateEffectEvent:Fire({ effect, data })
	end

	-- pretty hardcoded but im lazy bru
	return effectModule(if effect == "Confetti" then data else table.unpack(data))
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
	self.RunEffectEvent:Connect(function(data: { any })
		self:RunEffect(table.unpack(data))
	end)
end

return EffectController
