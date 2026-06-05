-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterPlayers = game:GetService("StarterPlayer")
local Debris = game:GetService("Debris")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)

-- Shared
local Shared = ReplicatedStorage.Shared
local BatSkins = require(Shared.Config.BatSkins)

-- Assets
local Assets = ReplicatedStorage.Assets

-- Constants
local TOOL_NAME = "BaseballBat"
local COMPONENT_TAG = "Bat"
local OWNER_ATTRIBUTE = "OwnerId"
local EQUIPPED_SKIN_ATTRIBUTE = "EquippedBatSkin"
local REQUEST_COOLDOWN = 0.1
local VALID_RANGE = 8
local MIN_FORWARD_DOT = 0.2
local KNOCKBACK_SPEED = 40
local KNOCKBACK_UP_SPEED = 10
local KNOCKBACK_DURATION = 0.18
local KNOCKBACK_FORCE = 1e6
local EQUIPPED_WALKSPEED = 10
local EQUIPPED_JUMPPOWER = 0

--
local RoundManager
local SoundManager

--
local BatManager = {
	RequestBatHit = BridgeNet2.ReferenceBridge("RequestBatHit"),

	_tools = {} :: { [Player]: Tool },
	_lastSwingAt = {} :: { [Player]: number },
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

function BatManager:_disconnectToolConnections(player: Player)
	local connections = self._toolConnections[player]
	if not connections then
		return
	end

	for _, connection in connections do
		connection:Disconnect()
	end

	self._toolConnections[player] = nil
end

-- Removes any bat tool owned by the player from their backpack and character.
function BatManager:_removePlayerTool(player: Player)
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

-- Resolves the bat tool template for the player's equipped bat skin. Skin tools
-- are full drop-in bats (same Handle/attachment setup), so we just clone the
-- equipped one; falls back to the default BaseballBat tool.
function BatManager:_resolveToolTemplate(player: Player): Tool?
	local skinId = player:GetAttribute(EQUIPPED_SKIN_ATTRIBUTE)
	if skinId and skinId ~= "Default" then
		local skinData = BatSkins.GetBatFromId(skinId)
		if skinData and skinData.Model and skinData.Model:IsA("Tool") then
			return skinData.Model
		end
	end

	local toolsFolder = Assets:FindFirstChild("Tools")
	return toolsFolder and toolsFolder:FindFirstChild(TOOL_NAME) :: Tool?
end

-- Gives and equips the final-round bat tool.
function BatManager:_givePlayerTool(player: Player)
	self:_removePlayerTool(player)

	local toolTemplate = self:_resolveToolTemplate(player)
	if not toolTemplate or not toolTemplate:IsA("Tool") then
		warn("[BatManager] No bat tool template available (missing BaseballBat / skin)")
		return
	end

	local backpack = getBackpack(player) or player:WaitForChild("Backpack", 5)
	if not backpack then
		return
	end

	local batTool = toolTemplate:Clone()
	batTool.Name = TOOL_NAME
	batTool:SetAttribute(OWNER_ATTRIBUTE, player.UserId)
	batTool:AddTag(COMPONENT_TAG)
	batTool.Parent = backpack
	self._tools[player] = batTool
	self._toolConnections[player] = {
		batTool.Equipped:Connect(function()
			setPlayerMovement(player, EQUIPPED_WALKSPEED, EQUIPPED_JUMPPOWER)
		end),
		batTool.Unequipped:Connect(function()
			resetPlayerMovement(player)
		end),
	}

	local humanoid = getHumanoid(player)
	if humanoid then
		humanoid:EquipTool(batTool)
	end
end

-- Starts bat tooling for the two active finalists.
function BatManager:_startFinalRound(players: { Player })
	self:_cleanupFinalRound()

	for _, player in players do
		if player and player:IsDescendantOf(Players) then
			self:_givePlayerTool(player)
		end
	end
end

-- Clears bat tools and request state for the active final round.
function BatManager:_cleanupFinalRound()
	local playersWithTools = {}
	for player in self._tools do
		table.insert(playersWithTools, player)
	end

	for _, player in playersWithTools do
		self:_removePlayerTool(player)
	end

	table.clear(self._lastSwingAt)
end

-- Checks the attacker still owns an equipped or backpacked bat tool.
function BatManager:_hasOwnedBatTool(player: Player): boolean
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
function BatManager:_canBatHit(attacker: Player, target: Player): boolean
	if attacker == target then
		return false
	end

	if not RoundManager:IsLastRoundActive() then
		return false
	end

	if not RoundManager:IsPlayerAlive(attacker) or not RoundManager:IsPlayerAlive(target) then
		return false
	end

	if not self:_hasOwnedBatTool(attacker) then
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

-- Pushes the target away from the attacker using a temporary LinearVelocity.
function BatManager:_pushTarget(attackerRoot: BasePart, targetRoot: BasePart)
	local offset = targetRoot.Position - attackerRoot.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude <= 0 then
		local look = attackerRoot.CFrame.LookVector
		flat = Vector3.new(look.X, 0, look.Z)
	end
	if flat.Magnitude <= 0 then
		return
	end

	local velocity = flat.Unit * KNOCKBACK_SPEED + Vector3.new(0, KNOCKBACK_UP_SPEED, 0)

	local attachment = Instance.new("Attachment")
	attachment.Parent = targetRoot

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Attachment0 = attachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.MaxForce = KNOCKBACK_FORCE
	linearVelocity.VectorVelocity = velocity
	linearVelocity.Parent = targetRoot

	Debris:AddItem(linearVelocity, KNOCKBACK_DURATION)
	Debris:AddItem(attachment, KNOCKBACK_DURATION)
end

-- Handles client bat hit requests after server-side validation.
function BatManager:_handleBatHit(attacker: Player, payload: any)
	local targetUserId = parseTargetUserId(payload)
	local target = targetUserId and Players:GetPlayerByUserId(targetUserId)
	if not target then
		return
	end

	local now = workspace:GetServerTimeNow()
	if now - (self._lastSwingAt[attacker] or 0) < REQUEST_COOLDOWN then
		return
	end
	self._lastSwingAt[attacker] = now

	if not self:_canBatHit(attacker, target) then
		return
	end

	local attackerRoot = getRootPart(attacker)
	local targetRoot = getRootPart(target)
	if not attackerRoot or not targetRoot then
		return
	end

	self:_pushTarget(attackerRoot, targetRoot)
	SoundManager:PlayToPlayers("SwingHit", attackerRoot, { PlaybackSpeed = Random.new():NextNumber(0.8, 1.2) })
end

function BatManager:OnInit()
	RoundManager = require(script.Parent.RoundManager)
	SoundManager = require(script.Parent.SoundManager)
end

function BatManager:OnStart()
	RoundManager.OnLastRoundStarted:Connect(function(players: { Player })
		self:_startFinalRound(players)
	end)

	RoundManager.OnLastRoundEnded:Connect(function()
		self:_cleanupFinalRound()
	end)

	self.RequestBatHit:Connect(function(player: Player, payload: any)
		self:_handleBatHit(player, payload)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		self._characterConnections[player] = player.CharacterRemoving:Connect(function()
			self:_removePlayerTool(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:_removePlayerTool(player)
		self._lastSwingAt[player] = nil

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

return BatManager
