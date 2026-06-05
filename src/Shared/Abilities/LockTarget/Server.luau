local Players = game:GetService("Players")

local Config = require(script.Parent.Config)

local LockTarget = {}

local round
local notify
local allPlayers

local lockTarget: Player? = nil
local lockTargetExpiresAt = 0

local function clearLockTarget(shouldNotify: boolean)
	local target = lockTarget
	lockTarget = nil
	lockTargetExpiresAt = 0

	if shouldNotify and target then
		notify(allPlayers, `Lock Target on <font color="#ff0000">{target.Name}</font> is over`)
	end
end

function LockTarget.Setup(deps)
	round = deps.Round
	notify = deps.Notify
	allPlayers = deps.AllPlayers

	-- Override the pass target while a lock is active. Expired or now-invalid
	-- locks clear themselves here so a stale target can't be reused.
	round:RegisterHook("ResolvePassTarget", function(): Player?
		local target = lockTarget
		if not target then
			return nil
		end

		if workspace:GetServerTimeNow() >= lockTargetExpiresAt then
			clearLockTarget(true)
			return nil
		end

		if not round:IsMatchActive() or not target:IsDescendantOf(Players) or not round:IsPlayerAlive(target) then
			clearLockTarget(false)
			return nil
		end

		return target
	end)

	round:RegisterHook("MatchReset", function()
		clearLockTarget(false)
	end)

	round:RegisterHook("PlayerRemoved", function(player: Player)
		if lockTarget == player then
			clearLockTarget(false)
		end
	end)
end

function LockTarget.Activate(player: Player, context): boolean
	local target = context.SelectedPlayer
	if not target then
		return false
	end

	if not round:IsPlayerInActiveMatch(player) or not round:IsPlayerInActiveMatch(target) then
		return false
	end

	if player == target then
		notify(player, { "Select another player.", 3, "Reject" })
		return false
	end

	if round:ArePassesLocked() then
		notify(player, { "The bomb cannot be retargeted right now.", 3, "Reject" })
		return false
	end

	local lockDuration = type(Config.LockDuration) == "number" and Config.LockDuration > 0 and Config.LockDuration

	lockTarget = target
	lockTargetExpiresAt = workspace:GetServerTimeNow() + lockDuration
	local expiresAt = lockTargetExpiresAt

	notify(
		allPlayers,
		`The bomb will target <font color="#ff0000">{target.Name}</font> for <font color="#55ff00">{lockDuration}</font> seconds`
	)

	task.delay(lockDuration, function()
		if lockTarget == target and lockTargetExpiresAt == expiresAt then
			clearLockTarget(true)
		end
	end)

	return true
end

return LockTarget
