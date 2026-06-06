-- Services
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

--
local PlayerDataManager

--
local CurrencyManager = {}

--
function CurrencyManager:IncrementCurrency(player: Player, amount: number?, ignoreBoosts: boolean?)
	amount = amount or 1

	if ignoreBoosts then
		return PlayerDataManager:IncrementDataKey(player, "Currency", amount)
	end

	--
	local addition = 0
	if player:HasTag("x2Coin") then
		addition += amount
	end

	if player:HasTag("VIP") then
		addition += math.round(amount * 0.25)
	end

	amount += addition
	PlayerDataManager:IncrementDataKey(player, "Currency", amount)
end

function CurrencyManager:DeductCurrency(player: Player, amount: number?)
	amount = amount or 1
	PlayerDataManager:DecrementDataKey(player, "Currency", amount)
end

function CurrencyManager:CanAfford(player: Player, amount: number): (boolean, number)
	local hasData, playerCurrency = PlayerDataManager:GetPlayerDataKey(player, "Currency"):await()
	if not hasData then
		return false
	end

	return playerCurrency >= amount, amount - playerCurrency
end

function CurrencyManager:OnInit()
	--
	PlayerDataManager = require(script.Parent.PlayerDataManager)
end

function CurrencyManager:OnStart()
	--[[-- TEMP: dev command for testing currency, e.g. "/givemoney 5000"
	local command = Instance.new("TextChatCommand")
	command.Name = "GiveMoneyCommand"
	command.PrimaryAlias = "/givemoney"
	command.Parent = TextChatService

	command.Triggered:Connect(function(textSource, message)
		local player = Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			return
		end

		local amount = tonumber(string.match(message, "(%-?%d+)")) or 1000
		self:IncrementCurrency(player, amount, true)
	end)]]
end

return CurrencyManager
