#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Gui, Pixel

// Keep each journey on the native desktop, with the same startup wiring and private library
// that the shipped application uses. The fixture owns every file it creates.
struct CaptureJourney
{
    late app: *Application
    root:     String
    late surface: *Surface
    late main:    *MainWnd
    watch:    Time.Stopwatch
    savedKeepRatio: bool
    savedResizeMode: u64
    savedWidth, savedHeight: s32
}

impl CaptureJourney
{
    mtd setup()
    {
        .app = &g_App
        .savedKeepRatio = g_KeepRatio
        .savedResizeMode = g_ResizeMode
        .savedWidth = g_Width
        .savedHeight = g_Height
        testUseScratchLibrary()
        .root = Testing.tempFilePath("capture-journey-", "")
        expect Directory.create(.root)
        expect g_Library.setFolder(.root)

        let statePath = Path.combine(.root, "settings.scc")
        .app.setStatePath(statePath)
        .app.setAppIcon(expect Image.decode(".png", AppIcon))
        registerAppStrings(&.app.resources)
        .surface = expect .app.createSurface(40, 40, 1100, 760, surfaceId: "capture-test-journey")
        .surface.setTitle(ProductName)
        .main = MainWnd.create(.surface.wnd)
        .surface.show()
        // Application.run sends this startup event before its first frame.
        var firstFrame = FrameEvent{firstFrame: true}
        .surface.wnd.view.sendEvent(&firstFrame)
        .watch.start()
        let main = .main
        .waitFor("startup", func|main|()->bool => main.recentWnd.loadDone and
                                                  not main.quickWnd.qsHighlight.forms.isEmpty())
    }

    mtd shutdown()
    {
        .main.libWnd.requestClose()
        .surface.destroy()
        Swag.drop(&g_Library, 1)
        Swag.init(&g_Library, 1)
        discard catch Directory.delete(.root, recurse: true)
        g_KeepRatio = .savedKeepRatio
        g_ResizeMode = .savedResizeMode
        g_Width = .savedWidth
        g_Height = .savedHeight
        g_Main = null
        Swag.drop(&g_App, 1)
        Swag.init(&g_App, 1)
    }

    // The native event loop yields on idle turns; readiness comes from the task's visible state.
    mtd waitFor(stage: string, ready: func||()->bool)
    {
        Console.println("Swag Capture journey: ", stage)
        while true
        {
            .app.runFrame()
            Swag.require(.surface.renderFailure.isEmpty(), .surface.renderFailure.toString())
            if ready() do
                return
            if .watch.elapsedMilliseconds() > 38_000
            {
                Console.println("ready=", ready(), " animations=", .app.animator.activeCount(),
                                " renderFailure=", .surface.renderFailure)
                Swag.require(false, Format.toString("Swag Capture journey timed out at %", stage))
            }
        }
    }

    mtd openLibrary(count: u64)
    {
        .main.sendCommandEvent(ActionGlobal.ShowLibrary)
        let main = .main
        let ready = func|main, count|()->bool
        {
            let view = main.libWnd.view
            if not main.libraryMode or view.allItems.count != count or g_UpdatingLib do
                return false
            for item in view.allItems where not item!.loaded do
                return false
            return true
        }
        .waitFor("library loaded", ready)
    }

    mtd newCapture(width = 96, height = 64)->String
    {
        .main.newCapture(Testing.indexedImage(width, height), sourceKind: .Clipboard)
        let capture = unwrap .main.editWnd.getCapture()
        var path = String.from(capture.file)
        .waitFor("new capture saved", func|&path|()->bool => File.exists(path))
        return path
    }

    // Send the same tool command and editor pointer events as a drag on the visible image.
    mtd drawForm(command: WndId, mode: EditMode, start, end: Math.Point)
    {
        .main.sendCommandEvent(command)
        Swag.require(.main.editMode == mode)

        let view    = .main.editWnd.editView
        let capture = unwrap view.capture
        let count   = capture.forms.count
        .dragSurfacePoints(.surfacePoint(start), .surfacePoint(end), hover: false)
        .waitFor("annotation drawn", func|capture, count|()->bool => capture.forms.count == count + 1)
    }

    mtd dragImage(start, end: Math.Point)
    {
        .dragSurfacePoints(.surfacePoint(start), .surfacePoint(end))
    }

    mtd dragSelection(start, end: Math.Point)
    {
        // The lasso consumes view-local coordinates relative to Capture.paintRect.
        let view = .main.editWnd.editView
        let capture = unwrap view.capture
        let origin = Math.Point{capture.paintRect.x - view.scrollPos.x,
                                capture.paintRect.y - view.scrollPos.y}
        let first = view.localToSurface(origin + start * view.zoom)
        let last = view.localToSurface(origin + end * view.zoom)
        .dragSurfacePoints(first, last, hover: false)
    }

    mtd dragSurfacePoints(first, last: Math.Point, hover = true)
    {
        let view = .main.editWnd.editView
        let target: IWnd = view
        var pointer = MouseEvent{kind: .Move, button: .Left, surfacePos: first}
        if hover do
            target.onMouseEvent(&pointer)
        pointer.kind = .Pressed
        target.onMouseEvent(&pointer)
        pointer.kind       = .Move
        pointer.surfacePos = last
        target.onMouseEvent(&pointer)
        pointer.kind = .Released
        target.onMouseEvent(&pointer)
    }

    mtd surfacePoint(point: Math.Point)->Math.Point
    {
        let view   = .main.editWnd.editView
        let rect   = view.getCaptureRect()
        let origin = Math.Point{rect.x - view.scrollPos.x, rect.y - view.scrollPos.y}
        return view.localToSurface(origin + point * view.zoom)
    }

    // Answer a size sheet through its labelled edit boxes during the modal event loop.
    mtd changeImageSize(command: WndId, width, height: s32)
    {
        var answered: bool
        let app = .app
        g_KeepRatio = false
        defer app.sigFrame.clear()
        app.sigFrame += func|app, width, height, answered = &answered|(_)
        {
            if answered[] or app.surfaces.count < 2 do
                return
            let dialog = assume cast(*FormDlg, app.surfaces.back().view())
            var foundWidth, foundHeight: bool
            for row in dialog.form.rows
            {
                if row.field is EditBox as edit
                {
                    if row.label.name.raw == appStrings().ui_Width
                    {
                        edit.setText(Format.toString("%", width))
                        foundWidth = true
                    }
                    elif row.label.name.raw == appStrings().ui_Height
                    {
                        edit.setText(Format.toString("%", height))
                        foundHeight = true
                    }
                }
            }
            Swag.require(foundWidth and foundHeight)
            answered[] = true
            Swag.require(dialog.closeWithResult(Dialog.BtnOk))
        }

        .main.sendCommandEvent(command)
        Swag.require(answered)
    }

    mtd confirmCommand(command, answer: WndId)
    {
        var answered: bool
        let app = .app
        defer app.sigFrame.clear()
        app.sigFrame += func|app, answer, answered = &answered|(_)
        {
            if answered[] or app.surfaces.count < 2 do
                return
            let dialog = assume cast(*Dialog, app.surfaces.back().view())
            answered[] = true
            Swag.require(dialog.closeWithResult(answer))
        }
        .main.sendCommandEvent(command)
        Swag.require(answered)
    }

    mtd drawPolygon(first, second, third, fourth: Math.Point)
    {
        .main.sendCommandEvent(ActionToolMode.Poly)
        Swag.require(.main.editMode == .Polygon)
        let view    = .main.editWnd.editView
        let capture = unwrap view.capture
        let count   = capture.forms.count
        let target: IWnd = view
        var pointer = MouseEvent{kind: .Pressed, button: .Left, surfacePos: .surfacePoint(first)}
        target.onMouseEvent(&pointer)
        pointer.kind       = .Move
        pointer.surfacePos = .surfacePoint(second)
        target.onMouseEvent(&pointer)
        pointer.kind = .Released
        target.onMouseEvent(&pointer)

        pointer.kind       = .Pressed
        pointer.surfacePos = .surfacePoint(third)
        target.onMouseEvent(&pointer)
        pointer.kind = .Released
        target.onMouseEvent(&pointer)

        pointer.kind       = .DoubleClick
        pointer.surfacePos = .surfacePoint(fourth)
        target.onMouseEvent(&pointer)
        .waitFor("polygon drawn", func|capture, count|()->bool => capture.forms.count == count + 1)
    }
}
