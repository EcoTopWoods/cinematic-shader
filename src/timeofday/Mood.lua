--!nonstrict
--[[
	timeofday/Mood.lua  —  CONTROLLER (manifest.boot)
	-----------------------------------------------------------------------------
	ClockTime driver + named time-of-day moods.

	Selecting a non-Custom mood pushes a coherent set of values through State (which
	the Lighting / Atmosphere / ColorGrade observers then apply) — ClockTime is eased
	smoothly with frame-rate-independent damping for a nice transition; the discrete
	colour keys are set directly. "Custom" leaves everything alone so the user's own
	tuning is respected.

	mood_auto_cycle advances ClockTime continuously (a living sky) at
	mood_cycle_speed in-game hours per real second; this naturally flows through
	Lighting.lua's lighting_clock_time observer.

	No invented APIs — every value lands on a real config key.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local Mood = {}
	Mood.id = "timeofday/Mood"

	-- Each mood seeds clock + the palette keys. Tuned for a filmic feel.
	local MOODS = {
		["Golden Hour"] = {
			clock = 17.6,
			ambient = Color3.fromRGB(46, 38, 32),
			outdoor = Color3.fromRGB(150, 110, 80),
			tint = Color3.fromRGB(255, 226, 196),
			atmos = Color3.fromRGB(232, 196, 160),
		},
		["Blue Hour"] = {
			clock = 5.6,
			ambient = Color3.fromRGB(30, 36, 50),
			outdoor = Color3.fromRGB(70, 88, 120),
			tint = Color3.fromRGB(216, 226, 255),
			atmos = Color3.fromRGB(150, 170, 205),
		},
		["Noon"] = {
			clock = 12.5,
			ambient = Color3.fromRGB(60, 62, 70),
			outdoor = Color3.fromRGB(130, 138, 150),
			tint = Color3.fromRGB(255, 250, 244),
			atmos = Color3.fromRGB(200, 210, 225),
		},
		["Night"] = {
			clock = 0.0,
			ambient = Color3.fromRGB(16, 20, 32),
			outdoor = Color3.fromRGB(34, 42, 64),
			tint = Color3.fromRGB(190, 205, 240),
			atmos = Color3.fromRGB(60, 72, 100),
		},
		["Overcast"] = {
			clock = 13.0,
			ambient = Color3.fromRGB(58, 60, 64),
			outdoor = Color3.fromRGB(120, 124, 130),
			tint = Color3.fromRGB(228, 230, 235),
			atmos = Color3.fromRGB(186, 190, 196),
		},
	}

	function Mood.start(ctx)
		local maid = ctx.maid:childMaid()
		Mood._maid = maid

		local targetClock = nil -- non-nil while easing toward a pinned mood

		local function applyMood(name)
			local m = MOODS[name]
			if not m then
				targetClock = nil -- "Custom" → stop driving the clock
				return
			end
			-- discrete palette keys land immediately (their own observers react)
			State.set("lighting_ambient", m.ambient)
			State.set("lighting_outdoor_ambient", m.outdoor)
			State.set("grade_tint", m.tint)
			State.set("atmos_color", m.atmos)
			targetClock = m.clock
		end

		maid:give(State.observe("mood_preset", applyMood))

		-- clock driver: cycling overrides; else ease toward a pinned mood's clock.
		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			if State.get("mood_auto_cycle") then
				local speed = State.get("mood_cycle_speed")
				local t = State.get("lighting_clock_time") + speed * dt
				if t >= 24 then t -= 24 end
				State.set("lighting_clock_time", t)
				return
			end
			if targetClock ~= nil then
				local cur = State.get("lighting_clock_time")
				-- shortest-path easing around the 24h wrap
				local diff = targetClock - cur
				if diff > 12 then diff -= 24 elseif diff < -12 then diff += 24 end
				if math.abs(diff) < 0.01 then
					targetClock = nil
					return
				end
				local stepTarget = cur + diff
				local nextV = Util.damp(cur, stepTarget, 0.6, dt)
				if nextV < 0 then nextV += 24 elseif nextV >= 24 then nextV -= 24 end
				State.set("lighting_clock_time", nextV)
			end
		end))

		ctx.log.debug("Mood online")
		return Mood
	end

	function Mood.stop()
		if Mood._maid then Mood._maid:clean() end
	end

	return Mood
end
