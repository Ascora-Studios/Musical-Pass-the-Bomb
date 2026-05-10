--[[
	RoundController

	Mirrors the server's `RoundData` replica and listens to round/bomb-related
	BridgeNet2 events. Exposes empty hook methods you can fill in for visuals,
	UI, sounds, camera effects, etc.

	Hooks (override these — they're called automatically):
	  :OnIntermissionStart()                        - intermission stage began
	  :OnIntermissionWaiting()                      - not enough players; countdown paused
	  :OnIntermissionCountdown(secondsLeft)         - fires every second during intermission (5 → 0)
	  :OnEnterMatchAll()                            - InitMatch stage; runs for BOTH players and spectators (UI swap, etc.)
	  :OnEnterMatchAsPlayer()                       - InitMatch stage; runs ONLY for players in the alive list
	  :OnEnterMatchSpectator()                      - InitMatch stage; runs ONLY for spectators (joined mid-game)
	  :OnMatchStart()                               - Match stage (music timer starts soon)
	  :OnPreElimination(victimInfo)                 - server grace starts; victim about to be eliminated (play effects now)
	  :OnPlayerEliminated(eliminatedInfo, remaining) - player was just eliminated
	  :OnPostElimination(remainingCount)            - server grace starts; circle is about to reset (play effects now)
	  :OnEliminationChoicePrompt(expirationTime)    - LOCAL ONLY; you were eliminated and the match still has > 2 alive — show LEAVE/RESPAWN UI
	  :OnEliminationChoiceResolved(choice)          - LOCAL ONLY; the prompt was answered, timed out, or was cancelled — hide the UI
	                                                  (`choice` is "Respawn" or "Leave"; call :RequestRespawn() / :RequestLeave() to answer)
	  :OnReceiveBomb()                              - YOU just received the bomb
	  :OnOtherPlayerReceiveBomb(player, userId)     - another player just received the bomb
	  :OnBombPassed(player, skipAnim, fromPlayer)   - bomb holder changed; fromPlayer is nil if there is no source
	  :OnMusicStart(explosionTimestamp)             - server set a new explosion timer (music cycle started/resumed)
	  :OnMusicStop()                                - server cleared the explosion timer (music cycle stopped)
	  :OnMatchEnd(winner, placements)               - match over; celebration phase (confetti, winner UI, fanfare, etc.)

	Other helpers:
	  :HasBomb()                                    - true if local player is the bomb holder
	  :IsInMatch()                                  - true if local player is in the alive list (not a spectator)
	  :GetBombHolderUserId()
	  :GetExplosionTimestamp()
	  :GetCurrentStage()
	  :RequestBombPass(direction)                   - "Left" | "Right" | "Front"
	  :RequestRespawn()                             - answer the elimination prompt with RESPAWN (re-enter the match)
	  :RequestLeave()                               - answer the elimination prompt with LEAVE (return to lobby as spectator)
]]

-- Services
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Promise = require(Packages.Promise)
local Trove = require(Packages.Trove)
local Replica = require(Packages.Replica)
local Signal = require(Packages.Signal)
local Spr = require(Packages.Spr)

--
local Assets = ReplicatedStorage.Assets
local Meshes = Assets.Meshes

--
local LocalPlayer = Players.LocalPlayer
local Controls =
	require(LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"):WaitForChild("ControlModule"))
local PlayerGui = LocalPlayer.PlayerGui

--
local DEFAULT_TIMEOUT = 15

--
local HudController
local UIController
local SoundController
local PlayerDataController
local AnimationController

--
local RoundController = {
	-- Public signals (in case you'd rather Connect than override)
	OnReplicaReady = Signal.new(),
	OnDataChanged = Signal.new(),

	OnIntermissionStartedSignal = Signal.new(),
	OnIntermissionWaitingSignal = Signal.new(), -- fired when not enough players (countdown paused)
	OnIntermissionCountdownSignal = Signal.new(), -- (secondsLeft: string) fires every ~0.05s during countdown
	OnEnterMatchAllSignal = Signal.new(), -- fires for BOTH players and spectators
	OnEnterMatchAsPlayerSignal = Signal.new(), -- fires only for players in the alive list
	OnEnterMatchSpectatorSignal = Signal.new(), -- fires only for spectators (joined mid-game)
	OnMatchStartedSignal = Signal.new(),
	OnPreEliminationSignal = Signal.new(), -- (victimInfo) fired during PRE_ELIMINATION_GRACE
	OnPlayerEliminatedSignal = Signal.new(), -- (eliminatedInfo, remainingCount)
	OnPostEliminationSignal = Signal.new(), -- (remainingCount) fired during POST_ELIMINATION_GRACE
	OnReceiveBombSignal = Signal.new(),
	OnOtherPlayerReceiveBombSignal = Signal.new(), -- (player: Player?, userId: number)
	OnMusicStartSignal = Signal.new(), -- (explosionTimestamp: number)
	OnMusicStopSignal = Signal.new(),
	OnMatchEndSignal = Signal.new(), -- (winner: { UserId, Name, DisplayName }?, placements: { [number]: any })
	OnEliminationChoicePromptSignal = Signal.new(), -- (expirationTime: number)
	OnEliminationChoiceResolvedSignal = Signal.new(), -- (choice: string) "Respawn" | "Leave"

	-- BridgeNet2 references (server creates with these names)
	RequestBombPassBridge = BridgeNet2.ReferenceBridge("RequestBombPass"),
	SyncBombHolderBridge = BridgeNet2.ReferenceBridge("SyncBombHolder"),
	SyncExplosionTimeBridge = BridgeNet2.ReferenceBridge("SyncExplosionTime"),
	PreEliminationBridge = BridgeNet2.ReferenceBridge("PreElimination"),
	PlayerEliminatedBridge = BridgeNet2.ReferenceBridge("PlayerEliminated"),
	PostEliminationBridge = BridgeNet2.ReferenceBridge("PostElimination"),
	MatchEndBridge = BridgeNet2.ReferenceBridge("MatchEnd"),
	EliminationChoicePromptBridge = BridgeNet2.ReferenceBridge("EliminationChoicePrompt"),
	EliminationChoiceResolvedBridge = BridgeNet2.ReferenceBridge("EliminationChoiceResolved"),
	EliminationChoiceRequestBridge = BridgeNet2.ReferenceBridge("EliminationChoiceRequest"),

	_roundReplica = nil,
	_lastStage = nil,
	_lastBombHolderUserId = nil,
	_explosionTimestamp = 0,
	_countdownEndsAt = 0,
	--
	_gameCleaner = Trove.new(),
	_passCleaner = Trove.new(),
	_musicStopCleaner = Trove.new(),
	_respawnCleaner = Trove.new(),

	_waitingDotsThread = nil :: thread?,
}

----------------------------------------------------------------
-- Replica accessors
----------------------------------------------------------------

function RoundController:GetReplica(timeout: number?)
	timeout = timeout or DEFAULT_TIMEOUT

	return Promise.new(function(resolve, reject)
		local expiresAt = os.clock() + timeout

		if not self._roundReplica then
			repeat
				task.wait()
			until self._roundReplica or os.clock() >= expiresAt

			if not self._roundReplica then
				reject("Timeout reached while waiting for round replica.")
				return
			end
		end

		resolve(self._roundReplica)
	end)
end

function RoundController:GetData(): { [string]: any }?
	local success, replica = self:GetReplica():await()
	if not success then
		return nil
	end

	return replica.Data
end

function RoundController:GetKey(key: string): any
	local data = self:GetData()
	if not data then
		return nil
	end

	return data[key]
end

----------------------------------------------------------------
-- Convenience accessors
----------------------------------------------------------------

function RoundController:GetCurrentStage(): string?
	return self:GetKey("CurrentStage")
end

function RoundController:GetBombHolderUserId(): number?
	return self:GetKey("BombHolderUserId")
end

function RoundController:HasBomb(): boolean
	local holderUserId = self:GetBombHolderUserId()
	return holderUserId == LocalPlayer.UserId
end

function RoundController:GetBomb(): Model?
	return self._bomb
end

-- Returns true if the local player is in the alive list (i.e. an active participant,
-- not someone who joined mid-game or was already eliminated).
function RoundController:IsInMatch(): boolean
	local data = self:GetData()
	if not data or not data.AlivePlayers then
		return false
	end
	for _, entry in data.AlivePlayers do
		if entry.UserId == LocalPlayer.UserId then
			return true
		end
	end
	return false
end

function RoundController:GetExplosionTimestamp(): number
	return self._explosionTimestamp
end

function RoundController:GetTimeUntilExplosion(): number
	if self._explosionTimestamp <= 0 then
		return 0
	end
	return math.max(0, self._explosionTimestamp - workspace:GetServerTimeNow())
end

function RoundController:RequestBombPass(direction: string)
	self.RequestBombPassBridge:Fire(direction)
end

-- Answer the elimination prompt with RESPAWN. Server will re-add you to the
-- alive list, unragdoll, lock movement, and re-circle everyone.
-- Server silently ignores this if you don't currently have an active prompt.
function RoundController:RequestRespawn()
	self.EliminationChoiceRequestBridge:Fire({ Choice = "Respawn" })
end

-- Answer the elimination prompt with LEAVE. Server will unragdoll, restore
-- movement, and teleport you to the lobby spawn as a spectator.
-- Server silently ignores this if you don't currently have an active prompt.
function RoundController:RequestLeave()
	self.EliminationChoiceRequestBridge:Fire({ Choice = "Leave" })
end

----------------------------------------------------------------
-- ↓↓↓ HOOKS — fill these in for your UI / VFX / SFX / camera ↓↓↓
----------------------------------------------------------------

function RoundController:ToggleGameControls(show: boolean)
	local ui = self.GameUI
	Spr.target(ui.Bottom, 0.7, 2.5, { Position = show and UDim2.fromScale(0.5, 0.72) or UDim2.fromScale(0.5, 1.1) })
end

function RoundController:TogglePassButtons(show: boolean)
	local buttons = self.GameUI.Bottom.Arrows
	buttons.Visible = show

	--
	self._passCleaner:Clean()

	if not show then
		return
	end

	-- Bind the buttons
	for _, v in buttons:GetChildren() do
		self._passCleaner:Add(UIController:BindButtonClick(v, function()
			self:RequestBombPass(v.Name)
		end, true))
	end
end

-- Called when the intermission stage begins.
-- Use for: showing intermission UI, fading match HUD, lobby music, etc.
function RoundController:OnIntermissionStart()
	--
	local ui = self.GameUI.Top
	local intermission = ui.Intermission
	local winnerFrame = ui.Winner

	--
	HudController:ShowHud()
	Spr.target(intermission, 0.7, 2.5, { Position = UDim2.fromScale(0.5, 0.325) })
	Spr.target(winnerFrame, 0.7, 2.5, { Position = UDim2.fromScale(0.5, -0.5) })
end

-- Called when the server is waiting for more players (countdown paused / not yet started).
-- Use for: showing "Waiting for players..." text, hiding the countdown label, etc.
function RoundController:OnIntermissionWaiting()
	--
	local ui = self.GameUI.Top
	local intermission = ui.Intermission
	local winnerFrame = ui.Winner

	--
	self._countdownEndsAt = 0
	Spr.target(intermission, 0.7, 2.5, { Position = UDim2.fromScale(0.5, 0.325) })
	Spr.target(winnerFrame, 0.7, 2.5, { Position = UDim2.fromScale(0.5, -0.5) })
	intermission.Countdown.Visible = false
	intermission.NotEnoughPlayersDescription.Visible = true

	-- Cancel any existing dots animation before starting a fresh one.
	self:_stopWaitingDots()

	self._waitingDotsThread = task.spawn(function()
		local suffixes = { ".", "..", "..." }
		local i = 0
		while true do
			i = (i % #suffixes) + 1
			intermission.Title.Text = "WAITING FOR PLAYERS" .. suffixes[i]
			task.wait(0.5)
		end
	end)
end

-- Called every second during the intermission countdown.
-- `secondsLeft` counts down from the duration to 0 (inclusive).
-- Use for: updating a countdown label, playing a tick SFX at 3-2-1, etc.
function RoundController:OnIntermissionCountdown(secondsLeft: string)
	--
	local ui = self.GameUI.Top
	local intermission = ui.Intermission

	-- Stop the dots animation now that a real countdown is running.
	self:_stopWaitingDots()

	--
	intermission.Countdown.Text = secondsLeft
	intermission.Countdown.Visible = true
	intermission.Title.Text = "GAME IS STARTING!"
	intermission.NotEnoughPlayersDescription.Visible = false

	-- Change countdown color when 3 seconds or fewer remain.
	local rawLeft = tonumber(secondsLeft) or 0
	if rawLeft <= 3 then
		intermission.Countdown.TextColor3 = Color3.fromRGB(255, 50, 50) -- urgent red
	else
		intermission.Countdown.TextColor3 = Color3.fromRGB(255, 255, 255) -- default white
	end
end

-- Called when InitMatch starts (you've just been spawned in the circle, but
-- the music timer hasn't started yet). Runs for BOTH players and spectators.
-- Use for: closing intermission UI, fade-in match HUD, camera framing, etc.
-- Player-only setup goes in OnEnterMatchAsPlayer; spectator-only setup goes in OnEnterMatchSpectator.
function RoundController:OnEnterMatchAll()
	-- Leaving intermission — ensure the dots animation is cleaned up.
	self:_stopWaitingDots()
	HudController:HideHud()

	local ui = self.GameUI

	local top = ui.Top
	local inGame = top.InGame
	local intermission = top.Intermission

	Spr.target(intermission, 0.7, 3, { Position = UDim2.fromScale(0.5, -0.25) })
	task.delay(3, function()
		Spr.target(inGame, 0.7, 2.5, { Position = UDim2.fromScale(0.5, 0.05) })
	end)

	SoundController:StartGameMusic(self:GetKey("MusicToPlay"))
	SoundController:SwitchBGM("Game", 3.5)
end

-- Called when InitMatch starts AND the local player is in the alive list.
-- Use for: ready-text animation, disabling default controls, showing the in-match HUD, etc.
function RoundController:OnEnterMatchAsPlayer()
	local ui = self.GameUI
	local middle = ui.Middle
	local readyText = middle.ReadyText
	local bottom = ui.Bottom

	readyText:AddTag("UISway")
	readyText.UIScale.Scale = 0

	Spr.target(readyText.UIScale, 0.45, 1.5, { Scale = 1 })
	readyText.Visible = true

	SoundController:PlaySound("StartRound")
	self._gameCleaner:Add(task.delay(3, function()
		Spr.target(readyText.UIScale, 0.5, 1.5, { Scale = 0 })
		readyText.UIScale.Scale = 0

		task.wait(1)
		readyText.Visible = false
		readyText:RemoveTag("UISway")
	end))

	-- Reset state if the match ends mid-animation.
	self._gameCleaner:Add(function()
		readyText:RemoveTag("UISway")
		readyText.UIScale.Scale = 0
		readyText.Visible = false
	end)

	Controls:Disable()
end

-- Called when InitMatch starts AND the local player is NOT in the alive list
-- (joined mid-game). Use for: spectator camera, "Watching" UI, free-cam controls, etc.
function RoundController:OnEnterMatchSpectator() end

-- Called when the Match stage actually starts (music timer is now ticking).
-- Use for: starting the music sound on the client, showing the bomb timer UI,
-- enabling pass buttons, etc.
function RoundController:OnMatchStart()
	local bomb = self._gameCleaner:Clone(Meshes.Bomb)
	bomb.Parent = workspace.Main
	self._bomb = bomb

	local player = Players:GetPlayerByUserId(self:GetBombHolderUserId())
	if player then
		self:OnBombPassed(player, true, nil)
	end

	if self:IsInMatch() then
		self:ToggleGameControls(true)
	end
end

-- Called when the timer expires and the server enters the PRE_ELIMINATION_GRACE window.
-- `victimInfo` is { UserId, Name, DisplayName } of the player about to be eliminated.
-- The actual elimination fires after GameConfigs.PRE_ELIMINATION_GRACE seconds.
-- Use for: explosion wind-up SFX, camera shake build-up, highlight the victim, etc.
function RoundController:OnPreElimination(victimInfo: { [string]: any }?)
	--
	local ui = self.GameUI
	local middle = ui.Middle
	local notification = middle.Notification

	local name = victimInfo and victimInfo.Name or "unknown"
	local player = Players:GetPlayerByUserId(victimInfo and victimInfo.UserId or 0)

	if not player then
		return
	end

	task.wait(1.5)

	local character = player.Character
	if not character or not character.Parent then
		return
	end

	local camera = workspace.CurrentCamera

	SoundController:PlaySound("OnEliminated")

	if self:IsInMatch() then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = character:GetPivot()
			* CFrame.new(0, 5, -15)
			* CFrame.Angles(0, math.rad(180), 0)
			* CFrame.Angles(math.rad(-15), 0, 0)

		local tween = TweenService:Create(camera, TweenInfo.new(5), { CFrame = camera.CFrame * CFrame.new(0, 0, -5) })
		tween:Play()

		self._gameCleaner:Add(function()
			if tween then
				tween:Cancel()
			end
		end)
	end

	--
	task.delay(1, function()
		local eliminatedNotificationText = notification.EliminatedNotification:Clone()
		eliminatedNotificationText.Title.UIScale.Scale = 0
		eliminatedNotificationText.Title.Text = `{name:upper()} HAS BEEN ELIMINATED!`
		eliminatedNotificationText.Visible = true
		eliminatedNotificationText.Parent = notification

		eliminatedNotificationText.Title:SetAttribute("Amplitude", 1)
		eliminatedNotificationText.Title:AddTag("UISway")

		Spr.target(eliminatedNotificationText.Title.UIScale, 0.7, 2.5, { Scale = 1 })

		task.delay(3, function()
			Spr.target(eliminatedNotificationText.Title.UIScale, 0.7, 2.5, { Scale = 0 })
			task.wait(3)
			eliminatedNotificationText:Destroy()
		end)
	end)
end

-- Called right after an elimination and before survivors are re-circled
-- (server is in the POST_ELIMINATION_GRACE window).
-- `remainingCount` is how many players are still alive.
-- The circle reset + new music cycle fires after GameConfigs.POST_ELIMINATION_GRACE seconds.
-- Use for: "X players remain" banner, arena reset animation, breath-of-air SFX, etc.
function RoundController:OnPostElimination(remainingCount: number)
	--
	local ui = self.GameUI
	local middle = ui.Middle
	local readyText = middle.ReadyText

	if not self:IsInMatch() then
		return
	end

	self._gameCleaner:Add(task.delay(4, function()
		readyText:AddTag("UISway")

		readyText.UIScale.Scale = 0

		Spr.target(readyText.UIScale, 0.45, 2, { Scale = 1 })
		readyText.Visible = true

		self._gameCleaner:Add(task.delay(2.8, function()
			Spr.target(readyText.UIScale, 0.5, 2, { Scale = 0 })
			readyText.UIScale.Scale = 0

			task.wait(1)
			readyText.Visible = false
			readyText:RemoveTag("UISway")
		end))
	end))

	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
end

-- Called whenever ANY player gets eliminated (including yourself).
-- `eliminatedInfo` is { UserId, Name, DisplayName }.
-- Use for: explosion VFX/SFX, screen shake, kill feed, particle effects, etc.
function RoundController:OnPlayerEliminated(elimatedInfo: { [string]: any }?, remainingCount: number)
	-- Only collapse the local player's match UI when THEY were the one eliminated.
	-- Otherwise other players' eliminations would hide the still-active HUD.
	if elimatedInfo and elimatedInfo.UserId == LocalPlayer.UserId then
		self._passCleaner:Clean()
		self._musicStopCleaner:Clean()
		HudController:HideHud()
		self:ToggleGameControls(false)
		self:TogglePassButtons(false)
		Controls:Enable()
		workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	end

	if self._bomb and self._bomb.Parent then
		self._bomb:PivotTo(workspace.Main.Arena.Main:GetPivot() * CFrame.new(0, 5, 0))
		self._bomb.Parent = nil
	end
end

-- Called for the LOCAL player ONLY when they've just been eliminated from a
-- match that had > 2 players before the elimination. Show your LEAVE / RESPAWN UI here.
-- `expirationTime` is the server timestamp when the prompt expires and the
-- server defaults the choice to LEAVE. Use `expirationTime - workspace:GetServerTimeNow()`
-- to drive a countdown on the buttons. The server's clock is
-- the source of truth — if your UI countdown drifts, the server will resolve on
-- its own and OnEliminationChoiceResolved will fire.
-- Use :RequestRespawn() / :RequestLeave() to send the answer.
function RoundController:OnEliminationChoicePrompt(expirationTime: number)
	--
	local ui = self.RespawnUI
	local holder = ui.Holder
	local buttons = holder.Buttons

	PlayerDataController:GetReplica():andThen(function(replica)
		local firstPurchaseOfTheDay = replica.Data.FirstPurchaseOfTheDay or {}
		local firstRespawnOfTheDay = firstPurchaseOfTheDay.Respawn

		buttons.Respawn.DiscountText.Visible = not firstRespawnOfTheDay or firstRespawnOfTheDay <= os.time()
	end)

	HudController:HideHud()
	UIController:OpenFrame(holder, true)

	self._respawnCleaner:Add(UIController:BindButtonClick(buttons.Respawn, function()
		self:RequestRespawn()
	end, true))

	self._respawnCleaner:Add(UIController:BindButtonClick(buttons.Leave, function()
		self:RequestLeave()
	end, true))

	local promptDuration = math.max(0, expirationTime - workspace:GetServerTimeNow())
	self._respawnCleaner:Add(task.spawn(function()
		while true do
			local timeLeft = math.max(0, expirationTime - workspace:GetServerTimeNow())
			local timerAlpha = if promptDuration > 0 then math.clamp(timeLeft / promptDuration, 0, 1) else 0

			if timeLeft <= 0 then
				break
			end

			holder.TimerBar.Bar.Size = UDim2.fromScale(timerAlpha, 1)
			task.wait()
		end
	end))
end

-- Called for the LOCAL player ONLY once the elimination prompt has been
-- resolved (they answered, the timer expired, or the match ended). Hide the
-- LEAVE / RESPAWN UI here. `choice` is "Respawn" or "Leave".
function RoundController:OnEliminationChoiceResolved(choice: string)
	--
	local ui = self.RespawnUI
	local holder = ui.Holder

	if choice == "Respawn" then
		HudController:HideHud()
		self:ToggleGameControls(true)
	else
		HudController:ShowHud()
	end

	UIController:CloseFrame(holder)
	self._respawnCleaner:Clean()
end

-- Called when YOU specifically just received the bomb.
-- Use for: vibrating UI, attaching bomb model client-side, scary SFX, panic
-- shader, showing the pass-direction buttons prominently, etc.
function RoundController:OnReceiveBomb()
	AnimationController:PlayAnimation("HoldBomb")
	self:TogglePassButtons(true)
end

-- Called when ANOTHER player (not you) just received the bomb.
-- `player` is the Player instance (nil if they've already left), `userId` is always present.
-- Use for: highlighting that player's character, playing a pass SFX, updating a
-- bomb-holder nameplate, animating the bomb flying to them, etc.
function RoundController:OnOtherPlayerReceiveBomb(_player: Player?, _userId: number)
	AnimationController:StopAnimation("HoldBomb")
	self:TogglePassButtons(false)
end

-- Called when the server sets a new explosion timer (the music cycle started
-- or resumed). Fires at match start AND after each post-elimination grace when
-- the server begins a new music cycle. `explosionTimestamp` is the absolute
-- server time when the bomb is scheduled to explode — use
-- `explosionTimestamp - workspace:GetServerTimeNow()` for the cycle duration.
-- Use for: starting/resuming music sound, showing the bomb timer UI, etc.
function RoundController:OnMusicStart(_explosionTimestamp: number)
	SoundController:ToggleGameMusic(true, 1)

	if self:IsInMatch() then
		self:ToggleGameControls(true)
	end
end

-- Called when the server clears the explosion timer (the music cycle stopped).
-- Fires on PreElimination, PostElimination, MatchEnd, or any other point where
-- the server stops the music. Use for: fading out music sound, stopping bomb
-- ticking SFX, hiding the bomb timer UI, etc.
function RoundController:OnMusicStop()
	local ui = self.GameUI
	local middle = ui.Middle
	local musicStoppedIcon = middle.MusicStopped

	SoundController:ToggleGameMusic(false, 0)
	SoundController:PlaySound("MusicStop")

	if not self:IsInMatch() then
		return
	end

	-- Tear down any in-flight effects from a previous music stop so threads,
	-- tweens, and the Lighting effect can't stack across cycles.
	self._musicStopCleaner:Clean()

	Spr.target(musicStoppedIcon.UIScale, 0.8, 3, { Scale = 1 })
	musicStoppedIcon:SetAttribute("Speed", 3)
	musicStoppedIcon:SetAttribute("Amplitude", 8)
	musicStoppedIcon:AddTag("UISway")

	self:TogglePassButtons(false)
	self:ToggleGameControls(false)

	-- Red Flash
	local colorCorrection = self._musicStopCleaner:Add(Instance.new("ColorCorrectionEffect"))
	colorCorrection.Parent = Lighting

	TweenService:Create(
		colorCorrection,
		TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, true),
		{ TintColor = Color3.fromRGB(255, 100, 100) }
	):Play()

	self._musicStopCleaner:Add(task.delay(6, function()
		colorCorrection:Destroy()
	end))

	-- Hide the music stopped icon
	self._musicStopCleaner:Add(task.delay(1.5, function()
		Spr.target(musicStoppedIcon.UIScale, 0.7, 2, { Scale = 0 })
		task.wait(3)

		musicStoppedIcon:RemoveTag("UISway")
		musicStoppedIcon.UIScale.Scale = 0
		musicStoppedIcon.Position = UDim2.fromScale(0.5, 0.5)
	end))

	-- Final reset — runs first on :Clean() (Trove unwinds in reverse), so the
	-- icon ends in a tidy state even if cleanup interrupts the animation
	-- mid-flight (round restart, local player elimination, etc.).
	self._musicStopCleaner:Add(function()
		musicStoppedIcon:RemoveTag("UISway")
		musicStoppedIcon.UIScale.Scale = 0
		musicStoppedIcon.Position = UDim2.fromScale(0.5, 0.5)
	end)
end

function RoundController:OnBombPassed(player: Player, skipAnim: boolean, fromPlayer: Player?)
	--
	local ui = self.GameUI.Top
	local inGame = ui.InGame

	local character = player.Character
	local upperTorso = character.UpperTorso
	local bomb = self._bomb

	TweenService:Create(
		inGame.Title.UIScale,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, true),
		{ Scale = 1 }
	):Play()

	if not bomb then
		return
	end

	bomb.Parent = workspace.Main

	if fromPlayer and fromPlayer.Character then
		SoundController:PlaySound(
			"OnPass",
			fromPlayer.Character:GetPivot(),
			{ PlaybackSpeed = Random.new():NextNumber(0.9, 1.1) }
		)
	end

	if not skipAnim then
		TweenService:Create(
			bomb,
			TweenInfo.new(0.5, Enum.EasingStyle.Quint),
			{ CFrame = upperTorso:GetPivot() * CFrame.new(0, 0, -2.4) * CFrame.Angles(math.rad(-90), 0, 0) }
		):Play()
	else
		bomb.CFrame = upperTorso:GetPivot() * CFrame.new(0, 0, -2.4) * CFrame.Angles(math.rad(-90), 0, 0)
	end

	if player == LocalPlayer then
		inGame.Title.Text = `<font color="#55ff00">YOU</font> ARE HOLDING THE <font color="#ff0000">BOMB!</font>`
	else
		inGame.Title.Text =
			`<font color="#55ff00">{player.Name:upper()}</font> IS HOLDING THE <font color="#ff0000">BOMB!</font>`
	end

	TweenService:Create(
		inGame.Title.UIScale,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, true),
		{ Scale = 1.1 }
	):Play()
end

-- Called when the server fires the MatchEnd event (the celebratory phase).
-- `winner` is { UserId, Name, DisplayName } or nil if no one survived.
-- `placements` is the ordered placements table from the server.
-- Use for: confetti VFX, fanfare music, winner podium UI, camera pan to winner, etc.
function RoundController:OnMatchEnd(winner: { [string]: any }?, _placements: { [number]: any })
	--
	local ui = self.GameUI
	local top = ui.Top
	local inGame = top.InGame
	local middle = ui.Middle
	local winnerFrame = top.Winner

	local winnerName = winner and winner.Name or "none"

	-- Reset game ui back to normal
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	Spr.target(inGame, 0.7, 2.5, { Position = UDim2.fromScale(0.5, -0.5) })
	inGame.Title.UIScale.Scale = 1
	middle.MusicStopped.UIScale.Scale = 0

	self:ToggleGameControls(false)
	HudController:HideHud()
	Controls:Enable()

	self._gameCleaner:Clean()
	self._passCleaner:Clean()
	self._musicStopCleaner:Clean()

	winnerFrame.Title.Text = `{winnerName:upper()} WON!`
	Spr.target(winnerFrame, 0.7, 2.5, { Position = UDim2.fromScale(0.5, 0.1) })

	SoundController:SwitchBGM("Background", 1.5)
	AnimationController:StopAnimation("HoldBomb")

	-- Reset per-match state so it doesn't bleed into the next match.
	-- _lastStage is intentionally left alone — it drives stage-change detection
	-- and the upcoming Intermission transition still needs the previous value.
	self._lastBombHolderUserId = nil
	self._explosionTimestamp = 0
	self._countdownEndsAt = 0
	self._bomb = nil
end

----------------------------------------------------------------
-- Internal: waiting dots animation
----------------------------------------------------------------

function RoundController:_stopWaitingDots()
	if self._waitingDotsThread then
		task.cancel(self._waitingDotsThread)
		self._waitingDotsThread = nil
	end
end

----------------------------------------------------------------
-- Internal: intermission countdown loop
----------------------------------------------------------------

function RoundController:_startIntermissionCountdown(endsAt: number)
	if endsAt <= 0 then
		return
	end

	-- Cancel any previously running countdown loop before starting a new one.
	self._countdownEndsAt = endsAt

	task.spawn(function()
		local myEndsAt = endsAt
		while self._lastStage == "Intermission" and self._countdownEndsAt == myEndsAt do
			local rawLeft = math.max(0, myEndsAt - workspace:GetServerTimeNow())
			local secondsLeft = string.format("%05.2f", rawLeft)
			self.OnIntermissionCountdownSignal:Fire(secondsLeft)
			self:OnIntermissionCountdown(secondsLeft)
			if rawLeft <= 0 then
				break
			end
			task.wait()
		end
	end)
end

----------------------------------------------------------------
-- Internal: dispatch hooks based on replica + bridge events
----------------------------------------------------------------

function RoundController:_fireEnterMatchHooks()
	-- Both: shared UI swap, dots cleanup, etc.
	self.OnEnterMatchAllSignal:Fire()
	self:OnEnterMatchAll()

	-- Branch: player vs. spectator.
	-- The server publishes CurrentStage="InitMatch" BEFORE AlivePlayers (each
	-- replica:Set is its own RemoteEvent fire), so on the very frame this hook
	-- runs from the CurrentStage OnChange, AlivePlayers may still be the old
	-- (empty) list — IsInMatch() would then incorrectly report spectator.
	-- task.defer waits until same-frame replica updates have all dispatched.
	task.defer(function()
		if self:IsInMatch() then
			self.OnEnterMatchAsPlayerSignal:Fire()
			self:OnEnterMatchAsPlayer()
		else
			self.OnEnterMatchSpectatorSignal:Fire()
			self:OnEnterMatchSpectator()
		end
	end)
end

function RoundController:_fireStageEntryHooks(newStage: string?, previousStage: string?)
	if newStage == "Intermission" then
		self.OnIntermissionStartedSignal:Fire()
		self:OnIntermissionStart()

		-- Immediately resolve the waiting/countdown state for the current
		-- IntermissionEndsAt value. Handles:
		--   1) Client joins mid-intermission (initial sync).
		--   2) IntermissionEndsAt was already 0 when the stage started, so
		--      the replica fires no OnChange and the waiting hook would never run.
		local endsAt = self._roundReplica and self._roundReplica.Data.IntermissionEndsAt or 0
		if endsAt and endsAt > 0 then
			self:_startIntermissionCountdown(endsAt)
		else
			self.OnIntermissionWaitingSignal:Fire()
			self:OnIntermissionWaiting()
		end
	elseif newStage == "InitMatch" then
		self._countdownEndsAt = 0
		self:_fireEnterMatchHooks()
	elseif newStage == "Match" then
		-- A late joiner who arrives directly in "Match" never saw "InitMatch",
		-- so the OnEnterMatchAll hook (which disables Controls and shows the game
		-- UI) would otherwise be skipped. Fire it here too so the client always
		-- has the in-match setup applied before OnMatchStart runs.
		if previousStage ~= "InitMatch" then
			self:_fireEnterMatchHooks()
		end
		self.OnMatchStartedSignal:Fire()
		self:OnMatchStart()
	end
end

function RoundController:_handleStageChange(newStage: string?)
	if newStage == self._lastStage then
		return
	end

	local previousStage = self._lastStage
	self._lastStage = newStage

	self:_fireStageEntryHooks(newStage, previousStage)
end

function RoundController:_handleBombHolderChange(newHolderUserId: number?)
	if not newHolderUserId then
		self._lastBombHolderUserId = nil
		self:TogglePassButtons(false)
		return
	end

	if newHolderUserId == self._lastBombHolderUserId then
		return
	end

	local previousHolderUserId = self._lastBombHolderUserId
	local holderPlayer = Players:GetPlayerByUserId(newHolderUserId)
	if not holderPlayer then
		self._lastBombHolderUserId = nil
		self:TogglePassButtons(false)
		return
	end
	self._lastBombHolderUserId = newHolderUserId
	local fromPlayer = previousHolderUserId and Players:GetPlayerByUserId(previousHolderUserId) or nil

	if newHolderUserId == LocalPlayer.UserId then
		self.OnReceiveBombSignal:Fire()
		self:OnReceiveBomb()
	elseif newHolderUserId then
		self.OnOtherPlayerReceiveBombSignal:Fire(holderPlayer, newHolderUserId)
		self:OnOtherPlayerReceiveBomb(holderPlayer, newHolderUserId)
	end

	self:OnBombPassed(holderPlayer, false, fromPlayer)
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function RoundController:OnInit()
	--
	UIController = require(script.Parent.UIController)
	SoundController = require(script.Parent.SoundController)
	HudController = require(script.Parent.HudController)
	AnimationController = require(script.Parent.AnimationController)
	PlayerDataController = require(script.Parent.PlayerDataController)

	--
	self.GameUI = PlayerGui:WaitForChild("GameUI")
	self.RespawnUI = PlayerGui:WaitForChild("RespawnUI")
	self.AbilitiesUI = PlayerGui:WaitForChild("AbilitiesUI")

	--
	Replica.OnNew("RoundData", function(replica)
		self._roundReplica = replica

		self.OnReplicaReady:Fire(replica)

		-- Initial sync (replica may already have data when we attach)
		self:_handleStageChange(replica.Data.CurrentStage)
		self:_handleBombHolderChange(replica.Data.BombHolderUserId)

		replica:OnChange(function(action, path, param1, param2)
			self.OnDataChanged:Fire(action, path, param1, param2, replica.Data)

			-- React to specific replicated keys
			local key = path and path[1]
			if key == "CurrentStage" then
				self:_handleStageChange(replica.Data.CurrentStage)
			elseif key == "BombHolderUserId" then
				self:_handleBombHolderChange(replica.Data.BombHolderUserId)
			elseif key == "IntermissionEndsAt" then
				local endsAt = replica.Data.IntermissionEndsAt or 0
				if self._lastStage == "Intermission" then
					if endsAt > 0 then
						self:_startIntermissionCountdown(endsAt)
					else
						self.OnIntermissionWaitingSignal:Fire()
						self:OnIntermissionWaiting()
					end
				end
			end
		end)
	end)

	--
	UIController:BindButtonClick(self.GameUI.Bottom.Abilities, function()
		UIController:OpenFrame(self.AbilitiesUI.Holder)
	end, true)
end

function RoundController:OnStart()
	-- Server-pushed bomb explosion timestamp
	self.SyncExplosionTimeBridge:Connect(function(payload: any)
		if typeof(payload) == "table" then
			local previousTimestamp = self._explosionTimestamp
			self._explosionTimestamp = payload.Timestamp or 0
			if self._explosionTimestamp > 0 then
				-- Only fire OnMusicStart on a real stopped → playing transition
				-- (mirrors the OnMusicStop guard below). This skips no-op resyncs
				-- where the server pushes the same/updated timestamp without an
				-- intervening clear.
				if previousTimestamp <= 0 then
					self.OnMusicStartSignal:Fire(self._explosionTimestamp)
					self:OnMusicStart(self._explosionTimestamp)
				end
			else
				-- Only fire OnMusicStop on a real playing → stopped transition.
				-- The server may push timestamp=0 at match start or after a previous
				-- stop, and we don't want to re-trigger the hook in those cases.
				if previousTimestamp > 0 and not payload.SuppressMusicStop then
					self.OnMusicStopSignal:Fire()
					self:OnMusicStop()
				end
			end
		end
	end)

	-- Bomb holder broadcast (used for clients who don't watch the replica)
	self.SyncBombHolderBridge:Connect(function(payload: any)
		if typeof(payload) == "table" then
			self:_handleBombHolderChange(payload.UserId)
		end
	end)

	-- Pre-elimination grace (server about to eliminate the victim)
	self.PreEliminationBridge:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		self.OnPreEliminationSignal:Fire(payload.Victim)
		self:OnPreElimination(payload.Victim)
	end)

	-- Player eliminated broadcast
	self.PlayerEliminatedBridge:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		self.OnPlayerEliminatedSignal:Fire(payload.Eliminated, payload.RemainingCount)
		self:OnPlayerEliminated(payload.Eliminated, payload.RemainingCount or 0)
	end)

	-- Post-elimination grace (circle about to reset)
	self.PostEliminationBridge:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		self.OnPostEliminationSignal:Fire(payload.RemainingCount)
		self:OnPostElimination(payload.RemainingCount or 0)
	end)

	-- Elimination choice prompt (server -> this player only)
	self.EliminationChoicePromptBridge:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local expirationTime = tonumber(payload.ExpirationTime)
		if not expirationTime then
			local duration = tonumber(payload.DurationSeconds) or 0
			expirationTime = workspace:GetServerTimeNow() + duration
		end
		self.OnEliminationChoicePromptSignal:Fire(expirationTime)
		self:OnEliminationChoicePrompt(expirationTime)
	end)

	-- Elimination choice resolved (server -> this player only)
	self.EliminationChoiceResolvedBridge:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local choice = payload.Choice or "Leave"
		self.OnEliminationChoiceResolvedSignal:Fire(choice)
		self:OnEliminationChoiceResolved(choice)
	end)

	-- Match end broadcast (winner + final placements)
	self.MatchEndBridge:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		self.OnMatchEndSignal:Fire(payload.Winner, payload.Placements)
		self:OnMatchEnd(payload.Winner, payload.Placements)
	end)
end

return RoundController
