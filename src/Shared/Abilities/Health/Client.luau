-- Services
local Players = game:GetService("Players")

-- Local Player
local LocalPlayer = Players.LocalPlayer

--
local SoundController = require(LocalPlayer.PlayerScripts.Client.Controllers.SoundController)

return {
	OnActivated = function()
		SoundController:PlaySound("AddHealth", LocalPlayer.Character:GetPivot())
	end,
	OnVictim = function() end,
}
