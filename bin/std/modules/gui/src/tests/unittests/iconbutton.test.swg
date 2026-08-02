#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

const IconButtonHeadless_Command = "IconButtonHeadless.Command"

var IconButtonHeadlessPressedCount: u32
var IconButtonHeadlessCheckCount:   u32

func iconButtonHeadlessPressed(btn: *Button)
{
    discard btn
    IconButtonHeadlessPressedCount += 1
}

func iconButtonHeadlessChecked(btn: *IconButton)
{
    discard btn
    IconButtonHeadlessCheckCount += 1
}

func iconButtonHeadlessReset()
{
    IconButtonHeadlessPressedCount = 0
    IconButtonHeadlessCheckCount   = 0
}

// A plain icon button posts a command and fires sigPressed on click.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)
    defer host.shutdown()
    host.recordCommands()
    iconButtonHeadlessReset()

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40})
    btn.sigPressed += &iconButtonHeadlessPressed

    host.click({40, 40})
    @assert(IconButtonHeadlessPressedCount == 1)
    @assert(!btn.isChecked)
}

// A Toggle button flips its checked state on every click.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)
    defer host.shutdown()
    host.recordCommands()
    iconButtonHeadlessReset()

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40}, IconButtonHeadless_Command)
    btn.updateFlags(.Toggle)
    btn.sigCheckedChanged += &iconButtonHeadlessChecked

    host.click({40, 40})
    @assert(btn.isChecked)
    @assert(IconButtonHeadlessCheckCount == 1)

    host.click({40, 40})
    @assert(!btn.isChecked)
    @assert(IconButtonHeadlessCheckCount == 2)
}

// A radio button can only be set, never unset, by user activation.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)
    defer host.shutdown()
    host.recordCommands()
    iconButtonHeadlessReset()

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40})
    btn.updateFlags(.Radio)
    btn.sigCheckedChanged += &iconButtonHeadlessChecked

    host.click({40, 40})
    @assert(btn.isChecked)
    @assert(IconButtonHeadlessCheckCount == 1)

    host.click({40, 40})
    @assert(btn.isChecked)
    @assert(IconButtonHeadlessCheckCount == 1)
}

// Programmatic checked-state changes support both stateful modes and remain silent.
#test
{
    var host: Testing.HeadlessHost
    host.setup(180, 120)
    defer host.shutdown()
    iconButtonHeadlessReset()

    let toggle = IconButton.create(&host.root, {}, {20, 20, 40, 40}, flags: .Toggle)
    toggle.sigCheckedChanged += &iconButtonHeadlessChecked
    toggle.setChecked(true)
    @assert(toggle.isChecked)
    @assert(IconButtonHeadlessCheckCount == 0)

    toggle.setChecked(false)
    @assert(!toggle.isChecked)
    @assert(IconButtonHeadlessCheckCount == 0)

    let radio = IconButton.create(&host.root, {}, {80, 20, 40, 40}, flags: .Radio)
    radio.sigCheckedChanged += &iconButtonHeadlessChecked
    radio.setChecked(true)
    @assert(radio.isChecked)
    @assert(IconButtonHeadlessCheckCount == 0)
}

// Space and Enter activate a focused toggle with the same state, signal, and command contract as a click.
#test
{
    var host: Testing.HeadlessHost
    host.setup(180, 120)
    defer host.shutdown()
    host.recordCommands()
    iconButtonHeadlessReset()

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40}, IconButtonHeadless_Command, .Toggle)
    btn.sigCheckedChanged += &iconButtonHeadlessChecked
    host.focus(btn)

    host.keyPress(Input.Key.Space)
    @assert(btn.isChecked)
    host.keyPress(Input.Key.Return)
    @assert(!btn.isChecked)
    @assert(IconButtonHeadlessCheckCount == 2)
    @assert(host.commandCount == 2 and host.lastCommand == IconButtonHeadless_Command)
}

// Hiding a button resets both its pointer state and its animated overlay state.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)
    defer host.shutdown()
    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40})
    btn.isHot          = true
    btn.isPressed      = true
    btn.aniBk.themeCrc = 42'u32

    btn.hide()

    @assert(!btn.isHot)
    @assert(!btn.isPressed)
    @assert(btn.aniBk.themeCrc == Swag.U32.Max)
}

// Disabling a button keeps it in the layout, but still drops transient input/paint state.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)
    defer host.shutdown()
    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40})
    btn.isHot              = true
    btn.isIn               = true
    btn.isPressed          = true
    btn.isPressing         = true
    btn.aniBk.themeCrc     = 42'u32
    host.app.mouseEnterWnd = btn
    host.app.setMouseCaptureRaw(btn)

    btn.disable()

    @assert(!btn.isHot)
    @assert(!btn.isIn)
    @assert(!btn.isPressed)
    @assert(!btn.isPressing)
    @assert(btn.aniBk.themeCrc == Swag.U32.Max)
    @assert(host.app.mouseEnterWnd == null)
    @assert(host.app.mouseCaptureWnd == null)
}
