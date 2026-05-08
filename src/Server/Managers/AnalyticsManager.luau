-- Services
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

--
local RoundManager
local AbilitiesManager

--
local AnalyticsManager = {
	_sessions = {},
}

local function logCustomEvent(player: Player, eventName: string, value: number, customFields: { [string]: any }?)
	pcall(function()
		if customFields then
			AnalyticsService:LogCustomEvent(player, eventName, value, customFields)
		else
			AnalyticsService:LogCustomEvent(player, eventName, value)
		end
	end)
end

function AnalyticsManager:_trackPlayerJoined(player: Player)
	self._sessions[player] = {
		SessionRoundsPlayed = 0,
		JoinedDuringRoundAt = RoundManager:IsMatchActive() and workspace:GetServerTimeNow() or nil,
	}
end

function AnalyticsManager:_trackPlayerLeaving(player: Player)
	local session = self._sessions[player]
	if not session then
		return
	end

	logCustomEvent(player, "Rounds Played Before Leave", session.SessionRoundsPlayed or 0)

	if session.JoinedDuringRoundAt then
		local stayDuration = math.max(0, workspace:GetServerTimeNow() - session.JoinedDuringRoundAt)
		local playStatus = if (session.SessionRoundsPlayed or 0) > 0 then "Played Round" else "Left Before Playing"
		logCustomEvent(player, "Mid Round Join Stay Time", math.floor(stayDuration + 0.5), {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = playStatus,
		})
	end

	self._sessions[player] = nil
end

function AnalyticsManager:OnInit()
	RoundManager = require(script.Parent.RoundManager)
	AbilitiesManager = require(script.Parent.AbilitiesManager)
end

function AnalyticsManager:OnStart()
	for _, player in Players:GetPlayers() do
		self:_trackPlayerJoined(player)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		self:_trackPlayerJoined(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:_trackPlayerLeaving(player)
	end)

	RoundManager.OnMatchStarted:Connect(function(alivePlayers: { Player })
		for _, player in alivePlayers do
			local session = self._sessions[player]
			if not session then
				self:_trackPlayerJoined(player)
				session = self._sessions[player]
			end

			session.SessionRoundsPlayed += 1
		end
	end)

	AbilitiesManager.OnAbilityUsed:Connect(function(player: Player, ability: string)
		logCustomEvent(player, "Ability Used", 1, {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = ability,
		})
	end)
end

return AnalyticsManager
