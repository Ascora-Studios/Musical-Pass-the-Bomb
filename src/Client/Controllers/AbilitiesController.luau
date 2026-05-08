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

--
local AbilitiesController = {
	--
	UseAbilityEvent = BridgeNet2.ReferenceBridge("UseAbility"),
	OnUseAbilityEvent = BridgeNet2.ReferenceBridge("OnUseAbility"),
	RequestAbilityPurchaseEvent = BridgeNet2.ReferenceBridge("RequestAbilityPurchase"),

	_abilities = {},
}

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

	-- Update the abilities
	local function updateAbilities()
		for _, ability in Abilities:GetChildren() do
			local abilityTemplate = container:FindFirstChild(ability.Name)
			if abilityTemplate then
				local ownedAmount = playerReplica.Data.Abilities[ability.Name] or 0
				abilityTemplate.Holder.Amount.Text = `x{ownedAmount}`
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

	self.UI = PlayerGui:WaitForChild("AbilitiesUI")

	for _, ability in Abilities:GetChildren() do
		self._abilities[ability.Name] = require(ability.Client)
	end
end

function AbilitiesController:OnStart()
	self.UseAbilityEvent:Connect(function(data)
		local ability = data[1]
		local role = data[2]

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
