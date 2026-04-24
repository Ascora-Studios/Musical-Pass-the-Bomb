-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Packages = ReplicatedStorage.Packages
local Component = require(Packages.Component)
local Trove = require(Packages.Trove)

--
local UIHover = Component.new({
	Tag = script.Name,
})

function UIHover:Construct()
	--
	local ui = self.Instance
	local offset = ui:GetAttribute("Offset") or Vector2.new(0, 0.05)
	local speed = ui:GetAttribute("Speed") or 1

	--
	local udim2 = UDim2.fromScale(ui.Position.X.Scale + offset.X, ui.Position.Y.Scale + offset.Y)
	TweenService
		:Create(
			ui,
			TweenInfo.new(speed, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = udim2 }
		)
		:Play()
end

return UIHover
