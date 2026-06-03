-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

-- Assets
local Assets = ReplicatedStorage.Assets
local Effects = Assets.Effects
local CoinEffect = Effects.Coin

--
local LocalPlayer = Players.LocalPlayer

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

	local highlight = Instance.new("Highlight")
	highlight.OutlineTransparency = 1
	highlight.FillTransparency = 0.5
	highlight.FillColor = Color3.fromRGB(255, 170, 0)
	highlight.Parent = character

	TweenService:Create(highlight, TweenInfo.new(0.5), { FillTransparency = 1 }):Play()
	task.delay(0.5, function()
		highlight:Destroy()
	end)

	if player == LocalPlayer then
		SoundController:PlaySound("ReceivedCoins")
	else
		SoundController:PlaySound("ReceivedCoins", rootPart.Position)
	end
end
