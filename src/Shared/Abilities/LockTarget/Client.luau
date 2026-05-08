-- Services
local Players = game:GetService("Players")

-- Local Player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

--
local SoundController = require(LocalPlayer.PlayerScripts.Client.Controllers.SoundController)

return {
	OnActivated = function() end,
	OnVictim = function() end,
}
