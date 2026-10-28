#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, File

func testFindItem(prop: *PropWnd, name: string)->*PropertiesItem?
{
    for item in prop.grid.items
    {
        let it = unwrap item
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

// Collects the controls of the head of the panel whose tooltip is `tip`, in display order.
func testCollectStyleButtons(wnd: *Wnd, tip: string, result: *Array'(*IconButton))
{
    for child in wnd.children
    {
        if child is IconButton as button where button.toolTip == tip do
            result.add(button)
        testCollectStyleButtons(child, tip, result)
    }
}

func testHasStyleTip(prop: *PropWnd, tip: string)->bool
{
    var buttons: Array'(*IconButton)
    testCollectStyleButtons(prop.topLayout, tip, &buttons)
    return not buttons.isEmpty()
}

func testFindStyleButtons(prop: *PropWnd, tip: string)->Array'(*IconButton)
{
    var result: #returntype
    testCollectStyleButtons(prop.topLayout, tip, &result)
    return result
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
    next.backImg = Gui.Testing.indexedImage(120, 80)
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

    let current = unwrap f.main.editWnd.getCapture()
    Swag.assert(current.file == nextPath)
    Swag.assert(current.selection.isEmpty())

    let border = unwrap testFindItem(prop, #nameof(BaseForm.borderSize))
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

    let outline = unwrap testFindItem(prop, #nameof(FormLine.outlineSize))
    Swag.assert((outline.sliderBox != null))
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
    Swag.assert(not testFindItem(prop, #nameof(FormDraw.outlineSize))!.line.isVisible())
}

// FormArrow embeds FormLine, so the start and end glyphs must read and write the embedded caps
// rather than treating the arrow as an unrelated form type.
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

    // One glyph per line end, the current one checked.
    let starts = testFindStyleButtons(prop, appStrings().ui_PropStart)
    Swag.assert(starts.count == LineCapStyle.count)
    Swag.assert(starts[cast(u64, LineCapStyle.SquareAnchor)].isChecked)
    Swag.assert(not starts[cast(u64, LineCapStyle.ArrowAnchor)].isChecked)

    // The panel rebuilds after a choice, since a line end decides which size rows it shows.
    f.gui.clickWnd(starts[cast(u64, LineCapStyle.ArrowAnchor)])
    f.gui.pump()
    Swag.assert(arrow.beginCap == .ArrowAnchor)
    let rebuilt = testFindStyleButtons(prop, appStrings().ui_PropStart)
    Swag.assert(rebuilt[cast(u64, LineCapStyle.ArrowAnchor)].isChecked)
    Swag.assert(not rebuilt[cast(u64, LineCapStyle.SquareAnchor)].isChecked)
}

// The dashes are a row of glyphs like the line ends: every style but `Pattern`, which takes its
// lengths from the pen and has nothing to show on its own.
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

    // The glyphs are None, Dot, Dash, DashDot: the second one is Dot.
    let dashes = testFindStyleButtons(prop, appStrings().ui_PropDash)
    Swag.assert(dashes.count == DashStyle.count - 1)
    Swag.assert(dashes[3].isChecked)

    f.gui.clickWnd(dashes[1])
    f.gui.pump()
    Swag.assert(line.dashStyle == .Dot)
    let rebuilt = testFindStyleButtons(prop, appStrings().ui_PropDash)
    Swag.assert(rebuilt[1].isChecked and not rebuilt[3].isChecked)
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
    let border = unwrap testFindItem(prop, #nameof(BaseForm.borderSize))
    Swag.assert((border.sliderBox != null))
    Swag.assert(border.sliderBox.label.name == "Outline")
    Swag.assert(border.sliderBox.slider.minimum() == MinTextBorderSize)
    Swag.assert(border.sliderBox.slider.maximum() == MaxTextBorderSize)
    let labelWidth = Math.ceil(Painter.measureString(border.sliderBox.label.name.raw, unwrap border.sliderBox.label.font().regular).width)
    Swag.assert(border.sliderBox.labelWidth >= labelWidth)

    // The joins row is a generated combo omitting JoinStyle.None: Round selects index 1
    let joins = unwrap testFindItem(prop, #nameof(BaseForm.joinStyle))
    Swag.assert((joins.comboBox != null))
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
    Swag.assert(not (testFindItem(prop, #nameof(FormText.fontStyle))!.label != null))
    Swag.assert(not (testFindItem(prop, #nameof(FormText.alignHorz))!.label != null))
    Swag.assert(not (testFindItem(prop, #nameof(FormText.alignVert))!.label != null))

    // Most specific first: the text form's own fields come before the shared BaseForm
    // block, even though the language declares 'using base' first
    Swag.assert(testItemIndex(prop, #nameof(FormText.fontName)) < testItemIndex(prop, #nameof(BaseForm.borderSize)))
    Swag.assert(testItemIndex(prop, #nameof(FormText.fontSize)) < testItemIndex(prop, #nameof(BaseForm.borderSize)))
    Swag.assert(testFindItem(prop, "Effects") == null)

    // The x/y and w/h rows close the grid. They carry no category separator of their own: each
    // one is named for what it holds, and a heading above them would only repeat it.
    let n = prop.grid.items.count
    Swag.assert(n >= 3)
    Swag.assert(prop.grid.items[n - 1]!.typeValue.name == appStrings().ui_PropPosition)

    // Rows span the whole panel width (they used to be clamped to editorWidth)
    Swag.assert(border.line.position.width > 250)
    Swag.assert(border.line.position.width >= prop.grid.position.width - 24)

    // The placeholder section row consumes no vertical room: the first real row
    // starts right at the top of the grid (only its own margin above)
    let sectionIt = unwrap prop.grid.items[0]
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

    let posItemX = unwrap testFindItem(prop, appStrings().ui_PropPosition)
    let stackX   = posItemX.line.children[0]
    f.gui.clickWnd((assume cast(*EditCtrl, stackX.children[0]).edit))
    f.gui.pump()
    Swag.assert(prop.grid.scrollWnd.scrollPosition().y == sc.y)

    // Focusing an editor may rebuild property-row widgets. Resolve them again after
    // every pump instead of retaining pointers into the previous window tree.
    let posItemY = unwrap testFindItem(prop, appStrings().ui_PropPosition)
    let stackY   = posItemY.line.children[0]
    let editY    = assume cast(*EditCtrl, stackY.children[1]).edit
    f.gui.clickWnd(editY)
    f.gui.pump()
    Swag.assert(prop.grid.scrollWnd.scrollPosition().y == sc.y)

    let posItemLine = unwrap testFindItem(prop, appStrings().ui_PropPosition)
    f.gui.clickWnd(posItemLine.line)
    f.gui.pump()
    Swag.assert(prop.grid.scrollWnd.scrollPosition().y == sc.y)

    // Dead zone just above the row (inside the separator margin)
    let posItemDead = unwrap testFindItem(prop, appStrings().ui_PropPosition)
    var pt = posItemDead.line.surfaceRect().center()
    pt.y = posItemDead.line.surfaceRect().y - 8
    posItemDead.line.surface!.surfaceToScreen(&pt)
    f.gui.click(pt)
    f.gui.pump()
    Swag.assert(prop.grid.scrollWnd.scrollPosition().y == sc.y)
}

// The position strip holds X, Y, W and H in one row; a value typed in one of them moves or sizes
// the selected object.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let prop = testSetupPropWnd(&f)

    let text = testAddText(f.capture, 10, 20, 100, 50)
    f.capture.selection.add(0)
    prop.selectionHasChanged()
    f.gui.pump()

    let strip = unwrap testFindItem(prop, appStrings().ui_PropPosition)
    let boxes = strip.line.children[0]
    Swag.assert(boxes.children.count == 4)
    let width = (assume cast(*EditCtrl, boxes.children[2])).edit
    Swag.assert(width.text() == "100")

    width.setText("140")
    width.sigCommitted.call(width)
    f.gui.pump()
    Swag.assert(text.w == 140)
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
    Swag.assert(border != null and not border.line.isVisible())
    let joins = testFindItem(prop, #nameof(BaseForm.joinStyle))
    Swag.assert(joins != null and not joins.line.isVisible())
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
    Swag.assert(border != null and not border.line.isVisible())
    let round = testFindItem(prop, #nameof(FormShape.roundSize))
    Swag.assert(round != null and not round.line.isVisible())
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

    with let line = testAddLine(f.capture, 10, 20, 100, 50)
    {
        .beginCap = .Round
        .endCap   = .ArrowAnchor
    }

    f.capture.selection.add(0)
    prop.selectionHasChanged()
    f.gui.pump()

    let start = testFindItem(prop, #nameof(FormLine.startSize))
    let end   = testFindItem(prop, #nameof(FormLine.endSize))
    Swag.assert(start != null and not start.line.isVisible())
    Swag.assert(end != null and end.line.isVisible())

    // Picking an anchor for the other end brings its row back, on the next frame: the style cell
    // sits outside the grid, so the panel rebuilds itself to re-read the rule.
    prop.pushTypedValue(cast(u32, LineCapStyle.RoundAnchor), FormLine, #nameof(FormLine.beginCap), true)
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
    let expectedWidth = Math.ceil(Painter.measureString(thickness.label.name.raw, unwrap thickness.label.font().regular).width)
    Swag.assert(thickness.label.name == "Épaisseur")
    Swag.assert(thickness.labelWidth >= expectedWidth)
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
    text.text = "Swag"

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
