--!nonstrict
--[[
	detection/Scanner.lua  —  CONTROLLER (manifest.boot, started 1st)
	-----------------------------------------------------------------------------
	Streaming-aware, debounced, BUDGETED world part classifier.

	WHY: Reflections / Materials / Enhancers all need to know "is this a floor / a
	piece of foliage / water / a light holder". Walking workspace:GetDescendants()
	every frame would be catastrophic on big places (and StreamingEnabled means the
	tree changes constantly). Instead we maintain a work QUEUE fed by
	DescendantAdded, drain at most `perf_scanner_budget` parts/frame on Heartbeat,
	cache results in a weak table, and keep per-kind sets current.

	Classification = Material (via materials/PBR) + size/orientation + name hints +
	child emitters + CollectionService tags. Cached; we deliberately do NOT connect
	a Changed listener per part (that would mean thousands of connections) — call
	rescan() if the world's materials are mutated wholesale.

	Public API (the cross-module contract):
	    Scanner.classify(part) -> { kind, roughness, f0, isFloor, isFoliage,
	                                 isWater, isGlass, isMetal }
	    Scanner.getFloors()    -> { BasePart, ... }
	    Scanner.getByKind(k)   -> { BasePart, ... }
	    Scanner.onClassified   -> Signal (part, classification)
	    Scanner.rescan()
]]

return function(require)
	local State = require("core/State")
	local Signal = require("core/Signal")
	local CollectionService = game:GetService("CollectionService")

	local Scanner = {}
	Scanner.id = "detection/Scanner"
	Scanner.onClassified = Signal.new()

	-- name hint tables (lower-cased substring match)
	local FOLIAGE_WORDS = { "leaf", "leaves", "bush", "tree", "foliage", "grass", "fern", "plant", "vine", "hedge" }
	local WATER_WORDS = { "water", "ocean", "sea", "pond", "lake", "river", "pool" }

	local KINDS = { "floor", "foliage", "water", "glass", "metal", "fire", "smoke", "light", "generic" }

	-- state
	local cache = setmetatable({}, { __mode = "k" })       -- part -> classification
	local sets = {}                                        -- kind -> { [part]=true }
	for _, k in ipairs(KINDS) do sets[k] = setmetatable({}, { __mode = "k" }) end
	local queue = {}                                       -- pending parts
	local queued = setmetatable({}, { __mode = "k" })      -- part -> true (dedupe)
	local qualityMul = 1

	local function hasWord(name, words)
		name = string.lower(name)
		for _, w in ipairs(words) do
			if string.find(name, w, 1, true) then return true end
		end
		return false
	end

	-- compute (does not cache) the classification for a part
	local function compute(part)
		local PBR = require("materials/PBR")
		local props = PBR.props(part.Material)
		local mat = part.Material
		local name = part.Name

		local cls = {
			kind = "generic",
			roughness = props.roughness,
			f0 = props.f0,
			isFloor = false, isFoliage = false, isWater = false,
			isGlass = false, isMetal = false,
		}

		-- tags force-mark
		local floorTag = State.get("reflect_floor_tag")
		local tagged = false
		pcall(function() tagged = floorTag ~= "" and CollectionService:HasTag(part, floorTag) end)

		-- child emitters → kind holders (used by enhancers)
		if part:FindFirstChildOfClass("Fire") then cls.kind = "fire" end
		if part:FindFirstChildOfClass("Smoke") then cls.kind = (cls.kind == "fire") and "fire" or "smoke" end
		if part:FindFirstChildWhichIsA("Light", true)
			or part:FindFirstChildOfClass("PointLight")
			or part:FindFirstChildOfClass("SpotLight")
			or part:FindFirstChildOfClass("SurfaceLight") then
			if cls.kind == "generic" then cls.kind = "light" end
		end

		if mat == Enum.Material.Water or hasWord(name, WATER_WORDS) then
			cls.isWater = true
			if cls.kind == "generic" then cls.kind = "water" end
		end
		if mat == Enum.Material.Glass or mat == Enum.Material.ForceField then
			cls.isGlass = true
			if cls.kind == "generic" then cls.kind = "glass" end
		end
		if mat == Enum.Material.Metal or mat == Enum.Material.DiamondPlate
			or mat == Enum.Material.Foil or mat == Enum.Material.CorrodedMetal then
			cls.isMetal = true
			if cls.kind == "generic" then cls.kind = "metal" end
		end
		if mat == Enum.Material.Grass or mat == Enum.Material.LeafyGrass or hasWord(name, FOLIAGE_WORDS) then
			cls.isFoliage = true
			if cls.kind == "generic" then cls.kind = "foliage" end
		end

		-- FLOOR: tagged, OR a big upward-facing top face. Top face normal of a part
		-- in world space is its CFrame.UpVector. Area of the top face = X*Z.
		if tagged then
			cls.isFloor = true
			cls.kind = "floor"
		else
			local up = part.CFrame.UpVector
			local upish = up:Dot(Vector3.yAxis) > 0.85
			local size = part.Size
			local area = size.X * size.Z
			local flatish = size.Y <= math.max(size.X, size.Z) -- platey, not a tall wall
			if upish and flatish and area >= 100 then
				cls.isFloor = true
				if cls.kind == "generic" or cls.kind == "metal" or cls.kind == "glass" then
					cls.kind = "floor"
				end
			end
		end

		return cls
	end

	local function removeFromSets(part)
		for _, set in pairs(sets) do set[part] = nil end
	end

	local function addToSets(part, cls)
		removeFromSets(part)
		sets[cls.kind][part] = true
		-- floors also live in their own boolean flag regardless of primary kind
		if cls.isFloor then sets.floor[part] = true end
	end

	-- classify + cache + announce
	function Scanner.classify(part)
		if not (part and part:IsA("BasePart")) then return nil end
		local existing = cache[part]
		if existing then return existing end
		local ok, cls = pcall(compute, part)
		if not ok or not cls then return nil end
		cache[part] = cls
		addToSets(part, cls)
		Scanner.onClassified:Fire(part, cls)
		return cls
	end

	local function setToArray(set)
		local out = {}
		for part in pairs(set) do
			if part.Parent then out[#out + 1] = part end
		end
		return out
	end

	function Scanner.getFloors() return setToArray(sets.floor) end
	function Scanner.getByKind(kind)
		local set = sets[kind]
		return set and setToArray(set) or {}
	end

	local function enqueue(part)
		if part and part:IsA("BasePart") and not queued[part] and not cache[part] then
			queued[part] = true
			queue[#queue + 1] = part
		end
	end

	function Scanner.rescan()
		table.clear(cache)
		table.clear(queued)
		table.clear(queue)
		for _, set in pairs(sets) do table.clear(set) end
		for _, d in ipairs(workspace:GetDescendants()) do enqueue(d) end
	end

	function Scanner.setQuality(q)
		qualityMul = math.clamp(q, 0.25, 1)
	end

	-- ── lifecycle ─────────────────────────────────────────────────────────────
	function Scanner.start(ctx)
		local maid = ctx.maid:childMaid()
		Scanner._maid = maid
		local RunService = ctx.services.RunService

		-- initial sweep (queued, drained over frames — never all at once)
		for _, d in ipairs(workspace:GetDescendants()) do enqueue(d) end

		-- streaming: enroll new parts; reclassify holders when an emitter/light is added
		maid:give(workspace.DescendantAdded:Connect(function(inst)
			if inst:IsA("BasePart") then
				enqueue(inst)
			elseif inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Light") then
				local p = inst.Parent
				if p and p:IsA("BasePart") then
					cache[p] = nil  -- force reclassify so it lands in fire/smoke/light set
					enqueue(p)
				end
			end
		end))
		maid:give(workspace.DescendantRemoving:Connect(function(inst)
			if inst:IsA("BasePart") then
				cache[inst] = nil
				queued[inst] = nil
				removeFromSets(inst)
			end
		end))

		-- drain loop: budgeted parts/frame
		maid:give(RunService.Heartbeat:Connect(function()
			if #queue == 0 then return end
			local budget = math.max(8, math.floor(State.get("perf_scanner_budget") * qualityMul))
			local processed = 0
			while processed < budget and #queue > 0 do
				local part = table.remove(queue)
				if part then
					queued[part] = nil
					if part.Parent then Scanner.classify(part) end
				end
				processed += 1
			end
		end))

		ctx.log.debug("Scanner online; initial queue =", #queue)
		return Scanner
	end

	function Scanner.stop()
		if Scanner._maid then Scanner._maid:clean() end
	end

	return Scanner
end
