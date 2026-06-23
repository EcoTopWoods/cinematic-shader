--!nonstrict
--[[
	ui/Schema.lua  —  pure module
	-----------------------------------------------------------------------------
	Generates the entire settings UI from Config.layout. Walks each {tab, group,
	keys} entry, creates a section header per group, and emits the matching Rayfield
	control for every key (via ui/Controls), wiring each to State.set. Controls whose
	meta.requires capability is unavailable are skipped with a note, so the UI never
	exposes a control that can't work on this client.

	Returns a control registry { key = controlObject } so ui/UI can push State changes
	back into the controls (preset/import → live UI refresh).
]]

return function(require)
	local Config = require("core/Config")
	local State = require("core/State")
	local Controls = require("ui/Controls")

	local Schema = {}

	-- tabsByName: { [tabName] = rayfieldTab }
	function Schema.build(tabsByName, ctx)
		local registry = {}
		-- group layout entries by tab to create sections in order
		for _, entry in ipairs(Config.layout) do
			local tab = tabsByName[entry.tab]
			if tab then
				pcall(function() tab:CreateSection(entry.group) end)
				for _, key in ipairs(entry.keys) do
					local meta = Config.meta[key]
					if meta then
						local gated = meta.requires and not ctx.platform.caps[meta.requires]
						if gated then
							pcall(function()
								tab:CreateParagraph({
									Title = meta.label or key,
									Content = "Unavailable on this client (requires " .. meta.requires .. ").",
								})
							end)
						else
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
