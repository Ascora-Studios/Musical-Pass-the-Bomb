-- Services
local Players = game:GetService("Players")

-- Config
local Config = require(script.Parent.Config)

-- Local Player
local LocalPlayer = Players.LocalPlayer

-- Controllers
local RoundController = require(LocalPlayer.PlayerScripts.Client.Controllers.RoundController)
local SoundController = require(LocalPlayer.PlayerScripts.Client.Controllers.SoundController)

-- Self-contained ice state. The bomb model is destroyed and re-cloned on
-- skin-change passes, so we re-attach on RoundController.OnBombSpawnedSignal and
-- tear everything down when the freeze ends or the match finishes.
local iceParts = {}
local respawnConnection: RBXScriptConnection? = nil
local stopThread: thread? = nil

local function clearIce()
	for _, part in iceParts do
		part:Destroy()
	end
	table.clear(iceParts)
end

local function attachToBomb()
	clearIce()

	local bomb = RoundController:GetBomb()
	local primaryPart = bomb and bomb.PrimaryPart
	if not primaryPart then
		return
	end

	local ice = Instance.new("Part")
	ice.Name = "FreezeIce"
	ice.Size = bomb:GetExtentsSize()
	ice.CFrame = bomb:GetPivot()
	ice.Material = Enum.Material.Ice
	ice.Color = Color3.fromRGB(170, 255, 255)
	ice.Transparency = 0.3
	ice.CanCollide = false
	ice.CanQuery = false
	ice.Anchored = false
	ice.Massless = true
	ice.Parent = bomb

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = primaryPart
	weld.Part1 = ice
	weld.Parent = ice

	table.insert(iceParts, ice)
end

local function stopFreeze()
	if respawnConnection then
		respawnConnection:Disconnect()
		respawnConnection = nil
	end
	if stopThread then
		task.cancel(stopThread)
		stopThread = nil
	end
	clearIce()
end

-- Runs on every alive client so everyone sees the bomb freeze over.
local function freezeBomb()
	stopFreeze()

	attachToBomb()
	respawnConnection = RoundController.OnBombSpawnedSignal:Connect(attachToBomb)

	local bomb = RoundController:GetBomb()
	if bomb then
		SoundController:PlaySound("Freeze", bomb:GetPivot())
	end

	stopThread = task.delay(Config.Duration, function()
		stopThread = nil
		stopFreeze()
	end)
end

-- A match ending mid-freeze destroys the bomb anyway; make sure the timer/connection
-- don't bleed into the next match.
RoundController.OnMatchEndSignal:Connect(stopFreeze)

return {
	OnActivated = function() end,
	OnVictim = freezeBomb,
}
