local Players = game:GetService("Players")

local GameConfigs = require(script.Parent.Parent.GameConfigs)
local AFKManager = require(script.Parent.Parent.Parent.AFKManager)

local Stage = {}

function Stage:OnStart(roundManager)
	roundManager:SetStageDisplayName("Intermission")
	roundManager:SetRoundActive(false)
	roundManager:PickRandomGameMusic()

	self._endsAt = 0

	local function startCountdown()
		if self._endsAt > 0 then
			return
		end

		local endsAt = workspace:GetServerTimeNow() + GameConfigs.INTERMISSION_DURATION
		self._endsAt = endsAt
		roundManager:SetStatus("Intermission", "Starting soon...")
		roundManager:SetIntermissionEndsAt(endsAt)
	end

	local function pauseCountdown()
		self._endsAt = 0
		roundManager:SetStatus("Intermission", "Waiting for players...")
		roundManager:SetIntermissionEndsAt(0)
	end

	local function refreshCountdown()
		if roundManager:HasEnoughPlayers() then
			startCountdown()
		else
			pauseCountdown()
		end
	end

	if roundManager._winningRig then
		roundManager._winningRig:Destroy()
		roundManager._winningRig = nil
	end

	refreshCountdown()

	-- Start the countdown when a player joins while we're still waiting.
	self._playerAddedConn = Players.PlayerAdded:Connect(function()
		refreshCountdown()
	end)

	self._playerRemovingConn = Players.PlayerRemoving:Connect(function(player: Player)
		local eligibleCount = #roundManager:GetEligiblePlayers()
		if not AFKManager:IsAFK(player) then
			eligibleCount -= 1
		end

		if eligibleCount < GameConfigs.MIN_PLAYERS_TO_START then
			pauseCountdown()
		end
	end)

	self._afkChangedConn = AFKManager.OnAFKChanged:Connect(function()
		refreshCountdown()
	end)
end

function Stage:OnEnd(roundManager)
	if self._playerAddedConn then
		self._playerAddedConn:Disconnect()
		self._playerAddedConn = nil
	end
	if self._playerRemovingConn then
		self._playerRemovingConn:Disconnect()
		self._playerRemovingConn = nil
	end
	if self._afkChangedConn then
		self._afkChangedConn:Disconnect()
		self._afkChangedConn = nil
	end
	self._endsAt = 0
	roundManager:SetIntermissionEndsAt(0)

	-- Lock in the match roster and pre-load characters BEFORE we transition
	-- to InitMatch. The next _runStage call will fire the CurrentStage replica
	-- update that triggers _fireEnterMatchHooks on clients; if we wait to
	-- publish AlivePlayers until inside StartMatch, the 5s character-load
	-- yield can drop the pruned list AFTER the client's task.defer'd
	-- OnEnterMatchAsPlayer check has already run.
	roundManager._alive = roundManager:GetEligiblePlayers()
	roundManager:_waitForAliveCharactersAndPrune()
	roundManager:_publishAliveList()
end

function Stage:ForceEnd(_roundManager) end

function Stage:GetCanEnd(_timeElapsed: number, roundManager)
	-- Block until the intermission timer AND minimum player count are satisfied.
	if not roundManager:HasEnoughPlayers() then
		return false
	end

	return self._endsAt > 0 and workspace:GetServerTimeNow() >= self._endsAt
end

function Stage:GetNextStageName(_roundManager)
	return "InitMatch"
end

return Stage
