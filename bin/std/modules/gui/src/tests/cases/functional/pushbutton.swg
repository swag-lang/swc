#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

const PushButtonHeadless_Command = "PushButtonHeadless.Command"
const PushButtonHeadless_Shortcut = "PushButtonHeadless.Shortcut"

var PushButtonHeadlessPressedCount:      u32
var PushButtonHeadlessRightPressedCount: u32

func pushButtonHeadlessPressed(_: *Button)
{
    PushButtonHeadlessPressedCount += 1
}

func pushButtonHeadlessRightPressed(_: *Button)
{
    PushButtonHeadlessRightPressedCount += 1
}

func pushButtonHeadlessHideOnPressed(btn: *Button)
{
    btn.hide()
    PushButtonHeadlessPressedCount += 1
}

func pushButtonHeadlessResetCounters()
{
    PushButtonHeadlessPressedCount      = 0
    PushButtonHeadlessRightPressedCount = 0
}

// A button that changes what it does changes what it says, so the label is writable after
// creation and reads back as plain text.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30})
    Swag.require(button.text() == "Run")

    button.setText("Stop")
    Swag.require(button.text() == "Stop")

    button.setText(null)
    Swag.require(button.text() == "")
}

// Space and Enter activate the focused button with the same signal and command as a click.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command, .Default)
    button.sigPressed += &pushButtonHeadlessPressed
    button.setFocus()

    host.keyPress(Input.Key.Space)
    host.keyPress(Input.Key.Return)
    Swag.require(PushButtonHeadlessPressedCount == 2)
    Swag.require(host.commandCount == 2 and host.lastCommand == PushButtonHeadless_Command)
    Swag.require(button.form == .Default)
}

// Modified keys stay available to shortcuts and never press a focused action.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Capture", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed += &pushButtonHeadlessPressed
    button.setFocus()

    for modifiers in [Input.KeyModifiers.Control, Input.KeyModifiers.Shift, Input.KeyModifiers.Alt]
    {
        host.keyPress(Input.Key.Space, modifiers)
        host.keyPress(Input.Key.Return, modifiers)
    }
    Swag.require(PushButtonHeadlessPressedCount == 0)
    Swag.require(host.commandCount == 0)

    host.surface.cancelButton = button
    host.root.registerKeyShortcut(.Control, .Escape, PushButtonHeadless_Shortcut)
    host.keyPress(Input.Key.Escape, .Control)
    Swag.require(PushButtonHeadlessPressedCount == 0)
    Swag.require(host.commandCount == 1 and host.lastCommand == PushButtonHeadless_Shortcut)

    host.keyPress(Input.Key.Space)
    Swag.require(PushButtonHeadlessPressedCount == 1 and host.commandCount == 2)
}

// Sending Space to a button outside the focus path cannot activate it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let focused = PushButton.create(&host.root, "Focused", {20, 20, 90, 30}, PushButtonHeadless_Command)
    let idle    = PushButton.create(&host.root, "Idle", {120, 20, 90, 30}, PushButtonHeadless_Command)
    idle.sigPressed += &pushButtonHeadlessPressed
    focused.setFocus()

    Swag.require(focused.hasVisibleFocus() and not idle.hasVisibleFocus())
    discard idle.sendKeyPress(.Space)
    host.pump()
    Swag.require(PushButtonHeadlessPressedCount == 0 and host.commandCount == 0)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed += &pushButtonHeadlessPressed

    host.moveMouse({40, 30})
    Swag.require(button.isHot)
    Swag.require(button.isIn)

    host.moveMouse({150, 80})
    Swag.require(not button.isHot)
    Swag.require(not button.isIn)
    Swag.require(host.commandCount == 0)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed += &pushButtonHeadlessPressed

    host.mouseDown({40, 30})
    Swag.require(button.isPressed)
    Swag.require(button.isPressing)
    Swag.require(button.isIn)
    Swag.require(host.app.mouseCaptureWnd == button)
    Swag.require(host.commandCount == 0)
    Swag.require(PushButtonHeadlessPressedCount == 0)

    host.mouseUp({40, 30})
    Swag.require(host.commandCount == 1)
    Swag.require(host.lastCommand == PushButtonHeadless_Command)
    Swag.require(PushButtonHeadlessPressedCount == 1)
    Swag.require(not button.isPressed)
    Swag.require(not button.isPressing)
    Swag.require(button.isIn)
    Swag.require(host.app.mouseCaptureWnd == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed         += &pushButtonHeadlessHideOnPressed
    button.aniBk.themeCrc     = 42'u32
    button.aniBorder.themeCrc = 43'u32
    button.aniText.themeCrc   = 44'u32

    host.click({40, 30})

    Swag.require(PushButtonHeadlessPressedCount == 1)
    Swag.require(button.wndFlags.has(.Hidden))
    Swag.require(not button.isHot)
    Swag.require(not button.isIn)
    Swag.require(not button.isPressed)
    Swag.require(not button.isPressing)
    Swag.require(button.aniBk.themeCrc == Swag.U32.Max)
    Swag.require(button.aniBorder.themeCrc == Swag.U32.Max)
    Swag.require(button.aniText.themeCrc == Swag.U32.Max)
    Swag.require(host.app.mouseCaptureWnd == null)
    Swag.require(host.app.mouseEnterWnd == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let panel  = Wnd.create'Wnd(&host.root, {0, 0, 160, 80})
    let button = PushButton.create(panel, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.aniBk.themeCrc     = 42'u32
    button.aniBorder.themeCrc = 43'u32
    button.aniText.themeCrc   = 44'u32
    button.sigPressed         += func|panel|(_)
    {
        panel.hide()
        PushButtonHeadlessPressedCount += 1
    }

    host.click({40, 30})

    Swag.require(PushButtonHeadlessPressedCount == 1)
    Swag.require(panel.wndFlags.has(.Hidden))
    Swag.require(not button.isHot)
    Swag.require(not button.isIn)
    Swag.require(not button.isPressed)
    Swag.require(not button.isPressing)
    Swag.require(button.aniBk.themeCrc == Swag.U32.Max)
    Swag.require(button.aniBorder.themeCrc == Swag.U32.Max)
    Swag.require(button.aniText.themeCrc == Swag.U32.Max)
    Swag.require(host.app.mouseCaptureWnd == null)
    Swag.require(host.app.mouseEnterWnd == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed += &pushButtonHeadlessPressed

    host.mouseDown({40, 30})
    host.moveMouse({150, 80})
    Swag.require(not button.isPressed)
    Swag.require(button.isPressing)
    Swag.require(not button.isIn)
    Swag.require(host.app.mouseCaptureWnd == button)

    host.mouseUp({150, 80})
    Swag.require(host.commandCount == 0)
    Swag.require(PushButtonHeadlessPressedCount == 0)
    Swag.require(not button.isPressed)
    Swag.require(not button.isPressing)
    Swag.require(not button.isIn)
    Swag.require(host.app.mouseCaptureWnd == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed += &pushButtonHeadlessPressed

    host.mouseDown({40, 30})
    host.moveMouse({150, 80})
    host.moveMouse({40, 30})
    Swag.require(button.isPressed)
    Swag.require(button.isPressing)
    Swag.require(button.isIn)

    host.mouseUp({40, 30})
    Swag.require(host.commandCount == 1)
    Swag.require(host.lastCommand == PushButtonHeadless_Command)
    Swag.require(PushButtonHeadlessPressedCount == 1)
    Swag.require(not button.isPressed)
    Swag.require(not button.isPressing)
    Swag.require(host.app.mouseCaptureWnd == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed += &pushButtonHeadlessPressed

    host.mouseDown({150, 80})
    Swag.require(host.app.mouseCaptureWnd == null)

    host.moveMouse({40, 30})
    Swag.require(button.isIn)
    Swag.require(not button.isPressed)
    Swag.require(not button.isPressing)

    host.mouseUp({40, 30})
    Swag.require(host.commandCount == 0)
    Swag.require(PushButtonHeadlessPressedCount == 0)
    Swag.require(not button.isPressed)
    Swag.require(not button.isPressing)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed += &pushButtonHeadlessPressed

    host.moveMouse({40, 30})
    Swag.require(button.isHot)
    Swag.require(button.isIn)
    Swag.require(host.app.mouseEnterWnd == button)
    button.aniBk.themeCrc     = 42'u32
    button.aniBorder.themeCrc = 43'u32
    button.aniText.themeCrc   = 44'u32
    button.disable()
    host.click({40, 30})

    Swag.require(host.commandCount == 0)
    Swag.require(PushButtonHeadlessPressedCount == 0)
    Swag.require(not button.isHot)
    Swag.require(not button.isIn)
    Swag.require(button.aniBk.themeCrc == Swag.U32.Max)
    Swag.require(button.aniBorder.themeCrc == Swag.U32.Max)
    Swag.require(button.aniText.themeCrc == Swag.U32.Max)

    // A disabled window does not swallow the pointer: the application hands the gesture to
    // the nearest enabled ancestor, so the root is what the pointer is now over.
    Swag.require(host.app.mouseEnterWnd == &host.root)
    Swag.require(host.app.mouseCaptureWnd == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed += &pushButtonHeadlessPressed

    button.aniBk.themeCrc     = 42'u32
    button.aniBorder.themeCrc = 43'u32
    button.aniText.themeCrc   = 44'u32
    button.hide()
    host.click({40, 30})

    Swag.require(host.commandCount == 0)
    Swag.require(PushButtonHeadlessPressedCount == 0)
    Swag.require(not button.isHot)
    Swag.require(not button.isIn)
    Swag.require(button.aniBk.themeCrc == Swag.U32.Max)
    Swag.require(button.aniBorder.themeCrc == Swag.U32.Max)
    Swag.require(button.aniText.themeCrc == Swag.U32.Max)
    Swag.require(host.app.mouseCaptureWnd == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed      += &pushButtonHeadlessPressed
    button.sigRightPressed += &pushButtonHeadlessRightPressed

    host.click({40, 30}, Input.MouseButton.Right)

    Swag.require(host.commandCount == 0)
    Swag.require(PushButtonHeadlessPressedCount == 0)
    Swag.require(PushButtonHeadlessRightPressedCount == 1)
    Swag.require(not button.isPressed)
    Swag.require(not button.isPressing)
    Swag.require(host.app.mouseCaptureWnd == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30})
    button.sigPressed += &pushButtonHeadlessPressed

    host.click({40, 30})

    Swag.require(host.commandCount == 0)
    Swag.require(PushButtonHeadlessPressedCount == 1)
    Swag.require(not button.isPressed)
    Swag.require(not button.isPressing)
    Swag.require(host.app.mouseCaptureWnd == null)
}
