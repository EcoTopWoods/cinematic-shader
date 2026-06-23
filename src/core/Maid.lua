--!nonstrict
--[[
	core/Maid.lua
	-----------------------------------------------------------------------------
	Janitor / Maid — tracks everything that must be cleaned up.

	WHY: The single most important robustness primitive in this suite. Every
	RBXScriptConnection, custom Signal connection, created Instance, task.spawn
	thread and arbitrary teardown closure is handed to a Maid. On unload we clean
	in REVERSE insertion order so dependents die before their dependencies. No
	orphaned PreRender/RenderStepped loops, no leaked GUIs.

	Accepts (and knows how to clean up):
	  * RBXScriptConnection                -> :Disconnect()
	  * tables with :Disconnect / :disconnect (our Signal connections)
	  * Instances                          -> :Destroy()
	  * functions                          -> called
	  * threads (task.spawn result)        -> task.cancel
	  * tables with :Destroy / :destroy    -> called

	Returns a class. Each subsystem owns a child Maid given to the root Maid, so
	tearing down the root tears down the whole tree.
]]

return function(_require)
	local Maid = {}
	Maid.__index = Maid

	function Maid.new()
		return setmetatable({ _tasks = {}, _alive = true }, Maid)
	end

	-- Add a task; returns it so you can write `local c = maid:give(conn)`.
	function Maid:give(item)
		if not self._alive then
			-- Already cleaned: dispose immediately to avoid leaks.
			Maid._dispose(item)
			return item
		end
		self._tasks[#self._tasks + 1] = item
		return item
	end
	Maid.Add = Maid.give
	Maid.GiveTask = Maid.give

	-- Convenience: spawn a tracked thread that is cancelled on cleanup.
	function Maid:spawn(fn, ...)
		local thread = task.spawn(fn, ...)
		self:give(thread)
		return thread
	end

	-- Convenience: create + track a child Maid.
	function Maid:childMaid()
		local child = Maid.new()
		self:give(child)
		return child
	end

	function Maid._dispose(item)
		local t = typeof(item)
		if t == "RBXScriptConnection" then
			item:Disconnect()
		elseif t == "Instance" then
			item:Destroy()
		elseif t == "function" then
			local ok, err = pcall(item)
			if not ok then warn("[Cinematic] maid task error:", err) end
		elseif t == "thread" then
			pcall(task.cancel, item)
		elseif t == "table" then
			if type(item.Disconnect) == "function" then
				pcall(item.Disconnect, item)
			elseif type(item.disconnect) == "function" then
				pcall(item.disconnect, item)
			elseif type(item.Destroy) == "function" then
				pcall(item.Destroy, item)
			elseif type(item.destroy) == "function" then
				pcall(item.destroy, item)
			elseif type(item.clean) == "function" then
				pcall(item.clean, item)
			end
		end
	end

	-- Clean everything in reverse order. Safe to call multiple times.
	function Maid:clean()
		self._alive = false
		local tasks = self._tasks
		self._tasks = {}
		for i = #tasks, 1, -1 do
			Maid._dispose(tasks[i])
			tasks[i] = nil
		end
		-- Allow re-arming after a clean (e.g. effect toggled off then on).
		self._alive = true
	end
	Maid.Destroy = Maid.clean
	Maid.DoCleaning = Maid.clean

	function Maid:isEmpty()
		return #self._tasks == 0
	end

	return Maid
end
