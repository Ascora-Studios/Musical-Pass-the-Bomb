local RandomUtil = {}

-- Accepts either an existing Random instance (preferred for repeated draws so
-- successive calls don't keep re-seeding to the same value) or a numeric seed.
-- Returns a Random you can draw from.
type RandomLike = number | Random
local function resolveRng(seedOrRng: RandomLike?): Random
	if typeof(seedOrRng) == "Random" then
		return seedOrRng
	end
	return Random.new(seedOrRng or tick())
end

--[[
	Selects a random item from weighted data.
	@param data Array of {value, weight} pairs, e.g., { {"Common", 20}, {"Rare", 5} }
	@param seedOrRng Optional seed (number) or an existing Random instance to draw from
	@return The selected value and the full entry {value, weight}
]]
function RandomUtil.GetResultFromWeight(data: { table }, seedOrRng: RandomLike?)
	local totalWeight = 0
	for _, entry in data do
		totalWeight += entry[2]
	end

	if totalWeight <= 0 then
		return nil, nil
	end

	local rng = resolveRng(seedOrRng)
	local chosen = rng:NextNumber(0, totalWeight)

	local accumulatedWeight = 0
	for _, entry in data do
		accumulatedWeight += entry[2]
		if chosen <= accumulatedWeight then
			return entry[1], entry
		end
	end

	-- Fallback (should never reach here)
	return data[#data][1], data[#data]
end

--[[
	Gets a random value from the data table.
	If the value is in the ignoreList, it will retry up to 10 times.
	@param data Array of values to choose from
	@param ignoreList Single value or array of values to exclude
	@return Random value not in ignoreList, or nil if all attempts failed
]]
function RandomUtil.GetRandomFromArray(data: { any }, ignoreList: any?): any?
	if #data == 0 then
		return nil
	end

	local rng = Random.new()
	local maxAttempts = 10

	for attempt = 1, maxAttempts do
		local randomIndex = rng:NextInteger(1, #data)
		local currentRandom = data[randomIndex]

		-- Check if value should be ignored
		local shouldIgnore = false
		if ignoreList then
			if typeof(ignoreList) == "table" then
				shouldIgnore = table.find(ignoreList, currentRandom) ~= nil
			else
				shouldIgnore = ignoreList == currentRandom
			end
		end

		if not shouldIgnore then
			return currentRandom
		end
	end

	return nil
end

--[[
	Gets a random point on the part, constrained to the XZ plane (Y = 0).
	@param part The part to sample from
	@return A random Vector3 position on the part's XZ plane
]]
function RandomUtil.GetRandomXZFromPart(part: BasePart): Vector3
	local partSize = part.Size
	local rng = Random.new()
	local randomOffset =
		Vector3.new(rng:NextNumber(-partSize.X / 2, partSize.X / 2), 0, rng:NextNumber(-partSize.Z / 2, partSize.Z / 2))
	return (part.CFrame * CFrame.new(randomOffset)).Position
end

--[[
	Gets a random point anywhere within the part's bounds.
	@param part The part to sample from
	@return A random Vector3 position within the part
]]
function RandomUtil.GetRandomXYZFromPart(part: BasePart): Vector3
	local partSize = part.Size
	local rng = Random.new()
	local randomOffset = Vector3.new(
		rng:NextNumber(-partSize.X / 2, partSize.X / 2),
		rng:NextNumber(-partSize.Y / 2, partSize.Y / 2),
		rng:NextNumber(-partSize.Z / 2, partSize.Z / 2)
	)
	return (part.CFrame * CFrame.new(randomOffset)).Position
end

--[[
	Gets a random number between min and max (inclusive).
	@param min Minimum value
	@param max Maximum value
	@param seedOrRng Optional seed (number) or an existing Random instance to draw from
	@return Random number in range [min, max)
]]
function RandomUtil.GetRandomFromMinMax(min: number, max: number, seedOrRng: RandomLike?): number
	local rng = resolveRng(seedOrRng)
	return rng:NextNumber(min, max)
end

--[[
	Gets a random integer between min and max (inclusive).
	@param min Minimum value
	@param max Maximum value
	@param seedOrRng Optional seed (number) or an existing Random instance to draw from
	@return Random integer in range [min, max]
]]
function RandomUtil.GetRandomIntFromMinMax(min: number, max: number, seedOrRng: RandomLike?): number
	local rng = resolveRng(seedOrRng)
	return rng:NextInteger(min, max)
end

--[[
	Returns true with the given percentage chance.
	@param chance Percentage chance (0-100) to return true
	@param seedOrRng Optional seed (number) or an existing Random instance to draw from
	@return true if chance succeeds, false otherwise
]]
function RandomUtil.RollChance(chance: number, seedOrRng: RandomLike?): boolean
	local rng = resolveRng(seedOrRng)
	return rng:NextNumber(0, 100) < chance
end

return RandomUtil
