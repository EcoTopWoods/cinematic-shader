--!nonstrict
--[[
	ui/UI.lua  —  CONTROLLER (manifest.boot, near last)
	-----------------------------------------------------------------------------
	Builds the Rayfield control panel: one window with ConfigurationSaving, a tab per
	Config.tabs, every config setting AUTO-GENERATED from ui/Schema (live + persisted),
	and only the ACTION controls hand-wired (Freecam, Photo Mode, presets, import/
	export, re-benchmark, unload). Wires the toggle keybind and the Notify entry-point.
	Falls back to ui/FallbackUI if Rayfield can't be fetched/loaded.

	Rayfield is executor/Studio-loaded over HTTP — every remote call is pcall-guarded.
]]

return function(require)
	local State = require("core/State")
	local Config = require("core/Config")
	local Logger = require("core/Logger")
	local Platform = require("core/Platform")
	local Schema = require("ui/Schema")
	local Controls = require("ui/Controls")
	local Notify = require("ui/Notify")

	local UI = {}
	UI.id = "ui/UI"

	local function loadRayfield()
		if not (Platform.caps.httpGet and Platform.caps.loadstring) then return nil end
		local ok, lib = pcall(function()
			return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
		end)
		if ok and type(lib) == "table" then return lib end
		Logger.warn("Rayfield load failed:", lib)
		return nil
	end

	local function findRayfieldGui()
		local candidates = {}
		if Platform.caps.gethui then
			local ok, hui = pcall(gethui)
			if ok then candidates[#candidates + 1] = hui end
		end
		pcall(function() candidates[#candidates + 1] = game:GetService("CoreGui") end)
		local lp = game:GetService("Players").LocalPlayer
		if lp then candidates[#candidates + 1] = lp:FindFirstChild("PlayerGui") end
		for _, parent in ipairs(candidates) do
			if parent then
				local gui = parent:FindFirstChild("Rayfield")
				if gui then return gui end
			end
		end
		return nil
	end

	function UI.start(ctx)
		local maid = ctx.maid:childMaid()
		UI._maid = maid
		local globals = Platform.globalTable()
		local handle = globals["__CINEMATIC_SHADER"] or {}

		local Rayfield = loadRayfield()
		if not Rayfield then
			Logger.warn("Mounting FallbackUI (Rayfield unavailable).")
			local Fallback = require("ui/FallbackUI")
			Fallback.start(ctx)
			ctx.registerHandle(Fallback)
			-- minimal toggle + notify still available
			UI.toggle = function() end
			ctx.toggleUI = UI.toggle
			handle.toggleUI = UI.toggle
			handle.notify = Notify.send
			ctx.notify = Notify.send
			return UI
		end
		UI._rayfield = Rayfield
		Notify.setRayfield(Rayfield)

		-- ── window ────────────────────────────────────────────────────────────
		local placeId = 0
		pcall(function() placeId = game.PlaceId end)
		local window
		local okWin = pcall(function()
			window = Rayfield:CreateWindow({
				Name = "Cinematic Suite  v" .. Config.version,
				LoadingTitle = "Cinematic Graphics Suite",
				LoadingSubtitle = "by a senior rendering engineer",
				ConfigurationSaving = {
					Enabled = true,
					FolderName = "CinematicSuite",
					-- save-slot is suffixed with a tuning epoch: bumping it makes a
					-- retuned release start from fresh defaults instead of reloading a
					-- user's old (e.g. blown-out) saved values.
					FileName = "settings_t8_" .. tostring(placeId),
				},
				Discord = { Enabled = false },
				KeySystem = false,
			})
		end)
		if not okWin or not window then
			Logger.error("Rayfield CreateWindow failed — falling back.")
			local Fallback = require("ui/FallbackUI")
			Fallback.start(ctx); ctx.registerHandle(Fallback)
			return UI
		end
		UI._window = window

		-- ── tabs ──────────────────────────────────────────────────────────────
		local tabsByName = {}
		for _, name in ipairs(Config.tabs) do
			local ok, tab = pcall(function() return window:CreateTab(name) end)
			if ok and tab then tabsByName[name] = tab end
		end

		-- ── auto-generated settings ────────────────────────────────────────────
		local registry = Schema.build(tabsByName, ctx)
		UI._registry = registry

		-- State → UI sync (preset/import refresh). Equal-value guard in State.set
		-- breaks any feedback loop.
		maid:give(State.changed:Connect(function(key, value)
			local control = registry[key]
			if control then Controls.setValue(control, Config.meta[key], value) end
		end))

		-- ── hand-wired ACTIONS ─────────────────────────────────────────────────
		UI._wireActions(ctx, tabsByName, handle)

		-- ── toggle keybind ─────────────────────────────────────────────────────
		UI.toggle = function(on)
			local gui = UI._gui or findRayfieldGui()
			UI._gui = gui
			if gui then
				if on == nil then on = not gui.Enabled end
				gui.Enabled = on and true or false
			end
		end
		ctx.toggleUI = UI.toggle
		handle.toggleUI = UI.toggle
		handle.notify = Notify.send
		ctx.notify = Notify.send

		maid:give(ctx.services.UserInputService.InputBegan:Connect(function(input, gp)
			if gp then return end
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
			local name = State.get("ui_keybind")
			local ok, kc = pcall(function() return Enum.KeyCode[name] end)
			if ok and input.KeyCode == kc then
				UI.toggle()
			end
		end))

		-- persistence: load any flagged config Rayfield saved last session
		pcall(function() Rayfield:LoadConfiguration() end)

		if State.get("intro_notify") then
			Notify.send("Cinematic Suite", "Loaded. Press " .. tostring(State.get("ui_keybind")) .. " to toggle.", 5)
		end

		Logger.debug("UI online")
		return UI
	end

	function UI._wireActions(ctx, tabsByName, handle)
		local camTab = tabsByName["Camera & Cinematic"]
		local presetTab = tabsByName["Presets"]
		local perfTab = tabsByName["Performance"]
		local aboutTab = tabsByName["About"]

		-- Camera actions
		if camTab then
			pcall(function() camTab:CreateSection("Actions") end)
			pcall(function()
				camTab:CreateButton({ Name = "Toggle Freecam", Callback = function()
					require("camera/Freecam").toggle()
				end })
			end)
			pcall(function()
				camTab:CreateButton({ Name = "Toggle Photo Mode", Callback = function()
					require("camera/PhotoMode").toggle()
				end })
			end)
		end

		-- Presets + import/export
		if presetTab then
			local Presets = require("presets/Presets")
			local Serializer = require("presets/Serializer")
			local ConfigStore = require("presets/ConfigStore")
			pcall(function() presetTab:CreateSection("Look Presets") end)
			local chosen = Presets.current()
			pcall(function()
				presetTab:CreateDropdown({
					Name = "Preset", Options = Presets.names(),
					CurrentOption = { chosen }, MultipleOptions = false,
					Callback = function(o) chosen = (type(o) == "table") and o[1] or o end,
				})
			end)
			pcall(function()
				presetTab:CreateButton({ Name = "Apply Preset", Callback = function()
					Presets.apply(chosen)
					require("ui/Notify").send("Preset", "Applied: " .. tostring(chosen), 3)
				end })
			end)
			pcall(function() presetTab:CreateSection("Import / Export (portable JSON)") end)
			pcall(function()
				presetTab:CreateButton({ Name = "Export to Clipboard / Box", Callback = function()
					local json = Serializer.export()
					if json then
						if Platform.caps.setclipboard then pcall(setclipboard, json) end
						if ConfigStore.available() then ConfigStore.save(json) end
						require("ui/Notify").send("Export", "Config copied (and saved if supported).", 4)
					end
				end })
			end)
			local importBox = ""
			pcall(function()
				presetTab:CreateInput({
					Name = "Paste config JSON here",
					PlaceholderText = "{ \"v\":1, \"data\":{...} }",
					RemoveTextAfterFocusLost = false,
					Callback = function(t) importBox = t end,
				})
			end)
			pcall(function()
				presetTab:CreateButton({ Name = "Import from Box", Callback = function()
					local ok, n = Serializer.import(importBox)
					require("ui/Notify").send("Import", ok and ("Applied " .. tostring(n) .. " settings.") or ("Failed: " .. tostring(n)), 4)
				end })
			end)
		end

		-- Performance: re-benchmark
		if perfTab then
			pcall(function() perfTab:CreateSection("Actions") end)
			pcall(function()
				perfTab:CreateButton({ Name = "Re-run Benchmark", Callback = function()
					local tier = require("perf/Benchmark").run()
					require("ui/Notify").send("Benchmark", "Re-tiered: " .. tostring(tier), 3)
				end })
			end)
		end

		-- About
		if aboutTab then
			pcall(function() aboutTab:CreateSection("About") end)
			pcall(function()
				aboutTab:CreateParagraph({
					Title = "Cinematic Graphics Suite v" .. Config.version,
					Content = "A client-side visual enhancement suite. Composes Roblox's built-in "
						.. "lighting, post-processing, atmosphere and particle stack — no GPU shaders. "
						.. "Reflections are an honest SSR approximation, not ray tracing.\n\n"
						.. "Load source: " .. tostring(handle.loadSource or "unknown"),
				})
			end)
			pcall(function()
				aboutTab:CreateButton({ Name = "Show Last Error", Callback = function()
					require("ui/Notify").send("Last Error", tostring(Logger.getLastError() or "none"), 6)
				end })
			end)
			pcall(function()
				aboutTab:CreateButton({ Name = "⛔ UNLOAD / KILL", Callback = function()
					require("api/Teardown").kill()
				end })
			end)
		end
	end

	function UI.stop()
		-- Destroy the Rayfield window if present (its GUI is tagged by Rayfield, not
		-- us, so we explicitly Destroy it here; our own overlays go via the Maid).
		if UI._rayfield then pcall(function() UI._rayfield:Destroy() end) end
		if UI._maid then UI._maid:clean() end
	end

	return UI
end
