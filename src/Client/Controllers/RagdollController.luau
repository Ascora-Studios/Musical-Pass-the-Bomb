-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Trove = require(Packages.Trove)

-- Shared
local Shared = ReplicatedStorage.Shared
local RagdollShared = require(Shared.RagdollShared)

-- Values
local DEFAULT_RAGDOLL_LENGTH = 3

-- Events
local RagdollPlayer = BridgeNet2.ReferenceBridge(RagdollShared.BRIDGE_NAME)

-- Controllers
local CameraController = require(script.Parent.CameraController)

--
local RagdollController = {
	_trove = nil :: any,
}

function RagdollController:_getCharacter(): Model?
	local player = Players.LocalPlayer
	local character = player.Character
	if not character or not character:FindFirstChild("Humanoid") then
		return nil
	end
	return character
end

function RagdollController:_enableRagdoll(timeLength: number?, pushDirection: Vector3?)
	local character = self:_getCharacter()
	if not character then
		return
	end

	-- Re-ragdoll: refresh the timer (and keep the impulse if one was passed)
	if self._trove then
		self._trove:Destroy()
		self._trove = nil
	end

	local humanoid: Humanoid = character.Humanoid
	local rootPart = character.PrimaryPart

	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	RagdollShared.EnableRagdoll(character)
	CameraController:SetSubject(character.Head) -- avoid camera bobble

	if pushDirection and rootPart then
		local worldDirection = character:GetPivot():VectorToWorldSpace(pushDirection)
		rootPart:ApplyImpulse(worldDirection * rootPart.AssemblyMass)
	end

	self._trove = Trove.new()
	self._trove:Add(task.delay(timeLength or DEFAULT_RAGDOLL_LENGTH, function()
		self:_disableRagdoll()
	end))
end

function RagdollController:_disableRagdoll()
	local character = self:_getCharacter()
	if not character then
		return
	end

	if self._trove then
		self._trove:Destroy()
		self._trove = nil
	end

	local humanoid: Humanoid = character.Humanoid
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	CameraController:SetSubject(humanoid)
	RagdollShared.DisableRagdoll(character)
end

function RagdollController:ToggleRagdoll(toggle: boolean, timeLength: number?, pushDirection: Vector3?)
	if toggle then
		self:_enableRagdoll(timeLength, pushDirection)
	else
		self:_disableRagdoll()
	end
end

function RagdollController:OnStart()
	RagdollPlayer:Connect(function(payload: RagdollShared.RagdollPayload)
		self:ToggleRagdoll(payload.Toggle, payload.TimeLength, payload.PushDirection)
	end)
end

return RagdollController
