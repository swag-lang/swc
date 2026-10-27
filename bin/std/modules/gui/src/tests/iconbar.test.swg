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

    Swag.assert(b1 != null)
    Swag.assert(b2 != null)
    Swag.assert(bar.children.count == 2)
    Swag.assert(bar.itemSpacing == 8)
    Swag.assert(b2.position.x - b1.position.right() == bar.itemSpacing)
    Swag.assert(bar.position.width == b1.position.width + b2.position.width + bar.itemSpacing)
    Swag.assert(bar.buttonById(IconBarHeadless_Btn1) == b1)
    Swag.assert(b1.form == .RoundedRectangle and b2.form == .RoundedRectangle)
    Swag.assert(b1.checkIndicator == .Frame and b2.checkIndicator == .Frame)
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
    Swag.assert(btn.position.width == 24 and btn.position.height == 24)
    Swag.assert(bar.position.width == 24 and bar.position.height == 24)

    bar.addButton({}, "IconBarHeadless.Btn2")
    Swag.assert(bar.position.width == 56 and bar.children[1].position.x - btn.position.right() == bar.itemSpacing)
    bar.setItemSpacing(4)
    Swag.assert(bar.position.width == 52 and bar.children[1].position.x - btn.position.right() == 4)

    bar.setItemPadding(4)
    Swag.assert(btn.position.width == 28 and btn.position.height == 28)
    Swag.assert(bar.position.width == 60 and bar.position.height == 28)

    bar.setIconSize(30)
    Swag.assert(btn.iconWidth == 30 and btn.iconHeight == 30)
    Swag.assert(btn.icon.sizeX == descriptorWidth and btn.icon.sizeY == descriptorHeight)
    Swag.assert(btn.position.width == 38 and btn.position.height == 38)
    Swag.assert(bar.position.width == 80 and bar.position.height == 38)
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
    Swag.assert(IconBarHeadlessPressedCount == 1)
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
    Swag.assert(b.isChecked)
    Swag.assert(IconBarHeadlessCheckCount == 1)

    bar.setOrientation(.Vertical)
    Swag.assert(bar.orientation == .Vertical)
    Swag.assert(bar.position.width == 32 and bar.position.height == 32)
    Swag.assert(b.form == .Rectangle)
    Swag.assert(b.checkIndicator == .Left)
}
