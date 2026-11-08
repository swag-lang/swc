#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Gui, Pixel

// Keep each journey on the native desktop, with the same startup wiring and private library
// that the shipped application uses. The fixture owns every file it creates.
struct CaptureJourney
{
    app:      Application
    root:     String
    late surface: *Surface
    late main:    *MainWnd
    watch:    Time.Stopwatch
}

impl CaptureJourney
{
    mtd setup()
    {
        testUseScratchLibrary()
        .root = Testing.tempFilePath("capture-journey-", "")
        expect Directory.create(.root)
        expect g_Library.setFolder(.root)

        let statePath = Path.combine(.root, "settings.scc")
        g_App.setStatePath(statePath)
        .app.setStatePath(statePath)
        .app.setAppIcon(expect Image.decode(".png", AppIcon))
        registerAppStrings(&g_App.resources)
        registerAppStrings(&.app.resources)
        .surface = expect .app.createSurface(40, 40, 1100, 760, surfaceId: "capture-test-journey")
        .surface.setTitle(ProductName)
        .main = MainWnd.create(.surface.wnd)
        .surface.show()
        .watch.start()
        let main = .main
        .waitFor("startup", func|main|()->bool => main.recentWnd.loadDone)
    }

    mtd shutdown()
    {
        .main.libWnd.requestClose()
        .surface.destroy()
        Swag.drop(&g_Library, 1)
        Swag.init(&g_Library, 1)
        discard catch Directory.delete(.root, recurse: true)
        g_Main = null
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

    mtd newCapture()->String
    {
        .main.newCapture(Testing.indexedImage(96, 64), sourceKind: .Clipboard)
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
        let rect    = view.getCaptureRect()
        let origin  = Math.Point{rect.x - view.scrollPos.x, rect.y - view.scrollPos.y}
        let first   = view.localToSurface(origin + start * view.zoom)
        let last    = view.localToSurface(origin + end * view.zoom)
        let target: IWnd = view
        var pointer = MouseEvent{kind: .Pressed, button: .Left, surfacePos: first}
        target.onMouseEvent(&pointer)
        pointer.kind       = .Move
        pointer.surfacePos = last
        target.onMouseEvent(&pointer)
        pointer.kind = .Released
        target.onMouseEvent(&pointer)

        .waitFor("annotation drawn", func|capture, count|()->bool => capture.forms.count == count + 1)
    }
}
