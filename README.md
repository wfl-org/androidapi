# androidapi

Low level API for interacting with Android NDK from LuaJIT

The app host (see `host/shim.c`) hands Lua the `android_app` pointer as the `LDE_ANDROID_APP`
global; everything after that is FFI.

## JNI

Some of what an app needs is only in the Java framework: the character a key types
(`KeyEvent.getUnicodeChar` has no NDK counterpart), the clipboard, the on-screen keyboard.
`androidapi.jni` makes those calls without any Java code of its own:

```lua
local android = require("androidapi")

android.keyCharacter(deviceId, keyCode, metaState) -- code point, or nil
android.showKeyboard(true)
android.setClipboardText("text")
android.getClipboardText()
```

The app thread attaches itself to the VM on its first JNI call. The host detaches it before
`android_main` returns, because ART aborts the process when an attached native thread exits.
Android only lets the focused app read the clipboard.
