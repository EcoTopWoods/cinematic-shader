--!nonstrict
--[[
	weather/Weather.lua  —  CONTROLLER (manifest.boot)
	-----------------------------------------------------------------------------
	Weather state machine with SMOOTH transitions. Owns a single camera-following
	volume part (so precipitation always falls around the player without spawning
	emitters across the whole map) and cross-fades rain/snow levels with frame-rate-
	independent damping when weather_mode changes.

	It writes a target wetness to bus.wetness (rain/storm soak floors → the
	Reflections controller raises floor reflectance), drives wind (base ×
	storm gusts), and toggles Lightning during storms.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local Weather = {}
	Weather.id = "weather/Weather"

	local WIND_DIR = Vector3.new(1, 0, 0.3).Unit
	local MAX_WIND = 120

	function Weather.start(ctx)
		local maid = ctx.maid:childMaid()
		Weather._maid = maid
		local Snapshot = ctx.snapshot

		-- camera-following emission volume (high above the player)
		local volume = Snapshot.create("Part", {
			Name = "WeatherVolume",
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
			Transparency = 1,
			Size = Vector3.new(240, 8, 240),
		}, ctx.worldFolder)

		-- start sub-emitters on the shared volume
		local Rain = require("weather/Rain"); Rain.start(ctx, volume); ctx.registerHandle(Rain)
		local Snow = require("weather/Snow"); Snow.start(ctx, volume); ctx.registerHandle(Snow)
		local Storm = require("weather/Storm"); Storm.start(ctx); ctx.registerHandle(Storm)
		local Lightning = require("weather/Lightning"); Lightning.start(ctx); ctx.registerHandle(Lightning)

		-- eased levels
		local rainLevel, snowLevel, wetLevel = 0, 0, 0

		local function targetsFor(mode, intensity)
			if mode == "Rain" then
				return intensity, 0, intensity, false
			elseif mode == "Snow" then
				return 0, intensity, intensity * 0.3, false
			elseif mode == "Storm" then
				return math.clamp(intensity * 1.3, 0, 1), 0, 1, true
			end
			return 0, 0, 0, false -- Clear
		end

		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			local mode = State.get("weather_mode")
			local intensity = State.get("weather_intensity")
			local rT, sT, wT, storming = targetsFor(mode, intensity)

			rainLevel = Util.damp(rainLevel, rT, 1.0, dt)
			snowLevel = Util.damp(snowLevel, sT, 1.4, dt)
			wetLevel = Util.damp(wetLevel, wT, 1.5, dt)
			ctx.bus.wetness = wetLevel

			-- wind (base × storm gust), as a world-space horizontal vector
			Storm.setActive(storming)
			local gust = Storm.gust(dt)
			local windMag = State.get("weather_wind") * gust * MAX_WIND
			local windVec = WIND_DIR * windMag

			Rain.set(rainLevel, windVec)
			Snow.set(snowLevel, windVec)

			-- lightning only during storm AND when enabled
			Lightning.setActive(storming and State.get("weather_lightning"))

			-- follow the camera
			local cam = ctx.camera()
			if cam then
				volume.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 55, 0))
			end
		end))

		ctx.log.debug("Weather online")
		return Weather
	end

	function Weather.setQuality(q)
		-- particle budget scaling handled implicitly via levels; nothing extra here.
		Weather._q = q
	end

	function Weather.stop()
		if Weather._maid then Weather._maid:clean() end
	end

	return Weather
end
