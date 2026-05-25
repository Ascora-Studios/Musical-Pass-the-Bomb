-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnalyticsService = game:GetService("AnalyticsService")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Signal = require(Packages.Signal)

-- Abilities
local AbilitiesModules = ReplicatedStorage.Shared.Abilities

--
local NotificationManager
local PlayerDataManager
local ShopManager
local CurrencyManager
local RoundManager
local SelectPlayerManager

local REQUEST_THROTTLE_SECONDS = 0.35
local REQUEST_THROTTLE_NOTIFY_SECONDS = 1.5
local DEFAULT_ABILITY_COOLDOWN_SECONDS = 3
local MIN_ABILITY_COOLDOWN_SECONDS = 1

--
local AbilitiesManager = {
	UseAbilityEvent = BridgeNet2.ReferenceBridge("UseAbility"),
	OnUseAbilityEvent = BridgeNet2.ReferenceBridge("OnUseAbility"),
	RequestAbilityPurchaseEvent = BridgeNet2.ReferenceBridge("RequestAbilityPurchase"),
	RequestPurchaseAbilityWithCurrencyEvent = BridgeNet2.ReferenceBridge("RequestPurchaseAbilityWithCurrency"),

	OnAbilityUsed = Signal.new(),

	_abilities = {},
	_cooldowns = {},
	_requestLocks = {},
	_requestTimestamps = {},
	_requestNotifyTimestamps = {},
}

----------------------------------------------------------------
-- Local Helpers
----------------------------------------------------------------

local function isValidPlayer(player: Player?): boolean
	return player ~= nil and player:IsDescendantOf(Players)
end

local function getAbilityName(ability: string, config: { [string]: any }): string
	return config.Name or ability
end

local function notify(playerOrPlayers: any, text: string, notificationType: string?)
	NotificationManager.NotifyNormalEvent:Fire(playerOrPlayers, {
		text,
		nil,
		notificationType,
	})
end

local function logCurrencySink(player: Player, ability: string, price: number)
	task.spawn(function()
		pcall(function()
			PlayerDataManager:GetPlayerDataKey(player, "Currency"):andThen(function(currency)
				AnalyticsService:LogEconomyEvent(
					player,
					Enum.AnalyticsEconomyFlowType.Sink,
					"Coins",
					price,
					currency,
					Enum.AnalyticsEconomyTransactionType.Shop.Name,
					ability
				)
			end)
		end)
	end)
end

local function getCooldownKey(player: Player, ability: string): string
	return `{player.UserId}_{ability}`
end

local function getCooldownLeft(cooldowns: { [string]: number }, player: Player, ability: string): number
	local cooldownEndsAt = cooldowns[getCooldownKey(player, ability)] or 0
	return math.max(0, cooldownEndsAt - workspace:GetServerTimeNow())
end

local function getAbilityCooldown(abilityConfig: { [string]: any }): number
	local cooldown = abilityConfig.Cooldown
	if type(cooldown) ~= "number" then
		return DEFAULT_ABILITY_COOLDOWN_SECONDS
	end

	return math.max(MIN_ABILITY_COOLDOWN_SECONDS, cooldown)
end

local function parseAbilityPayload(abilityPayload: any, selectedTargetPayload: any?): (string?, any?)
	if type(abilityPayload) == "string" then
		return abilityPayload, selectedTargetPayload
	end

	if type(abilityPayload) ~= "table" then
		return nil, selectedTargetPayload
	end

	return abilityPayload.Ability, selectedTargetPayload or abilityPayload.SelectedUserId
end

local function prepareSelectedPlayer(
	player: Player,
	abilityConfig: { [string]: any },
	selectedTargetPayload: any?
): boolean
	if not abilityConfig.SelectPlayer then
		return true
	end

	if selectedTargetPayload == nil then
		return true
	end

	return SelectPlayerManager:SetSelectedPlayerByUserId(player, selectedTargetPayload)
end

local function cleanupPlayerRequests(self, player: Player)
	self._requestLocks[player] = nil
	self._requestTimestamps[player] = nil
	self._requestNotifyTimestamps[player] = nil
end

local function cleanupPlayerCooldowns(self, player: Player)
	local playerPrefix = `{player.UserId}_`

	for key in self._cooldowns do
		if string.sub(key, 1, #playerPrefix) == playerPrefix then
			self._cooldowns[key] = nil
		end
	end
end

local function tryBeginPlayerRequest(self, player: Player): boolean
	if not isValidPlayer(player) then
		return false
	end

	if self._requestLocks[player] then
		return false
	end

	local now = workspace:GetServerTimeNow()
	local nextAllowedRequest = (self._requestTimestamps[player] or 0) + REQUEST_THROTTLE_SECONDS
	if now < nextAllowedRequest then
		local nextNotify = self._requestNotifyTimestamps[player] or 0
		if now >= nextNotify then
			self._requestNotifyTimestamps[player] = now + REQUEST_THROTTLE_NOTIFY_SECONDS
			notify(player, "Please wait a moment before using another ability.", "Reject")
		end

		return false
	end

	self._requestTimestamps[player] = now
	self._requestLocks[player] = true
	return true
end

local function finishPlayerRequest(self, player: Player)
	self._requestLocks[player] = nil
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

-- Adds owned uses to a player's ability inventory. This is used for shop
-- purchases outside the match and for Robux purchases that should stack.
function AbilitiesManager:AddPlayerAbility(player: Player, ability: string, amount: number?)
	if not isValidPlayer(player) then
		return
	end

	local hasData, playerData = PlayerDataManager:GetPlayerData(player):await()
	if not hasData then
		return
	end

	local abilities = playerData.Abilities or {}
	abilities[ability] = (abilities[ability] or 0) + (amount or 1)
	PlayerDataManager:SetPlayerDataKey(player, "Abilities", abilities)
end

-- Handles the client "use ability" request. If the player owns a use, it
-- spends one and runs in the active match; if they own none, it routes to the
-- configured currency or Robux purchase path.
function AbilitiesManager:UseAbility(player: Player, abilityPayload: any, selectedTargetPayload: any?)
	if not tryBeginPlayerRequest(self, player) then
		return
	end

	local ok, err = xpcall(function()
		local ability, parsedTargetPayload = parseAbilityPayload(abilityPayload, selectedTargetPayload)
		if type(ability) ~= "string" or not isValidPlayer(player) then
			return
		end

		local abilityEntry = self._abilities[ability]
		if not abilityEntry then
			warn(`Ability '{ability}' not found.`)
			return
		end

		local abilityConfig = abilityEntry.Config
		local hasData, playerData = PlayerDataManager:GetPlayerData(player):await()
		if not hasData then
			return
		end

		local abilities = playerData.Abilities or {}
		local ownedAmount = abilities[ability] or 0
		local isInActiveMatch = RoundManager:IsPlayerInActiveMatch(player)

		if isInActiveMatch then
			local cooldownLeft = getCooldownLeft(self._cooldowns, player, ability)
			if cooldownLeft > 0 then
				notify(
					player,
					`Wait <font color="#ff0000">{string.format("%.2f", cooldownLeft)}</font> seconds before using <font color="#55ff00">{getAbilityName(
						ability,
						abilityConfig
					)}</font> again!`,
					"Reject"
				)
				return
			end
		end

		if ownedAmount <= 0 then
			if abilityConfig.IsCurrencyPurchase then
				self:_purchaseAbilityWithCurrency(player, ability, isInActiveMatch, parsedTargetPayload)
			elseif abilityConfig.IsRobuxPurchase then
				if not prepareSelectedPlayer(player, abilityConfig, parsedTargetPayload) then
					return
				end

				ShopManager:AttemptProductPurchase(player, ability)
			else
				notify(
					player,
					`<font color="#ffd400">{getAbilityName(ability, abilityConfig)}</font> is not available for purchase.`,
					"Reject"
				)
			end
			return
		end

		if not isInActiveMatch then
			notify(player, "Abilities can only be used while you are alive in a match.", "Reject")
			return
		end

		if not prepareSelectedPlayer(player, abilityConfig, parsedTargetPayload) then
			return
		end

		if self:_runAbility(player, ability, abilityEntry) then
			abilities[ability] = math.max(0, ownedAmount - 1)
			PlayerDataManager:SetPlayerDataKey(player, "Abilities", abilities)
		end
	end, debug.traceback)

	finishPlayerRequest(self, player)

	if not ok then
		warn(`Failed to use ability: {err}`)
	end
end

-- Legacy-friendly helper for code paths that expect an immediate currency
-- purchase and use attempt.
function AbilitiesManager:PurchaseThenUseAbility(player: Player, ability: string, selectedTargetPayload: any?)
	if not tryBeginPlayerRequest(self, player) then
		return
	end

	local ok, err = xpcall(function()
		self:_purchaseAbilityWithCurrency(player, ability, true, selectedTargetPayload)
	end, debug.traceback)

	finishPlayerRequest(self, player)

	if not ok then
		warn(`Failed to purchase then use ability: {err}`)
	end
end

-- Purchases an ability with in-game currency. Active alive players auto-use
-- the purchase immediately; players outside the match receive one owned use.
function AbilitiesManager:PurchaseAbilityWithCurrency(player: Player, abilityPayload: any, selectedTargetPayload: any?)
	if not tryBeginPlayerRequest(self, player) then
		return
	end

	local ok, err = xpcall(function()
		local ability, parsedTargetPayload = parseAbilityPayload(abilityPayload, selectedTargetPayload)
		if type(ability) ~= "string" then
			return
		end

		self:_purchaseAbilityWithCurrency(
			player,
			ability,
			RoundManager:IsPlayerInActiveMatch(player),
			parsedTargetPayload
		)
	end, debug.traceback)

	finishPlayerRequest(self, player)

	if not ok then
		warn(`Failed to purchase ability with currency: {err}`)
	end
end

-- Client-facing adaptive purchase path. Outside an active match this buys and
-- stores a use; inside an active match it buys and immediately uses it.
function AbilitiesManager:PurchaseAbility(player: Player, abilityPayload: any, selectedTargetPayload: any?)
	if not tryBeginPlayerRequest(self, player) then
		return
	end

	local ok, err = xpcall(function()
		local ability, parsedTargetPayload = parseAbilityPayload(abilityPayload, selectedTargetPayload)
		if type(ability) ~= "string" or not isValidPlayer(player) then
			return
		end

		local abilityEntry = self._abilities[ability]
		if not abilityEntry then
			warn(`Ability '{ability}' not found.`)
			return
		end

		local abilityConfig = abilityEntry.Config
		if abilityConfig.IsCurrencyPurchase then
			self:_purchaseAbilityWithCurrency(
				player,
				ability,
				RoundManager:IsPlayerInActiveMatch(player),
				parsedTargetPayload
			)
		elseif abilityConfig.IsRobuxPurchase then
			if not prepareSelectedPlayer(player, abilityConfig, parsedTargetPayload) then
				return
			end

			ShopManager:AttemptProductPurchase(player, ability)
		else
			notify(
				player,
				`<font color="#ffd400">{getAbilityName(ability, abilityConfig)}</font> is not available for purchase.`,
				"Reject"
			)
		end
	end, debug.traceback)

	finishPlayerRequest(self, player)

	if not ok then
		warn(`Failed to purchase ability: {err}`)
	end
end

----------------------------------------------------------------
-- Internal Flow
----------------------------------------------------------------

function AbilitiesManager:_runAbility(player: Player, ability: string, abilityEntry: { [string]: any }): boolean
	if not RoundManager:IsPlayerInActiveMatch(player) then
		notify(player, "Abilities can only be used while you are alive in a match.", "Reject")
		return false
	end

	local alivePlayers = RoundManager:GetAlivePlayers()
	if #alivePlayers == 0 then
		return false
	end

	local abilityConfig = abilityEntry.Config
	local selectedPlayer = nil
	if abilityConfig.SelectPlayer then
		selectedPlayer = SelectPlayerManager:ConsumeSelectedPlayer(player)
		if not selectedPlayer then
			notify(player, "Select a target player first.", "Reject")
			return false
		end
	end

	local result = abilityEntry.Server(player, alivePlayers, {
		Ability = ability,
		Config = abilityConfig,
		RoundManager = RoundManager,
		SelectPlayerManager = SelectPlayerManager,
		SelectedPlayer = selectedPlayer,
	})
	if result == false then
		return false
	end

	local cooldown = getAbilityCooldown(abilityConfig)
	local cooldownEndsAt = workspace:GetServerTimeNow() + cooldown
	self._cooldowns[getCooldownKey(player, ability)] = cooldownEndsAt

	self.UseAbilityEvent:Fire(BridgeNet2.Players(alivePlayers), { ability, "Victim" })
	self.UseAbilityEvent:Fire(player, { ability, "Activator" })
	self.OnUseAbilityEvent:Fire(player, { ability, cooldownEndsAt })
	self.OnAbilityUsed:Fire(player, ability)

	notify(
		BridgeNet2.Players(alivePlayers),
		`<font color="#55ff00">{player.Name}</font> Used <font color="#ff0000">{getAbilityName(ability, abilityConfig)}</font>`
	)
	return true
end

function AbilitiesManager:_purchaseAbilityWithCurrency(
	player: Player,
	ability: string,
	shouldAutoUse: boolean,
	selectedTargetPayload: any?
): boolean
	if not isValidPlayer(player) then
		return false
	end

	local abilityEntry = self._abilities[ability]
	if not abilityEntry then
		warn(`Ability '{ability}' not found.`)
		return false
	end

	local abilityConfig = abilityEntry.Config
	if not abilityConfig.IsCurrencyPurchase then
		notify(
			player,
			`<font color="#ffd400">{getAbilityName(ability, abilityConfig)}</font> cannot be purchased with Coins.`,
			"Reject"
		)
		return false
	end

	local price = abilityConfig.Price
	if type(price) ~= "number" or price <= 0 then
		warn(`Ability '{ability}' has no valid currency price configured.`)
		return false
	end

	local canAfford, currencyNeeded = CurrencyManager:CanAfford(player, price)
	if not canAfford then
		currencyNeeded = currencyNeeded or price
		notify(
			player,
			`You need <font color="#2de200">{currencyNeeded} Coins</font> more to purchase <font color="#ffd400">{getAbilityName(
				ability,
				abilityConfig
			)}</font>`,
			"Reject"
		)
		ShopManager:PromptCurrencyPurchase(player, currencyNeeded)
		return false
	end

	if shouldAutoUse and RoundManager:IsPlayerInActiveMatch(player) then
		local cooldownLeft = getCooldownLeft(self._cooldowns, player, ability)
		if cooldownLeft > 0 then
			notify(
				player,
				`Wait <font color="#ff0000">{string.format("%.2f", cooldownLeft)}</font> seconds before using <font color="#55ff00">{getAbilityName(
					ability,
					abilityConfig
				)}</font> again!`,
				"Reject"
			)
			return false
		end

		if not prepareSelectedPlayer(player, abilityConfig, selectedTargetPayload) then
			return false
		end

		if not self:_runAbility(player, ability, abilityEntry) then
			return false
		end
	else
		self:AddPlayerAbility(player, ability)
		notify(
			player,
			`Successfully purchased <font color="#ffd400">{getAbilityName(ability, abilityConfig)}</font>`,
			"CurrencyPurchase"
		)
	end

	CurrencyManager:DeductCurrency(player, price)
	logCurrencySink(player, ability, price)
	return true
end

function AbilitiesManager:_handleRobuxAbilityPurchased(player: Player, ability: string)
	local abilityEntry = self._abilities[ability]
	if not abilityEntry or not abilityEntry.Config.IsRobuxPurchase then
		return
	end

	if RoundManager:IsPlayerInActiveMatch(player) then
		local cooldownLeft = getCooldownLeft(self._cooldowns, player, ability)
		if cooldownLeft <= 0 and self:_runAbility(player, ability, abilityEntry) then
			return
		end

		notify(
			player,
			`<font color="#ffd400">{getAbilityName(ability, abilityEntry.Config)}</font> was added to your inventory.`,
			"RobuxPurchase"
		)
		self:AddPlayerAbility(player, ability)
	else
		self:AddPlayerAbility(player, ability)
	end
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

-- Loads manager dependencies and discovers every ability module under
-- ReplicatedStorage.Shared.Abilities.
function AbilitiesManager:OnInit()
	NotificationManager = require(script.Parent.NotificationManager)
	PlayerDataManager = require(script.Parent.PlayerDataManager)
	ShopManager = require(script.Parent.ShopManager)
	CurrencyManager = require(script.Parent.CurrencyManager)
	RoundManager = require(script.Parent.RoundManager)
	SelectPlayerManager = require(script.Parent.SelectPlayerManager)

	for _, ability in AbilitiesModules:GetChildren() do
		self._abilities[ability.Name] = {
			Server = require(ability.Server),
			Config = require(ability.Config),
		}
	end
end

-- Connects client bridge requests and Robux purchase completion callbacks.
function AbilitiesManager:OnStart()
	self.UseAbilityEvent:Connect(function(player: Player, abilityPayload: any)
		self:UseAbility(player, abilityPayload)
	end)

	self.RequestAbilityPurchaseEvent:Connect(function(player: Player, abilityPayload: any)
		self:PurchaseAbility(player, abilityPayload)
	end)

	self.RequestPurchaseAbilityWithCurrencyEvent:Connect(function(player: Player, abilityPayload: any)
		self:PurchaseAbilityWithCurrency(player, abilityPayload)
	end)

	ShopManager.PlayerPurchased:Connect(function(player: Player, productId: string)
		self:_handleRobuxAbilityPurchased(player, productId)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		cleanupPlayerRequests(self, player)
		cleanupPlayerCooldowns(self, player)
	end)
end

return AbilitiesManager
