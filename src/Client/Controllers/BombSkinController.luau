--[[
	BombSkinController

	Owns the bomb skin inventory UI and the rotating world shop pedestals.

	- World pedestals: workspace.BombDisplays children named "1".."8"
	  Listens to the "BombShop" Replica and displays the active skin model
	  on each pedestal with a ProximityPrompt that purchases / equips.

	- Inventory UI: PlayerGui.BombSkinUI
	  Layout (mirrors AbilitiesUI):
	    Holder.Header.Exit (GuiButton)
	    Holder.Unlocked (TextLabel "UNLOCKED SKINS: x/y")
	    Holder.Container.ScrollingFrame  -- cloned templates go here
	    Templates.BombSkinTemplate
	      Holder.Title (TextLabel)
	      Holder.ViewportFrame
	      Holder.Equip (TextLabel + UIStroke)
	      Holder.Button (TextButton)
	      Holder.UIStroke
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
local BombSkinController = {
	PurchaseBombSkinEvent = BridgeNet2.ReferenceBridge("PurchaseBombSkin"),
	EquipBombSkinEvent = BridgeNet2.ReferenceBridge("EquipBombSkin"),
	UnequipBombSkinEvent = BridgeNet2.ReferenceBridge("UnequipBombSkin"),
}

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

local function getRarityColor(rarity: string): Color3
	return GameColors.RARITY_COLORS[rarity] or Color3.fromRGB(255, 255, 255)
end

local function getRarityFrameColors(rarity: string)
	return GameColors.RARITY_FRAME_COLORS[rarity] or GameColors.RARITY_FRAME_COLORS.Common
end

----------------------------------------------------------------
-- World shop displays
----------------------------------------------------------------

function BombSkinController:_setupDisplays()
	local bombDisplays = workspace:WaitForChild("BombDisplays")

	local ownedSkins: { [string]: boolean } = {}
	local equippedSkin: string = "Default"

	-- One slot per numbered child part. Each slot owns its prompt + clone
	-- and tears them down when the shop replica re-rolls.
	local slots = {}
	for _, slotPart in bombDisplays:GetChildren() do
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

		local skinData = BombSkins.GetBombFromId(skinId)
		if not skinData then
			warn(`Invalid skin id on bomb display: {skinId}`)
			return
		end

		local model = skinData.Model:Clone()
		model:ScaleTo(1.2)
		model:AddTag("PartSpin")
		model:SetAttribute("SpinSpeed", 0.25)
		model.Parent = slot.Part

		local _, modelSize = model:GetBoundingBox()
		model:PivotTo(slot.Part:GetPivot() * CFrame.new(0, modelSize.Y / 2 + 2, 0))

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
				self.UnequipBombSkinEvent:Fire()
			elseif ownedSkins[slot.SkinId] then
				self.EquipBombSkinEvent:Fire(slot.SkinId)
			else
				self.PurchaseBombSkinEvent:Fire(slot.SkinId)
			end
		end))

		slot.Cleaner:Add(function()
			model:Destroy()
			details:Destroy()
			promptAttachment:Destroy()
			slot.SkinId = nil
			slot.Prompt = nil
		end)
	end

	local function applyShop(bombs: { string })
		for index, slot in slots do
			local skinId = bombs[index]
			if skinId then
				setupSlot(slot, skinId)
			else
				slot.Cleaner:Clean()
			end
		end
	end

	-- Listen to the server's BombShop replica
	Replica.OnNew("BombShop", function(replica)
		applyShop(replica.Data.Bombs)

		replica:OnSet({ "Bombs" }, function(newBombs)
			applyShop(newBombs)
		end)
	end)

	-- Track local ownership + equipped state to keep prompt labels in sync
	PlayerDataController:GetReplica():andThen(function(replica)
		ownedSkins = replica.Data.OwnedBombSkins or {}
		equippedSkin = replica.Data.EquippedBombSkin or "Default"
		updateAllPrompts()

		replica:OnSet({ "OwnedBombSkins" }, function(newOwned)
			ownedSkins = newOwned or {}
			updateAllPrompts()
		end)

		replica:OnSet({ "EquippedBombSkin" }, function(newEquipped)
			equippedSkin = newEquipped or "Default"
			updateAllPrompts()
		end)
	end)
end

----------------------------------------------------------------
-- Inventory UI
----------------------------------------------------------------

function BombSkinController:_setupUI()
	local ui = self.UI
	local holder = ui.Holder
	local templates = ui.Templates
	local container = holder.Container.ScrollingFrame

	local ownedSkins: { [string]: boolean } = {}
	local equippedSkin: string = "Default"
	local createdFrames: { [string]: Frame } = {}

	local function createSkinFrame(skinId: string)
		local skinData = BombSkins.GetBombFromId(skinId)
		if not skinData then
			warn(`Invalid bomb skin id when building UI: {skinId}`)
			return
		end

		local frameColors = getRarityFrameColors(skinData.Rarity)

		local template = templates.BombSkinTemplate:Clone()
		template.Name = skinId
		template.LayoutOrder = BombSkins.Priority[skinData.Rarity] or 99

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
			Viewport.new(skinData.Model:Clone(), viewportFrame, CFrame.new(), true, holder)
		end

		template.Visible = true
		template.Parent = container

		createdFrames[skinId] = template

		UIController:BindButtonClick(template.Holder.Button, function()
			if not ownedSkins[skinId] then
				return
			end

			if equippedSkin == skinId then
				self.UnequipBombSkinEvent:Fire()
			else
				self.EquipBombSkinEvent:Fire(skinId)
			end
		end, true, false, { ShowFrame = template.Holder })
	end

	local function refreshFrames()
		local unlocked = 0
		for skinId in ownedSkins do
			unlocked += 1
			if not createdFrames[skinId] then
				createSkinFrame(skinId)
			end
		end

		for skinId, frame in createdFrames do
			local skinData = BombSkins.GetBombFromId(skinId)
			if not skinData then
				continue
			end

			local isEquipped = equippedSkin == skinId
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

		local totalSkins = #BombSkins.Data
		local unlockedLabel = holder:FindFirstChild("Unlocked")
		if unlockedLabel then
			unlockedLabel.Text = `UNLOCKED SKINS: {unlocked}/{totalSkins}`
		end
	end

	PlayerDataController:GetReplica():andThen(function(replica)
		ownedSkins = replica.Data.OwnedBombSkins or {}
		equippedSkin = replica.Data.EquippedBombSkin or "Default"
		refreshFrames()

		replica:OnSet({ "OwnedBombSkins" }, function(newOwned)
			ownedSkins = newOwned or {}
			refreshFrames()
		end)

		replica:OnSet({ "EquippedBombSkin" }, function(newEquipped)
			equippedSkin = newEquipped or "Default"
			refreshFrames()
		end)
	end)

	HudController:BindHudButton("BombSkin", function()
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

function BombSkinController:OnInit()
	PlayerDataController = require(script.Parent.PlayerDataController)
	UIController = require(script.Parent.UIController)
	HudController = require(script.Parent.HudController)

	self.UI = PlayerGui:WaitForChild("BombSkinUI")
end

function BombSkinController:OnStart()
	task.spawn(BombSkinController._setupDisplays, self)
	task.spawn(BombSkinController._setupUI, self)
end

return BombSkinController
