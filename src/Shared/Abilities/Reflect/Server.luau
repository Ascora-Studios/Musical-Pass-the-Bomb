return function(player: Player, _alivePlayers: { Player }, context: { [string]: any })
	local roundManager = context.RoundManager
	if not roundManager or not roundManager.ActivateReflect then
		return false
	end

	return roundManager:ActivateReflect(player)
end
