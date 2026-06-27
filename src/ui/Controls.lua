--!nonstrict
--[[
	ui/Controls.lua  —  pure module
	-----------------------------------------------------------------------------
	Maps one Config metadata entry to the matching FLUENT control. Every control's
	Callback is wired to onChanged(value) (the Schema points it at State.set), and the
	created control object is returned so State→UI sync (preset/import refresh) can push
	values back via :SetValue / :SetValueRGB.

	Fluent control creators take an idx (flag) as the first argument — we use the config
	key (unique) so Fluent's global Options/Toggles tables stay tidy. Each call is
	pcall-guarded because the remote library's signature can drift between versions.
]]

return function(require)
	local State = require("core/State")

	local Controls = {}

	-- decimals of precision Fluent should round a slider to, derived from the step.
	local function rounding(step)
		step = step or 0.01
		if step >= 1 then return 0
		elseif step >= 0.1 then return 1
		else return 2 end
	end

	function Controls.create(tab, key, meta, onChanged)
		local title = meta.label or key
		local desc = meta.desc
		local ok, control = pcall(function()
			if meta.type == "number" then
				return tab:AddSlider(key, {
					Title = title, Description = desc,
					Default = State.get(key), Min = meta.min or 0, Max = meta.max or 1,
					Rounding = rounding(meta.step),
					Callback = function(v) onChanged(v) end,
				})
			elseif meta.type == "boolean" then
				return tab:AddToggle(key, {
					Title = title, Description = desc,
					Default = State.get(key) and true or false,
					Callback = function(v) onChanged(v and true or false) end,
				})
			elseif meta.type == "option" then
				return tab:AddDropdown(key, {
					Title = title, Description = desc,
					Values = meta.options or {}, Multi = false, Default = State.get(key),
					Callback = function(v)
						if type(v) == "table" then v = next(v) or v[1] end
						onChanged(v)
					end,
				})
			elseif meta.type == "color" then
				return tab:AddColorpicker(key, {
					Title = title, Default = State.get(key),
					Callback = function(c) onChanged(c) end,
				})
			elseif meta.type == "keybind" then
				return tab:AddKeybind(key, {
					Title = title, Mode = "Toggle", Default = tostring(State.get(key)),
					Callback = function() end,
					ChangedCallback = function(newKey) onChanged(newKey) end,
				})
			else -- string / freeform
				return tab:AddInput(key, {
					Title = title, Default = tostring(State.get(key)),
					Placeholder = desc or "", Finished = true,
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
		if not control then return end
		pcall(function()
			if meta.type == "color" and type(control.SetValueRGB) == "function" then
				control:SetValueRGB(value)
			elseif type(control.SetValue) == "function" then
				control:SetValue(value)
			end
		end)
	end

	return Controls
end
