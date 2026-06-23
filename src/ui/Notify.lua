--!nonstrict
--[[
	ui/Notify.lua  —  pure module
	-----------------------------------------------------------------------------
	Single toast entry-point. Prefers Rayfield:Notify (set by ui/UI once Rayfield is
	loaded); falls back to the CoreGui SendNotification via StarterGui:SetCore so
	notifications still work under FallbackUI or before Rayfield mounts. All pcall'd.
]]

return function(require)
	local Notify = {}
	local rayfield = nil

	function Notify.setRayfield(rf)
		rayfield = rf
	end

	function Notify.send(title, content, duration)
		title = tostring(title or "Cinematic")
		content = tostring(content or "")
		duration = duration or 4
		if rayfield then
			local ok = pcall(function()
				rayfield:Notify({ Title = title, Content = content, Duration = duration })
			end)
			if ok then return end
		end
		pcall(function()
			game:GetService("StarterGui"):SetCore("SendNotification", {
				Title = title, Text = content, Duration = duration,
			})
		end)
	end

	return Notify
end
