#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

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

    @assert(splitter.items.count == 2)
    @assert(splitter.numVisiblePanes == 2)
    @assert(splitter.isPaneVisible(0))
    @assert(splitter.isPaneVisible(1))
    @assert(splitter.items[1]!.view == pane1)
    @assert(pane1.parent == splitter)

    let client  = splitter.paddedClientRect()
    let barSize = splitter.themeMetrics().splitView_BarSize
    let total   = splitter.items[0]!.size + splitter.items[1]!.size + barSize
    @assert(Math.abs(total - client.width) < 1.5)
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
    @assert(!splitter.isPaneVisible(1))
    @assert(splitter.numVisiblePanes == 1)
    @assert(!pane1.isLocallyVisible())

    splitter.setPaneVisible(1, true)
    @assert(splitter.isPaneVisible(1))
    @assert(splitter.numVisiblePanes == 2)
    @assert(pane1.isLocallyVisible())
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
    @assert(pane0It.size >= 20)
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
    @assert(!pane1.isLocallyVisible())
    @assert(item1.label and !item1.label.isLocallyVisible())

    let middleSize = item1.size
    let total      = item0.size + item2.size
    let requested  = item0.size + 30
    splitter.setPaneSize(0, requested)

    @assert(Math.abs(item0.size - requested) < 0.01)
    @assert(Math.abs(item0.size + item2.size - total) < 0.01)
    @assert(item1.size == middleSize)
}
