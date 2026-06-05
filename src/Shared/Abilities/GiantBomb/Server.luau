local Config = require(script.Parent.Config)

local GiantBomb = {}

local round
local notify

local giantBombActive = false
local giantBombDamage = 0

local function indexOf(list: { Player }, player: Player): number?
	for i, p in list do
		if p == player then
			return i
		end
	end
	return nil
end

function GiantBomb.Setup(deps)
	round = deps.Round
	notify = deps.Notify

	-- Fired right before the bomb holder is eliminated. Blast the holder's two
	-- circle neighbours. Capture neighbours before any elimination so indices are
	-- valid; TakeDamage routes any lethal hit through the Humanoid.Died safety net.
	round:RegisterHook("HolderPreEliminate", function(holder: Player)
		if not giantBombActive then
			return
		end

		giantBombActive = false

		local damage = giantBombDamage
		local alive = round:GetAlivePlayers()
		local count = #alive
		if count <= 1 then
			return
		end

		local idx = indexOf(alive, holder)
		if not idx then
			return
		end

		-- The two players flanking the holder in the circle (deduped; a tiny circle
		-- can resolve both sides to the same player).
		local neighbors = {}
		neighbors[alive[idx == 1 and count or idx - 1]] = true
		neighbors[alive[idx == count and 1 or idx + 1]] = true
		neighbors[holder] = nil

		local targets = {}
		local neighborCount = 0
		for neighbor in neighbors do
			neighborCount += 1
			local humanoid = neighbor.Character and neighbor.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				table.insert(targets, humanoid)
			end
		end

		-- Players who are neither the holder nor flanking it always survive the
		-- blast. When there are none (a 2-3 player circle) and the blast would wipe
		-- everyone it can reach, spare one finalist at 1 HP so there's still a winner.
		local untouchedSurvivors = count - 1 - neighborCount
		if untouchedSurvivors <= 0 then
			local anySurvives = false
			for _, humanoid in targets do
				if humanoid.Health > damage then
					anySurvives = true
					break
				end
			end

			if not anySurvives and #targets > 0 then
				local spared = table.remove(targets, 1)
				spared.Health = 1
			end
		end

		for _, humanoid in targets do
			humanoid:TakeDamage(damage)
		end
	end)

	round:RegisterHook("MatchReset", function()
		giantBombActive = false
		giantBombDamage = 0
	end)
end

-- Arms the giant bomb: clients grow the bomb model, and the next time it
-- explodes (the holder is eliminated by the music timer) the two players
-- flanking the holder in the circle take a chunk of damage. Stays armed until
-- that explosion happens or the match ends.
function GiantBomb.Activate(player: Player): boolean
	if not round:IsPlayerInActiveMatch(player) then
		return false
	end

	local holder = round:GetBombHolder()
	if not holder or not round:IsPlayerAlive(holder) then
		notify(player, { "No one is holding the bomb right now.", 3, "Reject" })
		return false
	end

	if giantBombActive then
		notify(player, { "The bomb is already supersized.", 3, "Reject" })
		return false
	end

	giantBombActive = true
	giantBombDamage = Config.Damage

	return true
end

return GiantBomb
