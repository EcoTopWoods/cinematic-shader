--!nonstrict
--[[
	core/Snapshot.lua
	-----------------------------------------------------------------------------
	The zero-residue safety net.

	WHY: This suite mutates shared singletons (Lighting, Camera, Terrain) that we
	do NOT own. On unload we must restore the game EXACTLY as we found it. Two
	mechanisms:

	  1. Property capture — before the FIRST write to any property we record its
	     original value (capture-once; later writes never overwrite the original).
	     restore() writes them all back and clears the record.

	  2. Created-instance tagging — every Instance we create is stamped with the
	     attribute __cinematic=true and (optionally) tracked. On teardown we
	     Destroy ONLY tagged instances. We never Destroy or modify pre-existing
	     game effects — we add our own alongside and restore originals.

	This module does not decide WHEN to restore (that's Teardown/API); it only
	remembers and reverts.
]]

return function(require)
	local Logger = require("core/Logger")

	local Snapshot = {}
	local TAG_ATTR = "__cinematic"

	-- records[instance] = { propName = originalValue, ... }
	local records = setmetatable({}, { __mode = "k" }) -- weak keys: GC'd instances drop out
	local createdOrder = {}                              -- tracked created instances (ordered)

	-- Capture the original value of inst[prop] exactly once.
	function Snapshot.capture(inst, prop)
		if not inst then return end
		local rec = records[inst]
		if not rec then
			rec = {}
			records[inst] = rec
		end
		if rec[prop] == nil then
			local ok, val = pcall(function() return (inst :: any)[prop] end)
			if ok then
				-- store a sentinel for genuine nils so we know we captured it
				rec[prop] = { v = val }
			end
		end
	end

	-- Capture then write in one call — the canonical "mutate a foreign prop" path.
	function Snapshot.set(inst, prop, value)
		Snapshot.capture(inst, prop)
		local ok, err = pcall(function() (inst :: any)[prop] = value end)
		if not ok then
			Logger.warn("Snapshot.set failed", tostring(inst), prop, "->", err)
		end
		return ok
	end

	-- Mark an instance as ours and track it for destruction on teardown.
	function Snapshot.track(inst)
		if not inst then return inst end
		pcall(function() inst:SetAttribute(TAG_ATTR, true) end)
		createdOrder[#createdOrder + 1] = inst
		return inst
	end

	-- Create + parent + tag in one call.
	function Snapshot.create(className, props, parent)
		local inst = Instance.new(className)
		if props then
			for k, v in pairs(props) do
				pcall(function() (inst :: any)[k] = v end)
			end
		end
		Snapshot.track(inst)
		if parent then inst.Parent = parent end
		return inst
	end

	function Snapshot.isOurs(inst)
		local ok, val = pcall(function() return inst:GetAttribute(TAG_ATTR) end)
		return ok and val == true
	end

	-- Restore every captured property to its original value.
	function Snapshot.restoreProperties()
		local restored, failed = 0, 0
		for inst, rec in pairs(records) do
			if inst then
				for prop, boxed in pairs(rec) do
					local ok = pcall(function() (inst :: any)[prop] = boxed.v end)
					if ok then restored += 1 else failed += 1 end
				end
			end
		end
		table.clear(records)
		Logger.debug(string.format("Snapshot restored %d properties (%d failed)", restored, failed))
		return restored, failed
	end

	-- Destroy every tracked created instance (reverse order). Also sweeps any
	-- stray tagged instances under a provided root as a belt-and-braces pass.
	function Snapshot.destroyCreated(extraRoots)
		local destroyed = 0
		for i = #createdOrder, 1, -1 do
			local inst = createdOrder[i]
			if inst then
				pcall(function() inst:Destroy() end)
				destroyed += 1
			end
			createdOrder[i] = nil
		end
		-- Sweep for anything tagged we may have lost track of.
		for _, root in ipairs(extraRoots or {}) do
			if root then
				for _, d in ipairs(root:GetDescendants()) do
					if Snapshot.isOurs(d) then
						pcall(function() d:Destroy() end)
						destroyed += 1
					end
				end
			end
		end
		Logger.debug(string.format("Snapshot destroyed %d created instances", destroyed))
		return destroyed
	end

	-- Full revert. Properties first (so restored refs are valid), then instances.
	function Snapshot.restoreAll(extraRoots)
		Snapshot.restoreProperties()
		Snapshot.destroyCreated(extraRoots)
	end

	function Snapshot.stats()
		local propCount = 0
		for _, rec in pairs(records) do
			for _ in pairs(rec) do propCount += 1 end
		end
		return { properties = propCount, created = #createdOrder }
	end

	Snapshot.TAG_ATTR = TAG_ATTR
	return Snapshot
end
