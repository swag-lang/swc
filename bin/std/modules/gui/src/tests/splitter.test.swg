#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Two structural panel panes keep all four rounded sides, including the sides facing their
// draggable divider. The divider is one pixel wider than the ordinary outer-panel gutter so
// both antialiased silhouettes remain distinct.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let splitter = SplitterCtrl.create(&host.root, {20, 20, 280, 180}, vertical: true)
    splitter.backgroundStyle = .ToolBar

    let pane0 = Wnd.create'Wnd(splitter)
    pane0.backgroundStyle = .Panel
    let pane1 = Wnd.create'Wnd(splitter)
    pane1.backgroundStyle = .Panel
    splitter.addPane(pane0, 88)
    splitter.addPane(pane1)
    splitter.sendResizeEvent()

    Swag.assert(splitter.themeMetrics().splitView_BarSize == splitter.themeMetrics().panel_GutterSize + 1)
    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, "splitter.panel-panes.vertical")
}

// Panes are parented, counted, and fill the client area (panes + bars).
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    defer host.shutdown()
    let splitter = SplitterCtrl.create(&host.root, {0, 0, 300, 200})
    let pane0    = Wnd.create'Wnd(splitter, null, {})
    let pane1    = Wnd.create'Wnd(splitter, null, {})
    splitter.addPane(pane0)
    splitter.addPane(pane1, 100)

    Swag.assert(splitter.items.count == 2)
    Swag.assert(splitter.numVisiblePanes == 2)
    Swag.assert(splitter.isPaneVisible(0))
    Swag.assert(splitter.isPaneVisible(1))
    Swag.assert(splitter.items[1]!.view == pane1)
    Swag.assert(pane1.parent == splitter)

    let client  = splitter.paddedClientRect()
    let barSize = splitter.themeMetrics().splitView_BarSize
    let total   = splitter.items[0]!.size + splitter.items[1]!.size + barSize
    Swag.assert(Math.abs(total - client.width) < 1.5)
}

// A pane can be hidden and shown again, updating the visible-pane count.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    defer host.shutdown()
    let splitter = SplitterCtrl.create(&host.root, {0, 0, 300, 200})
    let pane0    = Wnd.create'Wnd(splitter, null, {})
    let pane1    = Wnd.create'Wnd(splitter, null, {})
    splitter.addPane(pane0)
    splitter.addPane(pane1, 100)

    splitter.setPaneVisible(1, false)
    Swag.assert(!splitter.isPaneVisible(1))
    Swag.assert(splitter.numVisiblePanes == 1)
    Swag.assert(!pane1.isLocallyVisible())

    splitter.setPaneVisible(1, true)
    Swag.assert(splitter.isPaneVisible(1))
    Swag.assert(splitter.numVisiblePanes == 2)
    Swag.assert(pane1.isLocallyVisible())
}

// setPaneSize clamps to the pane minimum size.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    defer host.shutdown()
    let splitter = SplitterCtrl.create(&host.root, {0, 0, 300, 200})
    let pane0    = Wnd.create'Wnd(splitter, null, {})
    let pane1    = Wnd.create'Wnd(splitter, null, {})
    splitter.addPane(pane0)
    splitter.addPane(pane1, 100)

    let pane0It = splitter.items[0]!
    pane0It.minimumSize = 20
    splitter.setPaneSize(0, -50)
    Swag.assert(pane0It.size >= 20)
}

// Hidden panes do not absorb size transferred between visible neighbors.
#test
{
    var host: Testing.HeadlessHost
    host.setup(340, 220)
    defer host.shutdown()
    let splitter = SplitterCtrl.create(&host.root, {0, 0, 320, 200})
    let pane0    = Wnd.create'Wnd(splitter)
    let pane1    = Wnd.create'Wnd(splitter)
    let pane2    = Wnd.create'Wnd(splitter)
    let item0    = splitter.addPane(pane0)
    let item1    = splitter.addPane(pane1, 90, showTitle: true)
    let item2    = splitter.addPane(pane2, 90)

    splitter.setPaneVisible(1, false)
    Swag.assert(!pane1.isLocallyVisible())
    Swag.assert(item1.label and !item1.label.isLocallyVisible())

    let middleSize = item1.size
    let total      = item0.size + item2.size
    let requested  = item0.size + 30
    splitter.setPaneSize(0, requested)

    Swag.assert(Math.abs(item0.size - requested) < 0.01)
    Swag.assert(Math.abs(item0.size + item2.size - total) < 0.01)
    Swag.assert(item1.size == middleSize)
}
