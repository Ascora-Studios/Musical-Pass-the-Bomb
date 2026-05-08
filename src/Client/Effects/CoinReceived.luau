-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Assets
local Assets = ReplicatedStorage.Assets
local Effects = Assets.Effects
local CoinEffect = Effects.Coin

--
local SoundController = require(script.Parent.Parent.Controllers.SoundController)

return function(player)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character.HumanoidRootPart

	--
	local coinEffect = CoinEffect:Clone()
	coinEffect.Parent = rootPart

	for _, v in coinEffect:GetChildren() do
		if v:IsA("ParticleEmitter") then
			v:Emit(v:GetAttribute("EmitCount") or 10)
		end
	end

	task.delay(3, function()
		coinEffect:Destroy()
	end)

	SoundController:PlaySound("ReceivedCoins")
end
