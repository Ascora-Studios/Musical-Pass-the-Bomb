-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Packages
local Packages = ReplicatedStorage.Packages

-- Shared
local Shared = ReplicatedStorage.Shared
local GuiUtil = require(Shared.GuiUtil)

-- Local Player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

--
local PlayerDataController
local EffectController

--
local CurrencyController = {
	_previousThread = nil,
}

function CurrencyController:OnIncrementCurrency(new: number, old: number?)
	local hudUI = self.HudUI
	local currency = hudUI.Left.Currency

	if self._previousThread then
		task.cancel(self._previousThread)
		self._previousThread = nil
	end

	local difference = new - (old or 0)

	GuiUtil.AnimateNumberTo(new, false, 0.5, function(value)
		currency.Amount.Text = GuiUtil.ConvertNumberWithCommas(value)
	end, old)

	TweenService:Create(
		currency.UIScale,
		TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut, 0, true),
		{ Scale = 1.1 }
	):Play()

	self._previousThread = task.delay(1, function()
		TweenService:Create(
			currency.UIScale,
			TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, true),
			{ Scale = 1 }
		):Play()
	end)

	-- if coin increased then do effe
	if difference > 0 then
		EffectController:RunEffect("CoinReceived", LocalPlayer)
	end
end

function CurrencyController:OnInit()
	PlayerDataController = require(script.Parent.PlayerDataController)
	EffectController = require(script.Parent.EffectController)

	self.HudUI = PlayerGui:WaitForChild("HudUI")

	PlayerDataController:GetReplica():andThen(function(replica)
		self.HudUI.Left.Currency.Amount.Text = GuiUtil.ConvertNumberWithCommas(replica.Data.Currency)
		replica:OnSet({ "Currency" }, function(new, old)
			self:OnIncrementCurrency(new, old)
		end)
	end)
end

return CurrencyController
