#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core

func runTextInputPeer(script, mode, saved: string)
{
    var peer = expect Env.startProcess(Env.StartInfo{fileName: "python3", arguments: [script, mode, saved],
                                                     standardOutput: .Pipe, standardError: .Pipe})
    defer { discard catch peer.kill(); discard catch peer.waitForExit(); }
    Swag.require(expect peer.tryWaitForExit(3000'ms), "X11 text-input peer timed out")
    Swag.require(peer.exitCode() == 0, peer.standardError())
}

// The isolated X server receives ordinary, dead-key and multi-scalar compose input via XTEST.
#[Swag.TestTag("integration.desktop")]
#test
{
    Swag.require(Env.variable("SWAG_TEST_ISOLATED_X11") == "1")
    var temporary = Path.combine(Env.getSpecialDirectory(.Temp), "swag-textinput-XXXXXX")
    Swag.require(Linux.mkdtemp(temporary.storage()) == temporary.buffer)
    defer expect Directory.delete(temporary, recurse: true)
    let script = Path.combine(testSourceRoot(), "datas/textinput.x11.peer.py")
    let saved  = Path.combine(temporary, "keymap.json")
    runTextInputPeer(script.toString(), "setup", saved.toString())
    defer runTextInputPeer(script.toString(), "restore", saved.toString())

    var app: Application
    app.setMotionPreference(.Reduced)
    let surface = expect app.createSurface(60, 50, 320, 240, surfaceId: "linux-native-text-input")
    surface.show()
    for 4 do
        app.runFrame()
    surface.wnd.view.focusPolicy = .Click
    surface.wnd.view.setFocus()
    var characters: String
    var presses, releases: Array'Input.Key
    surface.wnd.view.hookOnEvent = func|&characters, &presses, &releases|(_, event)->bool
    {
        if event is KeyEvent as key
        {
            if key.kind == .Character do
                characters.append(key.character)
            elif key.kind == .Pressed do
                presses.add(key.key)
            elif key.kind == .Released do
                releases.add(key.key)
            return true
        }

        return false
    }

    defer surface.wnd.view.hookOnEvent = null
    let id = Format.toString("%", surface.windowId)
    for mode in ["send", "remap", "held-remap"]
    {
        var peer = expect Env.startProcess(Env.StartInfo{fileName: "python3", arguments: [script.toString(), mode, saved.toString(), id.toString()],
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
        let expectedPresses = mode == "send" ? 7 : (mode == "remap" ? 8 : 10)
        Swag.require(presses.count == expectedPresses,
                     Format.toString("physical presses in %: %, text %", mode, presses.count, characters))
        if mode == "remap"
        {
            let context = expect LinuxDesktop.ensure()
            let mapped = LinuxDesktop.portableKey(context, 230, 0)
            Swag.require(mapped == .B, Format.toString("mapped key after X11 change: %", mapped))
        }

        let expectedText = mode == "send" ? "aéJ\u0301" : (mode == "remap" ? "aéJ\u0301b" : "aéJ\u0301bbc")
        Swag.require(characters == expectedText, Format.toString("text in %: %", mode, characters))
        if mode == "held-remap"
        {
            Swag.require(presses[presses.count - 2] == .B and presses.back() == .C)
            Swag.require(releases[releases.count - 2] == .B and releases.back() == .C)
        }
    }
}
