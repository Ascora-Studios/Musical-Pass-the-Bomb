-- Constants
local DEBUG_MODE = false
local DEBUG_DELAY = 0.1

local Hitbox = {}

-- Helper function to extract character models from overlapping parts
-- @param parts Array of parts that were hit
-- @param ignoreHits Models to ignore
-- @returns Array of unique character models
local function extractCharacters(parts: { BasePart }, ignoreHits: { Model }?): { Model }
	local characterHits = {}

	for _, part in parts do
		local character = part:FindFirstAncestorOfClass("Model")

		if character and character:FindFirstChild("Humanoid") then
			-- Check if character should be ignored
			local shouldIgnore = false
			if ignoreHits then
				shouldIgnore = table.find(ignoreHits, character) ~= nil
			end

			-- Add character if not ignored and not already in list
			if not shouldIgnore and not table.find(characterHits, character) then
				table.insert(characterHits, character)
			end
		end
	end

	return characterHits
end

-- Helper function to create overlap parameters
-- @param ignoreHits Models to ignore in the hit detection
-- @returns OverlapParams configured for exclusion
local function createOverlapParams(ignoreHits: { Model }?): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	if ignoreHits then
		params.FilterDescendantsInstances = ignoreHits
	end

	return params
end

-- Attempts to get all the character models within a given hitbox
-- @param cframe The CFrame position and rotation of the hitbox (or offset if bindToPart is provided)
-- @param size The Vector3 size of the hitbox
-- @param ignoreHits Optional array of character models to ignore
-- @param bindToPart Optional BasePart to weld the hitbox to (if provided, cframe is used as C0 offset)
-- @returns Array of character models that were hit
function Hitbox.Hit(cframe: CFrame, size: Vector3, ignoreHits: { Model }?, bindToPart: BasePart?): { Model }
	-- Create temporary hitbox part
	local hitbox = Instance.new("Part")
	hitbox.Transparency = DEBUG_MODE and 0.5 or 1
	hitbox.CanCollide = false
	hitbox.Size = size

	local weld: Weld? = nil

	if bindToPart and bindToPart:IsA("BasePart") then
		-- Bind hitbox to part using weld
		hitbox.Anchored = false
		hitbox.Massless = true
		hitbox.Parent = bindToPart

		-- Create weld to bind hitbox to the part
		weld = Instance.new("Weld")
		weld.Part0 = bindToPart
		weld.Part1 = hitbox
		weld.C0 = cframe -- Use cframe as the offset
		weld.Parent = hitbox
	else
		-- Place hitbox in workspace at specified position
		hitbox.Anchored = true
		hitbox.CFrame = cframe
		hitbox.Parent = workspace
	end

	-- Get overlapping parts
	local params = createOverlapParams(ignoreHits)
	local overlappingParts = workspace:GetPartsInPart(hitbox, params)

	-- Extract character models from overlapping parts
	local characterHits = extractCharacters(overlappingParts, ignoreHits)

	-- Clean up hitbox part and weld
	local delay = DEBUG_MODE and DEBUG_DELAY or 0
	task.delay(delay, function()
		if weld and weld.Parent then
			weld:Destroy()
		end
		if hitbox and hitbox.Parent then
			hitbox:Destroy()
		end
	end)

	return characterHits
end

-- Attempts to get all the character models within a given part's bounds
-- @param part The BasePart to use as the hitbox
-- @param ignoreHits Optional array of character models to ignore
-- @returns Array of character models that were hit
function Hitbox.HitWithPart(part: BasePart, ignoreHits: { Model }?): { Model }
	if not part or not part:IsA("BasePart") then
		warn("Hitbox.HitWithPart: Invalid part provided")
		return {}
	end

	-- Get overlapping parts using the provided part
	local params = createOverlapParams(ignoreHits)
	local overlappingParts = workspace:GetPartsInPart(part, params)

	-- Extract character models from overlapping parts
	return extractCharacters(overlappingParts, ignoreHits)
end

return Hitbox
