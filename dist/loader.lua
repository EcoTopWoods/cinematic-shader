--[[
	dist/loader.lua  —  NETWORK LOADER (the only file users paste)
	=============================================================================
	    loadstring(game:HttpGet(
	      "https://raw.githubusercontent.com/EcoTopWoods/cinematic-shader/v1.0.8/dist/loader.lua"
	    ))()
	=============================================================================
	DESIGN: fetch the SINGLE pre-built bundle (dist/cinematic.lua) in ONE request,
	then loadstring + run it. This replaced an earlier shim that fetched all ~64
	source modules individually — that hammered raw.githubusercontent with a burst of
	parallel requests, tripped its rate limiting, and aborted when any module failed.
	One request is dramatically more reliable (and the offline bundle was already the
	proven-good path).

	Robustness: CDN mirror fallback (raw.githubusercontent → jsDelivr → Statically),
	retries + linear backoff, an optional disk cache (writefile/readfile) keyed by
	version, and a clean notify-and-abort with NO half-applied state on total failure.
	Everything executor-specific (HttpGet/writefile/...) is capability-checked + pcall'd.
]]

-- ⚠ EDIT THESE for your fork (must match manifest.repo).
local USER = "EcoTopWoods"
local REPO = "cinematic-shader"
local REF  = "v1.0.8"          -- a TAG or commit SHA (use "main" for always-latest)
local VERSION = "1.0.8"
local BUNDLE = "dist/cinematic.lua"

-- ── capability probes ────────────────────────────────────────────────────────
local function has(fn) return typeof(fn) == "function" end
local httpGetFn = has(game.HttpGet) and function(url) return game:HttpGet(url, true) end or nil
if not httpGetFn then
	if syn and has(syn.request) then
		httpGetFn = function(url) return syn.request({ Url = url, Method = "GET" }).Body end
	elseif has(request) then
		httpGetFn = function(url) return request({ Url = url, Method = "GET" }).Body end
	elseif has(http_request) then
		httpGetFn = function(url) return http_request({ Url = url, Method = "GET" }).Body end
	end
end

local canWrite = has(writefile) and has(readfile) and has(isfile)
local CACHE_FILE = "CinematicSuite/bundle_v" .. VERSION .. ".lua"

local function notify(title, text)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", { Title = title, Text = text, Duration = 6 })
	end)
end

if not httpGetFn then
	notify("Cinematic Suite", "No HTTP capability in this environment — cannot load.")
	return
end

-- ── url mirrors for the bundle ───────────────────────────────────────────────
local MIRRORS = {
	("https://raw.githubusercontent.com/%s/%s/%s/%s"):format(USER, REPO, REF, BUNDLE),
	("https://cdn.jsdelivr.net/gh/%s/%s@%s/%s"):format(USER, REPO, REF, BUNDLE),
	("https://cdn.statically.io/gh/%s/%s/%s/%s"):format(USER, REPO, REF, BUNDLE),
}

local function looksValid(body)
	return type(body) == "string" and #body > 1000
		and not body:find("404: Not Found", 1, true)
		and body:find("__require", 1, true) ~= nil
end

-- ── disk cache (optional) ────────────────────────────────────────────────────
local function diskRead()
	if not canWrite then return nil end
	local ok, data = pcall(function()
		if isfile(CACHE_FILE) then return readfile(CACHE_FILE) end
		return nil
	end)
	return ok and data or nil
end
local function diskWrite(data)
	if not canWrite then return end
	pcall(function()
		if has(makefolder) and not (has(isfolder) and isfolder("CinematicSuite")) then
			pcall(makefolder, "CinematicSuite")
		end
		writefile(CACHE_FILE, data)
	end)
end

-- ── fetch the bundle (cache → mirrors × retries) ─────────────────────────────
local function fetchBundle()
	local cached = diskRead()
	if looksValid(cached) then return cached, "cache" end
	for _, url in ipairs(MIRRORS) do
		for attempt = 1, 3 do
			local ok, body = pcall(httpGetFn, url)
			if ok and looksValid(body) then
				diskWrite(body)
				return body, url
			end
			task.wait(0.25 * attempt) -- linear backoff
		end
	end
	return nil
end

local src, source = fetchBundle()
if not src then
	notify("Cinematic Suite", "Failed to fetch the bundle from every mirror. Aborted (nothing applied).")
	return
end

-- ── compile + boot ───────────────────────────────────────────────────────────
local factory, compileErr = loadstring(src, "@cinematic-bundle")
if not factory then
	notify("Cinematic Suite", "Bundle compile error: " .. tostring(compileErr))
	return
end

local ok, handleOrErr = pcall(factory)
if not ok then
	notify("Cinematic Suite", "Boot error: " .. tostring(handleOrErr))
	return
end

-- record where it loaded from for the About tab.
if type(handleOrErr) == "table" then
	handleOrErr.loadSource = "network loader (" .. tostring(source) .. ")"
end
return handleOrErr
