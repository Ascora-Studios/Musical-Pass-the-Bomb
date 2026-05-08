-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)

-- Shared
local Shared = ReplicatedStorage.Shared
local TimeRewardsConfig = require(Shared.Config.TimeRewards)
local GuiUtil = require(Shared.GuiUtil)

-- Local Player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

--
local HudController
local UIController

--
local TimeRewardController = {
	ClaimRewardEvent = BridgeNet2.ReferenceBridge("ClaimTimeReward"),
}

function TimeRewardController:_setupUI()
	local ui = self.UI
	local holder = ui.Holder
	local container = holder.Container.HolderFrame

	local hasAvailableReward = false
	local claimedRewards

	--
	local data = HudController:BindHudButton("Gift", function()
		UIController:OpenFrame(holder)
	end)

	--
	for _, reward in TimeRewardsConfig.GetAllRewards() do
		local rewardTemplate = container.RewardTemplate:Clone()
		rewardTemplate.Name = reward.Id
		rewardTemplate.Title.Text = reward.Title:upper()
		rewardTemplate.Icon.Image = reward.Icon
		rewardTemplate.Visible = true
		rewardTemplate.Parent = container

		UIController:BindButtonClick(rewardTemplate.Button, function()
			self.ClaimRewardEvent:Fire(reward.Id)
		end, true, false, { ShowFrame = rewardTemplate })
	end

	local function getClaimedTimeRewards()
		return HttpService:JSONDecode(LocalPlayer:GetAttribute("ClaimedTimeRewards") or "[]")
	end

	local function updateRewards()
		local joinTime = LocalPlayer:GetAttribute("JoinTime")
		if not joinTime then
			return
		end

		local timeElapsed = workspace:GetServerTimeNow() - joinTime
		local nextHasAvailableReward = false

		for _, reward in container:GetChildren() do
			if not reward:IsA("Frame") then
				continue
			end
			local rewardConfig = TimeRewardsConfig.GetRewardFromId(reward.Name)
			if not rewardConfig then
				continue
			end

			local isClaimed = table.find(claimedRewards, reward.Name)
			if isClaimed then
				reward.LockedDim.Visible = true
				reward.LockedTitle.Visible = true
				reward.LockedTitle.TextColor3 = Color3.fromRGB(85, 255, 0)
				reward.LockedTitle.Text = "CLAIMED!"
				reward.Ray.Visible = false
				reward.Alert.Visible = false
			elseif timeElapsed < rewardConfig.Time then
				reward.LockedDim.Visible = true
				reward.LockedTitle.Visible = true
				reward.LockedTitle.Text = GuiUtil.ConvertSecondsToMMSS(rewardConfig.Time - timeElapsed)
			else
				nextHasAvailableReward = true
				reward.Ray.Visible = true
				reward.Alert.Visible = true
				reward.Alert:AddTag("UISway")
				reward.LockedDim.Visible = false
				reward.LockedTitle.Visible = false
			end
		end

		if hasAvailableReward ~= nextHasAvailableReward then
			hasAvailableReward = nextHasAvailableReward
		end
	end

	claimedRewards = getClaimedTimeRewards()
	LocalPlayer:GetAttributeChangedSignal("ClaimedTimeRewards"):Connect(function()
		claimedRewards = getClaimedTimeRewards()
		updateRewards()
	end)
	LocalPlayer:GetAttributeChangedSignal("JoinTime"):Connect(updateRewards)

	UIController:BindButtonClick(holder.Exit, function()
		UIController:CloseFrame(holder)
	end, true)

	task.spawn(function()
		while true do
			updateRewards()
			data.Button.AlertIcon.Visible = hasAvailableReward
			task.wait(1)
		end
	end)
end

function TimeRewardController:OnInit()
	UIController = require(script.Parent.UIController)
	HudController = require(script.Parent.HudController)

	self.UI = PlayerGui:WaitForChild("TimeRewardUI")
end

function TimeRewardController:OnStart()
	task.spawn(TimeRewardController._setupUI, self)
end

return TimeRewardController
