-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)
local Spr = require(Packages.Spr)

-- Player
local LPlayer = Players.LocalPlayer
local PlayerGui = LPlayer.PlayerGui

local Camera = workspace.CurrentCamera

--
local SoundController

--
local UIController = {
	OnFrameOpened = Signal.new(),
	OnFrameClosed = Signal.new(),

	_currentOpenedFrame = nil,
}

--[[
	Opens up the frame that we provide:
	- frame: Frame - The frame to open
	- independent: boolean? - Whether or not this frame is independent of others
	if its not independent it will close any other open frames
]]
function UIController:OpenFrame(frame: Frame, independent: boolean?)
	local uiScale = frame:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = frame
	end

	if not frame:GetAttribute("OrigPosition") then
		frame:SetAttribute("OrigPosition", frame.Position)
	end

	-- Close if already opened
	if self._currentOpenedFrame == frame then
		self:CloseFrame(frame)
		return
	end

	-- Setup the effect
	frame.Position = frame:GetAttribute("OrigPosition") + UDim2.fromScale(0, 0.1)
	uiScale.Scale = 0.97

	-- Start the effect
	Spr.target(uiScale, 0.6, 3.5, { Scale = 1 })
	Spr.target(frame, 0.55, 3.5, { Position = frame:GetAttribute("OrigPosition") })
	frame.Visible = true

	if not independent then
		if self._currentOpenedFrame and self._currentOpenedFrame ~= frame then
			self:CloseFrame(self._currentOpenedFrame)
		end

		Spr.target(Camera, 0.7, 2.5, { FieldOfView = 75 })
		self._currentOpenedFrame = frame
	else
		frame:AddTag("IndependentFrame")
	end

	self.OnFrameOpened:Fire(frame)
end

--[[
	Closes the frame that we provide
	- frame: Frame - The frame to close
]]
function UIController:CloseFrame(frame: Frame)
	--
	frame.Visible = false

	if self._currentOpenedFrame == frame then
		self._currentOpenedFrame = nil
	end

	if not frame:HasTag("IndependentFrame") then
		Spr.target(Camera, 0.7, 2.5, { FieldOfView = 70 })
	end

	frame:RemoveTag("IndependentFrame")

	self.OnFrameClosed:Fire(frame)
end

--
function UIController:BindButtonClick(
	button: GuiButton,
	clickCallback: () -> (),
	bindEffect: boolean?,
	disconnectAfter: boolean?,
	bindEffectProperties: {
		ShowFrame: Frame?,
		ButtonDownScale: number?,
		ButtonHoverscale: number?,
		OnHoverCallback: () -> ()?,
		OnHoverEndCallback: () -> ()?,
		ClickSoundName: string?,
		ButtonNormalScale: number?,
	}?
): { Disconnect: () -> () }
	--
	local cleaner = Trove.new()

	cleaner:Add(button.MouseButton1Click:Connect(function()
		if clickCallback then
			task.spawn(clickCallback)
		end

		if disconnectAfter then
			cleaner:Destroy()
		end
	end))

	if bindEffect then
		bindEffectProperties = bindEffectProperties or {}
		cleaner:Add(self:BindButtonEffect(button, bindEffectProperties))
	end

	return {
		Disconnect = function()
			cleaner:Destroy()
		end,
	}
end

function UIController:BindButtonEffect(
	button: GuiButton,
	properties: {
		ShowFrame: Frame?,
		ButtonDownScale: number?,
		ButtonHoverscale: number?,
		OnHoverCallback: () -> ()?,
		OnHoverEndCallback: () -> ()?,
		ClickSoundName: string?,
		ButtonNormalScale: number?,
	}?
)
	--
	local cleaner = Trove.new()

	--
	properties = properties or {}
	local showFrame = properties.ShowFrame or button
	local buttonDownScale = properties.ButtonDownScale
	local buttonHoverscale = properties.ButtonHoverscale
	local onHoverCallback = properties.OnHoverCallback
	local OnHoverEndCallback = properties.OnHoverEndCallback
	local clickSoundName = properties.ClickSoundName
	local buttonNormalScale = properties.ButtonNormalScale

	--
	local uiScale = showFrame:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = showFrame
	end

	local damping = 0.5
	local frequency = 6

	local buttonSprings = {
		Press = function()
			Spr.target(uiScale, damping, frequency, {
				Scale = buttonDownScale or 0.93,
			})
		end,

		Hover = function()
			Spr.target(uiScale, damping, frequency, {
				Scale = buttonHoverscale or 1.06,
			})
		end,

		Normal = function()
			Spr.target(uiScale, damping, frequency, {
				Scale = buttonNormalScale or 1,
			})
		end,
	}

	--
	cleaner:Add(button.MouseButton1Down:Connect(function()
		SoundController:PlaySound(clickSoundName or "InteractUI")
		buttonSprings.Press()
	end))

	cleaner:Add(button.MouseButton1Up:Connect(function()
		buttonSprings.Normal()
	end))

	cleaner:Add(button.MouseEnter:Connect(function()
		if onHoverCallback then
			onHoverCallback()
		end

		SoundController:PlaySound("ButtonHover")
		buttonSprings.Hover()
	end))

	cleaner:Add(button.MouseLeave:Connect(function()
		if OnHoverEndCallback then
			OnHoverEndCallback()
		end

		buttonSprings.Normal()
	end))

	cleaner:Add(buttonSprings.Normal)

	return {
		Disconnect = function()
			cleaner:Destroy()
		end,
	}
end

function UIController:OnInit()
	SoundController = require(script.Parent.SoundController)

	--
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	-- Disable Reset Button
	task.spawn(function()
		repeat
			local success = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", false)
			end)
			task.wait(1)
		until success
	end)
end

function UIController:OnStart() end

return UIController
