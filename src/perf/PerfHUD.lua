--!nonstrict
--[[
	perf/PerfHUD.lua
	-----------------------------------------------------------------------------
	Toggleable on-screen diagnostics (perf_hud): FPS, frame-time, effective quality,
	and per-effect cost reported via ctx.perf.report(name, ms). A plain GUI overlay
	updated a few times a second (never per-frame string building). Reads bus.fps from
	AdaptiveQuality.
]]

return function(require)
	local State = require("core/State")

	local PerfHUD = {}
	PerfHUD.id = "perf/PerfHUD"

	function PerfHUD.start(ctx)
		local maid = ctx.maid:childMaid()
		PerfHUD._maid = maid
		local Snapshot = ctx.snapshot

		local frame = Snapshot.create("Frame", {
			Name = "PerfHUD",
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.4,
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(196, 86),
			BorderSizePixel = 0,
			ZIndex = 90, Visible = false,
		}, ctx.gui)
		Snapshot.create("UICorner", { CornerRadius = UDim.new(0, 6) }, frame)
		local label = Snapshot.create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -12, 1, -12),
			Position = UDim2.fromOffset(6, 6),
			Font = Enum.Font.Code,
			TextColor3 = Color3.fromRGB(180, 255, 200),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextSize = 13, ZIndex = 91, Text = "",
		}, frame)

		local accum = 0
		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			local on = State.get("perf_hud")
			frame.Visible = on
			if not on then return end
			accum += dt
			if accum < 0.2 then return end
			accum = 0
			local fps = ctx.bus.fps or (1 / math.max(dt, 1e-3))
			local q = ctx.getQuality()
			local lines = {
				("FPS  %3d   (%.1f ms)"):format(math.floor(fps + 0.5), 1000 / math.max(fps, 1)),
				("Quality  %.0f%%  (mul %.2f)"):format(q * 100, ctx.bus.qualityMul or 1),
			}
			local costs = ctx.perf.get()
			local shown = 0
			for name, ms in pairs(costs) do
				lines[#lines + 1] = ("%-10s %.2fms"):format(name, ms)
				shown += 1
				if shown >= 2 then break end
			end
			label.Text = table.concat(lines, "\n")
		end))

		ctx.log.debug("PerfHUD ready")
		return PerfHUD
	end

	function PerfHUD.stop() if PerfHUD._maid then PerfHUD._maid:clean() end end

	return PerfHUD
end
