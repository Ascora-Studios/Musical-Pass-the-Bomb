-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Packages
local Packages = ReplicatedStorage.Packages
local Component = require(Packages.Component)
local Trove = require(Packages.Trove)

-- Assets
local Assets = ReplicatedStorage.Assets
local Meshes = Assets.Meshes

-- Constants
local CROWN_HEIGHT_OFFSET = 1.4
local CROWN_LERP_SPEED = 0.2

--
local ActiveCrowns = {}
local UpdateConnection: RBXScriptConnection?

--
local CrownsFolder = Instance.new("Folder")
CrownsFolder.Name = "VIPCrowns"
CrownsFolder.Parent = workspace

--
local VIPCrown = Component.new({
	Tag = script.Name,
})

local rot = 0
local function updateCrowns(dt: number)
	local alpha = math.clamp(CROWN_LERP_SPEED * dt * 60, 0.4, 1)
	rot += 20 * dt

	for vipCrown in pairs(ActiveCrowns) do
		vipCrown:_updateCrown(alpha)
	end
end

function VIPCrown:_updateCrown(alpha: number)
	--
	local character: Model = self._character
	local crown: BasePart = self._crown

	if not character or not crown then
		return
	end

	--
	local finalCFrame = character:GetPivot() * self._offset * CFrame.Angles(0, math.rad(rot), 0)

	--
	crown.CFrame = crown.CFrame:Lerp(finalCFrame, alpha)
end

function VIPCrown:_createCrown(character: Model)
	--
	self._crownCleaner:Clean()

	--
	local rootPart: BasePart? = character:FindFirstChild("HumanoidRootPart")
		or character:WaitForChild("HumanoidRootPart", 5)

	if not rootPart then
		return
	end

	--
	local characterSize = character:GetExtentsSize()
	local offset = CFrame.new(0, (characterSize.Y / 2) + CROWN_HEIGHT_OFFSET, 0)

	--
	local crown: BasePart = Meshes.VIPCrown:Clone()
	crown.Anchored = true
	crown.CanCollide = false
	crown.CanQuery = false
	crown.CanTouch = false
	crown.Massless = true
	crown.CFrame = rootPart.CFrame * offset
	crown.Parent = CrownsFolder

	--
	self._character = character
	self._crown = crown
	self._offset = offset

	--
	ActiveCrowns[self] = true

	if not UpdateConnection then
		UpdateConnection = RunService.RenderStepped:Connect(updateCrowns)
	end

	self._crownCleaner:Add(function()
		ActiveCrowns[self] = nil

		if not next(ActiveCrowns) and UpdateConnection then
			UpdateConnection:Disconnect()
			UpdateConnection = nil
		end
	end)

	self._crownCleaner:Add(crown)
end

function VIPCrown:Construct()
	--
	local vipPlayer: Player = self.Instance

	--
	self._cleaner = Trove.new()
	self._crownCleaner = self._cleaner:Extend()

	--
	if vipPlayer.Character then
		self:_createCrown(vipPlayer.Character)
	end

	--
	self._cleaner:Add(vipPlayer.CharacterAdded:Connect(function(character: Model)
		self:_createCrown(character)
	end))
end

function VIPCrown:Stop()
	self._cleaner:Destroy()
end

return VIPCrown
