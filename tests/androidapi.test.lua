local test = require("lde-test")
local android = require("androidapi")

test.it("should expose raw app command numbers", function()
	test.equal(android.Constants.AppCommand.initWindow, 1)
	test.equal(android.Constants.AppCommand.termWindow, 2)
	test.equal(android.Constants.AppCommand.destroy, 15)
end)

test.it("should expose raw input numbers", function()
	test.equal(android.Constants.InputType.key, 1)
	test.equal(android.Constants.InputType.motion, 2)
	test.equal(android.Constants.MotionAction.pointerDown, 5)
	test.equal(android.Constants.KeyAction.up, 1)
end)

test.it("should expose raw modifier, button and axis bits", function()
	test.equal(android.Constants.Meta.shift, 0x1)
	test.equal(android.Constants.Meta.ctrl, 0x1000)
	test.equal(android.Constants.Button.primary, 0x1)
	test.equal(android.Constants.Button.secondary, 0x2)
	test.equal(android.Constants.Axis.hscroll, 10)
end)

if not android.isAndroid then
	test.skip("raw Android runtime (skipped: not running inside an Android app)")
	return
end

test.it("should expose the Android application and window", function()
	test.truthy(android.app() ~= nil)
	test.truthy(android.activity() ~= nil)
	test.truthy(android.libandroid ~= nil)
end)

test.it("should pump the looper", function()
	local result = android.pollOnce(0)
	test.truthy(result <= android.POLL_CALLBACK)
end)
