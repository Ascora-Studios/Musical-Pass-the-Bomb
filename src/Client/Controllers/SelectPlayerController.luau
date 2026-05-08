-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Trove = require(Packages.Trove)

-- Local Player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

--
local UIController
local RoundController

--
local SelectPlayerController = {
	SyncSelectedPlayer = BridgeNet2.ReferenceBridge("SyncSelectedPlayer"),

	_playerFrames = {},
	_playerFrameCleaners = {},
	_uiCleaner = Trove.new(),
	_roundCleaner = Trove.new(),
	_pendingAbility = nil,
	_selectionCallback = nil,
	_selectedUserId = nil,
}

function SelectPlayerController:OpenUI()
	UIController:OpenFrame(self.UI.Holder)
end

function SelectPlayerController:OpenForAbility(ability: string, onSelected: (number) -> ())
	self._pendingAbility = ability
	self._selectionCallback = onSelected
	self:OpenUI()
end

function SelectPlayerController:CloseUI()
	if not self.UI.Holder.Visible then
		return
	end

	UIController:CloseFrame(self.UI.Holder)
end

function SelectPlayerController:ClearSelection(closeUI: boolean?)
	self._selectedUserId = nil
	self._selectionCallback = nil
	self._pendingAbility = nil

	if closeUI ~= false then
		self:CloseUI()
	end
end

function SelectPlayerController:SelectPlayer(userId: number)
	self._selectedUserId = userId

	local selectionCallback = self._selectionCallback
	self._selectionCallback = nil
	self._pendingAbility = nil
	self:CloseUI()

	if selectionCallback then
		task.spawn(selectionCallback, userId)
	end
end

function SelectPlayerController:_initUI()
	local ui = self.UI
	local holder = ui.Holder
	local container = holder.Container.ScrollingFrame
	local template = container.PlayerFrameTemplate

	template.Visible = false
	self._uiCleaner:Clean()
	for _, frameCleaner in self._playerFrameCleaners do
		frameCleaner:Destroy()
	end
	self._playerFrames = {}
	self._playerFrameCleaners = {}

	local function setPlayerIcon(playerFrame: Frame, userId: number)
		local playerIcon = playerFrame:FindFirstChild("PlayerIcon")
		if not playerIcon or not playerIcon:IsA("ImageLabel") then
			return
		end

		task.spawn(function()
			local success, image = pcall(
				Players.GetUserThumbnailAsync,
				Players,
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)

			if success and self._playerFrames[userId] == playerFrame then
				playerIcon.Image = image
			end
		end)
	end

	local function updatePlayerFrame(playerFrame: Frame, playerInfo: { [string]: any }, layoutOrder: number)
		local userName = playerInfo.Name or "Unknown"
		local displayName = playerInfo.DisplayName or userName

		playerFrame.LayoutOrder = layoutOrder

		local playerDisplayName = playerFrame:FindFirstChild("PlayerDisplayName")
		if playerDisplayName and playerDisplayName:IsA("TextLabel") then
			playerDisplayName.Text = displayName
		end

		local playerUserName = playerFrame:FindFirstChild("PlayerUserName")
		if playerUserName and playerUserName:IsA("TextLabel") then
			playerUserName.Text = `@{userName}`
		end
	end

	local function removePlayerFrame(userId: number)
		local playerFrame = self._playerFrames[userId]
		if not playerFrame then
			return
		end

		local frameCleaner = self._playerFrameCleaners[userId]
		if frameCleaner then
			frameCleaner:Destroy()
			self._playerFrameCleaners[userId] = nil
		end

		playerFrame:Destroy()
		self._playerFrames[userId] = nil
	end

	local function createPlayerFrame(playerInfo: { [string]: any }, userId: number, layoutOrder: number)
		local playerFrame = template:Clone()
		local frameCleaner = Trove.new()

		playerFrame.Name = `PlayerFrame_{userId}`
		playerFrame.Visible = true
		playerFrame.Parent = container

		self._playerFrames[userId] = playerFrame
		self._playerFrameCleaners[userId] = frameCleaner

		updatePlayerFrame(playerFrame, playerInfo, layoutOrder)
		setPlayerIcon(playerFrame, userId)

		frameCleaner:Add(UIController:BindButtonClick(playerFrame.Button, function()
			self:SelectPlayer(userId)
		end, true, false, { ShowFrame = playerFrame }))
	end

	local function isLocalPlayerAlive(alivePlayers: { [number]: { [string]: any } }?): boolean
		for _, playerInfo in alivePlayers or {} do
			if tonumber(playerInfo.UserId) == LocalPlayer.UserId then
				return true
			end
		end

		return false
	end

	local function syncAlivePlayers(alivePlayers: { [number]: { [string]: any } }?)
		local aliveUserIds = {}
		local staleUserIds = {}

		for layoutOrder, playerInfo in alivePlayers or {} do
			local userId = tonumber(playerInfo.UserId)
			if userId then
				if userId == LocalPlayer.UserId then
					continue
				end

				aliveUserIds[userId] = true

				local playerFrame = self._playerFrames[userId]
				if playerFrame then
					updatePlayerFrame(playerFrame, playerInfo, layoutOrder)
				else
					createPlayerFrame(playerInfo, userId, layoutOrder)
				end
			end
		end

		for userId, _playerFrame in self._playerFrames do
			if not aliveUserIds[userId] then
				table.insert(staleUserIds, userId)
			end
		end

		for _, userId in staleUserIds do
			removePlayerFrame(userId)
		end

		if not isLocalPlayerAlive(alivePlayers) then
			self:ClearSelection()
		elseif self._selectedUserId and not aliveUserIds[self._selectedUserId] then
			self:ClearSelection()
		end
	end

	self._uiCleaner:Add(RoundController.OnReplicaReady:Connect(function(replica)
		syncAlivePlayers(replica.Data.AlivePlayers)
	end))

	self._uiCleaner:Add(RoundController.OnDataChanged:Connect(function(_action, path, _param1, _param2, data)
		local key = path and path[1]
		if key == "AlivePlayers" then
			syncAlivePlayers(data.AlivePlayers)
		end
	end))

	self._uiCleaner:Add(Players.PlayerRemoving:Connect(function(player)
		removePlayerFrame(player.UserId)
	end))

	task.spawn(function()
		local data = RoundController:GetData()
		if data then
			syncAlivePlayers(data.AlivePlayers)
		end
	end)
end

function SelectPlayerController:OnInit()
	UIController = require(script.Parent.UIController)
	RoundController = require(script.Parent.RoundController)

	self.UI = PlayerGui:WaitForChild("SelectPlayerUI")
end

function SelectPlayerController:OnStart()
	task.spawn(SelectPlayerController._initUI, self)

	self._roundCleaner:Add(RoundController.OnPlayerEliminatedSignal:Connect(function(eliminatedInfo: { [string]: any }?)
		if not eliminatedInfo then
			return
		end

		if eliminatedInfo.UserId == LocalPlayer.UserId or eliminatedInfo.UserId == self._selectedUserId then
			self:ClearSelection()
		end
	end))

	self._roundCleaner:Add(RoundController.OnMatchEndSignal:Connect(function()
		self:ClearSelection()
	end))

	self._roundCleaner:Add(RoundController.OnIntermissionStartedSignal:Connect(function()
		self:ClearSelection()
	end))

	self.SyncSelectedPlayer:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end

		self._selectedUserId = payload.UserId
		if payload.UserId == nil then
			self:ClearSelection()
		end
	end)
end

return SelectPlayerController
