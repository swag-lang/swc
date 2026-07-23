#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core

const IconBarHeadless_Btn1 = "IconBarHeadless.Btn1"

var IconBarHeadlessPressedCount: u32
var IconBarHeadlessCheckCount:   u32

func iconBarHeadlessPressed(btn: *IconButton)
{
    discard btn;
    IconBarHeadlessPressedCount += 1
}

func iconBarHeadlessChecked(btn: *IconButton)
{
    discard btn;
    IconBarHeadlessCheckCount += 1
}

func iconBarHeadlessReset()
{
    IconBarHeadlessPressedCount = 0
    IconBarHeadlessCheckCount   = 0
}

// Buttons are added as children and retrievable by id.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)
    iconBarHeadlessReset()

    let bar = IconBar.create(&host.root, 24, {20, 20})
    let b1  = bar.addItem({}, IconBarHeadless_Btn1)
    let b2  = bar.addCheckableToggleItem({}, "IconBarHeadless.Btn2")

    @assert(b1 != null)
    @assert(b2 != null)
    @assert(bar.childs.count == 2)
    @assert(bar.getButton(IconBarHeadless_Btn1) == b1)

    host.shutdown()
}

// Clicking a docked button forwards through the bar's sigPressed.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)
    iconBarHeadlessReset()

    let bar = IconBar.create(&host.root, 24, {20, 20})
    bar.sigPressed += &iconBarHeadlessPressed
    bar.addItem({}, IconBarHeadless_Btn1)

    // First button is docked on the left, filling the bar origin.
    host.click({34, 34})
    @assert(IconBarHeadlessPressedCount == 1)

    host.shutdown()
}

// A checkable-toggle button forwards through the bar's sigCheckChanged.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)
    iconBarHeadlessReset()

    let bar = IconBar.create(&host.root, 24, {20, 20})
    bar.sigCheckChanged += &iconBarHeadlessChecked
    let b = bar.addCheckableToggleItem({}, IconBarHeadless_Btn1)

    host.click({34, 34})
    @assert(b.isChecked)
    @assert(IconBarHeadlessCheckCount == 1)

    host.shutdown()
}
