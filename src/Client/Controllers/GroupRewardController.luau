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
local PlayerDataController
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

	local function setButtonState(isClaimed: boolean)
		holder.Claim.UIStroke.Color = isClaimed and Color3.fromRGB(50, 50, 50) or Color3.fromRGB(0, 85, 0)
		holder.Claim.Title.UIStroke.Color = isClaimed and Color3.fromRGB(50, 50, 50) or Color3.fromRGB(0, 85, 0)
		holder.Claim.Title.Text = isClaimed and "CLAIMED" or "CLAIM"
		holder.Claim.CantClaimGradient.Enabled = isClaimed
		holder.Claim.CanClaimGradient.Enabled = not isClaimed
	end

	PlayerDataController:GetReplica():andThen(function(replica)
		local hasClaimedReward = replica.Data.ClaimedGroupReward
		setButtonState(hasClaimedReward)

		replica:OnSet({ "ClaimedGroupReward" }, function(newClaimedReward)
			setButtonState(newClaimedReward)
		end)
	end)
end

function GroupRewardController:OnInit()
	PlayerDataController = require(script.Parent.PlayerDataController)
	UIController = require(script.Parent.UIController)
	self.UI = PlayerGui:WaitForChild("LikeGameUI")
end

function GroupRewardController:OnStart()
	task.spawn(GroupRewardController._setupUI, self)
end

return GroupRewardController
