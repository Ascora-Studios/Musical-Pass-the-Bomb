return function(player: Player, _alivePlayers: { Player }, context: { [string]: any })
	local roundManager = context.RoundManager
	if not roundManager or not roundManager.ActivateNuke then
		return false
	end

	return roundManager:ActivateNuke(player)
end
