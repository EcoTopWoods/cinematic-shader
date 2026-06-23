--!nonstrict
--[[
	reflections/RaycastProbe.lua  —  probe strategy ("Raycast Probe (SSR approx.)")
	-----------------------------------------------------------------------------
	An HONEST approximation of screen-space reflections. NOT ray tracing, NOT mirror-
	accurate. Each frame we cast a small BUDGET of "roving" reflection rays
	(reflect_rays_per_frame) spread across the registered floors: from a sample point
	on a floor we reflect the view direction about the floor normal and
	workspace:Raycast outward. The colour we hit (or the sky/ambient on a miss) is
	accumulated into a per-floor exponentially-smoothed colour, so the estimate is
	temporally stable and shimmer-free.

	Camera-delta REPROJECTION: instead of warping a screen buffer (we have no depth
	buffer), we modulate the temporal blend factor by bus.camDelta — when the camera
	moves fast the estimate snaps toward fresh samples (less lag); when still it
	smooths hard (kills shimmer). reflect_smoothing sets the resting smoothness.

	Multi-bounce (reflect_multibounce, auto-off on mobile) casts one extra bounce.
	The controller reads colorFor(entry) and tints the floor's glass sheen overlay.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local RaycastProbe = {}
	RaycastProbe.id = "reflections/RaycastProbe"

	local registered = {}     -- array of floor entries
	local indexByEntry = {}   -- entry -> array index
	local cursor = 1
	local qualityMul = 1
	local rng = Random.new(99)

	function RaycastProbe.register(entry)
		if indexByEntry[entry] then return end
		registered[#registered + 1] = entry
		indexByEntry[entry] = #registered
		entry._probe = entry._probe or { color = Color3.fromRGB(150, 160, 175) }
	end

	function RaycastProbe.unregister(entry)
		local i = indexByEntry[entry]
		if not i then return end
		-- swap-remove
		local last = #registered
		registered[i] = registered[last]
		if registered[i] then indexByEntry[registered[i]] = i end
		registered[last] = nil
		indexByEntry[entry] = nil
	end

	function RaycastProbe.colorFor(entry)
		return entry._probe and entry._probe.color or nil
	end

	function RaycastProbe.setQuality(q)
		qualityMul = math.clamp(q, 0.25, 1)
	end

	function RaycastProbe.start(ctx)
		local maid = ctx.maid:childMaid()
		RaycastProbe._maid = maid
		local isMobile = ctx.platform.isMobile

		-- cached RaycastParams — never reallocate per ray.
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.IgnoreWater = false
		local function refreshFilter()
			local ignore = { ctx.worldFolder }
			local char = ctx.services.Players.LocalPlayer and ctx.services.Players.LocalPlayer.Character
			if char then ignore[#ignore + 1] = char end
			params.FilterDescendantsInstances = ignore
		end
		refreshFilter()
		local lp = ctx.services.Players.LocalPlayer
		if lp then maid:give(lp.CharacterAdded:Connect(refreshFilter)) end

		local function skyColor()
			-- miss → environment colour: blend outdoor ambient toward sky tint.
			local L = ctx.services.Lighting
			return L.OutdoorAmbient:Lerp(L.ColorShift_Top, 0.35)
		end

		local function hitColor(result, fallback)
			if not result then return fallback end
			local inst = result.Instance
			local ok, c = pcall(function() return inst.Color end)
			if ok and typeof(c) == "Color3" then return c end
			return fallback
		end

		-- one reflection sample for a floor → returns a Color3
		local function sampleFloor(entry, camPos)
			local part = entry.part
			if not part.Parent then return nil end
			local n = part.CFrame.UpVector
			-- random point on the top face
			local size = part.Size
			local lx = (rng:NextNumber() - 0.5) * size.X
			local lz = (rng:NextNumber() - 0.5) * size.Z
			local p = (part.CFrame * CFrame.new(lx, size.Y / 2 + 0.05, lz)).Position
			local viewDir = (p - camPos)
			if viewDir.Magnitude < 1e-3 then return nil end
			viewDir = viewDir.Unit
			-- reflect view about the surface normal
			local refl = viewDir - 2 * viewDir:Dot(n) * n
			local dist = 120
			local result = workspace:Raycast(p + n * 0.05, refl * dist, params)
			local col = hitColor(result, skyColor())
			-- optional one extra bounce (desktop only)
			if result and State.get("reflect_multibounce") and not isMobile then
				local p2 = result.Position
				local n2 = result.Normal
				local refl2 = refl - 2 * refl:Dot(n2) * n2
				local r2 = workspace:Raycast(p2 + n2 * 0.05, refl2 * dist, params)
				col = col:Lerp(hitColor(r2, skyColor()), 0.4)
			end
			return col
		end

		maid:give(ctx.services.RunService.Heartbeat:Connect(function()
			local count = #registered
			if count == 0 then return end
			local cam = ctx.camera()
			if not cam then return end
			local camPos = cam.CFrame.Position

			-- reprojection-flavoured blend: faster camera → snappier estimate.
			-- The resting blend implements an N-frame temporal ACCUMULATION window:
			-- a running average over N frames has per-frame weight ~1/N, which we damp
			-- further by the smoothing slider. More accum frames OR more smoothing →
			-- smaller alpha → a more stable, shimmer-free estimate (and more lag).
			local smoothing = State.get("reflect_smoothing")
			local accumN = math.max(1, State.get("reflect_accum_frames"))
			local restAlpha = (1 - smoothing) / math.sqrt(accumN)
			local alpha = restAlpha
			if State.get("reflect_reproject") then
				local cd = ctx.bus.camDelta or 0
				alpha = Util.clamp(restAlpha + cd * 0.08, restAlpha, 1)
			end

			local budget = math.max(4, math.floor(State.get("reflect_rays_per_frame") * qualityMul))
			-- distribute rays round-robin across floors
			for _ = 1, budget do
				local entry = registered[cursor]
				cursor = (cursor % count) + 1
				if entry and entry.part.Parent then
					local c = sampleFloor(entry, camPos)
					if c then
						local pc = entry._probe
						pc.color = pc.color:Lerp(c, alpha)
					end
				end
			end
		end))

		ctx.log.debug("RaycastProbe online (SSR approximation)")
		return RaycastProbe
	end

	function RaycastProbe.stop()
		if RaycastProbe._maid then RaycastProbe._maid:clean() end
	end

	return RaycastProbe
end
