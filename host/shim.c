/*
 * The only C an androidapi app needs: NativeActivity bootstrap.
 *
 * android_main runs on the app thread. It creates the Lua state, hands Lua the
 * android_app pointer, and runs the embedded bundle. Every platform operation
 * after that is LuaJIT FFI (see src/init.lua).
 *
 * Build beside android_native_app_glue and an embedded lde bundle. The bundle
 * symbols are supplied by the .incbin object the app compiler links:
 *
 *   $CC -shared -fPIC -O2 \
 *     -I"$LUAJIT/include" -I"$NDK/sources/android/native_app_glue" \
 *     shim.c "$NDK/sources/android/native_app_glue/android_native_app_glue.c" \
 *     bundle.S "$LUAJIT/lib/libluajit.a" \
 *     -landroid -llog -ldl -lm \
 *     -Wl,-z,max-page-size=16384 -Wl,-soname,libmain.so \
 *     -o libmain.so
 */

#include "android_native_app_glue.h"

#include <android/log.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

extern const unsigned char lde_bundle_start[];
extern const unsigned char lde_bundle_end[];

void android_main(struct android_app* app)
{
	lua_State* L = luaL_newstate();

	if (L == NULL) {
		ANativeActivity_finish(app->activity);
		return;
	}

	luaL_openlibs(L);
	lua_pushlightuserdata(L, app);
	lua_setglobal(L, "LDE_ANDROID_APP");

	if (luaL_loadbuffer(L, (const char*)lde_bundle_start,
			(size_t)(lde_bundle_end - lde_bundle_start), "@bundle") != LUA_OK
		|| lua_pcall(L, 0, 0, 0) != LUA_OK) {
		__android_log_write(ANDROID_LOG_ERROR, "lde", lua_tostring(L, -1));
	}

	lua_close(L);
	ANativeActivity_finish(app->activity);
}
