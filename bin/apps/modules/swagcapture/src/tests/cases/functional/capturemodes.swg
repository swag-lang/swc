#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui

// Timed preparation cannot annotate, even outside the zone or through editor commands.
// Returning to Picture restores the draft without deleting its forms.
#test
{
    var host: Gui.Testing.HeadlessHost
    let editor = testSetupInPlace(&host, dark: true)
    defer
    {
        g_CaptureMedia = .Picture
        g_Main?.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }
    let view = editor.editWnd.editView
    let capture = unwrap editor.capture
    let count = capture.forms.count
    Swag.require(count > 0)

    for media in [CaptureMedia.Video, CaptureMedia.Animation]
    {
        editor.setMedia(media)
        host.runFrames(1)
        let zone = view.getCaptureRect()
        let outside = Math.Point{zone.x - 80, zone.y - 80}
        let width = capture.width
        let height = capture.height
        editor.newMain.editMode = .Draw
        host.drag(view.localToSurface(outside), view.localToSurface(outside + Math.Point{40, 30}))
        Swag.require(capture.width == width and capture.height == height)
        host.drag(view.localToSurface(Math.Point{zone.x + 40, zone.y + 40}), view.localToSurface(Math.Point{zone.x + 100, zone.y + 100}))
        host.doubleClick(view.localToSurface(Math.Point{zone.x + 50, zone.y + 50}))
        capture.selection.add(0)
        editor.newMain.sendCommandEvent(ActionSelection.DeleteSelection)
        editor.newMain.sendCommandEvent(ActionUndo.DoUndo)
        Swag.require(capture.forms.count == count and not view.isEditingText())
        for form in capture.forms do
            Swag.require(not capture.isFormShown(form))

        // The bottom-right zone handle remains available while form editing is blocked.
        capture.selection.clear()
        host.runFrames(1)
        var preview = host.render(editor)
        Swag.require(preview.isValid())
        let current = view.getCaptureRect()
        host.moveMouse(view.localToSurface(Math.Point{current.right(), current.bottom()}))
        host.runFrames(1)
        Swag.require(capture.gizmo.hotAnchor != Swag.U32.Max)
        host.drag(view.localToSurface(Math.Point{current.right(), current.bottom()}),
                  view.localToSurface(Math.Point{current.right() + 20, current.bottom() + 20}))
        Swag.require(capture.width > width and capture.height > height)

        var chosen: bool
        host.app.sigFrame += func|host = &host, chosen = &chosen|(_)
        {
            if chosen[] do
                return
            Swag.require(host.clickPopupMenuItem(kindMenuId(.Picture)))
            chosen[] = true
        }
        host.clickWnd(unwrap editor.kindButton)
        host.app.sigFrame.clear()
        Swag.require(chosen and g_CaptureMedia == .Picture)
        Swag.require(capture.forms.count == count)
        for form in capture.forms do
            Swag.require(capture.isFormShown(form))
    }
}
