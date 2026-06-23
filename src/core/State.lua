--!nonstrict
--[[
	core/State.lua
	-----------------------------------------------------------------------------
	Live, mutable settings store seeded from Config defaults.

	WHY: Config is static metadata; State is the running value of every setting.
	Modules read with State.get(key) and react to changes via State.changed (a
	Signal that fires (key, newValue, oldValue) on every set). This is the live-
	update backbone — change a slider in the UI and the owning module updates
	immediately, no reload.

	State.set() validates/clamps through Config.coerce, so out-of-range UI input
	or bad imported JSON can never poison a module.

	Singleton (one store per loaded suite).
]]

return function(require)
	local Config = require("core/Config")
	local Signal = require("core/Signal")
	local Logger = require("core/Logger")

	local State = {}
	local values = Config.buildDefaults()

	-- Fired on every successful change: (key, newValue, oldValue).
	State.changed = Signal.new()
	-- Fired after a bulk apply (preset/import) completes: (changedKeysArray).
	State.bulkChanged = Signal.new()

	function State.get(key)
		return values[key]
	end

	-- Snapshot of ALL live values (shallow copy; values are immutable types).
	function State.snapshot()
		local out = {}
		for k, v in pairs(values) do out[k] = v end
		return out
	end

	-- Set one key. Coerces, stores, fires changed (unless silent / unchanged).
	-- Returns the stored (coerced) value.
	function State.set(key, value, silent)
		local coerced = Config.coerce(key, value)
		local old = values[key]
		if old == coerced then
			return coerced -- no-op; don't spam the signal
		end
		values[key] = coerced
		if not silent then
			State.changed:Fire(key, coerced, old)
		end
		return coerced
	end

	-- Apply a partial overlay (preset / imported data). Only keys present are
	-- touched — this is what makes presets PARTIAL overlays. Fires per-key
	-- changed signals plus one bulkChanged at the end.
	function State.applyOverlay(overlay, silentPerKey)
		local changed = {}
		for key, value in pairs(overlay) do
			if Config.meta[key] ~= nil then
				local old = values[key]
				local coerced = Config.coerce(key, value)
				if old ~= coerced then
					values[key] = coerced
					changed[#changed + 1] = key
					if not silentPerKey then
						State.changed:Fire(key, coerced, old)
					end
				end
			else
				Logger.warn("State.applyOverlay: unknown key ignored:", key)
			end
		end
		State.bulkChanged:Fire(changed)
		return changed
	end

	-- Reset everything to Config defaults.
	function State.reset()
		local overlay = Config.buildDefaults()
		return State.applyOverlay(overlay)
	end

	-- Subscribe to a single key; returns a connection. Fires immediately once
	-- with the current value so modules can self-initialise from one code path.
	function State.observe(key, fn)
		fn(values[key], nil)
		return State.changed:Connect(function(k, new, old)
			if k == key then fn(new, old) end
		end)
	end

	-- Subscribe to several keys at once (any of them firing calls fn(key,new)).
	function State.observeMany(keys, fn)
		local set = {}
		for _, k in ipairs(keys) do set[k] = true end
		return State.changed:Connect(function(k, new, old)
			if set[k] then fn(k, new, old) end
		end)
	end

	return State
end
