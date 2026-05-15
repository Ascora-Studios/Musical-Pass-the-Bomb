-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Component = require(Packages.Component)
local Trove = require(Packages.Trove)

-- Shared
local Shared = ReplicatedStorage.Shared
local Hitbox = require(Shared.Hitbox)

-- Local Player
local LocalPlayer = Players.LocalPlayer

local PER_PUNCH_CD = 0.25
local MAX_PUNCH_SET = 2
local PER_SET_CD = 1
local SET_ALLOWANCE = 1.5

local HITBOX_OFFSET = CFrame.new(0, 0, -3)
local HITBOX_SIZE = Vector3.new(5, 5, 5)

-- Controllers
local AnimationController = require(script.Parent.Parent.Controllers.AnimationController)
local SoundController = require(script.Parent.Parent.Controllers.SoundController)

--
local Punch = Component.new({
	Tag = script.Name,
})

local RequestPunchHit = BridgeNet2.ReferenceBridge("RequestPunchHit")

function Punch:Construct()
	self._cleaner = Trove.new()
	self._lastPunch = nil
	self._setCooldownEndsAt = 0
	self._punchCount = 0

	local ownerId = self.Instance:GetAttribute("OwnerId")

	if ownerId and ownerId ~= LocalPlayer.UserId then
		return
	end

	self._cleaner:Add(self.Instance.Equipped:Connect(function()
		AnimationController:PlayAnimation("PunchIdle")
	end))

	self._cleaner:Add(self.Instance.Unequipped:Connect(function()
		AnimationController:StopAnimation("PunchIdle")
	end))

	self._cleaner:Add(function()
		AnimationController:StopAnimation("PunchIdle")
	end)

	self._cleaner:Add(self.Instance.Activated:Connect(function()
		local now = os.clock()

		if now < self._setCooldownEndsAt then
			return
		end

		if self._lastPunch and now - self._lastPunch < PER_PUNCH_CD then
			return
		end

		if self._lastPunch and now - self._lastPunch > SET_ALLOWANCE then
			self._punchCount = 0
		end

		local character = LocalPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not rootPart then
			return
		end

		self._lastPunch = now
		self._punchCount += 1
		AnimationController:PlayAnimation(`Punch{self._punchCount}`)
		SoundController:PlaySound("Punch", rootPart, { PlaybackSpeed = Random.new():NextNumber(1, 1.2) }, nil, true)
		self:_checkHit(character, rootPart)

		if self._punchCount < MAX_PUNCH_SET then
			return
		end

		self._setCooldownEndsAt = now + PER_SET_CD
		self._punchCount = 0
		self:OnSetCompleted()
	end))
end

-- Checks a local forward hitbox and sends the first target candidate.
function Punch:_checkHit(character: Model, rootPart: BasePart)
	local hits = Hitbox.Hit(rootPart.CFrame * HITBOX_OFFSET, HITBOX_SIZE, { character })
	for _, hitCharacter in hits do
		local targetPlayer = Players:GetPlayerFromCharacter(hitCharacter)
		if targetPlayer and targetPlayer ~= LocalPlayer then
			RequestPunchHit:Fire({
				TargetUserId = targetPlayer.UserId,
			})
			return
		end
	end
end

-- Hook for future server punch behavior.
function Punch:OnSetCompleted() end

function Punch:Stop()
	self._cleaner:Destroy()
end

return Punch
