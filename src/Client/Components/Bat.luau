-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Component = require(Packages.Component)
local RaycastHitbox = require(Packages.RaycastHitbox)
local Trove = require(Packages.Trove)

-- Local Player
local LocalPlayer = Players.LocalPlayer

local PER_SWING_CD = 0.25
local MAX_SWING_SET = 2
local PER_SET_CD = 1
local SET_ALLOWANCE = 1.5
local SWING_DURATION = 0.35

-- Controllers
local AnimationController = require(script.Parent.Parent.Controllers.AnimationController)
local SoundController = require(script.Parent.Parent.Controllers.SoundController)

--
local Bat = Component.new({
	Tag = script.Name,
})

local RequestBatHit = BridgeNet2.ReferenceBridge("RequestBatHit")

function Bat:Construct()
	self._cleaner = Trove.new()
	self._lastSwing = nil
	self._setCooldownEndsAt = 0
	self._swingCount = 0

	local isEquipped = false

	local ownerId = self.Instance:GetAttribute("OwnerId")

	if ownerId and ownerId ~= LocalPlayer.UserId then
		return
	end

	local hitbox = RaycastHitbox.new(self.Instance)
	hitbox.Visualizer = false
	hitbox.DetectionMode = RaycastHitbox.DetectionMode.Default

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LocalPlayer.Character }
	hitbox.RaycastParams = params

	self._hitbox = hitbox
	self._cleaner:Add(function()
		hitbox:Destroy()
	end)

	self._cleaner:Add(LocalPlayer.CharacterAdded:Connect(function(character)
		params.FilterDescendantsInstances = { character }
	end))

	hitbox.OnHit:Connect(function(_hit, humanoid)
		local targetCharacter = humanoid and humanoid.Parent
		local targetPlayer = targetCharacter and Players:GetPlayerFromCharacter(targetCharacter)
		if targetPlayer and targetPlayer ~= LocalPlayer then
			RequestBatHit:Fire({ TargetUserId = targetPlayer.UserId })
		end
	end)

	local function lockCamera()
		isEquipped = true
		UserInputService.MouseIconEnabled = false
		UserInputService.MouseBehavior = UserInputService.TouchEnabled and Enum.MouseBehavior.Default
			or Enum.MouseBehavior.LockCenter

		local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.AutoRotate = false
		end
	end

	local function unlockCamera()
		isEquipped = false
		UserInputService.MouseIconEnabled = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default

		local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.AutoRotate = true
		end
	end

	AnimationController:PlayAnimation("BatIdle")
	self._cleaner:Add(self.Instance.Equipped:Connect(function()
		AnimationController:PlayAnimation("BatIdle")
		lockCamera()
	end))

	self._cleaner:Add(self.Instance.Unequipped:Connect(function()
		AnimationController:StopAnimation("BatIdle")
		hitbox:HitStop()
		unlockCamera()
	end))

	self._cleaner:Add(function()
		AnimationController:StopAnimation("BatIdle")
		unlockCamera()
	end)

	self._cleaner:Add(RunService.RenderStepped:Connect(function(dt)
		if not isEquipped then
			return
		end

		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end

		local look = workspace.CurrentCamera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			local desired = CFrame.lookAt(root.Position, root.Position + flat)
			root.CFrame = root.CFrame:Lerp(desired, 0.25 * dt * 60)
		end
	end))

	self._cleaner:Add(self.Instance.Activated:Connect(function()
		local now = os.clock()

		if now < self._setCooldownEndsAt then
			return
		end

		if self._lastSwing and now - self._lastSwing < PER_SWING_CD then
			return
		end

		if self._lastSwing and now - self._lastSwing > SET_ALLOWANCE then
			self._swingCount = 0
		end

		local character = LocalPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not rootPart then
			return
		end

		self._lastSwing = now
		self._swingCount += 1

		local swingAnim = self._swingCount % 2 == 1 and "BatRightSwing" or "BatLeftSwing"
		AnimationController:PlayAnimation(swingAnim)
		SoundController:PlaySound("Swing", rootPart, { PlaybackSpeed = Random.new():NextNumber(1, 1.2) }, nil, true)
		hitbox:HitStart(SWING_DURATION)

		if self._swingCount < MAX_SWING_SET then
			return
		end

		self._setCooldownEndsAt = now + PER_SET_CD
		self._swingCount = 0
		self:OnSetCompleted()
	end))
end

-- Hook for future server bat behavior.
function Bat:OnSetCompleted() end

function Bat:Stop()
	self._cleaner:Destroy()
end

return Bat
