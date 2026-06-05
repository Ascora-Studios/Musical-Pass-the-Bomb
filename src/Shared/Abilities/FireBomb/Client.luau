-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Assets
local FireEffects = ReplicatedStorage.Assets.Effects.Fire

-- Config
local Config = require(script.Parent.Config)

-- Local Player
local LocalPlayer = Players.LocalPlayer

-- Controllers
local RoundController = require(LocalPlayer.PlayerScripts.Client.Controllers.RoundController)

-- Self-contained fire effect state. The bomb model is destroyed and re-cloned on
-- skin-change passes, so we re-attach on RoundController.OnBombSpawnedSignal and
-- tear everything down when the burn ends or the match finishes.
local activeEffects = {}
local respawnConnection: RBXScriptConnection? = nil
local stopThread: thread? = nil

local function clearEffects()
	for _, effect in activeEffects do
		effect:Destroy()
	end
	table.clear(activeEffects)
end

local function attachToBomb()
	clearEffects()

	local bomb = RoundController:GetBomb()
	local primaryPart = bomb and bomb.PrimaryPart
	if not primaryPart then
		return
	end

	for _, effect in FireEffects:GetChildren() do
		local clone = effect:Clone()
		clone.Parent = primaryPart
		table.insert(activeEffects, clone)
	end
end

local function stopFire()
	if respawnConnection then
		respawnConnection:Disconnect()
		respawnConnection = nil
	end
	if stopThread then
		task.cancel(stopThread)
		stopThread = nil
	end
	clearEffects()
end

-- Runs on every alive client so everyone sees the bomb catch fire.
local function igniteBomb()
	stopFire()

	attachToBomb()
	respawnConnection = RoundController.OnBombSpawnedSignal:Connect(attachToBomb)

	stopThread = task.delay(Config.Duration, function()
		stopThread = nil
		stopFire()
	end)
end

-- A match ending mid-burn destroys the bomb anyway; make sure the timer/connection
-- don't bleed into the next match.
RoundController.OnMatchEndSignal:Connect(stopFire)

return {
	OnActivated = function() end,
	OnVictim = igniteBomb,
}
