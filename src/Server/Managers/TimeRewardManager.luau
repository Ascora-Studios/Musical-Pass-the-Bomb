-- Services
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)

-- Shared
local Shared = ReplicatedStorage.Shared
local TimeRewardsConfig

--
local NotificationManager
local PlayerDataManager

--
local JOIN_TIME_ATTRIBUTE = "JoinTime"
local CLAIMED_REWARDS_ATTRIBUTE = "ClaimedTimeRewards"
local TIME_REWARD_PLAYTIME_KEY = "TimeRewardPlaytime"
local TIME_REWARD_LAST_RESET_KEY = "TimeRewardLastReset"
local RESET_INTERVAL = 24 * 60 * 60

--
local TimeRewardManager = {
	ClaimRewardEvent = BridgeNet2.ReferenceBridge("ClaimTimeReward"),

	_joinTimes = {} :: { [Player]: number },
	_claimedRewards = {} :: { [Player]: { [string]: boolean } },
}

function TimeRewardManager:_getClaimedRewards(player: Player): { string }
	local claimedRewards = {}
	for claimedRewardId in self._claimedRewards[player] or {} do
		table.insert(claimedRewards, claimedRewardId)
	end
	table.sort(claimedRewards)

	return claimedRewards
end

function TimeRewardManager:_syncClaimedRewards(player: Player)
	if not player:IsDescendantOf(Players) then
		return
	end

	player:SetAttribute(CLAIMED_REWARDS_ATTRIBUTE, HttpService:JSONEncode(self:_getClaimedRewards(player)))
end

function TimeRewardManager:_setPlaytime(player: Player, playtime: number)
	local joinTime = workspace:GetServerTimeNow() - playtime
	self._joinTimes[player] = joinTime
	player:SetAttribute(JOIN_TIME_ATTRIBUTE, joinTime)
end

function TimeRewardManager:_resetRewards(player: Player)
	self._claimedRewards[player] = {}
	self:_setPlaytime(player, 0)
	self:_syncClaimedRewards(player)

	PlayerDataManager:SetPlayerDataKey(player, TIME_REWARD_PLAYTIME_KEY, 0)
	PlayerDataManager:SetPlayerDataKey(player, TIME_REWARD_LAST_RESET_KEY, os.time())
	PlayerDataManager:SetPlayerDataKey(player, CLAIMED_REWARDS_ATTRIBUTE, {})
end

function TimeRewardManager:_setupPlayer(player: Player)
	local hasData, playerData = PlayerDataManager:GetPlayerData(player):await()
	if not hasData or not player:IsDescendantOf(Players) then
		return
	end

	local lastReset = playerData.TimeRewardLastReset
	if type(lastReset) ~= "number" or lastReset <= 0 or os.time() - lastReset >= RESET_INTERVAL then
		self:_resetRewards(player)
	else
		local playtime = playerData.TimeRewardPlaytime
		if type(playtime) ~= "number" then
			playtime = 0
		end

		local claimedRewards = {}
		for _, rewardId in playerData.ClaimedTimeRewards or {} do
			if type(rewardId) == "string" then
				claimedRewards[rewardId] = true
			end
		end

		self._claimedRewards[player] = claimedRewards
		self:_setPlaytime(player, playtime)
		self:_syncClaimedRewards(player)
	end
end

function TimeRewardManager:AttemptClaimReward(player: Player, rewardId: string)
	if type(rewardId) ~= "string" or not player:IsDescendantOf(Players) then
		return
	end

	local rewardConfig = TimeRewardsConfig.GetRewardFromId(rewardId)
	if not rewardConfig then
		warn(`Time reward '{rewardId}' not found.`)
		return
	end

	local hasData, playerData = PlayerDataManager:GetPlayerData(player):await()
	if not hasData then
		return
	end

	local lastReset = playerData.TimeRewardLastReset
	if type(lastReset) ~= "number" or lastReset <= 0 or os.time() - lastReset >= RESET_INTERVAL then
		self:_resetRewards(player)
	end

	local joinTime = self._joinTimes[player]
	if not joinTime then
		return
	end

	if self._claimedRewards[player] and self._claimedRewards[player][rewardId] then
		NotificationManager.NotifyNormalEvent:Fire(player, { "You have already claimed this reward!", 3, "Reject" })
		return
	end

	if type(rewardConfig.Time) ~= "number" then
		warn(`Time reward '{rewardId}' does not have a valid Time value.`)
		return
	end

	local timeElapsed = workspace:GetServerTimeNow() - joinTime
	if timeElapsed < rewardConfig.Time then
		NotificationManager.NotifyNormalEvent:Fire(player, { `Come back later to claim this reward!`, 3, "Reject" })
		return
	end

	local onClaim = rewardConfig.OnClaim or rewardConfig.Callback
	if type(onClaim) ~= "function" then
		warn(`Time reward '{rewardId}' does not have a valid OnClaim callback.`)
		return
	end

	if not self._claimedRewards[player] then
		self._claimedRewards[player] = {}
	end
	self._claimedRewards[player][rewardId] = true

	local success, errorMessage = pcall(onClaim, player)
	if not success then
		self._claimedRewards[player][rewardId] = nil
		self:_syncClaimedRewards(player)
		warn(`Failed to claim time reward '{rewardId}' for {player.Name}: {errorMessage}`)
		return
	end

	self:_syncClaimedRewards(player)
	PlayerDataManager:SetPlayerDataKey(player, CLAIMED_REWARDS_ATTRIBUTE, self:_getClaimedRewards(player))
	PlayerDataManager:SetPlayerDataKey(player, TIME_REWARD_PLAYTIME_KEY, workspace:GetServerTimeNow() - joinTime)

	NotificationManager.NotifyNormalEvent:Fire(player, {
		`Successfully claimed <font color="#ffd400">{rewardConfig.Title or "time reward"}</font>!`,
		5,
		"CollectedReward",
	})
end

function TimeRewardManager:OnInit()
	NotificationManager = require(script.Parent.NotificationManager)
	PlayerDataManager = require(script.Parent.PlayerDataManager)
	TimeRewardsConfig = require(Shared.Config.TimeRewards)

	for _, player in Players:GetPlayers() do
		task.spawn(TimeRewardManager._setupPlayer, self, player)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		self:_setupPlayer(player)
	end)

	PlayerDataManager:BindForCleanup(function(player: Player)
		local joinTime = self._joinTimes[player]
		if not joinTime then
			return
		end

		PlayerDataManager:SetPlayerDataKey(player, TIME_REWARD_PLAYTIME_KEY, workspace:GetServerTimeNow() - joinTime)
		PlayerDataManager:SetPlayerDataKey(player, CLAIMED_REWARDS_ATTRIBUTE, self:_getClaimedRewards(player))
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self._joinTimes[player] = nil
		self._claimedRewards[player] = nil
	end)
end

function TimeRewardManager:OnStart()
	self.ClaimRewardEvent:Connect(function(player: Player, rewardId: string)
		self:AttemptClaimReward(player, rewardId)
	end)
end

return TimeRewardManager
