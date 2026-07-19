#global #[Swag.ExplicitNullability]
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

    mtd impl update(cxt: ActionContext, evt: #nonull *CommandStateEvent)->bool
    {
        let main = cast(#nonull *MainWnd) cxt.wnd

        switch cxt.id
        {
        case DoIt:
            evt.setFlags |= .Name | .Icon
            evt.name = "Capture"
            evt.icon = Icon.from(&main.icons48, 6)
        case Area:
            evt.setFlags |= .Name | .Icon
            evt.name = "Capture Area"
            evt.icon = Icon.from(&main.icons24, 7)
        case LastArea:
            evt.setFlags |= .Name | .Icon
            evt.name = "Capture Last Area"
            evt.icon = Icon.from(&main.icons24, 15)
        case FullScreen:
            evt.setFlags |= .Name | .Icon
            evt.name = "Capture Full Screen"
            evt.icon = Icon.from(&main.icons24, 6)
        case ActiveWnd:
            evt.setFlags |= .Name | .Icon
            evt.name = "Capture Active Window"
            evt.icon = Icon.from(&main.icons24, 14)
        case Screen0:
            evt.setFlags |= .Name | .Icon
            evt.name = Format.toString("Capture Monitor 0 (%x%)", main.monitors[0].rect.width, main.monitors[0].rect.height)
            evt.icon = Icon.from(&main.icons24, 5)
        case Screen1:
            // Screen<N> maps to monitors[N]; guard the read like the execute path
            // (idx >= monitors.count) so a machine with fewer monitors is safe.
            evt.setFlags |= .Name | .Icon | .Disabled
            evt.disabled = main.monitors.count <= 1
            evt.name     = evt.disabled ? "Capture Monitor 1" : Format.toString("Capture Monitor 1 (%x%)", main.monitors[1].rect.width, main.monitors[1].rect.height)
            evt.icon     = Icon.from(&main.icons24, 5)
        case Screen2:
            evt.setFlags |= .Name | .Icon | .Disabled
            evt.disabled = main.monitors.count <= 2
            evt.name     = evt.disabled ? "Capture Monitor 2" : Format.toString("Capture Monitor 2 (%x%)", main.monitors[2].rect.width, main.monitors[2].rect.height)
            evt.icon     = Icon.from(&main.icons24, 5)
        case Screen3:
            evt.setFlags |= .Name | .Icon | .Disabled
            evt.disabled = main.monitors.count <= 3
            evt.name     = evt.disabled ? "Capture Monitor 3" : Format.toString("Capture Monitor 3 (%x%)", main.monitors[3].rect.width, main.monitors[3].rect.height)
            evt.icon     = Icon.from(&main.icons24, 5)

        case HideEditor:
            evt.setFlags |= .Name | .Checked
            evt.name     = "Hide Editor Before Capture"
            evt.checked  = main.captureOptions.hideEditorBefore
            evt.accepted = true
        case CaptureCursor:
            evt.setFlags |= .Name | .Checked
            evt.name     = "Capture Mouse Cursor"
            evt.checked  = main.captureOptions.captureCursor
            evt.accepted = true
        case ToInPlace:
            evt.setFlags |= .Name | .Checked
            evt.name     = "Edit Captured Area In Place"
            evt.checked  = main.captureOptions.inPlaceEdit
            evt.accepted = true
        case ToEditor:
            evt.setFlags |= .Name | .Checked
            evt.name     = "Send Capture To Editor"
            evt.checked  = main.captureOptions.sendToEditor
            evt.accepted = true
        case ToClipboard:
            evt.setFlags |= .Name | .Checked
            evt.name     = "Send Capture To Clipboard"
            evt.checked  = main.captureOptions.sendToClipboard
            evt.accepted = true
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = cast(#nonull *MainWnd) cxt.wnd

        switch cxt.id
        {
        case DoIt:
            main.captureScreen(.Area)
        case Area:
            main.captureScreen(.Area)
        case LastArea:
            main.captureScreen(.LastArea)
        case FullScreen:
            main.captureScreen(.FullScreen)
        case ActiveWnd:
            main.captureScreen(.ActiveWindow)
        case Screen0:
            main.captureScreen(.Screen0)
        case Screen1:
            main.captureScreen(.Screen1)
        case Screen2:
            main.captureScreen(.Screen2)
        case Screen3:
            main.captureScreen(.Screen3)

        case ToInPlace:
            main.captureOptions.inPlaceEdit = !main.captureOptions.inPlaceEdit
        case HideEditor:
            main.captureOptions.hideEditorBefore = !main.captureOptions.hideEditorBefore
        case CaptureCursor:
            main.captureOptions.captureCursor = !main.captureOptions.captureCursor
        case ToEditor:
            main.captureOptions.sendToEditor = !main.captureOptions.sendToEditor
        case ToClipboard:
            main.captureOptions.sendToClipboard = !main.captureOptions.sendToClipboard
        }

        return true
    }
}

impl MainWnd
{
    mtd newCapture(img: Image, linked: #nonull string = "", from: #null *Capture = null)
    {
        if !img.isValid() do
            return

        var capture = from
        if !capture
        {
            with capture = Memory.new'Capture()
            {
                .width, .widthOrg = img.width
                .height, .heightOrg = img.height
                .backImg = img
            }
        }

        let validCapture = assume capture
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
