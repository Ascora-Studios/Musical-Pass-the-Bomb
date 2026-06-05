local Config = require(script.Parent.Config)

local Health = {}

local round
local notify

function Health.Setup(deps)
	round = deps.Round
	notify = deps.Notify
end

function Health.Activate(player: Player): boolean
	if not round:IsPlayerInActiveMatch(player) then
		return false
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	if humanoid.Health >= humanoid.MaxHealth then
		notify(player, { "You are already at full health.", 3, "Reject" })
		return false
	end

	humanoid.Health = math.min(humanoid.Health + Config.HealAmount, humanoid.MaxHealth)
	return true
end

return Health
