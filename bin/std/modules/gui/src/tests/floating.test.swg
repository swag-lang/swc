#global if #command == Swag.CompilerCommand.Test
#global private

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
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 480, 400, false)
    let metrics = host.theme.metrics

    var changes = 0
    let dock    = ToolDock.create(&host.root)
    dock.sigToolChanged += func|changes = &changes|(_, _) { changes[] += 1 }
    let select = dock.addTool(host.theme.icon(.Edit, 18), toolTip: "Select")
    let shape  = dock.addTool(host.theme.icon(.Plus, 18), toolTip: "Rectangle")
    discard dock.addTool(host.theme.icon(.Link, 18), toolTip: "Arrow")
    host.root.applyLayout()

    // Its body sits the floating inset from the edge, centred on the height of the window.
    let body = dock.bodySize()
    Swag.assert(dock.position.x == metrics.floating_Inset)
    Swag.assert(Math.abs(dock.position.y + body.y * 0.5 - 200) <= 1)
    Swag.assert(body.x == metrics.toolDock_CellSize + 2 * metrics.toolDock_Padding)
    Swag.assert(select.position.width == metrics.toolDock_CellSize and select.icon.sizeX == metrics.toolDock_Glyph)

    // The window is the body alone: its shadow falls outside it, wider below than above, and the
    // pointer right beside the body reaches the work instead of the dock.
    let reach = host.theme.floatingShadowReach()
    Swag.assert(dock.position.width == body.x and dock.position.height == body.y)
    Swag.assert(reach.w > reach.y and dock.invalidatePadding.w == -reach.w)
    Swag.assert(host.mouseTargetAt({dock.position.horzCenter(), dock.position.bottom() + 4}) != &dock.wnd)

    // The first tool starts active; picking another moves the mark and reports it once.
    Swag.assert(dock.activeTool() == select and changes == 0)
    host.clickWnd(shape)
    Swag.assert(dock.activeTool() == shape and not select.isChecked)
    Swag.assert(changes == 1)

    dock.setActiveTool(select)
    Swag.assert(dock.activeTool() == select and changes == 1)

    // The dock follows the window, and takes no room from the work beside it.
    host.root.resize(480, 300)
    Swag.assert(Math.abs(dock.position.y + body.y * 0.5 - 150) <= 1)
}

// The mini-bar stands above the selection, centred on it, and goes below it near the top edge.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 480, 400, false)
    let metrics = host.theme.metrics

    let bar = MiniBar.create(&host.root)
    discard bar.addButton(host.theme.icon(.Copy, 16), toolTip: "Copy")
    discard bar.addButton(host.theme.icon(.Cut, 16), toolTip: "Cut")
    bar.addSeparator()
    discard bar.addTextButton("Group")
    Swag.assert(not bar.isLocallyVisible())

    let size = bar.bodySize()
    Swag.assert(size.y == metrics.miniBar_ButtonSize + 2 * metrics.miniBar_Padding)

    let selection = Math.Rectangle{200, 200, 80, 40}
    bar.showNear(selection)
    Swag.assert(bar.isLocallyVisible())
    Swag.assert(bar.position.y + size.y + metrics.miniBar_Distance == selection.y)
    Swag.assert(Math.abs(bar.position.x + size.x * 0.5 - selection.horzCenter()) <= 1)

    let high = Math.Rectangle{200, 10, 80, 40}
    bar.showNear(high)
    Swag.assert(bar.position.y == high.bottom() + metrics.miniBar_Distance)

    // Its items stand in one row, inside the padding, the hairline in the gap of its group.
    let first = unwrap bar.items[0].wnd
    Swag.assert(first.position.x == metrics.miniBar_Padding and first.position.height == metrics.miniBar_ButtonSize)
}

// The hint line sits centred, its bottom the hint inset above the bottom edge, as wide as what it writes.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 480, 400, false)
    let metrics = host.theme.metrics

    with let hint = HintLine.create(&host.root)
    {
        .setReading("880 × 550 · 100 %")
        .addHint(strings().key_Space, "capture, open, library")
    }

    host.root.applyLayout()
    Swag.assert(hint.position.bottom() == 400 - metrics.hintLine_Bottom)
    Swag.assert(hint.position.width == hint.contentWidth())
    Swag.assert(Math.abs(hint.position.horzCenter() - 240) <= 1)

    hint.clearHints()
    hint.setReading(null)
    Swag.assert(hint.contentWidth() == 0)
}

// A leading and a trailing hint line stand on the edges the parent's padding measures, at the same
// height as a centred one.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 480, 400, false)
    let metrics = host.theme.metrics
    host.root.padding = {40, 0, 60, 0}

    with let keys = HintLine.create(&host.root)
    {
        .setAlignment(.Leading)
        .addHint(strings().key_Space, "views, stages, examples")
    }

    with let reading = HintLine.create(&host.root)
    {
        .setAlignment(.Trailing)
        .setReading("Compiled in 38 ms")
    }

    host.root.applyLayout()
    Swag.assert(keys.position.x == 40 and keys.position.width == keys.contentWidth())
    Swag.assert(reading.position.right() == 480 - 60 and reading.position.width == reading.contentWidth())
    Swag.assert(keys.position.bottom() == 400 - metrics.hintLine_Bottom and reading.position.y == keys.position.y)
}

// The sheet opens at the trailing edge, below the strip of the window, and its key toggles it.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 640, 480, false)
    let metrics = host.theme.metrics

    with let sheet = InfoSheet.create(&host.root)
    {
        .setTitle("viewerchrome.swg")
        .setIdentity("swagscope / src")
        .addFact("612", "lines")
        .addReading("Encoding", "UTF-8")
    }

    Swag.assert(not sheet.isLocallyVisible())
    sheet.toggle()
    Swag.assert(sheet.isLocallyVisible())
    Swag.assert(sheet.position.right() == 640 - metrics.floating_Inset)
    Swag.assert(sheet.position.y == metrics.floating_Inset)
    Swag.assert(sheet.position.width == metrics.infoSheet_Width)

    // Its height follows what it holds, and a primary action stands at its foot.
    let before = sheet.position.height
    let action = sheet.setAction("Open", "sheet.open")
    Swag.assert(sheet.position.height == before + metrics.infoSheet_BlockGap + metrics.btnPush_Height)
    Swag.assert(action.position.bottom() == sheet.position.height - metrics.infoSheet_Padding)

    // A secondary action shares the foot with it, each on half of the line.
    let secondary = sheet.setSecondaryAction("Extract…", "sheet.extract")
    Swag.assert(secondary.position.y == action.position.y and secondary.position.width == action.position.width)
    Swag.assert(secondary.position.x > action.position.right())
    Swag.assert(Utf8.contains(sheet.text(), "Open\nExtract…"))

    sheet.toggle()
    Swag.assert(not sheet.isLocallyVisible())

    sheet.clear()
    Swag.assert(sheet.blocks.isEmpty() and sheet.action == null and sheet.secondary == null)

    // A poster stands beside the title with the facts that follow it, the action right under them.
    var poster = Image.create(40, 60, .RGB8)
    var texture = host.app.renderer.addImage(&poster)
    defer host.app.renderer.removeTexture(&texture)
    sheet.setPicture(texture)
    sheet.setPictureBeside(true)
    sheet.setTitle("Blade Runner")
    sheet.addFact("8.1", "IMDb")
    sheet.addReading("Director", "Ridley Scott")
    let open = sheet.setAction("Open", "sheet.open")
    sheet.open()
    Swag.assert(sheet.blocks[0].left > 0 and sheet.blocks[1].left == 0)
    Swag.assert(open.position.bottom() < sheet.blocks[1].top)
    sheet.clear()
    Swag.assert(not sheet.beside)
}

// A sheet arrives from its edge and fades out, reachable at once on the way in and gone at
// once on the way out; the mini-bar leaves its selection rising, and follows it once it is up.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 640, 480, false)
    host.setReducedMotion(false)
    let metrics = host.theme.metrics

    with let sheet = InfoSheet.create(&host.root)
    {
        .setTitle("viewerchrome.swg")
        .addReading("Encoding", "UTF-8")
    }

    sheet.open()
    Swag.assert(sheet.isLocallyVisible())
    Swag.assert(sheet.presentationOpacity == 0 and sheet.presentationOffset == Math.Point{metrics.motion_EdgeTravel, 0})
    host.app.animator.finishAll()
    Swag.assert(sheet.presentationOpacity == 1 and sheet.presentationOffset == Math.Point{})

    sheet.close()
    Swag.assert(not sheet.isLocallyVisible() and sheet.paintsWhenHidden)
    host.app.animator.finishAll()
    Swag.assert(not sheet.paintsWhenHidden and sheet.presentationOpacity == 1)

    let bar = MiniBar.create(&host.root)
    discard bar.addTextButton("Crop")
    bar.showNear({200, 300, 120, 80})
    Swag.assert(bar.isLocallyVisible() and bar.position.bottom() <= 300)
    Swag.assert(bar.presentationOffset == Math.Point{0, metrics.motion_AnchorTravel})
    host.app.animator.finishAll()
    bar.showNear({240, 300, 120, 80})
    Swag.assert(bar.presentationOffset == Math.Point{} and bar.presentationOpacity == 1)
}

// The inspector stands at the trailing edge with its editors in one column, and folds to a tab.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 640, 480, false)
    let metrics = host.theme.metrics

    let inspector = Inspector.create(&host.root)
    inspector.setTitle("Arrow", "1 object")
    discard inspector.addAction("Delete")
    inspector.addSection("Stroke")
    let thickness = inspector.addRow("Thickness", Slider.create(&host.root, {}))
    let style     = inspector.addWideRow(EditBox.create(&host.root, "dashed"))
    host.root.applyLayout()

    let width = metrics.inspector_Width
    Swag.assert(inspector.position.width == width)
    Swag.assert(inspector.position.right() == 640 - metrics.floating_Inset)
    Swag.assert(thickness.parent == &inspector.wnd and thickness.position.height == metrics.control_InspectorHeight)
    Swag.assert(thickness.position.x == metrics.inspector_Padding + metrics.inspector_LabelWidth + metrics.inspector_LabelGap)
    Swag.assert(thickness.position.right() == width - metrics.inspector_Padding)
    Swag.assert(style.position.x == metrics.inspector_Padding)
    Swag.assert(style.position.y == thickness.position.bottom() + metrics.inspector_RowGap)

    var folds = 0
    inspector.sigFoldChanged += func|folds = &folds|(_) { folds[] += 1 }
    inspector.toggleFolded()
    Swag.assert(inspector.folded and folds == 1)
    Swag.assert(inspector.position.width < width and not thickness.isLocallyVisible())

    host.clickWnd(inspector)
    Swag.assert(not inspector.folded and folds == 2 and thickness.isLocallyVisible())

    inspector.clear()
    Swag.assert(inspector.rows.isEmpty())
}

// An inspector carrying generated settings stands the whole height of its parent and hands them
// the column under its rows; clearing the rows keeps them.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 640, 480, false)
    let metrics = host.theme.metrics

    let inspector = Inspector.create(&host.root)
    inspector.setTitle("Text", "1 object")
    inspector.addSection("Color")
    let swatch  = inspector.addRow("Fill", Slider.create(&host.root, {}))
    let content = inspector.setContent(Wnd.create'Wnd(&host.root, {}))
    host.root.applyLayout()

    let pad = metrics.inspector_Padding
    Swag.assert(content.parent == &inspector.wnd)
    Swag.assert(inspector.position.bottom() == 480 - metrics.floating_Inset)
    Swag.assert(content.position.x == pad and content.position.width == inspector.position.width - 2 * pad)
    Swag.assert(content.position.y == swatch.position.bottom() + metrics.inspector_RowGap)
    Swag.assert(content.position.bottom() == inspector.position.height - pad)

    inspector.clear()
    host.root.applyLayout()
    Swag.assert(inspector.rows.isEmpty() and not content.isPendingDestroy)
    Swag.assert(content.position.y == pad + metrics.control_InspectorHeight + metrics.inspector_RowGap)
}

// A mini-bar is filled again for each selection: clearing it destroys what it held.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 640, 480, false)

    let bar    = MiniBar.create(&host.root)
    let button = bar.addButton(host.theme.icon(.Copy, 16), toolTip: "Copy")
    bar.addSeparator()
    discard bar.addTextButton("Group")
    let width = bar.bodySize().x

    // The bar writes no word beside a glyph, whatever the command of the button names.
    Swag.assert(button.flags.has(.IconOnly))

    bar.clear()
    Swag.assert(bar.items.isEmpty() and button.isPendingDestroy)
    Swag.assert(bar.bodySize().x < width)
}

// A section label names its group in small spaced capitals and can be renamed.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 320, 120, false)

    let label = SectionLabel.create(&host.root, "Color", {20, 20, 200, host.theme.metrics.inspector_SectionHeight})
    Swag.assert(label.text == "Color")
    label.setText("Stroke")
    Swag.assert(label.text == "Stroke")
    var image = host.render(&host.root)
    Swag.assert(image.isValid())
}

// The dock, a selection with its mini-bar and the hint line, in Encre and in Papier.
#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
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
}

// The information sheet, open over the work, in Encre and in Papier.
#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
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
}

// The inspector, unfolded and folded, in Encre and in Papier.
#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
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
}

// A floating panel holds what the application puts in it inside its padding; floating, it casts
// its shadow outside its body, and docked beside the work it casts none.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 480, 400, false)
    let reach = host.theme.floatingShadowReach()

    let panel = FloatingPanel.create(&host.root, {40, 40, 200, 48})
    with let field = EditBox.create(panel, "", {})
    {
        .dockStyle = .Center
    }

    panel.applyLayout()
    let pad = host.theme.metrics.miniBar_Padding
    Swag.assert(field.position.x == pad and field.position.width == 200 - 2 * pad)
    Swag.assert(panel.radius() == host.theme.metrics.corner_Floating)
    Swag.assert(panel.invalidatePadding.w == -reach.w)
    Swag.assert(host.mouseTargetAt({panel.position.horzCenter(), panel.position.bottom() + 4}) != &panel.wnd)

    panel.setShadow(false)
    Swag.assert(panel.invalidatePadding.w == 0 and not panel.wndFlags.has(.BeforeChildrenPaint))
}

// A hint without a key is words alone: what the tool in hand does takes no keycap.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 640, 200, false)

    let words = HintLine.create(&host.root)
    words.addHint("", "Drag to draw an arrow")
    let keyed = HintLine.create(&host.root)
    keyed.addHint("Space", "Drag to draw an arrow")

    let metrics = host.theme.metrics
    Swag.assert(keyed.contentWidth() - words.contentWidth() >= metrics.hintLine_KeyGap)
    var image = host.render(&host.root)
    Swag.assert(image.isValid())
}

// A toast stands centred above the foot of its parent, stays while the pointer is over it, leaves
// on its timer, and answers its action once.
#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        floatingHost(&host, 900, 400, light)
        let metrics = host.theme.metrics

        let toast = Toast.create(&host.root)
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
}

