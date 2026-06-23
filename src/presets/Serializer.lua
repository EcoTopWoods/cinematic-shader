--!nonstrict
--[[
	presets/Serializer.lua  —  pure module
	-----------------------------------------------------------------------------
	Round-trips the full live State to/from a schema-versioned JSON string:
	    { v = <schemaVersion>, data = { key = value, ... } }
	HttpService:JSONEncode can't encode Color3/Vector3/Enum, so we flatten those via
	Util.encodeValue and rebuild them with Util.decodeValue on import. The copy/paste
	string is the PRIMARY portable path; writefile (ConfigStore) is a convenience.
	Everything is pcall-guarded so a malformed paste can never poison State.
]]

return function(require)
	local State = require("core/State")
	local Config = require("core/Config")
	local Util = require("core/Util")
	local Logger = require("core/Logger")

	local HttpService = game:GetService("HttpService")

	local Serializer = {}

	function Serializer.export()
		local snap = State.snapshot()
		local data = {}
		for k, v in pairs(snap) do
			if Config.meta[k] ~= nil then
				data[k] = Util.encodeValue(v)
			end
		end
		local payload = { v = Config.schemaVersion, data = data }
		local ok, json = pcall(function() return HttpService:JSONEncode(payload) end)
		if not ok then
			Logger.error("Serializer.export failed:", json)
			return nil
		end
		return json
	end

	-- returns ok, errOrChangedCount
	function Serializer.import(jsonString)
		if type(jsonString) ~= "string" or jsonString == "" then
			return false, "empty input"
		end
		local ok, payload = pcall(function() return HttpService:JSONDecode(jsonString) end)
		if not ok or type(payload) ~= "table" or type(payload.data) ~= "table" then
			Logger.error("Serializer.import: bad JSON")
			return false, "invalid JSON"
		end
		if payload.v ~= nil and payload.v ~= Config.schemaVersion then
			Logger.warn("Serializer.import: schema v" .. tostring(payload.v)
				.. " (current v" .. Config.schemaVersion .. ") — importing leniently")
		end
		local overlay = {}
		for k, v in pairs(payload.data) do
			if Config.meta[k] ~= nil then
				overlay[k] = Util.decodeValue(v)
			end
		end
		local changed = State.applyOverlay(overlay)
		return true, #changed
	end

	return Serializer
end
