#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Gui, Pixel

enum RecordingJourneyEnd
{
    Stop
    Cancel
    CancelCountdown
    PauseThenStop
}

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
    started: bool
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
        g_Library.defaultFolder = .root
        expect g_Library.setFolder(.root)

        .app.setStatePath(Library.getStatePath())
        .app.setAppIcon(expect Image.decode(".png", AppIcon))
        registerAppStrings(&.app.resources)
        .surface = expect .app.createSurface(40, 40, 1100, 760, surfaceId: "capture-test-journey")
        .surface.setTitle(ProductName)
        .main = MainWnd.create(.surface.wnd)
        .started = true
        .surface.show()
        // Application.run sends this startup event before its first frame.
        var firstFrame = FrameEvent{firstFrame: true}
        .surface.wnd.view.sendEvent(&firstFrame)
        .watch.start()
        let main = .main
        .waitFor("startup", func|main|()->bool => main.recentWnd.loadDone and
                                                  not main.quickWnd.qsHighlight.forms.isEmpty())
    }

    mtd opDrop()
    {
        if not .started do
            return
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
                Console.println("libraryMode=", .main.libraryMode, " items=", .main.libWnd.view.allItems.count,
                                " updating=", g_UpdatingLib)
                for item in .main.libWnd.view.allItems do
                    Console.println("item=", item!.fi.fullName, " loaded=", item.loaded)
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

    mtd selectScreenArea(overlay: *CaptureRectWnd)
    {
        var pointer = MouseEvent{kind: .Pressed, button: .Left, surfacePos: {24, 24}}
        overlay.sendEvent(&pointer)
        pointer.kind       = .Move
        pointer.surfacePos = {120, 88}
        overlay.sendEvent(&pointer)
        pointer.kind = .Released
        overlay.sendEvent(&pointer)
    }

    // Take an area picture through the native selector and open it in the editor.
    mtd captureScreenPicture()
    {
        let app = .app
        let main = .main
        var selected: bool
        main.captureOptions.inPlaceEdit = false
        main.captureOptions.sendToEditor = true
        defer app.sigFrame.clear()
        app.sigFrame += func|journey = me, selected = &selected|(_)
        {
            if selected[] do
                return
            Swag.require(journey.watch.elapsedMilliseconds() < 38_000, "picture selector timed out")
            for surface in journey.app.surfaces
            {
                if surface.view() is CaptureRectWnd as overlay
                {
                    journey.selectScreenArea(overlay)
                    selected[] = true
                    return
                }
            }
        }

        main.sendCommandEvent(ActionCapture.Area)
        app.runFrame()
        Swag.require(selected)
        Swag.require(main.editWnd.getCapture() != null)
    }

    // Cancel a selected picture from the in-place editor before it becomes a capture.
    mtd cancelInPlacePicture()
    {
        let app = .app
        let main = .main
        var stage: u32
        main.captureOptions.inPlaceEdit = true
        defer app.sigFrame.clear()
        app.sigFrame += func|journey = me, stage = &stage|(_)
        {
            Swag.require(journey.watch.elapsedMilliseconds() < 38_000, "in-place picture journey timed out")
            if stage[] == 0
            {
                for surface in journey.app.surfaces
                {
                    if surface.view() is CaptureRectWnd as overlay
                    {
                        journey.selectScreenArea(overlay)
                        stage[] = 1
                        return
                    }
                }
            }
            elif stage[] == 1
            {
                for surface in journey.app.surfaces
                {
                    if surface.view() is InPlaceEditWnd as editor
                    {
                        var key = KeyEvent{kind: .Pressed, key: .Escape, modifiers: .None}
                        editor.sendEvent(&key)
                        Swag.require(key.accepted)
                        stage[] = 2
                        return
                    }
                }
            }
        }

        main.sendCommandEvent(ActionCapture.Area)
        app.runFrame()
        Swag.require(stage == 2 and app.surfaces.count == 1)
    }

    // Select a small screen area, start recording from the in-place editor, then use the
    // recording pill. Wait for written frames before ending it.
    mtd recordAnimation(ending: RecordingJourneyEnd)
    {
        var stage: u32
        var pausedCount: u64
        let main = .main
        let app  = .app
        let watch = &.watch
        defer app.sigFrame.clear()

        main.captureOptions.recordCountdown = ending == .CancelCountdown
        main.captureOptions.captureCursor   = false
        app.sigFrame += func|journey = me, ending, watch, stage = &stage, pausedCount = &pausedCount|(_)
        {
            Swag.require(watch[].elapsedMilliseconds() < 38_000, "recording journey timed out")

            if stage[] == 0
            {
                for surface in g_App.surfaces
                {
                    if surface.view() is CaptureRectWnd as overlay
                    {
                        journey.selectScreenArea(overlay)
                        stage[] = 1
                        return
                    }
                }
            }

            if stage[] == 1
            {
                for surface in g_App.surfaces
                {
                    if surface.view() is InPlaceEditWnd as editor
                    {
                        var key = KeyEvent{kind: .Pressed, key: .Return, modifiers: .None}
                        editor.sendEvent(&key)
                        Swag.require(key.accepted)
                        stage[] = 2
                        return
                    }
                }
            }

            if stage[] == 2 and g_Recorder
            {
                let recorder = unwrap g_Recorder
                let hud = unwrap recorder.hud
                let count = recorder.writer.frameCount()
                if ending == .CancelCountdown and recorder.state == .Counting
                {
                    stage[] = 5
                    hud.cancelButton.sigPressed.call(hud.cancelButton)
                    return
                }
                elif ending == .PauseThenStop and count >= 1
                {
                    pausedCount[] = count
                    stage[] = 3
                    hud.pauseButton.sigPressed.call(hud.pauseButton)
                    return
                }
                elif ending != .PauseThenStop and ending != .CancelCountdown and count >= 2
                {
                    stage[] = 5
                    let button = ending == .Cancel ? hud.cancelButton : hud.stopButton
                    button.sigPressed.call(button)
                    return
                }
            }

            if stage[] == 3 and g_Recorder
            {
                let recorder = unwrap g_Recorder
                Swag.require(recorder.state == .Paused)
                let hud = unwrap recorder.hud
                stage[] = 4
                hud.pauseButton.sigPressed.call(hud.pauseButton)
                return
            }

            if stage[] == 4 and g_Recorder and g_Recorder!.writer.frameCount() > pausedCount[]
            {
                let hud = unwrap g_Recorder!.hud
                stage[] = 5
                hud.stopButton.sigPressed.call(hud.stopButton)
            }
        }

        main.sendCommandEvent(ActionCapture.Record)
        app.runFrame()
        Swag.require(stage == 5)
        Swag.require(g_Recorder == null)
        Swag.require(app.surfaces.count == 1)
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
        .dragSurfacePoints(.surfacePoint(start), .surfacePoint(end), hover: false)
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
