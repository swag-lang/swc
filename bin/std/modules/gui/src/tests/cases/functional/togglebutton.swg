#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

const ToggleButtonHeadless_Command = "ToggleButtonHeadless.Command"

var ToggleButtonHeadlessChangedCount: u32

func toggleButtonHeadlessChanged(_: *ToggleButton)
{
    ToggleButtonHeadlessChangedCount += 1
}

// Each click flips the toggled state and emits the change signal + command.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    ToggleButtonHeadlessChangedCount = 0

    let toggle = ToggleButton.create(&host.root, {20, 20, 60, 30}, ToggleButtonHeadless_Command)
    toggle.sigChanged += &toggleButtonHeadlessChanged

    Swag.require(not toggle.isChecked())

    host.click({40, 35})
    Swag.require(toggle.isChecked())
    Swag.require(ToggleButtonHeadlessChangedCount == 1)
    Swag.require(host.commandCount == 1)
    Swag.require(host.lastCommand == ToggleButtonHeadless_Command)

    host.click({40, 35})
    Swag.require(not toggle.isChecked())
    Swag.require(ToggleButtonHeadlessChangedCount == 2)
    Swag.require(host.commandCount == 2)
}

// Pressing then leaving the button before release cancels the toggle.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    ToggleButtonHeadlessChangedCount = 0

    let toggle = ToggleButton.create(&host.root, {20, 20, 60, 30})
    toggle.sigChanged += &toggleButtonHeadlessChanged

    host.mouseDown({40, 35})
    host.moveMouse({200, 100})
    host.mouseUp({200, 100})

    Swag.require(not toggle.isChecked())
    Swag.require(ToggleButtonHeadlessChangedCount == 0)
    Swag.require(host.commandCount == 0)
    Swag.require(host.app.mouseCaptureWnd == null)
}

// Programmatic changes are silent; keyboard activation follows pointer activation.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    ToggleButtonHeadlessChangedCount = 0

    let toggle = ToggleButton.create(&host.root, {20, 20, 60, 30}, ToggleButtonHeadless_Command)
    toggle.sigChanged += &toggleButtonHeadlessChanged
    toggle.setChecked(true)
    Swag.require(toggle.isChecked())
    Swag.require(ToggleButtonHeadlessChangedCount == 0 and host.commandCount == 0)

    toggle.setFocus()
    host.keyPress(Input.Key.Space)
    Swag.require(not toggle.isChecked())
    Swag.require(ToggleButtonHeadlessChangedCount == 1 and host.commandCount == 1)
}

// A programmatic state change shown at once cancels an in-flight knob slide.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.setReducedMotion(false)

    let toggle = ToggleButton.create(&host.root, {20, 20, 60, 30})
    toggle.toggle()
    host.advanceAnimations(toggle.themeMetrics().motion_QuickSeconds * 0.5)
    Swag.require(toggle.isChecked() and toggle.knob > 0 and toggle.knob < 1)

    toggle.setChecked(false)
    Swag.require(not toggle.isChecked())
    Swag.require(toggle.knob == 0)
}

// Hiding a toggle button resets its transient pointer and animated paint state.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    let toggle = ToggleButton.create(&host.root, {20, 20, 60, 30})
    toggle.isHot              = true
    toggle.isPressed          = true
    toggle.aniBk.themeCrc     = 42'u32
    toggle.aniBorder.themeCrc = 43'u32
    toggle.aniMark.themeCrc   = 44'u32

    toggle.hide()

    Swag.require(not toggle.isHot)
    Swag.require(not toggle.isPressed)
    Swag.require(toggle.aniBk.themeCrc == Swag.U32.Max)
    Swag.require(toggle.aniBorder.themeCrc == Swag.U32.Max)
    Swag.require(toggle.aniMark.themeCrc == Swag.U32.Max)
}
