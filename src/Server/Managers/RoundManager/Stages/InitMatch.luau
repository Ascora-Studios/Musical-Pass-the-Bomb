local GameConfigs = require(script.Parent.Parent.GameConfigs)

local Stage = {}

function Stage:OnStart(roundManager)
	local roundNumber = roundManager:IncrementRoundNumber()

	roundManager:SetStageDisplayName("Init Match")
	roundManager:SetRoundActive(false)
	roundManager:ClearWinner()
	roundManager:SetStatus(`Round {roundNumber}`, "Get ready...")

	local started = roundManager:StartMatch()
	if not started then
		-- Not enough players, kick back to intermission.
		roundManager:AdvanceStage("Intermission")
	end
end

function Stage:OnEnd(_roundManager) end

function Stage:ForceEnd(_roundManager) end

function Stage:GetCanEnd(timeElapsed: number, _roundManager)
	-- Tiny delay so clients can react to spawning before the music starts.
	return timeElapsed >= GameConfigs.INIT_MATCH_PRE_STAGE_DELAY
end

function Stage:GetNextStageName(_roundManager)
	return "Match"
end

return Stage
