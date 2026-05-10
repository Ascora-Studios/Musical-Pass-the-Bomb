-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages

--
local PlayerDataManager = require(ServerScriptService.Server.Managers.PlayerDataManager)

--[[ 
	OnInitCallback: This function runs when the BadgeService is initialized.
	It is best to attach listeners in this function. (SHOULD ONLY BE CALLED ONCE!!!) 
--]]

--[[
	toAwardCallback: This function should be called when the condition for awarding
	the badge is met on your listener. It will give the badge to the player.
--]]

export type Badge = {
	Name: string,
	Key: string,
	BadgeId: number,
	OnInitCallback: (toAwardCallback: (player: Player, badgeKey: number, announce: boolean?) -> ()) -> (),
}

local Badges = {}

Badges.Data = {
	{
		Name = "Welcome",
		Key = "FirstJoin",
		BadgeId = 931604781514469,
		OnInitCallback = function(toAwardCallback: (player: Player, badgeKey: string) -> ())
			Players.PlayerAdded:Connect(function(player: Player)
				toAwardCallback(player, "FirstJoin")
			end)

			for _, player in Players:GetPlayers() do
				toAwardCallback(player, "FirstJoin")
			end
		end,
	},

	{
		Name = "1st Win",
		Key = "FirstWin",
		BadgeId = 3090271502708060,
		OnInitCallback = function(toAwardCallback: (player: Player, badgeKey: string) -> ())
			PlayerDataManager.OnDataChanged:Connect(function(player, key, newValue)
				if key == "Wins" and newValue == 1 then
					toAwardCallback(player, "FirstWin")
				end
			end)
		end,
	},

	{
		Name = "5th Win",
		Key = "FiveWins",
		BadgeId = 3260823466998087,
		OnInitCallback = function(toAwardCallback: (player: Player, badgeKey: string) -> ())
			PlayerDataManager.OnDataChanged:Connect(function(player, key, newValue)
				if key == "Wins" and newValue == 5 then
					toAwardCallback(player, "FiveWins")
				end
			end)
		end,
	},

	{
		Name = "Get 10 Wins",
		Key = "TenWins",
		BadgeId = 2390890035926874,
		OnInitCallback = function(toAwardCallback: (player: Player, badgeKey: string) -> ())
			PlayerDataManager.OnDataChanged:Connect(function(player, key, newValue)
				if key == "Wins" and newValue == 10 then
					toAwardCallback(player, "TenWins")
				end
			end)
		end,
	},
} :: { Badge }

function Badges.GetBadgeFromKey(key: string): Badge
	for _, v in Badges.Data do
		if v.Key == key then
			return v
		end
	end

	return nil
end

function Badges.GetBadges()
	return Badges.Data
end

return Badges
