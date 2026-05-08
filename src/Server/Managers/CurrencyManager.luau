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

return CurrencyManager
