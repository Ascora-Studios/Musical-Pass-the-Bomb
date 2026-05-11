-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnalyticsService = game:GetService("AnalyticsService")
local ConfigService = game:GetService("ConfigService")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages
local ZonePlus = require(Packages.ZonePlus)

-- Shared
local Shared = ReplicatedStorage.Shared

local RandomUtil = require(Shared.RandomUtil)
local GuiUtil = require(Shared.GuiUtil)

-- Config
local FreeGiftConfig = require(script.Parent.Parent.Config.FreeGift)

--
local Obby = workspace.Obby

local GIFT_CLAIM_FREQUENCY = 3 * 60

--
local NotificationManager

--
local FreeGiftManager = {
	_claimTime = {},
	_playerClaims = {},
}

--
function FreeGiftManager:ClaimGift(player: Player)
	-- Check if the player can claim another gift
	local claimTime = self._claimTime[player]
	if workspace:GetServerTimeNow() < claimTime then
		NotificationManager.NotifyNormalEvent:Fire(player, {
			`You can claim another gift in <font color="#ffd400">{GuiUtil.ConvertSecondsToMMSS(
				claimTime - workspace:GetServerTimeNow()
			)}</font>`,
			5,
			"Reject",
		})
		return
	end

	-- Give the gift to the player
	local freeGiftChances = {}
	for index, gift in FreeGiftConfig do
		table.insert(freeGiftChances, { index, gift.Chance })
	end

	local randomGift: FreeGiftConfig.FreeGift = RandomUtil.GetResultFromWeight(freeGiftChances)
	local giftData = FreeGiftConfig[randomGift]

	giftData.Callback(player)

	-- Set the claim time for the player
	local newClaimTime = workspace:GetServerTimeNow() + player:GetAttribute("GiftWaitTime")
	self._claimTime[player] = newClaimTime
	player:SetAttribute("GiftClaimTime", newClaimTime)

	self._playerClaims[player] = (self._playerClaims[player] or 0) + 1

	--
	AnalyticsService:LogCustomEvent(player, "Claimed Free Gift", 1, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = giftData.Id,
		[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = tostring(self._playerClaims[player]),
	})
end

-- Setups the gift
function FreeGiftManager:_setupGift()
	-- Setup the zone for the gift
	local giftZone = ZonePlus.new(Obby.Hitbox)
	giftZone.playerEntered:Connect(function(player: Player)
		self:ClaimGift(player)
	end)

	-- Setup the time for player to claim the gift
	local function setupPlayer(player: Player)
		--local success, waitingTime = pcall(function()
		--	local playerConfig = ConfigService:GetConfigForPlayerAsync(player)
		--	return playerConfig:GetValue("FreeGiftTime")
		--end)

		--if success then
		--	waitingTime = waitingTime * 60
		--else
		--	waitingTime = GameConfigs.GIFT_CLAIM_FREQUENCY
		--end
		player:SetAttribute("GiftWaitTime", GIFT_CLAIM_FREQUENCY)

		local claimTime = workspace:GetServerTimeNow() + 10
		player:SetAttribute("GiftClaimTime", claimTime)
		self._claimTime[player] = claimTime
	end

	Players.PlayerAdded:Connect(function(player)
		setupPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._claimTime[player] = nil
		self._playerClaims[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
end

--
function FreeGiftManager:_setupObbyAntiFall()
	local obbyAntiFall = Obby.ObbyAntiFall
	local obbySpawnPoint = Obby.ObbySpawnPoint

	obbyAntiFall.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = Players:GetPlayerFromCharacter(character)

		if player then
			character:PivotTo(obbySpawnPoint.CFrame)
		end
	end)

	local water = workspace.Main.Water
	water.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = Players:GetPlayerFromCharacter(character)

		if player then
			character:PivotTo(workspace.Spawn.CFrame)
		end
	end)
end

function FreeGiftManager:OnInit()
	NotificationManager = require(script.Parent.Parent.Managers.NotificationManager)
end

function FreeGiftManager:OnStart()
	task.spawn(self._setupObbyAntiFall, self)
	task.spawn(self._setupGift, self)
end

return FreeGiftManager
