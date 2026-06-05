-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

--
local LocalPlayer = Players.LocalPlayer

--
local RoundController = require(script.Parent.Parent.Controllers.RoundController)

--
return function()
	local bomb = RoundController:GetBomb()
	if not bomb or not bomb.Parent then
		return
	end

	local nuke = bomb:Clone()
	nuke:PivotTo(bomb:GetPivot())
	nuke.Parent = bomb.Parent

	local highlight = Instance.new("Highlight")
	highlight.OutlineTransparency = 1
	highlight.FillColor = Color3.fromRGB(255, 255, 255)
	highlight.Parent = nuke

	TweenService:Create(highlight, TweenInfo.new(0.5), { FillTransparency = 0 }):Play()
	task.delay(0.5, function()
		if nuke then
			nuke:Destroy()
		end

		-- Shake the camera
		local localPlayer = Players.LocalPlayer
		local CameraController = require(localPlayer.PlayerScripts.Client.Controllers.CameraController)
		local SoundController = require(localPlayer.PlayerScripts.Client.Controllers.SoundController)

		CameraController:ShakeCustom(4, 8, 0.1, 5)
		SoundController:PlaySound("NukeExplosion")
	end)

	--
	task.spawn(function()
		task.wait(0.5)
		local colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Name = `{LocalPlayer.Name}_NukeColorCorrection`
		colorCorrection.Parent = game.Lighting

		TweenService
			:Create(colorCorrection, TweenInfo.new(1, Enum.EasingStyle.Sine), { Brightness = 1, Saturation = 1 })
			:Play()
		task.wait(2)
		TweenService
			:Create(colorCorrection, TweenInfo.new(5, Enum.EasingStyle.Linear), { Brightness = 0, Saturation = 0 })
			:Play()

		task.wait(5)
		colorCorrection:Destroy()
	end)
end
