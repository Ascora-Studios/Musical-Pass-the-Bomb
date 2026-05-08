local Players = game:GetService("Players")

local GameConfigs = require(script.Parent.Parent.GameConfigs)

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

	self._playerRemovingConn = Players.PlayerRemoving:Connect(function()
		if #Players:GetPlayers() - 1 < GameConfigs.MIN_PLAYERS_TO_START then
			pauseCountdown()
		end
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
	self._endsAt = 0
	roundManager:SetIntermissionEndsAt(0)
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
