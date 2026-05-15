-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

-- Packages
local Packages = ReplicatedStorage.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local TopbarPlus = require(Packages.TopbarPlus)

--
local TIME_THRESHOLD = 0.05

--
local SoundController = {
	PlaySoundEvent = BridgeNet2.ReferenceBridge("PlaySound"),
	PlayRandomSoundEvent = BridgeNet2.ReferenceBridge("PlayRandomSoundInFolder"),
	ReplicateToOthersEvent = BridgeNet2.ReferenceBridge("ReplicateSoundToOthers"),

	_lastPlayedSounds = {},
	_currentGameMusic = nil,
	_currentBGMType = nil,
	_muted = false,
}

--
local function createLocationPart(position: Vector3): BasePart
	local locationPart = Instance.new("Part")
	locationPart.Anchored = true
	locationPart.CanCollide = false
	locationPart.Transparency = 1
	locationPart.Size = Vector3.one
	locationPart.Position = position
	locationPart.Parent = workspace.Terrain
	return locationPart
end

-- Plays a sound at a location with optional custom properties
-- @param soundName The name of the sound to play
-- @param location The location to play the sound at (CFrame, Vector3, or Part)
-- @param customProperties Optional custom properties to apply to the sound
-- @param limit Whether to limit overlapping sounds
-- @param replicate Whether to replicate the sound to other clients
-- @returns Sound The sound instance that was played
function SoundController:PlaySound(
	soundName: string,
	location: CFrame | Vector3 | Part?,
	customProperties: { [any]: any }?,
	limit: boolean?,
	replicate: boolean?
): Sound?
	local sound: Sound? = SoundService:FindFirstChild(soundName, true)
	if not sound then
		warn(`Sound {soundName} not found in SoundService`)
		return
	end

	if limit and self._lastPlayedSounds[soundName] then
		return
	end

	local soundClone = sound:Clone()

	if customProperties then
		for property, val in customProperties do
			soundClone[property] = val
		end
	end

	-- Convert CFrame to Vector3 if needed
	if typeof(location) == "CFrame" then
		location = location.Position
	end

	-- Set sound parent based on location type
	local locationPart: BasePart?
	if typeof(location) == "Vector3" then
		locationPart = createLocationPart(location)
		soundClone.Parent = locationPart
	elseif location and location:IsA("BasePart") then
		soundClone.Parent = location
	else
		soundClone.Parent = SoundService.SFX
	end

	if replicate then
		self.ReplicateToOthersEvent:Fire({ soundName, location, customProperties, limit })
	end

	soundClone.Name = `{soundName}_Played`
	soundClone.SoundGroup = SoundService.SFX
	soundClone:Play()

	-- Cleanup sound after it finishes
	task.delay(sound.TimeLength + 1, function()
		if soundClone.Looped then
			return
		end

		if soundClone then
			soundClone:Destroy()
		end

		if locationPart then
			locationPart:Destroy()
		end
	end)

	-- Prevent overlapping sounds
	if limit then
		self._lastPlayedSounds[soundName] = true
		task.delay(TIME_THRESHOLD, function()
			self._lastPlayedSounds[soundName] = nil
		end)
	end

	return soundClone
end

-- Stops a sound with optional fade out
-- @param soundName The name of the sound to stop
-- @param location Optional location to search for the sound (defaults to ReplicatedStorage)
function SoundController:StopSound(soundName: string, location: Instance?)
	local soundLocation = location or ReplicatedStorage
	local sound: Sound? = soundLocation:FindFirstChild(soundName)

	if not sound then
		return
	end

	if sound.Playing then
		local tween = TweenService:Create(sound, TweenInfo.new(1), { Volume = 0 })
		tween:Play()
		tween.Completed:Connect(function()
			if sound then
				sound:Destroy()
			end
		end)
	else
		sound:Destroy()
	end
end

-- Sets the core BGM volume with optional tween duration
-- @param volume The target volume (0-1)
-- @param setDuration Optional duration for the volume tween (default: 0)
function SoundController:SetBGMCoreVolume(volume: number, setDuration: number?)
	local coreBGM = SoundService:FindFirstChild("CoreBGM", true)
	if not coreBGM then
		warn("CoreBGM Sound Group not found in SoundService")
		return
	end

	TweenService:Create(coreBGM, TweenInfo.new(setDuration or 0, Enum.EasingStyle.Linear), {
		Volume = volume,
	}):Play()
end

-- Plays a random sound from a folder
-- @param folderName The name of the folder containing sounds
-- @param params Optional parameters to pass to PlaySound
function SoundController:PlayRandomSoundInFolder(folderName: string, params: { any }?)
	local soundFolder = SoundService:FindFirstChild(folderName, true)
	if not soundFolder then
		warn(`Sound folder {folderName} not found`)
		return
	end

	local sounds = soundFolder:GetChildren()
	if #sounds == 0 then
		warn(`Sound folder {folderName} is empty`)
		return
	end

	local randomSound: Sound = sounds[math.random(1, #sounds)]
	self:PlaySound(randomSound.Name, table.unpack(params or {}))
end

-- Starts the background music cycle
function SoundController:_startBackgroundMusicCycle()
	local backgroundMusic = SoundService:FindFirstChild("BackgroundMusic", true)
	if not backgroundMusic then
		warn("BackgroundMusic Sound Group not found in SoundService")
		return
	end

	while true do
		for _, sound: Sound in backgroundMusic:GetChildren() do
			if not sound:IsA("Sound") then
				continue
			end

			sound:Play()
			sound.Ended:Wait()
		end
		task.wait(1)
	end
end

-- Mutes or unmutes the background music
-- @param toggle Whether to mute (true) or unmute (false)
function SoundController:MuteBGM(toggle: boolean)
	local backgroundMusic = SoundService:FindFirstChild("BackgroundMusic", true)
	if not backgroundMusic then
		warn("BackgroundMusic Sound Group not found in SoundService")
		return
	end

	TweenService:Create(backgroundMusic, TweenInfo.new(1), {
		Volume = toggle and 0 or 1,
	}):Play()
end

-- Turns the game music on or off
-- @param enabled Whether to enable (true) or disable (false) the game music
-- @param fadeDuration Optional duration for the volume fade (default: 1)
function SoundController:ToggleGameMusic(enabled: boolean, fadeDuration: number?)
	local gameMusic = SoundService:FindFirstChild("GameMusic", true)
	if not gameMusic then
		warn("GameMusic Sound Group not found in SoundService")
		return
	end

	TweenService:Create(gameMusic, TweenInfo.new(fadeDuration or 1, Enum.EasingStyle.Linear), {
		Volume = enabled and 1 or 0,
	}):Play()
end

function SoundController:SwitchBGM(bgmType: "Game" | "Background" | "Fight", switchDuration: number?)
	local backgroundMusic = SoundService:FindFirstChild("BackgroundMusic", true)
	local gameMusic = SoundService:FindFirstChild("GameMusic", true)
	local fightSound = SoundService:FindFirstChild("FightSound", true)

	if self._currentBGMType and self._currentBGMType == bgmType then
		return
	end

	TweenService:Create(backgroundMusic, TweenInfo.new(switchDuration or 1, Enum.EasingStyle.Linear), {
		Volume = bgmType == "Background" and 1 or 0,
	}):Play()
	TweenService:Create(gameMusic, TweenInfo.new(switchDuration or 1, Enum.EasingStyle.Linear), {
		Volume = bgmType == "Game" and 1 or 0,
	}):Play()
	TweenService:Create(fightSound, TweenInfo.new(switchDuration or 1, Enum.EasingStyle.Linear), {
		Volume = bgmType == "Fight" and 1 or 0,
	}):Play()
end

-- Starts the game music thats gonna be used for the match
function SoundController:StartGameMusic(name: string)
	if self._currentGameMusic then
		self._currentGameMusic:Stop()
	end

	local gameMusic = SoundService:FindFirstChild(name, true)
	gameMusic:Play()
	self._currentGameMusic = gameMusic
end

-- Starts a random fight music track for the final 1v1
function SoundController:StartRandomFightMusic()
	local fightSound = SoundService:FindFirstChild("FightSound", true)
	if not fightSound then
		warn("FightSound Sound Group not found in SoundService")
		return
	end

	local sounds = fightSound:GetChildren()
	if #sounds == 0 then
		warn("FightSound Sound Group is empty")
		return
	end

	if self._currentGameMusic then
		self._currentGameMusic:Stop()
	end

	local randomFightMusic: Sound = sounds[math.random(1, #sounds)]
	randomFightMusic:Play()
	self._currentGameMusic = randomFightMusic
end

function SoundController:OnInit()
	task.spawn(function()
		self:_startBackgroundMusicCycle()
	end)
end

function SoundController:OnStart()
	-- Setup mute button
	local muteButton = TopbarPlus.new()
	muteButton:setImage("rbxassetid://103265952469825", "Deselected")
	muteButton:setImage("rbxassetid://70577541005282", "Selected")

	muteButton.selected:Connect(function()
		self:SetBGMCoreVolume(0, 0.5)
	end)

	muteButton.deselected:Connect(function()
		self:SetBGMCoreVolume(1, 0.5)
	end)

	-- Setup event handlers
	self.PlaySoundEvent:Connect(function(data: { any })
		self:PlaySound(table.unpack(data))
	end)

	self.PlayRandomSoundEvent:Connect(function(data: { any })
		self:PlayRandomSoundInFolder(table.unpack(data))
	end)
end

return SoundController
