-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local ZonePlus = require(Packages.ZonePlus)

-- Local Player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

--
local UIController

--
local GroupRewardController = {
	ClaimRewardEvent = BridgeNet2.ReferenceBridge("ClaimGroupReward"),
}

function GroupRewardController:_setupUI()
	local ui = self.UI
	local holder = ui.Holder

	--
	UIController:BindButtonClick(holder.Claim, function()
		self.ClaimRewardEvent:Fire()
	end, true)

	--
	local likeReward = workspace.Main.LikeReward

	local likeRewardZone = ZonePlus.new(likeReward.Hitbox)
	likeRewardZone.localPlayerEntered:Connect(function()
		UIController:OpenFrame(holder)
	end, true)

	UIController:BindButtonClick(holder.Exit, function()
		UIController:CloseFrame(holder)
	end, true)
end

function GroupRewardController:OnInit()
	UIController = require(script.Parent.UIController)
	self.UI = PlayerGui:WaitForChild("LikeGameUI")
end

function GroupRewardController:OnStart()
	task.spawn(GroupRewardController._setupUI, self)
end

return GroupRewardController
