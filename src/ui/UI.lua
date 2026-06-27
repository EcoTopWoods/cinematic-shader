--!nonstrict
--[[
	ui/UI.lua  —  CONTROLLER (manifest.boot, near last)
	-----------------------------------------------------------------------------
	Builds the control panel with the FLUENT library (sleek, app-style dark UI —
	swapped in for Rayfield). One window, a tab per Config.tabs, every setting
	AUTO-GENERATED from ui/Schema (live), and only the ACTION controls hand-wired
	(presets, import/export, freecam, photo mode, re-benchmark, unload). Wires the
	toggle keybind and the Notify entry-point. Falls back to ui/FallbackUI if Fluent
	can't be fetched/loaded.

	Fluent is executor/Studio-loaded over HTTP — every remote call is pcall-guarded,
	so a partial API mismatch degrades gracefully instead of breaking the boot.
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

	-- Lucide icon per tab (Fluent supports Lucide names). Safe set; if an icon ever
	-- rejects, the tab is recreated without one.
	local TAB_ICONS = {
		["General"] = "settings", ["Lighting"] = "sun", ["Reflections"] = "droplet",
		["Atmosphere & Weather"] = "cloud", ["Camera & Cinematic"] = "camera",
		["Materials"] = "box", ["Performance"] = "activity", ["Presets"] = "sliders",
		["About"] = "info",
	}

	local function loadFluent()
		if not (Platform.caps.httpGet and Platform.caps.loadstring) then return nil end
		local ok, lib = pcall(function()
			return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
		end)
		if ok and type(lib) == "table" then return lib end
		Logger.warn("Fluent load failed:", lib)
		return nil
	end

	-- which GUI container Fluent will parent into (so we can find its ScreenGui after)
	local function guiContainer()
		if Platform.caps.gethui then
			local ok, hui = pcall(gethui)
			if ok and hui then return hui end
		end
		local ok, cg = pcall(function() return game:GetService("CoreGui") end)
		if ok and cg then return cg end
		local lp = game:GetService("Players").LocalPlayer
		return lp and lp:FindFirstChild("PlayerGui") or nil
	end

	function UI.start(ctx)
		local maid = ctx.maid:childMaid()
		UI._maid = maid
		local globals = Platform.globalTable()
		local handle = globals["__CINEMATIC_SHADER"] or {}

		local function mountFallback()
			local Fallback = require("ui/FallbackUI")
			Fallback.start(ctx); ctx.registerHandle(Fallback)
			UI.toggle = UI.toggle or function() end
			ctx.toggleUI = UI.toggle
			handle.toggleUI = UI.toggle
			handle.notify = Notify.send
			ctx.notify = Notify.send
		end

		local Fluent = loadFluent()
		if not Fluent then
			Logger.warn("Mounting FallbackUI (Fluent unavailable).")
			mountFallback()
			return UI
		end
		UI._fluent = Fluent
		Notify.setLib(Fluent)

		-- snapshot existing ScreenGuis so we can identify the one Fluent creates
		local container = guiContainer()
		local before = {}
		if container then
			for _, g in ipairs(container:GetChildren()) do before[g] = true end
		end

		-- resolve the toggle key for Fluent's built-in minimize bind
		local minKey = Enum.KeyCode.RightShift
		do
			local ok, kc = pcall(function() return Enum.KeyCode[tostring(State.get("ui_keybind"))] end)
			if ok and kc then minKey = kc end
		end

		local window
		local okWin = pcall(function()
			window = Fluent:CreateWindow({
				Title = "Cinematic Suite",
				SubTitle = "v" .. Config.version .. "  •  client-side visual suite",
				TabWidth = 150,
				Size = UDim2.fromOffset(600, 470),
				Acrylic = false,            -- max executor compatibility; dark theme still reads pro
				Theme = "Dark",
				MinimizeKey = minKey,
			})
		end)
		if not okWin or not window then
			Logger.error("Fluent CreateWindow failed — falling back.")
			mountFallback()
			return UI
		end
		UI._window = window

		-- find Fluent's freshly-created ScreenGui (for programmatic toggleUI)
		if container then
			for _, g in ipairs(container:GetChildren()) do
				if not before[g] and g:IsA("ScreenGui") then UI._gui = g; break end
			end
		end

		-- ── tabs ──────────────────────────────────────────────────────────────
		local tabsByName = {}
		for _, name in ipairs(Config.tabs) do
			local tab
			local ok = pcall(function()
				tab = window:AddTab({ Title = name, Icon = TAB_ICONS[name] or "" })
			end)
			if not ok or not tab then
				pcall(function() tab = window:AddTab({ Title = name }) end) -- retry without icon
			end
			if tab then tabsByName[name] = tab end
		end

		-- ── auto-generated settings ────────────────────────────────────────────
		local registry = Schema.build(tabsByName, ctx)
		UI._registry = registry

		-- State → UI sync (preset/import refresh). The equal-value guard inside
		-- State.set breaks any feedback loop.
		maid:give(State.changed:Connect(function(key, value)
			local control = registry[key]
			if control then Controls.setValue(control, Config.meta[key], value) end
		end))

		-- ── hand-wired ACTIONS ─────────────────────────────────────────────────
		UI._wireActions(ctx, tabsByName, handle)

		-- ── toggle (Fluent minimize handles the keybind; this is the programmatic path)
		UI.toggle = function(on)
			local gui = UI._gui
			if gui then
				if on == nil then on = not gui.Enabled end
				gui.Enabled = on and true or false
			end
		end
		ctx.toggleUI = UI.toggle
		handle.toggleUI = UI.toggle
		handle.notify = Notify.send
		ctx.notify = Notify.send

		-- backup keybind (in case MinimizeKey differs from the user's chosen key live)
		maid:give(ctx.services.UserInputService.InputBegan:Connect(function(input, gp)
			if gp then return end
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
			local ok, kc = pcall(function() return Enum.KeyCode[tostring(State.get("ui_keybind"))] end)
			if ok and kc and input.KeyCode == kc and kc ~= minKey then
				UI.toggle()
			end
		end))

		pcall(function() window:SelectTab(1) end)

		if State.get("intro_notify") then
			Notify.send("Cinematic Suite", "v" .. Config.version .. " loaded. Press " ..
				tostring(State.get("ui_keybind")) .. " to minimise.", 5)
		end

		Logger.debug("UI online (Fluent)")
		return UI
	end

	function UI._wireActions(ctx, tabsByName, handle)
		local camTab = tabsByName["Camera & Cinematic"]
		local presetTab = tabsByName["Presets"]
		local perfTab = tabsByName["Performance"]
		local aboutTab = tabsByName["About"]

		if camTab then
			pcall(function() camTab:AddParagraph({ Title = "Actions", Content = "" }) end)
			pcall(function()
				camTab:AddButton({ Title = "Toggle Freecam", Description = "WASD/gamepad fly camera",
					Callback = function() require("camera/Freecam").toggle() end })
			end)
			pcall(function()
				camTab:AddButton({ Title = "Toggle Photo Mode", Description = "Hide UI, lock cam, composition aids",
					Callback = function() require("camera/PhotoMode").toggle() end })
			end)
		end

		if presetTab then
			local Presets = require("presets/Presets")
			local Serializer = require("presets/Serializer")
			local ConfigStore = require("presets/ConfigStore")
			pcall(function() presetTab:AddParagraph({ Title = "Look Presets", Content = "Pick a look, then Apply." }) end)
			local chosen = Presets.current()
			pcall(function()
				presetTab:AddDropdown("preset_pick", {
					Title = "Preset", Values = Presets.names(), Multi = false, Default = chosen,
					Callback = function(o) chosen = (type(o) == "table") and (next(o) or o[1]) or o end,
				})
			end)
			pcall(function()
				presetTab:AddButton({ Title = "Apply Preset", Callback = function()
					Presets.apply(chosen)
					require("ui/Notify").send("Preset", "Applied: " .. tostring(chosen), 3)
				end })
			end)
			pcall(function() presetTab:AddParagraph({ Title = "Import / Export", Content = "Portable JSON config." }) end)
			pcall(function()
				presetTab:AddButton({ Title = "Export config", Description = "Copy to clipboard (+ save if supported)",
					Callback = function()
						local json = Serializer.export()
						if json then
							if Platform.caps.setclipboard then pcall(setclipboard, json) end
							if ConfigStore.available() then ConfigStore.save(json) end
							require("ui/Notify").send("Export", "Config copied to clipboard.", 4)
						end
					end })
			end)
			local importBox = ""
			pcall(function()
				presetTab:AddInput("import_box", {
					Title = "Paste config JSON", Placeholder = "{ \"v\":1, \"data\":{...} }",
					Finished = true, Callback = function(t) importBox = t end,
				})
			end)
			pcall(function()
				presetTab:AddButton({ Title = "Import config", Callback = function()
					local ok, n = Serializer.import(importBox)
					require("ui/Notify").send("Import", ok and ("Applied " .. tostring(n) .. " settings.")
						or ("Failed: " .. tostring(n)), 4)
				end })
			end)
		end

		if perfTab then
			pcall(function() perfTab:AddParagraph({ Title = "Actions", Content = "" }) end)
			pcall(function()
				perfTab:AddButton({ Title = "Re-run Benchmark", Callback = function()
					local tier = require("perf/Benchmark").run()
					require("ui/Notify").send("Benchmark", "Re-tiered: " .. tostring(tier), 3)
				end })
			end)
		end

		if aboutTab then
			pcall(function()
				aboutTab:AddParagraph({
					Title = "Cinematic Graphics Suite v" .. Config.version,
					Content = "Client-side visual suite. Composes Roblox's built-in lighting, post-"
						.. "processing, atmosphere and particles — Roblox exposes no GPU shaders, so "
						.. "reflections are an honest SSR approximation, not ray tracing.\n\nLoad source: "
						.. tostring(handle.loadSource or "unknown"),
				})
			end)
			pcall(function()
				aboutTab:AddButton({ Title = "Show Last Error", Callback = function()
					require("ui/Notify").send("Last Error", tostring(Logger.getLastError() or "none"), 6)
				end })
			end)
			pcall(function()
				aboutTab:AddButton({ Title = "⛔ Unload / Kill", Description = "Restore the game exactly + remove the suite",
					Callback = function() require("api/Teardown").kill() end })
			end)
		end
	end

	function UI.stop()
		if UI._fluent then
			pcall(function() if UI._fluent.Destroy then UI._fluent:Destroy() end end)
			pcall(function() UI._fluent.Unloaded = true end)
		end
		if UI._gui then pcall(function() UI._gui:Destroy() end) end
		if UI._maid then UI._maid:clean() end
	end

	return UI
end
