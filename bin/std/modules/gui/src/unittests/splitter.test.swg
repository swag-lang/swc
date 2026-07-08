#global #if #command == Swag.CompilerCommand.Test
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

    @assert(splitter.items.count == 2)
    @assert(splitter.numVisiblePanes == 2)
    @assert(splitter.isPaneVisible(0))
    @assert(splitter.isPaneVisible(1))
    @assert(splitter.items[1].view == pane1)
    @assert(pane1.parent == splitter)

    let client  = splitter.getClientRectPadding()
    let barSize = splitter.getThemeMetrics().splitView_BarSize
    let total   = splitter.items[0].size + splitter.items[1].size + barSize
    @assert(Math.abs(total - client.width) < 1.5)

    host.shutdown()
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

    splitter.showPane(1, false)
    @assert(!splitter.isPaneVisible(1))
    @assert(splitter.numVisiblePanes == 1)
    @assert(!pane1.isVisibleState())

    splitter.showPane(1, true)
    @assert(splitter.isPaneVisible(1))
    @assert(splitter.numVisiblePanes == 2)
    @assert(pane1.isVisibleState())

    host.shutdown()
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

    splitter.items[0].minSize = 20
    splitter.setPaneSize(0, -50)
    @assert(splitter.items[0].size >= 20)

    host.shutdown()
}
