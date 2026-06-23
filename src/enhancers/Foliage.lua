--!nonstrict
--[[
	enhancers/Foliage.lua
	-----------------------------------------------------------------------------
	Noise-driven wind sway for foliage parts (Scanner kind "foliage"). We capture
	each swayed part's original CFrame ONCE via Snapshot (so unload restores it
	exactly) and apply a small, phase-offset rotational wobble around its base each
	frame. Budgeted: only a rotating subset of nearby foliage is updated per frame,
	amplitude scales with weather_wind. Only ANCHORED parts are swayed (moving a
	physics part would fight the engine).
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local Foliage = {}
	Foliage.id = "enhancers/Foliage"
	local BUDGET = 40
	local RADIUS = 160

	function Foliage.start(ctx)
		local maid = ctx.maid:childMaid()
		Foliage._maid = maid
		local Snapshot = ctx.snapshot
		local Scanner = require("detection/Scanner")
		Foliage._q = ctx.getQuality()

		local bases = setmetatable({}, { __mode = "k" }) -- part -> base CFrame
		local list = {}
		local cursor = 1

		local function enroll(part)
			if bases[part] then return end
			if not part:IsA("BasePart") or not part.Anchored then return end
			Snapshot.capture(part, "CFrame")   -- remember original for restore
			bases[part] = part.CFrame
			list[#list + 1] = part
		end

		for _, p in ipairs(Scanner.getByKind("foliage")) do enroll(p) end
		maid:give(Scanner.onClassified:Connect(function(part, cls)
			if cls.isFoliage then enroll(part) end
		end))

		local t = 0
		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			if not (State.get("enh_enabled") and State.get("enh_foliage_wind")) then return end
			t += dt
			local cam = ctx.camera()
			local camPos = cam and cam.CFrame.Position or Vector3.zero
			local amp = (0.04 + State.get("weather_wind") * 0.12) -- radians
			local n = #list
			if n == 0 then return end
			local budget = math.max(6, math.floor(BUDGET * (Foliage._q or 1)))
			local done, scanned = 0, 0
			while done < budget and scanned < n do
				local part = list[cursor]
				cursor = (cursor % n) + 1
				scanned += 1
				if part and part.Parent and bases[part] then
					if (part.Position - camPos).Magnitude <= RADIUS then
						local phase = (part.Position.X + part.Position.Z) * 0.1
						local sway = Util.noise(t * 0.6 + phase, 0, 0) * amp
						local sway2 = Util.noise(0, t * 0.5 + phase, 0) * amp * 0.6
						part.CFrame = bases[part] * CFrame.Angles(sway2, 0, sway)
						done += 1
					end
				end
			end
		end))

		ctx.log.debug("Foliage sway online; candidates =", #list)
		return Foliage
	end

	function Foliage.setQuality(q) Foliage._q = q end
	function Foliage.stop() if Foliage._maid then Foliage._maid:clean() end end

	return Foliage
end
