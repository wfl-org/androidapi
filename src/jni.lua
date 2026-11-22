local ffi = require("ffi")
local bit = require("bit")

require("androidapi.ffi") -- androidapi_jvalue and the JNIEnv/JavaVM structs

--- A small JNI surface for the calls an Android app makes into the framework without Java code
--- of its own: a character for a key, the clipboard. JNIEnv is a table of function pointers;
--- each slot used here is cast once, by its index in `struct JNINativeInterface` (jni.h).
---
--- The app thread `android_main` runs on is not a Java thread, so it attaches itself to the VM
--- on first use. The host must detach it before `android_main` returns: ART aborts the process
--- when an attached native thread exits.

local JNI_VERSION_1_6 = 0x00010006
local JNI_OK = 0

local Ptr = ffi.typeof("void*[1]")
local JValues = ffi.typeof("androidapi_jvalue[?]")
local U16Array = ffi.typeof("uint16_t[?]")

---@type table<string, { slot: number, type: string }>
local slots = {
	FindClass = { slot = 6, type = "void*(*)(void*, const char*)" },
	ExceptionClear = { slot = 17, type = "void(*)(void*)" },
	PushLocalFrame = { slot = 19, type = "int32_t(*)(void*, int32_t)" },
	PopLocalFrame = { slot = 20, type = "void*(*)(void*, void*)" },
	NewGlobalRef = { slot = 21, type = "void*(*)(void*, void*)" },
	DeleteGlobalRef = { slot = 22, type = "void(*)(void*, void*)" },
	DeleteLocalRef = { slot = 23, type = "void(*)(void*, void*)" },
	NewObjectA = { slot = 30, type = "void*(*)(void*, void*, void*, const androidapi_jvalue*)" },
	GetObjectClass = { slot = 31, type = "void*(*)(void*, void*)" },
	GetMethodID = { slot = 33, type = "void*(*)(void*, void*, const char*, const char*)" },
	CallObjectMethodA = { slot = 36, type = "void*(*)(void*, void*, void*, const androidapi_jvalue*)" },
	CallBooleanMethodA = { slot = 39, type = "uint8_t(*)(void*, void*, void*, const androidapi_jvalue*)" },
	CallIntMethodA = { slot = 51, type = "int32_t(*)(void*, void*, void*, const androidapi_jvalue*)" },
	CallFloatMethodA = { slot = 57, type = "float(*)(void*, void*, void*, const androidapi_jvalue*)" },
	CallVoidMethodA = { slot = 63, type = "void(*)(void*, void*, void*, const androidapi_jvalue*)" },
	GetFieldID = { slot = 94, type = "void*(*)(void*, void*, const char*, const char*)" },
	GetObjectField = { slot = 95, type = "void*(*)(void*, void*, void*)" },
	GetFloatField = { slot = 102, type = "float(*)(void*, void*, void*)" },
	GetStaticMethodID = { slot = 113, type = "void*(*)(void*, void*, const char*, const char*)" },
	CallStaticObjectMethodA = { slot = 116, type = "void*(*)(void*, void*, void*, const androidapi_jvalue*)" },
	GetStaticFieldID = { slot = 144, type = "void*(*)(void*, void*, const char*, const char*)" },
	GetStaticObjectField = { slot = 145, type = "void*(*)(void*, void*, void*)" },
	NewString = { slot = 163, type = "void*(*)(void*, const uint16_t*, int32_t)" },
	GetStringLength = { slot = 164, type = "int32_t(*)(void*, void*)" },
	GetArrayLength = { slot = 171, type = "int32_t(*)(void*, void*)" },
	GetObjectArrayElement = { slot = 173, type = "void*(*)(void*, void*, int32_t)" },
	NewCharArray = { slot = 177, type = "void*(*)(void*, int32_t)" },
	NewIntArray = { slot = 179, type = "void*(*)(void*, int32_t)" },
	NewFloatArray = { slot = 181, type = "void*(*)(void*, int32_t)" },
	GetFloatArrayRegion = { slot = 205, type = "void(*)(void*, void*, int32_t, int32_t, float*)" },
	SetCharArrayRegion = { slot = 209, type = "void(*)(void*, void*, int32_t, int32_t, const uint16_t*)" },
	SetIntArrayRegion = { slot = 211, type = "void(*)(void*, void*, int32_t, int32_t, const int32_t*)" },
	SetFloatArrayRegion = { slot = 213, type = "void(*)(void*, void*, int32_t, int32_t, const float*)" },
	GetStringRegion = { slot = 220, type = "void(*)(void*, void*, int32_t, int32_t, uint16_t*)" },
	ExceptionCheck = { slot = 228, type = "uint8_t(*)(void*)" },
	NewDirectByteBuffer = { slot = 229, type = "void*(*)(void*, void*, int64_t)" },
}

local VM_ATTACH_CURRENT_THREAD = 4
local VM_GET_ENV = 6

---@class androidapi.jni
local jni = {}

local vm ---@type { functions: ffi.cdata* }?
local env ---@type { functions: ffi.cdata* }?
---@type table<string, any>
local fn = {}

--- Hand the module the VM it attaches to. Called by androidapi with the activity's VM.
---@param javaVm ffi.cdata*
function jni.init(javaVm)
	vm = javaVm
end

--- The JNIEnv of the calling thread, attaching it to the VM the first time.
---@return ffi.cdata* env
function jni.env()
	if env ~= nil then return env end
	if vm == nil then error("androidapi.jni: no Java VM (not running inside an Android app)") end

	local vmFunctions = vm.functions
	local out = Ptr()
	local getEnv = ffi.cast("int32_t(*)(void*, void**, int32_t)", vmFunctions[VM_GET_ENV])
	if getEnv(vm, out, JNI_VERSION_1_6) ~= JNI_OK then
		local attach = ffi.cast("int32_t(*)(void*, void**, void*)", vmFunctions[VM_ATTACH_CURRENT_THREAD])
		if attach(vm, out, nil) ~= JNI_OK then
			error("androidapi.jni: AttachCurrentThread failed")
		end
	end

	env = ffi.cast("struct androidapi_jni_env*", out[0])
	local functions = env.functions
	for name, def in pairs(slots) do
		fn[name] = ffi.cast(def.type, functions[def.slot])
	end
	return env
end

--- Raise a Lua error for a pending Java exception, after clearing it so the env is usable again.
---@param what string
local function check(what)
	if fn.ExceptionCheck(env) ~= 0 then
		fn.ExceptionClear(env)
		error("androidapi.jni: Java exception in " .. what, 0)
	end
end

local MAX_ARGS = 10
local args = JValues(MAX_ARGS)

--- The argument kinds of a method signature, one letter each: `(I[CFZLandroid/graphics/Paint;)V`
--- is "I", "L", "F", "Z", "L" -- an array is a jobject like any other object.
---@type table<string, string[]>
local argKinds = {}

---@param signature string
local function kindsOf(signature)
	local known = argKinds[signature]
	if known then return known end
	local kinds, at = {}, 2
	while true do
		local c = signature:sub(at, at)
		if c == ")" or c == "" then break end
		if c == "[" then
			kinds[#kinds + 1] = "L"
			while signature:sub(at, at) == "[" do at = at + 1 end
			c = signature:sub(at, at)
		else
			kinds[#kinds + 1] = c
		end
		if c == "L" then
			at = signature:find(";", at, true) + 1
		else
			at = at + 1
		end
	end
	argKinds[signature] = kinds
	return kinds
end

--- Writes the arguments into the jvalue array the way the signature says each is passed: a Lua
--- number is an int, a long, a float or a double depending on the parameter, which only the
--- signature knows.
---@param signature string
local function pack(signature, ...)
	local kinds = kindsOf(signature)
	local n = select("#", ...)
	if n ~= #kinds then
		error(string.format("androidapi.jni: %s takes %d arguments, got %d", signature, #kinds, n), 3)
	end
	if n > MAX_ARGS then error("androidapi.jni: at most " .. MAX_ARGS .. " arguments", 3) end
	for i = 1, n do
		local value = select(i, ...)
		local slot = args[i - 1]
		local kind = kinds[i]
		slot.j = 0
		if kind == "I" or kind == "S" or kind == "B" or kind == "C" then
			slot.i = value
		elseif kind == "J" then
			slot.j = value
		elseif kind == "F" then
			slot.f = value
		elseif kind == "D" then
			slot.d = value
		elseif kind == "Z" then
			slot.z = value and 1 or 0
		else
			slot.l = value
		end
	end
	return args
end

--- Run `body` inside a JNI local frame, so the references it makes are released when it
--- returns, whether or not it raised. Returns what `body` returned, or nil and the error.
---@generic T
---@param body fun(): T
---@param capacity number? # how many local references the frame holds before it grows; 16 by default
---@return T?, string?
function jni.frame(body, capacity)
	jni.env()
	if fn.PushLocalFrame(env, capacity or 16) ~= JNI_OK then
		fn.ExceptionClear(env)
		return nil, "androidapi.jni: PushLocalFrame failed"
	end
	local ok, result = pcall(body)
	fn.PopLocalFrame(env, nil)
	if not ok then return nil, result end
	return result
end

--- A class by its JNI name (`android/view/KeyCharacterMap`), as a global reference kept for the
--- life of the Lua state. Framework classes only: the attached thread sees the boot class loader.
---@type table<string, ffi.cdata*>
local classes = {}
---@param name string
function jni.class(name)
	local cached = classes[name]
	if cached then return cached end
	jni.env()
	local localRef = fn.FindClass(env, name)
	check("FindClass " .. name)
	local global = fn.NewGlobalRef(env, localRef)
	classes[name] = global
	return global
end

---@type table<string, ffi.cdata*>
local methods = {}
---@param class ffi.cdata*
---@param name string
---@param signature string
---@param static boolean?
local function method(class, className, name, signature, static)
	local key = className .. (static and "::" or ".") .. name .. signature
	local cached = methods[key]
	if cached then return cached end
	local id = (static and fn.GetStaticMethodID or fn.GetMethodID)(env, class, name, signature)
	check("GetMethodID " .. key)
	methods[key] = id
	return id
end

--- Call an instance method. `ret` is its Java return type: "object", "boolean", "int", "float"
--- or "void"; each goes through its own Call<Type>MethodA, as JNI requires.
---@param object ffi.cdata*
---@param className string # the class declaring the method, JNI-named
---@param name string
---@param signature string
---@param ret "object" | "boolean" | "int" | "float" | "void"
function jni.call(object, className, name, signature, ret, ...)
	jni.env()
	local id = method(jni.class(className), className, name, signature, false)
	local packed = pack(signature, ...)
	local result
	if ret == "object" then
		result = fn.CallObjectMethodA(env, object, id, packed)
	elseif ret == "boolean" then
		result = fn.CallBooleanMethodA(env, object, id, packed) ~= 0
	elseif ret == "int" then
		result = fn.CallIntMethodA(env, object, id, packed)
	elseif ret == "float" then
		result = fn.CallFloatMethodA(env, object, id, packed)
	else
		fn.CallVoidMethodA(env, object, id, packed)
	end
	check(className .. "." .. name)
	if ret == "object" and result == nil then return nil end
	return result
end

--- Call a static method returning an object.
---@param className string
---@param name string
---@param signature string
function jni.callStatic(className, name, signature, ...)
	jni.env()
	local class = jni.class(className)
	local id = method(class, className, name, signature, true)
	local result = fn.CallStaticObjectMethodA(env, class, id, pack(signature, ...))
	check(className .. "." .. name)
	if result == nil then return nil end
	return result
end

--- A new object: `jni.new("android/graphics/RectF", "()V")`.
---@param className string
---@param signature string # the constructor's, returning V
function jni.new(className, signature, ...)
	jni.env()
	local class = jni.class(className)
	local id = method(class, className, "<init>", signature, false)
	local result = fn.NewObjectA(env, class, id, pack(signature, ...))
	check("new " .. className)
	return result
end

---@type table<string, ffi.cdata*>
local fields = {}

---@param className string
---@param name string
---@param signature string
---@param static boolean?
local function field(className, name, signature, static)
	local key = className .. (static and "::" or ".") .. name
	local cached = fields[key]
	if cached then return cached end
	local id = (static and fn.GetStaticFieldID or fn.GetFieldID)(env, jni.class(className), name, signature)
	check("GetFieldID " .. key)
	fields[key] = id
	return id
end

--- A float field of an object.
---@param object ffi.cdata*
---@param className string
---@param name string
---@return number
function jni.floatField(object, className, name)
	jni.env()
	return fn.GetFloatField(env, object, field(className, name, "F"))
end

--- An object field of a class, like `Bitmap$Config.ALPHA_8`.
---@param className string
---@param name string
---@param signature string
function jni.staticField(className, name, signature)
	jni.env()
	local result = fn.GetStaticObjectField(env, jni.class(className), field(className, name, signature, true))
	check(className .. "." .. name)
	return result
end

--- A Java `char[]` holding `count` UTF-16 units.
---@param units ffi.cdata* # const uint16_t*
---@param count number
function jni.chars(units, count)
	jni.env()
	local array = fn.NewCharArray(env, count)
	check("NewCharArray")
	fn.SetCharArrayRegion(env, array, 0, count, units)
	return array
end

--- A Java `int[]` of `count` values.
---@param values ffi.cdata* # const int32_t*
---@param count number
function jni.ints(values, count)
	jni.env()
	local array = fn.NewIntArray(env, count)
	check("NewIntArray")
	fn.SetIntArrayRegion(env, array, 0, count, values)
	return array
end

--- A Java `float[]` of `count` values.
---@param values ffi.cdata* # const float*
---@param count number
function jni.floats(values, count)
	jni.env()
	local array = fn.NewFloatArray(env, count)
	check("NewFloatArray")
	fn.SetFloatArrayRegion(env, array, 0, count, values)
	return array
end

--- A `java.nio.ByteBuffer` over memory the caller owns. Java reads it in place; the memory has
--- to outlive every object that keeps the buffer.
---@param pointer ffi.cdata*
---@param size number
function jni.directBuffer(pointer, size)
	jni.env()
	local buffer = fn.NewDirectByteBuffer(env, pointer, size)
	check("NewDirectByteBuffer")
	return buffer
end

--- Drops a global reference made by `jni.global`.
---@param object ffi.cdata*
function jni.release(object)
	jni.env()
	fn.DeleteGlobalRef(env, object)
end

--- Drops a local reference before its frame ends, for a loop that makes many.
---@param object ffi.cdata*
function jni.drop(object)
	jni.env()
	fn.DeleteLocalRef(env, object)
end

--- Copies a Java `float[]` into `into`.
---@param array ffi.cdata*
---@param count number
---@param into ffi.cdata* # float*
function jni.getFloats(array, count, into)
	jni.env()
	fn.GetFloatArrayRegion(env, array, 0, count, into)
	check("GetFloatArrayRegion")
end

--- How many elements a Java array has.
---@param array ffi.cdata*
---@return number
function jni.arrayLength(array)
	jni.env()
	return tonumber(fn.GetArrayLength(env, array)) or 0
end

--- One element of a Java object array, from nought, as a local reference.
---@param array ffi.cdata*
---@param index number
---@return ffi.cdata*?
function jni.arrayElement(array, index)
	jni.env()
	local element = fn.GetObjectArrayElement(env, array, index)
	check("GetObjectArrayElement")
	if element == nil then return nil end
	return element
end

--- A global reference to `object`, which outlives the frame it was made in.
---@param object ffi.cdata*
function jni.global(object)
	jni.env()
	return fn.NewGlobalRef(env, object)
end

local utf16 = U16Array(256)
local utf16Size = 256

---@param size number
local function ensure(size)
	if size > utf16Size then
		while utf16Size < size do utf16Size = utf16Size * 2 end
		utf16 = U16Array(utf16Size)
	end
end

--- A java.lang.String from UTF-8 text. NewStringUTF is not used: it takes modified UTF-8,
--- which has no four-byte sequences, so anything outside the BMP would be corrupted.
---@param text string
function jni.string(text)
	jni.env()
	ensure(#text)
	local n, i, len = 0, 1, #text
	while i <= len do
		local c = text:byte(i)
		local cp, size
		if c < 0x80 then cp, size = c, 1
		elseif c < 0xE0 then cp, size = bit.band(c, 0x1F), 2
		elseif c < 0xF0 then cp, size = bit.band(c, 0x0F), 3
		else cp, size = bit.band(c, 0x07), 4 end
		for k = 1, size - 1 do
			cp = bit.bor(bit.lshift(cp, 6), bit.band(text:byte(i + k) or 0x80, 0x3F))
		end
		i = i + size
		if cp >= 0x10000 then
			cp = cp - 0x10000
			utf16[n] = 0xD800 + bit.rshift(cp, 10)
			utf16[n + 1] = 0xDC00 + bit.band(cp, 0x3FF)
			n = n + 2
		else
			utf16[n] = cp
			n = n + 1
		end
	end
	local result = fn.NewString(env, utf16, n)
	check("NewString")
	return result
end

--- UTF-8 text from a java.lang.String.
---@param jstring ffi.cdata*
---@return string
function jni.tostring(jstring)
	jni.env()
	local n = fn.GetStringLength(env, jstring)
	ensure(n)
	fn.GetStringRegion(env, jstring, 0, n, utf16)
	check("GetStringRegion")
	local out, i = {}, 0
	while i < n do
		local u = utf16[i]
		i = i + 1
		if u >= 0xD800 and u < 0xDC00 and i < n then
			u = 0x10000 + bit.lshift(u - 0xD800, 10) + (utf16[i] - 0xDC00)
			i = i + 1
		end
		out[#out + 1] = jni.utf8(u)
	end
	return table.concat(out)
end

--- One code point as UTF-8.
---@param cp number
---@return string
function jni.utf8(cp)
	if cp < 0x80 then
		return string.char(cp)
	elseif cp < 0x800 then
		return string.char(0xC0 + bit.rshift(cp, 6), 0x80 + bit.band(cp, 0x3F))
	elseif cp < 0x10000 then
		return string.char(0xE0 + bit.rshift(cp, 12), 0x80 + bit.band(bit.rshift(cp, 6), 0x3F),
			0x80 + bit.band(cp, 0x3F))
	end
	return string.char(0xF0 + bit.rshift(cp, 18), 0x80 + bit.band(bit.rshift(cp, 12), 0x3F),
		0x80 + bit.band(bit.rshift(cp, 6), 0x3F), 0x80 + bit.band(cp, 0x3F))
end

return jni
