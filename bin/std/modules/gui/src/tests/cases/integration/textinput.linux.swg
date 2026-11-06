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
    var letterPressModifiers, letterCharacterModifiers: Array'Input.KeyModifiers
    var layoutChanges: u32
    surface.wnd.view.hookOnEvent = func|&characters, &presses, &releases, &letterPressModifiers, &letterCharacterModifiers, &layoutChanges|(_, event)->bool
    {
        if event is NotifyEvent as notice where notice.kind == .KeyboardLayoutChanged
        {
            layoutChanges += 1
            return false
        }
        if event is KeyEvent as key
        {
            if key.kind == .Character
            {
                characters.append(key.character)
                if key.key == .A do
                    letterCharacterModifiers.add(key.modifiers)
            }
            elif key.kind == .Pressed
            {
                presses.add(key.key)
                if key.key == .A do
                    letterPressModifiers.add(key.modifiers)
            }
            elif key.kind == .Released do
                releases.add(key.key)
            return true
        }

        return false
    }

    defer surface.wnd.view.hookOnEvent = null
    let id = Format.toString("%", surface.windowId)
    for mode in ["send", "remap", "held-remap", "repeat", "modifiers"]
    {
        let priorCharacterCount = characters.count
        let priorLayoutChanges = layoutChanges
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
        let expectedPresses = mode == "send" ? 7 : (mode == "remap" ? 8 : (mode == "held-remap" ? 10 : (mode == "repeat" ? 11 : 15)))
        Swag.require(presses.count == expectedPresses,
                     Format.toString("physical presses in %: %, text %", mode, presses.count, characters))
        if mode == "remap"
        {
            let context = expect LinuxDesktop.ensure()
            let mapped = LinuxDesktop.portableKey(context, 230, 0)
            Swag.require(mapped == .B, Format.toString("mapped key after X11 change: %", mapped))
        }

        if mode == "modifiers"
        {
            Swag.require(characters.count == priorCharacterCount + 1 and Utf8.endsWith(characters.toString(), "A"),
                         Format.toString("modifier text: %", characters))
            Swag.require(letterPressModifiers[letterPressModifiers.count - 2] == .Shift and
                         letterPressModifiers.back() == .Control,
                         "modified key presses lost their native modifier state")
            Swag.require(letterCharacterModifiers.back() == .Shift,
                         "shifted text lost its modifier state")
            Swag.require(presses[presses.count - 4] == .LShift and
                         presses[presses.count - 3] == .A and
                         presses[presses.count - 2] == .LControl and
                         presses.back() == .A)
            Swag.require(releases.count == presses.count)
            Swag.require(layoutChanges == priorLayoutChanges, "modifier-only changes notified a new keyboard layout")
        }
        elif mode == "repeat"
        {
            Swag.require(characters.count >= priorCharacterCount + 2 and Utf8.endsWith(characters.toString(), "aa"),
                         Format.toString("repeated text: %", characters))
        }
        else
        {
            let expectedText = mode == "send" ? "aéJ\u0301" : (mode == "remap" ? "aéJ\u0301b" : "aéJ\u0301bbc")
            Swag.require(characters == expectedText, Format.toString("text in %: %", mode, characters))
        }
        if mode == "held-remap"
        {
            Swag.require(presses[presses.count - 2] == .B and presses.back() == .C)
            Swag.require(releases[releases.count - 2] == .B and releases.back() == .C)
        }
        if mode == "repeat"
        {
            Swag.require(presses.back() == .A and releases.back() == .A)
            Swag.require(releases.count == presses.count, "a repeated key changed the number of physical transitions")
        }
    }

    runTextInputPeer(script.toString(), "group-setup", saved.toString())
    defer runTextInputPeer(script.toString(), "group-restore", saved.toString())
    for 8 do
        app.runFrame()
    Swag.require(layoutChanges > 0, "XKB keymap replacement did not notify the surface")
    let changesBeforeGroupSwitch = layoutChanges
    let countBeforeGroups = characters.count
    let pressesBeforeGroups = presses.count
    var groupPeer = expect Env.startProcess(Env.StartInfo{fileName: "python3",
                                                          arguments: [script.toString(), "group-send", saved.toString(), id.toString()],
                                                          standardOutput: .Pipe, standardError: .Pipe})
    defer { discard catch groupPeer.kill(); discard catch groupPeer.waitForExit(); }
    let groupDeadline = Time.monotonicMilliseconds() + 4000
    while groupPeer.isRunning() and Time.monotonicMilliseconds() < groupDeadline
    {
        app.runFrame()
        discard expect groupPeer.tryWaitForExit(5'ms)
    }
    for 8 do
        app.runFrame()
    Swag.require(not groupPeer.isRunning() and groupPeer.exitCode() == 0, groupPeer.standardError())
    Swag.require(characters.count == countBeforeGroups + 2 and Utf8.endsWith(characters.toString(), "zy"),
                 Format.toString("XKB group text: %", characters))
    Swag.require(presses.count == pressesBeforeGroups + 2 and releases.count == presses.count)
    Swag.require(presses[presses.count - 2] == .Y and presses.back() == .Y and
                 releases[releases.count - 2] == .Y and releases.back() == .Y)
    Swag.require(layoutChanges >= changesBeforeGroupSwitch + 2, "XKB group switches did not notify the surface")
}
