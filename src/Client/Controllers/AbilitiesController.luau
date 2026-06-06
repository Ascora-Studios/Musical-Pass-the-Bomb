-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Spr = require(Packages.Spr)

-- Local Player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

-- Shared
local Shared = ReplicatedStorage.Shared
local Abilities = Shared.Abilities

--
local PlayerDataController
local HudController
local ShopController
local UIController
local SelectPlayerController
local RoundController

--
local AbilitiesController = {
	--
	UseAbilityEvent = BridgeNet2.ReferenceBridge("UseAbility"),
	OnUseAbilityEvent = BridgeNet2.ReferenceBridge("OnUseAbility"),
	RequestAbilityPurchaseEvent = BridgeNet2.ReferenceBridge("RequestAbilityPurchase"),

	_abilities = {},
	_timerRevealActive = false,
	_timerRevealThread = nil :: thread?,
	_timerRevealConnections = {},
}

function AbilitiesController:ToggleDisplay(toggle: boolean)
	local ui = self.UI
	local display = ui.Display

	Spr.target(display, 0.8, 2.5, { Position = toggle and UDim2.fromScale(0.94, 0.5) or UDim2.fromScale(1.2, 0.5) })
end

function AbilitiesController:ToggleUI(toggle: boolean)
	local ui = self.UI
	local holder = ui.Holder

	if toggle then
		UIController:OpenFrame(holder)
	else
		UIController:CloseFrame(holder)
	end
end

function AbilitiesController:OpenTimerReveal()
	if self._timerRevealActive then
		return
	end
	self._timerRevealActive = true

	local frame = self.TimeStopFrame
	local countdown = frame.Countdown

	UIController:OpenFrame(frame, true)

	self._timerRevealThread = task.spawn(function()
		local started = false

		while true do
			local timeLeft = RoundController:GetTimeUntilExplosion()

			if timeLeft > 0 then
				started = true
				countdown.Text = string.format("%05.2f", timeLeft)
				countdown.TextColor3 = timeLeft < 3 and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(255, 255, 255)
			elseif started then
				-- The timer reached zero (bomb exploded / music stopped) — the
				-- revealed cycle is over, so close the vision. Clear the reference
				-- first so :_closeTimerReveal doesn't try to cancel this thread.
				countdown.Text = string.format("%05.2f", 0)
				self._timerRevealThread = nil
				self:_closeTimerReveal()
				return
			else
				-- Bought during the gap between cycles; hold until the next timer.
				countdown.Text = string.format("%05.2f", 0)
				countdown.TextColor3 = Color3.fromRGB(255, 50, 50)
			end

			task.wait()
		end
	end)

	-- Close if the match ends while the vision is still open.
	table.insert(self._timerRevealConnections, RoundController.OnMatchEndSignal:Connect(function()
		self:_closeTimerReveal()
	end))
end

function AbilitiesController:_closeTimerReveal()
	if not self._timerRevealActive then
		return
	end
	self._timerRevealActive = false

	if self._timerRevealThread then
		task.cancel(self._timerRevealThread)
		self._timerRevealThread = nil
	end

	for _, connection in self._timerRevealConnections do
		connection:Disconnect()
	end
	table.clear(self._timerRevealConnections)

	UIController:CloseFrame(self.TimeStopFrame)
end

function AbilitiesController:RequestAbilityPurchase(ability: string, selectedUserId: number?)
	if type(ability) ~= "string" then
		return
	end

	if selectedUserId then
		self.RequestAbilityPurchaseEvent:Fire({
			Ability = ability,
			SelectedUserId = selectedUserId,
		})
	else
		self.RequestAbilityPurchaseEvent:Fire(ability)
	end
end

function AbilitiesController:RequestUseAbility(ability: string, selectedUserId: number?)
	if type(ability) ~= "string" then
		return
	end

	if selectedUserId then
		self.UseAbilityEvent:Fire({
			Ability = ability,
			SelectedUserId = selectedUserId,
		})
	else
		self.UseAbilityEvent:Fire(ability)
	end
end

function AbilitiesController:_setupUI()
	local ui = self.UI
	local holder = ui.Holder
	local container = holder.Container.ScrollingFrame
	local display = ui.Display

	local playerReplica

	local function requestAbility(abilityName: string, selectedUserId: number?)
		local ownedAmount = 0
		if playerReplica then
			ownedAmount = (playerReplica.Data.Abilities or {})[abilityName] or 0
		end

		if LocalPlayer:GetAttribute("InGame") == true and ownedAmount > 0 then
			self:RequestUseAbility(abilityName, selectedUserId)
		else
			self:RequestAbilityPurchase(abilityName, selectedUserId)
		end
	end

	-- Bind the buttons
	for _, ability in Abilities:GetChildren() do
		local configFile = require(ability.Config)

		--
		local abilityTemplate = container.AbilityTemplate:Clone()
		abilityTemplate.Name = ability.Name
		abilityTemplate.Holder.Description.Text = configFile.Description
		abilityTemplate.Holder.Title.Text = configFile.Name
		abilityTemplate.Holder.Icon.Image = configFile.Icon
		abilityTemplate.Holder.Price.CurrencyPurchaseGradient.Enabled = configFile.IsCurrencyPurchase
		abilityTemplate.Holder.Price.RobuxPurchaseGradient.Enabled = configFile.IsRobuxPurchase
		abilityTemplate.Holder.Ray.Visible = configFile.IsRobuxPurchase
		abilityTemplate.Visible = true
		abilityTemplate.LayoutOrder = configFile.IsCurrencyPurchase and configFile.Price or -1
		abilityTemplate.Parent = container

		task.spawn(function()
			local price = configFile.IsRobuxPurchase and ShopController:GetPrice(ability.Name) or configFile.Price
			abilityTemplate.Holder.Price.Text = configFile.IsCurrencyPurchase and `${price}`
				or `{utf8.char(0xE002)}{price}`
		end)

		UIController:BindButtonClick(abilityTemplate.Holder.Button, function()
			if configFile.SelectPlayer and LocalPlayer:GetAttribute("InGame") == true then
				SelectPlayerController:OpenForAbility(ability.Name, function(selectedUserId: number)
					requestAbility(ability.Name, selectedUserId)
				end)
				return
			end

			requestAbility(ability.Name)
		end, true, false, { ShowFrame = abilityTemplate.Holder })
	end

	for _, frame in display:GetChildren() do
		if not frame:IsA("Frame") then
			continue
		end

		local abilityName = frame.Name
		local abilityModule = Abilities[abilityName]
		local configFile = require(abilityModule.Config)

		UIController:BindButtonClick(frame.Button, function()
			if configFile.SelectPlayer and LocalPlayer:GetAttribute("InGame") == true then
				SelectPlayerController:OpenForAbility(frame.Name, function(selectedUserId: number)
					requestAbility(frame.Name, selectedUserId)
				end)
				return
			end

			requestAbility(frame.Name)
		end, true, false, { ShowFrame = frame })
	end

	-- Update the abilities
	local function updateAbilities()
		for _, ability in Abilities:GetChildren() do
			local abilityTemplate = container:FindFirstChild(ability.Name)
			local ownedAmount = playerReplica.Data.Abilities[ability.Name] or 0

			if abilityTemplate then
				abilityTemplate.Holder.Amount.Text = `x{ownedAmount}`
			end

			local displayFrame = display:FindFirstChild(ability.Name)
			if displayFrame then
				displayFrame.Amount.Text = `x{ownedAmount}`
			end
		end
	end

	-- Update the abilities when the player data changes
	PlayerDataController:GetReplica():andThen(function(replica)
		playerReplica = replica
		updateAbilities()

		replica:OnChange(function(_, path)
			if path[1] == "Abilities" then
				updateAbilities()
			end
		end)
	end)

	-- Bind the exit button
	UIController:BindButtonClick(holder.Exit, function()
		UIController:CloseFrame(holder)
	end, true)

	-- Bind the hud button
	HudController:BindHudButton("Abilities", function()
		UIController:OpenFrame(holder)
	end)
end

function AbilitiesController:OnInit()
	PlayerDataController = require(script.Parent.PlayerDataController)
	ShopController = require(script.Parent.ShopController)
	UIController = require(script.Parent.UIController)
	HudController = require(script.Parent.HudController)
	SelectPlayerController = require(script.Parent.SelectPlayerController)
	RoundController = require(script.Parent.RoundController)

	self.UI = PlayerGui:WaitForChild("AbilitiesUI")
	self.TimeStopFrame = self.UI.TimeStop

	for _, ability in Abilities:GetChildren() do
		self._abilities[ability.Name] = require(ability.Client)
	end
end

function AbilitiesController:OnStart()
	self.UseAbilityEvent:Connect(function(data)
		local ability = data[1]
		local role = data[2]

		if ability == "TimerReveal" and role == "Activator" then
			self:OpenTimerReveal()
		end

		local abilityModule = self._abilities[ability]
		if not abilityModule then
			warn(`Ability {ability} not found.`)
			return
		end

		if role == "Victim" and abilityModule.OnVictim then
			abilityModule.OnVictim()
		elseif role == "Activator" and abilityModule.OnActivated then
			abilityModule.OnActivated()
		end
	end)

	task.spawn(AbilitiesController._setupUI, self)
end

return AbilitiesController
