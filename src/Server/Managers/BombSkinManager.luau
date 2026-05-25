--[[
	BombSkinManager

	Handles bomb skin ownership, equip state, and the rotating bomb skin shop
	displays. The shop seeds itself from a global Clock so all servers show the
	same 8 random skins for the configured interval.

	Mirrors the AbilitiesManager currency purchase flow and uses a Replica
	(token "BombShop") to broadcast the active shop roster to clients.
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
local BombSkinManager = {
	PurchaseBombSkinEvent = BridgeNet2.ReferenceBridge("PurchaseBombSkin"),
	EquipBombSkinEvent = BridgeNet2.ReferenceBridge("EquipBombSkin"),
	UnequipBombSkinEvent = BridgeNet2.ReferenceBridge("UnequipBombSkin"),
}

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

local function notify(player: Player, text: string, notificationType: string?)
	NotificationManager.NotifyNormalEvent:Fire(player, { text, nil, notificationType })
end

local function applyEquippedAttribute(player: Player, skinId: string)
	if player and player:IsDescendantOf(Players) then
		player:SetAttribute("EquippedBombSkin", skinId)
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

-- Purchases a bomb skin for the specified player using in-game currency.
function BombSkinManager:PurchaseSkin(player: Player, id: string)
	local skinData = BombSkins.GetBombFromId(id)
	if not skinData then
		warn(`Invalid bomb skin ID: {id}`)
		return
	end

	local hasData, ownedSkins = PlayerDataManager:GetPlayerDataKey(player, "OwnedBombSkins"):await()
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
			`You need <font color="#ffd400">{currencyNeeded} Coins</font> more to purchase this bomb skin`,
			"Reject"
		)
		ShopManager:PromptCurrencyPurchase(player, currencyNeeded)
		return
	end

	local newOwned = table.clone(ownedSkins)
	newOwned[id] = true
	PlayerDataManager:SetPlayerDataKey(player, "OwnedBombSkins", newOwned)
	CurrencyManager:DeductCurrency(player, skinData.Price)

	notify(player, `Successfully purchased <font color="#ffd400">{skinData.Name}</font>`, "CurrencyPurchase")

	AnalyticsService:LogCustomEvent(player, "Bomb Skin Purchased", 1, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = skinData.Id,
	})

	logCurrencySink(player, skinData.Id, skinData.Price)
end

-- Equips a bomb skin the player owns.
function BombSkinManager:EquipSkin(player: Player, id: string)
	local skinData = BombSkins.GetBombFromId(id)
	if not skinData then
		warn(`Invalid bomb skin ID: {id}`)
		return
	end

	local hasEquipped, equippedSkin = PlayerDataManager:GetPlayerDataKey(player, "EquippedBombSkin"):await()
	if not hasEquipped then
		return
	end

	if equippedSkin == id then
		notify(player, `<font color="#ffd400">{skinData.Name}</font> is already equipped!`, "Reject")
		return
	end

	local hasOwned, ownedSkins = PlayerDataManager:GetPlayerDataKey(player, "OwnedBombSkins"):await()
	if not hasOwned then
		return
	end

	if not ownedSkins[id] then
		notify(player, `You do not own the <font color="#ffd400">{skinData.Name}</font> bomb skin!`, "Reject")
		return
	end

	PlayerDataManager:SetPlayerDataKey(player, "EquippedBombSkin", id)
	applyEquippedAttribute(player, id)
	notify(player, `Equipped <font color="#ffd400">{skinData.Name}</font>`)
end

-- Unequips the current bomb skin, falling back to "Default".
function BombSkinManager:UnequipSkin(player: Player)
	local hasEquipped, equippedSkin = PlayerDataManager:GetPlayerDataKey(player, "EquippedBombSkin"):await()
	if not hasEquipped or equippedSkin == "Default" then
		return
	end

	PlayerDataManager:SetPlayerDataKey(player, "EquippedBombSkin", "Default")
	applyEquippedAttribute(player, "Default")

	local skinData = BombSkins.GetBombFromId(equippedSkin)
	if not skinData then
		return
	end

	notify(player, `Unequipped <font color="#ffd400">{skinData.Name}</font>`)
end

-- Grants a specific bomb skin to the player without charging them.
function BombSkinManager:GivePlayerSkin(player: Player, id: string)
	local skinData = BombSkins.GetBombFromId(id)
	if not skinData then
		warn(`Invalid bomb skin ID: {id}`)
		return
	end

	PlayerDataManager:GetPlayerDataKey(player, "OwnedBombSkins"):andThen(function(ownedSkins)
		if ownedSkins[id] then
			return
		end

		local newOwned = table.clone(ownedSkins)
		newOwned[id] = true
		PlayerDataManager:SetPlayerDataKey(player, "OwnedBombSkins", newOwned)
		notify(player, `Received <font color="#ffd400">{skinData.Name}</font>`)
	end)
end

-- Grants a random skin of the specified rarity; if the player already owns it
-- they get a small currency refund instead.
function BombSkinManager:GiveRandomRarityBomb(player: Player, rarity: string)
	local skins = BombSkins.GetBombsByRarity(rarity)
	if #skins == 0 then
		warn(`No bomb skins found for rarity: {rarity}`)
		return
	end

	local randomSkin = skins[RandomUtil.GetRandomIntFromMinMax(1, #skins)]
	if not randomSkin then
		return
	end

	PlayerDataManager:GetPlayerDataKey(player, "OwnedBombSkins"):andThen(function(ownedSkins)
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
		PlayerDataManager:SetPlayerDataKey(player, "OwnedBombSkins", newOwned)
		notify(player, `Received <font color="#ffd400">{randomSkin.Name}</font>`)
	end)
end

----------------------------------------------------------------
-- Internal
----------------------------------------------------------------

-- Sets the EquippedBombSkin attribute on the player from their saved data so
-- other clients (and RoundController) can read it without subscribing to the
-- player's replica.
function BombSkinManager:_setupPlayerAttribute(player: Player)
	PlayerDataManager:GetPlayerData(player)
		:andThen(function(playerData, replica)
			applyEquippedAttribute(player, playerData.EquippedBombSkin or "Default")

			replica.Maid:Add(PlayerDataManager.OnDataChanged:Connect(function()
				applyEquippedAttribute(player, replica.Data.EquippedBombSkin or "Default")
			end))
		end)
		:catch(function(err)
			warn(`Failed to set up EquippedBombSkin attribute for {player.Name}: {err}`)
		end)
end

function BombSkinManager:_setupRandomBombs()
	local bombShopReplica = Replica.New({
		Token = Replica.Token("BombShop"),
		Data = {
			Bombs = {},
		},
	})

	bombShopReplica:Replicate()
	self._bombShopReplica = bombShopReplica

	local function changeBombs(seed: number, broadcast: boolean)
		local randomBombs = BombSkins.GetRandomBombsByAmount(GameConfigs.BOMB_SKIN_SHOP_AMOUNT, seed)
		bombShopReplica:Set({ "Bombs" }, randomBombs)

		if not broadcast then
			return
		end

		local lobbyPlayers = BridgeNet2.PlayersExcept(CollectionService:GetTagged("InGame"))
		NotificationManager.NotifyNormalEvent:Fire(lobbyPlayers, {
			`The <font color="#ffd400">Bomb Skin Shop</font> has been updated with new skins!`,
			6,
		})
		NotificationManager.NotifyChatEvent:Fire(
			lobbyPlayers,
			`The <font color="#ffd400">Bomb Skin Shop</font> has been updated with new skins!`
		)
	end

	local clock = Clock.new(GameConfigs.BOMB_SKIN_SHOP_INTERVAL)
	self._shopClock = clock

	changeBombs(clock.CurrentSeed, false)

	clock.Reached:Connect(function(seed: number)
		changeBombs(seed, true)
	end)

	-- Live countdown label inside workspace.BombDisplays.Attachment.SkinTitleUI
	local skinTitleUI = workspace:WaitForChild("BombDisplays"):FindFirstChild("SkinTitleUI", true)
	if not skinTitleUI then
		warn("BombDisplays.SkinTitleUI not found; skipping live countdown")
		return
	end

	local timeLabel = skinTitleUI:FindFirstChild("Time")
	if not timeLabel then
		warn("BombDisplays.SkinTitleUI.Time not found; skipping live countdown")
		return
	end

	clock.OnTimeChanged:Connect(function(timeLeft: number)
		timeLabel.Text = GuiUtil.ConvertSecondsToHHMMSS(timeLeft)
	end)
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function BombSkinManager:OnInit()
	PlayerDataManager = require(script.Parent.PlayerDataManager)
	NotificationManager = require(script.Parent.NotificationManager)
	CurrencyManager = require(script.Parent.CurrencyManager)
	ShopManager = require(script.Parent.ShopManager)
end

function BombSkinManager:OnStart()
	task.spawn(BombSkinManager._setupRandomBombs, self)

	self.PurchaseBombSkinEvent:Connect(function(player: Player, id: string)
		if type(id) == "string" then
			self:PurchaseSkin(player, id)
		end
	end)

	self.EquipBombSkinEvent:Connect(function(player: Player, id: string)
		if type(id) == "string" then
			self:EquipSkin(player, id)
		end
	end)

	self.UnequipBombSkinEvent:Connect(function(player: Player)
		self:UnequipSkin(player)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		self:_setupPlayerAttribute(player)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(BombSkinManager._setupPlayerAttribute, self, player)
	end
end

return BombSkinManager
