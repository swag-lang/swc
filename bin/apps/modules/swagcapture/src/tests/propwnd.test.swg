#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, File

// Build the right-side properties panel the way the app does (quick styles pane on
// top, properties pane below) and return it, laid out.
func testSetupPropWnd(f: *HeadlessFixture)->*PropWnd
{
    f.gui.surfaceWnd.view = f.main

    f.main.quickStyleBar = SplitterCtrl.create(f.main, {600, 0, 300, 650}, vertical: true)

    let splitter = f.main.quickStyleBar
    f.main.quickWnd = QuickWnd.create(splitter, f.main)
    f.main.propWnd  = PropWnd.create(splitter, f.main)
    discard f.main.quickStyleBar.addPane(f.main.quickWnd)
    discard f.main.quickStyleBar.addPane(f.main.propWnd)
    f.main.quickStyleBar.setPaneSize(0, 300)
    f.main.quickWnd.setDefault()
    Swag.assert(!f.main.quickStyleBar.flags.has(.HideDividers))
    return f.main.propWnd
}

func testFindItem(prop: *PropWnd, name: string)->#null *PropertiesItem
{
    for item in prop.grid.items
    {
        let it = item!
        if it.typeValue.name == name do
            return it
    }

    return null
}

func testItemIndex(prop: *PropWnd, name: string)->u64
{
    for item, idx in prop.grid.items
    {
        if item!.typeValue.name == name do
            return idx
    }

    Swag.assert(false)
    return 0
}

func testHasStyleTip(prop: *PropWnd, tip: string)->bool
{
    for row in prop.topLayout.children
    {
        for child in row.children
        {
            if child.toolTip == tip do
                return true
        }
    }

    return false
}

func testFindStyleButton(prop: *PropWnd, tip: string)->#null *IconButton
{
    for row in prop.topLayout.children
    {
        for child in row.children
        {
            if child.toolTip == tip do
                return cast(*IconButton) child
        }
    }

    return null
}

// Replacing the editor document from history retargets the panel after the old capture
// is released. With no form selected, the controls edit the live tool model.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let prop = testSetupPropWnd(&f)

    let oldShape = testAddShape(f.capture, 10, 10, 40, 40)
    oldShape.borderSize = 7
    f.capture.selection.add(0)
    f.capture.selectionHasChanged()

    let oldPath = testTempCapturePath()
    defer discard catch File.delete(oldPath)
    f.capture.file    = oldPath
    f.capture.changed = true
    expect f.capture.save()

    let next = Memory.new'Capture()
    next.width, next.widthOrg   = 120
    next.height, next.heightOrg = 80
    next.backImg                = Gui.Testing.indexedImage(120, 80)
    discard testAddShape(next, 20, 20, 40, 30)
    let nextPath = testTempCapturePath()
    defer discard catch File.delete(nextPath)
    next.file    = nextPath
    next.changed = true
    expect next.save()
    Memory.delete(next)

    f.main.recentWnd = RecentWnd.create(f.main, f.main)
    f.main.recentWnd.addRecent(nextPath, Gui.Testing.indexedImage(32, 20), front: false)
    f.main.recentWnd.recentView.select(0)

    let current = f.main.editWnd.getCapture()!
    Swag.assert(current.file == nextPath)
    Swag.assert(current.selection.isEmpty())

    let border = testFindItem(prop, #nameof(BaseForm.borderSize))!
    border.sliderBox.setValue(12)
    Swag.assert(Math.isEqualEpsilon(f.main.mdlFormShape.borderSize, 12, 0.001))
}

// Lines, arrows and freehand paths expose the same adjustable outer contour. It is hidden for
// pixel selections, whose rendering is prescribed by the selection tool rather than its form.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let prop = testSetupPropWnd(&f)

    let line = testAddLine(f.capture, 10, 10, 100, 10)
    f.capture.selection.add(0)
    prop.selectionHasChanged()
    f.gui.pump()

    let outline = testFindItem(prop, #nameof(FormLine.outlineSize))!
    Swag.assert(Swag.isSet(outline.sliderBox))
    Swag.assert(outline.sliderBox.label.name == "Outline")
    Swag.assert(outline.sliderBox.slider.minimum() == MinOutlineSize)
    Swag.assert(outline.sliderBox.slider.maximum() == MaxOutlineSize)
    outline.sliderBox.setValue(4)
    Swag.assert(Math.isEqualEpsilon(line.outlineSize, 4, 0.001))
    Swag.assert(testHasStyleTip(prop, appStrings().ui_PropColor))
    Swag.assert(testHasStyleTip(prop, appStrings().ui_PropOutline))

    f.capture.selection.clear()
    let arrow = testAddArrow(f.capture, 10, 30, 100, 30)
    f.capture.selection.add(1)
    prop.selectionHasChanged()
    f.gui.pump()
    testFindItem(prop, #nameof(FormLine.outlineSize))!.sliderBox.setValue(5)
    Swag.assert(Math.isEqualEpsilon(arrow.outlineSize, 5, 0.001))

    f.capture.selection.clear()
    var points: Array'Math.Vector2
    points.add({10, 50})
    points.add({100, 50})
    let draw = testAddDraw(f.capture, points.toSlice())
    f.capture.selection.add(2)
    prop.selectionHasChanged()
    f.gui.pump()
    testFindItem(prop, #nameof(FormDraw.outlineSize))!.sliderBox.setValue(6)
    Swag.assert(Math.isEqualEpsilon(draw.outlineSize, 6, 0.001))

    draw.subKind = .PixSel
    prop.selectionHasChanged()
    f.gui.pump()
    Swag.assert(!testFindItem(prop, #nameof(FormDraw.outlineSize))!.line.isVisible())
}

// FormArrow embeds FormLine, so the start/end samples and their list must read and write the
// embedded caps rather than treating the arrow as an unrelated form type.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let prop = testSetupPropWnd(&f)

    let arrow = testAddArrow(f.capture, 10, 30, 100, 30)
    arrow.beginCap = .SquareAnchor
    f.capture.selection.add(0)
    prop.selectionHasChanged()
    f.gui.pump()

    let startButton = testFindStyleButton(prop, appStrings().ui_PropStart)!
    prop.createPopupCapStyle(startButton, begin: true)
    let popup = prop.stylePopup!
    Swag.assert(popup.selectedIndex == cast(u32) LineCapStyle.SquareAnchor)
    Swag.assert(popup.items.count == LineCapStyle.count)
    Swag.assert(popup.markSelectionOnly)
    Swag.assert(popup.items[popup.selectedIndex]!.contentPainter != null)

    let view  = popup.scrollWnd.view!
    let local = Math.Point{12, cast(f32) LineCapStyle.ArrowAnchor * popup.itemHeight + popup.itemHeight * 0.5}
    var pt    = view.localToSurface(local)
    view.surface!.surfaceToScreen(&pt)
    f.gui.click(pt)
    f.gui.pump()
    Swag.assert(prop.stylePopup == null)
    Swag.assert(arrow.beginCap == .ArrowAnchor)
}

// The dash chooser marks its selection the way the line-end chooser does.
//
// Its entries are samples of the stroke itself, so a filled row behind one hid the sample the row
// is there to show; the mark sits in a lane reserved beside them instead.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let prop = testSetupPropWnd(&f)

    let line = testAddLine(f.capture, 10, 30, 100, 30)
    line.dashStyle = .DashDot
    f.capture.selection.add(0)
    prop.selectionHasChanged()
    f.gui.pump()

    let dashButton = testFindStyleButton(prop, appStrings().ui_PropDash)!
    prop.createPopupDashStyle(dashButton)
    let popup = prop.stylePopup!
    Swag.assert(popup.markSelectionOnly)

    // Every style but `Pattern`, which takes its lengths from the pen and has nothing to show.
    Swag.assert(popup.items.count == DashStyle.count - 1)
    Swag.assert(popup.items[popup.selectedIndex]!.contentPainter != null)
    Swag.assert(enumFromUserData'DashStyle(popup.items[popup.selectedIndex]!.userData0) == .DashDot)

    // `Pattern` is not listed, so the rows are None, Dot, Dash, DashDot: the second one is Dot.
    let view  = popup.scrollWnd.view!
    let local = Math.Point{12, popup.itemHeight * 1.5}
    var pt    = view.localToSurface(local)
    view.surface!.surfaceToScreen(&pt)
    f.gui.click(pt)
    f.gui.pump()
    Swag.assert(prop.stylePopup == null)
    Swag.assert(line.dashStyle == .Dot)
}

// A selected text form generates the full grid: retargeted outline slider, joins combo
// without `JoinStyle.None`, and the compact x/y and w/h rows
// appended at the very end. Every row spans the panel width.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let prop = testSetupPropWnd(&f)

    let tf = testAddText(f.capture, 10, 20, 100, 50)
    f.capture.selection.add(0)
    prop.selectionHasChanged()
    f.gui.pump()

    // The border-size row is generated by the grid and retargeted for a text form
    let border = testFindItem(prop, #nameof(BaseForm.borderSize))!
    Swag.assert(Swag.isSet(border.sliderBox))
    Swag.assert(border.sliderBox.label.name == "Outline")
    Swag.assert(border.sliderBox.slider.minimum() == MinTextBorderSize)
    Swag.assert(border.sliderBox.slider.maximum() == MaxTextBorderSize)
    let labelWidth = Math.ceil(Painter.measureString(border.sliderBox.label.name.raw.toString(), border.sliderBox.label.font().regular!).width)
    Swag.assert(border.sliderBox.labelWidth >= labelWidth)

    // The joins row is a generated combo omitting JoinStyle.None: Round selects index 1
    let joins = testFindItem(prop, #nameof(BaseForm.joinStyle))!
    Swag.assert(Swag.isSet(joins.comboBox))
    Swag.assert(joins.comboBox.items.count == 4)
    Swag.assert(tf.joinStyle == .Round)
    Swag.assert(joins.comboBox.selectedIndex == 1)

    // What the form says comes before how it is set: the box the words are typed in stands
    // above the face they are set in.
    Swag.assert(testItemIndex(prop, #nameof(FormText.text)) < testItemIndex(prop, #nameof(FormText.fontName)))
    Swag.assert(testItemIndex(prop, #nameof(FormText.alignVert)) < testItemIndex(prop, #nameof(FormText.fontName)))
    Swag.assert(testItemIndex(prop, #nameof(FormText.fontName)) < testItemIndex(prop, #nameof(FormText.fontSize)))

    // Icon-only bars explain themselves through their glyphs and selected state, so they do
    // not reserve a heading line repeating what the controls already say.
    Swag.assert(!Swag.isSet(testFindItem(prop, #nameof(FormText.fontStyle))!.label))
    Swag.assert(!Swag.isSet(testFindItem(prop, #nameof(FormText.alignHorz))!.label))
    Swag.assert(!Swag.isSet(testFindItem(prop, #nameof(FormText.alignVert))!.label))

    // Most specific first: the text form's own fields come before the shared BaseForm
    // block, even though the language declares 'using base' first
    Swag.assert(testItemIndex(prop, #nameof(FormText.fontName)) < testItemIndex(prop, #nameof(BaseForm.borderSize)))
    Swag.assert(testItemIndex(prop, #nameof(FormText.fontSize)) < testItemIndex(prop, #nameof(BaseForm.borderSize)))
    Swag.assert(testFindItem(prop, "Effects") == null)

    // The x/y and w/h rows close the grid. They carry no category separator of their own: each
    // one is named for what it holds, and a heading above them would only repeat it.
    let n = prop.grid.items.count
    Swag.assert(n >= 3)
    Swag.assert(prop.grid.items[n - 1]!.typeValue.name == appStrings().ui_PropSize)
    Swag.assert(prop.grid.items[n - 2]!.typeValue.name == appStrings().ui_PropPosition)

    // Rows span the whole panel width (they used to be clamped to editorWidth)
    Swag.assert(border.line.position.width > 250)
    Swag.assert(border.line.position.width >= prop.grid.position.width - 24)

    // The placeholder section row consumes no vertical room: the first real row
    // starts right at the top of the grid (only its own margin above)
    let sectionIt = prop.grid.items[0]!
    Swag.assert(sectionIt.flags.has(.Section))
    Swag.assert(sectionIt.line.position.height == 0)
    Swag.assert(sectionIt.line.margin.y == 0 and sectionIt.line.margin.w == 0)
}

// Clicking inside the grid must never yank the scroll back to the top: neither on a
// row, nor on its editors, nor in the dead zone between two rows (a missed hit used
// to fall back to selecting — and revealing — the first row).
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let prop = testSetupPropWnd(&f)

    discard testAddText(f.capture, 10, 20, 100, 50)
    f.capture.selection.add(0)
    prop.selectionHasChanged()
    f.gui.pump()

    // Scroll all the way down (content is taller than the prop pane)
    prop.grid.scrollWnd.setScrollPos(0, 10000)
    let sc = prop.grid.scrollWnd.scrollPosition()
    Swag.assert(sc.y > 0)

    let posItemX = testFindItem(prop, appStrings().ui_PropPosition)!
    let stackX   = posItemX.line.children[0]
    f.gui.clickWnd(((cast(*EditCtrl) stackX.children[0]).edit)!)
    f.gui.pump()
    Swag.assert(prop.grid.scrollWnd.scrollPosition().y == sc.y)

    // Focusing an editor may rebuild property-row widgets. Resolve them again after
    // every pump instead of retaining pointers into the previous window tree.
    let posItemY = testFindItem(prop, appStrings().ui_PropPosition)!
    let stackY   = posItemY.line.children[0]
    let editY    = ((cast(*EditCtrl) stackY.children[1]).edit)!
    f.gui.clickWnd(editY)
    f.gui.pump()
    Swag.assert(prop.grid.scrollWnd.scrollPosition().y == sc.y)

    let posItemLine = testFindItem(prop, appStrings().ui_PropPosition)!
    f.gui.clickWnd(posItemLine.line!)
    f.gui.pump()
    Swag.assert(prop.grid.scrollWnd.scrollPosition().y == sc.y)

    // Dead zone just above the row (inside the separator margin)
    let posItemDead = testFindItem(prop, appStrings().ui_PropPosition)!
    var pt          = posItemDead.line.surfaceRect().center()
    pt.y = posItemDead.line.surfaceRect().y - 8
    let lineSrf = posItemDead.line.surface!
    lineSrf.surfaceToScreen(&pt)
    f.gui.click(pt)
    f.gui.pump()
    Swag.assert(prop.grid.scrollWnd.scrollPosition().y == sc.y)
}

// The x/y and w/h rows are keyboard-navigable: Down from the position row selects the
// size row (a non-navigable selection used to snap back to the first row of the grid).
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let prop = testSetupPropWnd(&f)

    discard testAddText(f.capture, 10, 20, 100, 50)
    f.capture.selection.add(0)
    prop.selectionHasChanged()
    f.gui.pump()

    let posItem  = testFindItem(prop, appStrings().ui_PropPosition)!
    let sizeItem = testFindItem(prop, appStrings().ui_PropSize)!

    // Bring the trailing rows into view before clicking them
    prop.grid.scrollWnd.setScrollPos(0, 10000)
    f.gui.pump()

    f.gui.clickWnd(posItem.line!)
    f.gui.pump()
    Swag.assert(prop.grid.selItem == posItem)

    f.gui.keyPress(.Down)
    f.gui.pump()
    Swag.assert(prop.grid.selItem == sizeItem)

    f.gui.keyPress(.Up)
    f.gui.pump()
    Swag.assert(prop.grid.selItem == posItem)
}

// A selected step form hides the whole border/joins block and gets no position/size rows.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let prop = testSetupPropWnd(&f)

    discard testAddStep(f.capture, 10, 20, 100, 50)
    f.capture.selection.add(0)
    prop.selectionHasChanged()
    f.gui.pump()

    let border = testFindItem(prop, #nameof(BaseForm.borderSize))
    Swag.assert(border != null and !border.line.isVisible())
    let joins = testFindItem(prop, #nameof(BaseForm.joinStyle))
    Swag.assert(joins != null and !joins.line.isVisible())
    Swag.assert(testFindItem(prop, "Effects") == null)

    Swag.assert(testFindItem(prop, appStrings().ui_PropPosition) == null)
    Swag.assert(testFindItem(prop, appStrings().ui_PropSize) == null)
}

// A pixel-selection shape hides the whole style content, separators included (no
// visible row is left in their groups).
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let prop = testSetupPropWnd(&f)

    discard testAddShape(f.capture, 10, 20, 100, 50, subKind: .PixSel)
    f.capture.selection.add(0)
    prop.selectionHasChanged()
    f.gui.pump()

    let border = testFindItem(prop, #nameof(BaseForm.borderSize))
    Swag.assert(border != null and !border.line.isVisible())
    let round = testFindItem(prop, #nameof(FormShape.roundSize))
    Swag.assert(round != null and !round.line.isVisible())
    Swag.assert(testFindItem(prop, "Effects") == null)
}

// A line end that cannot be resized does not offer the row that would resize it.
//
// The four plain ends are the terminal of the stroke itself and are as wide as it is thick; only
// the anchors are decorations the size rows scale. Offering the row for all of them left two
// sliders that silently did nothing.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let prop = testSetupPropWnd(&f)

    let line = testAddLine(f.capture, 10, 20, 100, 50)
    line.beginCap = .Round
    line.endCap   = .ArrowAnchor
    f.capture.selection.add(0)
    prop.selectionHasChanged()
    f.gui.pump()

    let start = testFindItem(prop, #nameof(FormLine.startSize))
    let end   = testFindItem(prop, #nameof(FormLine.endSize))
    Swag.assert(start != null and !start.line.isVisible())
    Swag.assert(end != null and end.line.isVisible())

    // Picking an anchor for the other end brings its row back, on the next frame: the style cell
    // sits outside the grid, so the panel rebuilds itself to re-read the rule.
    prop.pushTypedValue(cast(u32) LineCapStyle.RoundAnchor, FormLine, #nameof(FormLine.beginCap), true)
    f.gui.runFrames(2)

    Swag.assert(testFindItem(prop, #nameof(FormLine.startSize))!.line.isVisible())
}

// A French session shows the generated rows in French.
//
// Every row here comes from a compile-time attribute literal, so this exercises the whole
// chain: the resolver Swag Capture installs, the key lookup against the reference English, and
// the rebuild the panel does when the notification arrives.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let prop = testSetupPropWnd(&f)

    // Whatever this test switches to, the next one starts on the reference wording.
    defer discard catch f.gui.app.setLanguage(Gui.ReferenceLanguage)

    discard testAddText(f.capture, 10, 20, 100, 50)
    f.capture.selection.add(0)
    prop.selectionHasChanged()
    f.gui.pump()

    // A slider row carries its label, and a combo row its entries. Both come from an
    // attribute literal: #[Name("Size")] and the JoinStyle case names.
    Swag.assert(testFindItem(prop, #nameof(FormText.fontSize))!.sliderBox.label.name == "Size")
    Swag.assert(testFindItem(prop, #nameof(BaseForm.joinStyle))!.comboBox.items[1]!.name.raw == "Round")

    expect f.gui.app.setLanguage("fr")

    // The resolver answers from the live table, so it is French before a single row is built.
    Swag.assert(Properties.resolveText("Size") == "Taille")

    f.gui.notify(.LanguageChanged)
    f.gui.pump()

    Swag.assert(testFindItem(prop, #nameof(FormText.fontSize))!.sliderBox.label.name == "Taille")
    Swag.assert(testFindItem(prop, #nameof(BaseForm.joinStyle))!.comboBox.items[1]!.name.raw == "Arrondi")

    f.capture.selection.clear()
    discard testAddShape(f.capture, 20, 20, 80, 40)
    f.capture.selection.add(1)
    prop.selectionHasChanged()
    f.gui.pump()

    let thickness     = testFindItem(prop, #nameof(BaseForm.borderSize))!.sliderBox
    let expectedWidth = Math.ceil(Painter.measureString(thickness.label.name.raw.toString(), thickness.label.font().regular!).width)
    Swag.assert(thickness.label.name == "Épaisseur")
    Swag.assert(thickness.labelWidth == expectedWidth)
    Swag.assert(testFindItem(prop, "Effects") == null)
}

// A property editor is built for the kind that was selected, and the painters and handlers it
// installs run again long after that: the panel is rebuilt from an event and a frame is not, so
// by the time one of them fires the selection may be another kind entirely. They ask for the
// selection as the kind they were made for, and must be told it is not one rather than handed
// another form's bytes to read as that kind.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let prop = testSetupPropWnd(&f)

    discard testAddShape(f.capture, 10, 10, 40, 40)
    let text = testAddText(f.capture, 60, 10, 100, 40)
    text.text = String.from("Swag")

    f.capture.selection.add(0)
    prop.selectionHasChanged()
    prop.applyLayout()
    Swag.assert(prop.getSelectedForm'FormShape() != null)

    // Move the selection to the text form without telling the panel, which is the window every
    // repaint between an editor being built and being rebuilt falls into.
    f.capture.selection.clear()
    f.capture.selection.add(1)

    Swag.assert(prop.getSelectedForm'FormShape() == null)
    Swag.assert(prop.getSelectedForm'FormStep() == null)
    Swag.assert(prop.getSelectedForm'FormLine() == null)
    Swag.assert(prop.getSelectedForm'FormCallout() == null)
    Swag.assert(prop.getSelectedForm'FormText() != null)
}

