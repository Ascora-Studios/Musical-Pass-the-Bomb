-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

-- Local Player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

--
local IntroController = {}

function IntroController:RunIntro()
	--
	local ui = self.UI
	local holder = ui.Holder
	local dim = ui.Dim

	--
	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local humanoid: Humanoid = character.Humanoid

	--
	humanoid.CameraOffset = Vector3.new(0, 5, 0)
	task.wait(5)

	--
	TweenService:Create(dim, TweenInfo.new(2.5, Enum.EasingStyle.Quad), {
		BackgroundTransparency = 1,
	}):Play()

	TweenService:Create(holder, TweenInfo.new(2.5, Enum.EasingStyle.Quad), {
		GroupTransparency = 1,
	}):Play()

	TweenService:Create(humanoid, TweenInfo.new(2, Enum.EasingStyle.Sine), {
		CameraOffset = Vector3.new(0, 0, 0),
	}):Play()

	task.wait(5)
	self.UI:Destroy()
end

function IntroController:OnInit()
	self.UI = PlayerGui:WaitForChild("IntroUI")
	self.UI.Enabled = true
	task.spawn(IntroController.RunIntro, self)
end

return IntroController
