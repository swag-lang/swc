#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Nested splits keep stable pane identities and compose their minimum sizes along each axis.
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 700)

    let dock = DockHost.create(&host.root, {0, 0, 880, 660})
    let editor = Label.create(&host.root, "Editor")
    dock.addPane("editor", "Editor", editor, {200, 100})
    host.pump()

    let inspector = Label.create(&host.root, "Inspector")
    dock.splitPane("editor", "inspector", "Inspector", inspector, .Horizontal, splitSize: 300, minimumSize: {180, 120})
    host.pump()

    let output = Label.create(&host.root, "Output")
    dock.splitPane("inspector", "output", "Output", output, .Vertical, splitSize: 210, minimumSize: {90, 80})
    host.pump()

    let bar = dock.themeMetrics().splitView_BarSize
    Swag.require(dock.paneCount == 3)
    Swag.require(dock.hasPane("editor") and dock.hasPane("inspector") and dock.hasPane("output"))
    Swag.require(not dock.hasPane("missing"))
    Swag.require(dock.minSize == Math.Point{200 + bar + 180, 120 + bar + 80})
    Swag.require(editor.position.width >= 200 and editor.position.height >= 100)
    Swag.require(inspector.position.width >= 180 and inspector.position.height >= 120)
    Swag.require(output.position.width >= 90 and output.position.height >= 80)

    dock.setPosition({0, 0, 50, 40})
    Swag.require(dock.position.width >= dock.minSize.x and dock.position.height >= dock.minSize.y)
    dock.setPosition({0, 0, 880, 660})
    host.pump()

    dock.selectPane("inspector")
    Swag.require(inspector.isLocallyVisible())
    dock.hidePane("inspector")
    host.pump()
    Swag.require(not inspector.isLocallyVisible())
    Swag.require(dock.minSize == Math.Point{200 + bar + 90, Math.max(100, 80)})

    dock.showPane("inspector")
    host.pump()
    Swag.require(inspector.isLocallyVisible())
    Swag.require(dock.minSize == Math.Point{200 + bar + 180, 120 + bar + 80})

    dock.closePane("inspector")
    Swag.require(not dock.hasPane("inspector") and dock.paneCount == 2)
    Swag.require(inspector.isPendingDestroy)
    host.pump()
}

// A stack preserves each pane's identity while hiding the tab and transferring selection.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 400)

    let dock = DockHost.create(&host.root, {0, 0, 620, 360})
    let first = Label.create(&host.root, "First")
    let second = Label.create(&host.root, "Second")
    dock.addPane("first", "First", first, {120, 80})
    dock.addTab("first", "second", "Second", second, {180, 100})
    host.pump()

    Swag.require(dock.paneCount == 2)
    Swag.require(first.isLocallyVisible() and not second.isLocallyVisible())
    Swag.require(dock.minSize == Math.Point{180, 100})

    dock.selectPane("second")
    dock.hidePane("second")
    host.pump()
    Swag.require(first.isLocallyVisible() and not second.isLocallyVisible())
    Swag.require(dock.minSize == Math.Point{120, 80})

    dock.showPane("second")
    host.pump()
    Swag.require(first.isLocallyVisible() and not second.isLocallyVisible())
    Swag.require(dock.minSize == Math.Point{180, 100})
    dock.selectPane("second")
    Swag.require(second.isLocallyVisible())

    dock.closePane("first")
    Swag.require(not dock.hasPane("first") and dock.hasPane("second"))
    Swag.require(dock.paneCount == 1)
}

// Closing the last pane leaves the host reusable with a new root pane.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 240)

    let dock = DockHost.create(&host.root, {0, 0, 300, 200})
    dock.addPane("old", "Old", Label.create(&host.root, "Old"))
    dock.closePane("old")
    Swag.require(dock.paneCount == 0 and not dock.hasPane("old"))

    dock.addPane("new", "New", Label.create(&host.root, "New"))
    Swag.require(dock.paneCount == 1 and dock.hasPane("new"))
}

// A requested split size survives creation before the first host layout.
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 320)

    let dock = DockHost.create(&host.root, {0, 0, 560, 260})
    dock.addPane("left", "Left", Label.create(&host.root, "Left"))
    let right = Label.create(&host.root, "Right")
    dock.splitPane("left", "right", "Right", right, .Horizontal, splitSize: 160)
    host.pump()

    Swag.require(Math.abs(right.position.width - 160) < 1)
}

// A split with no requested size divides the available axis evenly when pane minimums permit.
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 320)

    let dock = DockHost.create(&host.root, {0, 0, 560, 260})
    let left = Label.create(&host.root, "Left")
    let right = Label.create(&host.root, "Right")
    dock.addPane("left", "Left", left, {120, 80})
    dock.splitPane("left", "right", "Right", right, .Horizontal, minimumSize: {140, 90})
    host.pump()

    Swag.require(Math.abs(left.position.width - right.position.width) < 1,
                 Format.toString("left %, right %", left.position.width, right.position.width).toString())
}
