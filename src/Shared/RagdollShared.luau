-- Services
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

--
local RagdollShared = {}
RagdollShared.BRIDGE_NAME = "RagdollPlayer"
RagdollShared.VALID_HUMANOID_STATES = {
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Dead] = true,
}

export type RagdollPayload = {
	Toggle: boolean,
	TimeLength: number?,
	PushDirection: Vector3?,
}

local function hasRagdollOwnership(humanoid: Humanoid)
	if RunService:IsServer() then
		-- Always set on the server, even if the owning client has already
		-- toggled the ragdoll. We don't want the server to be desynced in
		-- case the character changes ownership
		return true
	end

	local player = Players:GetPlayerFromCharacter(humanoid.Parent)
	return player == Players.LocalPlayer
end

function RagdollShared._toggleRagdoll(character: Model, toggle: boolean)
	--
	local ragdollConstraints = character:FindFirstChild("RagdollConstraints")
	if not ragdollConstraints then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if player then
		if toggle then
			player:AddTag("Ragdoll")
		else
			player:RemoveTag("Ragdoll")
		end
	end

	character.Animate.Enabled = not toggle

	for _, constraint in ragdollConstraints:GetChildren() do
		if not constraint:IsA("Constraint") then
			continue
		end

		local rigidJoint = constraint.RigidJoint.Value
		local expectedValue = (not toggle) and constraint.Attachment1.Parent or nil

		if rigidJoint.Part1 ~= expectedValue then
			rigidJoint.Part1 = expectedValue
		end
	end
end

function RagdollShared.EnableRagdoll(character: Model)
	local humanoid = character.Humanoid

	if not hasRagdollOwnership(humanoid) then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if player and player:HasTag("Ragdoll") then
		return
	end

	RagdollShared._toggleRagdoll(character, true)
end

function RagdollShared.DisableRagdoll(character: Model)
	local humanoid = character.Humanoid

	if not hasRagdollOwnership(humanoid) then
		return
	end

	RagdollShared._toggleRagdoll(character, false)
end

return RagdollShared
