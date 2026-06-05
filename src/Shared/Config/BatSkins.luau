-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Assets
local Assets = ReplicatedStorage.Assets
local BatSkinAssets = Assets.BatSkins

-- Shared
local Shared = ReplicatedStorage.Shared
local RandomUtil = require(Shared.RandomUtil)

--
export type BatSkin = {
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

local BatSkins = {}
BatSkins.Data = {
	------------- [[ COMMON BATS ]] -------------
	{
		Id = "Default",
		Name = "Default",
		Rarity = "Common",
		Price = 0,
		Hide = true,
	},

	{
		Id = "BlueBat",
		Name = "Blue Bat",
		Rarity = "Common",
		Price = 200,
	},

	{
		Id = "GreenBat",
		Name = "Green Bat",
		Rarity = "Common",
		Price = 220,
	},

	{
		Id = "MagentaBat",
		Name = "Magenta Bat",
		Rarity = "Common",
		Price = 300,
	},

	{
		Id = "PinkBat",
		Name = "Pink Bat",
		Rarity = "Common",
		Price = 270,
	},

	{
		Id = "RedBat",
		Name = "Red Bat",
		Rarity = "Common",
		Price = 220,
	},

	{
		Id = "YellowBat",
		Name = "Yellow Bat",
		Rarity = "Common",
		Price = 240,
	},

	------------- [[ RARE BATS ]] -------------
	{
		Id = "AngryBat",
		Name = "Angry Bat",
		Rarity = "Rare",
		Price = 900,
	},

	{
		Id = "DonutBat",
		Name = "Donut Bat",
		Rarity = "Rare",
		Price = 1000,
	},

	{
		Id = "FireBat",
		Name = "Fire Bat",
		Rarity = "Rare",
		Price = 850,
	},

	{
		Id = "HazardBat",
		Name = "Hazard Bat",
		Rarity = "Rare",
		Price = 1100,
	},

	{
		Id = "HeartBat",
		Name = "Heart Bat",
		Rarity = "Rare",
		Price = 1150,
	},

	{
		Id = "LaughBat",
		Name = "Laugh Bat",
		Rarity = "Rare",
		Price = 750,
	},

	{
		Id = "LeafBat",
		Name = "Leaf Bat",
		Rarity = "Rare",
		Price = 1300,
	},

	------------- [[ EPIC BATS ]] -------------
	{
		Id = "AcidBat",
		Name = "Acid Bat",
		Rarity = "Epic",
		Price = 2400,
	},

	{
		Id = "BubbleGumBat",
		Name = "Bubble Gum Bat",
		Rarity = "Epic",
		Price = 2600,
	},

	{
		Id = "FrostBat",
		Name = "Frost Bat",
		Rarity = "Epic",
		Price = 2200,
	},

	{
		Id = "InfernoBat",
		Name = "Inferno Bat",
		Rarity = "Epic",
		Price = 3400,
	},

	{
		Id = "MintBat",
		Name = "Mint Bat",
		Rarity = "Epic",
		Price = 2800,
	},

	{
		Id = "ToxicBat",
		Name = "Toxic Bat",
		Rarity = "Epic",
		Price = 3000,
	},

	{
		Id = "VoidBat",
		Name = "Void Bat",
		Rarity = "Epic",
		Price = 3200,
	},

	------------- [[ LEGENDARY BATS ]] -------------
	{
		Id = "CosmicBat",
		Name = "Cosmic Bat",
		Rarity = "Legendary",
		Price = 7000,
	},

	{
		Id = "CursedBat",
		Name = "Cursed Bat",
		Rarity = "Legendary",
		Price = 6200,
	},

	{
		Id = "DivineBat",
		Name = "Divine Bat",
		Rarity = "Legendary",
		Price = 5500,
	},

	{
		Id = "InfernoKingBat",
		Name = "Inferno King Bat",
		Rarity = "Legendary",
		Price = 6500,
	},

	{
		Id = "NatureBat",
		Name = "Nature Bat",
		Rarity = "Legendary",
		Price = 5000,
	},

	{
		Id = "ShadowBat",
		Name = "Shadow Bat",
		Rarity = "Legendary",
		Price = 5800,
	},

	{
		Id = "StormBat",
		Name = "Storm Bat",
		Rarity = "Legendary",
		Price = 6000,
	},
} :: { BatSkin }

BatSkins.Priority = { --- Layout order
	Legendary = 1,
	Epic = 2,
	Rare = 3,
	Common = 4,
}

for _, batSkin in BatSkins.Data do
	local rarityFolder = BatSkinAssets:FindFirstChild(batSkin.Rarity)
	if not rarityFolder then
		warn("Bat skin rarity folder not found for rarity:", batSkin.Rarity)
		continue
	end

	local bat = rarityFolder:FindFirstChild(batSkin.Id)
	if not bat then
		warn("Bat skin model not found for ID:", batSkin.Id)
		continue
	end

	batSkin.Model = bat
end

table.freeze(BatSkins.Data)

-- Gets a bat skin by its configured id.
function BatSkins.GetBatFromId(id: string): BatSkin?
	for _, v in BatSkins.Data do
		if v.Id == id then
			return v
		end
	end

	return nil
end

-- Gets all visible bat skins in a rarity.
function BatSkins.GetBatsByRarity(rarity: string): { BatSkin }
	local bats = {}

	for _, v in BatSkins.Data do
		if v.Rarity == rarity and not v.Hide then
			table.insert(bats, v)
		end
	end

	return bats
end

-- Gets unique random bat skin ids using the configured rarity odds.
function BatSkins.GetRandomBatsByAmount(amount: number, seed: number): { string }
	local randomBats = {}
	local rng = Random.new(seed)
	local MAX_ATTEMPTS_PER_SLOT = 50

	for _ = 1, amount do
		local picked = false
		for _ = 1, MAX_ATTEMPTS_PER_SLOT do
			local rarity = RandomUtil.GetResultFromWeight(RARITY_ODDS, rng)
			local bats = BatSkins.GetBatsByRarity(rarity)

			if bats and #bats > 0 then
				local randomBat = bats[RandomUtil.GetRandomIntFromMinMax(1, #bats, rng)]
				if randomBat and not table.find(randomBats, randomBat.Id) then
					table.insert(randomBats, randomBat.Id)
					picked = true
					break
				end
			end
		end

		if not picked then
			for _, bat in BatSkins.Data do
				if not bat.Hide and not table.find(randomBats, bat.Id) then
					table.insert(randomBats, bat.Id)
					picked = true
					break
				end
			end

			if not picked then
				break
			end
		end
	end

	return randomBats
end

return BatSkins
