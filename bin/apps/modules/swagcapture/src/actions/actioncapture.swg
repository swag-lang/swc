using Gui

// The commands that take a screenshot: the capture modes, the per-monitor captures, and where
// the result goes.
struct ActionCapture {}

impl ActionCapture
{
    newCmdId("DoIt")
    newCmdId("Repeat")
    newCmdId("Area")
    newCmdId("Record")
    newCmdId("CancelRecording")
    newCmdId("LastArea")
    newCmdId("FullScreen")
    newCmdId("ActiveWnd")
    newCmdId("HideEditor")
    newCmdId("CaptureCursor")
    newCmdId("ToInPlace")
    newCmdId("ToEditor")
    newCmdId("ToClipboard")

    // The per-monitor commands are minted from the live monitor list rather than
    // declared one by one, so the fifth monitor of a machine is as addressable as the
    // first. A `WndId` is a borrowed string that a menu item and a queued command event
    // both outlive, so the ids are cached here and kept for the process lifetime; there
    // is one per monitor, so the cache stays a handful of entries.
    private var screenIds: Array'String

    // Returns the command id capturing the monitor at `index` in `MainWnd.monitors`.
    func screenId(index: u64)->WndId
    {
        if screenIds.count <= index
        {
            screenIds.reserve(index + 1)
            while screenIds.count <= index do
                screenIds.add(Format.toString("%.Screen%", #scopename, screenIds.count))
        }

        return screenIds[index]
    }

    // Returns the monitor `id` captures, or `Swag.U64.Max` when it captures no monitor.
    func screenIndex(id: WndId)->u64
    {
        for &minted, index in screenIds where minted[] == id do
            return index
        return Swag.U64.Max
    }
}

impl IActionUI for ActionCapture
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main = mainWndOf(cxt)

        // A per-monitor command names its monitor by index. The entry stays visible but
        // disabled when that monitor was disconnected after the menu was built.
        let monitor = ActionCapture.screenIndex(cxt.id)
        if monitor != Swag.U64.Max
        {
            evt.updatedFields |= .Name | .Icon | .Disabled
            evt.disabled      = monitor >= main.monitors.count
            evt.name          = evt.disabled
                                ? Format.toString(appStrings().act_CaptureMonitor, monitor + 1)
                                : Format.toString(appStrings().act_CaptureMonitorSize,
                                                  monitor + 1,
                                                  main.monitors[monitor].bounds.width,
                                                  main.monitors[monitor].bounds.height)
            evt.icon = main.icon(.Monitor)
            return true
        }

        switch cxt.id
        {
        case .DoIt:
            evt.updatedFields |= .Name | .Icon
            evt.name = appStrings().ui_MenuCapture
            evt.icon = main.icon(.Capture)

        // The capture control of the top strip names the last capture taken, and takes it again.
        case .Repeat:
            let last = main.sendComputeCommandStateEvent(main.lastCaptureCommand())
            evt.updatedFields |= .Name | .Icon | .Disabled
            evt.name          = last.name
            evt.icon          = last.icon
            evt.disabled      = last.disabled

        case .Area:
            evt.updatedFields |= .Name | .Icon
            evt.name = appStrings().act_CaptureArea
            evt.icon = main.icon(.CaptureArea)

        case .Record:
            evt.updatedFields |= .Name | .Icon
            evt.name = g_Recorder ? appStrings().act_StopRecording : appStrings().act_RecordAnimation
            evt.icon = main.theme().icon(g_Recorder ? .Stop : .Play)

        case .CancelRecording:
            evt.updatedFields |= .Name | .Icon | .Disabled
            evt.name          = appStrings().act_CancelRecording
            evt.icon          = main.theme().icon(.WndClose)
            evt.disabled      = g_Recorder == null

        case .LastArea:
            evt.updatedFields |= .Name | .Icon
            evt.name = appStrings().act_CaptureLastArea
            evt.icon = main.icon(.LastArea)

        case .FullScreen:
            evt.updatedFields |= .Name | .Icon
            evt.name = appStrings().act_CaptureFullScreen
            evt.icon = main.icon(.FullScreen)

        case .ActiveWnd:
            evt.updatedFields |= .Name | .Icon
            evt.name = appStrings().act_CaptureActiveWindow
            evt.icon = main.icon(.ActiveWindow)

        case .HideEditor:
            evt.updatedFields |= .Name | .Checked | .Icon
            evt.icon          = main.theme().icon(.Minimize)
            evt.name          = appStrings().act_HideEditorBefore
            evt.checked       = main.captureOptions.hideEditorBefore
            evt.accepted      = true

        case .CaptureCursor:
            evt.updatedFields |= .Name | .Checked | .Icon
            evt.icon          = main.icon(.Select)
            evt.name          = appStrings().act_CaptureCursor
            evt.checked       = main.captureOptions.captureCursor
            evt.accepted      = true

        case .ToInPlace:
            evt.updatedFields |= .Name | .Checked | .Icon
            evt.icon          = main.theme().icon(.Edit)
            evt.name          = appStrings().act_EditInPlace
            evt.checked       = main.captureOptions.inPlaceEdit
            evt.accepted      = true

        case .ToEditor:
            evt.updatedFields |= .Name | .Checked | .Icon
            evt.icon          = main.theme().icon(.OpenExternal)
            evt.name          = appStrings().act_SendToEditor
            evt.checked       = main.captureOptions.sendToEditor
            evt.accepted      = true

        case .ToClipboard:
            evt.updatedFields |= .Name | .Checked | .Icon
            evt.icon          = main.theme().icon(.Copy)
            evt.name          = appStrings().act_SendToClipboard
            evt.checked       = main.captureOptions.sendToClipboard
            evt.accepted      = true
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = mainWndOf(cxt)

        let monitor = ActionCapture.screenIndex(cxt.id)
        if monitor != Swag.U64.Max
        {
            main.lastCapture = cxt.id
            main.captureScreen(.Monitor, monitor)
            return true
        }

        // The capture control of the top strip follows the last capture taken.
        switch cxt.id
        {
        case .Repeat:
            main.sendCommandEvent(main.lastCaptureCommand())
            return true

        case .Area, .Record, .LastArea, .FullScreen, .ActiveWnd:
            if not g_Recorder do
                main.lastCapture = cxt.id
        }

        switch cxt.id
        {
        case .DoIt:
            main.captureScreen(.Area)

        case .Area:
            main.captureScreen(.Area)

        case .Record:
            main.recordScreen()

        case .CancelRecording:
            if g_Recorder do
                g_Recorder!.cancel()

        case .LastArea:
            main.captureScreen(.LastArea)

        case .FullScreen:
            main.captureScreen(.FullScreen)

        case .ActiveWnd:
            main.captureScreen(.ActiveWindow)

        case .ToInPlace:
            main.captureOptions.inPlaceEdit = not main.captureOptions.inPlaceEdit

        case .HideEditor:
            main.captureOptions.hideEditorBefore = not main.captureOptions.hideEditorBefore

        case .CaptureCursor:
            main.captureOptions.captureCursor = not main.captureOptions.captureCursor

        case .ToEditor:
            main.captureOptions.sendToEditor = not main.captureOptions.sendToEditor

        case .ToClipboard:
            main.captureOptions.sendToClipboard = not main.captureOptions.sendToClipboard
        }

        return true
    }
}

impl MainWnd
{
    // Opens `img` in the editor as a new capture, or as `from` when given, gives it a
    // library file, saves it, and adds it to the recent strip. `linked` names the
    // image file the capture came from.
    mtd newCapture(img: Image, linked: string = "", from: *Capture? = null, sourceKind = CaptureSourceKind.Unknown)
    {
        if not img.isValid() do
            return

        var capture = from
        if not capture
        {
            var resolvedSourceKind = sourceKind
            if resolvedSourceKind == .Unknown do
                resolvedSourceKind = linked.count == 0 ? .Clipboard : .ImageFile

            with capture = Memory.new'Capture()
            {
                .width, .widthOrg   = img.width
                .height, .heightOrg = img.height
                .backImg            = img
                .sourceKind         = resolvedSourceKind
                .capturedAt         = Time.DateTime.now()
            }
        }

        // A recording already has its file, named like the frame file written beside it.
        with capture
        {
            .changed     = true
            .linkedImage = linked
            if not .isTimed() do
                .file = Library.newFileName()
        }

        .editWnd.editView.setCapture(capture)
        .editWnd.editView.zoomToFit(false)

        capture.computePreview()
        .recentWnd.addRecent(capture.file, capture.preview, linked: linked, duration: capture.timeline.duration)
        .recentWnd.recentView.selected = 0

        .saveCapture(capture)
        g_Library.addFile(capture.file)

        // Force edition mode
        if .libraryMode
        {
            .swapLibraryMode()
            .updateState()
        }
    }

    // Returns the command of the last capture taken, the area capture before the first; a monitor
    // that is no longer connected falls back to it too.
    mtd lastCaptureCommand()->WndId
    {
        if .lastCapture.isEmpty() do
            return ActionCapture.Area

        // The per-monitor commands are minted from the monitor list; mint them before matching.
        for index in .monitors.count do
            discard ActionCapture.screenId(index)
        let monitor = ActionCapture.screenIndex(.lastCapture)
        if monitor != Swag.U64.Max do
            return ActionCapture.screenId(monitor)

        for id in [ActionCapture.Area, ActionCapture.Record, ActionCapture.LastArea, ActionCapture.FullScreen, ActionCapture.ActiveWnd] where .lastCapture == id do
            return id
        return ActionCapture.Area
    }

    // Takes a picture of the screen in `mode`, `monitorIndex` naming the monitor of `.Monitor`.
    mtd captureScreen(mode: CaptureMode, monitorIndex: u64 = 0)
    {
        g_CaptureMedia = .Picture
        catch screenShot(me, mode, monitorIndex) { MessageDlg.error(unwrap .surface, appStrings().msg_FailedCaptureScreen, Swag.err) }
    }

    // Records an animation of an area chosen on the screen, or ends the recording in progress:
    // the command that starts a recording stops it.
    mtd recordScreen()
    {
        if g_Recorder
        {
            g_Recorder!.stop()
            return
        }

        g_CaptureMedia = .Animation
        catch screenShot(me, .Area) { MessageDlg.error(unwrap .surface, appStrings().msg_FailedRecordScreen, Swag.err) }
    }
}
