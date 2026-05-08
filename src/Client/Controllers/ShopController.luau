-- Services
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Spr = require(Packages.Spr)

-- Shared
local Shared = ReplicatedStorage.Shared
local Products = require(Shared.Config.Products)
local Gamepasses = require(Shared.Config.Gamepasses)
local GuiUtil = require(Shared.GuiUtil)

-- Local Player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

--
local PlayerDataController
local HudController
local UIController
local SoundController

--
local ShopController = {
	--
	RequestProductPurchase = BridgeNet2.ReferenceBridge("RequestProductPurchase"),
	RequestGamepassPurchase = BridgeNet2.ReferenceBridge("RequestGamepassPurchase"),

	--
	Prices = {},
}

-- Requests a product purchase from an id
function ShopController:PromptProductPurchaseFromId(id: string, toGift: Player?): (boolean, { any })
	--
	local productInfo = Products.GetProductFromId(id)
	if not productInfo then
		warn(`Product data for id {id} not found.`)
		return
	end

	--
	self.RequestProductPurchase:Fire({ id, toGift })
	return true, productInfo
end

-- Requests a gamepass purchase from an id
function ShopController:PromptGamepassPurchaseFromId(id: string, toGift: Player): (boolean, { any })
	--
	local gamepassInfo = Gamepasses.GetGamepassFromId(id)
	if not gamepassInfo then
		warn(`Gamepass data for id {id} not found.`)
		return
	end

	--
	self.RequestGamepassPurchase:Fire({ id, toGift })
	return true, gamepassInfo
end

-- Gets the product or gamepass data from an id
function ShopController:GetProductFromId(id: string): Gamepasses.Gamepass | Products.Product
	return Products.GetProductFromId(id) or Gamepasses.GetGamepassFromId(id)
end

-- Gets the price of a product or gamepass
function ShopController:GetPrice(id: string)
	--
	local data = Products.GetProductFromId(id) or Gamepasses.GetGamepassFromId(id)
	if not data then
		return "-"
	end
	local isGamepass = if Products.GetProductFromId(id) then false else true

	--
	if data.CurrencyPrice then
		return data.CurrencyPrice
	end

	--
	if self.Prices[data.Id] then
		return self.Prices[data.Id]
	end

	--
	local success, productInfo = pcall(function()
		return MarketplaceService:GetProductInfo(
			isGamepass and data.PassId or data.ProductId,
			isGamepass and Enum.InfoType.GamePass or Enum.InfoType.Product
		)
	end)

	if not success or not productInfo or productInfo.PriceInRobux == nil then
		return "-"
	end

	local price = productInfo.PriceInRobux
	self.Prices[data.Id] = price

	return price
end

-- Sets up the starter pack UI
function ShopController:_setupStarterPack()
	--
	local holder = self.UI.Holder
	local starterPackContainer = holder.Container.ScrollingFrame.StarterPack

	--
	local purchaseButton = starterPackContainer.Purchase

	task.spawn(function()
		purchaseButton.Title.Text = `{utf8.char(0xE002)}{self:GetPrice("StarterPack")}`
	end)

	UIController:BindButtonClick(purchaseButton, function()
		self:PromptProductPurchaseFromId("StarterPack")
	end, true, false)

	local hudButtonData = HudController:BindHudButton("StarterPack", function()
		self:PromptProductPurchaseFromId("StarterPack")
	end)

	PlayerDataController:GetReplica():andThen(function(replica)
		local starterPackStart = replica.Data.StarterPackStart
		local purchasedOnceProducts = replica.Data.PurchasedOnceProducts

		hudButtonData.Button.Visible = not table.find(purchasedOnceProducts, "StarterPack")
		task.spawn(function()
			while true do
				local timeLeft = starterPackStart - os.time()
				starterPackContainer.Timer.Text = GuiUtil.ConvertSecondsToHHMMSS(timeLeft)
				hudButtonData.Button.Timer.Text = GuiUtil.ConvertSecondsToHHMMSS(timeLeft)

				if timeLeft <= 0 then
					starterPackContainer.Timer.Visible = false
					starterPackContainer.TimerTitle.Visible = false
					hudButtonData.Button.Visible = false
					break
				end

				task.wait(1)
			end
		end)
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(_, productId: string, wasPurchased: boolean)
		local productData = Products.GetProductFromProductId(productId)
		if productData and productData.Id == "StarterPack" and wasPurchased then
			hudButtonData.Button.Visible = false
			starterPackContainer.Timer.Visible = false
			starterPackContainer.TimerTitle.Visible = false
		end
	end)
end

-- Sets up the gamepasses UI
function ShopController:_setupGamepasses()
	--
	local holder = self.UI.Holder
	local gamepassesContainer = holder.Container.ScrollingFrame.Gamepasses

	--
	for _, gamepassFrame in gamepassesContainer:GetChildren() do
		if not gamepassFrame:IsA("Frame") then
			continue
		end

		local data = Gamepasses.GetGamepassFromId(gamepassFrame.Name)
		if not data then
			print(`Gamepass frame {gamepassFrame.Name} not found in gamepasses data.`)
			continue
		end

		task.spawn(function()
			gamepassFrame.Price.Text = `{utf8.char(0xE002)}{self:GetPrice(data.Id)}`
		end)

		UIController:BindButtonClick(gamepassFrame.Button, function()
			self:PromptGamepassPurchaseFromId(data.Id)
		end, true, false, { ShowFrame = gamepassFrame, ButtonHoverscale = 1.025 })
	end
end

-- Sets up the coins UI
function ShopController:_setupCoins()
	--
	local holder = self.UI.Holder
	local coinsContainer = holder.Container.ScrollingFrame.Coins

	--
	for _, coinFrame in coinsContainer:GetChildren() do
		if not coinFrame:IsA("Frame") then
			continue
		end

		local data = Products.GetProductFromId(coinFrame.Name)
		if not data then
			print(`Coin frame {coinFrame.Name} not found in products data.`)
			continue
		end

		coinFrame.Title.Text = `{data.Value} COINS`
		task.spawn(function()
			coinFrame.Price.Text = `{utf8.char(0xE002)}{self:GetPrice(data.Id)}`
		end)

		UIController:BindButtonClick(coinFrame.Button, function()
			self:PromptProductPurchaseFromId(data.Id)
		end, true, false, { ShowFrame = coinFrame, ButtonHoverscale = 1.025 })
	end
end

--
function ShopController:_setupUI()
	--
	local ui = self.UI
	local holder = ui.Holder

	--
	HudController:BindHudButton("Shop", function()
		UIController:OpenFrame(holder)
	end, true)

	UIController:BindButtonClick(holder.Exit, function()
		UIController:CloseFrame(holder)
	end, true)

	local vignetteThread
	UIController.OnFrameOpened:Connect(function(frame)
		if not (frame == holder) then
			return
		end

		vignetteThread = task.spawn(function()
			while true do
				ui.Glow.ImageTransparency = 0.95 + math.sin(tick() * 3) * 0.05
				task.wait()
			end
		end)

		SoundController:PlaySound("ShopOpen")
		Spr.target(ui.Dim, 0.8, 2.5, { BackgroundTransparency = 0.5 })
	end)

	UIController.OnFrameClosed:Connect(function(frame)
		if not (frame == holder) then
			return
		end

		Spr.target(ui.Dim, 0.8, 2.5, { BackgroundTransparency = 1 })

		if vignetteThread then
			task.cancel(vignetteThread)
		end

		Spr.target(ui.Glow, 0.8, 2.5, { ImageTransparency = 1 })
	end)

	--
	task.spawn(ShopController._setupStarterPack, self)
	task.spawn(ShopController._setupGamepasses, self)
	task.spawn(ShopController._setupCoins, self)
end

function ShopController:OnInit()
	PlayerDataController = require(script.Parent.PlayerDataController)
	UIController = require(script.Parent.UIController)
	HudController = require(script.Parent.HudController)
	SoundController = require(script.Parent.SoundController)

	self.HudUI = PlayerGui:WaitForChild("HudUI")
	self.UI = PlayerGui:WaitForChild("ShopUI")
end

function ShopController:OnStart()
	task.spawn(ShopController._setupUI, self)
end

return ShopController
