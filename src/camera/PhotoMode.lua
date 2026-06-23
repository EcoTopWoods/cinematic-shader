--!nonstrict
--[[
	camera/PhotoMode.lua
	-----------------------------------------------------------------------------
	A clean composition mode for screenshots:
	  * hides the game HUD (CoreGui) and our own control panel,
	  * shows rule-of-thirds guides + a level-horizon indicator (rotates with camera
	    roll so you can level the shot),
	  * keeps the cinematic grade/overlays for the "final frame" look,
	  * prompts the user to capture (Roblox/OS screenshot — there is no reliable
	    in-engine capture API; an executor hook is used if present).

	Pairs with Freecam for positioning. Does NOT seize the camera (non-exclusive),
	honouring the contention rule. Everything restores on exit.
]]

return function(require)
	local Maid = require("core/Maid")

	local PhotoMode = {}
	PhotoMode.id = "camera/PhotoMode"
	local active = false

	function PhotoMode.start(ctx)
		PhotoMode._ctx = ctx
		PhotoMode._maid = ctx.maid:childMaid()
		PhotoMode._maid:give(function() if active then PhotoMode.toggle(false) end end)
		return PhotoMode
	end

	function PhotoMode.isActive() return active end

	function PhotoMode.toggle(on)
		if on == nil then on = not active end
		if on == active then return end
		if on then PhotoMode._enable() else PhotoMode._disable() end
	end

	function PhotoMode._enable()
		local ctx = PhotoMode._ctx
		active = true
		local session = Maid.new()
		PhotoMode._session = session
		local Snapshot = ctx.snapshot

		-- hide game HUD
		pcall(function()
			ctx.services.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		end)
		session:give(function()
			pcall(function() ctx.services.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
		end)

		-- hide our control panel (Rayfield) if present
		if ctx.toggleUI then pcall(ctx.toggleUI, false) end

		-- aids container
		local aids = Snapshot.create("Frame", {
			Name = "PhotoAids", BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1), ZIndex = 80, Active = false,
		}, ctx.gui)
		session:give(aids)

		local function gridLine(size, pos)
			Snapshot.create("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.7,
				BorderSizePixel = 0, Size = size, Position = pos, ZIndex = 80, Active = false,
			}, aids)
		end
		-- rule of thirds
		gridLine(UDim2.new(0, 1, 1, 0), UDim2.fromScale(1 / 3, 0))
		gridLine(UDim2.new(0, 1, 1, 0), UDim2.fromScale(2 / 3, 0))
		gridLine(UDim2.new(1, 0, 0, 1), UDim2.fromScale(0, 1 / 3))
		gridLine(UDim2.new(1, 0, 0, 1), UDim2.fromScale(0, 2 / 3))

		-- horizon indicator (rotates to stay world-level)
		local horizon = Snapshot.create("Frame", {
			Name = "Horizon", BackgroundColor3 = Color3.fromRGB(120, 220, 140),
			BackgroundTransparency = 0.4, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.5, 0, 0, 2), ZIndex = 81, Active = false,
		}, aids)

		session:give(ctx.services.RunService.PreRender:Connect(function()
			local cam = ctx.camera()
			if not cam then return end
			-- camera roll: angle of RightVector off the horizontal plane
			local rv = cam.CFrame.RightVector
			local roll = math.atan2(rv.Y, Vector3.new(rv.X, 0, rv.Z).Magnitude)
			horizon.Rotation = math.deg(roll)
			horizon.BackgroundColor3 = (math.abs(roll) < 0.02)
				and Color3.fromRGB(120, 220, 140) or Color3.fromRGB(220, 180, 120)
		end))

		PhotoMode._tryScreenshotHint(ctx)
		PhotoMode._maid:give(session)
		ctx.log.debug("PhotoMode enabled")
	end

	function PhotoMode._tryScreenshotHint(ctx)
		-- No reliable in-engine capture; try executor hooks, else prompt.
		local captured = false
		for _, name in ipairs({ "captureScreenshot", "take_screenshot" }) do
			local fn = (getgenv and getgenv()[name]) or rawget(_G, name)
			if typeof(fn) == "function" then
				captured = pcall(fn)
				if captured then break end
			end
		end
		if not captured and ctx.notify then
			pcall(ctx.notify, "Photo Mode", "Compose, then use your screenshot key. Toggle again to exit.", 5)
		end
	end

	function PhotoMode._disable()
		local ctx = PhotoMode._ctx
		active = false
		if PhotoMode._session then
			PhotoMode._session:clean()
			PhotoMode._session = nil
		end
		if ctx.toggleUI then pcall(ctx.toggleUI, true) end
		ctx.log.debug("PhotoMode disabled")
	end

	function PhotoMode.stop() if PhotoMode._maid then PhotoMode._maid:clean() end end

	return PhotoMode
end
