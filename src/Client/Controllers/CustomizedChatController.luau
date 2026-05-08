-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages

local CHAT_TAGS = {
	["VIP"] = "<font color='#ffd902'>[VIP]</font>",
}

local CHAT_BOX_MESSAGES = {}

local CHAT_BOX_MESSAGES_COLOR = {
	Color3.fromHex("#ffff7f"),
	Color3.fromHex("#ffaaff"),
	Color3.fromHex("#aaffff"),
	Color3.fromHex("#ff7f7f"),
	Color3.fromHex("#7fff7f"),
}

local MIN_TIME_CHAT_MESSAGE = 7 * 60
local MAX_TIME_CHAT_MESSAGE = 10 * 60

--
local ChatTagController = {}

--
function ChatTagController:OnInit()
	-- Setup tag adder
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local textChatProperties = Instance.new("TextChatMessageProperties")
		if not message.TextSource then
			return
		end

		-- Get player
		local playerChatted = Players:GetPlayerByUserId(message.TextSource.UserId)
		if not playerChatted then
			return
		end

		--
		local isPlayerVIP = playerChatted:HasTag("VIP")

		-- Add VIP Tag
		local tagPrefix = ""
		if isPlayerVIP then
			tagPrefix = `{tagPrefix} {CHAT_TAGS.VIP}`
		end

		-- Add player title on Tag
		tagPrefix = `{tagPrefix}`

		-- Set Prefix
		textChatProperties.PrefixText = `{tagPrefix} {message.PrefixText}`
		return textChatProperties
	end

	-- Connect the loop for the chatbox server messages
	--[[task.spawn(function()
		while true do
			local randomText = CHAT_BOX_MESSAGES[math.random(1, #CHAT_BOX_MESSAGES)]
			TextChatService.TextChannels.RBXSystem:DisplaySystemMessage(
				`<font color="#{CHAT_BOX_MESSAGES_COLOR[math.random(1, #CHAT_BOX_MESSAGES_COLOR)]:ToHex()}">{randomText}</font>`
			)

			-- Cooldown with a random amount
			task.wait(math.random(MIN_TIME_CHAT_MESSAGE, MAX_TIME_CHAT_MESSAGE))
		end
	end)]]
end

function ChatTagController:OnStart() end

return ChatTagController
