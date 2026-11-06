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
    var physicalPresses: u32
    surface.wnd.view.hookOnEvent = func|&characters, &physicalPresses|(_, event)->bool
    {
        if event is KeyEvent as key
        {
            if key.kind == .Character do
                characters.append(key.character)
            elif key.kind == .Pressed do
                physicalPresses += 1
            return true
        }

        return false
    }

    defer surface.wnd.view.hookOnEvent = null
    let id = Format.toString("%", surface.windowId)
    for mode in ["send", "remap"]
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
        Swag.require(physicalPresses == (mode == "send" ? 7 : 8),
                     Format.toString("physical presses in %: %, text %", mode, physicalPresses, characters))
        if mode == "remap"
        {
            let context = expect LinuxDesktop.ensure()
            let mapped = LinuxDesktop.portableKey(context, 230, 0)
            Swag.require(mapped == .B, Format.toString("mapped key after X11 change: %", mapped))
        }

        Swag.require(characters == (mode == "send" ? "aéJ\u0301" : "aéJ\u0301b"),
                     Format.toString("text in %: %", mode, characters))
    }
}
