--[[
	dist/loader.lua  —  NETWORK LOADER (the only file users paste)
	=============================================================================
	    loadstring(game:HttpGet(
	      "https://raw.githubusercontent.com/EcoTopWoods/cinematic-shader/v1.0.13/dist/loader.lua"
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
local REF  = "v1.0.13"          -- a TAG or commit SHA (use "main" for always-latest)
local VERSION = "1.0.13"
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
-- statically is placed second (ahead of jsDelivr) because it serves new tags
-- immediately and tends to stay reachable where raw.githubusercontent is region-
-- blocked; jsDelivr can 502 on a just-pushed tag until it caches.
local MIRRORS = {
	("https://raw.githubusercontent.com/%s/%s/%s/%s"):format(USER, REPO, REF, BUNDLE),
	("https://cdn.statically.io/gh/%s/%s/%s/%s"):format(USER, REPO, REF, BUNDLE),
	("https://cdn.jsdelivr.net/gh/%s/%s@%s/%s"):format(USER, REPO, REF, BUNDLE),
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

local function clearCache()
	pcall(function()
		if has(delfile) and has(isfile) and isfile(CACHE_FILE) then delfile(CACHE_FILE) end
	end)
end

-- A body is only accepted if it actually COMPILES. This is the key robustness
-- change: a truncated/partial fetch (or a poisoned cache) can pass a length check
-- yet fail to run — so we loadstring it here and reject anything that won't compile,
-- and we only ever cache validated, compilable bundles. Returns (factory, err).
local function compileBundle(body)
	if not looksValid(body) then return nil, "incomplete download" end
	local f, err = loadstring(body, "@cinematic-bundle")
	if not f then return nil, "compile: " .. tostring(err) end
	return f
end

-- ── fetch the bundle (validated cache → mirrors × retries) ───────────────────
local function fetchBundle()
	-- cached copy must still COMPILE; a poisoned cache self-heals (deleted + refetched).
	local cached = diskRead()
	if cached then
		local f = compileBundle(cached)
		if f then return f, "disk cache" end
		clearCache()
	end
	local lastErr = "no HTTP"
	for _, url in ipairs(MIRRORS) do
		for attempt = 1, 3 do
			local ok, body = pcall(httpGetFn, url)
			if ok then
				local f, err = compileBundle(body)
				if f then
					diskWrite(body) -- only cache validated, runnable bundles
					return f, url
				end
				lastErr = err or "bad body"
			else
				lastErr = "blocked/offline"
			end
			task.wait(0.25 * attempt) -- linear backoff
		end
	end
	return nil, lastErr
end

local factory, source = fetchBundle()
if not factory then
	notify("Cinematic Suite", "Couldn't load (" .. tostring(source) .. "). If raw.githubusercontent is "
		.. "blocked on your network, try the jsDelivr/statically URL from the README.")
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
