using Gui

struct ActionCapture {}

impl ActionCapture
{
    newCmdId("DoIt")
    newCmdId("Area")
    newCmdId("LastArea")
    newCmdId("FullScreen")
    newCmdId("Screen0")
    newCmdId("Screen1")
    newCmdId("Screen2")
    newCmdId("Screen3")
    newCmdId("ActiveWnd")
    newCmdId("HideEditor")
    newCmdId("CaptureCursor")
    newCmdId("ToInPlace")
    newCmdId("ToEditor")
    newCmdId("ToClipboard")
}

impl IActionUI for ActionCapture
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main = cast(*MainWnd) cxt.wnd!

        switch cxt.id
        {
        case .DoIt:
            evt.updatedFields |= .Name | .Icon
            evt.name          = appStrings().ui_MenuCapture
            evt.icon          = main.icon(.Capture, 48)

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

        case .Screen0:
            evt.updatedFields |= .Name | .Icon
            evt.name          = Format.toString(appStrings().act_CaptureMonitorSize, 0, main.monitors[0].bounds.width, main.monitors[0].bounds.height)
            evt.icon          = main.icon(.Monitor)

        case .Screen1:

            // Screen<N> maps to monitors[N]; guard the read like the execute path
            // (idx >= monitors.count) so a machine with fewer monitors is safe.
            evt.updatedFields |= .Name | .Icon | .Disabled
            evt.disabled      = main.monitors.count <= 1
            evt.name          = evt.disabled ? Format.toString(appStrings().act_CaptureMonitor, 1) : Format.toString(appStrings().act_CaptureMonitorSize, 1, main.monitors[1].bounds.width, main.monitors[1].bounds.height)
            evt.icon          = main.icon(.Monitor)

        case .Screen2:
            evt.updatedFields |= .Name | .Icon | .Disabled
            evt.disabled      = main.monitors.count <= 2
            evt.name          = evt.disabled ? Format.toString(appStrings().act_CaptureMonitor, 2) : Format.toString(appStrings().act_CaptureMonitorSize, 2, main.monitors[2].bounds.width, main.monitors[2].bounds.height)
            evt.icon          = main.icon(.Monitor)

        case .Screen3:
            evt.updatedFields |= .Name | .Icon | .Disabled
            evt.disabled      = main.monitors.count <= 3
            evt.name          = evt.disabled ? Format.toString(appStrings().act_CaptureMonitor, 3) : Format.toString(appStrings().act_CaptureMonitorSize, 3, main.monitors[3].bounds.width, main.monitors[3].bounds.height)
            evt.icon          = main.icon(.Monitor)

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

        switch cxt.id
        {
        case .DoIt:          main.captureScreen(.Area)
        case .Area:          main.captureScreen(.Area)
        case .LastArea:      main.captureScreen(.LastArea)
        case .FullScreen:    main.captureScreen(.FullScreen)
        case .ActiveWnd:     main.captureScreen(.ActiveWindow)
        case .Screen0:       main.captureScreen(.Screen0)
        case .Screen1:       main.captureScreen(.Screen1)
        case .Screen2:       main.captureScreen(.Screen2)
        case .Screen3:       main.captureScreen(.Screen3)
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

    mtd captureScreen(mode: CaptureMode)
    {
        catch screenShot(me, mode)
    }
}
