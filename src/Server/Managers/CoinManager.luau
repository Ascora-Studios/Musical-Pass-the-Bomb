-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Replica = require(Packages.Replica)

-- Shared
local Shared = ReplicatedStorage.Shared
local RandomUtil = require(Shared.RandomUtil)

-- Modules
local Modules = script.Parent.Parent.Modules
local ServerRandom = require(Modules.ServerRandom)

-- Constants
local MAX_SPAWNED = 15
local RESPAWN_RANGE = NumberRange.new(2, 6)
local REWARD_RANGE = NumberRange.new(1, 3)
local COLLECT_RADIUS = 8
local COIN_FLOAT_OFFSET = 3

local COINS_TOKEN = Replica.Token("Coins")

--
local CurrencyManager

--
local CoinManager = {
	RequestCollectCoin = BridgeNet2.ReferenceBridge("RequestCollectCoin"),
	CoinCollected = BridgeNet2.ReferenceBridge("CoinCollected"),

	_values = {} :: { [string]: number },
	_replica = nil,
	_spawnParts = {} :: { BasePart },
}

local function getRootPart(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Get Spawn Part > Get Random Pos > Spawn
function CoinManager:_spawnCoin()
	if #self._spawnParts == 0 then
		return
	end

	local rng = ServerRandom.MakeRNG("Coin")

	local part = self._spawnParts[rng:NextInteger(1, #self._spawnParts)]
	local size = part.Size
	local offset = Vector3.new(
		rng:NextNumber(-size.X / 2, size.X / 2),
		COIN_FLOAT_OFFSET,
		rng:NextNumber(-size.Z / 2, size.Z / 2)
	)
	local position = (part.CFrame * CFrame.new(offset)).Position

	local id = HttpService:GenerateGUID(false)
	self._values[id] = rng:NextInteger(REWARD_RANGE.Min, REWARD_RANGE.Max)
	self._replica:Set({ "Coins", id }, { Position = position })
end

function CoinManager:_countCoins(): number
	local count = 0
	for _ in self._values do
		count += 1
	end
	return count
end

function CoinManager:_fillToMax()
	for _ = self:_countCoins() + 1, MAX_SPAWNED do
		self:_spawnCoin()
	end
end

function CoinManager:_handleCollect(player: Player, id: string)
	local coin = self._replica.Data.Coins[id]
	if not coin then
		return
	end

	local rootPart = getRootPart(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	if (rootPart.Position - coin.Position).Magnitude > COLLECT_RADIUS then
		return
	end

	CurrencyManager:IncrementCurrency(player, self._values[id])
	self.CoinCollected:Fire(BridgeNet2.AllPlayers(), { Id = id, CollectorUserId = player.UserId })

	self._values[id] = nil
	self._replica:Set({ "Coins", id }, nil)

	task.delay(
		RandomUtil.GetRandomFromMinMax(RESPAWN_RANGE.Min, RESPAWN_RANGE.Max),
		function()
			self:_spawnCoin()
		end
	)
end

function CoinManager:OnInit()
	CurrencyManager = require(script.Parent.CurrencyManager)
end

function CoinManager:OnStart()
	local spawner = workspace:WaitForChild("CoinSpawner")
	for _, part in spawner:GetChildren() do
		if part:IsA("BasePart") then
			table.insert(self._spawnParts, part)
		end
	end

	self._replica = Replica.New({
		Token = COINS_TOKEN,
		Data = { Coins = {} },
	})
	self._replica:Replicate()

	self.RequestCollectCoin:Connect(function(player: Player, payload: any)
		local id = typeof(payload) == "table" and payload.Id
		if type(id) == "string" then
			self:_handleCollect(player, id)
		end
	end)

	self:_fillToMax()
end

return CoinManager
