--!nonstrict
--[[
	src/init.lua  —  ENTRY POINT
	=============================================================================
	Boots the whole suite and returns the public API handle.

	Responsibilities:
	  1. Double-load guard — if a suite is already live in the shared global table
	     (getgenv() on executors, else _G), surface its UI and return its API
	     instead of stacking a second pipeline.
	  2. Build the boot CONTEXT (`ctx`) handed to every controller's start(ctx).
	  3. Start each manifest.boot controller in order, each wrapped in pcall so one
	     failing subsystem cannot abort the rest.
	  4. Publish the global handle and return it.

	=============================================================================
	THE MODULE CONTRACT (every src/*.lua follows this)
	-----------------------------------------------------------------------------
	    return function(require)        -- factory; `require` is the injected shim
	        local Module = {}
	        function Module.start(ctx)  -- called once by init or a parent controller
	            local maid = ctx.maid:childMaid()   -- OWN your cleanup
	            -- read ctx.state, apply effects, subscribe via maid:give(...)
	            return Module
	        end
	        function Module.setQuality(q) end   -- OPTIONAL: scale budget 0..1
	        function Module.stop() end          -- OPTIONAL: explicit early stop
	        return Module
	    end

	THE CONTEXT (`ctx`) — shared across all modules
	-----------------------------------------------------------------------------
	    ctx.require      injected require shim (lazy-load any sibling by name)
	    ctx.maid         ROOT Maid. Call ctx.maid:childMaid() to own your cleanup.
	    ctx.state        core/State          (live settings; :get/:set/:observe)
	    ctx.config       core/Config         (metadata)
	    ctx.snapshot     core/Snapshot       (capture/restore/create — USE THIS to
	                                          mutate ANY foreign property/instance)
	    ctx.util         core/Util
	    ctx.log          core/Logger
	    ctx.platform     core/Platform       (.caps, .isMobile, …)
	    ctx.services     pre-fetched services table (Lighting, Workspace, …)
	    ctx.worldFolder  tagged Folder in Workspace for world instances (beams…)
	    ctx.gui          tagged ScreenGui for overlays (vignette/grain/letterbox…)
	    ctx.camera()     returns the current workspace.CurrentCamera (re-fetch!)
	    ctx.getQuality() effective quality 0..1 (global × adaptive multiplier)
	    ctx.bus          shared scratch table for cross-module live values, e.g.
	                       bus.exposure       (EyeAdaptation writes, Bloom reads)
	                       bus.sceneLuminance
	                       bus.camCFrame / bus.camDelta (CameraFX writes)
	    ctx.perf         { report(name, ms), get() } per-effect cost bus (PerfHUD)
	    ctx.registerHandle(handle)  add a started module to the setQuality fan-out
	=============================================================================
]]

return function(require)
	local manifest = require("manifest")
	local Logger = require("core/Logger")
	local Platform = require("core/Platform")
	local State = require("core/State")
	local Config = require("core/Config")
	local Snapshot = require("core/Snapshot")
	local Util = require("core/Util")
	local Maid = require("core/Maid")

	-- Apply persisted log level immediately.
	Logger.setLevel(State.get("log_level"))

	local GLOBAL_KEY = "__CINEMATIC_SHADER"
	local globals = Platform.globalTable()

	-- ── 1. double-load guard ─────────────────────────────────────────────────
	local existing = globals[GLOBAL_KEY]
	if existing and type(existing) == "table" and existing.__alive then
		Logger.warn("Suite already loaded — surfacing existing instance.")
		pcall(function() if existing.toggleUI then existing.toggleUI(true) end end)
		return existing
	end

	-- ── 2. build context ─────────────────────────────────────────────────────
	local rootMaid = Maid.new()

	local services = {}
	for _, name in ipairs({
		"Lighting", "Workspace", "RunService", "Players", "UserInputService",
		"TweenService", "CollectionService", "HttpService", "StarterGui",
		"GuiService", "AssetService", "ContextActionService", "ReplicatedStorage",
	}) do
		local ok, svc = pcall(game.GetService, game, name)
		services[name] = ok and svc or nil
	end

	-- A single tagged Folder in Workspace holds all world instances we create.
	local worldFolder = Snapshot.create("Folder", { Name = "CinematicSuite" }, services.Workspace)

	-- A single ScreenGui holds all faked overlays. Prefer gethui() on executors
	-- so the host game cannot see/clobber our UI; else PlayerGui.
	local guiParent
	if Platform.caps.gethui then
		local ok, hui = pcall(gethui)
		if ok then guiParent = hui end
	end
	if not guiParent then
		local lp = services.Players.LocalPlayer
		guiParent = lp and lp:WaitForChild("PlayerGui", 5)
	end
	local overlayGui = Snapshot.create("ScreenGui", {
		Name = "CinematicOverlays",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 9_999,
	}, guiParent)

	-- effective quality = global slider × adaptive multiplier (AdaptiveQuality
	-- writes bus.qualityMul; default 1).
	local bus = { exposure = State.get("lighting_exposure"), qualityMul = 1 }

	-- per-effect cost bus for the PerfHUD
	local perfCosts = {}
	local perf = {
		report = function(name, ms) perfCosts[name] = ms end,
		get = function() return perfCosts end,
	}

	local startedHandles = {}

	local ctx
	ctx = {
		require = require,
		maid = rootMaid,
		state = State,
		config = Config,
		snapshot = Snapshot,
		util = Util,
		log = Logger,
		platform = Platform,
		services = services,
		worldFolder = worldFolder,
		gui = overlayGui,
		bus = bus,
		perf = perf,
		manifest = manifest,
		camera = function()
			return services.Workspace.CurrentCamera
		end,
		getQuality = function()
			return Util.clamp(State.get("quality") * (bus.qualityMul or 1), 0, 1)
		end,
		registerHandle = function(handle)
			if handle then startedHandles[#startedHandles + 1] = handle end
		end,
	}

	-- ── 3. start controllers ─────────────────────────────────────────────────
	Logger.info(("Booting v%s — %s"):format(manifest.version, Platform.describe()))
	for _, name in ipairs(manifest.boot) do
		local ok, handle = pcall(function()
			local mod = require(name)
			if type(mod) == "table" and type(mod.start) == "function" then
				return mod.start(ctx) or mod
			end
			return mod
		end)
		if ok and handle then
			ctx.registerHandle(handle)
			Logger.debug("started", name)
		else
			Logger.error("controller failed:", name, "->", handle)
		end
	end

	-- propagate the current quality once everything is up
	local function fanoutQuality()
		local q = ctx.getQuality()
		for _, h in ipairs(startedHandles) do
			if type(h.setQuality) == "function" then
				pcall(h.setQuality, q)
			end
		end
	end
	rootMaid:give(State.observe("quality", fanoutQuality))
	-- expose for AdaptiveQuality (it changes bus.qualityMul then re-fans out)
	ctx.fanoutQuality = fanoutQuality

	-- ── 4. publish handle ────────────────────────────────────────────────────
	-- The full public API lives in api/API; init seeds the minimal shape so the
	-- double-load guard works even if api/API failed to load.
	local handle = globals[GLOBAL_KEY]
	if not (type(handle) == "table") then
		handle = {}
		globals[GLOBAL_KEY] = handle
	end
	handle.__alive = true
	handle.version = manifest.version
	handle.ctx = ctx
	handle._handles = startedHandles
	handle._fanoutQuality = fanoutQuality
	handle.loadSource = handle.loadSource or "unknown"

	if State.get("intro_notify") then
		pcall(function()
			if handle.notify then
				handle.notify("Cinematic Suite", "Loaded v" .. manifest.version, 4)
			end
		end)
	end

	Logger.info("Boot complete.")
	return handle
end
