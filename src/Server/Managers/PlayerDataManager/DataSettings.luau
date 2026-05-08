return {
	PlayerDataTemplate = {
		-- Core Gameplay
		Wins = 0,
		Loses = 0,
		GamesPlayed = 0,
		Currency = 0,
		Abilities = {},

		-- Core Shop Stuff
		StarterPackStart = 0,
		PurchasedOnceProducts = {},
		FirstPurchaseOfTheDay = {},

		--
		ClaimedGroupReward = false,

		-- Daily Rewards
		DailyRewardStreak = 0,
		LastDailyRewardClaim = 0,
	},

	ToLeaderstats = {
		Currency = "Coins",
		Wins = "Wins",
	},
}
