#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

const ToggleButtonHeadless_Command = "ToggleButtonHeadless.Command"

var ToggleButtonHeadlessChangedCount: u32

func toggleButtonHeadlessChanged(btn: *ToggleButton)
{
    discard btn
    ToggleButtonHeadlessChangedCount += 1
}

// Each click flips the toggled state and emits the change signal + command.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    ToggleButtonHeadlessChangedCount = 0

    let toggle = ToggleButton.create(&host.root, {20, 20, 60, 30}, ToggleButtonHeadless_Command)
    toggle.sigChanged += &toggleButtonHeadlessChanged

    @assert(!toggle.isChecked())

    host.click({40, 35})
    @assert(toggle.isChecked())
    @assert(ToggleButtonHeadlessChangedCount == 1)
    @assert(host.commandCount == 1)
    @assert(host.lastCommand == ToggleButtonHeadless_Command)

    host.click({40, 35})
    @assert(!toggle.isChecked())
    @assert(ToggleButtonHeadlessChangedCount == 2)
    @assert(host.commandCount == 2)
}

// Pressing then leaving the button before release cancels the toggle.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    ToggleButtonHeadlessChangedCount = 0

    let toggle = ToggleButton.create(&host.root, {20, 20, 60, 30})
    toggle.sigChanged += &toggleButtonHeadlessChanged

    host.mouseDown({40, 35})
    host.moveMouse({200, 100})
    host.mouseUp({200, 100})

    @assert(!toggle.isChecked())
    @assert(ToggleButtonHeadlessChangedCount == 0)
    @assert(host.commandCount == 0)
    @assert(host.app.mouseCaptureWnd == null)
}

// Programmatic changes are silent; keyboard activation follows pointer activation.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    ToggleButtonHeadlessChangedCount = 0

    let toggle = ToggleButton.create(&host.root, {20, 20, 60, 30}, ToggleButtonHeadless_Command)
    toggle.sigChanged += &toggleButtonHeadlessChanged
    toggle.setChecked(true)
    @assert(toggle.isChecked())
    @assert(ToggleButtonHeadlessChangedCount == 0 and host.commandCount == 0)

    host.focus(toggle)
    host.keyPress(Input.Key.Space)
    @assert(!toggle.isChecked())
    @assert(ToggleButtonHeadlessChangedCount == 1 and host.commandCount == 1)
}

// Hiding a toggle button resets its transient pointer and animated paint state.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    let toggle = ToggleButton.create(&host.root, {20, 20, 60, 30})
    toggle.isHot              = true
    toggle.isPressed          = true
    toggle.aniBk.themeCrc     = 42'u32
    toggle.aniBorder.themeCrc = 43'u32
    toggle.aniMark.themeCrc   = 44'u32

    toggle.hide()

    @assert(!toggle.isHot)
    @assert(!toggle.isPressed)
    @assert(toggle.aniBk.themeCrc == Swag.U32.Max)
    @assert(toggle.aniBorder.themeCrc == Swag.U32.Max)
    @assert(toggle.aniMark.themeCrc == Swag.U32.Max)
}
