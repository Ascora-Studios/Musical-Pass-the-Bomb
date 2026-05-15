-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterPlayers = game:GetService("StarterPlayer")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)

-- Assets
local Assets = ReplicatedStorage.Assets

-- Constants
local TOOL_NAME = "Punch"
local OWNER_ATTRIBUTE = "OwnerId"
local REQUEST_COOLDOWN = 0.1
local VALID_RANGE = 8
local MIN_FORWARD_DOT = 0.2
local KNOCKBACK_SPEED = 220
local KNOCKBACK_UP_SPEED = 25
local MAX_KNOCKBACK_SPEED = 90
local EQUIPPED_WALKSPEED = 10
local EQUIPPED_JUMPPOWER = 0

--
local RoundManager
local SoundManager

--
local PunchManager = {
	RequestPunchHit = BridgeNet2.ReferenceBridge("RequestPunchHit"),

	_tools = {} :: { [Player]: Tool },
	_lastPunchAt = {} :: { [Player]: number },
	_characterConnections = {} :: { [Player]: RBXScriptConnection },
	_toolConnections = {} :: { [Player]: any },
}

local function getRootPart(player: Player): BasePart?
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	return rootPart :: BasePart?
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid
end

local function getBackpack(player: Player): Backpack?
	local backpack = player:FindFirstChildOfClass("Backpack")
	return backpack
end

local function parseTargetUserId(payload: any): number?
	if typeof(payload) == "number" then
		return payload
	end

	if typeof(payload) == "table" then
		return tonumber(payload.TargetUserId or payload.UserId or payload[1])
	end

	return nil
end

local function setPlayerMovement(player: Player, walkSpeed: number, jumpPower: number)
	local humanoid = getHumanoid(player)
	if not humanoid then
		return
	end

	humanoid.WalkSpeed = walkSpeed
	humanoid.JumpPower = jumpPower
end

local function resetPlayerMovement(player: Player)
	setPlayerMovement(player, StarterPlayers.CharacterWalkSpeed, StarterPlayers.CharacterJumpPower)
end

function PunchManager:_disconnectToolConnections(player: Player)
	local connections = self._toolConnections[player]
	if not connections then
		return
	end

	for _, connection in connections do
		connection:Disconnect()
	end

	self._toolConnections[player] = nil
end

-- Removes any punch tool owned by the player from their backpack and character.
function PunchManager:_removePlayerTool(player: Player)
	self:_disconnectToolConnections(player)
	resetPlayerMovement(player)

	local trackedTool = self._tools[player]
	if trackedTool then
		trackedTool:Destroy()
		self._tools[player] = nil
	end

	for _, container in { getBackpack(player), player.Character } do
		if not container then
			continue
		end

		for _, child in container:GetChildren() do
			if
				child:IsA("Tool")
				and child.Name == TOOL_NAME
				and child:GetAttribute(OWNER_ATTRIBUTE) == player.UserId
			then
				child:Destroy()
			end
		end
	end
end

-- Gives and equips the final-round punch tool.
function PunchManager:_givePlayerTool(player: Player)
	self:_removePlayerTool(player)

	local toolsFolder = Assets:FindFirstChild("Tools")
	local toolTemplate = toolsFolder and toolsFolder:FindFirstChild(TOOL_NAME)
	if not toolTemplate or not toolTemplate:IsA("Tool") then
		warn("[PunchManager] ReplicatedStorage.Assets.Tools.Punch is missing")
		return
	end

	local backpack = getBackpack(player) or player:WaitForChild("Backpack", 5)
	if not backpack then
		return
	end

	local punchTool = toolTemplate:Clone()
	punchTool:SetAttribute(OWNER_ATTRIBUTE, player.UserId)
	punchTool:AddTag(TOOL_NAME)
	punchTool.Parent = backpack
	self._tools[player] = punchTool
	self._toolConnections[player] = {
		punchTool.Equipped:Connect(function()
			setPlayerMovement(player, EQUIPPED_WALKSPEED, EQUIPPED_JUMPPOWER)
		end),
		punchTool.Unequipped:Connect(function()
			resetPlayerMovement(player)
		end),
	}

	local humanoid = getHumanoid(player)
	if humanoid then
		humanoid:EquipTool(punchTool)
	end
end

-- Starts punch tooling for the two active finalists.
function PunchManager:_startFinalRound(players: { Player })
	self:_cleanupFinalRound()

	for _, player in players do
		if player and player:IsDescendantOf(Players) then
			self:_givePlayerTool(player)
		end
	end
end

-- Clears punch tools and request state for the active final round.
function PunchManager:_cleanupFinalRound()
	local playersWithTools = {}
	for player in self._tools do
		table.insert(playersWithTools, player)
	end

	for _, player in playersWithTools do
		self:_removePlayerTool(player)
	end

	table.clear(self._lastPunchAt)
end

-- Checks the attacker still owns an equipped or backpacked punch tool.
function PunchManager:_hasOwnedPunchTool(player: Player): boolean
	local tool = self._tools[player]
	if tool and tool:GetAttribute(OWNER_ATTRIBUTE) == player.UserId and tool:IsDescendantOf(game) then
		return true
	end

	for _, container in { player.Character, getBackpack(player) } do
		if not container then
			continue
		end

		for _, child in container:GetChildren() do
			if
				child:IsA("Tool")
				and child.Name == TOOL_NAME
				and child:GetAttribute(OWNER_ATTRIBUTE) == player.UserId
			then
				self._tools[player] = child
				return true
			end
		end
	end

	return false
end

-- Validates a client hit candidate using server character positions.
function PunchManager:_canPunchHit(attacker: Player, target: Player): boolean
	if attacker == target then
		return false
	end

	if not RoundManager:IsLastRoundActive() then
		return false
	end

	if not RoundManager:IsPlayerAlive(attacker) or not RoundManager:IsPlayerAlive(target) then
		return false
	end

	if not self:_hasOwnedPunchTool(attacker) then
		return false
	end

	local attackerRoot = getRootPart(attacker)
	local targetRoot = getRootPart(target)
	local targetHumanoid = getHumanoid(target)
	if not attackerRoot or not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
		return false
	end

	local offset = targetRoot.Position - attackerRoot.Position
	local flatOffset = Vector3.new(offset.X, 0, offset.Z)
	if flatOffset.Magnitude <= 0 or flatOffset.Magnitude > VALID_RANGE then
		return false
	end

	local look = attackerRoot.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude <= 0 then
		return false
	end

	return flatLook.Unit:Dot(flatOffset.Unit) >= MIN_FORWARD_DOT
end

-- Pushes the target away from the attacker without ragdolling.
function PunchManager:_pushTarget(attackerRoot: BasePart, targetRoot: BasePart)
	local offset = targetRoot.Position - attackerRoot.Position
	local direction = Vector3.new(offset.X, 0, offset.Z)
	if direction.Magnitude <= 0 then
		direction = Vector3.new(attackerRoot.CFrame.LookVector.X, 0, attackerRoot.CFrame.LookVector.Z)
	end
	if direction.Magnitude <= 0 then
		return
	end

	local currentVelocity = targetRoot.AssemblyLinearVelocity
	local horizontalVelocity = direction.Unit * KNOCKBACK_SPEED
	if horizontalVelocity.Magnitude > MAX_KNOCKBACK_SPEED then
		horizontalVelocity = horizontalVelocity.Unit * MAX_KNOCKBACK_SPEED
	end

	targetRoot.AssemblyLinearVelocity =
		Vector3.new(horizontalVelocity.X, math.max(currentVelocity.Y, KNOCKBACK_UP_SPEED), horizontalVelocity.Z)
end

-- Handles client punch hit requests after server-side validation.
function PunchManager:_handlePunchHit(attacker: Player, payload: any)
	local targetUserId = parseTargetUserId(payload)
	local target = targetUserId and Players:GetPlayerByUserId(targetUserId)
	if not target then
		return
	end

	local now = workspace:GetServerTimeNow()
	if now - (self._lastPunchAt[attacker] or 0) < REQUEST_COOLDOWN then
		return
	end
	self._lastPunchAt[attacker] = now

	if not self:_canPunchHit(attacker, target) then
		return
	end

	local attackerRoot = getRootPart(attacker)
	local targetRoot = getRootPart(target)
	if not attackerRoot or not targetRoot then
		return
	end

	self:_pushTarget(attackerRoot, targetRoot)
	SoundManager:PlayToPlayers("PunchHit", attackerRoot, { PlaybackSpeed = Random.new():NextNumber(0.8, 1.2) })
end

function PunchManager:OnInit()
	RoundManager = require(script.Parent.RoundManager)
	SoundManager = require(script.Parent.SoundManager)
end

function PunchManager:OnStart()
	RoundManager.OnLastRoundStarted:Connect(function(players: { Player })
		self:_startFinalRound(players)
	end)

	RoundManager.OnLastRoundEnded:Connect(function()
		self:_cleanupFinalRound()
	end)

	self.RequestPunchHit:Connect(function(player: Player, payload: any)
		self:_handlePunchHit(player, payload)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		self._characterConnections[player] = player.CharacterRemoving:Connect(function()
			self:_removePlayerTool(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:_removePlayerTool(player)
		self._lastPunchAt[player] = nil

		local connection = self._characterConnections[player]
		if connection then
			connection:Disconnect()
			self._characterConnections[player] = nil
		end
	end)

	for _, player in Players:GetPlayers() do
		self._characterConnections[player] = player.CharacterRemoving:Connect(function()
			self:_removePlayerTool(player)
		end)
	end
end

return PunchManager
