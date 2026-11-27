#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

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

// The technical page keeps its own quiet hierarchy beside the page arrow, in Encre.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 560, 400, false)
    let sheet = InfoSheet.create(&host.root)
    sheet.setTitle("Northbound.mp4")
    sheet.setIdentity("Films / Northbound")
    sheet.beginPage("Media")
    sheet.addFact("8.1", "IMDb")
    sheet.addText("A film crossing a long winter landscape.")
    sheet.beginPage("Technical")
    sheet.addSection("Video")
    sheet.addReading("Format", "MPEG-4")
    sheet.addReading("Dimensions", "1920 × 1080 px")
    sheet.addReading("Frame rate", "23.98 fps")
    sheet.addSection("Audio")
    sheet.addReading("Encoding", "AAC")
    sheet.addReading("Sample rate", "48000 Hz")
    sheet.selectPage(1)
    sheet.open()
    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, "floating.sheet.technical.ink")
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
    Swag.require(toast.isLocallyVisible())
    Swag.require(Math.abs(toast.position.horzCenter() - 450) <= 1)
    Swag.require(toast.position.bottom() == 400 - metrics.toast_Bottom and toast.position.height == metrics.toast_Height)

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, light ? "toast.paper" : "toast.ink")

    // The timer takes it away; the action is answered once and takes it away too.
    host.fireTimers()
    Swag.require(not toast.isLocallyVisible())
    toast.show("Saved", "capture-2026-10-28.png", .Done, "Show")
    let action = toast.surfaceRect()
    host.moveMouse({action.x + toast.actionRect.horzCenter(), action.vertCenter()})
    Swag.require(toast.hotAction and toast.timer == null)
    host.click({action.x + toast.actionRect.horzCenter(), action.vertCenter()})
    Swag.require(undone == 1 and not toast.isLocallyVisible())
}
