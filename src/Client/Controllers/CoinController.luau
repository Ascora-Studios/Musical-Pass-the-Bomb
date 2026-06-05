-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Replica = require(Packages.Replica)
local Spr = require(Packages.Spr)

-- Assets
local Assets = ReplicatedStorage.Assets
local Meshes = Assets.Meshes

-- Local Player
local LocalPlayer = Players.LocalPlayer

-- Constants
local SPIN_DIRECTION = Vector3.new(1, 0, 0)
local SPIN_SPEED = 0.5

--
local CoinController = {
	RequestCollectCoin = BridgeNet2.ReferenceBridge("RequestCollectCoin"),
	CoinCollected = BridgeNet2.ReferenceBridge("CoinCollected"),

	_coins = {} :: { [string]: Instance },
	_requested = {} :: { [string]: boolean },
	_folder = nil :: Folder?,
}

function CoinController:_addCoin(id: string, position: Vector3)
	if self._coins[id] then
		return
	end

	local coin = Meshes.Coin:Clone()
	coin:PivotTo(CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)))
	coin:SetAttribute("SpinDirection", SPIN_DIRECTION)
	coin:SetAttribute("SpinSpeed", SPIN_SPEED)
	coin:AddTag("PartSpin")
	coin.Parent = self._folder

	self._coins[id] = coin

	local touchPart = coin:IsA("BasePart") and coin or coin.PrimaryPart or coin:FindFirstChildWhichIsA("BasePart", true)
	if touchPart then
		touchPart.Touched:Connect(function(hit)
			if self._requested[id] then
				return
			end

			local character = LocalPlayer.Character
			if not character or not hit:IsDescendantOf(character) then
				return
			end

			self._requested[id] = true
			self.RequestCollectCoin:Fire({ Id = id })
		end)
	end
end

function CoinController:_removeCoin(id: string)
	local coin = self._coins[id]
	if coin then
		coin:Destroy()
	end

	self._coins[id] = nil
	self._requested[id] = nil
end

-- Hook: runs when a coin is collected. Add your collect effect here.
function CoinController:OnCoinCollected(coinInstance: Instance, collector: Player?)
	Spr.target(coinInstance, 0.8, 2.5, { Size = coinInstance.Size * 1.5 })
	TweenService:Create(coinInstance, TweenInfo.new(0.3), { Transparency = 1 }):Play()

	coinInstance:ClearAllChildren()

	task.wait(0.5)
	coinInstance:Destroy()
end

function CoinController:_onCollected(id: string, collectorUserId: number?)
	local coin = self._coins[id]
	if coin then
		self:OnCoinCollected(coin, collectorUserId and Players:GetPlayerByUserId(collectorUserId))
	end

	self._coins[id] = nil
	self._requested[id] = nil
end

function CoinController:OnStart()
	self._folder = Instance.new("Folder")
	self._folder.Name = "Coins"
	self._folder.Parent = workspace

	Replica.OnNew("Coins", function(replica)
		for id, coin in replica.Data.Coins do
			self:_addCoin(id, coin.Position)
		end

		replica:OnChange(function(_action, path)
			if path[1] ~= "Coins" then
				return
			end

			local id = path[2]
			local coin = replica.Data.Coins[id]
			if coin then
				self:_addCoin(id, coin.Position)
			else
				-- Collection is normally handled by the CoinCollected event (which
				-- carries the collector for the hook). This is a delayed safety net
				-- in case that event never arrives, so coins can't linger.
				task.delay(1, function()
					if self._coins[id] then
						self:_removeCoin(id)
					end
				end)
			end
		end)
	end)

	-- Primary collect path: carries the collector for the effect hook.
	self.CoinCollected:Connect(function(payload: any)
		if typeof(payload) == "table" and type(payload.Id) == "string" then
			self:_onCollected(payload.Id, payload.CollectorUserId)
		end
	end)
end

return CoinController
