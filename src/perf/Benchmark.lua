--!nonstrict
--[[
	perf/Benchmark.lua
	-----------------------------------------------------------------------------
	Startup micro-benchmark → initial quality tier. We can't read GPU specs, so we
	time a fixed batch of CPU work (math + a handful of raycasts) across a few frames
	and bucket the result into tier 1/2/3, then seed bus.qualityMul accordingly
	(lower on mobile regardless). It's a coarse starting point; AdaptiveQuality then
	closes the loop on real frame-rate. Re-runnable from the UI.
]]

return function(require)
	local Benchmark = {}
	Benchmark.id = "perf/Benchmark"

	function Benchmark.start(ctx)
		Benchmark._ctx = ctx
		-- defer the first run a moment so boot cost doesn't skew it
		task.defer(function() Benchmark.run() end)
		return Benchmark
	end

	-- returns tier 1..3 and sets bus.qualityMul
	function Benchmark.run()
		local ctx = Benchmark._ctx
		if not ctx then return 2 end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { ctx.worldFolder }

		local t0 = os.clock()
		local acc = 0
		for i = 1, 12000 do
			acc += math.sqrt(i) * math.sin(i * 0.001)
		end
		local origin = Vector3.new(0, 50, 0)
		for i = 1, 40 do
			workspace:Raycast(origin, Vector3.new(math.sin(i), -1, math.cos(i)) * 100, params)
		end
		local elapsed = os.clock() - t0  -- seconds for the fixed batch

		-- bucket: faster machines finish the batch quicker
		local tier
		if elapsed < 0.004 then tier = 3
		elseif elapsed < 0.012 then tier = 2
		else tier = 1 end
		if ctx.platform.isMobile then tier = math.min(tier, 1) end

		local mulByTier = { [1] = 0.45, [2] = 0.75, [3] = 1.0 }
		ctx.bus.qualityMul = mulByTier[tier]
		if ctx.fanoutQuality then pcall(ctx.fanoutQuality) end
		ctx.log.info(("Benchmark: tier %d (batch %.2fms) → qualityMul %.2f"):format(
			tier, elapsed * 1000, ctx.bus.qualityMul))
		return tier
	end

	function Benchmark.stop() end

	return Benchmark
end
