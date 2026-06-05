-- Services
local Players = game:GetService("Players")

-- Config
local Config = require(script.Parent.Config)

-- Local Player
local LocalPlayer = Players.LocalPlayer

-- Controllers
local RoundController = require(LocalPlayer.PlayerScripts.Client.Controllers.RoundController)

-- Self-contained scale state. The bomb model is destroyed and re-cloned on
-- skin-change passes, so we re-apply the scale on RoundController.OnBombSpawnedSignal
-- and shrink back when the bomb goes off (post-elimination) or the match ends.
local connections = {}

local function setBombScale(scale: number)
	local bomb = RoundController:GetBomb()
	if bomb then
		bomb:ScaleTo(scale)
	end
end

local function shrinkBomb()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	setBombScale(1)
end

-- Runs on every alive client so everyone sees the bomb grow.
local function enlargeBomb()
	shrinkBomb()

	setBombScale(Config.Scale)
	table.insert(connections, RoundController.OnBombSpawnedSignal:Connect(function()
		setBombScale(Config.Scale)
	end))
	-- The bomb shrinks back once it detonates (the holder is being eliminated).
	table.insert(connections, RoundController.OnPostEliminationSignal:Connect(shrinkBomb))
end

-- A match ending mid-arm destroys the bomb anyway; make sure the scale/connections
-- don't bleed into the next match.
RoundController.OnMatchEndSignal:Connect(shrinkBomb)

return {
	OnActivated = function() end,
	OnVictim = enlargeBomb,
}
