--[[
	SkinController

	Owns the unified skin inventory UI and the rotating world shop pedestals for
	both Bomb skins and Bat skins.

	- World pedestals: workspace.Displays.BombDisplays (1..8) and
	  workspace.Displays.BatDisplays (1..6). Each listens to its shop Replica
	  ("BombShop" / "BatShop") and displays the active skin on each pedestal with
	  a ProximityPrompt that purchases / equips.

	- Inventory UI: PlayerGui.SkinUI
	    Holder.Header.Exit (GuiButton)
	    Holder.Unlocked (TextLabel "UNLOCKED SKINS: x/y" for the current category)
	    Holder.Container.ScrollingFrame  -- cloned tiles go here (both categories)
	    Holder.Categories.Bomb / Holder.Categories.Bat (category buttons)
	    Templates.SkinTemplate
	      Holder.Title (TextLabel)
	      Holder.ViewportFrame
	      Holder.Equip (TextLabel + UIStroke)
	      Holder.Button (TextButton)
	      Holder.UIStroke

	Bat skins are Tools, so we clone their "Handle" mesh for both the inventory
	viewport and the world pedestal display.
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Replica = require(Packages.Replica)
local Trove = require(Packages.Trove)

-- Shared
local Shared = ReplicatedStorage.Shared
local BombSkins = require(Shared.Config.BombSkins)
local BatSkins = require(Shared.Config.BatSkins)
local GameColors = require(Shared.GameColors)

-- Assets
local Assets = ReplicatedStorage.Assets
local UIAssets = Assets.UI

-- Class
local Class = script.Parent.Parent.Class
local Viewport = require(Class.Viewport)

-- Local Player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--
local PlayerDataController
local UIController
local HudController

--
local SkinController = {
	PurchaseBombSkinEvent = BridgeNet2.ReferenceBridge("PurchaseBombSkin"),
	EquipBombSkinEvent = BridgeNet2.ReferenceBridge("EquipBombSkin"),
	UnequipBombSkinEvent = BridgeNet2.ReferenceBridge("UnequipBombSkin"),

	PurchaseBatSkinEvent = BridgeNet2.ReferenceBridge("PurchaseBatSkin"),
	EquipBatSkinEvent = BridgeNet2.ReferenceBridge("EquipBatSkin"),
	UnequipBatSkinEvent = BridgeNet2.ReferenceBridge("UnequipBatSkin"),
}

----------------------------------------------------------------
-- Skin type definitions
----------------------------------------------------------------

-- Generic per-type config so the inventory + shop logic stays shared.
local SKIN_TYPES = {
	Bomb = {
		Config = BombSkins,
		GetFromId = BombSkins.GetBombFromId,
		Priority = BombSkins.Priority,
		Total = #BombSkins.Data,
		OwnedKey = "OwnedBombSkins",
		EquippedKey = "EquippedBombSkin",
		ReplicaToken = "BombShop",
		ReplicaDataKey = "Bombs",
		DisplaysFolder = "BombDisplays",
		GetDisplayPart = function(skinData): (Model | BasePart)?
			return skinData.Model:Clone()
		end,
	},

	Bat = {
		Config = BatSkins,
		GetFromId = BatSkins.GetBatFromId,
		Priority = BatSkins.Priority,
		Total = #BatSkins.Data,
		OwnedKey = "OwnedBatSkins",
		EquippedKey = "EquippedBatSkin",
		ReplicaToken = "BatShop",
		ReplicaDataKey = "Bats",
		DisplaysFolder = "BatDisplays",
		GetDisplayPart = function(skinData): (Model | BasePart)?
			local handle = skinData.Model:FindFirstChild("Handle")
			return handle and handle:Clone()
		end,
	},
}

-- Resolves the right bridge set for a skin type.
local function getBridges(skinType: string)
	if skinType == "Bat" then
		return SkinController.PurchaseBatSkinEvent, SkinController.EquipBatSkinEvent, SkinController.UnequipBatSkinEvent
	end

	return SkinController.PurchaseBombSkinEvent, SkinController.EquipBombSkinEvent, SkinController.UnequipBombSkinEvent
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

local function getRarityFrameColors(rarity: string)
	return GameColors.RARITY_FRAME_COLORS[rarity] or GameColors.RARITY_FRAME_COLORS.Common
end

----------------------------------------------------------------
-- World shop displays
----------------------------------------------------------------

function SkinController:_setupDisplaysForType(skinType: string, typeData)
	local displays = workspace:WaitForChild("Displays")
	local displaysFolder = displays:WaitForChild(typeData.DisplaysFolder)

	local purchaseEvent, equipEvent, unequipEvent = getBridges(skinType)

	local ownedSkins: { [string]: boolean } = {}
	local equippedSkin: string = "Default"

	-- One slot per numbered child part. Each slot owns its prompt + clone
	-- and tears them down when the shop replica re-rolls.
	local slots = {}
	for _, slotPart in displaysFolder:GetChildren() do
		if slotPart:IsA("BasePart") and tonumber(slotPart.Name) then
			slots[tonumber(slotPart.Name)] = {
				Part = slotPart,
				Cleaner = Trove.new(),
				SkinId = nil :: string?,
				Prompt = nil :: ProximityPrompt?,
			}
		end
	end

	local function updatePromptText(slot)
		if not slot.Prompt or not slot.SkinId then
			return
		end

		if equippedSkin == slot.SkinId then
			slot.Prompt.ActionText = "Equipped"
		elseif ownedSkins[slot.SkinId] then
			slot.Prompt.ActionText = "Equip"
		else
			slot.Prompt.ActionText = "Purchase"
		end
	end

	local function updateAllPrompts()
		for _, slot in slots do
			updatePromptText(slot)
		end
	end

	local function setupSlot(slot, skinId: string)
		slot.Cleaner:Clean()
		slot.SkinId = skinId

		local skinData = typeData.GetFromId(skinId)
		if not skinData then
			warn(`Invalid {skinType} skin id on display: {skinId}`)
			return
		end

		local display = typeData.GetDisplayPart(skinData)
		if not display then
			warn(`Could not build display part for {skinType} skin: {skinId}`)
			return
		end

		if display:IsA("Model") then
			display:ScaleTo(1.2)
		end

		local _, displaySize
		if display:IsA("BasePart") then
			displaySize = display.Size
		else
			_, displaySize = display:GetBoundingBox()
		end

		if typeData.ReplicaDataKey == "Bats" then
			display.Anchored = true
			display:PivotTo(
				slot.Part:GetPivot() * CFrame.new(0, displaySize.Y / 2 + 4, 0) * CFrame.Angles(math.rad(-90), 0, 0)
			)
			display:SetAttribute("SpinDirection", Vector3.new(0, 0, 1))
		else
			display:PivotTo(slot.Part:GetPivot() * CFrame.new(0, displaySize.Y / 2 + 2, 0))
		end

		display:AddTag("PartSpin")
		display.Parent = slot.Part

		local details = UIAssets.BombSkinDetails:Clone()
		details.UI.Price.Text = `${skinData.Price}`
		details.UI.Rarity.Text = skinData.Rarity:upper()
		details.UI.Rarity.TextColor3 = GameColors.RARITY_COLORS[skinData.Rarity] or Color3.fromRGB(255, 255, 255)
		details.Parent = slot.Part

		local promptAttachment = Instance.new("Attachment")
		promptAttachment.CFrame = CFrame.new(0, 2.77, 0)
		promptAttachment.Parent = slot.Part

		local prompt = Instance.new("ProximityPrompt")
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.ObjectText = skinData.Name
		prompt.HoldDuration = 0
		prompt.Parent = promptAttachment

		slot.Prompt = prompt
		updatePromptText(slot)

		slot.Cleaner:Add(prompt.Triggered:Connect(function()
			if not slot.SkinId then
				return
			end

			if equippedSkin == slot.SkinId then
				unequipEvent:Fire()
			elseif ownedSkins[slot.SkinId] then
				equipEvent:Fire(slot.SkinId)
			else
				purchaseEvent:Fire(slot.SkinId)
			end
		end))

		slot.Cleaner:Add(function()
			display:Destroy()
			details:Destroy()
			promptAttachment:Destroy()
			slot.SkinId = nil
			slot.Prompt = nil
		end)
	end

	local function applyShop(skins: { string })
		for index, slot in slots do
			local skinId = skins[index]
			if skinId then
				setupSlot(slot, skinId)
			else
				slot.Cleaner:Clean()
			end
		end
	end

	-- Listen to the server's shop replica
	Replica.OnNew(typeData.ReplicaToken, function(replica)
		applyShop(replica.Data[typeData.ReplicaDataKey])

		replica:OnSet({ typeData.ReplicaDataKey }, function(newSkins)
			applyShop(newSkins)
		end)
	end)

	-- Track local ownership + equipped state to keep prompt labels in sync
	PlayerDataController:GetReplica():andThen(function(replica)
		ownedSkins = replica.Data[typeData.OwnedKey] or {}
		equippedSkin = replica.Data[typeData.EquippedKey] or "Default"
		updateAllPrompts()

		replica:OnSet({ typeData.OwnedKey }, function(newOwned)
			ownedSkins = newOwned or {}
			updateAllPrompts()
		end)

		replica:OnSet({ typeData.EquippedKey }, function(newEquipped)
			equippedSkin = newEquipped or "Default"
			updateAllPrompts()
		end)
	end)
end

----------------------------------------------------------------
-- Inventory UI
----------------------------------------------------------------

function SkinController:_setupUI()
	local ui = self.UI
	local holder = ui.Holder
	local templates = ui.Templates
	local container = holder.Container.ScrollingFrame
	local categories = holder.Categories
	local unlockedLabel = holder:FindFirstChild("Unlocked")

	local owned: { [string]: { [string]: boolean } } = { Bomb = {}, Bat = {} }
	local equipped: { [string]: string } = { Bomb = "Default", Bat = "Default" }
	local createdFrames: { [string]: Frame } = {}
	local currentCategory = "Bomb"

	local function refreshUnlockedLabel()
		if not unlockedLabel then
			return
		end

		local typeData = SKIN_TYPES[currentCategory]
		local unlocked = 0
		for _ in owned[currentCategory] do
			unlocked += 1
		end

		unlockedLabel.Text = `UNLOCKED SKINS: {unlocked}/{typeData.Total}`
	end

	local function createSkinFrame(skinType: string, skinId: string)
		local typeData = SKIN_TYPES[skinType]
		local skinData = typeData.GetFromId(skinId)
		if not skinData then
			warn(`Invalid {skinType} skin id when building UI: {skinId}`)
			return
		end

		local frameColors = getRarityFrameColors(skinData.Rarity)

		local template = templates.SkinTemplate:Clone()
		template.Name = `{skinType}_{skinId}`
		template:SetAttribute("SkinCategory", skinType)
		template:SetAttribute("SkinId", skinId)
		template.LayoutOrder = typeData.Priority[skinData.Rarity] or 99

		template.Holder.Title.Text = skinData.Name:upper()
		template.Holder.BackgroundColor3 = frameColors.BackgroundColor

		local stroke = template.Holder:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = frameColors.StrokeColor
		end

		local titleStroke = template.Holder.Title:FindFirstChildOfClass("UIStroke")
		if titleStroke then
			titleStroke.Color = frameColors.TextStrokeColor
		end

		local equipStroke = template.Holder.Equip:FindFirstChildOfClass("UIStroke")
		if equipStroke then
			equipStroke.Color = frameColors.TextStrokeColor
		end

		local viewportFrame = template.Holder:FindFirstChildOfClass("ViewportFrame")
		if viewportFrame then
			local display = typeData.GetDisplayPart(skinData)
			if display then
				if typeData.ReplicaDataKey == "Bats" then
					display:PivotTo(display:GetPivot() * CFrame.Angles(0, math.rad(90), 0))
				end
				Viewport.new(
					display,
					viewportFrame,
					CFrame.new(),
					true,
					holder,
					typeData.ReplicaDataKey == "Bats" and Vector3.new(0, 0, 1) or nil
				)
			end
		end

		template.Visible = skinType == currentCategory
		template.Parent = container

		createdFrames[`{skinType}_{skinId}`] = template

		local _, equipEvent, unequipEvent = getBridges(skinType)
		UIController:BindButtonClick(template.Holder.Button, function()
			if not owned[skinType][skinId] then
				return
			end

			if equipped[skinType] == skinId then
				unequipEvent:Fire()
			else
				equipEvent:Fire(skinId)
			end
		end, true, false, { ShowFrame = template.Holder })
	end

	local function refreshFrames(skinType: string)
		for skinId in owned[skinType] do
			if not createdFrames[`{skinType}_{skinId}`] then
				createSkinFrame(skinType, skinId)
			end
		end

		for _, frame in createdFrames do
			if frame:GetAttribute("SkinCategory") ~= skinType then
				continue
			end

			local skinId = frame:GetAttribute("SkinId")
			local skinData = SKIN_TYPES[skinType].GetFromId(skinId)
			if not skinData then
				continue
			end

			local isEquipped = equipped[skinType] == skinId
			local rarityFrameColors = getRarityFrameColors(skinData.Rarity)

			frame.Holder.Equip.Text = isEquipped and "Equipped" or "Equip"
			frame.Holder.Equip.TextColor3 = isEquipped and GameColors.EQUIPPED_COLORS.TextColor
				or Color3.fromRGB(255, 255, 255)

			local equipStroke = frame.Holder.Equip:FindFirstChildOfClass("UIStroke")
			if equipStroke then
				equipStroke.Color = isEquipped and GameColors.EQUIPPED_COLORS.TextStrokeColor
					or rarityFrameColors.TextStrokeColor
			end
		end

		if skinType == currentCategory then
			refreshUnlockedLabel()
		end
	end

	local function selectCategory(skinType: string)
		currentCategory = skinType

		for _, frame in createdFrames do
			frame.Visible = frame:GetAttribute("SkinCategory") == skinType
		end

		refreshUnlockedLabel()
	end

	PlayerDataController:GetReplica():andThen(function(replica)
		for skinType, typeData in SKIN_TYPES do
			owned[skinType] = replica.Data[typeData.OwnedKey] or {}
			equipped[skinType] = replica.Data[typeData.EquippedKey] or "Default"
			refreshFrames(skinType)

			replica:OnSet({ typeData.OwnedKey }, function(newOwned)
				owned[skinType] = newOwned or {}
				refreshFrames(skinType)
			end)

			replica:OnSet({ typeData.EquippedKey }, function(newEquipped)
				equipped[skinType] = newEquipped or "Default"
				refreshFrames(skinType)
			end)
		end

		selectCategory(currentCategory)
	end)

	UIController:BindButtonClick(categories.Bomb, function()
		selectCategory("Bomb")
	end, true)

	UIController:BindButtonClick(categories.Bat, function()
		selectCategory("Bat")
	end, true)

	HudController:BindHudButton("Skin", function()
		UIController:OpenFrame(holder)
	end)

	local exitButton = holder:FindFirstChild("Header") and holder.Header:FindFirstChild("Exit")
		or holder:FindFirstChild("Exit")
	if exitButton then
		UIController:BindButtonClick(exitButton, function()
			UIController:CloseFrame(holder)
		end, true)
	end
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function SkinController:OnInit()
	PlayerDataController = require(script.Parent.PlayerDataController)
	UIController = require(script.Parent.UIController)
	HudController = require(script.Parent.HudController)

	self.UI = PlayerGui:WaitForChild("SkinUI")
end

function SkinController:OnStart()
	for skinType, typeData in SKIN_TYPES do
		task.spawn(SkinController._setupDisplaysForType, self, skinType, typeData)
	end

	task.spawn(SkinController._setupUI, self)
end

return SkinController
