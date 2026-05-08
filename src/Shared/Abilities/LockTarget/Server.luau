return function(player: Player, _alivePlayers: { Player }, context: { [string]: any })
	local roundManager = context.RoundManager
	local selectedPlayer = context.SelectedPlayer
	if not roundManager or not roundManager.ActivateLockTarget or not selectedPlayer then
		return false
	end

	return roundManager:ActivateLockTarget(player, selectedPlayer, context.Config.LockDuration)
end
