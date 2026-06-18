#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core

struct CaptmeHeadlessFixture
{
    gui:        GuiHeadlessHost
    main:       *MainWnd
    editView:   *EditView
    capture:    *Capture
}

impl CaptmeHeadlessFixture
{
    mtd setup(width = 900.0, height = 700.0)
    {
        .gui.setup(width, height)
        g_App.theme = .gui.theme

        .main = Wnd.create'MainWnd(&.gui.root, {0, 0, width, height})
        g_Main = .main

        .main.mdlFavorite  = &.main.mdlFormShape
        .main.mdlHighlight = &.main.mdlFormShape
        .main.mdlPixSel    = &.main.mdlFormShape

        .main.editWnd = EditWnd.create(.main, .main)
        .main.editWnd.position = {0, 0, width, height}
        .main.editWnd.editView.position = {0, 0, width, height}
        .editView = .main.editWnd.editView
        .editView.zoom = 1

        let capture = Memory.new'Capture()
        capture.width  = 400
        capture.height = 300
        capture.backImg = Image.create(400, 300, .BGRA8)
        .editView.setCapture(capture)
        .capture = capture
    }

    mtd shutdown()
    {
        .gui.shutdown()
        g_Main = null
    }
}

func captmeTestCtx(main: *MainWnd, id: WndId)->ActionContext
{
    return {wnd: main, id: id}
}

func captmeTestAddShape(capture: *Capture, x, y, w, h: s32)->*FormShape
{
    let form = Memory.new'FormShape()
    form.IForm.setBaseForm(x, y, w, h)
    form.IForm.setup(capture)
    capture.forms.add(cast(IForm) form)
    return form
}

func captmeTestAddText(capture: *Capture, x, y, w, h: s32)->*FormText
{
    let form = Memory.new'FormText()
    form.text = "txt"
    form.IForm.setBaseForm(x, y, w, h)
    form.IForm.setup(capture)
    capture.forms.add(cast(IForm) form)
    return form
}

func captmeTestAddLine(capture: *Capture, xa, ya, xb, yb: f32)->*FormLine
{
    let form = Memory.new'FormLine()
    form.xa = xa
    form.ya = ya
    form.xb = xb
    form.yb = yb
    form.IForm.setup(capture)
    capture.forms.add(cast(IForm) form)
    return form
}

func captmeTestAddPolygon(capture: *Capture)->*FormPolygon
{
    let form = Memory.new'FormPolygon()
    form.points.add({10, 10})
    form.points.add({30, 10})
    form.points.add({30, 40})
    form.points.add({10, 40})
    form.IForm.setup(capture)
    capture.forms.add(cast(IForm) form)
    return form
}

func captmeTestAddDraw(capture: *Capture)->*FormDraw
{
    let form = Memory.new'FormDraw()
    form.points.add({10, 10})
    form.points.add({20, 25})
    form.points.add({35, 35})
    form.IForm.setup(capture)
    capture.forms.add(cast(IForm) form)
    return form
}

func captmeTestAddImage(capture: *Capture, x, y, w, h: s32)->*FormImage
{
    let form = Memory.new'FormImage()
    form.IForm.setBaseForm(x, y, w, h)
    form.IForm.setup(capture)
    capture.forms.add(cast(IForm) form)
    return form
}

func captmeTestAssertRect(rect: Math.Rectangle, x, y, w, h: f32)
{
    @assert(Math.abs(rect.x - x) < 0.001)
    @assert(Math.abs(rect.y - y) < 0.001)
    @assert(Math.abs(rect.width - w) < 0.001)
    @assert(Math.abs(rect.height - h) < 0.001)
}

func captmeTestDeleteForm(itf: IForm)
{
    Memory.delete(@dataof(itf), @kindof(itf))
}

func captmeTestTempCapturePath()->String
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    var name: String = "swag_captme_"
    name += GUID64.getRandom().getString()
    name += ".captme"
    return Path.combine(tempDir.toString(), name.toString())
}

func captmeTestCountNonZeroBytes(img: Image)->u64
{
    var result: retval
    for i in img.pixels.count
    {
        if img.pixels.buffer[i] do
            result += 1
    }

    return result
}

#test
{
    var fix: CaptmeHeadlessFixture
    fix.setup()

    let shape = captmeTestAddShape(fix.capture, 80, 70, 50, 40)
    shape.kind = .RoundRectangle
    shape.borderSize = 7
    shape.subKind = .Highlight
    fix.main.updateEditMode(cast(IForm) shape)
    fix.main.updateModel(cast(IForm) shape)
    @assert(fix.main.editMode == .Highlight)
    @assert(fix.main.getEditMode() == .Shape)

    let clonedShape = fix.main.newFormFromModel(fix.main.getEditMode())
    @assert(@kindof(clonedShape) == FormShape)
    let clonedShapeBase = cast(*BaseForm) @dataof(clonedShape)
    @assert(clonedShapeBase.subKind == .Highlight)
    captmeTestDeleteForm(clonedShape)

    let draw = captmeTestAddDraw(fix.capture)
    draw.subKind = .PixSel
    fix.main.updateEditMode(cast(IForm) draw)
    fix.main.updateModel(cast(IForm) draw)
    @assert(fix.main.editMode == .PixSel)
    @assert(fix.main.getEditMode() == .Draw)

    let clonedDraw = fix.main.newFormFromModel(fix.main.getEditMode())
    @assert(@kindof(clonedDraw) == FormDraw)
    let clonedDrawBase = cast(*BaseForm) @dataof(clonedDraw)
    @assert(clonedDrawBase.subKind == .PixSel)
    captmeTestDeleteForm(clonedDraw)

    fix.shutdown()
}

#test
{
    var fix: CaptmeHeadlessFixture
    fix.setup()

    let shape = captmeTestAddShape(fix.capture, 10, 20, -30, -40)
    captmeTestAssertRect(shape.IForm.boundRect(), -20, -20, 30, 40)
    shape.IForm.moveBaseForm(5, 6, 7, 8)
    captmeTestAssertRect(shape.IForm.boundRect(), -15, -14, 37, 48)
    shape.IForm.scaleBaseForm(2)
    captmeTestAssertRect(shape.IForm.boundRect(), -30, -28, 74, 96)

    let text = captmeTestAddText(fix.capture, 100, 120, -50, -60)
    @assert(text.IForm.mustClipToBound())
    @assert(text.IForm.canRotate())
    captmeTestAssertRect(text.IForm.boundRect(), 50, 60, 50, 60)
    @assert(text.IForm.hitTest({75, 90}, 1))
    @assert(!text.IForm.hitTest({20, 20}, 1))

    let step = Memory.new'FormStep()
    step.IForm.setBaseForm(30, 40, -20, -10)
    captmeTestAssertRect(step.IForm.boundRect(), 10, 30, 20, 10)
    captmeTestDeleteForm(cast(IForm) step)

    fix.shutdown()
}

#test
{
    var fix: CaptmeHeadlessFixture
    fix.setup()

    let line = captmeTestAddLine(fix.capture, 10, 20, 50, 80)
    captmeTestAssertRect(line.IForm.boundRect(), 10, 20, 40, 60)
    line.IForm.movePoint(1, -15, 10)
    @assert(line.xb == 35)
    @assert(line.yb == 90)
    line.IForm.moveForm(5, -5)
    @assert(line.xa == 15)
    @assert(line.ya == 15)
    @assert(line.xb == 40)
    @assert(line.yb == 85)

    let polygon = captmeTestAddPolygon(fix.capture)
    captmeTestAssertRect(polygon.IForm.boundRect(), 10, 10, 20, 30)
    polygon.IForm.movePoint(2, 10, -5)
    captmeTestAssertRect(polygon.IForm.boundRect(), 10, 10, 30, 30)
    polygon.IForm.setBaseForm(100, 200, 60, 30)
    captmeTestAssertRect(polygon.IForm.boundRect(), 100, 200, 60, 30)

    let draw = captmeTestAddDraw(fix.capture)
    captmeTestAssertRect(draw.IForm.boundRect(), 7.5, 7.5, 30, 30)
    draw.IForm.moveForm(5, 6)
    captmeTestAssertRect(draw.IForm.boundRect(), 12.5, 13.5, 30, 30)

    fix.shutdown()
}

#test
{
    let srcLine = Memory.new'FormLine()
    srcLine.borderSize = 11
    srcLine.subKind = .Highlight
    let dstLine = Memory.new'FormLine()
    srcLine.IForm.copy(dstLine, srcLine)
    @assert(dstLine.subKind == .Highlight)
    @assert(srcLine.IForm.isSame(dstLine))
    dstLine.subKind = .None
    @assert(!srcLine.IForm.isSame(dstLine))
    captmeTestDeleteForm(cast(IForm) srcLine)
    captmeTestDeleteForm(cast(IForm) dstLine)

    let srcPoly = Memory.new'FormPolygon()
    srcPoly.subKind = .PixSel
    let dstPoly = Memory.new'FormPolygon()
    srcPoly.IForm.copy(dstPoly, srcPoly)
    @assert(dstPoly.subKind == .PixSel)
    @assert(srcPoly.IForm.isSame(dstPoly))
    dstPoly.subKind = .None
    @assert(!srcPoly.IForm.isSame(dstPoly))
    captmeTestDeleteForm(cast(IForm) srcPoly)
    captmeTestDeleteForm(cast(IForm) dstPoly)

    let srcDraw = Memory.new'FormDraw()
    srcDraw.subKind = .Highlight
    srcDraw.paintShadow = false
    let dstDraw = Memory.new'FormDraw()
    srcDraw.IForm.copy(dstDraw, srcDraw)
    @assert(dstDraw.subKind == .Highlight)
    @assert(!dstDraw.paintShadow)
    @assert(srcDraw.IForm.isSame(dstDraw))
    dstDraw.paintShadow = true
    @assert(!srcDraw.IForm.isSame(dstDraw))
    captmeTestDeleteForm(cast(IForm) srcDraw)
    captmeTestDeleteForm(cast(IForm) dstDraw)
}

#test
{
    var quick: QuickWnd

    quick.defaultQuickStyleArrow()
    quick.defaultQuickStyleLine()
    quick.defaultQuickStyleShape()
    quick.defaultQuickStyleImage()
    quick.defaultQuickStyleStep()
    quick.defaultQuickStylePolygon()
    quick.defaultQuickStyleText()
    quick.defaultQuickStyleDraw()
    quick.defaultQuickStyleHighlight()
    quick.defaultQuickStylePixSel()

    @assert(quick.qsArrow.forms.count == 12)
    @assert(quick.qsLine.forms.count == 7)
    @assert(quick.qsShape.forms.count == 16)
    @assert(quick.qsImage.forms.count == 5)
    @assert(quick.qsStep.forms.count == 8)
    @assert(quick.qsPolygon.forms.count == 10)
    @assert(quick.qsText.forms.count == 14)
    @assert(quick.qsDraw.forms.count == 7)
    @assert(quick.qsHighlight.forms.count == 12)
    @assert(quick.qsPixSel.forms.count == 4)

    @assert(@kindof(quick.qsArrow.forms[0]) == FormArrow)
    @assert(@kindof(quick.qsLine.forms[0]) == FormLine)
    @assert(@kindof(quick.qsShape.forms[0]) == FormShape)
    @assert(@kindof(quick.qsImage.forms[0]) == FormImage)
    @assert(@kindof(quick.qsStep.forms[0]) == FormStep)
    @assert(@kindof(quick.qsPolygon.forms[0]) == FormPolygon)
    @assert(@kindof(quick.qsText.forms[0]) == FormText)
    @assert(@kindof(quick.qsDraw.forms[0]) == FormDraw)
    let highlightBase = cast(*BaseForm) @dataof(quick.qsHighlight.forms[0])
    let pixSelBase = cast(*BaseForm) @dataof(quick.qsPixSel.forms[0])
    @assert(highlightBase.subKind == .Highlight)
    @assert(pixSelBase.subKind == .PixSel)
}

#test
{
    var fix: CaptmeHeadlessFixture
    fix.setup()

    discard captmeTestAddShape(fix.capture, 10, 20, 30, 30)
    discard captmeTestAddText(fix.capture, 50, 60, 30, 30)
    discard captmeTestAddShape(fix.capture, 90, 100, 30, 30)

    var actSel: ActionSelection
    discard actSel.IActionUI.execute(captmeTestCtx(fix.main, ActionSelection.SelectAll))
    @assert(fix.capture.selection.count == 3)

    discard actSel.IActionUI.execute(captmeTestCtx(fix.main, ActionSelection.SelectSameAll))
    @assert(fix.capture.selection.count == 2)
    @assert(fix.capture.selection.contains(0))
    @assert(fix.capture.selection.contains(2))

    discard actSel.IActionUI.execute(captmeTestCtx(fix.main, ActionSelection.InvertSelection))
    @assert(fix.capture.selection.count == 1)
    @assert(fix.capture.selection[0] == 1)

    discard actSel.IActionUI.execute(captmeTestCtx(fix.main, ActionSelection.DeSelectAll))
    @assert(fix.capture.selection.isEmpty())

    fix.shutdown()
}

#test
{
    var fix: CaptmeHeadlessFixture
    fix.setup()

    let a = captmeTestAddShape(fix.capture, 10, 20, 30, 20)
    let b = captmeTestAddShape(fix.capture, 60, 80, 20, 40)
    fix.capture.selection.add(0)
    fix.capture.selection.add(1)

    var undo = fix.capture.newUndo(.AlignTop)
    fix.capture.pushUndo(undo)
    @assert(a.x == 10)
    @assert(b.x == 60)
    @assert(a.y == 20)
    @assert(b.y == 20)

    fix.capture.undo()
    @assert(a.x == 10)
    @assert(b.x == 60)
    @assert(a.y == 20)
    @assert(b.y == 80)

    undo = fix.capture.newUndo(.AlignBottom)
    fix.capture.pushUndo(undo)
    @assert(a.x == 10)
    @assert(b.x == 60)
    @assert(a.y + a.h == 120)
    @assert(b.y + b.h == 120)

    fix.capture.undo()
    @assert(a.x == 10)
    @assert(b.x == 60)
    @assert(a.y == 20)
    @assert(b.y == 80)

    fix.shutdown()
}

#test
{
    var fix: CaptmeHeadlessFixture
    fix.setup()

    let a = captmeTestAddShape(fix.capture, 10, 20, 30, 20)
    discard captmeTestAddShape(fix.capture, 60, 80, 20, 40)
    fix.capture.selection.add(0)

    var undo = fix.capture.newUndo(.OffsetSelection, 77)
    undo.newPosX = 5
    fix.capture.pushUndo(undo)

    undo = fix.capture.newUndo(.OffsetSelection, 77)
    undo.newPosY = -6
    fix.capture.pushUndo(undo)

    @assert(a.x == 15)
    @assert(a.y == 14)
    fix.capture.undo()
    @assert(a.x == 10)
    @assert(a.y == 20)
    @assert(fix.capture.canRedo())

    undo = fix.capture.newUndo(.OffsetSelection)
    undo.newPosX = -3
    fix.capture.pushUndo(undo)
    @assert(a.x == 7)
    @assert(!fix.capture.canRedo())

    fix.shutdown()
}

#test
{
    var fix: CaptmeHeadlessFixture
    fix.setup()

    let selected = captmeTestAddShape(fix.capture, 10, 20, 30, 20)
    discard captmeTestAddShape(fix.capture, 60, 80, 20, 40)
    fix.capture.selection.add(0)

    fix.main.snap = false
    var nx = 48
    var ny = 0
    fix.capture.snap(&nx, &ny, false, false)
    @assert(nx == 48)
    @assert(ny == 0)
    @assert(fix.capture.snapX == -1)

    fix.main.snap = true
    nx = 48
    ny = 0
    fix.capture.snap(&nx, &ny, false, false)
    @assert(nx == 50)
    @assert(ny == 0)
    @assert(fix.capture.snapX == 60)

    nx = 0
    ny = 57
    fix.capture.snap(&nx, &ny, false, false)
    @assert(nx == 0)
    @assert(ny == 60)
    @assert(fix.capture.snapY == 80)
    @assert(selected.x == 10)
    @assert(selected.y == 20)

    fix.shutdown()
}

#test
{
    var fix: CaptmeHeadlessFixture
    fix.setup()

    fix.capture.width = 6
    fix.capture.height = 6
    fix.capture.backImg = Image.create(6, 6, .BGRA8)
    fix.capture.backImg.fill(Argb.Zero)
    fix.main.pixSelFillCol = 0xFF112233

    let pixSel = captmeTestAddShape(fix.capture, 1, 1, 4, 4)
    pixSel.kind = .Rectangle
    pixSel.subKind = .PixSel
    fix.capture.selection.add(0)

    @assert(captmeTestCountNonZeroBytes(fix.capture.backImg) == 0)
    fix.main.pixSelFill()
    @assert(captmeTestCountNonZeroBytes(fix.capture.backImg) != 0)
    @assert(fix.capture.canUndo())

    fix.capture.undo()
    @assert(captmeTestCountNonZeroBytes(fix.capture.backImg) == 0)
    @assert(fix.capture.canRedo())

    fix.capture.redo()
    @assert(captmeTestCountNonZeroBytes(fix.capture.backImg) != 0)

    fix.main.pixSelClear()
    @assert(captmeTestCountNonZeroBytes(fix.capture.backImg) == 0)

    fix.shutdown()
}

#test
{
    var fix: CaptmeHeadlessFixture
    fix.setup()

    let path = captmeTestTempCapturePath()
    defer discard catch File.delete(path)

    let shape = captmeTestAddShape(fix.capture, 12, 34, 56, 78)
    shape.kind = .Rectangle
    shape.borderColor = ColorRed
    fix.capture.selection.add(0)
    fix.capture.file = path
    fix.capture.changed = true
    catch fix.capture.save()
    @assert(@err == null)

    let loaded = catch Capture.load(path)
    @assert(@err == null)
    defer Memory.delete(loaded)

    @assert(loaded.width == fix.capture.width)
    @assert(loaded.height == fix.capture.height)
    @assert(loaded.forms.count == 1)
    @assert(@kindof(loaded.forms[0]) == FormShape)
    let loadedShape = cast(*FormShape) @dataof(loaded.forms[0])
    @assert(loadedShape.x == 12)
    @assert(loadedShape.y == 34)
    @assert(loadedShape.w == 56)
    @assert(loadedShape.h == 78)
    @assert(loadedShape.kind == .Rectangle)
    @assert(loadedShape.borderColor == ColorRed)
    @assert(loadedShape.capture == loaded)

    fix.shutdown()
}

#test
{
    var fix: CaptmeHeadlessFixture
    fix.setup()

    let shape = captmeTestAddShape(fix.capture, 10, 10, 50, 50)

    var actEdit: ActionEdit
    var evt = CommandStateEvent{kind: .ComputeCommandState}
    evt.id = ActionEdit.ResetRotation
    discard actEdit.IActionUI.update(captmeTestCtx(fix.main, ActionEdit.ResetRotation), &evt)
    @assert(evt.hidden)
    @assert(evt.disabled)

    fix.capture.selection.add(0)
    evt = CommandStateEvent{kind: .ComputeCommandState}
    evt.id = ActionEdit.ResetRotation
    discard actEdit.IActionUI.update(captmeTestCtx(fix.main, ActionEdit.ResetRotation), &evt)
    @assert(!evt.hidden)
    @assert(evt.disabled)

    shape.rotate = 45
    evt = CommandStateEvent{kind: .ComputeCommandState}
    evt.id = ActionEdit.ResetRotation
    discard actEdit.IActionUI.update(captmeTestCtx(fix.main, ActionEdit.ResetRotation), &evt)
    @assert(!evt.hidden)
    @assert(!evt.disabled)

    discard actEdit.IActionUI.execute(captmeTestCtx(fix.main, ActionEdit.ResetRotation))
    @assert(shape.rotate == 0)
    fix.capture.undo()
    @assert(shape.rotate == 45)

    fix.shutdown()
}

#test
{
    var fix: CaptmeHeadlessFixture
    fix.setup()

    fix.editView.setZoom(-100)
    @assert(Math.abs(fix.editView.zoom - EditView.MinZoom) < 0.001)
    @assert(!fix.editView.canZoomOut())
    @assert(fix.editView.canZoomIn())

    fix.editView.setZoom(100)
    @assert(Math.abs(fix.editView.zoom - EditView.MaxZoom) < 0.001)
    @assert(fix.editView.canZoomOut())
    @assert(!fix.editView.canZoomIn())

    fix.editView.setZoom(1)
    fix.editView.zoomIn()
    @assert(Math.abs(fix.editView.zoom - 1.1) < 0.001)
    fix.editView.zoomOut()
    @assert(Math.abs(fix.editView.zoom - 1.0) < 0.001)

    fix.shutdown()
}

#test
{
    var g: GizmoRect
    g.rect = {10, 20, 100, 80}

    @assert(Math.abs(g.computeRotate({60, 20}) - 0) < 0.001)
    @assert(Math.abs(g.computeRotate({110, 60}) - 90) < 0.001)
    @assert(Math.abs(g.computeRotate({60, 100}) - 180) < 0.001)
    @assert(Math.abs(g.computeRotate({10, 60}) - 270) < 0.001)

    g.rotateEnabled = true
    g.rotateValue = 90
    let local = g.toLocal({100, 60})
    @assert(Math.abs(local.x - 60) < 0.001)
    @assert(Math.abs(local.y - 20) < 0.001)
}

#test
{
    var fix: CaptmeHeadlessFixture
    fix.setup()

    var tool: ActionToolMode
    discard tool.IActionUI.execute(captmeTestCtx(fix.main, ActionToolMode.Text))
    @assert(fix.main.editMode == .Text)
    discard tool.IActionUI.execute(captmeTestCtx(fix.main, ActionToolMode.PixSel))
    @assert(fix.main.editMode == .PixSel)

    var align: ActionAlign
    let shape = captmeTestAddShape(fix.capture, 20, 30, 20, 20)
    fix.capture.selection.add(0)
    discard align.IActionUI.execute(captmeTestCtx(fix.main, ActionAlign.Right1))
    @assert(shape.x == 21)
    discard align.IActionUI.execute(captmeTestCtx(fix.main, ActionAlign.Top))
    @assert(shape.y == 25)

    fix.shutdown()
}
