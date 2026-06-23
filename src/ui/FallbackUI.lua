--!nonstrict
--[[
	ui/FallbackUI.lua
	-----------------------------------------------------------------------------
	Minimal native-GUI control panel for when Rayfield can't be fetched (no HTTP / no
	loadstring / network failure). Covers the essentials: master enable, a quality
	slider, and an unload button — enough to control and safely remove the suite. All
	instances are tagged + Maid-tracked.
]]

return function(require)
	local State = require("core/State")

	local FallbackUI = {}
	FallbackUI.id = "ui/FallbackUI"

	function FallbackUI.start(ctx)
		local maid = ctx.maid:childMaid()
		FallbackUI._maid = maid
		local S = ctx.snapshot

		local root = S.create("Frame", {
			Name = "FallbackUI",
			BackgroundColor3 = Color3.fromRGB(18, 20, 26),
			BackgroundTransparency = 0.1,
			Position = UDim2.fromScale(0.02, 0.3),
			Size = UDim2.fromOffset(220, 150),
			BorderSizePixel = 0, ZIndex = 95,
		}, ctx.gui)
		S.create("UICorner", { CornerRadius = UDim.new(0, 8) }, root)
		S.create("TextLabel", {
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28),
			Text = "Cinematic Suite (fallback)", Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(235, 240, 250), TextSize = 14, ZIndex = 96,
		}, root)

		-- master enable toggle button
		local enableBtn = S.create("TextButton", {
			Position = UDim2.fromOffset(12, 36), Size = UDim2.fromOffset(196, 30),
			BackgroundColor3 = Color3.fromRGB(40, 120, 90), Font = Enum.Font.Gotham,
			TextColor3 = Color3.new(1, 1, 1), TextSize = 13, ZIndex = 96,
			Text = State.get("master_enabled") and "Enabled ✓" or "Disabled",
		}, root)
		S.create("UICorner", { CornerRadius = UDim.new(0, 6) }, enableBtn)
		maid:give(enableBtn.MouseButton1Click:Connect(function()
			local v = not State.get("master_enabled")
			State.set("master_enabled", v)
			enableBtn.Text = v and "Enabled ✓" or "Disabled"
			enableBtn.BackgroundColor3 = v and Color3.fromRGB(40, 120, 90) or Color3.fromRGB(120, 60, 60)
		end))

		-- quality slider (click-drag track)
		local track = S.create("Frame", {
			Position = UDim2.fromOffset(12, 74), Size = UDim2.fromOffset(196, 18),
			BackgroundColor3 = Color3.fromRGB(40, 44, 54), BorderSizePixel = 0, ZIndex = 96,
		}, root)
		S.create("UICorner", { CornerRadius = UDim.new(0, 4) }, track)
		local fill = S.create("Frame", {
			Size = UDim2.fromScale(State.get("quality"), 1),
			BackgroundColor3 = Color3.fromRGB(90, 150, 230), BorderSizePixel = 0, ZIndex = 97,
		}, track)
		S.create("UICorner", { CornerRadius = UDim.new(0, 4) }, fill)
		local UIS = ctx.services.UserInputService
		local dragging = false
		local function setFromX(px)
			local rel = math.clamp((px - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
			fill.Size = UDim2.fromScale(rel, 1)
			State.set("quality", rel)
		end
		maid:give(track.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				dragging = true; setFromX(i.Position.X)
			end
		end))
		maid:give(UIS.InputChanged:Connect(function(i)
			if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
				setFromX(i.Position.X)
			end
		end))
		maid:give(UIS.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end))

		-- unload
		local kill = S.create("TextButton", {
			Position = UDim2.fromOffset(12, 104), Size = UDim2.fromOffset(196, 30),
			BackgroundColor3 = Color3.fromRGB(150, 50, 50), Font = Enum.Font.GothamBold,
			TextColor3 = Color3.new(1, 1, 1), TextSize = 13, ZIndex = 96, Text = "Unload",
		}, root)
		S.create("UICorner", { CornerRadius = UDim.new(0, 6) }, kill)
		maid:give(kill.MouseButton1Click:Connect(function()
			require("api/Teardown").kill()
		end))

		ctx.log.debug("FallbackUI mounted")
		return FallbackUI
	end

	function FallbackUI.stop() if FallbackUI._maid then FallbackUI._maid:clean() end end

	return FallbackUI
end
