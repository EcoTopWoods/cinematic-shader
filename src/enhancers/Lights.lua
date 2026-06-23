--!nonstrict
--[[
	enhancers/Lights.lua
	-----------------------------------------------------------------------------
	A subtle "light polish" pass over existing PointLight/SpotLight/SurfaceLight in
	the place (Scanner kind "light"): a gentle noise flicker around each light's
	original Brightness for a less sterile, more lived-in feel. The original
	Brightness is captured ONCE via Snapshot so unload restores it exactly; we then
	write Brightness directly each frame (capture is idempotent). Budgeted to nearby
	lights only.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local Lights = {}
	Lights.id = "enhancers/Lights"
	local RADIUS = 140

	function Lights.start(ctx)
		local maid = ctx.maid:childMaid()
		Lights._maid = maid
		local Snapshot = ctx.snapshot
		local Scanner = require("detection/Scanner")

		-- light instance -> base brightness
		local bases = setmetatable({}, { __mode = "k" })

		local function enrollPart(part)
			for _, child in ipairs(part:GetChildren()) do
				if child:IsA("Light") and not bases[child] then
					Snapshot.capture(child, "Brightness")
					bases[child] = child.Brightness
				end
			end
		end

		for _, p in ipairs(Scanner.getByKind("light")) do enrollPart(p) end
		maid:give(Scanner.onClassified:Connect(function(part, cls)
			if cls.kind == "light" then enrollPart(part) end
		end))

		local t = 0
		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			local on = State.get("enh_enabled") and State.get("enh_lights_repair")
			t += dt
			local cam = ctx.camera()
			local camPos = cam and cam.CFrame.Position or Vector3.zero
			for light, base in pairs(bases) do
				local parent = light.Parent
				if parent and parent:IsA("BasePart") then
					if not on then
						light.Brightness = base
					elseif (parent.Position - camPos).Magnitude <= RADIUS then
						local flick = Util.noise(t * 4 + parent.Position.X * 0.05, 0, 0) -- -1..1
						light.Brightness = math.max(0, base * (1 + flick * 0.12))
					end
				end
			end
		end))

		ctx.log.debug("Light polish online")
		return Lights
	end

	function Lights.stop() if Lights._maid then Lights._maid:clean() end end

	return Lights
end
