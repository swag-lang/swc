#global #if #command == Swag.CompilerCommand.Test
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

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let button = PushButton.create(&host.root, "Run", {20, 20, 90, 30}, PushButtonHeadless_Command)
    button.sigPressed += &pushButtonHeadlessPressed

    host.moveMouse({40, 30})
    @assert(button.isHot)
    @assert(button.isIn)

    host.moveMouse({150, 80})
    @assert(!button.isHot)
    @assert(!button.isIn)
    @assert(host.commandCount == 0)

    host.shutdown()
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
    @assert(button.isPressed)
    @assert(button.isPressing)
    @assert(button.isIn)
    @assert(host.app.mouseCaptureWnd == button)
    @assert(host.commandCount == 0)
    @assert(PushButtonHeadlessPressedCount == 0)

    host.mouseUp({40, 30})
    @assert(host.commandCount == 1)
    @assert(host.lastCommand == PushButtonHeadless_Command)
    @assert(PushButtonHeadlessPressedCount == 1)
    @assert(!button.isPressed)
    @assert(!button.isPressing)
    @assert(button.isIn)
    @assert(host.app.mouseCaptureWnd == null)

    host.shutdown()
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

    @assert(PushButtonHeadlessPressedCount == 1)
    @assert(button.wndFlags.has(.Hidden))
    @assert(!button.isHot)
    @assert(!button.isIn)
    @assert(!button.isPressed)
    @assert(!button.isPressing)
    @assert(button.aniBk.themeCrc == Swag.U32.Max)
    @assert(button.aniBorder.themeCrc == Swag.U32.Max)
    @assert(button.aniText.themeCrc == Swag.U32.Max)
    @assert(host.app.mouseCaptureWnd == null)
    @assert(host.app.mouseEnterWnd == null)

    host.shutdown()
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    pushButtonHeadlessResetCounters()

    let panel = Wnd.create'Wnd(&host.root, {0, 0, 160, 80})
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

    @assert(PushButtonHeadlessPressedCount == 1)
    @assert(panel.wndFlags.has(.Hidden))
    @assert(!button.isHot)
    @assert(!button.isIn)
    @assert(!button.isPressed)
    @assert(!button.isPressing)
    @assert(button.aniBk.themeCrc == Swag.U32.Max)
    @assert(button.aniBorder.themeCrc == Swag.U32.Max)
    @assert(button.aniText.themeCrc == Swag.U32.Max)
    @assert(host.app.mouseCaptureWnd == null)
    @assert(host.app.mouseEnterWnd == null)

    host.shutdown()
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
    @assert(!button.isPressed)
    @assert(button.isPressing)
    @assert(!button.isIn)
    @assert(host.app.mouseCaptureWnd == button)

    host.mouseUp({150, 80})
    @assert(host.commandCount == 0)
    @assert(PushButtonHeadlessPressedCount == 0)
    @assert(!button.isPressed)
    @assert(!button.isPressing)
    @assert(!button.isIn)
    @assert(host.app.mouseCaptureWnd == null)

    host.shutdown()
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
    @assert(button.isPressed)
    @assert(button.isPressing)
    @assert(button.isIn)

    host.mouseUp({40, 30})
    @assert(host.commandCount == 1)
    @assert(host.lastCommand == PushButtonHeadless_Command)
    @assert(PushButtonHeadlessPressedCount == 1)
    @assert(!button.isPressed)
    @assert(!button.isPressing)
    @assert(host.app.mouseCaptureWnd == null)

    host.shutdown()
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
    @assert(host.app.mouseCaptureWnd == null)

    host.moveMouse({40, 30})
    @assert(button.isIn)
    @assert(!button.isPressed)
    @assert(!button.isPressing)

    host.mouseUp({40, 30})
    @assert(host.commandCount == 0)
    @assert(PushButtonHeadlessPressedCount == 0)
    @assert(!button.isPressed)
    @assert(!button.isPressing)

    host.shutdown()
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
    @assert(button.isHot)
    @assert(button.isIn)
    @assert(host.app.mouseEnterWnd == button)
    button.aniBk.themeCrc     = 42'u32
    button.aniBorder.themeCrc = 43'u32
    button.aniText.themeCrc   = 44'u32
    button.disable()
    host.click({40, 30})

    @assert(host.commandCount == 0)
    @assert(PushButtonHeadlessPressedCount == 0)
    @assert(!button.isHot)
    @assert(!button.isIn)
    @assert(button.aniBk.themeCrc == Swag.U32.Max)
    @assert(button.aniBorder.themeCrc == Swag.U32.Max)
    @assert(button.aniText.themeCrc == Swag.U32.Max)
    @assert(host.app.mouseEnterWnd == null)
    @assert(host.app.mouseCaptureWnd == null)

    host.shutdown()
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

    @assert(host.commandCount == 0)
    @assert(PushButtonHeadlessPressedCount == 0)
    @assert(!button.isHot)
    @assert(!button.isIn)
    @assert(button.aniBk.themeCrc == Swag.U32.Max)
    @assert(button.aniBorder.themeCrc == Swag.U32.Max)
    @assert(button.aniText.themeCrc == Swag.U32.Max)
    @assert(host.app.mouseCaptureWnd == null)

    host.shutdown()
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

    @assert(host.commandCount == 0)
    @assert(PushButtonHeadlessPressedCount == 0)
    @assert(PushButtonHeadlessRightPressedCount == 1)
    @assert(!button.isPressed)
    @assert(!button.isPressing)
    @assert(host.app.mouseCaptureWnd == null)

    host.shutdown()
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

    @assert(host.commandCount == 0)
    @assert(PushButtonHeadlessPressedCount == 1)
    @assert(!button.isPressed)
    @assert(!button.isPressing)
    @assert(host.app.mouseCaptureWnd == null)

    host.shutdown()
}
