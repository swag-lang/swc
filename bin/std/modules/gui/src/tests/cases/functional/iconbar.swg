#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

const IconBarHeadless_Btn1 = "IconBarHeadless.Btn1"

var IconBarHeadlessPressedCount: u32
var IconBarHeadlessCheckCount:   u32

func iconBarHeadlessPressed(_: *IconButton)
{
    IconBarHeadlessPressedCount += 1
}

func iconBarHeadlessChecked(_: *IconButton)
{
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
    let b1  = bar.addButton({}, IconBarHeadless_Btn1)
    let b2  = bar.addToggleButton({}, "IconBarHeadless.Btn2")

    Swag.require(b1 != null)
    Swag.require(b2 != null)
    Swag.require(bar.children.count == 2)
    Swag.require(bar.itemSpacing == 8)
    Swag.require(b2.position.x - b1.position.right() == bar.itemSpacing)
    Swag.require(bar.position.width == b1.position.width + b2.position.width + bar.itemSpacing)
    Swag.require(bar.buttonById(IconBarHeadless_Btn1) == b1)
    Swag.require(b1.form == .RoundedRectangle and b2.form == .RoundedRectangle)
    Swag.require(b1.checkIndicator == .Frame and b2.checkIndicator == .Frame)
}

// Changing bar metrics updates existing buttons as well as the bar extent.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    let bar              = IconBar.create(&host.root, 20, {20, 20}, itemPadding: 2)
    let btn              = bar.addButton({}, IconBarHeadless_Btn1)
    let descriptorWidth  = btn.icon.sizeX
    let descriptorHeight = btn.icon.sizeY
    Swag.require(btn.position.width == 24 and btn.position.height == 24)
    Swag.require(bar.position.width == 24 and bar.position.height == 24)

    bar.addButton({}, "IconBarHeadless.Btn2")
    Swag.require(bar.position.width == 56 and bar.children[1].position.x - btn.position.right() == bar.itemSpacing)
    bar.setItemSpacing(4)
    Swag.require(bar.position.width == 52 and bar.children[1].position.x - btn.position.right() == 4)

    bar.setItemPadding(4)
    Swag.require(btn.position.width == 28 and btn.position.height == 28)
    Swag.require(bar.position.width == 60 and bar.position.height == 28)

    bar.setIconSize(30)
    Swag.require(btn.iconWidth == 30 and btn.iconHeight == 30)
    Swag.require(btn.icon.sizeX == descriptorWidth and btn.icon.sizeY == descriptorHeight)
    Swag.require(btn.position.width == 38 and btn.position.height == 38)
    Swag.require(bar.position.width == 80 and bar.position.height == 38)
}

// Clicking a docked button forwards through the bar's sigPressed.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)
    iconBarHeadlessReset()

    let bar = IconBar.create(&host.root, 24, {20, 20})
    bar.sigPressed += &iconBarHeadlessPressed
    bar.addButton({}, IconBarHeadless_Btn1)

    // First button is docked on the left, filling the bar origin.
    host.click({34, 34})
    Swag.require(IconBarHeadlessPressedCount == 1)
}

// A toggle button forwards through the bar's sigCheckedChanged.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)
    iconBarHeadlessReset()

    let bar = IconBar.create(&host.root, 24, {20, 20})
    bar.sigCheckedChanged += &iconBarHeadlessChecked
    let b = bar.addToggleButton({}, IconBarHeadless_Btn1)

    host.click({34, 34})
    Swag.require(b.isChecked)
    Swag.require(IconBarHeadlessCheckCount == 1)

    bar.setOrientation(.Vertical)
    Swag.require(bar.orientation == .Vertical)
    Swag.require(bar.position.width == 32 and bar.position.height == 32)
    Swag.require(b.form == .Rectangle)
    Swag.require(b.checkIndicator == .Left)
}

// Hiding and showing a button updates the bar's content size and trailing gap.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)

    let bar         = IconBar.create(&host.root, 24, {20, 20})
    let first       = bar.addButton({})
    let second      = bar.addButton({})
    let singleWidth = first.position.width
    let fullWidth   = bar.position.width

    second.hide()
    host.pump()
    Swag.require(bar.position.width == singleWidth)
    Swag.require(first.margin.z == 0)

    second.show()
    host.pump()
    Swag.require(bar.position.width == fullWidth)
    Swag.require(first.margin.z == bar.itemSpacing)
}
