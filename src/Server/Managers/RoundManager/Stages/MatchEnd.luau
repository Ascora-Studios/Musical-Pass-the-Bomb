local Stage = {}

function Stage:OnStart(roundManager)
	roundManager:SetStageDisplayName("Match End")
	roundManager:SetRoundActive(false)
	roundManager:SetStatus("Round End", "Finalizing results...")

	-- Yields for celebration duration, awards winner, fires MatchEnd bridge.
	task.spawn(function()
		local success, err = xpcall(function()
			roundManager:FinalizeMatch()
		end, debug.traceback)
		if not success then
			warn(`[MatchEnd Stage] FinalizeMatch failed: {err}`)
		end

		roundManager:AdvanceStage("Intermission")
	end)
end

function Stage:OnEnd(_roundManager) end

function Stage:ForceEnd(_roundManager) end

function Stage:GetCanEnd(_timeElapsed: number, _roundManager)
	return false -- driven manually via AdvanceStage from FinalizeMatch above
end

function Stage:GetNextStageName(_roundManager)
	return "Intermission"
end

return Stage
