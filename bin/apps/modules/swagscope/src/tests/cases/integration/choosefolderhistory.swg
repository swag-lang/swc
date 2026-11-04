#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel

// Open Explorer's folder dialog, use its history, and browse the selected folder on the native desktop.
#[Swag.TestTag("integration.application.journey")]
#test
{
    let root   = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-folder-history-%", Guid64.random()))
    var chosen = Path.combine(root, "Pictures")
    expect Directory.create(chosen, recurse: true)
    defer discard catch Directory.delete(root, recurse: true)

    var app: Application
    app.setAppIcon(expect Image.decode(".png", AppIcon))
    app.setStatePath(Path.combine(root, "settings.scc"))
    registerAppStrings(&app.resources)
    let surface = expect app.createSurface(40, 40, 960, 680, surfaceId: "scope-folder-history-journey")
    let window  = ViewerWindow.create(surface.wnd, createViewerPluginRegistry())
    window.fileDlgState.currentFolder = root
    window.fileDlgState.recentFolders.add(chosen)
    window.fileDlgState.recentFolders.add(Path.combine(root, "Offline"))
    surface.show()

    var watch: Time.Stopwatch
    watch.start()
    var menuWatch:     Time.Stopwatch
    var menuFrameSeen: bool
    var stage:         u32
    app.sigFrame += func|app = &app, &stage, &watch, &menuWatch, &menuFrameSeen, &chosen|(_)
    {
        Swag.require(watch.elapsedMilliseconds() < 15_000, "folder-history journey exceeded its deadline")
        if stage == 2 do
            return
        var dialog: *FileDlg?
        for surface in app.surfaces
        {
            if surface.view() is FileDlg as candidate
            {
                dialog = candidate
                break
            }
        }

        if not dialog do
            return
        if stage == 0
        {
            if not (expect Testing.verifyNativePresentation(unwrap dialog.surface)) do
                return
            Swag.require(dialog.browser.choiceLabel.text().count == 0)
            Swag.require(dialog.browser.pathBar.breadcrumb.toolTip.isEmpty())
            for 2
            {
                stage         = 1
                menuFrameSeen = false
                menuWatch.restart()
                dialog.browser.historyButton.sigPressed.call(dialog.browser.historyButton)
                Swag.require(stage == 2 and dialog.selectedPath() == chosen)
            }

            discard dialog.closeWithResult(Dialog.BtnOk)
        }
        elif app.mouseCapture() is MenuCtrl as menu
        {
            Swag.require(menu.items.count == 2)
            Swag.require(menu.items[0]!.icon.color == app.theme.colors.arc)
            if not menuFrameSeen
            {
                menuFrameSeen = true
                Console.println("Folder history first frame: ", menuWatch.elapsedMilliseconds(), " ms")
            }

            if not (expect Testing.verifyNativePresentation(unwrap dialog.surface)) do
                return
            stage = 2
            let item  = unwrap menu.items[0]
            var click = MouseEvent{kind: .Pressed, button: .Left,
                                   surfacePos: menu.localToSurface(Math.Point{menu.clientRect().horzCenter(), item.pos + item.size * 0.5})}
            menu.sendEvent(&click)
            click.kind = .Released
            menu.sendEvent(&click)
        }
    }

    window.sendCommandEvent(ViewerCommands.Explore)
    Swag.require(stage == 2 and window.isExploring())
    while window.explorer!.load.started and watch.elapsedMilliseconds() < 20_000 do
        app.runFrame()
    Swag.require(not window.explorer.load.started and window.explorer.listing.path == chosen)
    Swag.require(surface.renderFailure.isEmpty())
}
