-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Assets
local Assets = ReplicatedStorage.Assets
local Effects = Assets.Effects

--
local SoundController = require(script.Parent.Parent.Controllers.SoundController)

--
type ConfettiType = "Small" | "Regular" | "Big"

type SoundProperties = {
	MinDistance: number?,
	MaxDistance: number?,
	Volume: number?,
}

export type ConfettiConfig = {
	-- Where to launch from. Pass a list to fire from many locations at once.
	-- PVInstances (BaseParts, Models) are re-sampled per-launch so confetti tracks live movement,
	-- and the loop stops firing from an origin if its instance gets destroyed/unparented.
	origin: CFrame | PVInstance | { CFrame | PVInstance },
	-- Amount of confetti per origin.
	amount: NumberRange,
	-- Pool of confetti models to randomly pick from.
	types: { ConfettiType },
	-- Y range of the launch arc.
	height: NumberRange,
	-- X spread around each origin. Defaults to ±6.
	spread: NumberRange?,
	-- Z spread around each origin. Defaults to ±2.
	depth: NumberRange?,
	-- Studs/sec travel speed. Defaults to 30.
	speed: NumberRange?,

	-- Delay between each confetti launch. Defaults to 0.2.
	launchDelay: NumberRange?,
	perOriginDelay: NumberRange?,

	-- Optional sound properties for the whistle/boom sounds.
	sound: SoundProperties?,
}

--
local DEFAULT_SPEED = NumberRange.new(20, 30)
local DEFAULT_SPREAD = NumberRange.new(-6, 6)
local DEFAULT_DEPTH = NumberRange.new(-2, 2)
local DEFAULT_LAUNCH_DELAY = NumberRange.new(0.2, 0.5)
local DEFAULT_PER_ORIGIN_DELAY = NumberRange.new(0, 0.001)
local DEFAULT_AMOUNT = NumberRange.new(1, 3)

--
return function(config: ConfettiConfig)
	local amount = config.amount or DEFAULT_AMOUNT
	local types = config.types
	local height = config.height
	local spread = config.spread or DEFAULT_SPREAD
	local depth = config.depth or DEFAULT_DEPTH
	local speed = config.speed or DEFAULT_SPEED
	local sound = config.sound
	local launchDelay = config.launchDelay or DEFAULT_LAUNCH_DELAY
	local perOriginDelay = config.perOriginDelay or DEFAULT_PER_ORIGIN_DELAY
	local confettis = Effects.Confettis
	local random = Random.new()

	-- Normalize origins into a list, but keep PVInstances as references so each launch can
	-- re-sample their current pivot (and detect when they've been destroyed)
	type OriginRef = CFrame | PVInstance
	local origins: { OriginRef }
	local rawOrigin = config.origin
	if typeof(rawOrigin) == "table" then
		origins = table.clone(rawOrigin)
	else
		origins = { rawOrigin }
	end

	local function resolveOrigin(originRef: OriginRef): CFrame?
		if typeof(originRef) == "CFrame" then
			return originRef
		end
		if not originRef.Parent then
			return nil
		end
		return originRef:GetPivot()
	end

	--
	local function launchConfetti(originRef: OriginRef)
		local launchOrigin = resolveOrigin(originRef)
		if not launchOrigin then
			return
		end

		local endPosition = launchOrigin
			* CFrame.new(
				random:NextNumber(spread.Min, spread.Max),
				random:NextNumber(height.Min, height.Max),
				random:NextNumber(depth.Min, depth.Max)
			)
		local totalDistance = (launchOrigin.Position - endPosition.Position).Magnitude

		local confettiType = types[random:NextInteger(1, #types)]
		local confetti = confettis[confettiType]:Clone()
		confetti:PivotTo(launchOrigin)
		confetti.Parent = workspace.Effects

		local currentSpeed = random:NextNumber(speed.Min, speed.Max)
		local launchTween = TweenService:Create(
			confetti.PrimaryPart,
			TweenInfo.new(totalDistance / currentSpeed, Enum.EasingStyle.Linear),
			{ CFrame = endPosition }
		)

		-- Clone so we don't mutate the caller's table across iterations
		local soundProps = if sound then table.clone(sound) else {}
		soundProps.PlaybackSpeed = random:NextNumber(1, 1.25)

		SoundController:PlaySound(
			`ConfettiWhistle{random:NextInteger(1, 3)}`,
			confetti.Container,
			{ PlaybackSpeed = random:NextNumber(0.8, 1.2) }
		)
		launchTween:Play()

		launchTween.Completed:Wait()
		for _, v in confetti.Container.ConfettiAttachment:GetChildren() do
			if v:IsA("ParticleEmitter") then
				v:Emit(v:GetAttribute("EmitAmount") or 10)
			end
		end

		SoundController:PlaySound(
			`ConfettiBoom{random:NextInteger(1, 2)}`,
			confetti.Container,
			{ PlaybackSpeed = random:NextNumber(0.8, 1.2) }
		)

		task.wait(3)
		confetti:Destroy()
	end

	for _, originRef in origins do
		task.spawn(function()
			for _ = 1, random:NextInteger(amount.Min, amount.Max) do
				-- Stop firing from this origin if its instance has been destroyed/unparented
				if typeof(originRef) ~= "CFrame" and not originRef.Parent then
					break
				end
				task.spawn(launchConfetti, originRef)
				task.wait(random:NextNumber(launchDelay.Min, launchDelay.Max))
			end
		end)

		task.wait(random:NextNumber(perOriginDelay.Min, perOriginDelay.Max))
	end
end
