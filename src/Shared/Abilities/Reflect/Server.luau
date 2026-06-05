local Reflect = {}

local round
local notify
local allPlayers
local activeReflects = {} :: { [Player]: boolean }

function Reflect.Setup(deps)
	round = deps.Round
	notify = deps.Notify
	allPlayers = deps.AllPlayers

	-- After a pass lands on a reflecting player, bounce the bomb back to the
	-- passer (if they're still alive) and consume the reflect.
	round:RegisterHook("PostPass", function(from: Player, target: Player): boolean
		if not activeReflects[target] then
			return false
		end

		if not round:IsPlayerAlive(from) then
			activeReflects[target] = nil
			return false
		end

		activeReflects[target] = nil

		task.wait(0.15)
		round:PassBomb(target, from, "Reflect")

		notify(
			allPlayers,
			`<font color="#55ff00">{target.Name}</font> reflected the bomb back to <font color="#ff0000">{from.Name}</font>`
		)
		return true
	end)

	round:RegisterHook("MatchReset", function()
		table.clear(activeReflects)
	end)

	round:RegisterHook("PlayerRemoved", function(player: Player)
		activeReflects[player] = nil
	end)
end

function Reflect.Activate(player: Player): boolean
	if not round:IsPlayerInActiveMatch(player) then
		return false
	end

	if activeReflects[player] then
		notify(player, { "Reflect is already active.", 3, "Reject" })
		return false
	end

	activeReflects[player] = true
	return true
end

return Reflect
