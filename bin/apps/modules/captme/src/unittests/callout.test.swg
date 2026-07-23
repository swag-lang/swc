#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The callout bound encloses both the body box and the freely-placed tail tip.
#test
{
    var f: HeadlessFixture
    f.setup()

    let cf = testAddCallout(f.capture, 10, 10, 40, 20)

    // Body is 10,10 → 50,30; testAddCallout drops the tail below at (22, 60).
    @assert(cf.tailY == 60)
    let b = cf.IForm.boundRect()
    @assert(b.x == 10)
    @assert(b.y == 10)
    @assert(b.right() == 50)
    @assert(b.bottom() == 60)

    f.shutdown()
}

// Point 0 of a callout is the tail tip; MovePoint undo moves it and restores it.
#test
{
    var f: HeadlessFixture
    f.setup()

    let cf = testAddCallout(f.capture, 0, 0, 40, 20)
    let tx = cf.tailX
    let ty = cf.tailY

    var mp = f.capture.newUndo(.MovePoint)
    mp.baseForm = cast(IForm) cf
    mp.pointIdx = 0
    mp.newPosX  = 5
    mp.newPosY  = -7
    f.capture.pushUndo(mp)
    @assert(cf.tailX == tx + 5)
    @assert(cf.tailY == ty - 7)

    f.capture.undo()
    @assert(cf.tailX == tx)
    @assert(cf.tailY == ty)

    // Moving the whole form drags the tail along with the body.
    cf.IForm.moveForm(3, 4)
    @assert(cf.tailX == tx + 3)
    @assert(cf.tailY == ty + 4)

    f.shutdown()
}

// SetText edits a callout's text (reusing the FormText undo path) with undo/redo.
#test
{
    var f: HeadlessFixture
    f.setup()

    let cf = testAddCallout(f.capture, 5, 5, 60, 30)
    cf.text = "old"
    f.capture.selection.add(0)

    var u = f.capture.newUndo(.SetText)
    u.text = "new"
    f.capture.pushUndo(u)
    @assert(cf.text == "new")

    f.capture.undo()
    @assert(cf.text == "old")

    f.capture.redo()
    @assert(cf.text == "new")

    f.shutdown()
}

// Edit-mode plumbing recognizes the callout in both directions.
#test
{
    var f: HeadlessFixture
    f.setup()

    let cf = testAddCallout(f.capture, 0, 0, 40, 20)
    @assert(MainWnd.formToEditMode(cast(IForm) cf) == .Callout)

    f.main.updateEditMode(cast(IForm) cf)
    @assert(f.main.editMode == .Callout)
    @assert(@kindof(f.main.editModeToModel(.Callout)) == FormCallout)

    f.shutdown()
}

// SetText must flag the render dirty so the displayed FormText glyphs actually refresh
// (regression guard for the shared formEditableText/formEditableTextDirty helpers).
#test
{
    var f: HeadlessFixture
    f.setup()

    let text = testAddText(f.capture, 0, 0, 100, 40)
    text.text    = "old"
    text.isDirty = false
    f.capture.selection.add(0)

    var u = f.capture.newUndo(.SetText)
    u.text = "new"
    f.capture.pushUndo(u)
    @assert(text.text == "new")
    @assert(text.isDirty)

    f.shutdown()
}

// Font name and style edits reuse the shared FormText undo paths for a callout.
#test
{
    var f: HeadlessFixture
    f.setup()

    let cf = testAddCallout(f.capture, 0, 0, 60, 30)
    cf.fontName  = "old"
    cf.fontStyle = .Regular
    f.capture.selection.add(0)

    var us = f.capture.newUndo(.SetFontStyle)
    us.fontStyle = .Bold
    f.capture.pushUndo(us)
    @assert(cf.fontStyle == .Bold)
    f.capture.undo()
    @assert(cf.fontStyle == .Regular)

    var uf = f.capture.newUndo(.SetFont)
    uf.text      = "Arial"
    uf.fontStyle = .Italic
    f.capture.pushUndo(uf)
    @assert(cf.fontName == "Arial")
    @assert(cf.fontStyle == .Italic)
    f.capture.undo()
    @assert(cf.fontName == "old")
    @assert(cf.fontStyle == .Regular)

    f.shutdown()
}

// Painting a callout emits body/tail/text geometry without crashing, and hit-testing
// covers the body while far-away points miss.
#test
{
    var f: HeadlessFixture
    f.setup()

    let cf = testAddCallout(f.capture, 20, 20, 120, 60)
    cf.text        = "Hi!"
    cf.backColor   = ColorBlue
    cf.borderColor = Argb.White
    cf.textColor   = Argb.White

    var painter: Painter{fake: true}
    painter.begin()
    var cxt: FormPaintContext
    cxt.z = 1
    cf.IForm.paint(&painter, cxt)
    painter.end()
    @assert(painter.commandBuffer.count > 0)

    @assert(cf.IForm.hitTest({80, 50}, 1))
    @assert(!cf.IForm.hitTest({500, 500}, 1))

    f.shutdown()
}

// copy propagates callout style (not text) and isSame tracks style changes.
#test
{
    var f: HeadlessFixture
    f.setup()

    let cf = testAddCallout(f.capture, 0, 0, 40, 20)
    cf.roundSize = 22
    cf.fontSize  = 30
    cf.textColor = ColorRed
    cf.text      = "content"

    var copy: FormCallout
    cf.IForm.copy(&copy, cf)
    @assert(cf.IForm.isSame(&copy))
    @assert(copy.roundSize == 22)
    @assert(copy.text.isEmpty())

    copy.roundSize += 1
    @assert(!cf.IForm.isSame(&copy))

    f.shutdown()
}

// The tail base stays on the straight part of an edge, clear of the rounded corners,
// even when the tip points toward a corner (regression: it used to attach at the sharp
// corner past the arc, leaving a gap/overshoot where tail meets body).
#test
{
    var f: HeadlessFixture
    f.setup()

    let cf = testAddCallout(f.capture, 0, 0, 100, 60)
    cf.roundSize = 20
    let cr = 20.0

    // Tip well past the bottom-left corner: base must sit on the bottom straight span.
    let bl = cf.tailBase({-40, 100}, cf.roundSize)
    @assert(bl.p0.y == 60 and bl.p1.y == 60)
    @assert(bl.p0.x >= cr - 0.01)
    @assert(bl.p1.x <= 100 - cr + 0.01)

    // Tip past the top-right corner picks the right edge; base stays off the corners.
    let cf2 = testAddCallout(f.capture, 0, 0, 60, 100)
    cf2.roundSize = 20
    let tr = cf2.tailBase({100, -40}, cf2.roundSize)
    @assert(tr.p0.x == 60 and tr.p1.x == 60)
    @assert(tr.p0.y >= cr - 0.01)
    @assert(tr.p1.y <= 100 - cr + 0.01)

    f.shutdown()
}

// Callouts survive the copy/paste clipboard round-trip with text and geometry intact.
#test
{
    var f: HeadlessFixture
    f.setup()

    let cf = testAddCallout(f.capture, 12, 14, 50, 25)
    cf.text      = "hello"
    cf.roundSize = 18
    cf.tailX     = 4
    cf.tailY     = 90

    var clip: CaptureClipboardForms
    clip.add(cast(IForm) cf)

    var forms = clip.toForms(f.capture)
    defer Capture.freeForms(forms)

    @assert(forms.count == 1)
    @assert(@kindof(forms[0]) == FormCallout)
    let c2 = cast(*FormCallout) @dataof(forms[0])
    @assert(c2.text == "hello")
    @assert(c2.roundSize == 18)
    @assert(c2.tailX == 4)
    @assert(c2.tailY == 90)
    @assert(c2.capture == f.capture)

    f.shutdown()
}
