local ffi = require("ffi")
local jit = require("jit")
local bit = require("bit")

local native = require("androidapi.ffi")
local jni = require("androidapi.jni")

local libandroid = native.loadAndroid()
local liblog = native.loadLog()
local hasLog = liblog ~= nil and pcall(function()
	return liblog.__android_log_write
end)

---@class androidapi.ffi.NativeWindow: ffi.cdata*
---@class androidapi.ffi.AssetManager: ffi.cdata*
---@class androidapi.ffi.NativeActivity: ffi.cdata*
---@field assetManager androidapi.ffi.AssetManager?
---@field sdkVersion number
---@field vm ffi.cdata*
---@field clazz ffi.cdata*

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
	jni.init(app.activity.vm)
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
		pointerIndexMask = 0xff00,
		pointerIndexShift = 8,
		down = 0,
		up = 1,
		move = 2,
		cancel = 3,
		outside = 4,
		pointerDown = 5,
		pointerUp = 6,
		hoverMove = 7,
		scroll = 8,
		hoverEnter = 9,
		hoverExit = 10,
		buttonPress = 11,
		buttonRelease = 12,
	},
	Source = {
		classPointer = 0x2,
		touchscreen = 0x1002,
		mouse = 0x2002,
		stylus = 0x4002,
	},
	ToolType = {
		unknown = 0,
		finger = 1,
		stylus = 2,
		mouse = 3,
		eraser = 4,
		palm = 5,
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
---@field jni androidapi.jni
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
	jni = jni,
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

---@type number?
local fastestRate = nil

--- The fastest refresh rate the display has a mode for, in hertz: 90 on a phone whose panel runs
--- at 60 or 90. What the display is running at now is the system's choice, and it picks the
--- fastest one only for a window that asks for it -- see `setFrameRate`.
---@return number?
function android.maxRefreshRate()
	if fastestRate ~= nil then return fastestRate end
	if not app then return nil end
	local activity = app.activity.clazz
	local rate = jni.frame(function()
		local manager = jni.call(activity, "android/app/Activity", "getWindowManager",
			"()Landroid/view/WindowManager;", "object")
		local display = jni.call(manager, "android/view/WindowManager", "getDefaultDisplay",
			"()Landroid/view/Display;", "object")
		local best = jni.call(display, "android/view/Display", "getRefreshRate", "()F", "float")
		local modes = jni.call(display, "android/view/Display", "getSupportedModes",
			"()[Landroid/view/Display$Mode;", "object")
		if modes ~= nil then
			for index = 0, jni.arrayLength(modes) - 1 do
				local mode = jni.arrayElement(modes, index)
				if mode ~= nil then
					local hz = jni.call(mode, "android/view/Display$Mode", "getRefreshRate", "()F", "float")
					if hz > best then best = hz end
					jni.drop(mode)
				end
			end
		end
		return best
	end, 32)
	fastestRate = tonumber(rate)
	return fastestRate
end

--- Asks the display to run at `hz` while this app's window is on screen, or gives the choice back
--- to the system with 0. Android 11 and later; earlier releases have no call for it and keep
--- their rate.
---@param hz number
function android.setFrameRate(hz)
	local window = app and app.window or nil
	if window == nil or not libandroid then return end
	pcall(function() libandroid.ANativeWindow_setFrameRate(window, hz, 0) end)
end

-- This runs on every event-loop pass, so its out-parameters are allocated once here rather
-- than per call. They are cleared before each poll: the buffer is shared, and a pass that
-- finds nothing must not see the source the previous pass left in it.
local pollSource = ffi.new(ffi.typeof("struct androidapi_poll_source*[1]"))
---@cast pollSource androidapi.ffi.PollSource[]
local pollSourceOut = ffi.cast("void**", pollSource)
local pollEvents = ffi.new("int[1]")

--- Run one pass of the Android looper and process the source it returns.
---@param timeoutMillis number?
---@return number
function android.pollOnce(timeoutMillis)
	if not app or not libandroid then
		return android.POLL_ERROR
	end

	pollSource[0] = nil
	pollEvents[0] = 0
	local result = libandroid.ALooper_pollOnce(timeoutMillis or 0, nil, pollEvents, pollSourceOut)

	if result >= 0 then
		local source = pollSource[0]
		if source ~= nil then
			source.process(app, source)
		end
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

-- InputMethodManager.SHOW_FORCED: show the keyboard though the view asking is not an editor.
local SHOW_FORCED = 2

--- Show or hide the on-screen keyboard. Its keys arrive as ordinary key events.
---
--- This goes through InputMethodManager on the activity's decor view: the NDK's
--- ANativeActivity_showSoftInput posts to a view that is not focused on most Android
--- releases, and the keyboard never opens. The decor view is not a text editor, so a plain
--- request is ignored: it is asked for with SHOW_FORCED. The NDK call is the fallback if JNI fails.
---@param show boolean
function android.showKeyboard(show)
	if not app or not libandroid then
		error("androidapi: not running inside an Android app")
	end

	local activity = app.activity.clazz
	local ok = jni.frame(function()
		local imm = jni.call(activity, "android/content/Context", "getSystemService",
			"(Ljava/lang/String;)Ljava/lang/Object;", "object", jni.string("input_method"))
		local window = jni.call(activity, "android/app/Activity", "getWindow", "()Landroid/view/Window;", "object")
		local view = jni.call(window, "android/view/Window", "getDecorView", "()Landroid/view/View;", "object")
		if show then
			jni.call(imm, "android/view/inputmethod/InputMethodManager", "showSoftInput",
				"(Landroid/view/View;I)Z", "boolean", view, SHOW_FORCED)
		else
			local token = jni.call(view, "android/view/View", "getWindowToken", "()Landroid/os/IBinder;", "object")
			jni.call(imm, "android/view/inputmethod/InputMethodManager", "hideSoftInputFromWindow",
				"(Landroid/os/IBinder;I)Z", "boolean", token, 0)
		end
		return true
	end)
	if ok then return end

	if show then
		libandroid.ANativeActivity_showSoftInput(ffi.cast("void*", app.activity), 1)
	else
		libandroid.ANativeActivity_hideSoftInput(ffi.cast("void*", app.activity), 1)
	end
end

-- KeyCharacterMap.COMBINING_ACCENT: the key starts a dead-key sequence rather than typing.
local COMBINING_ACCENT = 0x80000000

---@type table<number, ffi.cdata*>
local keyMaps = {}

--- The character a key types, as a Unicode code point, or nil when it types none (a modifier,
--- an arrow, a dead key). The NDK has no call for this -- AKeyEvent_getUnicodeChar does not
--- exist outside Java -- so it asks the device's KeyCharacterMap, which is what
--- KeyEvent.getUnicodeChar does. Safe to call outside the input callback: it takes the event's
--- numbers, not the event.
---@param deviceId number
---@param keyCode number
---@param metaState number
---@return number?
function android.keyCharacter(deviceId, keyCode, metaState)
	if not app then return nil end

	local result = jni.frame(function()
		local map = keyMaps[deviceId]
		if map == nil then
			local loaded = jni.callStatic("android/view/KeyCharacterMap", "load",
				"(I)Landroid/view/KeyCharacterMap;", deviceId)
			if loaded == nil then return 0 end
			map = jni.global(loaded)
			keyMaps[deviceId] = map
		end
		return jni.call(map, "android/view/KeyCharacterMap", "get", "(II)I", "int", keyCode, metaState)
	end)

	local code = tonumber(result) or 0
	if code == 0 or bit.band(code, COMBINING_ACCENT) ~= 0 then
		return nil
	end
	return code
end

--- The text on the system clipboard, or nil when it holds none.
---@return string?
function android.getClipboardText()
	if not app then return nil end
	local activity = app.activity.clazz
	return (jni.frame(function()
		local manager = jni.call(activity, "android/content/Context", "getSystemService",
			"(Ljava/lang/String;)Ljava/lang/Object;", "object", jni.string("clipboard"))
		local clip = jni.call(manager, "android/content/ClipboardManager", "getPrimaryClip",
			"()Landroid/content/ClipData;", "object")
		if clip == nil then return nil end
		if jni.call(clip, "android/content/ClipData", "getItemCount", "()I", "int") < 1 then return nil end
		local item = jni.call(clip, "android/content/ClipData", "getItemAt",
			"(I)Landroid/content/ClipData$Item;", "object", 0)
		local text = jni.call(item, "android/content/ClipData$Item", "getText",
			"()Ljava/lang/CharSequence;", "object")
		if text == nil then return nil end
		local str = jni.call(text, "java/lang/Object", "toString", "()Ljava/lang/String;", "object")
		return jni.tostring(str)
	end))
end

--- Put text on the system clipboard; nil empties it.
---@param text string?
function android.setClipboardText(text)
	if not app then
		error("androidapi: not running inside an Android app")
	end
	local activity = app.activity.clazz
	local _, err = jni.frame(function()
		local manager = jni.call(activity, "android/content/Context", "getSystemService",
			"(Ljava/lang/String;)Ljava/lang/Object;", "object", jni.string("clipboard"))
		if text == nil and app.activity.sdkVersion >= 28 then
			jni.call(manager, "android/content/ClipboardManager", "clearPrimaryClip", "()V", "void")
			return true
		end
		local clip = jni.callStatic("android/content/ClipData", "newPlainText",
			"(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Landroid/content/ClipData;",
			jni.string(""), jni.string(text or ""))
		jni.call(manager, "android/content/ClipboardManager", "setPrimaryClip",
			"(Landroid/content/ClipData;)V", "void", clip)
		return true
	end)
	if err then error(err, 2) end
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
