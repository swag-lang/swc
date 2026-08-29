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
    @assert(image.width == 128 and image.height == 64)
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

    let actionBar = Wnd.create'Wnd(&host.root, {0, 0, 0, 52})
    actionBar.dockStyle       = .Top
    actionBar.backgroundStyle = .Window
    actionBar.padding         = {16, 8, 16, 8}
    let infoBar = Wnd.create'Wnd(&host.root, {0, 0, 0, 40})
    infoBar.dockStyle       = .Bottom
    infoBar.backgroundStyle = .InformationBar
    infoBar.padding         = {16, 4, 16, 4}

    let request = ViewerRequest{contentParent: &host.root, commandParent: &host.root, fileName: fileName, actionParent: actionBar, infoParent: infoBar, navigateFile: &countImageNavigation}
    var result: ViewerResult
    createImageViewer(&request, &result)
    @assert(result.view != null and result.actions != null and result.info != null and result.commands == null)

    let view = cast(*ImageViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    var navigation: s32
    view.userData = &navigation
    @assert(view.previousButton.isEnabled() and view.nextButton.isEnabled())
    @assert(view.previousButton.icon.isValid() and view.nextButton.icon.isValid())
    @assert(view.transformButton.arrowPosition == .RightDownward)
    let transformMenu = view.createTransformMenu()
    defer transformMenu.destroy()
    @assert(transformMenu.itemAt(0).name.raw == imageStrings().ui_RotateCounterClockwise)
    @assert(transformMenu.itemAt(0).rightName.raw == "Shift+R")
    @assert(transformMenu.itemAt(1).rightName.raw == "R")
    @assert(transformMenu.itemAt(3).rightName.raw == "H")
    @assert(transformMenu.itemAt(4).rightName.raw == "V")
    @assert(transformMenu.itemAt(6).rightName.raw == "Ctrl+R")
    @assert(!Utf8.contains(transformMenu.itemAt(0).name.raw, "("))
    view.navigate(-1)
    view.navigate(1)
    @assert(navigation == 0)
    view.rotateCounterClockwise()
    @assert(view.imageView.rotationQuarterTurns == 3 and Utf8.contains(view.zoomLabel.text(), "270"))
    view.mirrorHorizontally()
    @assert(view.imageView.isMirrored and Utf8.contains(view.zoomLabel.text(), imageStrings().word_Mirrored))
    view.resetTransform()
    @assert(view.imageView.rotationQuarterTurns == 0 and !view.imageView.isMirrored)
    view.dockStyle         = .Center
    view.actions.dockStyle = .Center
    view.info.dockStyle    = .Center
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(&host.root)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.image.document")
}

// A decoder refusal crosses the viewer boundary as data; the viewer creates no competing error UI.
#test
{
    let fileName = Gui.Testing.tempFilePath("filescope-image-", ".png")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "not a PNG")

    var host: Gui.Testing.HeadlessHost
    host.setup(640, 420)
    defer host.shutdown()

    let request = ViewerRequest{contentParent: &host.root, commandParent: &host.root, fileName: fileName, actionParent: &host.root, infoParent: &host.root}
    var result: ViewerResult
    createImageViewer(&request, &result)
    @assert(result.view != null and result.actions != null and result.info != null and result.commands == null)
    let view = cast(*ImageViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    @assert(!view.failureReason.isEmpty())
}

// The application hosts image actions in its centred action slot and the zoom in its information
// row, leaving the lower command band to viewers that need its width.
#test
{
    var host: Gui.Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    let fileName = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/sample.svg")
    window.openFile(fileName)
    completeImageViewerWindow(&host, window)

    @assert(window.currentActions != null and window.currentActions!.parent == window.commandBar)
    @assert(window.currentInfo != null and window.currentInfo!.parent == window.infoContentGroup)
    @assert(window.currentCommands == null and !window.viewerBar.isLocallyVisible())
    @assert(!window.searchGroup.isLocallyVisible())
    @assert(Math.abs(window.currentActions!.position.horzCenter() - window.commandBar.paddedClientRect().horzCenter()) < 0.01)
}
