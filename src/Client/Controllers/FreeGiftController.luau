-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages

-- Shared
local Shared = ReplicatedStorage.Shared
local GuiUtil = require(Shared.GuiUtil)

-- Local Player
local LocalPlayer = Players.LocalPlayer

--
local FreeGiftController = {}

function FreeGiftController:_setupGift()
	--
	local ObbyFolder = workspace:WaitForChild("Obby")
	local Hitbox = ObbyFolder:WaitForChild("Hitbox")

	--
	local ui = Hitbox.Attachment.UI
	local timerText = ui.Holder.Timer

	--
	while true do
		task.wait(1)

		local currentTime = workspace:GetServerTimeNow()
		local claimTime = LocalPlayer:GetAttribute("GiftClaimTime")

		if not claimTime then
			continue
		end

		if currentTime < claimTime then
			local timeLeft = claimTime - currentTime
			timerText.Text = GuiUtil.ConvertSecondsToHHMMSS(timeLeft)
		else
			timerText.Text = "CLAIM GIFT!"
		end
	end
end

function FreeGiftController:OnStart()
	task.spawn(FreeGiftController._setupGift, self)
end

return FreeGiftController
