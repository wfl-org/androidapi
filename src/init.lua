local ffi = require("ffi")
local jit = require("jit")

local native = require("androidapi.ffi")

local libandroid = native.loadAndroid()
local liblog = native.loadLog()
local hasLog = liblog ~= nil and pcall(function()
	return liblog.__android_log_write
end)

---@class androidapi.ffi.NativeWindow: ffi.cdata*
---@class androidapi.ffi.AssetManager: ffi.cdata*
---@class androidapi.ffi.NativeActivity: ffi.cdata*
---@field assetManager androidapi.ffi.AssetManager?

---@class androidapi.ffi.InputEvent: ffi.cdata*

---@class androidapi.ffi.androidApp: ffi.cdata*
---@field onAppCmd ffi.cdata*?
---@field onInputEvent ffi.cdata*?
---@field activity androidapi.ffi.NativeActivity
---@field window androidapi.ffi.NativeWindow?
---@field destroyRequested number

---@class androidapi.ffi.PollSource: ffi.cdata*
---@field id number
---@field process fun(app: androidapi.ffi.androidApp, source: androidapi.ffi.PollSource)

local rawApp = rawget(_G, "LDE_ANDROID_APP")
---@type androidapi.ffi.androidApp?
local app = rawApp and ffi.cast("struct androidapi_app*", rawApp) or nil

if app then
	rawset(jit, "android", true)
end

local Constants = {
	AppCommand = {
		inputChanged = 0,
		initWindow = 1,
		termWindow = 2,
		windowResized = 3,
		windowRedrawNeeded = 4,
		contentRectChanged = 5,
		gainedFocus = 6,
		lostFocus = 7,
		configChanged = 8,
		lowMemory = 9,
		start = 10,
		resume = 11,
		saveState = 12,
		pause = 13,
		stop = 14,
		destroy = 15,
	},
	InputType = {
		key = 1,
		motion = 2,
	},
	MotionAction = {
		mask = 0xff,
		down = 0,
		up = 1,
		move = 2,
		cancel = 3,
		outside = 4,
		pointerDown = 5,
		pointerUp = 6,
		hoverMove = 7,
		scroll = 8,
	},
	KeyAction = {
		down = 0,
		up = 1,
		multiple = 2,
	},
	Meta = {
		shift = 0x1,
		alt = 0x2,
		sym = 0x4,
		ctrl = 0x1000,
		super = 0x10000,
		capsLock = 0x100000,
		numLock = 0x200000,
		scrollLock = 0x400000,
	},
	Button = {
		primary = 0x1,
		secondary = 0x2,
		tertiary = 0x4,
		back = 0x8,
		forward = 0x10,
	},
	Axis = {
		vscroll = 9,
		hscroll = 10,
	},
	KeyCode = {
		back = 4,
		home = 3,
		up = 19,
		down = 20,
		left = 21,
		right = 22,
		space = 62,
		tab = 61,
		enter = 66,
		escape = 111,
		backspace = 67,
		delete = 112,
		insert = 124,
		pageUp = 92,
		pageDown = 93,
		moveHome = 122,
		moveEnd = 123,
		leftShift = 59,
		rightShift = 60,
		leftCtrl = 113,
		rightCtrl = 114,
		leftAlt = 57,
		rightAlt = 58,
		leftSuper = 117,
		rightSuper = 118,
		capsLock = 115,
		f1 = 131,
		f2 = 132,
		f3 = 133,
		f4 = 134,
		f5 = 135,
		f6 = 136,
		f7 = 137,
		f8 = 138,
		f9 = 139,
		f10 = 140,
		f11 = 141,
		f12 = 142,
	},
}

local assetModeBuffer = 3

local logPriority = {
	verbose = 2,
	debug = 3,
	info = 4,
	warn = 5,
	error = 6,
	fatal = 7,
}

---@class androidapi
---@field isAndroid boolean
---@field isTermux boolean
---@field libandroid ffi.namespace*?
---@field liblog ffi.namespace*?
---@field Constants table
---@field POLL_WAKE number
---@field POLL_CALLBACK number
---@field POLL_TIMEOUT number
---@field POLL_ERROR number
local android = {
	isAndroid = app ~= nil,
	isTermux = rawget(jit, "android") == true and app == nil,
	libandroid = libandroid,
	liblog = liblog,
	Constants = Constants,
	POLL_WAKE = -1,
	POLL_CALLBACK = -2,
	POLL_TIMEOUT = -3,
	POLL_ERROR = -4,
}

---@return androidapi.ffi.androidApp?
function android.app()
	return app
end

---@return androidapi.ffi.NativeActivity?
function android.activity()
	return app and app.activity or nil
end

---@return androidapi.ffi.NativeWindow?
function android.window()
	return app and app.window or nil
end

---@return androidapi.ffi.AssetManager?
function android.assets()
	return app and app.activity.assetManager or nil
end

---@return number? width
---@return number? height
---@return number? format
function android.windowSize()
	local window = app and app.window or nil
	if window == nil or not libandroid then
		return nil
	end
	return tonumber(libandroid.ANativeWindow_getWidth(window)) or 0,
		tonumber(libandroid.ANativeWindow_getHeight(window)) or 0,
		tonumber(libandroid.ANativeWindow_getFormat(window)) or 0
end

--- Run one pass of the Android looper and process the source it returns.
---@param timeoutMillis number?
---@return number
function android.pollOnce(timeoutMillis)
	if not app or not libandroid then
		return android.POLL_ERROR
	end

	local source = ffi.new("struct androidapi_poll_source*[1]")
	---@cast source androidapi.ffi.PollSource[]
	local events = ffi.new("int[1]")
	local result = libandroid.ALooper_pollOnce(timeoutMillis or 0, nil, events, ffi.cast("void**", source))

	if result >= 0 and source[0] ~= nil then
		source[0].process(app, source[0])
	end

	return tonumber(result) or android.POLL_ERROR
end

---@return boolean
function android.destroyRequested()
	return app ~= nil and app.destroyRequested ~= 0
end

function android.finish()
	if not app or not libandroid then
		error("androidapi: not running inside an Android app")
	end
	libandroid.ANativeActivity_finish(ffi.cast("void*", app.activity))
end

---@param show boolean
function android.showKeyboard(show)
	if not app or not libandroid then
		error("androidapi: not running inside an Android app")
	end

	if show then
		libandroid.ANativeActivity_showSoftInput(ffi.cast("void*", app.activity), 1)
	else
		libandroid.ANativeActivity_hideSoftInput(ffi.cast("void*", app.activity), 1)
	end
end

---@return string? content
---@return string? err
function android.readAsset(path)
	if not app or not libandroid then
		return nil, "androidapi: no asset manager"
	end

	local manager = app.activity.assetManager
	if manager == nil then
		return nil, "androidapi: no asset manager"
	end

	local asset = libandroid.AAssetManager_open(manager, path, assetModeBuffer)
	if asset == nil then
		return nil, "androidapi: asset not found: " .. path
	end

	local length = tonumber(libandroid.AAsset_getLength(asset))
	if not length or length < 0 then
		libandroid.AAsset_close(asset)
		return nil, "androidapi: cannot size asset: " .. path
	end

	if length == 0 then
		libandroid.AAsset_close(asset)
		return ""
	end

	local buffer = ffi.new("uint8_t[?]", length)
	local offset = 0
	while offset < length do
		local read = tonumber(libandroid.AAsset_read(asset, buffer + offset, length - offset))
		if not read or read <= 0 then
			break
		end
		offset = offset + read
	end
	libandroid.AAsset_close(asset)

	return ffi.string(buffer, offset)
end

---@param path string
---@return string[]? names
---@return string? err
function android.listAssets(path)
	if not app or not libandroid then
		return nil, "androidapi: no asset manager"
	end

	local manager = app.activity.assetManager
	if manager == nil then
		return nil, "androidapi: no asset manager"
	end

	local directory = libandroid.AAssetManager_openDir(manager, path)
	if directory == nil then
		return nil, "androidapi: asset directory not found: " .. path
	end

	local names = {}
	while true do
		local name = libandroid.AAssetDir_getNextFileName(directory)
		if name == nil then break end
		---@cast name ffi.cdata*
		names[#names + 1] = ffi.string(name)
	end
	libandroid.AAssetDir_close(directory)

	return names
end

---@param level "verbose" | "debug" | "info" | "warn" | "error" | "fatal"
---@param message any
function android.log(level, message)
	local text = tostring(message)
	if hasLog then
		liblog.__android_log_write(logPriority[level] or logPriority.info, "lde", text)
	else
		print(text)
	end
end

return android
