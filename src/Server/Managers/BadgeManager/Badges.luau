--[[ 
	OnInitCallback: This function runs when the BadgeService is initialized.
	It is best to attach listeners in this function. (SHOULD ONLY BE CALLED ONCE!!!) 
--]]

--[[
	toAwardCallback: This function should be called when the condition for awarding
	the badge is met on your listener. It will give the badge to the player.
--]]

export type Badge = {
	Name: string,
	Key: string,
	BadgeId: number,
	OnInitCallback: (toAwardCallback: (player: Player, badgeKey: number, announce: boolean?) -> ()) -> (),
}

local Badges = {}

Badges.Data = {} :: { Badge }

function Badges.GetBadgeFromKey(key: string): Badge
	for _, v in Badges.Data do
		if v.Key == key then
			return v
		end
	end

	return nil
end

function Badges.GetBadges()
	return Badges.Data
end

return Badges
