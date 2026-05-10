-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)

-- Local Player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

--
local HudController

--
local AFKController = {
	ToggleAFKEvent = BridgeNet2.ReferenceBridge("ToggleAFK"),
}

function AFKController:_setupUI()
	local buttonData = HudController:BindHudButton("AFK", function()
		self.ToggleAFKEvent:Fire()
	end)

	local function setButtonState(isAFk: boolean)
		buttonData.Button.NotAFKGradient.Enabled = not isAFk
		buttonData.Button.AFKGradient.Enabled = isAFk
		buttonData.Button.UIStroke.Color = not isAFk and Color3.fromRGB(80, 0, 0) or Color3.fromRGB(0, 80, 0)
		buttonData.Button.Title.UIStroke.Color = not isAFk and Color3.fromRGB(80, 0, 0) or Color3.fromRGB(0, 80, 0)
	end

	setButtonState(LocalPlayer:GetAttribute("IsAFK"))
	LocalPlayer:GetAttributeChangedSignal("IsAFK"):Connect(function()
		local isAFk = LocalPlayer:GetAttribute("IsAFK")
		setButtonState(isAFk)
	end)
end

function AFKController:OnInit()
	HudController = require(script.Parent.HudController)
end

function AFKController:OnStart()
	task.spawn(AFKController._setupUI, self)
end

return AFKController
