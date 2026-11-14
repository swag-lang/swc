#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

func countImageNavigation(wnd: *Wnd, delta: s32)
{
    let count = cast(*s32, unwrap wnd.userData)
    count[] += delta
}

// What an image viewer reported to the host about the end of what it shows.
struct ImageReports
{
    shown:    s32     // Still pictures reported on screen.
    finished: s32     // Animation cycles reported complete.
    answer:   Viewer.Continuation = .Next
}

func countImageShown(wnd: *Wnd)
{
    let reports = cast(*ImageReports, unwrap wnd.userData)
    reports.shown += 1
}

func answerImageCycle(wnd: *Wnd)->Viewer.Continuation
{
    let reports = cast(*ImageReports, unwrap wnd.userData)
    reports.finished += 1
    return reports.answer
}

func completeImageViewerWindow(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    completeViewerWindowClassification(host, window)

    var steps = 0'u32
    while window.activeChoiceIndex < window.instances.count and steps < 4_096
    {
        let instance = &window.instances[window.activeChoiceIndex]
        if not instance.view or not instance.isLoading or not instance.isLoading() do
            break
        Threading.Thread.sleep(1'ms)
        host.fireTimers()
        steps += 1
    }

    expireViewerLoadingLinger(window)
}

#test
{
    let fileName = scopeTestDataPath("sample.svg")

    let image = expect Picture.loadViewerImage(fileName)
    Swag.require(image.width == 128 and image.height == 64)
}

// A picture a camera stored on its side opens standing up, in the viewer and in its thumbnail.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-image-orientation-", ".png")
    defer discard catch File.delete(fileName)

    // A little-endian TIFF header with one directory holding Orientation = 6.
    let tiff = [0x49'u8, 0x49'u8, 0x2A'u8, 0x00'u8, 0x08'u8, 0x00'u8, 0x00'u8, 0x00'u8,
                0x01'u8, 0x00'u8,
                0x12'u8, 0x01'u8, 0x03'u8, 0x00'u8, 0x01'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x06'u8, 0x00'u8, 0x00'u8, 0x00'u8,
                0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8]
    var stored = Image.create(40, 20, .RGB8)
    var record: ImageMetadata
    record.signature = 1
    record.tag       = "Exif"
    for byte in tiff do
        record.value.add(byte)
    stored.metadata.add(#move record)
    expect stored.save(fileName)

    let image = expect Picture.loadViewerImage(fileName)
    Swag.require(image.width == 20 and image.height == 40)

    var host: Testing.HeadlessHost
    host.setup(640, 420)
    var result = openTestViewer(Picture.viewerPlugin(), &host.root, fileName, commandParent: &host.root, actionParent: &host.root, infoParent: &host.root)
    let view   = assume cast(*Picture.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.require(view.facts.width == "20" and view.facts.height == "40")

    // Ctrl+C copies this upright picture.
    let picture = unwrap view.imageView.picture()
    Swag.require(picture.width == 20 and picture.height == 40)
}

// Changing language refreshes image facts and commands without changing the displayed frame.
#test
{
    for name in ["sample.svg", "imageset-animation.gif"]
    {
        var host: Testing.HeadlessHost
        host.setup(720, 440)
        defer discard catch host.app.setLanguage(ReferenceLanguage)

        let fileName = scopeTestDataPath(name)
        var session  = openTestViewer(Picture.viewerPlugin(), &host.root, fileName)
        Swag.require(session.view != null)
        let view = assume cast(*Picture.Panel, session.view)
        completeViewerBackgroundLoad(&host, &view.load)
        view.imageView.setPaused(true)
        if view.imageView.movie.frameCount > 1 do
            view.imageView.setFrameIndex(1)
        view.imageView.setZoom(1.5)
        view.mirrorHorizontally()
        let oldTip     = String.from(view.transformButton.toolTip)
        let oldDetails = String.from(view.details)
        let frameIndex = view.imageView.movie.frameIndex
        expect host.app.setLanguage("fr")
        host.notify(.LanguageChanged)
        Swag.require(Utf8.startsWith(view.transformButton.toolTip, Picture.texts().ui_TipTransform) and view.transformButton.toolTip != oldTip)
        Swag.require(view.zoomLabel.toolTip == Picture.texts().ui_ZoomMenu and view.playButton.toolTip == Picture.texts().ui_TipPlay)
        Swag.require(Utf8.contains(view.transformButton.toolTip, Picture.texts().word_Mirrored))
        Swag.require(view.details != oldDetails)
        Swag.require(view.imageView.zoom == 1.5 and
                     view.imageView.isMirrored and
                     view.imageView.movie.frameIndex == frameIndex)
        if view.imageView.movie.frameCount > 1 do
            Swag.require(view.imageView.movie.isPaused)
        expect host.app.setLanguage(ReferenceLanguage)
        host.notify(.LanguageChanged)
        Swag.require(view.transformButton.toolTip == oldTip and view.details == oldDetails)
    }
}

// Pins the still-image tools beside a real vector document: zoom, fit, native size, and rotate
// read as one icon family while the numeric zoom remains a value rather than an action.
#test
{
    let fileName = scopeTestDataPath("sample.svg")

    var host: Gui.Testing.HeadlessHost
    host.setup(720, 440)

    let foot   = createTestViewerFoot(&host.root)
    var result = openTestViewer(Picture.viewerPlugin(), &host.root, fileName, commandParent: foot.commands, actionParent: &host.root, infoParent: foot.readings, services: {navigateFile: &countImageNavigation})
    Swag.require(result.view != null and
                 result.actions == null and
                 result.info != null and
                 result.commands != null)

    let view = assume cast(*Picture.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    host.root.applyLayout()
    standTestCommands(foot, view.actions)
    Swag.require(result.info.parent == cast(*Wnd, foot.readings) and result.info.position.width > 0)
    var navigation: s32
    view.userData = &navigation
    Swag.require(view.previousButton.isEnabled() and view.nextButton.isEnabled())
    Swag.require(view.previousButton.icon.isValid() and view.nextButton.icon.isValid())
    Swag.require(view.transformButton.arrowPosition == .RightUpward)
    Swag.require(view.playModeButton.parent == view.actions and view.playModeButton.arrowPosition == .RightUpward)
    Swag.require(not view.playModeButton.isEnabled())
    Swag.require(view.transformButton.position.right() <= view.actions.clientRect().right())
    let transformMenu = view.createTransformMenu()
    defer transformMenu.destroy()
    Swag.require(transformMenu.itemAt(0).name.raw == Picture.texts().ui_RotateCounterClockwise)
    Swag.require(transformMenu.itemAt(0).rightName.raw == "Shift R")
    Swag.require(transformMenu.itemAt(1).rightName.raw == "R")
    Swag.require(transformMenu.itemAt(3).rightName.raw == "H")
    Swag.require(transformMenu.itemAt(4).rightName.raw == "V")
    Swag.require(transformMenu.itemAt(6).rightName.raw == "Ctrl R")
    Swag.require(not Utf8.contains(transformMenu.itemAt(0).name.raw, "("))
    view.navigate(-1)
    view.navigate(1)
    Swag.require(navigation == 0)
    view.rotateCounterClockwise()
    Swag.require(view.imageView.rotationQuarterTurns == 3 and Utf8.contains(view.transformButton.toolTip, "270"))
    view.mirrorHorizontally()
    Swag.require(view.imageView.isMirrored and Utf8.contains(view.transformButton.toolTip, Picture.texts().word_Mirrored))
    view.resetTransform()
    Swag.require(view.imageView.rotationQuarterTurns == 0 and not view.imageView.isMirrored)
    var rotate = KeyEvent{kind: .Pressed, key: .R}
    view.sendEvent(&rotate)
    Swag.require(view.imageView.rotationQuarterTurns == 1)
    var mirror = KeyEvent{kind: .Pressed, key: .V}
    view.sendEvent(&mirror)
    Swag.require(view.imageView.isMirrored)
    var reset = KeyEvent{kind: .Pressed, key: .R, modifiers: .Control}
    view.sendEvent(&reset)
    Swag.require(view.imageView.rotationQuarterTurns == 0 and not view.imageView.isMirrored)
    view.dockStyle = .Center
    host.root.applyLayout()
    standTestCommands(foot, view.actions)
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(&host.root)
    Swag.require(view.playModeButton.position.right() <= view.actions.clientRect().right())
}

// A decoder refusal crosses the viewer boundary as data; the viewer creates no competing error UI.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-image-", ".png")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "not a PNG")

    var host: Gui.Testing.HeadlessHost
    host.setup(640, 420)

    var result = openTestViewer(Picture.viewerPlugin(), &host.root, fileName, commandParent: &host.root, actionParent: &host.root, infoParent: &host.root)
    Swag.require(result.view != null and
                 result.actions == null and
                 result.info != null and
                 result.commands != null)
    let view = assume cast(*Picture.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.require(not view.failureReason.isEmpty())
}

// The application floats image navigation over the foot of the document and writes the zoom on
// the line of readings, with nothing on screen until the pointer moves.
#test
{
    var host: Gui.Testing.HeadlessHost
    host.setup(960, 680)

    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    let fileName = scopeTestDataPath("sample.svg")
    window.openFile(fileName)
    completeImageViewerWindow(&host, window)

    Swag.require(window.currentActions == null)
    Swag.require(window.currentInfo != null and window.currentInfo.parent == window.readingLine)
    Swag.require(window.currentSidePanelButton == null)
    Swag.require(window.currentInfo.themeColors().label_TextLight == window.themeColors().label_TextFaint)
    Swag.require(Math.abs(window.readingLine.details.position.right() + ViewerReadingLine.GroupSpacing - window.currentInfo.position.x) < 0.01)
    Swag.require(Math.abs(window.currentInfo.position.right() - window.readingLine.clientRect().right()) < 0.01)
    Swag.require(window.currentCommands != null and window.currentCommands.parent == window.viewerBar)

    // Windowed controls stay visible in every playback mode, like the other viewers.
    Swag.require(window.playMode == .Once and window.viewerBar.isLocallyVisible())
    window.concealViewerBar()
    Swag.require(window.viewerBar.isLocallyVisible() and not window.app().isCursorHidden())
    window.setPlayMode(.Folder)
    Swag.require(window.viewerBar.isLocallyVisible())
    window.revealViewerBar()
    Swag.require(window.viewerBar.isLocallyVisible() and window.viewerBar.position.height == ViewerWindow.BarHeight)
    Swag.require(not window.searchBar.isLocallyVisible())
    Swag.require(Math.abs(window.currentCommands.position.horzCenter() - window.viewerBar.paddedClientRect().horzCenter()) < 0.01)
    Swag.require(Math.abs(window.viewerBar.position.horzCenter() - window.documentArea().horzCenter()) <= 1)
    window.concealViewerBar()
    Swag.require(window.viewerBar.isLocallyVisible() and not window.app().isCursorHidden())
    window.notePointer(window.pointerPosition + Math.Point{1, 0})
    Swag.require(not window.app().isCursorHidden())
}

// A still picture reports that it is on screen, once, so the host can time a slideshow on it;
// it has no end to report.
#test
{
    var host: Testing.HeadlessHost
    host.setup(720, 440)

    let fileName = scopeTestDataPath("sample.svg")
    var session  = openTestViewer(Picture.viewerPlugin(), &host.root, fileName, services: {reportFinished: &answerImageCycle, reportShown: &countImageShown})
    Swag.require(session.view != null)
    let view = assume cast(*Picture.Panel, session.view)
    var reports: ImageReports
    view.userData = &reports
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.require(reports.shown == 1 and reports.finished == 0)
}

// Seeking never finishes a cycle. Playing through its final delay obeys the host's stop,
// replay, or next-file answer, including an animation with an encoded finite loop count.
#test
{
    for answer in [Viewer.Continuation.Stop, .Replay, .Next]
    {
        for name in ["imageset-animation.gif", "imageset-animation.apng", "imageset-animation.webp"]
        {
            var host: Testing.HeadlessHost
            host.setup(720, 440)

            let fileName = scopeTestDataPath(name)
            var session  = openTestViewer(Picture.viewerPlugin(), &host.root, fileName, services: {reportFinished: &answerImageCycle, reportShown: &countImageShown})
            Swag.require(session.view != null)
            let view    = assume cast(*Picture.Panel, session.view)
            var reports = ImageReports{answer: answer}
            view.userData = &reports
            completeViewerBackgroundLoad(&host, &view.load)
            let lastFrame = view.imageView.movie.frameCount - 1
            Swag.require(lastFrame > 0 and not view.imageView.movie.isPaused)
            Swag.require(reports.shown == 0 and reports.finished == 0)

            // A seek within the animation is not a cycle.
            view.imageView.setFrameIndex(lastFrame)
            view.imageView.setFrameIndex(1)
            Swag.require(reports.finished == 0)

            view.imageView.setFrameIndex(lastFrame)
            view.imageView.setFrameIndex(0)
            Swag.require(reports.finished == 0)

            view.imageView.setFrameIndex(lastFrame)
            view.resize(720, 440)
            view.applyLayout()
            for 120
            {
                if reports.finished do
                    break
                discard host.render()
            }

            view.refreshFrame()
            Swag.require(reports.finished == 1)
            Swag.require(view.handedOff == (answer == .Next))
            Swag.require(view.imageView.movie.isPaused == (answer != .Replay))
            Swag.require(view.imageView.movie.frameIndex == (answer == .Replay ? 0 : lastFrame))

            // Repainting or refreshing the same terminal frame does not report another cycle.
            view.refreshFrame()
            Swag.require(reports.finished == 1)
        }
    }
}
