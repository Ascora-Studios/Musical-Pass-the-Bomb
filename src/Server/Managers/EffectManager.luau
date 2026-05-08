-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)

--
local EffectManager = {
	RunEffect = BridgeNet2.ReferenceBridge("RunEffect"),
}

return EffectManager
