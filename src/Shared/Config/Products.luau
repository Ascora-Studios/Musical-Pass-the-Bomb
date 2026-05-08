-- Services
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local AnalyticsService = game:GetService("AnalyticsService")

-- Managers
local CurrencyManager
local PlayerDataManager
local AbilitiesManager
local NotificationManager

if RunService:IsServer() then
	CurrencyManager = require(ServerScriptService.Server.Managers.CurrencyManager)
	PlayerDataManager = require(ServerScriptService.Server.Managers.PlayerDataManager)
	AbilitiesManager = require(ServerScriptService.Server.Managers.AbilitiesManager)
	NotificationManager = require(ServerScriptService.Server.Managers.NotificationManager)
end

-- Helper for analytics
local function logCurrencySource(player: Player, amount: number, productId: string)
	if RunService:IsClient() then
		return
	end
	task.spawn(function()
		pcall(function()
			PlayerDataManager:GetPlayerDataKey(player, "Currency"):andThen(function(currency)
				AnalyticsService:LogEconomyEvent(
					player,
					Enum.AnalyticsEconomyFlowType.Source,
					"Coins",
					amount,
					currency,
					Enum.AnalyticsEconomyTransactionType.IAP.Name,
					productId
				)
			end)
		end)
	end)
end

--
export type Product = {
	Id: string,
	Name: string,
	Type: "Core" | "Troll" | "Currency",
	Description: string,
	PurchaseOnce: boolean,
	Icon: string,
	ProductId: number,
	CurrencyPrice: number?,
	Value: number?, -- this is optional mostly used for reference how much X amount an X thing is
	Callback: (player: Player, toGift: Player?) -> ()?,
}

local Products = {}
Products.Data = {
	--
	{
		Id = "StarterPack",
		Name = "Starter Pack",
		Type = "Core",
		PurchaseOnce = true,
		ProductId = 3587570775,
		Callback = function(player: Player)
			if RunService:IsClient() then
				return
			end

			AbilitiesManager:AddPlayerAbility(player, "Shield")
			AbilitiesManager:AddPlayerAbility(player, "Reflect")
			CurrencyManager:IncrementCurrency(player, 500, true)

			NotificationManager.NotifyNormalEvent:Fire(player, {
				`You have received <font color="#ffd400">500 Coins</font>, <font color="#ffd400">Shield</font> and <font color="#ffd400">Reflect</font> abilities!`,
			})

			logCurrencySource(player, 500, "StarterPack")
		end,
	},

	--
	{
		Id = "Respawn",
		Name = "Respawn",
		Type = "Core",
		Description = "Respawn into the current match.",
		PurchaseOnce = false,
		ProductId = 3585144890,
	},

	{
		Id = "FirstRespawnOfTheDay",
		Name = "First Respawn of the Day",
		Type = "Core",
		PurchaseOnce = false,
		ProductId = 3587654323,
		Callback = function(player: Player)
			if RunService:IsClient() then
				return
			end

			PlayerDataManager:SetPlayerDataKey(player, { "FirstPurchaseOfTheDay", "Respawn" }, os.time() + 24 * 60 * 60)
		end,
	},

	------------ [[ Abilities ]] -------------
	{
		Id = "Nuke",
		Name = "Nuke",
		ProductId = 3585877108,
	},

	------------ [[ Currency ]] -------------
	{
		Id = "CoinPack1",
		Name = "Coin Pack 1",
		Type = "Currency",
		ProductId = 3587550616,
		Value = 500,
		Callback = function(player: Player)
			if RunService:IsClient() then
				return
			end

			CurrencyManager:IncrementCurrency(player, 500, true)
			logCurrencySource(player, 500, "CoinPack1")
		end,
	},

	{
		Id = "CoinPack2",
		Name = "Coin Pack 2",
		Type = "Currency",
		ProductId = 3587550674,
		Value = 1750,
		Callback = function(player: Player)
			if RunService:IsClient() then
				return
			end

			CurrencyManager:IncrementCurrency(player, 1750, true)
			logCurrencySource(player, 1750, "CoinPack2")
		end,
	},

	{
		Id = "CoinPack3",
		Name = "Coin Pack 3",
		Type = "Currency",
		ProductId = 3587550751,
		Value = 5000,
		Callback = function(player: Player)
			if RunService:IsClient() then
				return
			end

			CurrencyManager:IncrementCurrency(player, 5000, true)
			logCurrencySource(player, 5000, "CoinPack3")
		end,
	},

	{
		Id = "CoinPack4",
		Name = "Coin Pack 4",
		Type = "Currency",
		ProductId = 3587550820,
		Value = 15000,
		Callback = function(player: Player)
			if RunService:IsClient() then
				return
			end

			CurrencyManager:IncrementCurrency(player, 15000, true)
			logCurrencySource(player, 15000, "CoinPack4")
		end,
	},
}
table.freeze(Products.Data)

function Products.GetProductFromId(id: string): Product?
	for _, v in Products.Data do
		if v.Id == id then
			return v
		end
	end

	return nil
end

function Products.GetProductFromProductId(productId: number): Product?
	for _, v in Products.Data do
		if v.ProductId == productId then
			return v
		end
	end

	return nil
end

function Products.GetProductsByType(productType: "Core" | "Troll" | "Currency"): { Product }
	local products = {}
	for _, v in Products.Data do
		if v.Type == productType then
			table.insert(products, v)
		end
	end

	return products
end

function Products.GetProducts(): { Product }
	return Products.Data
end

return Products
