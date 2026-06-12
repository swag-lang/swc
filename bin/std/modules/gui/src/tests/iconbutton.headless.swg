#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core

const IconButtonHeadless_Command = "IconButtonHeadless.Command"

var IconButtonHeadlessPressedCount: u32
var IconButtonHeadlessCheckCount:   u32

func iconButtonHeadlessPressed(btn: *Button)    { discard btn; IconButtonHeadlessPressedCount += 1 }
func iconButtonHeadlessChecked(btn: *IconButton) { discard btn; IconButtonHeadlessCheckCount += 1 }

func iconButtonHeadlessReset()
{
    IconButtonHeadlessPressedCount = 0
    IconButtonHeadlessCheckCount   = 0
}

// A plain icon button posts a command and fires sigPressed on click.
#test
{
    var host: GuiHeadlessHost
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
    var host: GuiHeadlessHost
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
    var host: GuiHeadlessHost
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
