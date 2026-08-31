#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

func countImageNavigation(wnd: *Wnd, delta: s32)
{
    let count = cast(*s32) wnd.userData!
    count[] += delta
}

func completeImageViewerWindow(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    completeViewerWindowClassification(host, window)

    var steps = 0'u32
    while window.activeChoiceIndex < window.instances.count and steps < 4_096
    {
        let instance = &window.instances[window.activeChoiceIndex]
        if !instance.view or !instance.isLoading or !instance.isLoading!(instance.view!) do
            break
        Threading.Thread.sleep(1'ms)
        host.fireTimers()
        steps += 1
    }
}

#test
{
    let fileName = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/sample.svg")

    let image = expect loadViewerImage(fileName)
    Swag.assert(image.width == 128 and image.height == 64)
}

// Pins the still-image tools beside a real vector document: zoom, fit, native size, and rotate
// read as one icon family while the numeric zoom remains a value rather than an action.
#test
{
    let fileName = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/sample.svg")

    var host: Gui.Testing.HeadlessHost
    host.setup(720, 440)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let actionBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 52})
    actionBar.dockStyle       = .Bottom
    actionBar.backgroundStyle = .Window
    actionBar.padding         = {16, 8, 16, 8}
    let infoBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 40})
    infoBar.dockStyle       = .Bottom
    infoBar.backgroundStyle = .InformationBar
    infoBar.padding         = {16, 4, 16, 4}

    var result = openTestViewer(imageViewerPlugin(), &host.root, fileName, commandParent: actionBar, actionParent: &host.root, infoParent: infoBar, services: {navigateFile: &countImageNavigation})
    Swag.assert(result.view != null and result.actions == null and result.info != null and result.commands != null)
    actionBar.centerGroup = result.commands
    infoBar.centerGroup   = result.info

    let view = cast(*ImageViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    var navigation: s32
    view.userData = &navigation
    Swag.assert(view.previousButton.isEnabled() and view.nextButton.isEnabled())
    Swag.assert(view.previousButton.icon.isValid() and view.nextButton.icon.isValid())
    Swag.assert(view.transformButton.arrowPosition == .RightDownward)
    let transformMenu = view.createTransformMenu()
    defer transformMenu.destroy()
    Swag.assert(transformMenu.itemAt(0).name.raw == imageStrings().ui_RotateCounterClockwise)
    Swag.assert(transformMenu.itemAt(0).rightName.raw == "Shift+R")
    Swag.assert(transformMenu.itemAt(1).rightName.raw == "R")
    Swag.assert(transformMenu.itemAt(3).rightName.raw == "H")
    Swag.assert(transformMenu.itemAt(4).rightName.raw == "V")
    Swag.assert(transformMenu.itemAt(6).rightName.raw == "Ctrl+R")
    Swag.assert(!Utf8.contains(transformMenu.itemAt(0).name.raw, "("))
    view.navigate(-1)
    view.navigate(1)
    Swag.assert(navigation == 0)
    view.rotateCounterClockwise()
    Swag.assert(view.imageView.rotationQuarterTurns == 3 and Utf8.contains(view.zoomLabel.text(), "270"))
    view.mirrorHorizontally()
    Swag.assert(view.imageView.isMirrored and Utf8.contains(view.zoomLabel.text(), imageStrings().word_Mirrored))
    view.resetTransform()
    Swag.assert(view.imageView.rotationQuarterTurns == 0 and !view.imageView.isMirrored)
    view.dockStyle         = .Center
    view.actions.dockStyle = .None
    view.info.dockStyle    = .None
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(&host.root)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.image.document")
}

// A decoder refusal crosses the viewer boundary as data; the viewer creates no competing error UI.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-image-", ".png")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "not a PNG")

    var host: Gui.Testing.HeadlessHost
    host.setup(640, 420)
    defer host.shutdown()

    var result = openTestViewer(imageViewerPlugin(), &host.root, fileName, commandParent: &host.root, actionParent: &host.root, infoParent: &host.root)
    Swag.assert(result.view != null and result.actions == null and result.info != null and result.commands != null)
    let view = cast(*ImageViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    Swag.assert(!view.failureReason.isEmpty())
}

// The application hosts image navigation in its centered viewer bar and zoom in the information
// row, leaving the global action bar to search and application-level actions.
#test
{
    var host: Gui.Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    let fileName = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/sample.svg")
    window.openFile(fileName)
    completeImageViewerWindow(&host, window)

    Swag.assert(window.currentActions == null)
    Swag.assert(window.currentInfo != null and window.currentInfo!.parent == window.infoContentGroup)
    Swag.assert(window.infoContentGroup.position.x + window.currentInfo!.position.right() == window.infoBar.paddedClientRect().right())
    Swag.assert(window.currentInfo!.themeColors().label_TextLight == window.themeColors().label_TextFaint)
    Swag.assert(Math.abs(window.infoStatsLabel.position.right() + ViewerInfoGroupSpacing - window.currentInfo!.position.x) < 0.01)
    Swag.assert(window.currentCommands != null and window.currentCommands!.parent == window.viewerBar)
    Swag.assert(window.viewerBar.isLocallyVisible() and window.viewerBar.position.height == ViewerBarHeight)
    Swag.assert(!window.searchGroup.isLocallyVisible())
    Swag.assert(Math.abs(window.currentCommands!.position.horzCenter() - window.viewerBar.paddedClientRect().horzCenter()) < 0.01)
}
