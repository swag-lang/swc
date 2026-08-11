#global if #command == Swag.CompilerCommand.Test

using Swag, Core

struct HeadlessFixture
{
    gui:      Gui.Testing.HeadlessHost
    main:     *MainWnd  = undefined
    editView: *EditView = undefined
    capture:  *Capture  = undefined
}

impl HeadlessFixture
{
    mtd setup(width = 900.0, height = 700.0, registerHeadlessCommands = false)
    {
        testUseScratchLibrary()

        .gui.setup(width, height)
        .gui.bindApplication(&g_App)

        // Same string wiring as `main`: the table, its embedded translations, and the resolver
        // the generated property rows go through. Registering again is a no-op.
        //
        // Both bundles get them. The host owns its own application, and that is the one a
        // language switch travels through; the module global gets them too, because the code
        // under test reads `g_App` directly.
        registerAppStrings(&g_App.resources)
        registerAppStrings(&.gui.app.resources)

        .main  = Wnd.create'MainWnd(&.gui.root, {x: 0, y: 0, width: width, height: height})
        g_Main = .main
        let renderer = .gui.app.renderer
        .main.icons.setup(renderer, captureIcons())
        .main.appIcon.set(renderer.addImage(Image.create(512, 512, .RGBA8)))
        .main.mdlFavorite  = &.main.mdlFormShape
        .main.mdlHighlight = &.main.mdlFormShape
        .main.mdlPixSel    = &.main.mdlFormShape
        .main.editWnd      = EditWnd.create(.main, .main)
        .main.editWnd.setPosition({x: 0, y: 0, width: width, height: height})
        .main.editWnd.editView.setPosition({x: 0, y: 0, width: width, height: height})

        let editWnd = .main.editWnd
        .editView = editWnd.editView!
        let localCapture = Memory.new'Capture()
        localCapture.width, localCapture.widthOrg   = 400
        localCapture.height, localCapture.heightOrg = 300
        localCapture.backImg = Image.create(400, 300, .BGRA8)
        .editView.setCapture(localCapture)
        .capture = localCapture

        if registerHeadlessCommands do
            .registerHeadlessCommands()
    }

    mtd registerHeadlessCommands()
    {
        testRegisterHeadlessCommands(.main)
    }

    mtd setupLibraryWnd()->*LibraryWnd
    {
        .main.libWnd      = Wnd.create'LibraryWnd(.main, {0, 0, 520, 420})
        .main.libWnd.main = .main
        .main.libWnd.registerActions()

        let scroll = Wnd.create'ScrollWnd(.main.libWnd, {0, 0, 520, 420})
        let view   = Wnd.create'LibraryView(scroll, {0, 0, 520, 420})
        view.libWnd    = .main.libWnd
        view.mainWnd   = .main
        view.scrollWnd = scroll
        scroll.setView(view)
        .main.libWnd.view = view
        return .main.libWnd
    }

    mtd shutdown()
    {
        .gui.shutdown()
        g_Main = null
    }
}

// Establishes the library a fixture works against.
//
// sCapture resolves it from the documents folder, which the sandbox already answers inside
// itself, so nothing here has to redirect anything. What it does do is refuse to run when the
// sandbox is not armed: these tests exercise capture actions that write real files through
// 'Library.newFileName', and outside a sandbox those land in the user's own library.
func testUseScratchLibrary()
{
    @assert(Env.isSandboxed())
    g_Library.rootFolder.clear()
    g_Library.defaultFolder.clear()
    discard catch Library.init()

    g_Library.files.clear()
    g_Library.onDeleteFile.clear()
    g_Library.loaded = false
}

func testMouse(kind: MouseEvent.Kind, button = Input.MouseButton.Left)->MouseEvent
{
    var evt = MouseEvent{kind: kind}
    evt.button = button
    return evt
}

func testAddShape(capture: *Capture, x: f32, y: f32, width: f32, height: f32, subKind = FormSubKind.None)->*FormShape
{
    let form = Memory.new'FormShape()
    form.IForm.setup(capture)
    form.IForm.setBaseForm(cast() x, cast() y, cast() width, cast() height)
    form.subKind = subKind
    capture.forms.add(form)
    return form
}

func testAddText(capture: *Capture, x: f32, y: f32, width: f32, height: f32)->*FormText
{
    let form = Memory.new'FormText()
    form.IForm.setup(capture)
    form.IForm.setBaseForm(cast() x, cast() y, cast() width, cast() height)
    capture.forms.add(form)
    return form
}

func testAddCallout(capture: *Capture, x: f32, y: f32, width: f32, height: f32)->*FormCallout
{
    let form = Memory.new'FormCallout()
    form.IForm.setup(capture)
    form.IForm.setBaseForm(cast() x, cast() y, cast() width, cast() height)
    form.tailX = x + width * 0.3
    form.tailY = y + height + 30
    capture.forms.add(form)
    return form
}

func testAddStep(capture: *Capture, x: f32, y: f32, width: f32, height: f32)->*FormStep
{
    let form = Memory.new'FormStep()
    form.IForm.setup(capture)
    form.IForm.setBaseForm(cast() x, cast() y, cast() width, cast() height)
    capture.forms.add(form)
    return form
}

func testAddLine(capture: *Capture, xa: f32, ya: f32, xb: f32, yb: f32, subKind = FormSubKind.None)->*FormLine
{
    let form = Memory.new'FormLine()
    form.IForm.setup(capture)
    form.IForm.setBaseForm(cast() xa, cast() ya, cast(s32) (xb - xa), cast(s32) (yb - ya))
    form.subKind = subKind
    capture.forms.add(form)
    return form
}

func testAddArrow(capture: *Capture, xa: f32, ya: f32, xb: f32, yb: f32, subKind = FormSubKind.None)->*FormArrow
{
    let form = Memory.new'FormArrow()
    form.IForm.setup(capture)
    form.IForm.setBaseForm(cast() xa, cast() ya, cast(s32) (xb - xa), cast(s32) (yb - ya))
    form.subKind = subKind
    capture.forms.add(form)
    return form
}

func testAddPolygon(capture: *Capture, points: [..] Math.Vector2, subKind = FormSubKind.None)->*FormPolygon
{
    let form = Memory.new'FormPolygon()
    form.IForm.setup(capture)
    for pt in points do
        form.points.add(pt)
    form.subKind = subKind
    capture.forms.add(form)
    return form
}

func testAddDraw(capture: *Capture, points: [..] Math.Vector2, subKind = FormSubKind.None)->*FormDraw
{
    let form = Memory.new'FormDraw()
    form.IForm.setup(capture)
    for pt in points do
        form.points.add(pt)
    form.subKind = subKind
    capture.forms.add(form)
    return form
}

func testAddImage(capture: *Capture, x: f32, y: f32, width: f32, height: f32)->*FormImage
{
    let form = Memory.new'FormImage()
    form.IForm.setup(capture)
    form.IForm.setBaseForm(cast() x, cast() y, cast() width, cast() height)
    capture.forms.add(form)
    return form
}

func testDeleteForm(itf: IForm)
{
    Memory.delete(@dataof(itf), @kindof(itf))
}

func testTempCapturePath()->String
{
    return Gui.Testing.tempFilePath("scapture-", ".scapture")
}

func testPrimeGizmo(form: IForm, z: f32 = 1)
{
    var painter: Painter
    painter.begin(layoutOnly: true)
    form.paintGizmo(&painter, z, .Selected)
    painter.end()
}

func testPrimeCaptureGizmo(capture: *Capture)
{
    capture.gizmo.rect = {0, 0, capture.width, capture.height}

    var painter: Painter
    painter.begin(layoutOnly: true)
    capture.gizmo.paint(&painter, false)
    painter.end()
}

func testRegisterHeadlessActions(main: *MainWnd)
{
    main.registerAction'ActionGlobal()
    main.registerAction'ActionSelection()
    main.registerAction'ActionMoveSel()
    main.registerAction'ActionAlign()
    main.registerAction'ActionGroup()
    main.registerAction'ActionUndo()
    main.registerAction'ActionZoom()
    main.registerAction'ActionPixSel()
    main.registerAction'ActionToolMode()
    main.registerAction'ActionImage()
    main.registerAction'ActionFlatten()
    main.registerAction'ActionQuickStyle()
    main.registerAction'ActionEdit()
    main.registerAction'ActionView()
    main.registerAction'ActionCaptureDelay()
    main.registerAction'ActionRecentSize()
}

func testRegisterHeadlessShortcuts(main: *MainWnd)
{
    main.registerKeyShortcut(.Control, .A, ActionSelection.SelectAll)
    main.registerKeyShortcut(.Control, .D, ActionSelection.DeSelectAll)
    main.registerKeyShortcut(.CtrlShift, .I, ActionSelection.InvertSelection)
    main.registerKeyShortcut(.Control, .Space, ActionSelection.Freeze)
    main.registerKeyShortcut(.None, .Delete, ActionSelection.DeleteSelection)
    main.registerKeyShortcut(.Control, .Z, ActionUndo.DoUndo)
    main.registerKeyShortcut(.Control, .Y, ActionUndo.DoRedo)
    main.registerKeyShortcut(.Shift, .Left, ActionMoveSel.Left1)
    main.registerKeyShortcut(.Shift, .Up, ActionMoveSel.Top1)
    main.registerKeyShortcut(.Shift, .Right, ActionMoveSel.Right1)
    main.registerKeyShortcut(.Shift, .Down, ActionMoveSel.Bottom1)
    main.registerKeyShortcut(.None, .Left, ActionMoveSel.Left)
    main.registerKeyShortcut(.None, .Up, ActionMoveSel.Top)
    main.registerKeyShortcut(.None, .Right, ActionMoveSel.Right)
    main.registerKeyShortcut(.None, .Down, ActionMoveSel.Bottom)
    main.registerKeyShortcut(.Control, .G, ActionGroup.Group)
    main.registerKeyShortcut(.CtrlShift, .G, ActionGroup.Ungroup)
    main.registerKeyShortcut(.None, .Home, ActionAlign.SendToFront)
    main.registerKeyShortcut(.None, .End, ActionAlign.SendToBack)
    main.registerKeyShortcut(.None, .PageUp, ActionAlign.MoveForward)
    main.registerKeyShortcut(.None, .PageDown, ActionAlign.MoveBackward)
    main.registerKeyShortcut(.Control, .Add, ActionZoom.ZoomIn)
    main.registerKeyShortcut(.Control, .Subtract, ActionZoom.ZoomOut)
    main.registerKeyShortcut(.Control, .NumPad0, ActionZoom.Zoom1)
}

func testRegisterHeadlessCommands(main: *MainWnd)
{
    testRegisterHeadlessActions(main)
    testRegisterHeadlessShortcuts(main)
}

func testRegisterIoActions(main: *MainWnd)
{
    main.registerAction'ActionCopyPaste()
    main.registerAction'ActionFile()
    main.registerAction'ActionCapture()
}

func testRegisterLocalEditorShortcuts(main: *MainWnd)
{
    testRegisterHeadlessCommands(main)
}

func testDate(day: u16)->Time.DateTime
{
    return {year: 2026, month: 1, day: day}
}

func testAddLibraryItem(view: *LibraryView, name: String, size: u64, day: u16, linked: string = "", linkedUpToDate = true, title: string = "")->*LibraryItem
{
    let it = view.allItems.addNew()
    it.fi.fullname      = name
    it.fi.size          = size
    it.fi.lastWriteTime = testDate(day)
    it.visible          = true
    it.loaded           = true
    it.width            = 100
    it.height           = 100
    it.rect             = {cast(f32) view.items.count * 60, 0, 50, 50}

    let capture = Memory.new'Capture()
    capture.linkedImage    = linked
    capture.linkedUpToDate = linkedUpToDate
    capture.title          = title
    it.capture             = capture

    view.items.add(it)
    return it
}
