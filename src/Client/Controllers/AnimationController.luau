-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages
local Replica = require(Packages.Replica)

-- Shared
local Shared = ReplicatedStorage.Shared
local Animations = require(Shared.Animations)

-- Local Player
local LocalPlayer = Players.LocalPlayer

--
local AnimationController = {
	_animationTracks = {},
}

function AnimationController:PlayAnimation(animationName: string)
	local animationTrack = self._animationTracks[animationName]
	if not animationTrack then
		warn("Animation not found:", animationName)
		return
	end

	animationTrack:Play()
end

function AnimationController:StopAnimation(animationName: string)
	local animationTrack = self._animationTracks[animationName]
	if not animationTrack then
		warn("Animation not found:", animationName)
		return
	end

	animationTrack:Stop()
end

function AnimationController:_initAnimations()
	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

	for animationName, animatiodId in Animations do
		--
		local animation = Instance.new("Animation")
		animation.Name = animationName
		animation.AnimationId = animatiodId

		local animationTrack = character.Humanoid.Animator:LoadAnimation(animation)
		self._animationTracks[animationName] = animationTrack
	end
end

function AnimationController:OnInit()
	LocalPlayer.CharacterAdded:Connect(function()
		self:_initAnimations()
	end)

	self:_initAnimations()
end

return AnimationController
