--!nonstrict
--[[
	enhancers/Foliage.lua
	-----------------------------------------------------------------------------
	Gentle noise wind-sway for SMALL DECORATIVE foliage only.

	⚠ HARD SAFETY RULE (learned the hard way): this is the ONLY module that moves a
	game part, and moving the wrong part wrecks the world — a rotated collidable
	floor/road becomes a pothole/ramp and you can't walk or drive. So we sway a part
	ONLY when ALL of these hold:
	    * it is classified foliage by Scanner (Grass/LeafyGrass or leaf/bush names),
	    * it is Anchored,
	    * it is NOT CanCollide   (pure decoration — never collision geometry),
	    * its largest dimension is small (<= MAX_SIZE) — structures are never small.
	The original CFrame is captured via Snapshot so unload restores it EXACTLY, and
	toggling the feature off restores every part immediately. Amplitude is tiny.

	Default OFF. Even constrained, moving geometry is risky on arbitrary places, so
	the user opts in deliberately.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local Foliage = {}
	Foliage.id = "enhancers/Foliage"
	local BUDGET = 30
	local RADIUS = 140
	local MAX_SIZE = 10        -- studs; anything bigger is structure, never swayed
	local MAX_AMP = 0.08       -- radians cap (~4.5°), very gentle

	function Foliage.start(ctx)
		local maid = ctx.maid:childMaid()
		Foliage._maid = maid
		local Snapshot = ctx.snapshot
		local Scanner = require("detection/Scanner")
		Foliage._q = ctx.getQuality()

		local bases = setmetatable({}, { __mode = "k" }) -- part -> base CFrame
		local list = {}
		local cursor = 1

		-- the safety gate: only small, non-collidable, anchored decorations
		local function eligible(part)
			if not part:IsA("BasePart") then return false end
			if not part.Anchored then return false end
			if part.CanCollide then return false end          -- NEVER move collision geometry
			local s = part.Size
			if math.max(s.X, s.Y, s.Z) > MAX_SIZE then return false end -- never move structures
			return true
		end

		local function enroll(part)
			if bases[part] then return end
			if not eligible(part) then return end
			Snapshot.capture(part, "CFrame")   -- remember original for restore
			bases[part] = part.CFrame
			list[#list + 1] = part
		end

		local function restoreAll()
			for part, base in pairs(bases) do
				if part.Parent then pcall(function() part.CFrame = base end) end
			end
		end

		for _, p in ipairs(Scanner.getByKind("foliage")) do enroll(p) end
		maid:give(Scanner.onClassified:Connect(function(part, cls)
			if cls.isFoliage then enroll(part) end
		end))

		-- when toggled off, snap everything back to its captured base immediately
		maid:give(State.observe("enh_foliage_wind", function(on)
			if not on then restoreAll() end
		end))

		local t = 0
		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			if not (State.get("enh_enabled") and State.get("enh_foliage_wind")) then return end
			t += dt
			local cam = ctx.camera()
			local camPos = cam and cam.CFrame.Position or Vector3.zero
			local amp = math.min(MAX_AMP, 0.02 + State.get("weather_wind") * 0.06)
			local n = #list
			if n == 0 then return end
			local budget = math.max(6, math.floor(BUDGET * (Foliage._q or 1)))
			local done, scanned = 0, 0
			while done < budget and scanned < n do
				local part = list[cursor]
				cursor = (cursor % n) + 1
				scanned += 1
				if part and part.Parent and bases[part] then
					-- guard: if a part somehow became collidable since enroll, skip + restore it
					if part.CanCollide then
						pcall(function() part.CFrame = bases[part] end)
					elseif (part.Position - camPos).Magnitude <= RADIUS then
						local phase = (part.Position.X + part.Position.Z) * 0.1
						local sway = Util.noise(t * 0.6 + phase, 0, 0) * amp
						local sway2 = Util.noise(0, t * 0.5 + phase, 0) * amp * 0.6
						part.CFrame = bases[part] * CFrame.Angles(sway2, 0, sway)
						done += 1
					end
				end
			end
		end))

		ctx.log.debug("Foliage sway online (decoration-only, non-collidable); candidates =", #list)
		return Foliage
	end

	function Foliage.setQuality(q) Foliage._q = q end
	function Foliage.stop() if Foliage._maid then Foliage._maid:clean() end end

	return Foliage
end
