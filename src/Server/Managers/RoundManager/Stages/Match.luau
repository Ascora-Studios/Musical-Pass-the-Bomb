local Stage = {}

function Stage:OnStart(roundManager)
	roundManager:SetStageDisplayName("Match")
	roundManager:SetRoundActive(true)
	roundManager:SetStatus("Match Started", "Last player standing wins!")

	-- Run the full last-man-standing loop. Yields until 1 player remains
	-- (or everyone disconnects). When it returns, the stage advances.
	task.spawn(function()
		local success, err = xpcall(function()
			roundManager:RunMatchLoop()
		end, debug.traceback)
		if not success then
			warn(`[Match Stage] RunMatchLoop failed: {err}`)
		end

		roundManager:AdvanceStage("MatchEnd")
	end)
end

function Stage:OnEnd(roundManager)
	roundManager:SetRoundActive(false)
end

function Stage:ForceEnd(_roundManager) end

function Stage:GetCanEnd(_timeElapsed: number, _roundManager)
	return false -- driven manually via AdvanceStage from RunMatchLoop above
end

function Stage:GetNextStageName(_roundManager)
	return "MatchEnd"
end

return Stage
