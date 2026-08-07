using Gui

struct ActionCapture {}

impl ActionCapture
{
    newCmdId("DoIt")
    newCmdId("Area")
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
        for &minted, [index] in screenIds where minted == id do
            return index
        return Swag.U64.Max
    }
}

impl IActionUI for ActionCapture
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main = cast(*MainWnd) cxt.wnd!

        // A per-monitor command names its monitor by index. The entry stays visible but
        // disabled when that monitor was disconnected after the menu was built.
        let monitor = ActionCapture.screenIndex(cxt.id)
        if monitor != Swag.U64.Max
        {
            evt.updatedFields |= .Name | .Icon | .Disabled
            evt.disabled      = monitor >= main.monitors.count
            evt.name          = evt.disabled ? Format.toString(appStrings().act_CaptureMonitor, monitor) : Format.toString(appStrings().act_CaptureMonitorSize, monitor, main.monitors[monitor].bounds.width, main.monitors[monitor].bounds.height)
            evt.icon          = main.icon(.Monitor)
            return true
        }

        switch cxt.id
        {
        case .DoIt:
            evt.updatedFields |= .Name | .Icon
            evt.name          = appStrings().ui_MenuCapture
            evt.icon          = main.icon(.Capture, RailGlyphSize)

        case .Area:
            evt.updatedFields |= .Name | .Icon
            evt.name          = appStrings().act_CaptureArea
            evt.icon          = main.icon(.CaptureArea)

        case .LastArea:
            evt.updatedFields |= .Name | .Icon
            evt.name          = appStrings().act_CaptureLastArea
            evt.icon          = main.icon(.LastArea)

        case .FullScreen:
            evt.updatedFields |= .Name | .Icon
            evt.name          = appStrings().act_CaptureFullScreen
            evt.icon          = main.icon(.FullScreen)

        case .ActiveWnd:
            evt.updatedFields |= .Name | .Icon
            evt.name          = appStrings().act_CaptureActiveWindow
            evt.icon          = main.icon(.ActiveWindow)

        case .HideEditor:
            evt.updatedFields |= .Name | .Checked
            evt.name          = appStrings().act_HideEditorBefore
            evt.checked       = main.captureOptions.hideEditorBefore
            evt.accepted      = true

        case .CaptureCursor:
            evt.updatedFields |= .Name | .Checked
            evt.name          = appStrings().act_CaptureCursor
            evt.checked       = main.captureOptions.captureCursor
            evt.accepted      = true

        case .ToInPlace:
            evt.updatedFields |= .Name | .Checked
            evt.name          = appStrings().act_EditInPlace
            evt.checked       = main.captureOptions.inPlaceEdit
            evt.accepted      = true

        case .ToEditor:
            evt.updatedFields |= .Name | .Checked
            evt.name          = appStrings().act_SendToEditor
            evt.checked       = main.captureOptions.sendToEditor
            evt.accepted      = true

        case .ToClipboard:
            evt.updatedFields |= .Name | .Checked
            evt.name          = appStrings().act_SendToClipboard
            evt.checked       = main.captureOptions.sendToClipboard
            evt.accepted      = true
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = cast(*MainWnd) cxt.wnd!

        let monitor = ActionCapture.screenIndex(cxt.id)
        if monitor != Swag.U64.Max
        {
            main.captureScreen(.Monitor, monitor)
            return true
        }

        switch cxt.id
        {
        case .DoIt:          main.captureScreen(.Area)
        case .Area:          main.captureScreen(.Area)
        case .LastArea:      main.captureScreen(.LastArea)
        case .FullScreen:    main.captureScreen(.FullScreen)
        case .ActiveWnd:     main.captureScreen(.ActiveWindow)
        case .ToInPlace:     main.captureOptions.inPlaceEdit = !main.captureOptions.inPlaceEdit
        case .HideEditor:    main.captureOptions.hideEditorBefore = !main.captureOptions.hideEditorBefore
        case .CaptureCursor: main.captureOptions.captureCursor = !main.captureOptions.captureCursor
        case .ToEditor:      main.captureOptions.sendToEditor = !main.captureOptions.sendToEditor
        case .ToClipboard:   main.captureOptions.sendToClipboard = !main.captureOptions.sendToClipboard
        }

        return true
    }
}

impl MainWnd
{
    mtd newCapture(img: Image, linked: string = "", from: #null *Capture = null)
    {
        if !img.isValid() do
            return

        var capture = from
        if !capture
        {
            with capture = Memory.new'Capture()
            {
                .width, .widthOrg   = img.width
                .height, .heightOrg = img.height
                .backImg            = img
            }
        }

        let validCapture = capture!
        with validCapture
        {
            .changed     = true
            .linkedImage = linked
            .file        = Library.newFileName()
        }

        .editWnd.editView.setCapture(validCapture)
        .editWnd.editView.zoomToFit(false)

        validCapture.computePreview()
        .recentWnd.addRecent(validCapture.file, validCapture.preview, linked: linked)
        .recentWnd.recentView.selected = 0

        .saveCapture(validCapture)
        g_Library.addFile(validCapture.file)

        // Force edition mode
        if .libraryMode
        {
            .swapLibraryMode()
            .updateState()
        }
    }

    mtd captureScreen(mode: CaptureMode, monitorIndex: u64 = 0)
    {
        catch screenShot(me, mode, monitorIndex)
    }
}
