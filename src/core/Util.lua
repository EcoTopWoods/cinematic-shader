--!nonstrict
--[[
	core/Util.lua
	-----------------------------------------------------------------------------
	Shared, dependency-free helpers used across every subsystem.

	WHY: A single home for math/easing/colour/table helpers keeps the rest of the
	codebase free of copy-paste. Nothing here touches engine state or other
	modules, so it can be required first and by anyone with zero ordering risk.

	The module is returned as a factory `function(require) ... end` to match the
	universal module contract (see manifest.lua / init.lua), but it needs no
	dependencies of its own.
]]

return function(_require)
	local Util = {}

	-- ── numbers ────────────────────────────────────────────────────────────
	function Util.clamp(v, lo, hi)
		if v < lo then return lo elseif v > hi then return hi else return v end
	end

	function Util.lerp(a, b, t)
		return a + (b - a) * t
	end

	-- Inverse lerp: where does `v` sit between a..b (unclamped).
	function Util.invLerp(a, b, v)
		if a == b then return 0 end
		return (v - a) / (b - a)
	end

	function Util.map(v, inA, inB, outA, outB)
		return Util.lerp(outA, outB, Util.invLerp(inA, inB, v))
	end

	function Util.round(v, step)
		step = step or 1
		if step <= 0 then return v end
		return math.floor(v / step + 0.5) * step
	end

	function Util.approxEqual(a, b, eps)
		return math.abs(a - b) <= (eps or 1e-4)
	end

	-- Frame-rate-independent exponential smoothing.
	-- WHY: `v += (target-v)*alpha` with a fixed alpha is dt-dependent and shimmers
	-- at variable FPS. The exp form is the correct continuous-time decay:
	--   v += (target - v) * (1 - exp(-dt / tau))
	-- Larger `tau` = slower response (use a big tau for exposure, small for FOV).
	function Util.damp(current, target, tau, dt)
		if tau <= 0 then return target end
		local alpha = 1 - math.exp(-dt / tau)
		return current + (target - current) * alpha
	end

	-- ── easing (t in 0..1) ─────────────────────────────────────────────────
	function Util.easeInOutQuad(t)
		t = Util.clamp(t, 0, 1)
		return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2
	end

	function Util.easeOutCubic(t)
		t = Util.clamp(t, 0, 1)
		return 1 - (1 - t) ^ 3
	end

	function Util.smoothstep(t)
		t = Util.clamp(t, 0, 1)
		return t * t * (3 - 2 * t)
	end

	-- ── colour ─────────────────────────────────────────────────────────────
	function Util.lerpColor(a, b, t)
		return a:Lerp(b, Util.clamp(t, 0, 1))
	end

	-- Rec.709 luminance of a Color3 (0..1). Used by eye-adaptation/tonemap.
	function Util.luminance(c)
		return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
	end

	function Util.color3FromHex(hex)
		hex = hex:gsub("#", "")
		local r = tonumber(hex:sub(1, 2), 16) or 0
		local g = tonumber(hex:sub(3, 4), 16) or 0
		local b = tonumber(hex:sub(5, 6), 16) or 0
		return Color3.fromRGB(r, g, b)
	end

	-- ── tables ─────────────────────────────────────────────────────────────
	function Util.deepCopy(value)
		if type(value) ~= "table" then return value end
		local out = {}
		for k, v in pairs(value) do
			out[k] = Util.deepCopy(v)
		end
		return out
	end

	-- Shallow-merge `overlay` onto a copy of `base` (overlay wins).
	function Util.merge(base, overlay)
		local out = Util.deepCopy(base)
		if type(overlay) == "table" then
			for k, v in pairs(overlay) do
				out[k] = v
			end
		end
		return out
	end

	function Util.keys(t)
		local out = {}
		for k in pairs(t) do out[#out + 1] = k end
		return out
	end

	function Util.count(t)
		local n = 0
		for _ in pairs(t) do n += 1 end
		return n
	end

	-- Stable alphabetical key iteration (deterministic UI / serialisation order).
	function Util.sortedKeys(t)
		local out = Util.keys(t)
		table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
		return out
	end

	-- ── value-type round-trip helpers (for JSON serialisation) ─────────────
	-- WHY: HttpService:JSONEncode cannot encode Color3/Vector3/Enum. The
	-- Serializer leans on these to flatten/expand the few engine types we store
	-- in config. Keep this list in sync with Config value `type`s.
	function Util.encodeValue(v)
		local tv = typeof(v)
		if tv == "Color3" then
			return { __t = "Color3", r = v.R, g = v.G, b = v.B }
		elseif tv == "Vector3" then
			return { __t = "Vector3", x = v.X, y = v.Y, z = v.Z }
		elseif tv == "EnumItem" then
			return { __t = "Enum", e = tostring(v.EnumType), n = v.Name }
		end
		return v
	end

	function Util.decodeValue(v)
		if type(v) == "table" and v.__t then
			if v.__t == "Color3" then
				return Color3.new(v.r, v.g, v.b)
			elseif v.__t == "Vector3" then
				return Vector3.new(v.x, v.y, v.z)
			elseif v.__t == "Enum" then
				local ok, enumGroup = pcall(function()
					return (Enum :: any)[v.e:gsub("Enum%.", "")]
				end)
				if ok and enumGroup then
					local ok2, item = pcall(function() return enumGroup[v.n] end)
					if ok2 then return item end
				end
				return nil
			end
		end
		return v
	end

	-- Try-call that never throws; returns ok, result|errMessage.
	function Util.try(fn, ...)
		return pcall(fn, ...)
	end

	-- Perlin-ish smooth noise sample in [-1, 1] via math.noise (built-in).
	function Util.noise(x, y, z)
		return math.noise(x or 0, y or 0, z or 0)
	end

	-- EditableImage binding (CPU pixel work) — feature-detected, never assumed.
	-- Creates an EditableImage of sizePx² and binds it to an existing ImageLabel,
	-- trying the current Content.fromObject API then the older child-parent API.
	-- Returns (editableImage, writeFn(flatRGBAarray)) or nil on ANY failure so
	-- callers degrade gracefully. Keep buffers small (128–256) — this is CPU-bound.
	function Util.bindEditableImage(imageLabel, sizePx)
		local AssetService = game:GetService("AssetService")
		if typeof(AssetService.CreateEditableImage) ~= "function" then return nil end
		local img
		pcall(function() img = AssetService:CreateEditableImage({ Size = Vector2.new(sizePx, sizePx) }) end)
		if not img then
			pcall(function() img = (AssetService :: any):CreateEditableImage(Vector2.new(sizePx, sizePx)) end)
		end
		if not img then return nil end
		-- bind to the label: current API uses Content.fromObject; older beta parented.
		local bound = false
		pcall(function()
			imageLabel.ImageContent = Content.fromObject(img)
			bound = true
		end)
		if not bound then
			pcall(function() img.Parent = imageLabel; bound = true end)
		end
		if not bound then
			pcall(function() img:Destroy() end)
			return nil
		end
		local size2 = Vector2.new(sizePx, sizePx)
		local write = function(buf)
			return pcall(function() img:WritePixels(Vector2.zero, size2, buf) end)
		end
		return img, write
	end

	return Util
end
