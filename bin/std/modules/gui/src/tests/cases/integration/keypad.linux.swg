#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core

// Real XTEST keycodes must follow NumLock and Shift without leaving a key pressed after a lock change.
#[Swag.TestTag("integration.desktop")]
#test
{
    Swag.require(Env.variable("SWAG_TEST_ISOLATED_X11") == "1")
    var app: Application
    app.setMotionPreference(.Reduced)
    let surface = expect app.createSurface(60, 50, 320, 240, surfaceId: "linux-native-keypad")
    surface.show()
    for 4 do
        app.runFrame()
    surface.wnd.view.focusPolicy = .Click
    surface.wnd.view.setFocus()
    var presses, releases: Array'Input.Key
    var characters:        String
    surface.wnd.view.hookOnEvent = func|&presses, &releases, &characters|(_, event)->bool
    {
        if event is KeyEvent as key
        {
            if key.kind == .Character
            {
                characters.append(key.character)
            }
            elif key.key != .NumLock and key.key != .LShift
            {
                if key.kind == .Pressed do
                    presses.add(key.key)
                elif key.kind == .Released do
                    releases.add(key.key)
            }

            return true
        }

        return false
    }

    defer surface.wnd.view.hookOnEvent = null
    let script = Path.combine(testSourceRoot(), "datas/keypad.x11.peer.py")
    let id     = Format.toString("%", surface.windowId)
    var peer   = expect Env.startProcess(Env.StartInfo{fileName: "python3", arguments: [script.toString(), id.toString()],
                                                       standardOutput: .Pipe, standardError: .Pipe})
    defer { discard catch peer.kill(); discard catch peer.waitForExit(); }
    let deadline = Time.monotonicMilliseconds() + 4000
    while peer.isRunning() and Time.monotonicMilliseconds() < deadline
    {
        app.runFrame()
        discard expect peer.tryWaitForExit(5'ms)
    }

    for 8 do
        app.runFrame()
    Swag.require(not peer.isRunning() and peer.exitCode() == 0, peer.standardError())
    let expected: const [..]Input.Key = [.Return, .Insert, .End, .Down, .PageDown, .Left, .Clear,
                                         .Right, .Home, .Up, .PageUp, .Delete, .End,
                                         .NumPad0, .NumPad1, .NumPad2, .NumPad3, .NumPad4, .NumPad5,
                                         .NumPad6, .NumPad7, .NumPad8, .NumPad9, .Decimal, .End, .NumPad1]
    Swag.require(presses.count == expected.count and releases.count == expected.count)
    for index in expected.count
    {
        Swag.require(presses[index] == expected[index], Format.toString("keypad press %: got %, expected %", index, presses[index], expected[index]))
        Swag.require(releases[index] == expected[index], Format.toString("keypad release %: got %, expected %", index, releases[index], expected[index]))
    }

    Swag.require(characters == "0123456789.1", characters.toString())
    Swag.require(app.keyboard.isKeyReleased(.NumPad1) and app.keyboard.isKeyReleased(.End))
}
