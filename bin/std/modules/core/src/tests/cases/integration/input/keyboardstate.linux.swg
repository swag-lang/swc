#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

// A held physical keypad key changes its polled command and rune with NumLock and Shift.
#[Swag.TestTag("integration.desktop")]
#test
{
    Swag.require(Env.variable("SWAG_TEST_ISOLATED_X11") == "1")
    var temporary = Path.combine(Env.getSpecialDirectory(.Temp), "swag-keypad-poll-XXXXXX")
    let created   = Linux.mkdtemp(temporary.storage())
    Swag.require(created == temporary.buffer)
    defer expect Directory.delete(temporary, recurse: true)
    let ready  = Path.combine(temporary, "ready")
    let done   = Path.combine(temporary, "done")
    let script = Path.combine(testSourceRoot(), "datas/keypad.x11.peer.py")
    for mode in 5
    {
        let argument = Format.toString("%", mode)
        var peer     = expect Env.startProcess(Env.StartInfo{fileName: "python3",
                                                             arguments: [script.toString(), argument.toString(), temporary.toString()],
                                                             standardOutput: .Pipe, standardError: .Pipe})
        defer { discard catch peer.kill(); discard catch peer.waitForExit(); }
        let deadline = Time.monotonicMilliseconds() + 3000
        while not File.exists(ready) and Time.monotonicMilliseconds() < deadline do
            Threading.Thread.sleep(5'ms)
        Swag.require(File.exists(ready), "native keypad peer did not become ready")
        var keyboard: Input.Keyboard
        keyboard.update()
        let numeric = mode == 1
        var expected: Input.Key = numeric ? .NumPad1 : .End
        if mode == 4 do
            expected = .Return
        let pressed      = keyboard.isKeyPressed(expected)
        let character    = keyboard.keyToRune(expected)
        let otherPressed = keyboard.isKeyPressed(numeric ? .End : .NumPad1)

        // Finish the peer before asserting observations so even a regression restores lock state.
        discard expect File.writeAllText(done, "done")
        let exited = expect peer.tryWaitForExit(3's)
        Swag.require(exited and peer.exitCode() == 0, peer.standardError())
        expect File.delete(ready)
        expect File.delete(done)
        Swag.require(pressed and not otherPressed, Format.toString("keypad polling mode %", mode))
        Swag.require(character == (numeric ? '1' : 0'rune))
    }
}

// A held pointer button reads as pressed through the pointer state alone, and the others as
// released: the mouse polls each button on every frame.
#[Swag.TestTag("integration.desktop")]
#test
{
    Swag.require(Env.variable("SWAG_TEST_ISOLATED_X11") == "1")
    var temporary = Path.combine(Env.getSpecialDirectory(.Temp), "swag-button-poll-XXXXXX")
    let created   = Linux.mkdtemp(temporary.storage())
    Swag.require(created == temporary.buffer)
    defer expect Directory.delete(temporary, recurse: true)
    let ready  = Path.combine(temporary, "ready")
    let done   = Path.combine(temporary, "done")
    let script = Path.combine(testSourceRoot(), "datas/pointerbutton.x11.peer.py")
    for button in [1, 3]
    {
        let argument = Format.toString("%", button)
        var peer     = expect Env.startProcess(Env.StartInfo{fileName: "python3",
                                                             arguments: [script.toString(), argument.toString(), temporary.toString()],
                                                             standardOutput: .Pipe, standardError: .Pipe})
        defer { discard catch peer.kill(); discard catch peer.waitForExit(); }
        let deadline = Time.monotonicMilliseconds() + 3000
        while not File.exists(ready) and Time.monotonicMilliseconds() < deadline do
            Threading.Thread.sleep(5'ms)
        Swag.require(File.exists(ready), "native pointer peer did not become ready")
        let left   = Input.Mouse.isButtonPressed(.Left)
        let right  = Input.Mouse.isButtonPressed(.Right)
        let middle = Input.Mouse.isButtonPressed(.Middle)

        // Finish the peer before asserting observations so even a regression releases the button.
        discard expect File.writeAllText(done, "done")
        let exited = expect peer.tryWaitForExit(3's)
        Swag.require(exited and peer.exitCode() == 0, peer.standardError())
        expect File.delete(ready)
        expect File.delete(done)
        Swag.require(left == (button == 1) and right == (button == 3) and not middle)
    }
}
