--!nonstrict
--[[
	ui/Notify.lua  —  pure module
	-----------------------------------------------------------------------------
	Single toast entry-point. Prefers the active UI library's :Notify (Fluent), set
	by ui/UI once the library is loaded; falls back to the CoreGui SendNotification
	via StarterGui:SetCore so notifications still work under FallbackUI or before the
	library mounts. All pcall'd.
]]

return function(require)
	local Notify = {}
	local lib = nil

	function Notify.setLib(l) lib = l end
	Notify.setRayfield = Notify.setLib -- backwards-compatible alias

	function Notify.send(title, content, duration)
		title = tostring(title or "Cinematic")
		content = tostring(content or "")
		duration = duration or 4
		if lib then
			local ok = pcall(function()
				lib:Notify({ Title = title, Content = content, Duration = duration })
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
