--[[
	BombManager

	Purpose:
		Keeps track of who currently has the bomb and syncs that holder to
		all clients. This module is intentionally small: it does not decide
		who is alive, who is allowed to receive a pass, when the bomb explodes,
		or when a match starts/ends. Those are round rules and live in
		RoundManager.

	What this owns:
		- The current bomb holder (`_bombHolder`)
		- `SyncBombHolder` server -> client replication
		- `OnHolderChanged`, so other server code can react to holder changes
		- A visual hook stub (`_onHolderChanged`) for bomb attach / handoff VFX

	What this does NOT own:
		- The alive-player list
		- Circle positions / pass direction math
		- `RequestBombPass` validation
		- Music / explosion timestamps
		- Eliminations, rewards, placements, or winner logic

	How it is used:
		1. RoundManager validates game rules.
		2. If a pass/random assignment is valid, RoundManager calls
		   `BombManager:SetHolder(player)`.
		3. BombManager updates `_bombHolder`, fires `SyncBombHolder`, and
		   triggers `OnHolderChanged`.

	BridgeNet2 notes:
		- `RequestBombPass` is referenced here only so both managers use the
		  same bridge name, but RoundManager is the module that connects to it
		  and validates requests.
		- `SyncBombHolder` is fired from here because holder sync is the bomb's
		  one real responsibility.
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Signal = require(Packages.Signal)

--
local BombManager = {
	-- BridgeNet2 bridges (server creates, clients ReferenceBridge by same name)
	RequestBombPass = BridgeNet2.ReferenceBridge("RequestBombPass"),
	SyncBombHolder = BridgeNet2.ReferenceBridge("SyncBombHolder"),

	-- Server-side signals
	OnHolderChanged = Signal.new(),

	-- State
	_bombHolder = nil :: Player?,
}

----------------------------------------------------------------
-- Holder management
----------------------------------------------------------------

function BombManager:SetHolder(player: Player?)
	if self._bombHolder == player then
		return
	end

	self._bombHolder = player
	self.SyncBombHolder:Fire(BridgeNet2.AllPlayers(), { UserId = player and player.UserId or nil })
	self.OnHolderChanged:Fire(player)

	-- HOOK: visual effects (attach bomb model to character, glow, etc.)
	-- Add your code here or listen to OnHolderChanged from another script.
	self:_onHolderChanged(player)
end

function BombManager:GetHolder(): Player?
	return self._bombHolder
end

----------------------------------------------------------------
-- Hooks (override or listen via signals)
----------------------------------------------------------------

function BombManager:_onHolderChanged(_player: Player?)
	-- HOOK: Attach bomb model, play hand-off VFX/SFX, etc.
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function BombManager:OnInit() end

function BombManager:OnStart()
	-- NOTE: client `RequestBombPass` requests are handled by `RoundManager`,
	-- which validates against its alive list and circle order, then calls
	-- BombManager:SetHolder(target) on success. We don't connect here.
end

return BombManager
