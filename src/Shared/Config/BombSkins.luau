-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Assets
local Assets = ReplicatedStorage.Assets
local BombSkinAssets = Assets.BombSkins

-- Shared
local Shared = ReplicatedStorage.Shared
local RandomUtil = require(Shared.RandomUtil)

--
export type BombSkin = {
	Id: string,
	Name: string,
	Model: Model,
	Price: number,
	Rarity: "Common" | "Rare" | "Epic" | "Legendary",
	Hide: boolean?,
}

local RARITY_ODDS = {
	{ "Common", 55 },
	{ "Rare", 30 },
	{ "Epic", 12 },
	{ "Legendary", 3 },
}

local BombSkins = {}
BombSkins.Data = {
	------------- [[ COMMON BOMBS ]] -------------
	{
		Id = "Blue",
		Name = "Blue",
		Rarity = "Common",
		Price = 200,
	},

	{
		Id = "Default",
		Name = "Default",
		Rarity = "Common",
		Price = 0,
		Hide = true,
	},

	{
		Id = "Green",
		Name = "Green",
		Rarity = "Common",
		Price = 220,
	},

	{
		Id = "Magenta",
		Name = "Magenta",
		Rarity = "Common",
		Price = 300,
	},

	{
		Id = "Pink",
		Name = "Pink",
		Rarity = "Common",
		Price = 270,
	},

	{
		Id = "Red",
		Name = "Red",
		Rarity = "Common",
		Price = 220,
	},

	{
		Id = "White",
		Name = "White",
		Rarity = "Common",
		Price = 250,
	},

	{
		Id = "Yellow",
		Name = "Yellow",
		Rarity = "Common",
		Price = 240,
	},

	------------- [[ RARE BOMBS ]] -------------
	{
		Id = "Acid",
		Name = "Acid",
		Rarity = "Rare",
		Price = 850,
	},

	{
		Id = "Diamond",
		Name = "Diamond",
		Rarity = "Rare",
		Price = 1300,
	},

	{
		Id = "Emerald",
		Name = "Emerald",
		Rarity = "Rare",
		Price = 1150,
	},

	{
		Id = "Radioactive",
		Name = "Radioactive",
		Rarity = "Rare",
		Price = 900,
	},

	{
		Id = "Ruby",
		Name = "Ruby",
		Rarity = "Rare",
		Price = 1100,
	},

	{
		Id = "Snow",
		Name = "Snow",
		Rarity = "Rare",
		Price = 750,
	},

	{
		Id = "Thunder",
		Name = "Thunder",
		Rarity = "Rare",
		Price = 1000,
	},

	------------- [[ EPIC BOMBS ]] -------------
	{
		Id = "BubbleGum",
		Name = "Bubble Gum",
		Rarity = "Epic",
		Price = 2400,
	},

	{
		Id = "Fiery",
		Name = "Fiery",
		Rarity = "Epic",
		Price = 3400,
	},

	{
		Id = "Mint",
		Name = "Mint",
		Rarity = "Epic",
		Price = 2200,
	},

	{
		Id = "Ocean",
		Name = "Ocean",
		Rarity = "Epic",
		Price = 2600,
	},

	{
		Id = "Shadow",
		Name = "Shadow",
		Rarity = "Epic",
		Price = 3200,
	},

	{
		Id = "Sunrise",
		Name = "Sunrise",
		Rarity = "Epic",
		Price = 2800,
	},

	{
		Id = "Toxic",
		Name = "Toxic",
		Rarity = "Epic",
		Price = 3000,
	},

	------------- [[ LEGENDARY BOMBS ]] -------------
	{
		Id = "Blazing",
		Name = "Blazing",
		Rarity = "Legendary",
		Price = 5500,
	},

	{
		Id = "Electric",
		Name = "Electric",
		Rarity = "Legendary",
		Price = 5000,
	},

	{
		Id = "Inferno",
		Name = "Inferno",
		Rarity = "Legendary",
		Price = 6200,
	},

	{
		Id = "RadiantMajesty",
		Name = "Radiant Majesty",
		Rarity = "Legendary",
		Price = 7000,
	},
} :: { BombSkin }

BombSkins.Priority = { --- Layout order
	Legendary = 1,
	Epic = 2,
	Rare = 3,
	Common = 4,
}

for _, bombSkin in BombSkins.Data do
	local rarityFolder = BombSkinAssets:FindFirstChild(bombSkin.Rarity)
	if not rarityFolder then
		warn("Bomb skin rarity folder not found for rarity:", bombSkin.Rarity)
		continue
	end

	local bomb = rarityFolder:FindFirstChild(bombSkin.Id)
	if not bomb then
		warn("Bomb skin model not found for ID:", bombSkin.Id)
		continue
	end

	bombSkin.Model = bomb
end

table.freeze(BombSkins.Data)

-- Gets a bomb skin by its configured id.
function BombSkins.GetBombFromId(id: string): BombSkin?
	for _, v in BombSkins.Data do
		if v.Id == id then
			return v
		end
	end

	return nil
end

-- Gets all visible bomb skins in a rarity.
function BombSkins.GetBombsByRarity(rarity: string): { BombSkin }
	local bombs = {}

	for _, v in BombSkins.Data do
		if v.Rarity == rarity and not v.Hide then
			table.insert(bombs, v)
		end
	end

	return bombs
end

-- Gets unique random bomb skin ids using the configured rarity odds.
function BombSkins.GetRandomBombsByAmount(amount: number, seed: number): { string }
	local randomBombs = {}
	local rng = Random.new(seed)
	local MAX_ATTEMPTS_PER_SLOT = 50

	for _ = 1, amount do
		local picked = false
		for _ = 1, MAX_ATTEMPTS_PER_SLOT do
			local rarity = RandomUtil.GetResultFromWeight(RARITY_ODDS, rng)
			local bombs = BombSkins.GetBombsByRarity(rarity)

			if bombs and #bombs > 0 then
				local randomBomb = bombs[RandomUtil.GetRandomIntFromMinMax(1, #bombs, rng)]
				if randomBomb and not table.find(randomBombs, randomBomb.Id) then
					table.insert(randomBombs, randomBomb.Id)
					picked = true
					break
				end
			end
		end

		if not picked then
			for _, bomb in BombSkins.Data do
				if not bomb.Hide and not table.find(randomBombs, bomb.Id) then
					table.insert(randomBombs, bomb.Id)
					picked = true
					break
				end
			end

			if not picked then
				break
			end
		end
	end

	return randomBombs
end

return BombSkins
