local Config = require(script.Parent.Config)

local FireBomb = {}

local round
local notify

local fireBombActive = false

function FireBomb.Setup(deps)
	round = deps.Round
	notify = deps.Notify

	round:RegisterHook("MatchReset", function()
		fireBombActive = false
	end)
end

function FireBomb.Activate(player: Player): boolean
	if not round:IsPlayerInActiveMatch(player) then
		return false
	end

	local holder = round:GetBombHolder()
	if not holder or not round:IsPlayerAlive(holder) then
		notify(player, { "No one is holding the bomb right now.", 3, "Reject" })
		return false
	end

	if fireBombActive then
		notify(player, { "The bomb is already on fire.", 3, "Reject" })
		return false
	end

	fireBombActive = true

	-- Burn ticks against whoever is holding the bomb at that moment, so the fire
	-- effectively follows the bomb as it's passed around. A lethal tick routes
	-- through the Humanoid.Died binding -> _onPlayerDied, which handles
	-- elimination/placement/world reaction outside the timer loop.
	local damagePerTick = Config.DamagePerSecond
	task.spawn(function()
		for _ = 1, math.floor(Config.Duration / Config.Tick) do
			task.wait(Config.Tick)
			if not round:IsMatchActive() then
				break
			end

			local currentHolder = round:GetBombHolder()
			if not currentHolder or not round:IsPlayerAlive(currentHolder) then
				continue
			end

			local character = currentHolder.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid:TakeDamage(damagePerTick)
			end
		end

		fireBombActive = false
	end)

	return true
end

return FireBomb
