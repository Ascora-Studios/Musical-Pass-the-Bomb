-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Trove = require(Packages.Trove)

-- Modules
local Modules = script.Parent.Parent.Modules
local BuildRagdoll = require(Modules.BuildRagdoll)

-- Shared
local Shared = ReplicatedStorage.Shared
local RagdollShared = require(Shared.RagdollShared)

-- Values
local DEFAULT_RAGDOLL_LENGTH = 3

--
local RagdollManager = {
	RagdollPlayer = BridgeNet2.ReferenceBridge(RagdollShared.BRIDGE_NAME),
	_cleaners = {} :: { [Model]: any },
}

function RagdollManager:_setupCharacterRagdoll(character: Model)
	local cleaner = Trove.new()
	RagdollManager._cleaners[character] = cleaner

	local humanoid: Humanoid = character:WaitForChild("Humanoid")
	BuildRagdoll(humanoid)

	cleaner:Add(humanoid.StateChanged:Connect(function(_, new)
		if RagdollShared.VALID_HUMANOID_STATES[new] then
			RagdollShared.EnableRagdoll(character)
		else
			RagdollShared.DisableRagdoll(character)
		end
	end))
end

function RagdollManager:_teardownCharacterRagdoll(character: Model)
	local cleaner = RagdollManager._cleaners[character]
	if cleaner then
		cleaner:Destroy()
		RagdollManager._cleaners[character] = nil
	end
end

-- Public API: tell a player's client to ragdoll for `duration` seconds
-- (defaults to DEFAULT_RAGDOLL_LENGTH) with an optional impulse.
function RagdollManager:Ragdoll(player: Player, duration: number?, impulse: Vector3?)
	self.RagdollPlayer:Fire(player, {
		Toggle = true,
		TimeLength = duration or DEFAULT_RAGDOLL_LENGTH,
		PushDirection = impulse,
	})
end

-- Public API: force a player out of ragdoll early.
function RagdollManager:Unragdoll(player: Player)
	local character = player.Character
	if character and character:FindFirstChild("Humanoid") then
		local humanoid: Humanoid = character.Humanoid
		RagdollShared.DisableRagdoll(character)
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	self.RagdollPlayer:Fire(player, { Toggle = false })
end

function RagdollManager:OnInit()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character: Model)
			self:_setupCharacterRagdoll(character)
		end)
		player.CharacterRemoving:Connect(function(character: Model)
			self:_teardownCharacterRagdoll(character)
		end)
	end)
end

return RagdollManager
