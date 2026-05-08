--[[
	GameConfigs

	Centralized, tweakable values for the round/match flow. Edit values here
	rather than in individual stage modules or RoundManager itself.
]]

local GameConfigs = {
	-- Match requirements
	MIN_PLAYERS_TO_START = 2,

	-- Stage durations (seconds)
	INTERMISSION_DURATION = 18, -- countdown once min players are present
	INIT_MATCH_PRE_STAGE_DELAY = 3, -- delay inside InitMatch stage before advancing to Match
	INIT_MATCH_COUNTDOWN = 3, -- "get ready" countdown after spawn, before music starts
	MATCH_END_CELEBRATION_DURATION = 6, -- celebration time after a winner is picked

	-- Elimination grace periods
	PRE_ELIMINATION_GRACE = 3, -- seconds between "timer expired" and the actual elimination call (for client effects)
	POST_ELIMINATION_GRACE = 4, -- seconds between elimination and re-circling / new music cycle (for client effects)
	POST_RESET_DELAY = 3, -- seconds between elimination and re-circling / new music cycle (for client effects)

	-- Elimination choice (LEAVE / RESPAWN prompt for the eliminated player)
	ELIMINATION_CHOICE_DURATION = 10, -- seconds the eliminated player has to choose; defaults to LEAVE on timeout
	ELIMINATION_CHOICE_MIN_REMAINING = 2, -- only prompt when the match had > 2 players before elim; otherwise auto-leave to lobby
	ELIMINATION_AUTO_LOBBY_DELAY = 3, -- ragdoll-on-screen delay before auto-returning to lobby when no prompt is shown
	FIRST_RESPAWN_PRODUCT_ID = "FirstRespawnOfTheDay", -- Products.Data id for the discounted first daily respawn developer product
	RESPAWN_PRODUCT_ID = "Respawn", -- Products.Data id for the paid respawn developer product

	-- Music / explosion timer
	MUSIC_DURATION_RANGE = NumberRange.new(5, 15), -- min/max song length (seconds)
	NUKE_TIMER_LOCK_DURATION = 600, -- keeps the normal bomb timer from expiring while the nuke effect plays
	NUKE_EFFECT_DELAY = 2, -- seconds between the nuke effect firing and the mass elimination

	-- Rewards
	PARTICIPATION_REWARD = 10, -- given to all survivors when someone is eliminated
	WINNER_REWARD = 200, -- given to last player standing

	-- Spawning (relative to workspace.Main.Arena.Main)
	SPAWN_HEIGHT_OFFSET = 2, -- studs above the arena top surface
	SPAWN_RADIUS_PADDING = -20, -- pulls spawn ring slightly inside the arena edge

	-- Player movement
	MATCH_WALKSPEED = 0, -- applied to all participants while the match is active
	MATCH_JUMPPOWER = 0,

	-- Bomb passing
	PASS_COOLDOWN = 0.1, -- seconds between accepted pass attempts
	VALID_PASS_DIRECTIONS = {
		Left = true,
		Right = true,
		Front = true,
	},
}

return GameConfigs
