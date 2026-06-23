--!nonstrict
--[[
	weather/Lightning.lua  —  stochastic storm lightning
	-----------------------------------------------------------------------------
	When active, fires lightning flashes at random intervals. A flash:
	  * spikes the owned BloomEffect intensity briefly (bus.pipeline.bloom),
	  * pulses a bright transient PointLight high in the world,
	  * writes a decaying value to bus.flash so overlays can react,
	then decays back over a fraction of a second. Uses a Random instance; the bloom
	value is captured/restored each flash so we never drift the user's setting.
]]

return function(require)
	local Lightning = {}
	Lightning.id = "weather/Lightning"

	function Lightning.start(ctx)
		local maid = ctx.maid:childMaid()
		Lightning._maid = maid
		local Snapshot = ctx.snapshot
		local rng = Random.new(2024)
		local active = false
		local nextFlashIn = rng:NextNumber(3, 8)
		local flashEnergy = 0      -- 0..1 decaying
		local baseBloom = nil

		-- a transient light high above; off until a flash
		local lightPart = Snapshot.create("Part", {
			Name = "LightningLight",
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
			Transparency = 1, Size = Vector3.new(1, 1, 1),
		}, ctx.worldFolder)
		local pointLight = Snapshot.create("PointLight", {
			Brightness = 0, Range = 200, Color = Color3.fromRGB(220, 230, 255), Enabled = false,
		}, lightPart)

		Lightning.setActive = function(on)
			active = on
			if not on then
				pointLight.Enabled = false
				flashEnergy = 0
			end
		end

		local function triggerFlash()
			flashEnergy = 1
			local cam = ctx.camera()
			if cam then
				lightPart.Position = cam.CFrame.Position + Vector3.new(rng:NextNumber(-80, 80), 120, rng:NextNumber(-80, 80))
			end
			local bloom = ctx.bus.pipeline and ctx.bus.pipeline.bloom
			if bloom and baseBloom == nil then baseBloom = bloom.Intensity end
		end

		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			if not active then return end
			nextFlashIn -= dt
			if nextFlashIn <= 0 then
				nextFlashIn = rng:NextNumber(4, 12)
				triggerFlash()
			end
			if flashEnergy > 0 then
				flashEnergy = math.max(0, flashEnergy - dt * 3.5) -- ~0.3s decay
				ctx.bus.flash = flashEnergy
				pointLight.Enabled = true
				pointLight.Brightness = flashEnergy * 8
				local bloom = ctx.bus.pipeline and ctx.bus.pipeline.bloom
				if bloom and baseBloom ~= nil then
					bloom.Intensity = baseBloom + flashEnergy * 2.5
				end
				if flashEnergy <= 0 then
					pointLight.Enabled = false
					local b = ctx.bus.pipeline and ctx.bus.pipeline.bloom
					if b and baseBloom ~= nil then b.Intensity = baseBloom; baseBloom = nil end
					ctx.bus.flash = 0
				end
			end
		end))

		ctx.log.debug("Lightning ready")
		return Lightning
	end

	function Lightning.stop()
		if Lightning._maid then Lightning._maid:clean() end
	end

	return Lightning
end
