#global #if #command == Swag.CompilerCommand.Test
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
    host.recordCommands()
    iconButtonHeadlessReset()

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40})
    btn.sigPressed += &iconButtonHeadlessPressed

    host.click({40, 40})
    @assert(IconButtonHeadlessPressedCount == 1)
    @assert(!btn.isChecked)

    host.shutdown()
}

// A CheckableToggle button flips its checked state on every click.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)
    host.recordCommands()
    iconButtonHeadlessReset()

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40}, IconButtonHeadless_Command)
    btn.iconBtnFlags.add(.CheckableToggle)
    btn.sigCheckChanged += &iconButtonHeadlessChecked

    host.click({40, 40})
    @assert(btn.isChecked)
    @assert(IconButtonHeadlessCheckCount == 1)

    host.click({40, 40})
    @assert(!btn.isChecked)
    @assert(IconButtonHeadlessCheckCount == 2)

    host.shutdown()
}

// A Checkable button can only be set, never unset, by clicking.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)
    host.recordCommands()
    iconButtonHeadlessReset()

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40})
    btn.iconBtnFlags.add(.Checkable)
    btn.sigCheckChanged += &iconButtonHeadlessChecked

    host.click({40, 40})
    @assert(btn.isChecked)
    @assert(IconButtonHeadlessCheckCount == 1)

    host.click({40, 40})
    @assert(btn.isChecked)
    @assert(IconButtonHeadlessCheckCount == 1)

    host.shutdown()
}

// Hiding a button resets both its pointer state and its animated overlay state.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40})
    btn.isHot          = true
    btn.isPressed      = true
    btn.aniBk.themeCrc = 42'u32

    btn.hide()

    @assert(!btn.isHot)
    @assert(!btn.isPressed)
    @assert(btn.aniBk.themeCrc == Swag.U32.Max)

    host.shutdown()
}

// Disabling a button keeps it in the layout, but still drops transient input/paint state.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40})
    btn.isHot                = true
    btn.isIn                 = true
    btn.isPressed            = true
    btn.isPressing           = true
    btn.aniBk.themeCrc       = 42'u32
    host.app.mouseEnterWnd   = btn
    host.app.mouseCaptureWnd = btn

    btn.disable()

    @assert(!btn.isHot)
    @assert(!btn.isIn)
    @assert(!btn.isPressed)
    @assert(!btn.isPressing)
    @assert(btn.aniBk.themeCrc == Swag.U32.Max)
    @assert(host.app.mouseEnterWnd == null)
    @assert(host.app.mouseCaptureWnd == null)

    host.shutdown()
}
