#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

struct CaptmeHeadlessFixture
{
    gui:      GuiHeadlessHost
    main:     *MainWnd
    editView: *EditView
    capture:  *Capture
}

impl CaptmeHeadlessFixture
{
    mtd setup(width = 900.0, height = 700.0)
    {
        .gui.setup(width, height)
        g_App.theme = Memory.new'Theme()
        g_App.theme.colors.setDark()
        g_App.theme.setupDefaultFonts()
        let style = Memory.new'ThemeStyleRef()
        style.theme = g_App.theme
        style.count = 2
        g_App.style.refr = style

        .main             = Wnd.create'MainWnd(&.gui.root, {x: 0, y: 0, width: width, height: height})
        g_Main            = .main
        .main.mdlFavorite = &.main.mdlFormShape
        .main.mdlHighlight = &.main.mdlFormShape
        .main.mdlPixSel  = &.main.mdlFormShape
        .main.editWnd    = EditWnd.create(.main, .main)
        .main.editWnd.setPosition({x: 0, y: 0, width: width, height: height})
        .main.editWnd.editView.setPosition({x: 0, y: 0, width: width, height: height})

        .editView        = .main.editWnd.editView
        let localCapture = Memory.new'Capture()
        localCapture.width, localCapture.widthOrg = 400
        localCapture.height, localCapture.heightOrg = 300
        localCapture.backImg = Image.create(400, 300, .BGRA8)
        .editView.setCapture(localCapture)
        .capture         = localCapture
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

func captmeTestWndCtx(wnd: *Wnd, id: WndId)->ActionContext
{
    return {wnd: wnd, id: id}
}

func captmeTestState(id: WndId)->CommandStateEvent
{
    return {id: id}
}

func captmeTestAssertRect(rect: Math.Rectangle, x: f32, y: f32, width: f32, height: f32)
{
    @assert(Math.abs(rect.x - x) < 0.001)
    @assert(Math.abs(rect.y - y) < 0.001)
    @assert(Math.abs(rect.width - width) < 0.001)
    @assert(Math.abs(rect.height - height) < 0.001)
}

func captmeTestAssertPoint(pt: Math.Vector2, x: f32, y: f32)
{
    @assert(Math.abs(pt.x - x) < 0.001)
    @assert(Math.abs(pt.y - y) < 0.001)
}

func captmeTestMouse(kind: MouseEvent.Kind, button = Input.MouseButton.Left)->MouseEvent
{
    var evt  = MouseEvent{kind: kind}
    evt.button = button
    return evt
}

func(T) captmeTestActionExecute(main: *MainWnd, id: WndId)->bool
{
    let act = @mkinterface(null, #typeof(T), IActionUI)
    return act.execute(captmeTestCtx(main, id))
}

func(T) captmeTestActionUpdate(main: *MainWnd, id: WndId, evt: *CommandStateEvent)->bool
{
    let act = @mkinterface(null, #typeof(T), IActionUI)
    return act.update(captmeTestCtx(main, id), evt)
}

func(T) captmeTestActionExecuteWnd(wnd: *Wnd, id: WndId)->bool
{
    let act = @mkinterface(null, #typeof(T), IActionUI)
    return act.execute(captmeTestWndCtx(wnd, id))
}

func(T) captmeTestActionUpdateWnd(wnd: *Wnd, id: WndId, evt: *CommandStateEvent)->bool
{
    let act = @mkinterface(null, #typeof(T), IActionUI)
    return act.update(captmeTestWndCtx(wnd, id), evt)
}

func captmeTestAddShape(capture: *Capture, x: f32, y: f32, width: f32, height: f32, subKind = FormSubKind.None)->*FormShape
{
    let form = Memory.new'FormShape()
    form.IForm.setup(capture)
    form.IForm.setBaseForm(cast() x, cast() y, cast() width, cast() height)
    form.subKind = subKind
    capture.forms.add(form)
    return form
}

func captmeTestAddText(capture: *Capture, x: f32, y: f32, width: f32, height: f32)->*FormText
{
    let form = Memory.new'FormText()
    form.IForm.setup(capture)
    form.IForm.setBaseForm(cast() x, cast() y, cast() width, cast() height)
    capture.forms.add(form)
    return form
}

func captmeTestAddStep(capture: *Capture, x: f32, y: f32, width: f32, height: f32)->*FormStep
{
    let form = Memory.new'FormStep()
    form.IForm.setup(capture)
    form.IForm.setBaseForm(cast() x, cast() y, cast() width, cast() height)
    capture.forms.add(form)
    return form
}

func captmeTestAddLine(capture: *Capture, xa: f32, ya: f32, xb: f32, yb: f32, subKind = FormSubKind.None)->*FormLine
{
    let form = Memory.new'FormLine()
    form.IForm.setup(capture)
    form.IForm.setBaseForm(cast() xa, cast() ya, cast(s32) (xb - xa), cast(s32) (yb - ya))
    form.subKind = subKind
    capture.forms.add(form)
    return form
}

func captmeTestAddArrow(capture: *Capture, xa: f32, ya: f32, xb: f32, yb: f32, subKind = FormSubKind.None)->*FormArrow
{
    let form = Memory.new'FormArrow()
    form.IForm.setup(capture)
    form.IForm.setBaseForm(cast() xa, cast() ya, cast(s32) (xb - xa), cast(s32) (yb - ya))
    form.subKind = subKind
    capture.forms.add(form)
    return form
}

func captmeTestAddPolygon(capture: *Capture, points: [..] Math.Vector2, subKind = FormSubKind.None)->*FormPolygon
{
    let form = Memory.new'FormPolygon()
    form.IForm.setup(capture)
    foreach pt in points do
        form.points.add(pt)
    form.subKind = subKind
    capture.forms.add(form)
    return form
}

func captmeTestAddDraw(capture: *Capture, points: [..] Math.Vector2, subKind = FormSubKind.None)->*FormDraw
{
    let form = Memory.new'FormDraw()
    form.IForm.setup(capture)
    foreach pt in points do
        form.points.add(pt)
    form.subKind = subKind
    capture.forms.add(form)
    return form
}

func captmeTestAddImage(capture: *Capture, x: f32, y: f32, width: f32, height: f32)->*FormImage
{
    let form = Memory.new'FormImage()
    form.IForm.setup(capture)
    form.IForm.setBaseForm(cast() x, cast() y, cast() width, cast() height)
    capture.forms.add(form)
    return form
}

func captmeTestDeleteForm(itf: IForm)
{
    Memory.delete(@dataof(itf), @kindof(itf))
}

func captmeTestTempCapturePath()->String
{
    let tempDir = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    return Path.combine(tempDir.toString(), "captme-${GUID64.new()}.captme")
}

func captmeTestCountNonZeroBytes(img: Image)->u64
{
    var count: u64
    let bytes = img.pixels.toSlice()
    foreach b in bytes
    {
        if b != 0 do
            count += 1
    }
    return count
}

func captmeTestPrimeGizmo(form: IForm, z: f32 = 1)
{
    var painter: Painter{fake: true}
    painter.begin()
    form.paintGizmo(&painter, z, .Selected)
    painter.end()
}

func captmeTestPrimeCaptureGizmo(capture: *Capture)
{
    capture.gizmo.rect = {0, 0, capture.width, capture.height}

    var painter: Painter{fake: true}
    painter.begin()
    capture.gizmo.paint(&painter, false)
    painter.end()
}

func captmeTestRegisterLocalEditorShortcuts(main: *MainWnd)
{
    main.registerAction'ActionSelection()
    main.registerAction'ActionMoveSel()
    main.registerAction'ActionAlign()
    main.registerAction'ActionUndo()
    main.registerAction'ActionZoom()

    main.registerKeyShortcut(.Control, .A, ActionSelection.SelectAll)
    main.registerKeyShortcut(.Control, .D, ActionSelection.DeSelectAll)
    main.registerKeyShortcut(.CtrlShift, .I, ActionSelection.InvertSelection)
    main.registerKeyShortcut(.Control, .Space, ActionSelection.Freeze)
    main.registerKeyShortcut(.Zero, .Delete, ActionSelection.DeleteSelection)
    main.registerKeyShortcut(.Control, .Z, ActionUndo.DoUndo)
    main.registerKeyShortcut(.Control, .Y, ActionUndo.DoRedo)
    main.registerKeyShortcut(.Shift, .Left, ActionMoveSel.Left1)
    main.registerKeyShortcut(.Shift, .Up, ActionMoveSel.Top1)
    main.registerKeyShortcut(.Shift, .Right, ActionMoveSel.Right1)
    main.registerKeyShortcut(.Shift, .Down, ActionMoveSel.Bottom1)
    main.registerKeyShortcut(.Zero, .Left, ActionMoveSel.Left)
    main.registerKeyShortcut(.Zero, .Up, ActionMoveSel.Top)
    main.registerKeyShortcut(.Zero, .Right, ActionMoveSel.Right)
    main.registerKeyShortcut(.Zero, .Down, ActionMoveSel.Bottom)
    main.registerKeyShortcut(.Zero, .Home, ActionAlign.SendToFront)
    main.registerKeyShortcut(.Zero, .End, ActionAlign.SendToBack)
    main.registerKeyShortcut(.Zero, .PageUp, ActionAlign.MoveForward)
    main.registerKeyShortcut(.Zero, .PageDown, ActionAlign.MoveBackward)
    main.registerKeyShortcut(.Control, .Add, ActionZoom.ZoomIn)
    main.registerKeyShortcut(.Control, .Subtract, ActionZoom.ZoomOut)
    main.registerKeyShortcut(.Control, .NumPad0, ActionZoom.Zoom1)
}

func captmeTestIndexedImage(w, h: s32)->Image
{
    var result = Image.create(w, h, .BGRA8)
    result.visitPixels()
    {
        let value = cast(u8) ((1 + x + y * 17) % 251)
        let green = cast(u8) ((cast(u32) value + 3) % 251)
        let blue  = cast(u8) ((cast(u32) value + 7) % 251)
        dref cast(*u32) pix = Color.fromArgb(255'u8, value, green, blue).argb
    }
    return result
}
