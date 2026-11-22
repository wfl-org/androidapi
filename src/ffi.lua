local ffi = require("ffi")

-- The structs are private to androidapi: a package compiled beside another Android
-- binding must not fight over `struct android_app` or `struct ARect` in the one C
-- namespace LuaJIT exposes to the process.
ffi.cdef[[
struct androidapi_rect {
	int32_t left;
	int32_t top;
	int32_t right;
	int32_t bottom;
};

struct androidapi_activity {
	void *callbacks;
	void *vm;
	void *env;
	void *clazz;
	void *activity;
	void *assetManager;
	const char *internalDataPath;
	const char *externalDataPath;
	int32_t sdkVersion;
	void *instance;
};

struct androidapi_poll_source {
	int32_t id;
	struct androidapi_app* app;
	void (*process)(struct androidapi_app* app, struct androidapi_poll_source* source);
};

struct androidapi_app {
	void *userData;
	void (*onAppCmd)(struct androidapi_app* app, int32_t cmd);
	int32_t (*onInputEvent)(struct androidapi_app* app, void* event);
	struct androidapi_activity *activity;
	void *config;
	void *savedState;
	size_t savedStateSize;
	void *looper;
	void *inputQueue;
	void *window;
	struct androidapi_rect contentRect;
	int32_t activityState;
	int32_t destroyRequested;
};

int32_t ALooper_pollOnce(int timeoutMillis, int *outFd, int *outEvents, void **outData);

int32_t ANativeWindow_getWidth(void *window);
int32_t ANativeWindow_getHeight(void *window);
int32_t ANativeWindow_getFormat(void *window);

struct androidapi_native_window_buffer {
	int32_t width;
	int32_t height;
	int32_t stride;
	int32_t format;
	void *bits;
	uint32_t reserved[6];
};

int32_t ANativeWindow_lock(void *window, struct androidapi_native_window_buffer *outBuffer, void *inOutDirtyBounds);
int32_t ANativeWindow_unlockAndPost(void *window);
int32_t ANativeWindow_setBuffersGeometry(void *window, int32_t width, int32_t height, int32_t format);


void ANativeActivity_finish(void *activity);
void ANativeActivity_showSoftInput(void *activity, uint32_t flags);
void ANativeActivity_hideSoftInput(void *activity, uint32_t flags);

int32_t AInputEvent_getType(void *event);
int32_t AInputEvent_getSource(void *event);
int32_t AMotionEvent_getAction(void *event);
float AMotionEvent_getX(void *event, size_t pointerIndex);
float AMotionEvent_getY(void *event, size_t pointerIndex);
int32_t AMotionEvent_getPointerId(void *event, size_t pointerIndex);
int32_t AMotionEvent_getButtonState(void *event);
float AMotionEvent_getAxisValue(void *event, int32_t axis, size_t pointerIndex);
int32_t AKeyEvent_getAction(void *event);
int32_t AKeyEvent_getKeyCode(void *event);
int32_t AKeyEvent_getMetaState(void *event);
int32_t AKeyEvent_getRepeatCount(void *event);
int32_t AKeyEvent_getUnicodeChar(void *event);

void *AAssetManager_open(void *manager, const char *filename, int mode);
int AAsset_read(void *asset, void *buffer, size_t count);
long AAsset_getLength(void *asset);
void AAsset_close(void *asset);
void *AAssetManager_openDir(void *manager, const char *dirname);
const char *AAssetDir_getNextFileName(void *assetDir);
void AAssetDir_close(void *assetDir);

int __android_log_write(int prio, const char *tag, const char *text);
]]

---@class androidapi.ffi
local ffiModule = {}

---@return ffi.namespace*?
function ffiModule.loadAndroid()
	local loaded, library = pcall(ffi.load, "android")
	if loaded then
		return library
	end
end

---@return ffi.namespace*?
function ffiModule.loadLog()
	local loaded, library = pcall(ffi.load, "log")
	if loaded then
		return library
	end
end

return ffiModule
