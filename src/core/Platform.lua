--!nonstrict
--[[
	core/Platform.lua
	-----------------------------------------------------------------------------
	Capability + device detection. Feature-detect, never assume.

	WHY: This suite targets vanilla Roblox clients AND executor environments, on
	desktop AND mobile, on Future lighting AND legacy fallbacks. Every risky
	capability (executor HTTP, EditableImage, Future lighting) is probed once
	here and exposed as a boolean so the rest of the code can `if Platform.caps.X`
	rather than re-pcalling everywhere.

	HARD TRUTHS honoured:
	  * loadstring/HttpGet/writefile/setclipboard/syn.request are EXECUTOR-only.
	  * EditableImage needs an ID-verified 13+ creator in published games — we
	    feature-detect by attempting a tiny image and degrade if it errors.
	  * Future lighting / Clouds silently degrade on low-end; we only report
	    whether the *enum* exists, not whether the GPU honours it.
]]

return function(require)
	local Logger = require("core/Logger")

	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")
	local GuiService = game:GetService("GuiService")
	local RunService = game:GetService("RunService")

	local Platform = {}
	Platform.caps = {}
	local caps = Platform.caps

	-- ── environment ─────────────────────────────────────────────────────────
	-- getgenv is the executor global table; absent in vanilla/Studio.
	local hasGetgenv = (typeof(getgenv) == "function")
	caps.executor = hasGetgenv or (typeof(syn) == "table") or (typeof(request) == "function")
	caps.studio = RunService:IsStudio()

	-- Shared global table: executor getgenv() if present, else _G.
	function Platform.globalTable()
		if hasGetgenv then
			local ok, g = pcall(getgenv)
			if ok and type(g) == "table" then return g end
		end
		return _G
	end

	-- ── executor file / net capabilities (all optional) ──────────────────────
	caps.httpGet = (typeof(game.HttpGet) == "function") or (typeof((syn or {}).request) == "function")
		or (typeof(request) == "function") or (typeof(http_request) == "function")
	caps.writefile = (typeof(writefile) == "function")
	caps.readfile = (typeof(readfile) == "function")
	caps.isfile = (typeof(isfile) == "function")
	caps.makefolder = (typeof(makefolder) == "function")
	caps.setclipboard = (typeof(setclipboard) == "function")
	caps.loadstring = (typeof(loadstring) == "function")
	-- gethui hides protected GUIs from the game on executors; fall back to PlayerGui.
	caps.gethui = (typeof(gethui) == "function")

	-- ── lighting capabilities ────────────────────────────────────────────────
	local function enumExists(group, name)
		local ok, val = pcall(function() return (Enum :: any)[group][name] end)
		return ok and val ~= nil, ok and val or nil
	end
	caps.futureLighting = enumExists("Technology", "Future")
	caps.realisticLightingStyle = enumExists("LightingStyle", "Realistic")
	do
		-- ShadowSoftness only exists on newer Lighting; probe the property.
		local okProp = pcall(function() return game:GetService("Lighting").ShadowSoftness end)
		caps.shadowSoftness = okProp
		local okPrio = pcall(function() return (game:GetService("Lighting") :: any).PrioritizeLightingQuality end)
		caps.prioritizeLightingQuality = okPrio
	end

	-- ── EditableImage / EditableMesh (CPU pixel work) ─────────────────────────
	-- Feature-detect properly: the API may exist but be gated to verified 13+
	-- creators, in which case CreateEditableImage throws at runtime.
	do
		local AssetService = game:GetService("AssetService")
		local ok = false
		if typeof(AssetService.CreateEditableImage) == "function" then
			ok = pcall(function()
				-- Newer signature takes a props table; older took (Vector2).
				local img = AssetService:CreateEditableImage({ Size = Vector2.new(8, 8) })
				if img then img:Destroy() end
			end)
			if not ok then
				ok = pcall(function()
					local img = (AssetService :: any):CreateEditableImage(Vector2.new(8, 8))
					if img then img:Destroy() end
				end)
			end
		end
		caps.editableImage = ok
	end

	-- ── device / input ────────────────────────────────────────────────────────
	caps.touch = UserInputService.TouchEnabled
	caps.keyboard = UserInputService.KeyboardEnabled
	caps.mouse = UserInputService.MouseEnabled
	caps.gamepad = UserInputService.GamepadEnabled
	caps.tenFootInterface = GuiService:IsTenFootInterface() -- console

	-- Heuristic: mobile = touch & not keyboard, OR a small screen.
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	caps.screenSize = viewport
	Platform.isMobile = (caps.touch and not caps.keyboard) or (viewport.X > 0 and viewport.X < 800)
	Platform.isConsole = caps.tenFootInterface
	Platform.isDesktop = not Platform.isMobile and not Platform.isConsole

	-- Coarse performance tier guess from device class; refined later by Benchmark.
	-- 1 = potato/mobile, 2 = mid, 3 = high desktop.
	Platform.tierGuess = Platform.isMobile and 1 or (Platform.isConsole and 2 or 3)

	function Platform.localPlayer()
		return Players.LocalPlayer
	end

	function Platform.describe()
		return string.format(
			"device=%s executor=%s future=%s editableImage=%s screen=%dx%d",
			Platform.isMobile and "mobile" or (Platform.isConsole and "console" or "desktop"),
			tostring(caps.executor), tostring(caps.futureLighting),
			tostring(caps.editableImage), viewport.X, viewport.Y
		)
	end

	Logger.info("Platform:", Platform.describe())
	return Platform
end
