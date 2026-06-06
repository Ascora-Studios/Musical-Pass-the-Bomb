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
	local animationTrack = self._animationTracks[animationName] or self:_loadAnimation(animationName)
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

function AnimationController:_loadAnimation(animationName: string)
	local animationId = Animations[animationName]
	if not animationId then
		return
	end

	local character = LocalPlayer.Character
	if not character then
		return
	end

	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		warn("Humanoid not found for animation:", animationName)
		return
	end

	local animator = humanoid:WaitForChild("Animator", 5)
	if not animator then
		warn("Animator not found for animation:", animationName)
		return
	end

	local animation = Instance.new("Animation")
	animation.Name = animationName
	animation.AnimationId = animationId

	local animationTrack = animator:LoadAnimation(animation)
	self._animationTracks[animationName] = animationTrack
	return animationTrack
end

function AnimationController:_initAnimations()
	local _ = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

	for animationName in Animations do
		self:_loadAnimation(animationName)
	end
end

function AnimationController:OnInit()
	LocalPlayer.CharacterAdded:Connect(function()
		task.spawn(AnimationController._initAnimations, self)
	end)

	task.spawn(AnimationController._initAnimations, self)
end

return AnimationController
