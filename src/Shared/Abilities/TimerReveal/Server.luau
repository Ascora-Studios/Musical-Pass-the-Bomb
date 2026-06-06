local TimerReveal = {}

local round
local notify

local usedThisCycle = {}

function TimerReveal.Setup(deps)
	round = deps.Round
	notify = deps.Notify

	round:RegisterHook("MatchReset", function()
		table.clear(usedThisCycle)
	end)

	round:RegisterHook("PlayerRemoved", function(player: Player)
		usedThisCycle[player] = nil
	end)
end

function TimerReveal.Activate(player: Player): boolean
	if not round:IsPlayerInActiveMatch(player) then
		return false
	end

	if usedThisCycle[player] then
		notify(player, { "You already revealed the timer this round.", 3, "Reject" })
		return false
	end

	usedThisCycle[player] = true
	return true
end

return TimerReveal
