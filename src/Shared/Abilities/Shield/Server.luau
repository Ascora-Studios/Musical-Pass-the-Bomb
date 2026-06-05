local Shield = {}

local round
local notify
local allPlayers
local activeShields = {} :: { [Player]: boolean }

function Shield.Setup(deps)
	round = deps.Round
	notify = deps.Notify
	allPlayers = deps.AllPlayers

	-- Block the next pass aimed at a shielded player, then consume the shield.
	round:RegisterHook("PrePass", function(from: Player, target: Player): boolean
		if not activeShields[target] then
			return false
		end

		activeShields[target] = nil
		notify(
			allPlayers,
			`<font color="#55ff00">{target.Name}</font> blocked <font color="#ff0000">{from.Name}</font>'s pass`
		)
		return true
	end)

	round:RegisterHook("MatchReset", function()
		table.clear(activeShields)
	end)

	round:RegisterHook("PlayerRemoved", function(player: Player)
		activeShields[player] = nil
	end)
end

function Shield.Activate(player: Player): boolean
	if not round:IsPlayerInActiveMatch(player) then
		return false
	end

	if activeShields[player] then
		notify(player, { "Shield is already active.", 3, "Reject" })
		return false
	end

	activeShields[player] = true
	return true
end

return Shield
