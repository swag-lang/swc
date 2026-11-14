#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

var InfoSheetTestLinkId: String
var ToolDockDynamicId:  String

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
    Swag.require(dock.position.x == metrics.floating_Inset)
    Swag.require(Math.abs(dock.position.y + body.y * 0.5 - 200) <= 1)
    Swag.require(body.x == metrics.toolDock_CellSize + 2 * metrics.toolDock_Padding)
    Swag.require(select.position.width == metrics.toolDock_CellSize and select.icon.sizeX == metrics.toolDock_Glyph)

    // The window is the body alone: its shadow falls outside it, wider below than above, and the
    // pointer right beside the body reaches the work instead of the dock.
    let reach = host.theme.floatingShadowReach()
    Swag.require(dock.position.width == body.x and dock.position.height == body.y)
    Swag.require(reach.w > reach.y and dock.invalidatePadding.w == -reach.w)
    Swag.require(host.mouseTargetAt({dock.position.horzCenter(), dock.position.bottom() + 4}) != &dock.wnd)

    // The first tool starts active; picking another moves the mark and reports it once.
    Swag.require(dock.activeTool() == select and changes == 0)
    host.clickWnd(shape)
    Swag.require(dock.activeTool() == shape and not select.isChecked)
    Swag.require(changes == 1)

    dock.setActiveTool(select)
    Swag.require(dock.activeTool() == select and changes == 1)

    // The dock follows the window, and takes no room from the work beside it.
    host.root.resize(480, 300)
    Swag.require(Math.abs(dock.position.y + body.y * 0.5 - 150) <= 1)
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
    Swag.require(not bar.isLocallyVisible())

    let size = bar.bodySize()
    Swag.require(size.y == metrics.miniBar_ButtonSize + 2 * metrics.miniBar_Padding)

    let selection = Math.Rectangle{200, 200, 80, 40}
    bar.showNear(selection)
    Swag.require(bar.isLocallyVisible())
    Swag.require(bar.position.y + size.y + metrics.miniBar_Distance == selection.y)
    Swag.require(Math.abs(bar.position.x + size.x * 0.5 - selection.horzCenter()) <= 1)

    let high = Math.Rectangle{200, 10, 80, 40}
    bar.showNear(high)
    Swag.require(bar.position.y == high.bottom() + metrics.miniBar_Distance)

    // With no room above or below, it stands beside the selection, level with its foot.
    let tall = Math.Rectangle{20, 10, 200, 380}
    bar.showNear(tall, below: true)
    Swag.require(bar.position.x == tall.right() + metrics.miniBar_Distance)
    Swag.require(bar.position.bottom() == tall.bottom() - metrics.miniBar_Distance)

    // It keeps within the room it is given, clear of what floats beside the work.
    bar.showNear(selection, room: Math.Rectangle{250, 0, 230, 400})
    Swag.require(bar.position.x >= 250 + metrics.miniBar_Distance)

    // Its items stand in one row, inside the padding, the hairline in the gap of its group.
    let first = unwrap bar.items[0].wnd
    Swag.require(first.position.x == metrics.miniBar_Padding and first.position.height == metrics.miniBar_ButtonSize)
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
    Swag.require(hint.position.bottom() == 400 - metrics.hintLine_Bottom)
    Swag.require(hint.position.width == hint.contentWidth())
    Swag.require(Math.abs(hint.position.horzCenter() - 240) <= 1)

    hint.clearHints()
    hint.setReading(null)
    Swag.require(hint.contentWidth() == 0)
}

// A hint line with less room than it writes leaves its last hints out whole, rather than cutting
// a word at its edge; the reading always stands.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 480, 400, false)

    with let hint = HintLine.create(&host.root)
    {
        .setReading("880 × 550")
        .addHint(strings().key_Space, "capture, open, library")
        .addHint(strings().key_Escape, "cancel")
    }

    host.root.applyLayout()
    let whole = hint.position.width
    Swag.require(whole == hint.contentWidth())

    // Room for the reading and the first hint only: the line is as wide as those two.
    hint.margin = {0, 0, 480 - (whole - 20), 0}
    host.root.applyLayout()
    Swag.require(hint.position.width < whole - 20)
    hint.clearHints()
    hint.addHint(strings().key_Space, "capture, open, library")
    let first = hint.contentWidth()
    host.root.applyLayout()
    Swag.require(hint.position.width == first)
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
    Swag.require(keys.position.x == 40 and keys.position.width == keys.contentWidth())
    Swag.require(reading.position.right() == 480 - 60 and reading.position.width == reading.contentWidth())
    Swag.require(keys.position.bottom() == 400 - metrics.hintLine_Bottom and reading.position.y == keys.position.y)
}

// An information-sheet link keeps its command identifier after the source string changes.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 640, 480, false)

    let expected = "InfoSheet.Dynamic.Link.Identifier"
    InfoSheetTestLinkId = Core.String.from(expected)
    let sheet = InfoSheet.create(&host.root)
    sheet.addLink("Open", InfoSheetTestLinkId.toString())
    sheet.addFootnote("Footnote", "Open", InfoSheetTestLinkId.toString())
    sheet.addFootnote("No command", "")
    InfoSheetTestLinkId[0] = 'X'

    Swag.require(sheet.blocks[0].commandId == expected and sheet.blocks[0].id == expected)
    Swag.require(sheet.blocks[1].commandId == expected and sheet.blocks[1].id == expected)
    Swag.require(sheet.blocks[2].commandId.isEmpty() and sheet.blocks[2].id == null)
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

    Swag.require(not sheet.isLocallyVisible())
    sheet.toggle()
    Swag.require(sheet.isLocallyVisible())
    Swag.require(sheet.position.right() == 640 - metrics.floating_Inset)
    Swag.require(sheet.position.y == metrics.floating_Inset)
    Swag.require(sheet.position.width == metrics.infoSheet_Width)

    // Its height follows what it holds, and a primary action follows its head, above the readings.
    let before = sheet.position.height
    let action = sheet.setAction("Open", "sheet.open")
    Swag.require(sheet.position.height == before + metrics.infoSheet_BlockGap + metrics.btnPush_Height)
    Swag.require(action.position.bottom() < sheet.blocks[1].top)
    Swag.require(sheet.blocks[0].top + sheet.blocks[0].height < action.position.y)

    // A secondary action shares the foot with it, each on half of the line.
    let secondary = sheet.setSecondaryAction("Extract…", "sheet.extract")
    Swag.require(secondary.position.y == action.position.y and secondary.position.width == action.position.width)
    Swag.require(secondary.position.x > action.position.right())
    Swag.require(Utf8.contains(sheet.text(), "Open\nExtract…"))

    sheet.toggle()
    Swag.require(not sheet.isLocallyVisible())

    sheet.clear()
    Swag.require(sheet.blocks.isEmpty() and sheet.action == null and sheet.secondary == null)

    // A poster stands beside the title with the facts that follow it, the action right under them.
    var poster  = Image.create(40, 60, .RGB8)
    var texture = host.app.renderer.addImage(&poster)
    defer host.app.renderer.removeTexture(&texture)
    sheet.setPicture(texture)
    sheet.setPictureBeside(true)
    sheet.setTitle("Blade Runner")
    sheet.addFact("8.1", "IMDb")
    sheet.addReading("Director", "Ridley Scott")
    let open = sheet.setAction("Open", "sheet.open")
    sheet.open()
    Swag.require(sheet.blocks[0].left > 0 and sheet.blocks[1].left == 0)
    Swag.require(open.position.bottom() < sheet.blocks[1].top)
    sheet.clear()
    Swag.require(not sheet.beside)
}

// The names of the pages stand as tabs on the line of the close button, and a click on one shows
// its page without carrying the media action onto technical readings.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 640, 480, false)
    let sheet = InfoSheet.create(&host.root)
    sheet.setTitle("Film")
    sheet.beginPage("Media")
    sheet.addFact("8.1", "IMDb")
    discard sheet.setAction("Open", "sheet.open")
    sheet.beginPage("Technical")
    sheet.addReading("Frame rate", "24 fps")
    sheet.open()
    Swag.require(sheet.tabRects.count == 2 and sheet.pageIndex == 0)
    Swag.require(sheet.tabRects[0].y == sheet.closeButton.position.y and
                 sheet.tabRects[0].height == sheet.closeButton.position.height)
    Swag.require(sheet.tabRects[0].x == host.theme.metrics.infoSheet_Padding and
                 sheet.tabRects[1].x > sheet.tabRects[0].right())
    let tabFont = host.theme.createDefaultFont(host.theme.metrics.defaultFontSize, .SemiBold)
    for rect, index in sheet.tabRects do
        Swag.require(rect.width >= Painter.measureStringSnapped(sheet.pages[index], tabFont, deviceScale: sheet.deviceScale()))
    Swag.require(sheet.closeButton.position.y < host.theme.metrics.infoSheet_Padding)
    Swag.require(Utf8.contains(sheet.text(), "8.1 IMDb") and not Utf8.contains(sheet.text(), "24 fps"))
    func clickTab(host: *Testing.HeadlessHost, sheet: *InfoSheet, index: u64)
    {
        let origin = sheet.surfaceRect()
        var pt     = Math.Point{origin.x + sheet.tabRects[index].horzCenter(), origin.y + sheet.tabRects[index].vertCenter()}
        sheet.surface!.surfaceToScreen(&pt)
        host.click(pt)
    }

    clickTab(&host, sheet, 1)
    Swag.require(sheet.pageIndex == 1 and not sheet.action!.isLocallyVisible())
    Swag.require(Utf8.contains(sheet.text(), "24 fps") and not Utf8.contains(sheet.text(), "8.1 IMDb"))
    clickTab(&host, sheet, 0)
    Swag.require(sheet.pageIndex == 0 and sheet.action!.isLocallyVisible())
}

// Page names keep every letter at a fractional display scale, including a longer translation.
#test
{
    var host: Testing.HeadlessHost
    host.setup(560, 400, 1.5)
    let sheet = InfoSheet.create(&host.root)
    sheet.beginPage("Media")
    sheet.beginPage("Technical Details")
    sheet.open()

    let font = host.theme.createDefaultFont(host.theme.metrics.defaultFontSize, .SemiBold)
    for rect, index in sheet.tabRects
    {
        Swag.require(rect.width >= Painter.measureStringSnapped(sheet.pages[index], font, deviceScale: sheet.deviceScale()))
        Swag.require(Painter.elideString(sheet.pages[index], font, rect.width + 1, sheet.deviceScale()) == sheet.pages[index])
    }
    Swag.require(sheet.tabRects[1].right() < sheet.closeButton.position.x)
}

// The figures stand on one line under the title wherever they were added, a long title runs on a
// second line that keeps its extension, and a long value wraps under its label.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 640, 480, false)
    let metrics = host.theme.metrics
    with let sheet = InfoSheet.create(&host.root)
    {
        .setTitle("ffmpeg-h264-two-aac-with-a-very-long-descriptive-name-for-the-test.mkv")
        .setIdentity("MKV · datas")
        .addFact("0:01")
        .addSection("Video")
        .addReading("Codec", "H.264 / AVC", mono: false)
        .addFact("64 × 48", "px")
        .addReading("Cast", "Harrison Ford, Rutger Hauer, Sean Young, Edward James Olmos, Daryl Hannah", mono: false)
        .addTrack("1", "Primary", "AAC-LC · 44.1 kHz · stereo")
        .addNote("The Exif header has no TIFF byte order.")
        .addFootnote("Online lookups are off.", "Turn On", "sheet.online")
        .open()
    }

    Swag.require(sheet.titleLines.count == 2 and Utf8.endsWith(sheet.titleLines[1], "test.mkv"))
    let duration = sheet.blocks[0]
    let size     = sheet.blocks[3]
    Swag.require(duration.top == size.top and size.left > duration.left + duration.width)
    Swag.require(duration.top + duration.height < sheet.blocks[1].top)
    let people = sheet.blocks[4]
    Swag.require(people.wrapped and people.height > metrics.infoSheet_LineHeight)
    Swag.require(people.valueLeft == metrics.infoSheet_LabelWidth)
    Swag.require(Utf8.contains(sheet.text(), "1 Primary\nAAC-LC · 44.1 kHz · stereo"))
    Swag.require(Utf8.contains(sheet.text(), "Online lookups are off. Turn On"))
    let foot = sheet.blocks[7]
    Swag.require(sheet.linkAt({metrics.infoSheet_Padding + foot.valueLeft + 2, foot.top + foot.valueTop + 4}) == 7)
}

// Long information remains reachable when the sheet fills the available height.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 640, 400, false)
    let sheet = InfoSheet.create(&host.root)
    sheet.setTitle("Film")
    for index in 40 do
        sheet.addReading("Track", Format.toString("%", index))
    sheet.open()
    Swag.require(sheet.contentHeight > sheet.position.height)
    host.mouseWheel({400, 200}, -1)
    Swag.require(sheet.scrollOffset > 0)
    host.mouseWheel({400, 200}, -100)
    Swag.require(sheet.scrollOffset == sheet.contentHeight - sheet.position.height)
    sheet.clear()
    Swag.require(sheet.scrollOffset == 0)
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
    Swag.require(sheet.isLocallyVisible())
    Swag.require(sheet.presentationOpacity == 0 and sheet.presentationOffset == Math.Point{metrics.motion_EdgeTravel, 0})
    host.app.animator.finishAll()
    Swag.require(sheet.presentationOpacity == 1 and sheet.presentationOffset == Math.Point{})

    sheet.close()
    Swag.require(not sheet.isLocallyVisible() and sheet.paintsWhenHidden)
    host.app.animator.finishAll()
    Swag.require(not sheet.paintsWhenHidden and sheet.presentationOpacity == 1)

    let bar = MiniBar.create(&host.root)
    discard bar.addTextButton("Crop")
    bar.showNear({200, 300, 120, 80})
    Swag.require(bar.isLocallyVisible() and bar.position.bottom() <= 300)
    Swag.require(bar.presentationOffset == Math.Point{0, metrics.motion_AnchorTravel})
    host.app.animator.finishAll()
    bar.showNear({240, 300, 120, 80})
    Swag.require(bar.presentationOffset == Math.Point{} and bar.presentationOpacity == 1)
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
    Swag.require(inspector.position.width == width)
    Swag.require(inspector.position.right() == 640 - metrics.floating_Inset)
    Swag.require(thickness.parent == &inspector.wnd and thickness.position.height == metrics.control_InspectorHeight)
    Swag.require(thickness.position.x == metrics.inspector_Padding + metrics.inspector_LabelWidth + metrics.inspector_LabelGap)
    Swag.require(thickness.position.right() == width - metrics.inspector_Padding)
    Swag.require(style.position.x == metrics.inspector_Padding)
    Swag.require(style.position.y == thickness.position.bottom() + metrics.inspector_RowGap)

    var folds = 0
    inspector.sigFoldChanged += func|folds = &folds|(_) { folds[] += 1 }
    inspector.toggleFolded()
    Swag.require(inspector.folded and folds == 1)
    Swag.require(inspector.position.width < width and not thickness.isLocallyVisible())

    host.clickWnd(inspector)
    Swag.require(not inspector.folded and folds == 2 and thickness.isLocallyVisible())

    inspector.clear()
    Swag.require(inspector.rows.isEmpty())
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

    let gutter = metrics.scrollBar_HitSize + metrics.scrollBar_EdgeInset
    let pad = Math.max(metrics.inspector_Padding, gutter)
    Swag.require(content.parent == &inspector.wnd)
    Swag.require(inspector.position.bottom() == 480 - metrics.floating_Inset)
    Swag.require(content.position.x == pad and content.position.width == inspector.position.width - 2 * pad + gutter)
    Swag.require(content.position.y == swatch.position.bottom() + metrics.inspector_RowGap)
    Swag.require(content.position.bottom() == inspector.position.height - pad)

    inspector.clear()
    host.root.applyLayout()
    Swag.require(inspector.rows.isEmpty() and not content.isPendingDestroy)
    Swag.require(content.position.y == pad + metrics.control_InspectorHeight + metrics.inspector_RowGap)
}

// A small negative top offset balances the top and bottom insets without crossing the parent's
// floating inset when the strip is hidden.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    host.surface.flags      = .StandardWindow
    host.surfaceWnd.padding = {1, 1, 1, 1}
    host.surfaceWnd.create(&host.root, null)
    host.surfaceWnd.sendResizeEvent()

    let metrics   = host.theme.metrics
    let inspector = Inspector.create(&host.root)
    inspector.topOffset = -8
    host.root.applyLayout()

    Swag.require(host.root.stripInset() > metrics.floating_Inset)
    Swag.require(inspector.position.y == host.root.stripInset() - 8)
    host.surface.flags = .None
    host.surfaceWnd.sendResizeEvent()
    host.root.applyLayout()
    Swag.require(inspector.position.y == metrics.floating_Inset)
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
    Swag.require(button.flags.has(.IconOnly))

    bar.clear()
    Swag.require(bar.items.isEmpty() and button.isPendingDestroy)
    Swag.require(bar.bodySize().x < width)
}

// A section label names its group in small spaced capitals and can be renamed.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 320, 120, false)

    let label = SectionLabel.create(&host.root, "Color", {20, 20, 200, host.theme.metrics.inspector_SectionHeight})
    Swag.require(label.text == "Color")
    label.setText("Stroke")
    Swag.require(label.text == "Stroke")
    var image = host.render(&host.root)
    Swag.require(image.isValid())
}

// A floating panel holds what the application puts in it inside its padding; floating, it casts
// its shadow outside its body, and docked beside the work it casts none.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 480, 400, false)
    let reach = host.theme.floatingShadowReach()

    let panel      = FloatingPanel.create(&host.root, {40, 40, 200, 48})
    with let field = EditBox.create(panel, "", {})
    {
        .dockStyle = .Center
    }

    panel.applyLayout()
    let pad = host.theme.metrics.miniBar_Padding
    Swag.require(field.position.x == pad and field.position.width == 200 - 2 * pad)
    Swag.require(panel.radius() == host.theme.metrics.corner_Floating)
    Swag.require(panel.invalidatePadding.w == -reach.w)
    Swag.require(host.mouseTargetAt({panel.position.horzCenter(), panel.position.bottom() + 4}) != &panel.wnd)

    panel.setShadow(false)
    Swag.require(panel.invalidatePadding.w == 0 and not panel.wndFlags.has(.BeforeChildrenPaint))
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
    Swag.require(keyed.contentWidth() - words.contentWidth() >= metrics.hintLine_KeyGap)
    var image = host.render(&host.root)
    Swag.require(image.isValid())
}

// A dock cell can stand for a group of tools: it shows the one chosen last, and a tool of the
// group made the active one by its command comes into the cell.
#test
{
    var host: Testing.HeadlessHost
    floatingHost(&host, 480, 400, false)

    let dock = ToolDock.create(&host.root)
    discard dock.addTool(host.theme.icon(.Edit, 18), "dock.select", "Select")
    let shape = dock.addTool(host.theme.icon(.Plus, 18), "dock.rectangle", "Rectangle")
    ToolDockDynamicId = Core.String.from("dock.ellipse")
    dock.addToGroup(shape, host.theme.icon(.Link, 18), ToolDockDynamicId.toString(), "Ellipse")
    ToolDockDynamicId[0] = 'X'
    host.root.applyLayout()
    Swag.require(dock.tools.count == 2)

    host.recordCommands()
    Swag.require(dock.selectTool("dock.ellipse"))
    Swag.require(shape.id == "dock.ellipse" and shape.toolTip == "Ellipse" and shape.isChecked)
    dock.chooseInGroup(shape, "dock.ellipse")
    host.pump()
    Swag.require(host.lastCommand == "dock.ellipse")
    Swag.require(dock.selectTool("dock.rectangle") and shape.id == "dock.rectangle")
    Swag.require(not dock.selectTool("dock.unknown"))
}
