--!nonstrict
--[[
	presets/ConfigStore.lua  —  pure module
	-----------------------------------------------------------------------------
	Executor-only disk persistence convenience (writefile/readfile/isfile), keyed by
	schema version. EVERY filesystem call is gated behind a Platform capability check
	and wrapped in pcall, so on vanilla Roblox / Studio this degrades to silent no-ops
	and the copy/paste JSON path (Serializer) remains the portable source of truth.
]]

return function(require)
	local Platform = require("core/Platform")
	local Config = require("core/Config")
	local Logger = require("core/Logger")

	local ConfigStore = {}
	local FOLDER = "CinematicSuite"
	local PATH = FOLDER .. "/config_v" .. Config.schemaVersion .. ".json"

	local function ensureFolder()
		if Platform.caps.makefolder and Platform.caps.isfile then
			pcall(function()
				if isfile and not isfile(FOLDER) then
					if makefolder then makefolder(FOLDER) end
				end
			end)
		end
	end

	function ConfigStore.available()
		return Platform.caps.writefile and Platform.caps.readfile and Platform.caps.isfile
	end

	function ConfigStore.save(jsonString)
		if not (Platform.caps.writefile and type(jsonString) == "string") then return false end
		ensureFolder()
		local ok, err = pcall(function() writefile(PATH, jsonString) end)
		if not ok then Logger.warn("ConfigStore.save failed:", err) end
		return ok
	end

	function ConfigStore.exists()
		if not Platform.caps.isfile then return false end
		local ok, res = pcall(function() return isfile(PATH) end)
		return ok and res == true
	end

	function ConfigStore.load()
		if not (Platform.caps.readfile and ConfigStore.exists()) then return nil end
		local ok, data = pcall(function() return readfile(PATH) end)
		if ok and type(data) == "string" then return data end
		return nil
	end

	return ConfigStore
end
