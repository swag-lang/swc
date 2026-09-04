#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

const PushButtonHeadless_Command = "PushButtonHeadless.Command"

var PushButtonHeadlessPressedCount:      u32
var PushButtonHeadlessRightPressedCount: u32

func pushButtonHeadlessPressed(btn: *Button)
{
    discard btn
    PushButtonHeadlessPressedCount += 1
}

func pushButtonHeadlessRightPressed(btn: *Button)
{
    discard btn
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
    defer host.shutdown()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30})
    Swag.assert(button.text() == "Run")

    button.setText("Stop")
    Swag.assert(button.text() == "Stop")

    button.setText(null)
    Swag.assert(button.text() == "")
}

// Space and Enter activate the focused button with the same signal and command as a click.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command, .Default)
    button.sigPressed += &pushButtonHeadlessPressed
    host.focus(button)

    host.keyPress(Input.Key.Space)
    host.keyPress(Input.Key.Return)
    Swag.assert(PushButtonHeadlessPressedCount == 2)
    Swag.assert(host.commandCount == 2 and host.lastCommand == PushButtonHeadless_Command)
    Swag.assert(button.form == .Default)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed += &pushButtonHeadlessPressed

    host.moveMouse({40, 30})
    Swag.assert(button.isHot)
    Swag.assert(button.isIn)

    host.moveMouse({150, 80})
    Swag.assert(!button.isHot)
    Swag.assert(!button.isIn)
    Swag.assert(host.commandCount == 0)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed += &pushButtonHeadlessPressed

    host.mouseDown({40, 30})
    Swag.assert(button.isPressed)
    Swag.assert(button.isPressing)
    Swag.assert(button.isIn)
    Swag.assert(host.app.mouseCaptureWnd == button)
    Swag.assert(host.commandCount == 0)
    Swag.assert(PushButtonHeadlessPressedCount == 0)

    host.mouseUp({40, 30})
    Swag.assert(host.commandCount == 1)
    Swag.assert(host.lastCommand == PushButtonHeadless_Command)
    Swag.assert(PushButtonHeadlessPressedCount == 1)
    Swag.assert(!button.isPressed)
    Swag.assert(!button.isPressing)
    Swag.assert(button.isIn)
    Swag.assert(host.app.mouseCaptureWnd == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed         += &pushButtonHeadlessHideOnPressed
    button.aniBk.themeCrc     = 42'u32
    button.aniBorder.themeCrc = 43'u32
    button.aniText.themeCrc   = 44'u32

    host.click({40, 30})

    Swag.assert(PushButtonHeadlessPressedCount == 1)
    Swag.assert(button.wndFlags.has(.Hidden))
    Swag.assert(!button.isHot)
    Swag.assert(!button.isIn)
    Swag.assert(!button.isPressed)
    Swag.assert(!button.isPressing)
    Swag.assert(button.aniBk.themeCrc == Swag.U32.Max)
    Swag.assert(button.aniBorder.themeCrc == Swag.U32.Max)
    Swag.assert(button.aniText.themeCrc == Swag.U32.Max)
    Swag.assert(host.app.mouseCaptureWnd == null)
    Swag.assert(host.app.mouseEnterWnd == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let panel  = Wnd.create'Wnd(&host.root, {0, 0, 160, 80})
    let button = PushButton.create(panel, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.aniBk.themeCrc     = 42'u32
    button.aniBorder.themeCrc = 43'u32
    button.aniText.themeCrc   = 44'u32
    button.sigPressed         += func|panel|(btn)
    {
        panel.hide()
        PushButtonHeadlessPressedCount += 1
    }

    host.click({40, 30})

    Swag.assert(PushButtonHeadlessPressedCount == 1)
    Swag.assert(panel.wndFlags.has(.Hidden))
    Swag.assert(!button.isHot)
    Swag.assert(!button.isIn)
    Swag.assert(!button.isPressed)
    Swag.assert(!button.isPressing)
    Swag.assert(button.aniBk.themeCrc == Swag.U32.Max)
    Swag.assert(button.aniBorder.themeCrc == Swag.U32.Max)
    Swag.assert(button.aniText.themeCrc == Swag.U32.Max)
    Swag.assert(host.app.mouseCaptureWnd == null)
    Swag.assert(host.app.mouseEnterWnd == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed += &pushButtonHeadlessPressed

    host.mouseDown({40, 30})
    host.moveMouse({150, 80})
    Swag.assert(!button.isPressed)
    Swag.assert(button.isPressing)
    Swag.assert(!button.isIn)
    Swag.assert(host.app.mouseCaptureWnd == button)

    host.mouseUp({150, 80})
    Swag.assert(host.commandCount == 0)
    Swag.assert(PushButtonHeadlessPressedCount == 0)
    Swag.assert(!button.isPressed)
    Swag.assert(!button.isPressing)
    Swag.assert(!button.isIn)
    Swag.assert(host.app.mouseCaptureWnd == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed += &pushButtonHeadlessPressed

    host.mouseDown({40, 30})
    host.moveMouse({150, 80})
    host.moveMouse({40, 30})
    Swag.assert(button.isPressed)
    Swag.assert(button.isPressing)
    Swag.assert(button.isIn)

    host.mouseUp({40, 30})
    Swag.assert(host.commandCount == 1)
    Swag.assert(host.lastCommand == PushButtonHeadless_Command)
    Swag.assert(PushButtonHeadlessPressedCount == 1)
    Swag.assert(!button.isPressed)
    Swag.assert(!button.isPressing)
    Swag.assert(host.app.mouseCaptureWnd == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed += &pushButtonHeadlessPressed

    host.mouseDown({150, 80})
    Swag.assert(host.app.mouseCaptureWnd == null)

    host.moveMouse({40, 30})
    Swag.assert(button.isIn)
    Swag.assert(!button.isPressed)
    Swag.assert(!button.isPressing)

    host.mouseUp({40, 30})
    Swag.assert(host.commandCount == 0)
    Swag.assert(PushButtonHeadlessPressedCount == 0)
    Swag.assert(!button.isPressed)
    Swag.assert(!button.isPressing)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed += &pushButtonHeadlessPressed

    host.moveMouse({40, 30})
    Swag.assert(button.isHot)
    Swag.assert(button.isIn)
    Swag.assert(host.app.mouseEnterWnd == button)
    button.aniBk.themeCrc     = 42'u32
    button.aniBorder.themeCrc = 43'u32
    button.aniText.themeCrc   = 44'u32
    button.disable()
    host.click({40, 30})

    Swag.assert(host.commandCount == 0)
    Swag.assert(PushButtonHeadlessPressedCount == 0)
    Swag.assert(!button.isHot)
    Swag.assert(!button.isIn)
    Swag.assert(button.aniBk.themeCrc == Swag.U32.Max)
    Swag.assert(button.aniBorder.themeCrc == Swag.U32.Max)
    Swag.assert(button.aniText.themeCrc == Swag.U32.Max)

    // A disabled window does not swallow the pointer: the application hands the gesture to
    // the nearest enabled ancestor, so the root is what the pointer is now over.
    Swag.assert(host.app.mouseEnterWnd == &host.root)
    Swag.assert(host.app.mouseCaptureWnd == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed += &pushButtonHeadlessPressed

    button.aniBk.themeCrc     = 42'u32
    button.aniBorder.themeCrc = 43'u32
    button.aniText.themeCrc   = 44'u32
    button.hide()
    host.click({40, 30})

    Swag.assert(host.commandCount == 0)
    Swag.assert(PushButtonHeadlessPressedCount == 0)
    Swag.assert(!button.isHot)
    Swag.assert(!button.isIn)
    Swag.assert(button.aniBk.themeCrc == Swag.U32.Max)
    Swag.assert(button.aniBorder.themeCrc == Swag.U32.Max)
    Swag.assert(button.aniText.themeCrc == Swag.U32.Max)
    Swag.assert(host.app.mouseCaptureWnd == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed      += &pushButtonHeadlessPressed
    button.sigRightPressed += &pushButtonHeadlessRightPressed

    host.click({40, 30}, Input.MouseButton.Right)

    Swag.assert(host.commandCount == 0)
    Swag.assert(PushButtonHeadlessPressedCount == 0)
    Swag.assert(PushButtonHeadlessRightPressedCount == 1)
    Swag.assert(!button.isPressed)
    Swag.assert(!button.isPressing)
    Swag.assert(host.app.mouseCaptureWnd == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30})
    button.sigPressed += &pushButtonHeadlessPressed

    host.click({40, 30})

    Swag.assert(host.commandCount == 0)
    Swag.assert(PushButtonHeadlessPressedCount == 1)
    Swag.assert(!button.isPressed)
    Swag.assert(!button.isPressing)
    Swag.assert(host.app.mouseCaptureWnd == null)
}
