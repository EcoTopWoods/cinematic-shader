--!nonstrict
--[[
	reflections/ViewportMirror.lua  —  hero-floor planar mirror (opt-in showpiece)
	=============================================================================
	HONESTY FIRST: a ViewportFrame only renders instances parented INTO it, never the
	live workspace, and Roblox gives no render-to-texture of the real scene. A "true"
	universal mirror is therefore impossible. This is the legitimate planar-reflection
	technique used by showcase places:

	  * Pick the floor DIRECTLY UNDER the player (raycast down), re-pick as they walk.
	  * Clone a budget-capped set of nearby anchored scenery INTO a WorldModel, plus a
	    live clone of the local character whose part CFrames are synced every frame —
	    so YOU appear in the reflection, animation and all.
	  * Place a Camera = the real camera reflected across the floor plane (position AND
	    orientation), and show it on a SurfaceGui on the floor's top face.
	  * Mirror strength blends with wetness (ImageTransparency) so it reads as a wet
	    sheen, not a perfect chrome plane.

	It reflects the cloned subset + you — not distant dynamic objects. Opt-in via the
	reflect_mirror toggle, desktop only, fully capped + Maid-tracked. EXPENSIVE: it
	renders a second camera, so it's gated behind an explicit toggle.
]]

return function(require)
	local State = require("core/State")

	local ViewportMirror = {}
	ViewportMirror.id = "reflections/ViewportMirror"

	local CLONE_CAP      = 55      -- max static scenery clones
	local CLONE_RADIUS   = 95      -- region half-extent for scenery
	local CLONE_REFRESH  = 4.0     -- re-grab scenery (catch moved props) seconds
	local REPICK_EVERY   = 0.4     -- how often we look for the floor under the player
	local MIRROR_DT      = 1 / 30  -- cap the mirror render at 30 fps

	function ViewportMirror.start(ctx)
		local maid = ctx.maid:childMaid()
		ViewportMirror._maid = maid
		local Snapshot = ctx.snapshot
		local Players = ctx.services.Players
		local Lighting = ctx.services.Lighting
		local RunService = ctx.services.RunService
		local lp = Players.LocalPlayer

		local res = math.clamp(State.get("reflect_resolution") or 128, 64, 256)

		-- ── raycast / overlap params (cached) ────────────────────────────────
		local downParams = RaycastParams.new()
		downParams.FilterType = Enum.RaycastFilterType.Exclude
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.MaxParts = CLONE_CAP * 3

		local function refreshFilters()
			local ignore = { ctx.worldFolder }
			if lp and lp.Character then ignore[#ignore + 1] = lp.Character end
			downParams.FilterDescendantsInstances = ignore
		end
		refreshFilters()
		if lp then maid:give(lp.CharacterAdded:Connect(function() refreshFilters() end)) end

		-- ── live mirror state ────────────────────────────────────────────────
		local heroFloor          -- the floor part currently mirrored
		local surface, vpf, world, vpCam
		local charClones = {}    -- { original BasePart, clone BasePart } pairs

		local function clearMirror()
			if surface then pcall(function() surface:Destroy() end) end
			surface, vpf, world, vpCam = nil, nil, nil, nil
			table.clear(charClones)
		end
		maid:give(clearMirror)

		-- strip everything from a clone that we don't want rendering/simulating
		local function sanitizeClone(inst)
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound")
					or d:IsA("Motor6D") or d:IsA("Weld") or d:IsA("WeldConstraint")
					or d:IsA("Motor") or d:IsA("ParticleEmitter") or d:IsA("Beam")
					or d:IsA("Light") then
					pcall(function() d:Destroy() end)
				end
			end
		end

		-- grab nearby static scenery into the WorldModel
		local function rebuildScenery()
			if not (world and heroFloor and heroFloor.Parent) then return end
			-- drop previous scenery clones (keep the character clones)
			for _, child in ipairs(world:GetChildren()) do
				if not child:GetAttribute("CinCharClone") then
					pcall(function() child:Destroy() end)
				end
			end
			overlap.FilterDescendantsInstances = { ctx.worldFolder, heroFloor }
			if lp and lp.Character then
				overlap.FilterDescendantsInstances = { ctx.worldFolder, heroFloor, lp.Character }
			end
			local origin = heroFloor.Position + Vector3.new(0, CLONE_RADIUS * 0.35, 0)
			local box = Vector3.new(CLONE_RADIUS * 2, CLONE_RADIUS * 1.2, CLONE_RADIUS * 2)
			local nearby = workspace:GetPartBoundsInBox(CFrame.new(origin), box, overlap)
			local n = 0
			for _, part in ipairs(nearby) do
				if n >= CLONE_CAP then break end
				if part.Anchored and part ~= heroFloor and part.Transparency < 1 then
					local ok, cl = pcall(function()
						local c = part:Clone()
						sanitizeClone(c)
						c.Anchored = true
						c.CanCollide = false
						c.Parent = world
						return c
					end)
					if ok and cl then n += 1 end
				end
			end
		end

		-- clone the local character once; map clone parts to originals for per-frame sync
		local function rebuildCharacter()
			table.clear(charClones)
			local char = lp and lp.Character
			if not (char and world) then return end
			local ok, cc = pcall(function() return char:Clone() end)
			if not ok or not cc then return end
			sanitizeClone(cc)
			cc:SetAttribute("CinCharClone", true)
			cc.Parent = world
			-- clone preserves descendant order, so we can pair by index
			local origs, clones = char:GetDescendants(), cc:GetDescendants()
			for i, op in ipairs(origs) do
				local cp = clones[i]
				if op:IsA("BasePart") and cp and cp:IsA("BasePart") then
					cp.Anchored = true
					charClones[#charClones + 1] = { op, cp }
				end
			end
		end

		local function buildMirrorOn(floor)
			clearMirror()
			heroFloor = floor
			-- CanvasSize scales with the probe-resolution budget (sharper when higher).
			local canvas = math.clamp(res * 4, 256, 1024)
			surface = Snapshot.create("SurfaceGui", {
				Name = "MirrorSurface", Face = Enum.NormalId.Top,
				CanvasSize = Vector2.new(canvas, canvas), LightInfluence = 0,
				ClipsDescendants = true,
			}, floor)
			vpf = Snapshot.create("ViewportFrame", {
				Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
				Ambient = Lighting.OutdoorAmbient,
				LightColor = Color3.fromRGB(255, 250, 242),
			}, surface)
			world = Snapshot.create("WorldModel", {}, vpf)
			vpCam = Snapshot.create("Camera", {}, vpf)
			vpf.CurrentCamera = vpCam
			rebuildCharacter()
			rebuildScenery()
		end

		-- find the floor under the player (raycast straight down from the root)
		local function floorUnderPlayer()
			local char = lp and lp.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then return nil end
			local result = workspace:Raycast(hrp.Position, Vector3.new(0, -12, 0), downParams)
			if result and result.Instance and result.Instance:IsA("BasePart") then
				local part = result.Instance
				-- must be a broad, roughly-flat, up-facing surface to be a mirror plane
				local up = part.CFrame.UpVector
				if up:Dot(Vector3.yAxis) > 0.8 and (part.Size.X * part.Size.Z) >= 80 then
					return part
				end
			end
			return nil
		end

		-- ── timers ───────────────────────────────────────────────────────────
		local repickAccum, refreshAccum, frameAccum = 0, 0, 0
		local sinceBuild = 999     -- cooldown so crossing many floor parts can't thrash rebuilds

		maid:give(RunService.PreRender:Connect(function(dt)
			repickAccum += dt
			sinceBuild += dt
			if repickAccum >= REPICK_EVERY then
				repickAccum = 0
				local floor = floorUnderPlayer()
				-- only re-home the mirror onto a NEW floor at most every ~1.5s
				if floor and floor ~= heroFloor and sinceBuild >= 1.5 then
					buildMirrorOn(floor)
					sinceBuild = 0
				elseif not floor and heroFloor and not heroFloor.Parent then
					clearMirror(); heroFloor = nil
				end
			end

			if not (heroFloor and heroFloor.Parent and vpCam and surface) then return end

			-- wet sheen: wetter floor → stronger (less transparent) mirror
			local wet = math.clamp(State.get("reflect_wetness") + (ctx.bus.wetness or 0) * State.get("weather_wet_boost"), 0, 1)
			vpf.ImageTransparency = math.clamp(1 - (0.35 + wet * 0.55), 0.15, 0.72)

			refreshAccum += dt
			if refreshAccum >= CLONE_REFRESH then
				refreshAccum = 0
				rebuildScenery()
			end

			frameAccum += dt
			if frameAccum < MIRROR_DT then return end
			frameAccum = 0

			local cam = ctx.camera()
			if not cam then return end

			-- reflect the camera across the floor plane (position + orientation)
			local n = heroFloor.CFrame.UpVector
			local planePoint = heroFloor.Position + n * (heroFloor.Size.Y * 0.5)
			local camCF = cam.CFrame
			local pos = camCF.Position
			local d = (pos - planePoint):Dot(n)
			local mPos = pos - 2 * d * n
			local look = camCF.LookVector
			local up = camCF.UpVector
			local mLook = look - 2 * look:Dot(n) * n
			local mUp = up - 2 * up:Dot(n) * n
			if mLook.Magnitude > 1e-3 then
				vpCam.CFrame = CFrame.lookAt(mPos, mPos + mLook, mUp)
				vpCam.FieldOfView = cam.FieldOfView
			end

			-- sync the live character pose into its clone (you, animating, in the mirror)
			for _, pair in ipairs(charClones) do
				local op, cp = pair[1], pair[2]
				if op.Parent and cp.Parent then
					cp.CFrame = op.CFrame
				end
			end

			-- keep the viewport sun roughly matched to the scene
			pcall(function() vpf.LightDirection = Lighting:GetSunDirection() end)
		end))

		ctx.log.debug("ViewportMirror online (floor-under-player + self reflection)")
		return ViewportMirror
	end

	function ViewportMirror.stop()
		if ViewportMirror._maid then ViewportMirror._maid:clean() end
	end

	return ViewportMirror
end
