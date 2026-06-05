--[[
	SkinManager

	Handles cosmetic skin ownership, equip state, and the rotating skin shop
	displays for both Bomb skins and Bat skins. Both shops are driven by a
	single global Clock so all servers show the same random skins for the
	configured interval, and both re-roll at the exact same time.

	Mirrors the AbilitiesManager currency purchase flow and uses Replicas
	(tokens "BombShop" / "BatShop") to broadcast the active shop roster to
	clients.
]]

-- Services
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Replica = require(Packages.Replica)

-- Shared
local Shared = ReplicatedStorage.Shared
local BombSkins = require(Shared.Config.BombSkins)
local BatSkins = require(Shared.Config.BatSkins)
local GuiUtil = require(Shared.GuiUtil)
local RandomUtil = require(Shared.RandomUtil)

-- Modules
local Modules = script.Parent.Parent.Modules
local Clock = require(Modules.Clock)

-- Config
local GameConfigs = require(script.Parent.RoundManager.GameConfigs)

--
local PlayerDataManager
local NotificationManager
local CurrencyManager
local ShopManager

--
local SkinManager = {
	PurchaseBombSkinEvent = BridgeNet2.ReferenceBridge("PurchaseBombSkin"),
	EquipBombSkinEvent = BridgeNet2.ReferenceBridge("EquipBombSkin"),
	UnequipBombSkinEvent = BridgeNet2.ReferenceBridge("UnequipBombSkin"),

	PurchaseBatSkinEvent = BridgeNet2.ReferenceBridge("PurchaseBatSkin"),
	EquipBatSkinEvent = BridgeNet2.ReferenceBridge("EquipBatSkin"),
	UnequipBatSkinEvent = BridgeNet2.ReferenceBridge("UnequipBatSkin"),
}

----------------------------------------------------------------
-- Skin type definitions
----------------------------------------------------------------

-- Generic per-type config so all the purchase/equip/shop logic stays shared.
local SKIN_TYPES = {
	Bomb = {
		Label = "Bomb",
		GetFromId = BombSkins.GetBombFromId,
		GetByRarity = BombSkins.GetBombsByRarity,
		GetRandomByAmount = BombSkins.GetRandomBombsByAmount,
		OwnedKey = "OwnedBombSkins",
		EquippedKey = "EquippedBombSkin",
		ReplicaToken = "BombShop",
		ReplicaDataKey = "Bombs",
		ShopAmount = GameConfigs.BOMB_SKIN_SHOP_AMOUNT,
		AnalyticsEvent = "Bomb Skin Purchased",
	},

	Bat = {
		Label = "Bat",
		GetFromId = BatSkins.GetBatFromId,
		GetByRarity = BatSkins.GetBatsByRarity,
		GetRandomByAmount = BatSkins.GetRandomBatsByAmount,
		OwnedKey = "OwnedBatSkins",
		EquippedKey = "EquippedBatSkin",
		ReplicaToken = "BatShop",
		ReplicaDataKey = "Bats",
		ShopAmount = GameConfigs.BAT_SKIN_SHOP_AMOUNT,
		AnalyticsEvent = "Bat Skin Purchased",
	},
}

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

local function notify(player: Player, text: string, notificationType: string?)
	NotificationManager.NotifyNormalEvent:Fire(player, { text, nil, notificationType })
end

local function applyEquippedAttribute(player: Player, attribute: string, skinId: string)
	if player and player:IsDescendantOf(Players) then
		player:SetAttribute(attribute, skinId)
	end
end

local function logCurrencySink(player: Player, skinId: string, price: number)
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
					skinId
				)
			end)
		end)
	end)
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

-- Purchases a skin for the specified player using in-game currency.
function SkinManager:PurchaseSkin(player: Player, skinType: string, id: string)
	local typeData = SKIN_TYPES[skinType]
	if not typeData then
		warn(`Invalid skin type: {skinType}`)
		return
	end

	local skinData = typeData.GetFromId(id)
	if not skinData then
		warn(`Invalid {typeData.Label} skin ID: {id}`)
		return
	end

	local hasData, ownedSkins = PlayerDataManager:GetPlayerDataKey(player, typeData.OwnedKey):await()
	if not hasData then
		return
	end

	if ownedSkins[id] then
		notify(player, `You already own the <font color="#ffd400">{skinData.Name}</font>`, "Reject")
		return
	end

	local canAfford, currencyNeeded = CurrencyManager:CanAfford(player, skinData.Price)
	if not canAfford then
		notify(
			player,
			`You need <font color="#ffd400">{currencyNeeded} Coins</font> more to purchase this {string.lower(typeData.Label)} skin`,
			"Reject"
		)
		ShopManager:PromptCurrencyPurchase(player, currencyNeeded)
		return
	end

	local newOwned = table.clone(ownedSkins)
	newOwned[id] = true
	PlayerDataManager:SetPlayerDataKey(player, typeData.OwnedKey, newOwned)
	CurrencyManager:DeductCurrency(player, skinData.Price)

	notify(player, `Successfully purchased <font color="#ffd400">{skinData.Name}</font>`, "CurrencyPurchase")

	AnalyticsService:LogCustomEvent(player, typeData.AnalyticsEvent, 1, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = skinData.Id,
	})

	logCurrencySink(player, skinData.Id, skinData.Price)
end

-- Equips a skin the player owns.
function SkinManager:EquipSkin(player: Player, skinType: string, id: string)
	local typeData = SKIN_TYPES[skinType]
	if not typeData then
		warn(`Invalid skin type: {skinType}`)
		return
	end

	local skinData = typeData.GetFromId(id)
	if not skinData then
		warn(`Invalid {typeData.Label} skin ID: {id}`)
		return
	end

	local hasEquipped, equippedSkin = PlayerDataManager:GetPlayerDataKey(player, typeData.EquippedKey):await()
	if not hasEquipped then
		return
	end

	if equippedSkin == id then
		notify(player, `<font color="#ffd400">{skinData.Name}</font> is already equipped!`, "Reject")
		return
	end

	local hasOwned, ownedSkins = PlayerDataManager:GetPlayerDataKey(player, typeData.OwnedKey):await()
	if not hasOwned then
		return
	end

	if not ownedSkins[id] then
		notify(
			player,
			`You do not own the <font color="#ffd400">{skinData.Name}</font> {string.lower(typeData.Label)} skin!`,
			"Reject"
		)
		return
	end

	PlayerDataManager:SetPlayerDataKey(player, typeData.EquippedKey, id)
	applyEquippedAttribute(player, typeData.EquippedKey, id)
	notify(player, `Equipped <font color="#ffd400">{skinData.Name}</font>`)
end

-- Unequips the current skin, falling back to "Default".
function SkinManager:UnequipSkin(player: Player, skinType: string)
	local typeData = SKIN_TYPES[skinType]
	if not typeData then
		warn(`Invalid skin type: {skinType}`)
		return
	end

	local hasEquipped, equippedSkin = PlayerDataManager:GetPlayerDataKey(player, typeData.EquippedKey):await()
	if not hasEquipped or equippedSkin == "Default" then
		return
	end

	PlayerDataManager:SetPlayerDataKey(player, typeData.EquippedKey, "Default")
	applyEquippedAttribute(player, typeData.EquippedKey, "Default")

	local skinData = typeData.GetFromId(equippedSkin)
	if not skinData then
		return
	end

	notify(player, `Unequipped <font color="#ffd400">{skinData.Name}</font>`)
end

-- Grants a specific skin to the player without charging them.
function SkinManager:GivePlayerSkin(player: Player, skinType: string, id: string)
	local typeData = SKIN_TYPES[skinType]
	if not typeData then
		warn(`Invalid skin type: {skinType}`)
		return
	end

	local skinData = typeData.GetFromId(id)
	if not skinData then
		warn(`Invalid {typeData.Label} skin ID: {id}`)
		return
	end

	PlayerDataManager:GetPlayerDataKey(player, typeData.OwnedKey):andThen(function(ownedSkins)
		if ownedSkins[id] then
			return
		end

		local newOwned = table.clone(ownedSkins)
		newOwned[id] = true
		PlayerDataManager:SetPlayerDataKey(player, typeData.OwnedKey, newOwned)
		notify(player, `Received <font color="#ffd400">{skinData.Name}</font>`)
	end)
end

-- Grants a random skin of the specified rarity; if the player already owns it
-- they get a small currency refund instead.
function SkinManager:GiveRandomRarity(player: Player, skinType: string, rarity: string)
	local typeData = SKIN_TYPES[skinType]
	if not typeData then
		warn(`Invalid skin type: {skinType}`)
		return
	end

	local skins = typeData.GetByRarity(rarity)
	if #skins == 0 then
		warn(`No {typeData.Label} skins found for rarity: {rarity}`)
		return
	end

	local randomSkin = skins[RandomUtil.GetRandomIntFromMinMax(1, #skins)]
	if not randomSkin then
		return
	end

	PlayerDataManager:GetPlayerDataKey(player, typeData.OwnedKey):andThen(function(ownedSkins)
		if ownedSkins[randomSkin.Id] then
			local refund = randomSkin.Price and math.floor(randomSkin.Price * 0.3) or 150
			CurrencyManager:IncrementCurrency(player, refund)
			notify(
				player,
				`You already own the <font color="#ffd400">{randomSkin.Name}</font>! You received <font color="#ffd400">{refund} Coins</font> as compensation!`
			)
			return
		end

		local newOwned = table.clone(ownedSkins)
		newOwned[randomSkin.Id] = true
		PlayerDataManager:SetPlayerDataKey(player, typeData.OwnedKey, newOwned)
		notify(player, `Received <font color="#ffd400">{randomSkin.Name}</font>`)
	end)
end

----------------------------------------------------------------
-- Internal
----------------------------------------------------------------

-- Sets the EquippedBombSkin / EquippedBatSkin attributes on the player from
-- their saved data so other clients (and RoundController) can read them without
-- subscribing to the player's replica.
function SkinManager:_setupPlayerAttribute(player: Player)
	PlayerDataManager:GetPlayerData(player)
		:andThen(function(playerData, replica)
			for _, typeData in SKIN_TYPES do
				applyEquippedAttribute(player, typeData.EquippedKey, playerData[typeData.EquippedKey] or "Default")
			end

			replica.Maid:Add(PlayerDataManager.OnDataChanged:Connect(function()
				for _, typeData in SKIN_TYPES do
					applyEquippedAttribute(
						player,
						typeData.EquippedKey,
						replica.Data[typeData.EquippedKey] or "Default"
					)
				end
			end))
		end)
		:catch(function(err)
			warn(`Failed to set up equipped skin attributes for {player.Name}: {err}`)
		end)
end

-- Creates both shop replicas and drives their synchronized re-rolls + the shared
-- countdown UI off a single global Clock.
function SkinManager:_setupShops()
	local replicas = {}
	for skinType, typeData in SKIN_TYPES do
		local replica = Replica.New({
			Token = Replica.Token(typeData.ReplicaToken),
			Data = {
				[typeData.ReplicaDataKey] = {},
			},
		})

		replica:Replicate()
		replicas[skinType] = replica
	end

	self._shopReplicas = replicas

	local function reroll(seed: number, broadcast: boolean)
		for skinType, typeData in SKIN_TYPES do
			local randomSkins = typeData.GetRandomByAmount(typeData.ShopAmount, seed)
			replicas[skinType]:Set({ typeData.ReplicaDataKey }, randomSkins)
		end

		if not broadcast then
			return
		end

		local lobbyPlayers = BridgeNet2.PlayersExcept(CollectionService:GetTagged("InGame"))
		local message = `The <font color="#ffd400">Skin Shop</font> has been updated with new bomb & bat skins!`
		NotificationManager.NotifyNormalEvent:Fire(lobbyPlayers, { message, 6 })
		NotificationManager.NotifyChatEvent:Fire(lobbyPlayers, message)
	end

	local clock = Clock.new(GameConfigs.SKIN_SHOP_INTERVAL)
	self._shopClock = clock

	reroll(clock.CurrentSeed, false)

	clock.Reached:Connect(function(seed: number)
		reroll(seed, true)
	end)

	-- Live countdown label inside workspace.Displays.Attachment.SkinTitleUI
	local displays = workspace:WaitForChild("Displays")
	local skinTitleUI = displays:FindFirstChild("SkinTitleUI", true)
	if not skinTitleUI then
		warn("Displays.SkinTitleUI not found; skipping live countdown")
		return
	end

	local timeLabel = skinTitleUI:FindFirstChild("Time")
	if not timeLabel then
		warn("Displays.SkinTitleUI.Time not found; skipping live countdown")
		return
	end

	clock.OnTimeChanged:Connect(function(timeLeft: number)
		timeLabel.Text = GuiUtil.ConvertSecondsToHHMMSS(timeLeft)
	end)
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function SkinManager:OnInit()
	PlayerDataManager = require(script.Parent.PlayerDataManager)
	NotificationManager = require(script.Parent.NotificationManager)
	CurrencyManager = require(script.Parent.CurrencyManager)
	ShopManager = require(script.Parent.ShopManager)
end

function SkinManager:OnStart()
	task.spawn(SkinManager._setupShops, self)

	self.PurchaseBombSkinEvent:Connect(function(player: Player, id: string)
		if type(id) == "string" then
			self:PurchaseSkin(player, "Bomb", id)
		end
	end)

	self.EquipBombSkinEvent:Connect(function(player: Player, id: string)
		if type(id) == "string" then
			self:EquipSkin(player, "Bomb", id)
		end
	end)

	self.UnequipBombSkinEvent:Connect(function(player: Player)
		self:UnequipSkin(player, "Bomb")
	end)

	self.PurchaseBatSkinEvent:Connect(function(player: Player, id: string)
		if type(id) == "string" then
			self:PurchaseSkin(player, "Bat", id)
		end
	end)

	self.EquipBatSkinEvent:Connect(function(player: Player, id: string)
		if type(id) == "string" then
			self:EquipSkin(player, "Bat", id)
		end
	end)

	self.UnequipBatSkinEvent:Connect(function(player: Player)
		self:UnequipSkin(player, "Bat")
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		self:_setupPlayerAttribute(player)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(SkinManager._setupPlayerAttribute, self, player)
	end
end

return SkinManager
