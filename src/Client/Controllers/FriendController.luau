-- Services
local AvatarEditorService = game:GetService("AvatarEditorService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage.Packages
local TopbarPlus = require(Packages.TopbarPlus)

-- Local Player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

--
local PlayerDataController

--
local SHOW_RANDOM_FRIEND_INVITE_FREQUENCE = 5 * 60 -- every 5 minutes

--
local FriendController = {}

-- Prompts the friend invite UI
function FriendController:OpenFriendInvitePrompt()
	local success, canInvite = pcall(function()
		return SocialService:CanSendGameInviteAsync(LocalPlayer)
	end)

	if not success or not canInvite then
		return
	end

	SocialService:PromptGameInvite(LocalPlayer)
end

-- Invites a specific friend
function FriendController:InviteFriend(friendUserId: number)
	local experienceInviteOption = Instance.new("ExperienceInviteOptions")
	experienceInviteOption.InviteUser = friendUserId

	SocialService:PromptGameInvite(LocalPlayer, experienceInviteOption)
end

-- Sends a random friend request
function FriendController:SendRandomFriendRequest()
	local attempt = 0
	local function getPlayer(): Player
		local players = Players:GetPlayers()
		local randomIndex = math.random(1, #players)

		attempt = attempt + 1
		if attempt > 5 then
			return nil
		end

		if players[randomIndex] == LocalPlayer then
			return getPlayer()
		end

		return players[randomIndex]
	end

	local randomPlayer = getPlayer()
	if not randomPlayer then
		return
	end

	StarterGui:SetCore("PromptSendFriendRequest", randomPlayer)
end

-- Starts the random friend invite, the thing on the bottom left
function FriendController:_runRandomInviteFriend()
	local currentRandomFriendId
	local clickBindable = Instance.new("BindableFunction")
	clickBindable.OnInvoke = function(response)
		if response == "Yes!" then
			self:InviteFriend(currentRandomFriendId)
		end
	end

	while true do
		task.wait(SHOW_RANDOM_FRIEND_INVITE_FREQUENCE)

		local success, onlineFriends = pcall(function()
			return LocalPlayer:GetFriendsOnline()
		end)

		if not success or not onlineFriends or #onlineFriends == 0 then
			continue
		end

		local randomFriend = onlineFriends[math.random(1, #onlineFriends)]

		local success, friendIcon = pcall(function()
			return Players:GetUserThumbnailAsync(
				randomFriend.VisitorId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size420x420
			)
		end)

		if not success then
			continue
		end

		currentRandomFriendId = randomFriend.VisitorId
		StarterGui:SetCore("SendNotification", {
			Title = randomFriend.DisplayName,
			Icon = friendIcon,
			Text = "Your friend wants to play with you! Want to invite them?",
			Duration = 10,
			Button1 = "Yes!",
			Button2 = "No",
			Callback = clickBindable,
		})
	end
end

--
function FriendController:OnInit()
	PlayerDataController = require(script.Parent.PlayerDataController)
end

function FriendController:OnStart()
	task.spawn(FriendController._runRandomInviteFriend, self)

	--
	PlayerDataController:GetReplica():andThen(function(replica)
		replica:OnSet({ "GamesPlayed" }, function(newGamesPlayed, oldGamesPlayed)
			if oldGamesPlayed == 0 and newGamesPlayed == 1 then
				AvatarEditorService:PromptSetFavorite(112106880997084, Enum.AvatarItemType.Asset, true)
			end
		end)
	end)

	local friendIcon = TopbarPlus.new()
	friendIcon:setImage("rbxassetid://78605640824200")
	friendIcon:setLabel("Invite Friends")
	friendIcon:setOrder(2)
	friendIcon:setRight()
	friendIcon:oneClick(true)

	friendIcon.selected:Connect(function()
		self:OpenFriendInvitePrompt()
	end)
end

return FriendController
