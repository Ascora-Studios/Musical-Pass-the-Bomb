-- Services
local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

--
local Abilities = ReplicatedStorage.Shared.Abilities

local ABILITY_ICONS = {
	LockTarget = require(Abilities.LockTarget.Config).Icon,
	Nuke = require(Abilities.Nuke.Config).Icon,
	Reflect = require(Abilities.Reflect.Config).Icon,
	Shield = require(Abilities.Shield.Config).Icon,
	StopMusic = require(Abilities.StopMusic.Config).Icon,
}

--
local AbilitiesManager
local CurrencyManager
local PlayerDataManager

if RunService:IsServer() then
	AbilitiesManager = require(ServerScriptService.Server.Managers.AbilitiesManager)
	CurrencyManager = require(ServerScriptService.Server.Managers.CurrencyManager)
	PlayerDataManager = require(ServerScriptService.Server.Managers.PlayerDataManager)
end

export type TimeReward = {
	Id: string,
	Title: string,
	Icon: string,
	Time: number, -- in seconds eg. 30 or  3 * 60
	Callback: (player: Player) -> (),
}

local COIN_ICON = "rbxassetid://82370054591244"

local function logCurrencySource(player: Player, amount: number, rewardId: string)
	task.spawn(function()
		pcall(function()
			PlayerDataManager:GetPlayerDataKey(player, "Currency"):andThen(function(currency)
				AnalyticsService:LogEconomyEvent(
					player,
					Enum.AnalyticsEconomyFlowType.Source,
					"Coins",
					amount,
					currency,
					Enum.AnalyticsEconomyTransactionType.TimedReward.Name,
					rewardId
				)
			end)
		end)
	end)
end

local function giveCurrency(player: Player, amount: number, rewardId: string)
	if RunService:IsClient() then
		return
	end

	CurrencyManager:IncrementCurrency(player, amount, true)
	logCurrencySource(player, amount, rewardId)
end

local function giveAbility(player: Player, ability: string, amount: number?)
	if RunService:IsClient() then
		return
	end

	AbilitiesManager:AddPlayerAbility(player, ability, amount)
end

local TimeRewards = {}
TimeRewards.Data = {
	{
		Id = "Gift1",
		Title = "25 Coins",
		Icon = COIN_ICON,
		Time = 30,
		Callback = function(player: Player)
			giveCurrency(player, 25, "Gift1")
		end,
	},
	{
		Id = "Gift2",
		Title = "50 Coins",
		Icon = COIN_ICON,
		Time = 90,
		Callback = function(player: Player)
			giveCurrency(player, 50, "Gift2")
		end,
	},
	{
		Id = "Gift3",
		Title = "100 Coins + Lock",
		Icon = ABILITY_ICONS.LockTarget,
		Time = 3 * 60,
		Callback = function(player: Player)
			giveCurrency(player, 100, "Gift3")
			giveAbility(player, "LockTarget")
		end,
	},
	{
		Id = "Gift4",
		Title = "150 Coins + Reflect",
		Icon = ABILITY_ICONS.Reflect,
		Time = 5 * 60,
		Callback = function(player: Player)
			giveCurrency(player, 150, "Gift4")
			giveAbility(player, "Reflect")
		end,
	},
	{
		Id = "Gift5",
		Title = "75 Coins",
		Icon = COIN_ICON,
		Time = 7 * 60,
		Callback = function(player: Player)
			giveCurrency(player, 75, "Gift5")
		end,
	},
	{
		Id = "Gift6",
		Title = "225 Coins + Shield",
		Icon = ABILITY_ICONS.Shield,
		Time = 10 * 60,
		Callback = function(player: Player)
			giveCurrency(player, 225, "Gift6")
			giveAbility(player, "Shield")
		end,
	},
	{
		Id = "Gift7",
		Title = "125 Coins",
		Icon = COIN_ICON,
		Time = 13 * 60,
		Callback = function(player: Player)
			giveCurrency(player, 125, "Gift7")
		end,
	},
	{
		Id = "Gift8",
		Title = "300 Coins + Stop Music",
		Icon = ABILITY_ICONS.StopMusic,
		Time = 16 * 60,
		Callback = function(player: Player)
			giveCurrency(player, 300, "Gift8")
			giveAbility(player, "StopMusic")
		end,
	},
	{
		Id = "Gift9",
		Title = "175 Coins",
		Icon = COIN_ICON,
		Time = 20 * 60,
		Callback = function(player: Player)
			giveCurrency(player, 175, "Gift9")
		end,
	},
	{
		Id = "Gift10",
		Title = "400 Coins + 2 Shields",
		Icon = ABILITY_ICONS.Shield,
		Time = 24 * 60,
		Callback = function(player: Player)
			giveCurrency(player, 400, "Gift10")
			giveAbility(player, "Shield", 2)
		end,
	},
	{
		Id = "Gift11",
		Title = "250 Coins",
		Icon = COIN_ICON,
		Time = 27 * 60,
		Callback = function(player: Player)
			giveCurrency(player, 250, "Gift11")
		end,
	},
	{
		Id = "Gift12",
		Title = "600 Coins + Nuke",
		Icon = ABILITY_ICONS.Nuke,
		Time = 30 * 60,
		Callback = function(player: Player)
			giveCurrency(player, 600, "Gift12")
			giveAbility(player, "Nuke")
		end,
	},
} :: { TimeReward }
table.freeze(TimeRewards.Data)

function TimeRewards.GetAllRewards(): { TimeReward }
	return TimeRewards.Data
end

function TimeRewards.GetRewardFromId(id: string): TimeReward?
	for _, reward in TimeRewards.Data do
		if reward.Id == id then
			return reward
		end
	end

	return nil
end

return TimeRewards
