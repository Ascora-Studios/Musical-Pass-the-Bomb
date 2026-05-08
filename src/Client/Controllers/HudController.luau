-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterPack = game:GetService("StarterPack")

-- Packages
local Packages = ReplicatedStorage.Packages
local Spr = require(Packages.Spr)

-- Local Player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

--
local UIController

--
local HudController = {}

function HudController:ShowHud()
	local ui = self.UI

	Spr.target(ui.Left, 0.7, 2.5, { Position = UDim2.fromScale(0.15, 0.5) })
	Spr.target(ui.Right, 0.7, 2.5, { Position = UDim2.fromScale(0.85, 0.5) })
end

function HudController:HideHud()
	local ui = self.UI

	Spr.target(ui.Left, 0.7, 2.5, { Position = UDim2.fromScale(-0.1, 0.5) })
	Spr.target(ui.Right, 0.7, 2.5, { Position = UDim2.fromScale(1.1, 0.5) })
end

--
function HudController:BindHudButton(
	buttonName: string,
	callback: () -> ()
): { Disconnect: () -> (), Button: GuiObject }
	local ui = self.UI

	local buttonFrame = ui:FindFirstChild(buttonName, true)
	if not buttonFrame then
		warn(`Button {buttonName} not found in HudUI`)
		return
	end

	local connection = UIController:BindButtonClick(buttonFrame.Button, callback, true, false, {
		ShowFrame = buttonFrame,
	})

	return {
		Disconnect = connection.Disconnect,
		Button = buttonFrame,
	}
end

function HudController:OnInit()
	self.UI = PlayerGui:WaitForChild("HudUI")
	UIController = require(script.Parent.UIController)
end

return HudController
