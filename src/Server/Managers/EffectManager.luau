-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)

--
local EffectManager = {
	ReplicateEffectEvent = BridgeNet2.ReferenceBridge("ReplicateEffect"),
	RunEffect = BridgeNet2.ReferenceBridge("RunEffect"),
}

function EffectManager:OnStart()
	self.ReplicateEffectEvent:Connect(function(player: Player, data: { any })
		self.RunEffect:Fire(BridgeNet2.PlayersExcept({ player }), data)
	end)
end

return EffectManager
