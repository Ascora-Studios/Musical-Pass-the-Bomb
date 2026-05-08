-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Signal = require(Packages.Signal)

--
local RoundManager
local NotificationManager

--
local SELECTION_TIMEOUT = 15

--
local SelectPlayerManager = {
	RequestSelectPlayer = BridgeNet2.ReferenceBridge("RequestSelectPlayer"),
	SyncSelectedPlayer = BridgeNet2.ReferenceBridge("SyncSelectedPlayer"),

	OnSelectedPlayerChanged = Signal.new(),

	_selectedPlayers = {} :: {
		[Player]: {
			Target: Player,
			UpdatedAt: number,
		},
	},
}

----------------------------------------------------------------
-- Local Helpers
----------------------------------------------------------------

local function isValidPlayer(player: Player?): boolean
	return player ~= nil and player:IsDescendantOf(Players)
end

local function notify(player: Player, text: string)
	if NotificationManager then
		NotificationManager.NotifyNormalEvent:Fire(player, { text, 3, "Reject" })
	end
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

function SelectPlayerManager:SetSelectedPlayer(player: Player, targetPlayer: Player?): boolean
	if not isValidPlayer(player) then
		return false
	end

	if targetPlayer == nil then
		self:ClearSelectedPlayer(player)
		return true
	end

	if not isValidPlayer(targetPlayer) then
		notify(player, "That player is no longer available.")
		return false
	end

	if targetPlayer == player then
		notify(player, "Select another player.")
		return false
	end

	if RoundManager and not RoundManager:IsPlayerInActiveMatch(player) then
		notify(player, "You can only select a target while alive in a match.")
		return false
	end

	if RoundManager and not RoundManager:IsPlayerInActiveMatch(targetPlayer) then
		notify(player, "Select a player who is alive in the match.")
		return false
	end

	self._selectedPlayers[player] = {
		Target = targetPlayer,
		UpdatedAt = workspace:GetServerTimeNow(),
	}

	self.SyncSelectedPlayer:Fire(player, {
		UserId = targetPlayer.UserId,
	})

	self.OnSelectedPlayerChanged:Fire(player, targetPlayer)
	return true
end

function SelectPlayerManager:SetSelectedPlayerByUserId(player: Player, targetUserId: number?): boolean
	if targetUserId == nil then
		return self:SetSelectedPlayer(player, nil)
	end

	if type(targetUserId) ~= "number" then
		return false
	end

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		notify(player, "That player is no longer available.")
		return false
	end

	return self:SetSelectedPlayer(player, targetPlayer)
end

function SelectPlayerManager:GetSelectedPlayer(player: Player): Player?
	local selection = self._selectedPlayers[player]
	if not selection then
		return nil
	end

	local targetPlayer = selection.Target
	local isExpired = workspace:GetServerTimeNow() - selection.UpdatedAt > SELECTION_TIMEOUT
	if isExpired or not isValidPlayer(player) or not isValidPlayer(targetPlayer) then
		self:ClearSelectedPlayer(player)
		return nil
	end

	if RoundManager and (not RoundManager:IsPlayerInActiveMatch(player) or not RoundManager:IsPlayerInActiveMatch(targetPlayer)) then
		self:ClearSelectedPlayer(player)
		return nil
	end

	return targetPlayer
end

function SelectPlayerManager:ConsumeSelectedPlayer(player: Player): Player?
	local targetPlayer = self:GetSelectedPlayer(player)
	self:ClearSelectedPlayer(player)
	return targetPlayer
end

function SelectPlayerManager:ClearSelectedPlayer(player: Player)
	if not self._selectedPlayers[player] then
		return
	end

	self._selectedPlayers[player] = nil

	if isValidPlayer(player) then
		self.SyncSelectedPlayer:Fire(player, {
			UserId = nil,
		})
	end

	self.OnSelectedPlayerChanged:Fire(player, nil)
end

function SelectPlayerManager:ClearPlayerReferences(player: Player)
	self:ClearSelectedPlayer(player)

	local selectorsToClear = {}
	for selector, selection in self._selectedPlayers do
		if selection.Target == player then
			table.insert(selectorsToClear, selector)
		end
	end

	for _, selector in selectorsToClear do
		self:ClearSelectedPlayer(selector)
	end
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function SelectPlayerManager:OnInit()
	RoundManager = require(script.Parent.RoundManager)
	NotificationManager = require(script.Parent.NotificationManager)
end

function SelectPlayerManager:OnStart()
	self.RequestSelectPlayer:Connect(function(player: Player, targetUserId: number)
		self:SetSelectedPlayerByUserId(player, targetUserId)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:ClearPlayerReferences(player)
	end)

	if RoundManager then
		RoundManager.OnPlayerEliminated:Connect(function(player: Player)
			self:ClearPlayerReferences(player)
		end)

		RoundManager.OnMatchEnded:Connect(function()
			local selectors = {}
			for selector in self._selectedPlayers do
				table.insert(selectors, selector)
			end

			for _, selector in selectors do
				self:ClearSelectedPlayer(selector)
			end
		end)
	end
end

return SelectPlayerManager
