local Config = require(script.Parent.Config)

local Nuke = {}

local round
local notify
local runEffect

local nukeActive = false

function Nuke.Setup(deps)
	round = deps.Round
	notify = deps.Notify
	runEffect = deps.RunEffect

	round:RegisterHook("MatchReset", function()
		nukeActive = false
	end)
end

function Nuke.Activate(player: Player): boolean
	if not round:IsPlayerInActiveMatch(player) then
		return false
	end

	if not round:IsMusicPlaying() then
		notify(player, { "Nuke cannot be used right now.", 3, "Reject" })
		return false
	end

	if nukeActive then
		notify(player, { "A nuke is already active.", 3, "Reject" })
		return false
	end

	if #round:GetAlivePlayers() <= 1 then
		return false
	end

	nukeActive = true
	round:SetPassesLocked(true)
	-- Freeze the normal timer so it can't expire mid-effect, then replicate it.
	round:ForceMusicTimer(Config.TimerLockDuration)

	runEffect({ "Nuke" })

	task.delay(Config.EffectDelay, function()
		if not nukeActive then
			return
		end

		nukeActive = false

		if not round:IsMatchActive() then
			round:SetPassesLocked(false)
			return
		end

		if not round:IsPlayerAlive(player) then
			round:SetPassesLocked(false)
			return
		end

		local victims = {}
		for _, alivePlayer in round:GetAlivePlayers() do
			if alivePlayer ~= player then
				table.insert(victims, alivePlayer)
			end
		end

		for _, victim in victims do
			if round:IsPlayerAlive(victim) then
				round:Eliminate(victim, true)
			end
		end

		if #round:GetAlivePlayers() <= 1 then
			round:SetSuppressNextMusicStop(true)
		end

		round:SetPassesLocked(false)
	end)

	return true
end

return Nuke
