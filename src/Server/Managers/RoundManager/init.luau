--[[
	RoundManager

	Purpose:
		Owns the full round-based game flow for Musical Pass the Bomb. This is
		the "rules" manager: it decides who is in the match, where players
		spawn, whether a bomb pass is legal, who gets eliminated, who gets
		rewarded, and when the next stage begins.

	Stage flow:
		Intermission
			Waits for enough players and a short delay.

		InitMatch
			Builds the alive list from current players, clears old placements,
			spawns everyone evenly around workspace.Main.Arena.Main, and gives
			the bomb to a random player.

		Match
			Starts the music/explosion timestamp and loops until one player is
			left:
				1. Wait until `workspace:GetServerTimeNow()` reaches the
				   replicated explosion timestamp.
				2. Eliminate the current bomb holder.
				3. Reward all remaining survivors.
				4. If more than one player remains, pick a random new holder and
				   start the next music cycle immediately.

		MatchEnd
			Adds the winner to placements, gives the winner reward, fires the
			match-end bridge, leaves room for celebration hooks, then returns to
			Intermission.

	What this owns:
		- Stage progression and the `RoundData` replica
		- Alive players and final placements
		- Spawn circle calculation and teleporting players
		- Pass validation for `Left`, `Right`, and `Front`
		- Music/explosion timestamps (`SyncExplosionTime`)
		- Eliminations, participation rewards, winner rewards
		- Disconnect handling while a match is active
		- Match-end celebration timing

	What BombManager owns:
		Only the current bomb holder and holder sync. RoundManager calls
		`BombManager:SetHolder(player)` after it has validated the game rules.

	Client-facing sync:
		- Replica `RoundData` includes stage text, alive players, placements,
		  bomb holder user id, and explosion timestamp.
		- BridgeNet2 events used here:
			`RequestBombPass` (client -> server)
			`SyncExplosionTime` (server -> clients)
			`PreElimination` (server -> clients)  -- fired before eliminating; grace window for client effects
			`PlayerEliminated` (server -> clients)
			`PostElimination` (server -> clients) -- fired after eliminating, before re-circling; grace window for client effects
			`MatchEnd` (server -> clients)
			`EliminationChoicePrompt` (server -> single player) -- shown post-elim when the match had > 2 players before elimination
			`EliminationChoiceResolved` (server -> single player) -- fired when the prompt has been answered, timed out, or cancelled
			`EliminationChoiceRequest` (client -> server) -- the player's "Respawn" / "Leave" answer

	Customization hooks:
		- `_onPlayerEliminated(player)` for explosion/death effects
		- `_onMatchEnded(winner, placements)` for confetti, camera focus,
		  winner UI, fanfare, etc.
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterPlayers = game:GetService("StarterPlayer")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Replica = require(Packages.Replica)
local Signal = require(Packages.Signal)

-- Shared
local Shared = ReplicatedStorage.Shared
local GameConfigs = require(script.GameConfigs)
local Products = require(ReplicatedStorage.Shared.Config.Products)
local RandomUtil = require(Shared.RandomUtil)

-- Assets
local Assets = ReplicatedStorage.Assets
local Meshes = Assets.Meshes

--
local BombManager
local CurrencyManager
local RagdollManager
local EffectManager
local ShopManager
local PlayerDataManager
local NotificationManager
local SoundManager
local AFKManager

--
local FIRST_STAGE = "Intermission"
local ROUND_DATA_TOKEN = Replica.Token("RoundData")
local PLAYER_IN_GAME_ATTRIBUTE = "InGame"

--
local RoundManager = {
	-- Server-side signals
	OnMatchStarted = Signal.new(),
	OnMatchEnded = Signal.new(),
	OnPlayerEliminated = Signal.new(),
	OnEliminationChoiceResolved = Signal.new(), -- (player, choice: "Respawn" | "Leave")
	OnBombPassed = Signal.new(), -- (fromPlayer, toPlayer, direction)
	OnMusicCycleStarted = Signal.new(), -- (timestamp, duration)
	OnMusicCycleStopped = Signal.new(),
	OnLastRoundStarted = Signal.new(), -- (players: { Player })
	OnLastRoundEnded = Signal.new(),

	-- BridgeNet2 events
	SyncExplosionTimeEvent = BridgeNet2.ReferenceBridge("SyncExplosionTime"),
	PreEliminationEvent = BridgeNet2.ReferenceBridge("PreElimination"),
	PlayerEliminatedEvent = BridgeNet2.ReferenceBridge("PlayerEliminated"),
	PostEliminationEvent = BridgeNet2.ReferenceBridge("PostElimination"),
	MatchEndEvent = BridgeNet2.ReferenceBridge("MatchEnd"),
	LastRoundCountdownEvent = BridgeNet2.ReferenceBridge("LastRoundCountdown"),
	LastRoundStartedEvent = BridgeNet2.ReferenceBridge("LastRoundStarted"),
	EliminationChoicePromptEvent = BridgeNet2.ReferenceBridge("EliminationChoicePrompt"),
	EliminationChoiceResolvedEvent = BridgeNet2.ReferenceBridge("EliminationChoiceResolved"),
	EliminationChoiceRequestEvent = BridgeNet2.ReferenceBridge("EliminationChoiceRequest"),

	-- Stage state
	_currentStageName = FIRST_STAGE,
	_currentStage = nil,
	_roundReplica = nil,
	_stageCache = {},
	_roundNumber = 0,
	_requestedNextStage = nil,
}

-- Match state
RoundManager._alive = {}
RoundManager._placements = {}
RoundManager._matchActive = false
RoundManager._explosionTimestamp = 0
RoundManager._musicDuration = 0
RoundManager._passesLocked = false
RoundManager._lastPassAt = 0
RoundManager._activeShields = {} :: { [Player]: boolean }
RoundManager._activeReflects = {} :: { [Player]: boolean }
RoundManager._lockTarget = nil :: Player?
RoundManager._lockTargetExpiresAt = 0
RoundManager._nukeActive = false
RoundManager._suppressNextMusicStop = false
RoundManager._bombHoldRewardThread = nil :: thread?
RoundManager._pendingChoices =
	{} :: { [Player]: { Resolved: boolean, Thread: thread?, PurchasePending: boolean?, ProductId: string? } }
RoundManager._eliminationBoardTitle = nil :: TextLabel?
RoundManager._lastRoundActive = false
RoundManager._lastRoundResolved = false
RoundManager._lastRoundScaleThread = nil :: thread?
RoundManager._lastRoundHitPart = nil :: BasePart?
RoundManager._lastRoundTouchConnection = nil :: RBXScriptConnection?
RoundManager._lastRoundPlayers = nil :: { Player }?
RoundManager._lastRoundStartedPayload = nil :: { [string]: any }?
RoundManager._arenaOriginalScale = 1

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

local function setPlayerMovement(player: Player, walkSpeed: number, jumpPower: number)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	humanoid.AutoRotate = walkSpeed > 0
	humanoid.WalkSpeed = walkSpeed
	humanoid.JumpPower = jumpPower
end

local function resetPlayerMovement(player: Player)
	setPlayerMovement(player, StarterPlayers.CharacterWalkSpeed, StarterPlayers.CharacterJumpPower)
end

local function isRespawnProductId(productId: string): boolean
	return productId == GameConfigs.RESPAWN_PRODUCT_ID or productId == GameConfigs.FIRST_RESPAWN_PRODUCT_ID
end

local function isPlayerSpawnable(player: Player): boolean
	if not player or not player:IsDescendantOf(Players) then
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	return hrp ~= nil and humanoid ~= nil and humanoid.Health > 0
end

local function indexOf(list: { Player }, player: Player): number?
	for i, p in list do
		if p == player then
			return i
		end
	end
	return nil
end

local function serializePlayer(player: Player?)
	if not player then
		return nil
	end

	if typeof(player) == "Instance" and player:IsA("Player") then
		return {
			UserId = player.UserId,
			Name = player.Name,
			DisplayName = player.DisplayName,
		}
	end

	return player
end

----------------------------------------------------------------
-- Replicated state writers
----------------------------------------------------------------

function RoundManager:_setReplicaValue(key: string, value: any)
	if not self._roundReplica then
		return
	end

	self._roundReplica:Set({ key }, value)
end

function RoundManager:_syncInGameAttributes()
	local aliveSet: { [Player]: boolean } = {}
	for _, player in self._alive do
		aliveSet[player] = true
	end

	for _, player in Players:GetPlayers() do
		player:SetAttribute(PLAYER_IN_GAME_ATTRIBUTE, aliveSet[player] == true)
	end
end

function RoundManager:_publishAliveList()
	local serialized = {}
	for _, player in self._alive do
		table.insert(serialized, serializePlayer(player))
	end
	self:_setReplicaValue("AlivePlayers", serialized)
	self:_syncInGameAttributes()
end

function RoundManager:_publishPlacements()
	local payload = {}
	for placement, userId in self._placements do
		payload[placement] = { Placement = placement, UserId = userId }
	end
	self:_setReplicaValue("Placements", payload)
	return payload
end

function RoundManager:_publishBombHolder(player: Player?)
	self:_setReplicaValue("BombHolderUserId", player and player.UserId or nil)
end

function RoundManager:_runBombHoldReward(player: Player?)
	if self._bombHoldRewardThread then
		task.cancel(self._bombHoldRewardThread)
		self._bombHoldRewardThread = nil
	end

	if not player or not CurrencyManager then
		return
	end

	self._bombHoldRewardThread = task.spawn(function()
		while BombManager:GetHolder() == player do
			task.wait(
				RandomUtil.GetRandomFromMinMax(
					GameConfigs.BOMB_HOLD_REWARD_INTERVAL.Min,
					GameConfigs.BOMB_HOLD_REWARD_INTERVAL.Max
				)
			)
			if BombManager:GetHolder() ~= player then
				break
			end
			CurrencyManager:IncrementCurrency(
				player,
				RandomUtil.GetRandomIntFromMinMax(
					GameConfigs.BOMB_HOLD_REWARD_RANGE.Min,
					GameConfigs.BOMB_HOLD_REWARD_RANGE.Max
				)
			)
		end
	end)
end

function RoundManager:_publishExplosionTimestamp()
	self:_setReplicaValue("ExplosionTimestamp", self._explosionTimestamp)
end

----------------------------------------------------------------
-- Stage management (existing API preserved)
----------------------------------------------------------------

function RoundManager:_loadStage(stageName: string)
	if self._stageCache[stageName] then
		return self._stageCache[stageName]
	end

	local stagesFolder = script:WaitForChild("Stages")
	local stageModule = stagesFolder:FindFirstChild(stageName)

	if not stageModule then
		error(`Round stage '{stageName}' could not be found`)
	end

	local stage = require(stageModule)
	self._stageCache[stageName] = stage

	return stage
end

function RoundManager:_runStage(stageName: string): string
	local stage = self:_loadStage(stageName)
	local stageStartedAt = os.clock()

	self._currentStageName = stageName
	self._currentStage = stage
	self._requestedNextStage = nil

	self:_setReplicaValue("CurrentStage", stageName)
	self:_setReplicaValue("StageDisplayName", stageName)
	self:_setReplicaValue("StageStartedAt", stageStartedAt)

	stage:OnStart(self)

	repeat
		task.wait()
	until self._requestedNextStage ~= nil or stage:GetCanEnd(os.clock() - stageStartedAt, self)

	stage:OnEnd(self)

	local nextStage = self._requestedNextStage or stage:GetNextStageName(self)
	self._requestedNextStage = nil

	return nextStage
end

function RoundManager:GetRoundData(): { [string]: any }
	if not self._roundReplica then
		return {}
	end

	return self._roundReplica.Data
end

function RoundManager:GetCurrentStageName(): string
	return self._currentStageName
end

function RoundManager:SetStageDisplayName(stageDisplayName: string)
	self:_setReplicaValue("StageDisplayName", stageDisplayName)
end

function RoundManager:SetStatus(statusText: string, subStatusText: string?)
	self:_setReplicaValue("StatusText", statusText)
	self:_setReplicaValue("SubStatusText", subStatusText or "")
end

function RoundManager:SetRoundActive(isRoundActive: boolean)
	self:_setReplicaValue("IsRoundActive", isRoundActive)
end

function RoundManager:SetWinner(winner: Player | { [string]: any }?)
	self:_setReplicaValue("Winner", serializePlayer(winner))
end

function RoundManager:ClearWinner()
	self:SetWinner(nil)
end

function RoundManager:SetIntermissionEndsAt(timestamp: number)
	self:_setReplicaValue("IntermissionEndsAt", timestamp)
end

function RoundManager:PickRandomGameMusic()
	local totalGameMusics = SoundService.CoreBGM.GameMusic:GetChildren()
	local randomGameMusic = totalGameMusics[math.random(1, #totalGameMusics)]
	self:_setReplicaValue("MusicToPlay", randomGameMusic.Name)
end

function RoundManager:IncrementRoundNumber(): number
	self._roundNumber += 1
	self:_setReplicaValue("RoundNumber", self._roundNumber)

	return self._roundNumber
end

function RoundManager:AdvanceStage(nextStageName: string?)
	self._requestedNextStage = nextStageName or true
end

----------------------------------------------------------------
-- Spawning (in a circle on top of workspace.Main.Arena.Main)
----------------------------------------------------------------

function RoundManager:_calculateSpawnCFrames(playerCount: number): { CFrame }
	local arenaPart = workspace.Main.Arena.Main
	if not arenaPart then
		warn("[RoundManager] Arena part workspace.Main.Arena.Main not found; cannot calculate spawns")
		return {}
	end

	local size = arenaPart.Size
	local radius = math.max(1, math.min(size.X, size.Z) / 2 + GameConfigs.SPAWN_RADIUS_PADDING)

	local topY = arenaPart.Position.Y + (size.Y / 2) + GameConfigs.SPAWN_HEIGHT_OFFSET
	local centerXZ = Vector3.new(arenaPart.Position.X, topY, arenaPart.Position.Z)

	local cframes = {}
	for i = 1, playerCount do
		local angle = (i - 1) * (2 * math.pi / playerCount)
		local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local position = centerXZ + offset

		local lookAt = Vector3.new(centerXZ.X, position.Y, centerXZ.Z)
		cframes[i] = CFrame.lookAt(position, lookAt)
	end

	return cframes
end

-- Loads characters in parallel for any player in self._alive who isn't
-- spawnable, then prunes anyone who still isn't ready after the timeout.
-- Dropped players are notified and dropped from self._alive so they don't
-- leave a dead slot in the bomb circle. Does NOT publish the alive list —
-- callers decide when to publish so the replica update can be batched with
-- the CurrentStage change that triggers client-side InitMatch hooks.
function RoundManager:_waitForAliveCharactersAndPrune(): boolean
	local snapshot = {}
	for _, player in self._alive do
		table.insert(snapshot, player)
	end

	local pending = 0
	for _, player in snapshot do
		if not isPlayerSpawnable(player) then
			pending += 1
			task.spawn(function()
				local timeout = os.clock() + 5
				if player:IsDescendantOf(Players) then
					task.spawn(function()
						local success, err = pcall(function()
							player:LoadCharacterAsync()
						end)
						if not success and player:IsDescendantOf(Players) then
							warn(`[RoundManager] Failed to load character for {player.Name}: {err}`)
						end
					end)
				end

				repeat
					task.wait()
				until isPlayerSpawnable(player) or not player:IsDescendantOf(Players) or os.clock() >= timeout

				pending -= 1
			end)
		end
	end
	while pending > 0 do
		task.wait()
	end

	local prunedAny = false
	for i = #self._alive, 1, -1 do
		local player = self._alive[i]
		if not isPlayerSpawnable(player) then
			warn(`[RoundManager] Dropping {player.Name} from match: character not spawnable in time`)
			table.remove(self._alive, i)
			prunedAny = true
			if NotificationManager and player:IsDescendantOf(Players) then
				NotificationManager.NotifyNormalEvent:Fire(player, {
					"You loaded in too late, sitting out this match.",
					4,
					"Reject",
				})
			end
		end
	end

	return prunedAny
end

function RoundManager:_teleportPlayersToCircle()
	if self:_waitForAliveCharactersAndPrune() then
		self:_publishAliveList()
	end

	local cframes = self:_calculateSpawnCFrames(#self._alive)
	for i, player in self._alive do
		local cframe = cframes[i]
		if not cframe then
			continue
		end

		local character = player.Character
		if character then
			character:PivotTo(cframe + Vector3.new(0, 3, 0))
		end
	end
end

----------------------------------------------------------------
-- Music / explosion timer
----------------------------------------------------------------

function RoundManager:_startMusicCycle(duration: number?)
	self._musicDuration = duration
		or self._musicDuration
		or RandomUtil.GetRandomFromMinMax(GameConfigs.MUSIC_DURATION_RANGE.Min, GameConfigs.MUSIC_DURATION_RANGE.Max)
	self._explosionTimestamp = workspace:GetServerTimeNow() + self._musicDuration
	self:_publishExplosionTimestamp()

	self.SyncExplosionTimeEvent:Fire(BridgeNet2.AllPlayers(), {
		Timestamp = self._explosionTimestamp,
		Duration = self._musicDuration,
	})

	self.OnMusicCycleStarted:Fire(self._explosionTimestamp, self._musicDuration)
end

function RoundManager:_stopMusicCycle(suppressClientMusicStop: boolean?)
	self._explosionTimestamp = 0
	self:_publishExplosionTimestamp()

	self.SyncExplosionTimeEvent:Fire(BridgeNet2.AllPlayers(), {
		Timestamp = 0,
		Duration = 0,
		SuppressMusicStop = suppressClientMusicStop == true,
	})

	self.OnMusicCycleStopped:Fire()
end

function RoundManager:_isMusicTimerExpired(): boolean
	return self._explosionTimestamp > 0 and workspace:GetServerTimeNow() >= self._explosionTimestamp
end

----------------------------------------------------------------
-- Elimination + rewards
----------------------------------------------------------------

function RoundManager:_eliminate(player: Player, suppressChoicePrompt: boolean?)
	local idx = indexOf(self._alive, player)
	if not idx then
		return
	end

	self._eliminationBoardTitle.Text = `{player.Name:upper()} HAS BEEN <font color="#ff0000">ELIMINATED</font>`

	self._activeShields[player] = nil
	self._activeReflects[player] = nil
	if self._lockTarget == player then
		self:_clearLockTarget(false)
	end

	table.remove(self._alive, idx)
	-- earliest eliminated -> last in placements (we insert at the front each time)
	table.insert(self._placements, 1, player.UserId)
	self:_publishAliveList()

	-- If the eliminated player was holding the bomb, clear the holder.
	-- (RunMatchLoop will reassign + restart the music cycle on its next tick.)
	if BombManager and BombManager:GetHolder() == player then
		BombManager:SetHolder(nil)
	end

	-- Restore movement for the eliminated player
	resetPlayerMovement(player)

	-- HOOK: death/explosion VFX & SFX
	self:_onPlayerEliminated(player)

	-- Award participation reward to all survivors instantly
	if CurrencyManager then
		for _, survivor in self._alive do
			CurrencyManager:IncrementCurrency(survivor, GameConfigs.PARTICIPATION_REWARD, true)
		end
	end

	self.PlayerEliminatedEvent:Fire(BridgeNet2.AllPlayers(), {
		Eliminated = serializePlayer(player),
		RemainingCount = #self._alive,
	})

	self.OnPlayerEliminated:Fire(player, #self._alive)

	if suppressChoicePrompt then
		task.spawn(function()
			task.wait(GameConfigs.ELIMINATION_AUTO_LOBBY_DELAY)
			self:_returnToLobby(player)
		end)
		return
	end

	-- Decide what happens to the eliminated player after the explosion / ragdoll.
	if #self._alive > GameConfigs.ELIMINATION_CHOICE_MIN_REMAINING then
		-- The match had more than 2 players before this elimination, so let the
		-- eliminated player pick LEAVE / RESPAWN.
		self:_promptEliminationChoice(player)
	else
		-- The match had 2 or fewer players before this elimination, so skip the
		-- prompt and auto-return to lobby after a short ragdoll moment.
		task.spawn(function()
			task.wait(GameConfigs.ELIMINATION_AUTO_LOBBY_DELAY)
			self:_returnToLobby(player)
		end)
	end
end

----------------------------------------------------------------
-- Post-elimination choice (LEAVE / RESPAWN) + lobby return
----------------------------------------------------------------

function RoundManager:_returnToLobby(player: Player)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	RagdollManager:Unragdoll(player)
	resetPlayerMovement(player)

	local character = player.Character
	local lobbySpawn = workspace:FindFirstChild("Spawn")
	if character and lobbySpawn then
		character:PivotTo(lobbySpawn:GetPivot() * CFrame.new(0, 3, 0))
	end
end

function RoundManager:_canRespawnFromEliminationChoice(player: Player): boolean
	if not player or not player:IsDescendantOf(Players) then
		return false
	end

	if not self:IsMatchActive() then
		return false
	end

	if indexOf(self._alive, player) then
		return false
	end

	if self._lastRoundActive or self._lastRoundResolved then
		return false
	end

	if #self._alive <= GameConfigs.ELIMINATION_CHOICE_MIN_REMAINING then
		return false
	end

	return true
end

function RoundManager:_respawnIntoMatch(player: Player): boolean
	if not player or not player:IsDescendantOf(Players) then
		return false
	end

	-- If the match is no longer running, fall back to the lobby so the player
	-- isn't stranded in the arena waiting for nothing.
	if not self._matchActive then
		self:_returnToLobby(player)
		return false
	end

	if indexOf(self._alive, player) then
		warn(`[RoundManager] Respawn blocked for {player.Name}: player is already alive`)
		return false
	end

	if self._lastRoundActive or self._lastRoundResolved then
		warn(`[RoundManager] Respawn blocked for {player.Name}: last round is active or resolved`)
		self:_returnToLobby(player)
		return false
	end

	if #self._alive <= GameConfigs.ELIMINATION_CHOICE_MIN_REMAINING then
		warn(`[RoundManager] Respawn blocked for {player.Name}: match is ending or has too few alive players`)
		self:_returnToLobby(player)
		return false
	end

	-- Drop the placement we recorded when they were eliminated.
	for i, userId in self._placements do
		if userId == player.UserId then
			table.remove(self._placements, i)
			break
		end
	end
	self:_publishPlacements()

	-- Re-add to the alive list (the bomb passing logic uses this as the circle order).
	if not indexOf(self._alive, player) then
		table.insert(self._alive, player)
	end
	self:_publishAliveList()

	if RagdollManager then
		RagdollManager:Unragdoll(player)
	end
	setPlayerMovement(player, GameConfigs.MATCH_WALKSPEED, GameConfigs.MATCH_JUMPPOWER)

	-- Re-circle everyone so physical positions match the new alive order.
	self:_teleportPlayersToCircle()
	return true
end

function RoundManager:_promptEliminationChoice(player: Player)
	-- Cancel any prior pending entry (shouldn't happen, but be defensive).
	local existing = self._pendingChoices[player]
	if existing then
		existing.Resolved = true
	end

	local entry = { Resolved = false, PurchasePending = false } :: {
		Resolved: boolean,
		Thread: thread?,
		PurchasePending: boolean?,
		ProductId: string?,
	}
	self._pendingChoices[player] = entry

	local expirationTime = workspace:GetServerTimeNow() + GameConfigs.ELIMINATION_CHOICE_DURATION

	self.EliminationChoicePromptEvent:Fire(player, {
		ExpirationTime = expirationTime,
	})

	entry.Thread = task.spawn(function()
		task.wait(GameConfigs.ELIMINATION_CHOICE_DURATION)
		if not entry.Resolved and self._pendingChoices[player] == entry then
			if entry.PurchasePending then
				return
			end
			self:_resolveEliminationChoice(player, "Leave")
		end
	end)
end

function RoundManager:_requestPaidRespawn(player: Player)
	local entry = self._pendingChoices[player]
	if not entry or entry.Resolved then
		return
	end

	if entry.PurchasePending then
		return
	end

	if not self:_canRespawnFromEliminationChoice(player) then
		self:_resolveEliminationChoice(player, "Leave")
		return
	end

	entry.PurchasePending = true

	local hasData, playerData = PlayerDataManager:GetPlayerData(player):await()
	if not hasData then
		warn(`[RoundManager] Respawn blocked for {player.Name}: player data was not available`)
		self:_resolveEliminationChoice(player, "Leave")
		return
	end

	entry = self._pendingChoices[player]
	if not entry or entry.Resolved then
		return
	end

	if not self:_canRespawnFromEliminationChoice(player) then
		entry.PurchasePending = false
		self:_resolveEliminationChoice(player, "Leave")
		return
	end

	local firstRespawnExpiresAt = 0
	if
		typeof(playerData.FirstPurchaseOfTheDay) == "table"
		and typeof(playerData.FirstPurchaseOfTheDay.Respawn) == "number"
	then
		firstRespawnExpiresAt = playerData.FirstPurchaseOfTheDay.Respawn
	end

	local productId = GameConfigs.RESPAWN_PRODUCT_ID
	if firstRespawnExpiresAt <= os.time() then
		productId = GameConfigs.FIRST_RESPAWN_PRODUCT_ID
	end

	local productData = Products.GetProductFromId(productId)
	if not productData or not productData.ProductId or productData.ProductId <= 0 then
		warn(`[RoundManager] Respawn product '{productId}' is not configured`)
		entry.PurchasePending = false
		if ShopManager then
			ShopManager:AttemptProductPurchase(player, productId)
		end
		self:_resolveEliminationChoice(player, "Leave")
		return
	end

	entry.ProductId = productId
	ShopManager:AttemptProductPurchase(player, productId)
end

function RoundManager:_handleRespawnProductPurchased(player: Player)
	local entry = self._pendingChoices[player]

	if not entry or entry.Resolved or not self:_canRespawnFromEliminationChoice(player) then
		if entry and not entry.Resolved then
			self:_resolveEliminationChoice(player, "Leave")
		else
			self:_returnToLobby(player)
		end

		CurrencyManager:IncrementCurrency(player, GameConfigs.RESPAWN_COMPENSATION_REWARD, true)
		NotificationManager.NotifyNormalEvent:Fire(player, {
			`The match was too far along to revive you, so you received <font color="#ffd400">{GameConfigs.RESPAWN_COMPENSATION_REWARD} Coins</font> instead.`,
			4,
			"RobuxPurchase",
		})
		return
	end

	self:_resolveEliminationChoice(player, "Respawn")
end

function RoundManager:_handleRespawnProductPromptFinished(player: Player, productId: string, wasPurchased: boolean)
	local entry = self._pendingChoices[player]
	if not entry or entry.Resolved then
		return
	end

	if entry.ProductId and entry.ProductId ~= productId then
		return
	end

	if wasPurchased then
		return
	end

	entry.PurchasePending = false
	entry.ProductId = nil
	self:_resolveEliminationChoice(player, "Leave")
end

function RoundManager:_resolveEliminationChoice(player: Player, choice: string)
	local entry = self._pendingChoices[player]
	if not entry or entry.Resolved then
		return
	end

	entry.Resolved = true
	self._pendingChoices[player] = nil

	if player:IsDescendantOf(Players) then
		self.EliminationChoiceResolvedEvent:Fire(player, { Choice = choice })
	end

	if choice == "Respawn" then
		self:_respawnIntoMatch(player)
	else
		self:_returnToLobby(player)
	end

	self.OnEliminationChoiceResolved:Fire(player, choice)
end

function RoundManager:_handleEliminationChoiceRequest(player: Player, payload: any)
	if not self._pendingChoices[player] then
		return -- not eligible, ignore
	end

	local choice = nil
	if typeof(payload) == "string" then
		choice = payload
	elseif typeof(payload) == "table" then
		choice = payload.Choice or payload.choice
	end

	if choice ~= "Respawn" and choice ~= "Leave" then
		return
	end

	if choice == "Respawn" then
		self:_requestPaidRespawn(player)
	else
		self:_resolveEliminationChoice(player, choice)
	end
end

function RoundManager:_clearAllPendingChoices()
	-- Snapshot first; _resolveEliminationChoice mutates _pendingChoices.
	local toResolve = {}
	for player in self._pendingChoices do
		table.insert(toResolve, player)
	end
	for _, player in toResolve do
		self:_resolveEliminationChoice(player, "Leave")
	end
end

function RoundManager:_hasPendingEliminationChoices(): boolean
	for _ in self._pendingChoices do
		return true
	end
	return false
end

----------------------------------------------------------------
-- Bomb holder + pass validation (RoundManager owns the circle)
----------------------------------------------------------------

-- Picks a random alive player and sets them as the bomb holder.
function RoundManager:_assignRandomBombHolder(): Player?
	if not BombManager then
		return nil
	end

	if #self._alive == 0 then
		BombManager:SetHolder(nil)
		return nil
	end

	local picked = self._alive[math.random(1, #self._alive)]
	BombManager:SetHolder(picked)
	return picked
end

function RoundManager:_clearLockTarget(shouldNotify: boolean)
	local target = self._lockTarget
	self._lockTarget = nil
	self._lockTargetExpiresAt = 0

	if shouldNotify and target and NotificationManager then
		NotificationManager.NotifyNormalEvent:Fire(
			BridgeNet2.AllPlayers(),
			`Lock Target on <font color="#ff0000">{target.Name}</font> is over`
		)
	end
end

function RoundManager:_getLockTarget(): Player?
	local target = self._lockTarget
	if not target then
		return nil
	end

	if workspace:GetServerTimeNow() >= self._lockTargetExpiresAt then
		self:_clearLockTarget(true)
		return nil
	end

	if not self._matchActive or not target:IsDescendantOf(Players) or not indexOf(self._alive, target) then
		self:_clearLockTarget(false)
		return nil
	end

	return target
end

-- Resolves a pass target by direction, given the current alive list as the
-- circle order. Left = previous index (wraps), Right = next index (wraps),
-- Front = directly across (#alive / 2 offset).
function RoundManager:_resolvePassTarget(direction: string): Player?
	if not BombManager then
		return nil
	end

	local holder = BombManager:GetHolder()
	if not holder then
		return nil
	end

	local holderIdx = indexOf(self._alive, holder)
	if not holderIdx then
		return nil
	end

	local count = #self._alive
	if count <= 1 then
		return nil
	end

	local lockTarget = self:_getLockTarget()
	if lockTarget then
		return lockTarget
	end

	local targetIdx
	if direction == "Right" then
		targetIdx = ((holderIdx - 2) % count) + 1
	elseif direction == "Left" then
		targetIdx = (holderIdx % count) + 1
	elseif direction == "Front" then
		local offset = math.floor(count / 2)
		if offset < 1 then
			offset = 1
		end
		targetIdx = ((holderIdx - 1 + offset) % count) + 1
	else
		return nil
	end

	return self._alive[targetIdx]
end

-- Handles a client `RequestBombPass` request. The bomb is purely a state
-- holder; RoundManager is responsible for deciding whether the pass is legal.
function RoundManager:_handleBombPassRequest(player: Player, payload: any)
	if not BombManager then
		return
	end

	if not self._matchActive then
		return
	end

	-- Lock passes during pre/post-elimination grace windows. Without this,
	-- players can keep volleying the bomb during the wind-up window after the
	-- timer expires. The pre-match countdown leaves this unlocked so the holder
	-- can pass while the buttons are visible but before the music starts.
	if self._passesLocked then
		return
	end

	-- Payload may be { direction = string } or { "Left" } or "Left"
	local direction = nil
	if typeof(payload) == "string" then
		direction = payload
	elseif typeof(payload) == "table" then
		direction = payload.direction or payload.Direction or payload[1]
	end

	if not direction or not GameConfigs.VALID_PASS_DIRECTIONS[direction] then
		return
	end

	if BombManager:GetHolder() ~= player then
		return -- requester is not the bomb holder
	end

	local target = self:_resolvePassTarget(direction)
	if not target or target == player then
		return
	end

	if not indexOf(self._alive, target) then
		return -- target is not in the alive list
	end

	local now = workspace:GetServerTimeNow()
	if now - self._lastPassAt < GameConfigs.PASS_COOLDOWN then
		return
	end
	self._lastPassAt = now

	local from = player
	if self:_consumeShield(target, from) then
		return
	end

	BombManager:SetHolder(target)
	self.OnBombPassed:Fire(from, target, direction)

	if self:_consumeReflect(target, from) then
		return
	end
end

----------------------------------------------------------------
-- Match flow (called by stage modules)
----------------------------------------------------------------

function RoundManager:HasEnoughPlayers(): boolean
	return #self:GetEligiblePlayers() >= GameConfigs.MIN_PLAYERS_TO_START
end

function RoundManager:GetEligiblePlayers(): { Player }
	local eligible = {}
	for _, player in Players:GetPlayers() do
		if not AFKManager:IsAFK(player) then
			table.insert(eligible, player)
		end
	end
	return eligible
end

function RoundManager:IsMatchActive(): boolean
	return self._matchActive and self._currentStageName == "Match"
end

function RoundManager:IsLastRoundActive(): boolean
	return self:IsMatchActive() and self._lastRoundActive and not self._lastRoundResolved
end

function RoundManager:IsPlayerAlive(player: Player): boolean
	return indexOf(self._alive, player) ~= nil
end

function RoundManager:IsPlayerInActiveMatch(player: Player): boolean
	return self:IsMatchActive() and self:IsPlayerAlive(player)
end

function RoundManager:GetAlivePlayers(): { Player }
	local alive = {}
	for _, player in self._alive do
		table.insert(alive, player)
	end
	return alive
end

function RoundManager:ActivateShield(player: Player): boolean
	if not self:IsPlayerInActiveMatch(player) then
		return false
	end

	if self._activeShields[player] then
		NotificationManager.NotifyNormalEvent:Fire(player, { "Shield is already active.", 3, "Reject" })
		return false
	end

	self._activeShields[player] = true
	return true
end

function RoundManager:ActivateReflect(player: Player): boolean
	if not self:IsPlayerInActiveMatch(player) then
		return false
	end

	if self._activeReflects[player] then
		NotificationManager.NotifyNormalEvent:Fire(player, { "Reflect is already active.", 3, "Reject" })
		return false
	end

	self._activeReflects[player] = true
	return true
end

function RoundManager:ActivateStopMusic(player: Player): boolean
	if not self:IsPlayerInActiveMatch(player) then
		return false
	end

	if self._passesLocked or self._explosionTimestamp <= workspace:GetServerTimeNow() then
		NotificationManager.NotifyNormalEvent:Fire(player, { "Music is not currently playing.", 3, "Reject" })
		return false
	end

	self._explosionTimestamp = workspace:GetServerTimeNow()
	self:_publishExplosionTimestamp()
	return true
end

function RoundManager:ActivateNuke(player: Player): boolean
	if not self:IsPlayerInActiveMatch(player) then
		return false
	end

	if self._passesLocked or self._explosionTimestamp <= workspace:GetServerTimeNow() then
		NotificationManager.NotifyNormalEvent:Fire(player, { "Nuke cannot be used right now.", 3, "Reject" })
		return false
	end

	if self._nukeActive then
		NotificationManager.NotifyNormalEvent:Fire(player, { "A nuke is already active.", 3, "Reject" })
		return false
	end

	if #self._alive <= 1 then
		return false
	end

	self._nukeActive = true
	self._passesLocked = true

	local timerLockDuration = GameConfigs.NUKE_TIMER_LOCK_DURATION
	self._musicDuration = timerLockDuration
	self._explosionTimestamp = workspace:GetServerTimeNow() + timerLockDuration
	self:_publishExplosionTimestamp()
	self.SyncExplosionTimeEvent:Fire(BridgeNet2.AllPlayers(), {
		Timestamp = self._explosionTimestamp,
		Duration = timerLockDuration,
	})

	EffectManager.RunEffect:Fire(BridgeNet2.AllPlayers(), { "Nuke" })

	task.delay(GameConfigs.NUKE_EFFECT_DELAY, function()
		if not self._nukeActive then
			return
		end

		self._nukeActive = false

		if not self:IsMatchActive() then
			self._passesLocked = false
			return
		end

		if not self:IsPlayerAlive(player) then
			self._passesLocked = false
			return
		end

		local victims = {}
		for _, alivePlayer in self._alive do
			if alivePlayer ~= player then
				table.insert(victims, alivePlayer)
			end
		end

		for _, victim in victims do
			if self:IsPlayerAlive(victim) then
				self:_eliminate(victim, true)
			end
		end

		if #self._alive <= 1 then
			self._suppressNextMusicStop = true
		end

		self._passesLocked = false
	end)

	return true
end

function RoundManager:ActivateLockTarget(player: Player, target: Player, duration: number?): boolean
	if not BombManager then
		return false
	end

	if not self:IsPlayerInActiveMatch(player) or not self:IsPlayerInActiveMatch(target) then
		return false
	end

	if player == target then
		NotificationManager.NotifyNormalEvent:Fire(player, { "Select another player.", 3, "Reject" })
		return false
	end

	if self._passesLocked then
		NotificationManager.NotifyNormalEvent:Fire(player, { "The bomb cannot be retargeted right now.", 3, "Reject" })
		return false
	end

	local lockDuration = type(duration) == "number" and duration > 0 and duration

	self._lockTarget = target
	self._lockTargetExpiresAt = workspace:GetServerTimeNow() + lockDuration
	local expiresAt = self._lockTargetExpiresAt

	NotificationManager.NotifyNormalEvent:Fire(
		BridgeNet2.AllPlayers(),
		`The bomb will target <font color="#ff0000">{target.Name}</font> for <font color="#55ff00">{lockDuration}</font> seconds`
	)

	task.delay(lockDuration, function()
		if self._lockTarget == target and self._lockTargetExpiresAt == expiresAt then
			self:_clearLockTarget(true)
		end
	end)

	return true
end

function RoundManager:_consumeShield(target: Player, from: Player): boolean
	if not self._activeShields[target] then
		return false
	end

	self._activeShields[target] = nil

	NotificationManager.NotifyNormalEvent:Fire(
		BridgeNet2.AllPlayers(),
		`<font color="#55ff00">{target.Name}</font> blocked <font color="#ff0000">{from.Name}</font>'s pass`
	)

	return true
end

function RoundManager:_consumeReflect(target: Player, from: Player): boolean
	if not self._activeReflects[target] then
		return false
	end

	if not indexOf(self._alive, from) then
		self._activeReflects[target] = nil
		return false
	end

	self._activeReflects[target] = nil

	task.wait(0.15)
	BombManager:SetHolder(from)

	NotificationManager.NotifyNormalEvent:Fire(
		BridgeNet2.AllPlayers(),
		`<font color="#55ff00">{target.Name}</font> reflected the bomb back to <font color="#ff0000">{from.Name}</font>`
	)

	self.OnBombPassed:Fire(target, from, "Reflect")
	return true
end

----------------------------------------------------------------
-- Last round brawl
----------------------------------------------------------------

-- Ends the final brawl state and lets brawl-only systems clean up.
function RoundManager:_endLastRound()
	if not self._lastRoundActive and self._lastRoundResolved then
		return
	end

	local wasActive = self._lastRoundActive
	self._lastRoundActive = false
	self._lastRoundResolved = true
	self._lastRoundPlayers = nil
	self._lastRoundStartedPayload = nil
	self:_setReplicaValue("LastRoundPlayers", {})

	if wasActive then
		self.OnLastRoundEnded:Fire()
	end
end

-- Shows or hides the final brawl hit part and its texture markers.
function RoundManager:_setLastRoundHitPartVisible(isVisible: boolean)
	local hitPart = self._lastRoundHitPart
	if not hitPart then
		return
	end

	hitPart.Transparency = if isVisible then 0 else 1
	hitPart.CanTouch = isVisible

	for _, descendant in hitPart:GetDescendants() do
		if descendant:IsA("Texture") then
			descendant.Transparency = if isVisible then 0 else 1
		end
	end
end

-- Restores last-round arena state so the next match starts from the full arena.
function RoundManager:_resetLastRoundArena()
	self:_endLastRound()

	if self._lastRoundScaleThread then
		task.cancel(self._lastRoundScaleThread)
		self._lastRoundScaleThread = nil
	end

	local arena = workspace.Main:FindFirstChild("Arena")
	if arena and arena:IsA("Model") then
		arena:ScaleTo(self._arenaOriginalScale)
	end

	self:_setLastRoundHitPartVisible(false)
	self._lastRoundResolved = false
end

-- Shrinks the arena model over the configured duration using Model:ScaleTo().
function RoundManager:_startLastRoundArenaScale()
	if self._lastRoundScaleThread then
		task.cancel(self._lastRoundScaleThread)
	end

	local arena = workspace.Main:FindFirstChild("Arena")
	if not arena or not arena:IsA("Model") then
		warn("[RoundManager] Arena model workspace.Main.Arena not found; cannot scale last round arena")
		return
	end

	local startScale = arena:GetScale()
	local targetScale = GameConfigs.LAST_ROUND_ARENA_TARGET_SCALE
	local duration = GameConfigs.LAST_ROUND_ARENA_SCALE_DURATION

	self._lastRoundScaleThread = task.spawn(function()
		local startedAt = os.clock()
		while self._lastRoundActive do
			local alpha = if duration > 0 then math.clamp((os.clock() - startedAt) / duration, 0, 1) else 1
			arena:ScaleTo(startScale + (targetScale - startScale) * alpha)

			if alpha >= 1 then
				break
			end

			RunService.Heartbeat:Wait()
		end

		self._lastRoundScaleThread = nil
	end)
end

-- Starts the final 1v1 brawl and yields until a winner can be resolved.
function RoundManager:_startLastRoundBrawl()
	if self._lastRoundActive or self._lastRoundResolved then
		return
	end

	if not self._lastRoundHitPart then
		warn("[RoundManager] Last round brawl skipped because LastRoundHitPart is missing")
		return
	end

	self._lastRoundActive = true
	self._lastRoundResolved = false
	self._passesLocked = true
	self._suppressNextMusicStop = true
	self:_stopMusicCycle(true)

	if BombManager then
		BombManager:SetHolder(nil)
	end

	for secondsLeft = GameConfigs.LAST_ROUND_COUNTDOWN, 0, -1 do
		self.LastRoundCountdownEvent:Fire(BridgeNet2.AllPlayers(), {
			SecondsLeft = secondsLeft,
		})

		if secondsLeft > 0 then
			task.wait(1)
		end
	end

	if #self._alive ~= 2 then
		self:_resetLastRoundArena()
		return
	end

	local lastRoundPlayers = {
		self._alive[1],
		self._alive[2],
	}
	local lastRoundStartedPayload = {
		Players = {
			serializePlayer(lastRoundPlayers[1]),
			serializePlayer(lastRoundPlayers[2]),
		},
	}
	self._lastRoundPlayers = lastRoundPlayers
	self._lastRoundStartedPayload = lastRoundStartedPayload
	self:_setReplicaValue("LastRoundPlayers", lastRoundStartedPayload.Players)

	self.LastRoundStartedEvent:Fire(BridgeNet2.AllPlayers(), lastRoundStartedPayload)
	self.OnLastRoundStarted:Fire(lastRoundPlayers)

	for _, player in self._alive do
		resetPlayerMovement(player)
	end

	self:_setLastRoundHitPartVisible(true)
	self:_startLastRoundArenaScale()

	while self._matchActive and self._lastRoundActive and not self._lastRoundResolved and #self._alive == 2 do
		task.wait()
	end
end

-- Eliminates the first finalist who touches the brawl hit part.
function RoundManager:_handleLastRoundHit(hit: BasePart)
	if not self._lastRoundActive or self._lastRoundResolved then
		return
	end

	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player or not indexOf(self._alive, player) then
		return
	end

	self:_endLastRound()
	self:_setLastRoundHitPartVisible(false)
	self:_eliminate(player, true)
end

-- Stage hook: called from InitMatch.
-- self._alive is populated + characters pre-loaded by Intermission.OnEnd so
-- the pruned alive list lands on clients together with the InitMatch
-- CurrentStage replica change (OnEnterMatchAsPlayer reads from it on the same frame).
function RoundManager:StartMatch(): boolean
	self._placements = {}
	self._matchActive = false
	self._passesLocked = false
	self._lastPassAt = 0
	self._activeShields = {}
	self._activeReflects = {}
	self._nukeActive = false
	self._suppressNextMusicStop = false
	self:_clearLockTarget(false)
	self._eliminationBoardTitle.Text = ""
	self:_resetLastRoundArena()

	self:_setReplicaValue("Placements", {})

	if BombManager then
		BombManager:SetHolder(nil)
	end
	self:_stopMusicCycle()

	if #self._alive < GameConfigs.MIN_PLAYERS_TO_START then
		self._alive = {}
		self:_publishAliveList()
		return false
	end

	self:_teleportPlayersToCircle()

	-- Lock movement for all participants while the match is active
	for _, player in self._alive do
		setPlayerMovement(player, GameConfigs.MATCH_WALKSPEED, GameConfigs.MATCH_JUMPPOWER)
	end

	if BombManager and #self._alive > 2 then
		self:_assignRandomBombHolder()
	end

	self.OnMatchStarted:Fire(self._alive)
	return true
end

-- Stage hook: called from Match. Yields until 1 player remains.
function RoundManager:RunMatchLoop()
	if #self._alive < GameConfigs.MIN_PLAYERS_TO_START then
		return
	end

	self._matchActive = true

	-- Pre-match countdown so clients can load UI / camera before the timer starts
	task.wait(GameConfigs.INIT_MATCH_COUNTDOWN)

	if not BombManager then
		warn("[RoundManager] RunMatchLoop — BombManager not loaded, aborting")
		self._matchActive = false
		return
	end

	if #self._alive == 2 then
		self:_startLastRoundBrawl()
		if #self._alive <= 1 then
			self._matchActive = false
			local suppressClientMusicStop = self._suppressNextMusicStop
			self._suppressNextMusicStop = false
			self:_stopMusicCycle(suppressClientMusicStop)
			return
		end
	end

	if not BombManager:GetHolder() then
		self:_assignRandomBombHolder()
	end

	self:_startMusicCycle(
		RandomUtil.GetRandomFromMinMax(GameConfigs.MUSIC_DURATION_RANGE.Min, GameConfigs.MUSIC_DURATION_RANGE.Max)
	)

	while self._matchActive do
		if #self._alive <= 1 then
			while self._matchActive and #self._alive <= 1 and self:_hasPendingEliminationChoices() do
				task.wait()
			end
			if #self._alive > 1 then
				if not BombManager:GetHolder() then
					self:_assignRandomBombHolder()
				end
			end
		end

		if #self._alive <= 1 then
			break
		end

		if #self._alive == 2 and not self._lastRoundActive and not self._lastRoundResolved then
			self:_teleportPlayersToCircle()
			self:_startLastRoundBrawl()
			if #self._alive <= 1 then
				break
			end
			if #self._alive > 2 and self._explosionTimestamp <= 0 then
				if not BombManager:GetHolder() then
					self:_assignRandomBombHolder()
				end
				self._passesLocked = false
				self:_startMusicCycle(
					RandomUtil.GetRandomFromMinMax(
						GameConfigs.MUSIC_DURATION_RANGE.Min,
						GameConfigs.MUSIC_DURATION_RANGE.Max
					)
				)
			end
		end

		if self:_isMusicTimerExpired() then
			local victim = BombManager:GetHolder()

			-- Grace 1: warn clients before the elimination so they can play pre-death effects.
			local victimEliminated = false
			if victim and indexOf(self._alive, victim) then
				-- Stop the music cycle first so clients fire OnMusicStop before
				-- the grace window starts. Edit GameConfigs.PRE_ELIMINATION_GRACE
				-- to change how long this window lasts.
				self._passesLocked = true
				self:_stopMusicCycle()
				self.PreEliminationEvent:Fire(BridgeNet2.AllPlayers(), {
					Victim = serializePlayer(victim),
				})
				task.wait(GameConfigs.PRE_ELIMINATION_GRACE)

				if indexOf(self._alive, victim) then
					-- Still present: eliminate normally.
					self:_eliminate(victim)
					victimEliminated = true
				else
					-- Victim disconnected during the grace window.
					-- _onPlayerLeaving already removed them, re-circled, and cleared
					-- the bomb holder — skip duplication below.
				end
			end

			if #self._alive <= 1 then
				while self._matchActive and #self._alive <= 1 and self:_hasPendingEliminationChoices() do
					task.wait()
				end
			end

			if #self._alive <= 1 then
				break
			end

			if #self._alive == 2 then
				if victimEliminated then
					self.PostEliminationEvent:Fire(BridgeNet2.AllPlayers(), {
						RemainingCount = #self._alive,
					})

					task.wait(GameConfigs.POST_ELIMINATION_GRACE)
				end

				self:_teleportPlayersToCircle()
				self:_startLastRoundBrawl()
				if #self._alive <= 1 then
					break
				end

				continue
			end

			if victimEliminated then
				-- Grace 2: let clients react before the circle resets.
				-- Skipped on disconnect because _onPlayerLeaving already re-circled.
				self.PostEliminationEvent:Fire(BridgeNet2.AllPlayers(), {
					RemainingCount = #self._alive,
				})

				task.wait(GameConfigs.POST_ELIMINATION_GRACE)
			end

			-- Re-arrange survivors into a fresh circle after each elimination.
			-- (Already done by _onPlayerLeaving on disconnect, so only needed here.)
			self:_teleportPlayersToCircle()
			task.wait(GameConfigs.POST_RESET_DELAY)

			-- Always reassign bomb and restart music — _onPlayerLeaving clears the
			-- holder on disconnect but does not start a new cycle.
			self:_assignRandomBombHolder()
			self._passesLocked = false
			self:_startMusicCycle(
				RandomUtil.GetRandomFromMinMax(
					GameConfigs.MUSIC_DURATION_RANGE.Min,
					GameConfigs.MUSIC_DURATION_RANGE.Max
				)
			)
		end

		task.wait()
	end

	self._matchActive = false
	local suppressClientMusicStop = self._suppressNextMusicStop
	self._suppressNextMusicStop = false
	self:_stopMusicCycle(suppressClientMusicStop)
end

-- Stage hook: called from MatchEnd. Awards winner, fires celebration, then yields.
function RoundManager:FinalizeMatch()
	-- Make sure no eliminated player is still ragdolled in the arena waiting on
	-- a LEAVE/RESPAWN prompt — resolve them all to Leave and send to lobby.
	self:_clearAllPendingChoices()

	local winner = self._alive[1]

	for _, userId in self._placements do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			PlayerDataManager:IncrementDataKey(player, "Loses")
		end
	end

	if winner then
		table.insert(self._placements, 1, winner.UserId)
		self._eliminationBoardTitle.Text = `<font color="#ffd400">{winner.Name:upper()} HAS WON THE GAME</font>`

		-- Restore winner's movement so they can walk around during celebration
		resetPlayerMovement(winner)

		CurrencyManager:IncrementCurrency(winner, GameConfigs.WINNER_REWARD, true)

		local winAmount = winner:HasTag("x2Win") and 2 or 1
		PlayerDataManager:IncrementDataKey(winner, "Wins", winAmount)

		self:SetWinner(winner)
		self:SetStatus("Round End", `{winner.DisplayName or winner.Name} wins!`)
	else
		self._eliminationBoardTitle.Text = ""
		self:SetStatus("Round End", "No winner this round.")
	end

	local placementsPayload = self:_publishPlacements()
	self.MatchEndEvent:Fire(BridgeNet2.AllPlayers(), {
		Winner = serializePlayer(winner),
		Placements = placementsPayload,
	})

	-- HOOK: confetti, camera focus on winner, winner UI, fanfare music, etc.
	if winner then
		self:_onMatchEnded(winner, placementsPayload)
	end
	self.OnMatchEnded:Fire(winner, placementsPayload)

	for _, userId in self._placements do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			PlayerDataManager:IncrementDataKey(player, "GamesPlayed")
		end
	end

	task.wait(GameConfigs.MATCH_END_CELEBRATION_DURATION)

	-- Cleanup state for next match
	self._alive = {}
	self._activeShields = {}
	self._activeReflects = {}
	self._nukeActive = false
	self._suppressNextMusicStop = false
	self:_clearLockTarget(false)
	self:_resetLastRoundArena()
	self._eliminationBoardTitle.Text = ""
	self:_publishAliveList()
	if BombManager then
		BombManager:SetHolder(nil)
	end
end

----------------------------------------------------------------
-- Disconnect handling
----------------------------------------------------------------

function RoundManager:_onPlayerLeaving(player: Player)
	self._activeShields[player] = nil
	self._activeReflects[player] = nil
	if self._lockTarget == player then
		self:_clearLockTarget(false)
	end

	-- Clear any pending choice prompt for the leaving player. No teleport
	-- needed since their character is about to be destroyed anyway.
	local pending = self._pendingChoices[player]
	if pending then
		pending.Resolved = true
		self._pendingChoices[player] = nil
	end

	local idx = indexOf(self._alive, player)
	if not idx then
		return
	end

	if not self._matchActive then
		table.remove(self._alive, idx)
		self:_publishAliveList()
		if BombManager and BombManager:GetHolder() == player then
			BombManager:SetHolder(nil)
		end
		return
	end

	local wasHolder = BombManager and BombManager:GetHolder() == player

	-- Restore movement before they fully leave (character may still exist briefly)
	resetPlayerMovement(player)

	table.remove(self._alive, idx)
	table.insert(self._placements, 1, player.UserId)
	self:_publishAliveList()

	NotificationManager.NotifyNormalEvent:Fire(BridgeNet2.AllPlayers(), {
		`<font color="#ff0000">{player.Name}</font> left the game`,
		3,
		"Notify",
	})

	if wasHolder and BombManager then
		-- Clear, then (if there are survivors) reassign immediately. No
		-- elimination, no reward — they just left.
		BombManager:SetHolder(nil)
	end

	if #self._alive <= 1 then
		-- RunMatchLoop will detect this and exit naturally. The final timer
		-- clear should not play the music-stopped warning for the winner.
		self._suppressNextMusicStop = true
		if self._lastRoundActive then
			self:_endLastRound()
			self:_setLastRoundHitPartVisible(false)
		end
		return
	end

	-- Re-arrange survivors into a fresh circle after the disconnect
	self:_teleportPlayersToCircle()

	if #self._alive == 2 then
		self.PostEliminationEvent:Fire(BridgeNet2.AllPlayers(), {
			RemainingCount = #self._alive,
		})

		self._passesLocked = true
		self._suppressNextMusicStop = true
		self:_stopMusicCycle(true)
		if BombManager then
			BombManager:SetHolder(nil)
		end
		return
	end

	if wasHolder then
		self:_assignRandomBombHolder()
	end
end

----------------------------------------------------------------
-- Hooks (override or listen via signals)
----------------------------------------------------------------

function RoundManager:_onPlayerEliminated(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local explosion = Instance.new("Explosion")
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Position = character:GetPivot().Position
	explosion.Parent = workspace

	SoundManager:PlayToPlayers("Explosion", character:GetPivot())

	RagdollManager:Ragdoll(player, 100, Vector3.new(0, 300, 250))
end

function RoundManager:_onMatchEnded(winner)
	local character = winner.Character

	if not character then
		return
	end

	--
	character:PivotTo(workspace.Spawn:GetPivot() * CFrame.new(0, 2, 0))

	EffectManager.RunEffect:Fire(BridgeNet2.AllPlayers(), {
		"Confetti",
		{
			origin = character,
			amount = NumberRange.new(5, 10),
			types = { "Regular" },
			height = NumberRange.new(10, 15),
			speed = NumberRange.new(15, 20),
			launchDelay = NumberRange.new(0.5, 0.9),
		},
	})

	--
	local humanoid: Humanoid = character.Humanoid
	local humanoidDesc = humanoid:GetAppliedDescription()

	--
	humanoidDesc.DepthScale = 7
	humanoidDesc.HeightScale = 7
	humanoidDesc.WidthScale = 7
	humanoidDesc.HeadScale = 7

	--
	local winningRig: Model = Meshes.WinRig:Clone()
	winningRig:PivotTo(workspace.Main.Arena.Main:GetPivot() * CFrame.new(0, winningRig:GetExtentsSize().Y / 2, 0))
	winningRig.Parent = workspace.Main

	winningRig.Humanoid:ApplyDescription(humanoidDesc)
	self._winningRig = winningRig

	-- Play winning animation
	local animator = winningRig.Humanoid.Animator
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://79709220174777"

	local animationTrack = animator:LoadAnimation(animation)
	animationTrack:Play()

	--
	local arenaCenter = workspace.Main.Arena.Main:GetPivot()
	local confettiCount = math.random(15, 20)
	local confettiCframes = table.create(confettiCount)
	for i = 1, confettiCount do
		-- Evenly space around the arena, then jitter the angle and radius so it doesn't look gridded
		local angle = math.rad((i - 1) * (360 / confettiCount) + math.random(-15, 15))
		local radius = math.random(10, 18)
		confettiCframes[i] = arenaCenter * CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	end

	EffectManager.RunEffect:Fire(BridgeNet2.AllPlayers(), {
		"Confetti",
		{
			origin = confettiCframes,
			amount = NumberRange.new(1, 2),
			types = { "Big", "ExtraLarge" },
			height = NumberRange.new(40, 60),
			spread = NumberRange.new(-4, 4),
			depth = NumberRange.new(-4, 4),
			speed = NumberRange.new(24, 28),
			perOriginDelay = NumberRange.new(0.05, 0.15),
		},
	})
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function RoundManager:OnInit()
	self._eliminationBoardTitle = workspace.Main.EliminationBoard.Board.EliminationUI.Title
	self._eliminationBoardTitle.RichText = true
	self._eliminationBoardTitle.Text = ""

	local arena = workspace.Main:FindFirstChild("Arena")
	if arena and arena:IsA("Model") then
		self._arenaOriginalScale = arena:GetScale()
	end

	local lastRoundHitPart = workspace.Main:FindFirstChild("LastRoundHitPart")
	if lastRoundHitPart and lastRoundHitPart:IsA("BasePart") then
		self._lastRoundHitPart = lastRoundHitPart
		self:_setLastRoundHitPartVisible(false)
		self._lastRoundTouchConnection = lastRoundHitPart.Touched:Connect(function(hit: BasePart)
			self:_handleLastRoundHit(hit)
		end)
	else
		warn("[RoundManager] workspace.Main.LastRoundHitPart not found; final brawl touch elimination disabled")
	end

	self._roundReplica = Replica.New({
		Token = ROUND_DATA_TOKEN,
		Data = {
			CurrentStage = FIRST_STAGE,
			StageDisplayName = FIRST_STAGE,
			StatusText = "",
			SubStatusText = "",
			Winner = nil,
			RoundNumber = 0,
			IsRoundActive = false,
			StageStartedAt = 0,
			AlivePlayers = {},
			Placements = {},
			BombHolderUserId = nil,
			LastRoundPlayers = {},
			MusicToPlay = nil,
			ExplosionTimestamp = 0,
			IntermissionEndsAt = 0,
		},
	})

	self._roundReplica:Replicate()

	BombManager = require(script.Parent.BombManager)
	CurrencyManager = require(script.Parent.CurrencyManager)
	RagdollManager = require(script.Parent.RagdollManager)
	EffectManager = require(script.Parent.EffectManager)
	ShopManager = require(script.Parent.ShopManager)
	NotificationManager = require(script.Parent.NotificationManager)
	PlayerDataManager = require(script.Parent.PlayerDataManager)
	SoundManager = require(script.Parent.SoundManager)
	AFKManager = require(script.Parent.AFKManager)
end

function RoundManager:OnStart()
	for _, player in Players:GetPlayers() do
		player:SetAttribute(PLAYER_IN_GAME_ATTRIBUTE, false)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		player:SetAttribute(PLAYER_IN_GAME_ATTRIBUTE, false)
		if self:IsLastRoundActive() and self._lastRoundStartedPayload then
			self.LastRoundStartedEvent:Fire(player, self._lastRoundStartedPayload)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:_onPlayerLeaving(player)
	end)

	BombManager.OnHolderChanged:Connect(function(player: Player?)
		self:_publishBombHolder(player)
		self:_runBombHoldReward(player)
	end)

	BombManager.RequestBombPass:Connect(function(player: Player, payload: any)
		self:_handleBombPassRequest(player, payload)
	end)

	self.EliminationChoiceRequestEvent:Connect(function(player: Player, payload: any)
		self:_handleEliminationChoiceRequest(player, payload)
	end)

	ShopManager.PlayerPurchased:Connect(function(player: Player, productId: string)
		if isRespawnProductId(productId) then
			self:_handleRespawnProductPurchased(player)
		end
	end)

	ShopManager.ProductPromptFinished:Connect(function(player: Player, productId: string, wasPurchased: boolean)
		if isRespawnProductId(productId) then
			self:_handleRespawnProductPromptFinished(player, productId, wasPurchased)
		end
	end)

	task.spawn(function()
		while true do
			local nextStage = self:_runStage(self._currentStageName)

			if nextStage == true then
				nextStage = self._currentStage:GetNextStageName(self)
			end

			self._currentStageName = nextStage
		end
	end)
end

return RoundManager
