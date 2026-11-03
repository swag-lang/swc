#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Panes are parented, counted, and fill the client area (panes + bars).
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    let splitter = SplitterCtrl.create(&host.root, {0, 0, 300, 200})
    let pane0    = Wnd.create'Wnd(splitter, null, {})
    let pane1    = Wnd.create'Wnd(splitter, null, {})
    splitter.addPane(pane0)
    splitter.addPane(pane1, 100)

    Swag.require(splitter.items.count == 2)
    Swag.require(splitter.numVisiblePanes == 2)
    Swag.require(splitter.isPaneVisible(0))
    Swag.require(splitter.isPaneVisible(1))
    Swag.require(splitter.items[1]!.view == pane1)
    Swag.require(pane1.parent == splitter)

    let client  = splitter.paddedClientRect()
    let barSize = splitter.themeMetrics().splitView_BarSize
    let total   = splitter.items[0]!.size + splitter.items[1]!.size + barSize
    Swag.require(Math.abs(total - client.width) < 1.5)
}

// Panes authored before the splitter has a rectangle keep their initial sizes for first layout.
#test
{
    for vertical in [false, true]
    {
        var host: Testing.HeadlessHost
        host.setup(640, 640)
        let splitter = SplitterCtrl.create(&host.root, vertical: vertical)
        let first    = splitter.addPane(Wnd.create'Wnd(splitter), 188)
        first.preserveSize = true
        first.minimumSize  = 88
        let second = splitter.addPane(Wnd.create'Wnd(splitter), 100)
        Swag.require(first.size == 188 and second.size == 100)

        splitter.resize(600, 600)
        Swag.require(first.size == 188)
        Swag.require(Math.abs(first.size + second.size + splitter.themeMetrics().splitView_BarSize - 600) < 0.01)
    }
}

// A size change is shared within each priority group, including when every pane preserves size.
#test
{
    for preserve in [false, true]
    {
        var host: Testing.HeadlessHost
        host.setup(640, 240)
        let splitter = SplitterCtrl.create(&host.root)
        for 3
        {
            let item = splitter.addPane(Wnd.create'Wnd(splitter), 100)
            item.preserveSize = preserve
        }

        let extent = 300 + 2 * splitter.themeMetrics().splitView_BarSize
        splitter.resize(extent, 200)
        for item in splitter.items do
            Swag.require(item!.size == 100)
        splitter.resize(extent + 90, 200)
        for item in splitter.items do
            Swag.require(item!.size == 130)
    }
}

// A pane can be hidden and shown again, updating the visible-pane count.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    let splitter = SplitterCtrl.create(&host.root, {0, 0, 300, 200})
    let pane0    = Wnd.create'Wnd(splitter, null, {})
    let pane1    = Wnd.create'Wnd(splitter, null, {})
    splitter.addPane(pane0)
    splitter.addPane(pane1, 100)

    splitter.setPaneVisible(1, false)
    Swag.require(not splitter.isPaneVisible(1))
    Swag.require(splitter.numVisiblePanes == 1)
    Swag.require(not pane1.isLocallyVisible())

    splitter.setPaneVisible(1, true)
    Swag.require(splitter.isPaneVisible(1))
    Swag.require(splitter.numVisiblePanes == 2)
    Swag.require(pane1.isLocallyVisible())
}

// setPaneSize clamps to the pane minimum size.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    let splitter = SplitterCtrl.create(&host.root, {0, 0, 300, 200})
    let pane0    = Wnd.create'Wnd(splitter, null, {})
    let pane1    = Wnd.create'Wnd(splitter, null, {})
    splitter.addPane(pane0)
    splitter.addPane(pane1, 100)

    let pane0It = unwrap splitter.items[0]
    pane0It.minimumSize = 20
    splitter.setPaneSize(0, -50)
    Swag.require(pane0It.size >= 20)
}

// Hidden panes do not absorb size transferred between visible neighbors.
#test
{
    var host: Testing.HeadlessHost
    host.setup(340, 220)
    let splitter = SplitterCtrl.create(&host.root, {0, 0, 320, 200})
    let pane0    = Wnd.create'Wnd(splitter)
    let pane1    = Wnd.create'Wnd(splitter)
    let pane2    = Wnd.create'Wnd(splitter)
    let item0    = splitter.addPane(pane0)
    let item1    = splitter.addPane(pane1, 90, showTitle: true)
    let item2    = splitter.addPane(pane2, 90)

    splitter.setPaneVisible(1, false)
    Swag.require(not pane1.isLocallyVisible())
    Swag.require(item1.label and not item1.label.isLocallyVisible())

    let middleSize = item1.size
    let total      = item0.size + item2.size
    let requested  = item0.size + 30
    splitter.setPaneSize(0, requested)

    Swag.require(Math.abs(item0.size - requested) < 0.01)
    Swag.require(Math.abs(item0.size + item2.size - total) < 0.01)
    Swag.require(item1.size == middleSize)
}
