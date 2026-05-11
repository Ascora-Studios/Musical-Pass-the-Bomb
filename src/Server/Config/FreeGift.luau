-- Services
local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--
local Shared = ReplicatedStorage.Shared
local RandomUtil = require(Shared.RandomUtil)

-- Managers
local Managers = script.Parent.Parent.Managers

local PlayerDataManager = require(Managers.PlayerDataManager)
local NotificationManager = require(Managers.NotificationManager)
local CurrencyManager = require(Managers.CurrencyManager)

export type FreeGift = {
	Id: string,
	Chance: number,
	Callback: (player: Player) -> (),
}

--
return {
	{
		Id = "Coins",
		Chance = 100,
		Callback = function(player: Player)
			local randomAmount = RandomUtil.GetRandomIntFromMinMax(50, 80)

			CurrencyManager:IncrementCurrency(player, randomAmount)
			NotificationManager.NotifyNormalEvent:Fire(player, {
				`You received <font color="#ffd400">{randomAmount} Coins</font> from the free gift!`,
				5,
				"CollectedReward",
			})

			-- Analytics
			task.spawn(function()
				pcall(function()
					PlayerDataManager:GetPlayerDataKey(player, "Currency"):andThen(function(currency)
						AnalyticsService:LogEconomyEvent(
							player,
							Enum.AnalyticsEconomyFlowType.Source,
							"Coins",
							randomAmount,
							currency,
							Enum.AnalyticsEconomyTransactionType.TimedReward.Name,
							"FreeGift"
						)
					end)
				end)
			end)
		end,
	},
} :: { FreeGift }
