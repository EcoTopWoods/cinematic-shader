--!nonstrict
--[[
	ui/Controls.lua  —  pure module
	-----------------------------------------------------------------------------
	Maps one Config metadata entry to the matching Rayfield control. Every control's
	Callback is wired to onChanged(value) (which the Schema points at State.set), and
	meta.save adds a Flag so Rayfield ConfigurationSaving persists it. Returns the
	created control object (which exposes :Set for State→UI sync) or nil.

	Only REAL Rayfield creators are used: CreateSlider/CreateToggle/CreateDropdown/
	CreateColorPicker/CreateKeybind/CreateInput. Each is pcall-guarded because the
	remote library's exact signature can drift between versions.
]]

return function(require)
	local State = require("core/State")

	local Controls = {}

	-- Rayfield dropdowns (newer) pass the selection as a table; normalise.
	local function pickOption(o)
		if type(o) == "table" then return o[1] end
		return o
	end

	function Controls.create(tab, key, meta, onChanged)
		local flag = meta.save and key or nil
		local ok, control = pcall(function()
			if meta.type == "number" then
				return tab:CreateSlider({
					Name = meta.label or key,
					Range = { meta.min or 0, meta.max or 1 },
					Increment = meta.step or 0.01,
					Suffix = "",
					CurrentValue = State.get(key),
					Flag = flag,
					Callback = function(v) onChanged(v) end,
				})
			elseif meta.type == "boolean" then
				return tab:CreateToggle({
					Name = meta.label or key,
					CurrentValue = State.get(key) and true or false,
					Flag = flag,
					Callback = function(v) onChanged(v and true or false) end,
				})
			elseif meta.type == "option" then
				return tab:CreateDropdown({
					Name = meta.label or key,
					Options = meta.options or {},
					CurrentOption = { State.get(key) },
					MultipleOptions = false,
					Flag = flag,
					Callback = function(o) onChanged(pickOption(o)) end,
				})
			elseif meta.type == "color" then
				return tab:CreateColorPicker({
					Name = meta.label or key,
					Color = State.get(key),
					Flag = flag,
					Callback = function(c) onChanged(c) end,
				})
			elseif meta.type == "keybind" then
				return tab:CreateKeybind({
					Name = meta.label or key,
					CurrentKeybind = tostring(State.get(key)),
					HoldToInteract = false,
					Flag = flag,
					Callback = function(k) onChanged(k) end,
				})
			else -- string / freeform
				return tab:CreateInput({
					Name = meta.label or key,
					CurrentValue = tostring(State.get(key)),
					PlaceholderText = meta.desc or "",
					RemoveTextAfterFocusLost = false,
					Flag = flag,
					Callback = function(t) onChanged(t) end,
				})
			end
		end)
		if not ok then
			require("core/Logger").warn("Controls.create failed for", key, "->", control)
			return nil
		end
		return control
	end

	-- push a value from State back into a control (preset/import refresh).
	function Controls.setValue(control, meta, value)
		if not control or type(control.Set) ~= "function" then return end
		pcall(function()
			if meta.type == "option" then
				control:Set({ value })
			else
				control:Set(value)
			end
		end)
	end

	return Controls
end
