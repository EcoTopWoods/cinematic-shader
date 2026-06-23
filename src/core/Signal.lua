--!nonstrict
--[[
	core/Signal.lua
	-----------------------------------------------------------------------------
	Minimal synchronous signal/event implementation (BindableEvent-free).

	WHY: State broadcasts config changes and several subsystems subscribe. A pure
	Luau signal avoids the overhead/teardown quirks of real Instances and lets a
	Maid disconnect everything deterministically. Fires are synchronous and
	wrapped so one bad listener cannot break the rest.

	Returns a class (not a singleton). `Signal.new()` per channel.
]]

return function(_require)
	local Connection = {}
	Connection.__index = Connection

	function Connection:Disconnect()
		if not self._connected then return end
		self._connected = false
		local conns = self._signal._connections
		for i = #conns, 1, -1 do
			if conns[i] == self then
				table.remove(conns, i)
				break
			end
		end
	end
	Connection.disconnect = Connection.Disconnect -- alias

	local Signal = {}
	Signal.__index = Signal

	function Signal.new()
		return setmetatable({ _connections = {} }, Signal)
	end

	function Signal:Connect(fn)
		assert(type(fn) == "function", "Signal:Connect expects a function")
		local conn = setmetatable({ _signal = self, _fn = fn, _connected = true }, Connection)
		self._connections[#self._connections + 1] = conn
		return conn
	end
	Signal.connect = Signal.Connect -- alias

	function Signal:Once(fn)
		local conn
		conn = self:Connect(function(...)
			conn:Disconnect()
			fn(...)
		end)
		return conn
	end

	function Signal:Fire(...)
		-- Iterate a snapshot so listeners may disconnect during dispatch.
		local snapshot = table.clone(self._connections)
		for _, conn in ipairs(snapshot) do
			if conn._connected then
				local ok, err = pcall(conn._fn, ...)
				if not ok then
					warn("[Cinematic] signal listener error:", err)
				end
			end
		end
	end

	function Signal:DisconnectAll()
		for _, conn in ipairs(self._connections) do
			conn._connected = false
		end
		table.clear(self._connections)
	end
	Signal.Destroy = Signal.DisconnectAll

	return Signal
end
