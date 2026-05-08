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

--
local JOIN_TIME_ATTRIBUTE = "JoinTime"
local CLAIMED_REWARDS_ATTRIBUTE = "ClaimedTimeRewards"

--
local TimeRewardManager = {
	ClaimRewardEvent = BridgeNet2.ReferenceBridge("ClaimTimeReward"),

	_joinTimes = {} :: { [Player]: number },
	_claimedRewards = {} :: { [Player]: { [string]: boolean } },
}

function TimeRewardManager:_syncClaimedRewards(player: Player)
	if not player:IsDescendantOf(Players) then
		return
	end

	local claimedRewards = {}
	for claimedRewardId in self._claimedRewards[player] or {} do
		table.insert(claimedRewards, claimedRewardId)
	end
	table.sort(claimedRewards)

	player:SetAttribute(CLAIMED_REWARDS_ATTRIBUTE, HttpService:JSONEncode(claimedRewards))
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
	NotificationManager.NotifyNormalEvent:Fire(player, {
		`Successfully claimed <font color="#ffd400">{rewardConfig.Title or "time reward"}</font>!`,
		5,
		"CollectedReward",
	})
end

function TimeRewardManager:OnInit()
	NotificationManager = require(script.Parent.NotificationManager)
	TimeRewardsConfig = require(Shared.Config.TimeRewards)

	for _, player in Players:GetPlayers() do
		local joinTime = workspace:GetServerTimeNow()
		player:SetAttribute(JOIN_TIME_ATTRIBUTE, joinTime)
		player:SetAttribute(CLAIMED_REWARDS_ATTRIBUTE, "[]")
		self._joinTimes[player] = joinTime
		self._claimedRewards[player] = {}
	end

	Players.PlayerAdded:Connect(function(player: Player)
		local joinTime = workspace:GetServerTimeNow()
		player:SetAttribute(JOIN_TIME_ATTRIBUTE, joinTime)
		player:SetAttribute(CLAIMED_REWARDS_ATTRIBUTE, "[]")
		self._joinTimes[player] = joinTime
		self._claimedRewards[player] = {}
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
