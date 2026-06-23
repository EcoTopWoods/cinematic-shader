--!nonstrict
--[[
	enhancers/Fire.lua
	-----------------------------------------------------------------------------
	Upgrades stock Fire instances (Scanner kind "fire") with a flickering warm
	PointLight so flames actually light their surroundings, plus a gentle Fire size
	pulse. We create our own tagged PointLight (destroyed on unload) and only mutate
	scalar Brightness per frame — the flicker NumberSequence is conceptual; we drive
	Brightness directly from cheap noise. We never destroy the game's Fire.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local Fire = {}
	Fire.id = "enhancers/Fire"
	local RADIUS = 180

	function Fire.start(ctx)
		local maid = ctx.maid:childMaid()
		Fire._maid = maid
		local Snapshot = ctx.snapshot
		local Scanner = require("detection/Scanner")

		local lights = setmetatable({}, { __mode = "k" }) -- part -> PointLight (ours)

		local function enroll(part)
			if lights[part] then return end
			local fire = part:FindFirstChildOfClass("Fire")
			if not fire then return end
			local light = Snapshot.create("PointLight", {
				Name = "FireLight",
				Color = Color3.fromRGB(255, 150, 70),
				Range = 18, Brightness = 2, Enabled = true,
			}, part)
			lights[part] = light
		end

		for _, p in ipairs(Scanner.getByKind("fire")) do enroll(p) end
		maid:give(Scanner.onClassified:Connect(function(part, cls)
			if cls.kind == "fire" then enroll(part) end
		end))

		local t = 0
		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			local on = State.get("enh_enabled") and State.get("enh_fire")
			t += dt
			local cam = ctx.camera()
			local camPos = cam and cam.CFrame.Position or Vector3.zero
			for part, light in pairs(lights) do
				if part.Parent and light.Parent then
					light.Enabled = on
					if on and (part.Position - camPos).Magnitude <= RADIUS then
						local flick = 0.5 + 0.5 * (Util.noise(t * 6 + part.Position.X, 0, 0) * 0.5 + 0.5)
						light.Brightness = 1.5 + flick * 3
						light.Range = 16 + flick * 6
					end
				end
			end
		end))

		ctx.log.debug("Fire enhancer online")
		return Fire
	end

	function Fire.stop() if Fire._maid then Fire._maid:clean() end end

	return Fire
end
