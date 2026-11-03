#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core, Pixel

// Builds a window of `width` by `height` on the theme of `light`, with a sheet of paper standing
// for the work in its middle, so a floating component reads against something it covers.
func floatingHost(host: *Testing.HeadlessHost, width, height: f32, light: bool)
{
    host.setup(width, height)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    host.root.backgroundStyle = .Window
    with let work = Wnd.create'Wnd(&host.root, {width * 0.25, height * 0.2, width * 0.5, height * 0.5})
    {
        .backgroundStyle = .Dialog
    }
}

// The dock stands at the leading edge, vertically centred, and keeps exactly one tool active.

// The mini-bar stands above the selection, centred on it, and goes below it near the top edge.

// The hint line sits centred, its bottom the hint inset above the bottom edge, as wide as what it writes.

// A hint line with less room than it writes leaves its last hints out whole, rather than cutting
// a word at its edge; the reading always stands.

// A leading and a trailing hint line stand on the edges the parent's padding measures, at the same
// height as a centred one.

// The sheet opens at the trailing edge, below the strip of the window, and its key toggles it.

// A sheet arrives from its edge and fades out, reachable at once on the way in and gone at
// once on the way out; the mini-bar leaves its selection rising, and follows it once it is up.

// The inspector stands at the trailing edge with its editors in one column, and folds to a tab.

// An inspector carrying generated settings stands the whole height of its parent and hands them
// the column under its rows; clearing the rows keeps them.

// A small negative top offset balances the top and bottom insets without crossing the parent's
// floating inset when the strip is hidden.

// A mini-bar is filled again for each selection: clearing it destroys what it held.

// A section label names its group in small spaced capitals and can be renamed.

// The dock, a selection with its mini-bar and the hint line, in Encre.
#[Swag.TestTag("golden")]
#test
{
    let light = false
    var host: Testing.HeadlessHost
    floatingHost(&host, 560, 360, light)

    with let dock = ToolDock.create(&host.root)
    {
        discard .addTool(host.theme.icon(.Edit, 18), toolTip: "Select")
        .setActiveTool(.addTool(host.theme.icon(.Plus, 18), toolTip: "Rectangle"))
        discard .addTool(host.theme.icon(.Link, 18), toolTip: "Arrow")
        discard .addTool(host.theme.icon(.Picker, 18), toolTip: "Pick")
    }

    with let bar = MiniBar.create(&host.root)
    {
        discard .addButton(host.theme.icon(.Copy, 16), toolTip: "Copy")
        discard .addButton(host.theme.icon(.Duplicate, 16), toolTip: "Duplicate")
        .addSeparator()
        discard .addTextButton("Group")
        discard .addButton(host.theme.icon(.More, 16), toolTip: "Properties")
    }

    with let hint = HintLine.create(&host.root)
    {
        .setReading("880 × 550 · 100 %")
        .addHint(strings().key_Space, "capture, open, library")
    }

    host.root.applyLayout()
    bar.showNear({240, 190, 120, 50})

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, light ? "floating.tools.paper" : "floating.tools.ink")
}

// The information sheet, open over the work, in Papier.
#[Swag.TestTag("golden")]
#test
{
    let light = true
    var host: Testing.HeadlessHost
    floatingHost(&host, 560, 400, light)

    with let sheet = InfoSheet.create(&host.root)
    {
        .setTitle("viewerchrome.swg")
        .setIdentity("swagscope / src · 24.1 KB")
        .addFact("612", "lines")
        .addSection("File")
        .addReading("Encoding", "UTF-8")
        .addReading("Line ends", "CRLF")
        .addReading("Kind", "Swag source", mono: false)
        .addText("The window chrome of the viewer: the action bar, its centre group and its spacing.")
        .addLink("Show in folder", "sheet.folder")
        .open()
    }

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, light ? "floating.sheet.paper" : "floating.sheet.ink")
}

// The inspector, unfolded and folded, in Encre.
#[Swag.TestTag("golden")]
#test
{
    let light = false
    var host: Testing.HeadlessHost
    floatingHost(&host, 560, 400, light)

    let inspector = Inspector.create(&host.root)
    inspector.setTitle("Arrow", "1 object")
    discard inspector.addAction("Delete")
    inspector.addSection("Stroke")
    with let thickness = Slider.create(&host.root, {})
    {
        .setValue(0.3)
    }

    inspector.addRow("Thickness", thickness)
    inspector.addRow("Dashes", Stepper.create(&host.root, {}))
    inspector.addSection("Effects")
    inspector.addRow("Shadow", ToggleButton.create(&host.root, {}), fill: false)
    host.root.applyLayout()

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, light ? "floating.inspector.paper" : "floating.inspector.ink")

    inspector.setFolded(true)
    var folded = host.render()
    Pixel.Testing.assertImageGolden(&folded, light ? "floating.inspector.folded.paper" : "floating.inspector.folded.ink")
}

// A floating panel holds what the application puts in it inside its padding; floating, it casts
// its shadow outside its body, and docked beside the work it casts none.

// A hint without a key is words alone: what the tool in hand does takes no keycap.

// A toast stands centred above the foot of its parent, stays while the pointer is over it, leaves
// on its timer, and answers its action once.
#[Swag.TestTag("golden")]
#test
{
    let light = true
    var host: Testing.HeadlessHost
    floatingHost(&host, 900, 400, light)
    let metrics = host.theme.metrics

    let toast  = Toast.create(&host.root)
    var undone = 0
    toast.sigAction += func|&undone|(_) { undone += 1 }
    toast.show("Removed from the history", "design.silence.md", .Done, "Undo")
    Swag.assert(toast.isLocallyVisible())
    Swag.assert(Math.abs(toast.position.horzCenter() - 450) <= 1)
    Swag.assert(toast.position.bottom() == 400 - metrics.toast_Bottom and toast.position.height == metrics.toast_Height)

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, light ? "toast.paper" : "toast.ink")

    // The timer takes it away; the action is answered once and takes it away too.
    host.fireTimers()
    Swag.assert(not toast.isLocallyVisible())
    toast.show("Saved", "capture-2026-10-28.png", .Done, "Show")
    let action = toast.surfaceRect()
    host.moveMouse({action.x + toast.actionRect.horzCenter(), action.vertCenter()})
    Swag.assert(toast.hotAction and toast.timer == null)
    host.click({action.x + toast.actionRect.horzCenter(), action.vertCenter()})
    Swag.assert(undone == 1 and not toast.isLocallyVisible())
}

// A dock cell can stand for a group of tools: it shows the one chosen last, and a tool of the
// group made the active one by its command comes into the cell.
