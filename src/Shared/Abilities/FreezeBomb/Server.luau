local Config = require(script.Parent.Config)

local FreezeBomb = {}

local round
local notify
local allPlayers

local frozenHolder: Player? = nil
local frozenExpiresAt = 0

local function clearFreeze()
	frozenHolder = nil
	frozenExpiresAt = 0
end

function FreezeBomb.Setup(deps)
	round = deps.Round
	notify = deps.Notify
	allPlayers = deps.AllPlayers

	-- Block the frozen holder from passing the bomb until the freeze expires, so
	-- the music timer can run out on them. Expired freezes clear themselves here.
	round:RegisterHook("PrePass", function(from: Player): boolean
		if from ~= frozenHolder then
			return false
		end

		if workspace:GetServerTimeNow() >= frozenExpiresAt then
			clearFreeze()
			return false
		end

		notify(from, { "The bomb is frozen to you!", 3, "Reject" })
		return true
	end)

	round:RegisterHook("MatchReset", clearFreeze)

	round:RegisterHook("PlayerRemoved", function(player: Player)
		if frozenHolder == player then
			clearFreeze()
		end
	end)
end

function FreezeBomb.Activate(player: Player): boolean
	if not round:IsPlayerInActiveMatch(player) then
		return false
	end

	local holder = round:GetBombHolder()
	if not holder or not round:IsPlayerAlive(holder) then
		notify(player, { "No one is holding the bomb right now.", 3, "Reject" })
		return false
	end

	if frozenHolder then
		notify(player, { "The bomb is already frozen.", 3, "Reject" })
		return false
	end

	frozenHolder = holder
	frozenExpiresAt = workspace:GetServerTimeNow() + Config.Duration

	notify(
		allPlayers,
		`The bomb is frozen to <font color="#ff0000">{holder.Name}</font> for <font color="#55ff00">{Config.Duration}</font> seconds`
	)

	task.delay(Config.Duration, function()
		if frozenHolder == holder then
			clearFreeze()
		end
	end)

	return true
end

return FreezeBomb
