#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Changing measured column widths invalidates the parent layout.
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 80)

    let row    = StackLayoutCtrl.create(&host.root, .Left, {0, 0, 600, 40})
    let header = Header.create(row, {0, 0, 0, 24})
    header.addColumn("Name", 120)
    host.pump()
    let originalWidth = header.measure({}).preferred.x

    header.addColumn("Count", 75)
    host.pump()
    let addedWidth = header.measure({}).preferred.x
    Swag.require(addedWidth != originalWidth, "Adding a header column should change its measured content width")
    Swag.require(header.position.width == addedWidth,
                 Format.toString("Header after add: measured %, committed %", addedWidth, header.position.width).toString())

    header.setItemWidth(0, 250)
    host.pump()
    let resizedWidth = header.measure({}).preferred.x
    Swag.require(resizedWidth != addedWidth, "Changing a header column width should change its measured content width")
    Swag.require(header.position.width == resizedWidth,
                 Format.toString("Header after resize: measured %, committed %", resizedWidth, header.position.width).toString())
}

// Header columns are added with a name and width.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 80)
    let header = Header.create(&host.root, {10, 10, 300, 24})
    Swag.require(header.items.isEmpty())

    header.addColumn("Name", 120)
    header.addColumn("Size", 80)
    Swag.require(header.items.count == 2)
    Swag.require(header.flags.has(.Clickable) and header.flags.has(.Separators))

    Swag.require(header.itemAt(0).name.raw == "Name")
    Swag.require(header.itemAt(1).name.raw == "Size")
    Swag.require(Math.abs(header.itemWidthAt(0) - 120) < 0.01)
    Swag.require(header.itemForColumn(1) == header.itemAt(1))

    header.setItemWidthLimits(0, 100, 140)
    header.setItemWidth(0, 20)
    Swag.require(header.itemWidthAt(0) == 100)
    header.setItemWidthForColumn(0, 300)
    Swag.require(header.itemWidthAt(0) == 140)

    header.setSortIndicator(1, .Descending)
    Swag.require(header.sortColumn == 1 and header.sortDirection == .Descending)
    header.clearSortIndicator()
    Swag.require(header.sortColumn == Swag.U32.Max and header.sortDirection == .None)
}

// A compact read-only table can keep the header baseline without drawing or activating vertical
// separators that imply configurable columns.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 70)
    host.root.backgroundStyle = .Window

    let header = Header.create(&host.root, {10, 10, 200, 24})
    header.form = .Transparent
    header.addColumn("Offset", 80)
    header.addColumn("Value", 100)

    var evt = MouseEvent{kind: .Move}
    evt.surfacePos = header.localToSurface(Math.Point{92, 10})
    header.sendEvent(&evt)
    Swag.require(header.hotSeparator)

    header.updateFlags(remove: .Separators)
    Swag.require(not header.flags.has(.Separators))
    Swag.require(not header.hotSeparator)
    header.sendEvent(&evt)
    Swag.require(not header.hotSeparator)
    discard host.render()
}

// A header nested below a presented window keeps its local content clip when the subtree is
// rendered into an off-screen layer. A surface-space clip used to fall outside that layer and
// hide the column labels for the duration of a page transition.
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 100)
    host.root.backgroundStyle = .Window

    let page   = Wnd.create'Wnd(&host.root, null, {160, 10, 220, 60})
    let header = Header.create(page, {0, 10, 180, 24})
    header.form = .Transparent
    header.addColumn("Mounted", 160)

    let background = host.theme.colors.wnd_Bk
    let normal     = host.render()
    var normalInk: bool
    var y          = 22's32
    while y < 41
    {
        var x = 164's32
        while x < 240
        {
            if normal.pixelColor(x, y).argb != background.argb do
                normalInk = true
            x += 1
        }

        y += 1
    }

    Swag.require(normalInk)

    page.setPresentationOpacity(0.5)
    page.setPresentationOffset({8, 0})
    let presented = host.render()
    var presentedInk: bool
    y = 22
    while y < 41
    {
        var x = 172's32
        while x < 248
        {
            if presented.pixelColor(x, y).argb != background.argb do
                presentedInk = true
            x += 1
        }

        y += 1
    }

    Swag.require(presentedInk)
}
