--!nonstrict
--[[
	reflections/ViewportMirror.lua  —  optional hero-floor planar mirror (HIGH tier)
	-----------------------------------------------------------------------------
	HONESTY FIRST: a ViewportFrame only renders instances parented INTO it, not the
	live workspace, and Roblox gives us no render-to-texture of the real scene. So a
	"true" mirror is impossible. This module implements the legitimate SHOWCASE
	technique: clone a small, budget-capped set of nearby ANCHORED parts into a
	ViewportFrame whose camera is the real camera reflected across one hero floor
	plane, and display it on a SurfaceGui on that floor. It reflects only that cloned
	static subset, refreshed slowly — a convincing hero-floor mirror, not a
	general-purpose reflection.

	Default OFF; only started by the controller at very high quality on desktop.
	Everything is capped, slow-refresh, and fully Maid-tracked.
]]

return function(require)
	local State = require("core/State")

	local ViewportMirror = {}
	ViewportMirror.id = "reflections/ViewportMirror"

	local CLONE_CAP = 40
	local CLONE_RADIUS = 80
	local REFRESH_EVERY = 3.0

	function ViewportMirror.start(ctx, heroFloor)
		local maid = ctx.maid:childMaid()
		ViewportMirror._maid = maid
		local Snapshot = ctx.snapshot

		heroFloor = heroFloor or ViewportMirror._pickHero(ctx)
		if not heroFloor then
			ctx.log.debug("ViewportMirror: no hero floor found — skipped")
			return ViewportMirror
		end

		-- The mirror's low-res buffer resolution is the reflect_resolution config (the
		-- same "small CPU-bound buffer" budget the probe uses). Read once at creation.
		local res = math.clamp(State.get("reflect_resolution") or 128, 64, 256)

		-- Parent the SurfaceGui directly to the floor part (most reliable rendering)
		-- It is tagged + tracked by Snapshot, so teardown destroys it cleanly.
		local surface = Snapshot.create("SurfaceGui", {
			Name = "MirrorSurface",
			Face = Enum.NormalId.Top,
			CanvasSize = Vector2.new(res * 2, res * 2),
			LightInfluence = 0,
		}, heroFloor)

		local vpf = Snapshot.create("ViewportFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ImageTransparency = 0.35,        -- let the floor show through (sheen)
			Ambient = Color3.fromRGB(140, 150, 165),
			LightColor = Color3.fromRGB(255, 250, 240),
		}, surface)

		local world = Snapshot.create("WorldModel", {}, vpf) -- proper lighting for clones
		local vpCam = Snapshot.create("Camera", {}, vpf)
		vpf.CurrentCamera = vpCam

		local cloneHolder = {}
		-- Cheap spatial query instead of workspace:GetDescendants() — the old code
		-- walked the ENTIRE instance tree on every refresh, a hard periodic hitch on
		-- big places. GetPartBoundsInBox returns only nearby BaseParts, capped.
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = { ctx.worldFolder }
		overlap.MaxParts = CLONE_CAP * 3

		local function rebuildClones()
			for _, c in ipairs(cloneHolder) do c:Destroy() end
			table.clear(cloneHolder)
			local origin = heroFloor.Position
			local box = Vector3.new(CLONE_RADIUS * 2, CLONE_RADIUS * 2, CLONE_RADIUS * 2)
			local nearby = workspace:GetPartBoundsInBox(CFrame.new(origin), box, overlap)
			local n = 0
			for _, part in ipairs(nearby) do
				if n >= CLONE_CAP then break end
				if part.Anchored and part ~= heroFloor then
					local ok, clone = pcall(function()
						local cl = part:Clone()
						cl.Anchored = true
						for _, ch in ipairs(cl:GetChildren()) do
							-- drop scripts/sounds/heavy children from clones
							if not ch:IsA("DataModelMesh") and not ch:IsA("SpecialMesh")
								and not ch:IsA("Decal") and not ch:IsA("Texture")
								and not ch:IsA("SurfaceAppearance") then
								ch:Destroy()
							end
						end
						cl.Parent = world
						return cl
					end)
					if ok and clone then
						cloneHolder[#cloneHolder + 1] = clone
						n += 1
					end
				end
			end
		end

		rebuildClones()

		local refreshAccum = REFRESH_EVERY
		local frameAccum = 0
		maid:give(ctx.services.RunService.PreRender:Connect(function(dt)
			refreshAccum += dt
			if refreshAccum >= REFRESH_EVERY then
				refreshAccum = 0
				rebuildClones()
			end
			frameAccum += dt
			if frameAccum < 1 / 30 then return end -- mirror at 30fps max
			frameAccum = 0
			local cam = ctx.camera()
			if not cam then return end
			-- reflect the camera across the hero floor plane (point on plane = floor
			-- top centre, plane normal = floor up vector).
			local n = heroFloor.CFrame.UpVector
			local planePoint = heroFloor.Position + n * (heroFloor.Size.Y / 2)
			local camCF = cam.CFrame
			local pos = camCF.Position
			local d = (pos - planePoint):Dot(n)
			local mirroredPos = pos - 2 * d * n
			local look = camCF.LookVector
			local mirroredLook = look - 2 * look:Dot(n) * n
			vpCam.CFrame = CFrame.lookAt(mirroredPos, mirroredPos + mirroredLook, Vector3.yAxis)
			vpCam.FieldOfView = cam.FieldOfView
		end))

		-- destroy clones explicitly on teardown (they live under our tagged vpf, but
		-- be tidy).
		maid:give(function()
			for _, c in ipairs(cloneHolder) do pcall(function() c:Destroy() end) end
			table.clear(cloneHolder)
		end)

		ctx.log.debug("ViewportMirror online on", heroFloor:GetFullName())
		return ViewportMirror
	end

	function ViewportMirror._pickHero(ctx)
		local Scanner = require("detection/Scanner")
		local cam = ctx.camera()
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		local best, bestScore
		for _, p in ipairs(Scanner.getFloors()) do
			local area = p.Size.X * p.Size.Z
			local dist = (p.Position - camPos).Magnitude
			local score = area - dist * 2
			if not bestScore or score > bestScore then
				best, bestScore = p, score
			end
		end
		return best
	end

	function ViewportMirror.stop()
		if ViewportMirror._maid then ViewportMirror._maid:clean() end
	end

	return ViewportMirror
end
