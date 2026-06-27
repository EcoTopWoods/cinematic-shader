--!nonstrict
--[[
	ui/Schema.lua  —  pure module
	-----------------------------------------------------------------------------
	Generates the entire settings UI from Config.layout for the FLUENT library. Walks
	each {tab, group, keys} entry, drops a group header (a titled paragraph — Fluent
	has no native section), and emits the matching Fluent control for every key (via
	ui/Controls), wiring each to State.set. Controls whose meta.requires capability is
	unavailable on this client are skipped silently.

	Returns a control registry { key = controlObject } so ui/UI can push State changes
	back into the controls (preset/import → live UI refresh).
]]

return function(require)
	local Config = require("core/Config")
	local State = require("core/State")
	local Controls = require("ui/Controls")

	local Schema = {}

	-- tabsByName: { [tabName] = fluentTab }
	function Schema.build(tabsByName, ctx)
		local registry = {}
		for _, entry in ipairs(Config.layout) do
			local tab = tabsByName[entry.tab]
			if tab then
				-- group header (Fluent has no AddSection; a titled paragraph reads as one)
				pcall(function() tab:AddParagraph({ Title = entry.group, Content = "" }) end)
				for _, key in ipairs(entry.keys) do
					local meta = Config.meta[key]
					if meta then
						local gated = meta.requires and not ctx.platform.caps[meta.requires]
						if not gated then
							local control = Controls.create(tab, key, meta, function(v)
								State.set(key, v)
							end)
							if control then registry[key] = control end
						end
					end
				end
			end
		end
		return registry
	end

	return Schema
end
