--[[
	dist/loader.lua  —  NETWORK LOADER (the only file users paste)
	=============================================================================
	    loadstring(game:HttpGet(
	      "https://raw.githubusercontent.com/EcoTopWoods/cinematic-shader/v1.0.0/dist/loader.lua"
	    ))()
	=============================================================================
	Pinned to a TAG (never a moving branch). Fetches manifest.lua, then implements a
	require-shim that lazily fetches each src module by logical name, loadstrings it,
	runs its factory once, and caches the result — identical semantics to the offline
	bundle. Includes eager parallel warming, retries + backoff, and CDN mirror
	fallback (raw.githubusercontent → jsDelivr → Statically), plus an optional disk
	cache (writefile/readfile) keyed by version. On total failure it notifies and
	aborts with NO half-applied state (it never starts the suite unless every needed
	module resolved).

	Everything executor-specific (HttpGet/writefile/...) is capability-checked + pcall'd.
]]

-- ⚠ EDIT THESE for your fork (must match manifest.repo).
local USER = "EcoTopWoods"
local REPO = "cinematic-shader"
local REF  = "v1.0.0"          -- a TAG or commit SHA
local SRC  = "src"
local VERSION = "1.0.0"

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
local CACHE_DIR = "CinematicSuite/cache_v" .. VERSION

local function notify(title, text)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", { Title = title, Text = text, Duration = 6 })
	end)
end

if not httpGetFn then
	notify("Cinematic Suite", "No HTTP capability in this environment — cannot load.")
	return
end

-- ── url builders + mirrors ───────────────────────────────────────────────────
local MIRRORS = {
	function(path) return ("https://raw.githubusercontent.com/%s/%s/%s/%s"):format(USER, REPO, REF, path) end,
	function(path) return ("https://cdn.jsdelivr.net/gh/%s/%s@%s/%s"):format(USER, REPO, REF, path) end,
	function(path) return ("https://cdn.statically.io/gh/%s/%s/%s/%s"):format(USER, REPO, REF, path) end,
}

-- ── disk cache (optional) ────────────────────────────────────────────────────
local function diskKey(name) return CACHE_DIR .. "/" .. name:gsub("/", "_") .. ".lua" end
local function diskRead(name)
	if not canWrite then return nil end
	local ok, data = pcall(function()
		local k = diskKey(name)
		if isfile(k) then return readfile(k) end
		return nil
	end)
	if ok then return data end
	return nil
end
local function diskWrite(name, data)
	if not canWrite then return end
	pcall(function()
		if has(makefolder) then
			if not isfile("CinematicSuite") then pcall(makefolder, "CinematicSuite") end
			pcall(makefolder, CACHE_DIR)
		end
		writefile(diskKey(name), data)
	end)
end

-- ── fetch with retries + mirror fallback ─────────────────────────────────────
local function fetchPath(path)
	for _, build in ipairs(MIRRORS) do
		local url = build(path)
		for attempt = 1, 3 do
			local ok, body = pcall(httpGetFn, url)
			if ok and type(body) == "string" and #body > 0 and not body:find("404: Not Found", 1, true) then
				return body
			end
			task.wait(0.2 * attempt) -- linear backoff
		end
	end
	return nil
end

-- fetch a module's source (disk cache first), name = logical "folder/Name"
local sources = {}
local function fetchModule(name)
	if sources[name] then return sources[name] end
	local cached = diskRead(name)
	if cached then sources[name] = cached; return cached end
	local body = fetchPath(SRC .. "/" .. name .. ".lua")
	if body then
		sources[name] = body
		diskWrite(name, body)
	end
	return body
end

-- ── manifest first ───────────────────────────────────────────────────────────
local manifestSrc = fetchModule("manifest")
if not manifestSrc then
	notify("Cinematic Suite", "Failed to fetch manifest from all mirrors. Aborted.")
	return
end
-- manifest.lua returns a factory `function(require) return {...} end`; call it
-- with a no-op require (manifest needs no dependencies) to read the table.
local manifestFactory = loadstring(manifestSrc, "@manifest")
local manifest
if type(manifestFactory) == "function" then
	local okR, result = pcall(manifestFactory, function() end)
	if okR then manifest = result end
end
if type(manifest) ~= "table" or type(manifest.modules) ~= "table" then
	notify("Cinematic Suite", "Manifest malformed. Aborted.")
	return
end

-- ── eager parallel warm ──────────────────────────────────────────────────────
do
	local pending = 0
	local done = false
	for _, name in ipairs(manifest.modules) do
		if not sources[name] then
			pending += 1
			task.spawn(function()
				fetchModule(name)
				pending -= 1
			end)
		end
	end
	-- wait (bounded) for warm to drain so the require-shim mostly hits cache
	local t = 0
	while pending > 0 and t < 20 do
		task.wait(0.1); t += 0.1
	end
end

-- pre-flight: confirm every module resolved BEFORE we run anything (no half-apply)
local missing = {}
for _, name in ipairs(manifest.modules) do
	if name ~= "manifest" and not sources[name] then
		if not fetchModule(name) then missing[#missing + 1] = name end
	end
end
if #missing > 0 then
	notify("Cinematic Suite", ("Aborted — %d module(s) failed to load (e.g. %s)."):format(#missing, missing[1]))
	return
end

-- ── require-shim ─────────────────────────────────────────────────────────────
local cache = {}
local running = {}
local shimRequire
shimRequire = function(name)
	if cache[name] ~= nil then return cache[name] end
	if running[name] then error("cyclic require: " .. name) end
	local src = sources[name] or fetchModule(name)
	if not src then error("module not found: " .. name) end
	local factory, err = loadstring(src, "@" .. name)
	if not factory then error("compile error in " .. name .. ": " .. tostring(err)) end
	running[name] = true
	local result = factory(shimRequire)
	running[name] = nil
	cache[name] = result
	return result
end

-- ── boot ─────────────────────────────────────────────────────────────────────
local ok, handleOrErr = pcall(shimRequire, "init")
if not ok then
	notify("Cinematic Suite", "Boot error: " .. tostring(handleOrErr))
	return
end
return handleOrErr
