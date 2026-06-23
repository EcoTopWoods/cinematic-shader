--!nonstrict
--[[
	api/API.lua  —  CONTROLLER (manifest.boot, last)
	-----------------------------------------------------------------------------
	Defines the public programmatic surface on the global handle that init seeded in
	Platform.globalTable().__CINEMATIC_SHADER. Everything a script (or the user via
	the console) needs:

	    handle.get(key)               handle.set(key, value)
	    handle.applyPreset(name)      handle.toggleUI(on?)
	    handle.setQuality(n)          handle.exportConfig()  handle.importConfig(json)
	    handle.reBenchmark()          handle.getLastError()
	    handle.kill() / handle.destroy()           handle.version  handle.loadSource

	We attach to the EXISTING handle table (never replace it) so the double-load guard
	and init's stored ctx/handles stay intact.
]]

return function(require)
	local State = require("core/State")
	local Logger = require("core/Logger")
	local Platform = require("core/Platform")

	local API = {}
	API.id = "api/API"

	function API.start(ctx)
		local globals = Platform.globalTable()
		local handle = globals["__CINEMATIC_SHADER"]
		if type(handle) ~= "table" then
			handle = {}
			globals["__CINEMATIC_SHADER"] = handle
		end

		handle.get = function(key) return State.get(key) end
		handle.set = function(key, value) return State.set(key, value) end
		handle.setQuality = function(n) return State.set("quality", n) end
		handle.applyPreset = function(name) return require("presets/Presets").apply(name) end
		handle.presets = function() return require("presets/Presets").names() end
		handle.toggleUI = handle.toggleUI or function(on)
			if ctx.toggleUI then ctx.toggleUI(on) end
		end
		handle.exportConfig = function() return require("presets/Serializer").export() end
		handle.importConfig = function(json) return require("presets/Serializer").import(json) end
		handle.reBenchmark = function() return require("perf/Benchmark").run() end
		handle.getLastError = function() return Logger.getLastError() end
		handle.notify = handle.notify or function(t, c, d) require("ui/Notify").send(t, c, d) end
		handle.kill = function() return require("api/Teardown").kill() end
		handle.destroy = handle.kill
		handle.version = ctx.manifest and ctx.manifest.version or "1.0.0"
		handle.__alive = true

		ctx.log.info("Public API ready on _G/getgenv().__CINEMATIC_SHADER")
		return API
	end

	function API.stop() end

	return API
end
