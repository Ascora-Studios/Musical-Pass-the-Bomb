-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Signal = require(Packages.Signal)

--
local NotificationManager

--
local AFK_ATTRIBUTE = "IsAFK"
local REQUEST_COOLDOWN_SECONDS = 1.5

--
local AFKManager = {
	ToggleAFKEvent = BridgeNet2.ReferenceBridge("ToggleAFK"),
	OnAFKChanged = Signal.new(),

	_afkPlayers = {} :: { [Player]: boolean },
	_requestCooldowns = {} :: { [Player]: number },
}

function AFKManager:IsAFK(player: Player): boolean
	return self._afkPlayers[player] == true
end

function AFKManager:SetAFK(player: Player, isAFK: boolean)
	if typeof(isAFK) ~= "boolean" or not player:IsDescendantOf(Players) then
		return
	end

	local wasAFK = self._afkPlayers[player] == true
	self._afkPlayers[player] = isAFK
	player:SetAttribute(AFK_ATTRIBUTE, isAFK)

	if isAFK then
		NotificationManager.NotifyNormalEvent:Fire(player, { "You are now AFK, You won't join the next match!", 3 })
	else
		NotificationManager.NotifyNormalEvent:Fire(
			player,
			{ "You are no longer AFK, You will join the next match!", 3 }
		)
	end

	if wasAFK ~= isAFK then
		self.OnAFKChanged:Fire(player, isAFK)
	end
end

function AFKManager:ToggleAFK(player: Player)
	self:SetAFK(player, not self:IsAFK(player))
end

function AFKManager:OnInit()
	NotificationManager = require(script.Parent.NotificationManager)
end

function AFKManager:OnStart()
	for _, player in Players:GetPlayers() do
		self._afkPlayers[player] = false
		player:SetAttribute(AFK_ATTRIBUTE, false)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		self._afkPlayers[player] = false
		player:SetAttribute(AFK_ATTRIBUTE, false)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self._afkPlayers[player] = nil
		self._requestCooldowns[player] = nil
	end)

	self.ToggleAFKEvent:Connect(function(player: Player)
		local now = workspace:GetServerTimeNow()
		if now < (self._requestCooldowns[player] or 0) then
			return
		end

		self._requestCooldowns[player] = now + REQUEST_COOLDOWN_SECONDS
		self:ToggleAFK(player)
	end)
end

return AFKManager
