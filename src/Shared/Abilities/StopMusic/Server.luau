local StopMusic = {}

local round
local notify

function StopMusic.Setup(deps)
	round = deps.Round
	notify = deps.Notify
end

function StopMusic.Activate(player: Player): boolean
	if not round:IsPlayerInActiveMatch(player) then
		return false
	end

	if not round:IsMusicPlaying() then
		notify(player, { "Music is not currently playing.", 3, "Reject" })
		return false
	end

	-- Snap the explosion to now so the current cycle ends immediately.
	round:SetExplosionTimestamp(workspace:GetServerTimeNow())
	return true
end

return StopMusic
