#global internal

using Core, Pixel, Gui

// Describes the picture viewer to the host.
//
// It offers itself for every raster format the imaging module can decode, plus SVG, so a decoder
// added there reaches the viewer without a list to update here.
func imageViewerPlugin()->Viewer.Plugin
{
    var result: retval
    result.key          = "image"
    result.staticName   = "Image"
    result.attach       = &registerImageStrings
    result.iconAtlas    = viewerIcons()
    result.iconIndex    = cast(s32) ViewerIcons.Image
    result.create       = &createImageViewer
    result.smokeFixture = "sample.svg"

    let formats = Image.decodableFormats()
    for format in formats do
        result.addSelectors(format.extensions)
    result.addSelectors(".svg")
    return result
}

private const ImageInfoWidth = 156.0
private const SvgRasterLimit = 2048.0

private func imageCommandWidth(metrics: const *ThemeMetrics)->f32
{
    return 2 * themeActionButtonSize(metrics) + 2 * themeDropDownButtonWidth(metrics) + 16
}

private func imageSetCommandWidth(metrics: const *ThemeMetrics)->f32
{
    return imageCommandWidth(metrics) + themeActionButtonSize(metrics) + 10 + 128 + 12 + 58
}

struct ImageViewerContent
{
    image:       Image
    movie:       Movie
    drawing:     Svg.Drawing     // Vector document, for a format that has no pixels of its own.
    facts:       ImageViewerFacts
    information: MediaInfoData
}

// Rasterizes a vector document at the size it declares, bounded so a poster-sized view box
// cannot ask for an unbounded bitmap.
//
// The viewer itself shows the drawing as vectors, so this is for the callers that genuinely
// need pixels — a thumbnail, an export, a comparison against a decoded picture.
internal func loadViewerImage(fileName: string)->Image fail
{
    if Path.lowercaseExtension(fileName) != ".svg"
    {
        var file   = try File.MappedFile.open(fileName)
        let region = try file.mapAll()
        return try Image.decode(fileName, region.bytes())
    }

    let drawing = try loadViewerDrawing(fileName)
    let largest = Math.max(drawing.width, drawing.height)
    let scale   = largest > SvgRasterLimit ? SvgRasterLimit / largest : 1
    let width   = cast(s32) Math.max(Math.round(drawing.width * scale), 1)
    let height  = cast(s32) Math.max(Math.round(drawing.height * scale), 1)
    return drawing.rasterize(width, height, 1)
}

internal func loadViewerDrawing(fileName: string)->Svg.Drawing fail
{
    var file   = try File.MappedFile.open(fileName)
    let region = try file.mapAll()
    return try Svg.Drawing.parse(cast(string) region.bytes())
}

private func loadImageViewerContent(fileName: string)->ImageViewerContent fail
{
    var result: retval
    var extension = String.from(Path.extension(fileName) orelse "")
    extension = extension.toLower()
    result.information.add(.Image, group: true)
    result.information.add(.Format, extension.toUpper().toString())
    if extension == ".svg"
    {
        result.drawing      = try loadViewerDrawing(fileName)
        result.facts.width  = formatViewBoxExtent(result.drawing.width)
        result.facts.height = formatViewBoxExtent(result.drawing.height)
        result.facts.vector = true
        result.information.add(.Dimensions, Format.toString("% × %", formatViewBoxExtent(result.drawing.width), formatViewBoxExtent(result.drawing.height)).toString())
    }
    else
    {
        try result.movie.load(fileName)
        try result.movie.prepareCache()
        let frame = &result.movie.frame
        result.facts.width  = Format.toString("%", frame.width)
        result.facts.height = Format.toString("%", frame.height)
        result.facts.bits   = frame.bitsPerPixel
        result.facts.frames = result.movie.frameCount
        result.information.add(.Dimensions, Format.toString("% × % px", frame.width, frame.height).toString())
        result.information.add(.PixelFormat, Format.toString("%", frame.pixelFormat).toString())
        result.information.add(.Depth, Format.toString("%", frame.bitsPerPixel).toString())
        if result.movie.frameCount > 1
        {
            result.information.add(.Frames, Format.toString("%", result.movie.frameCount).toString())
        }
        else
        {
            result.image = frame[]
        }

        result.information.addImageMetadata(frame.metadata.toSlice(), extension == ".png" or extension == ".apng")
        if result.movie.frameCount <= 1 do
            result.movie.clear()
    }

    return #move result
}

// Writes one view-box extent the way the document authored it: a whole number stays whole.
private func formatViewBoxExtent(value: f32)->String
{
    if value == Math.round(value) do
        return Format.toString("%", cast(s64) value)
    return Format.toString("%", value)
}

// Keeps decoded facts independent of the language active while the worker was running.
internal struct ImageViewerFacts
{
    width, height: String
    bits:          u32
    frames:        s32
    vector:        bool
}

private impl ImageViewerFacts
{
    mtd const text()->String
    {
        if .vector do
            return Format.toString(imageStrings().ui_DetailsVector, .width, .height)
        if .frames > 1 do
            return Format.toString(imageStrings().ui_DetailsMovie, .width, .height, frameCountText(.frames))
        return Format.toString(imageStrings().ui_DetailsStill, .width, .height, .bits)
    }
}

internal struct ImageViewer
{
    using wnd: Wnd
    details:   String
    facts:     ImageViewerFacts

    late
    {
        actions:         *Wnd
        info:            *Wnd
        previousButton:  *IconButton
        nextButton:      *IconButton
        imageView:       *ImageView
        zoomLabel:       *IconButton
        transformButton: *IconButton
        playModeButton:  *Viewer.PlaybackButton
        playButton:      *IconButton
        timeline:        *Slider
        frameLabel:      *Label
        information:     *MediaInfoPanel
    }

    navigateFile:         Viewer.NavigateFile?
    reportFailure:        Viewer.ReportFailure?
    reportDetails:        Viewer.ReportDetails?
    reportChromeChanged:  Viewer.ReportChromeChanged?
    reportLoadingChanged: Viewer.ReportLoadingChanged?
    reportFinished:       Viewer.ReportFinished?
    reportShown:          Viewer.ReportShown?
    lastCompletedLoops:   u32      // Playback cycles observed by the latest frame refresh.
    handedOff:            bool     // The host was told the animation has run its cycle, and answered that it moves on.
    load:                 Viewer.BackgroundLoad'ImageViewerContent
    loadTimer:            *Timer?
    failureReason:        String
}

internal impl ImageViewer
{
    mtd refreshZoom()
    {
        let zoom = cast(s32) Math.round(.imageView.effectiveZoom() * 100)
        if .imageView.rotationQuarterTurns or .imageView.isMirrored
        {
            let angle = .imageView.rotationQuarterTurns * 90
            if .imageView.isMirrored do
                .zoomLabel.setText(Format.toString("% % · %° · %", zoom, "%", angle, imageStrings().word_Mirrored))
            else do
                .zoomLabel.setText(Format.toString("% % · %°", zoom, "%", angle))
        }
        else do
            .zoomLabel.setText(Format.toString("% %", zoom, "%"))
        if .reportChromeChanged do
            .reportChromeChanged(me)
    }

    mtd refreshFrame()
    {
        let movie = &.imageView.movie
        if movie.frameCount <= 1 do
            return
        .timeline.setValueWithoutGesture(cast(f32) movie.frameIndex)
        .frameLabel.setText(Format.toString("% / %", movie.frameIndex + 1, movie.frameCount))
        .playButton.setIcon(.theme().icon(movie.isPaused ? .Play : .Pause, themeActionIconSize(.themeMetrics())))

        // The movie records elapsed cycles independently of frame seeks and encoded loop limits.
        let completed = movie.completedLoopCount()
        let finished  = completed != 0 and .lastCompletedLoops == 0
        .lastCompletedLoops = completed
        if finished do
            .finishCycle()
    }

    // Keeps the completed cycle's last frame until the host explicitly requests another cycle.
    mtd finishCycle()
    {
        if .handedOff or not .reportFinished do
            return
        switch #complete .reportFinished(me)
        {
        case .Stop:
            break

        case .Replay:
            .imageView.setFrameIndex(0)
            .imageView.setPaused(false)
            .refreshFrame()

        case .Next:
            .handedOff = true
        }
    }

    mtd showPlayback()
    {
        let width = imageSetCommandWidth(.themeMetrics())
        .actions.preferredSize.x = width
        .actions.resize(width, themeActionButtonSize(.themeMetrics()))
        .playButton.show(.imageView.movie.isAnimated())
        .timeline.show()
        .frameLabel.show()
        .timeline.setBounds(0, cast(f32) .imageView.movie.frameCount - 1, 1)
        .refreshFrame()
        if .reportChromeChanged do
            .reportChromeChanged(me)
    }

    mtd navigate(delta: s32)
    {
        if .navigateFile do
            .navigateFile(me, delta)
    }

    mtd rotateClockwise()
    {
        .imageView.rotateClockwise()
    }

    mtd rotateCounterClockwise()
    {
        .imageView.rotateCounterClockwise()
    }

    mtd mirrorHorizontally()
    {
        .imageView.mirrorHorizontally()
    }

    mtd mirrorVertically()
    {
        .imageView.mirrorVertically()
    }

    mtd resetTransform()
    {
        .imageView.resetTransform()
    }

    mtd createTransformMenu()->*MenuCtrl
    {
        let texts = imageStrings()
        let menu  = MenuCtrl.createPopup(me, owner: me)
        menu.addItem(texts.ui_RotateCounterClockwise, "scope.image.rotateLeft", .theme().icon(.Undo, themeRowIconSize(.themeMetrics())), rightName: "Shift+R")
        menu.addItem(texts.ui_RotateClockwise, "scope.image.rotateRight", .theme().icon(.Redo, themeRowIconSize(.themeMetrics())), rightName: "R")
        menu.addSeparator()
        menu.addItem(texts.ui_MirrorHorizontal, "scope.image.mirrorHorizontal", rightName: "H")
        menu.addItem(texts.ui_MirrorVertical, "scope.image.mirrorVertical", rightName: "V")
        menu.addSeparator()
        menu.addItem(texts.ui_ResetTransform, "scope.image.reset", .theme().icon(.Update, themeRowIconSize(.themeMetrics())), rightName: "Ctrl+R")
        return menu
    }

    mtd showTransformMenu()
    {
        let menu = .createTransformMenu()
        switch menu.doModal(.transformButton, autoDestroy: true) orelse ""
        {
        case "scope.image.rotateLeft":       .rotateCounterClockwise()
        case "scope.image.rotateRight":      .rotateClockwise()
        case "scope.image.mirrorHorizontal": .mirrorHorizontally()
        case "scope.image.mirrorVertical":   .mirrorVertically()
        case "scope.image.reset":            .resetTransform()
        }
    }

    mtd showZoomMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem("25%", "scope.image.zoom25")
        menu.addItem("50%", "scope.image.zoom50")
        menu.addItem("100%", "scope.image.zoom100")
        menu.addItem("200%", "scope.image.zoom200")
        menu.addSeparator()
        menu.addItem(imageStrings().ui_TipFit, "scope.image.zoomFit", .theme().icon(.FitView, themeRowIconSize(.themeMetrics())), rightName: "F")
        switch menu.doModal(.zoomLabel, autoDestroy: true) orelse ""
        {
        case "scope.image.zoom25":  .imageView.setZoom(0.25)
        case "scope.image.zoom50":  .imageView.setZoom(0.5)
        case "scope.image.zoom100": .imageView.actualSize()
        case "scope.image.zoom200": .imageView.setZoom(2)
        case "scope.image.zoomFit": .imageView.zoomToFit()
        }
    }
}

private impl IWnd for ImageViewer
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged
        {
            .previousButton.toolTip  = imageStrings().ui_TipPrevious
            .nextButton.toolTip      = imageStrings().ui_TipNext
            .transformButton.toolTip = imageStrings().ui_TipTransform
            .playButton.toolTip      = imageStrings().ui_TipPlay
            .zoomLabel.toolTip       = imageStrings().ui_ZoomMenu
            .refreshZoom()
            if not .facts.width.isEmpty()
            {
                .details = .facts.text()
                if .reportDetails do
                    .reportDetails(me, .details.toString())
            }
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .loadTimer
        {
            evt.accepted = false
            return
        }

        if not .load.isDone() do
            return

        .removeTimer(evt.timer)
        .loadTimer = null
        var content: ImageViewerContent
        .failureReason = .load.finish(&content)
        if not .failureReason.isEmpty()
        {
            if .reportFailure do
                .reportFailure(me, .failureReason.toString())
            return
        }

        if content.movie.isValid()
        {
            if .reportFinished do
                content.movie.loops = false
            .imageView.exchangeMovie(&content.movie)
            if .imageView.movie.frameCount > 1 do
                .showPlayback()
        }
        elif content.drawing.width > 0 and content.drawing.height > 0 do
            .imageView.setDrawing(#move content.drawing)
        else do
            .imageView.takeImage(&content.image)

        .facts   = #move content.facts
        .details = .facts.text()
        .information.publish(&content.information)
        .refreshZoom()
        .applyLayout()
        .setInitialFocus(.imageView)
        if .reportDetails do
            .reportDetails(me, .details.toString())
        if .reportLoadingChanged do
            .reportLoadingChanged(me)

        // A still picture has no end of its own; the host's slideshow gives it one.
        let still = not .imageView.movie.isValid() or .imageView.movie.frameCount <= 1
        if still and .reportShown do
            .reportShown(me)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        switch evt.key
        {
        case .Left where evt.modifiers == .None:
            if .navigateFile do
                .navigate(-1)
            else do
                evt.accepted = false

        case .Right where evt.modifiers == .None:
            if .navigateFile do
                .navigate(1)
            else do
                evt.accepted = false

        case .Add, .OemPlus:
            .imageView.zoomIn()

        case .Subtract, .OemMinus:
            .imageView.zoomOut()

        case .D0 where evt.modifiers.has(.Control):
            .imageView.actualSize()

        case .F:
            .imageView.zoomToFit()

        case .R where evt.modifiers == .None:
            .rotateClockwise()

        case .R where evt.modifiers == .Shift:
            .rotateCounterClockwise()

        case .R where evt.modifiers == .Control:
            .resetTransform()

        case .H where evt.modifiers == .None:
            .mirrorHorizontally()

        case .V where evt.modifiers == .None:
            .mirrorVertically()

        case .Space where .imageView.movie.isAnimated() and .imageView.movie.frameCount > 1:
            .imageView.setPaused(not .imageView.movie.isPaused)
            .refreshFrame()

        default:
            evt.accepted = false
        }
    }
}

private impl ImageViewer
{
    mtd retire()->bool
    {
        if not .load.retire() do
            return false
        if .loadTimer
        {
            .removeTimer(.loadTimer)
            .loadTimer = null
        }

        return true
    }

    func create(host: Viewer.Host)->*ImageViewer
    {
        let services     = host.services()
        let navigateFile = services.navigateFile
        let result       = Wnd.create'ImageViewer(host.contentParent(), "scope.image")
        result.backgroundStyle      = .View
        result.navigateFile         = navigateFile
        result.reportFailure        = services.reportFailure
        result.reportDetails        = services.reportDetails
        result.reportChromeChanged  = services.reportChromeChanged
        result.reportLoadingChanged = services.reportLoadingChanged
        result.reportFinished       = services.reportFinished
        result.reportShown          = services.reportShown

        result.actions     = host.createCommandGroup(imageCommandWidth(result.themeMetrics()))
        result.info        = host.createInfoGroup(ImageInfoWidth)
        result.information = MediaInfoPanel.create(host)

        with result.previousButton = IconButton.create(result.actions, result.theme().icon(.ChevronLeft, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle = .Left
            .toolTip   = imageStrings().ui_TipPrevious
            .enable(navigateFile != null)
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.navigate(-1)
            }
        }

        with result.nextButton = IconButton.create(result.actions, result.theme().icon(.ChevronRight, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle = .Left
            .toolTip   = imageStrings().ui_TipNext
            .enable(navigateFile != null)
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.navigate(1)
            }
        }

        with result.transformButton = IconButton.create(result.actions, result.theme().icon(.Redo, themeActionIconSize(result.themeMetrics())), {0, 0, themeDropDownButtonWidth(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())}, flags: .CenterContent)
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = imageStrings().ui_TipTransform
            .setArrowPosition(.RightUpward)
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.showTransformMenu()
            }
        }

        result.playModeButton = Viewer.PlaybackButton.create(result.actions, result, services.playback, showSlideDuration: true)
        result.playModeButton.dockStyle = .Left
        result.playModeButton.margin.x  = 8

        with result.playButton = IconButton.create(result.actions, result.theme().icon(.Pause, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle = .Left
            .margin.x  = 10
            .toolTip   = imageStrings().ui_TipPlay
            .hide()
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.setPaused(not view.imageView.movie.isPaused)
                view.refreshFrame()
            }
        }

        with result.timeline = Slider.create(result.actions, {0, 0, 128, 36})
        {
            .dockStyle = .Left
            .margin    = {6, 1, 6, 1}
            .hide()
            .sigChanged += func|view = result|(slider)
            {
                view.imageView.setFrameIndex(cast(s32) Math.round(slider.value()))
            }
        }

        with result.frameLabel = Label.create(result.actions, "", {0, 0, 58, 36}, null, .SecondaryText)
        {
            .dockStyle = .Left
            .setTextAlignment(.Center, .Center)
            .hide()
        }

        with result.zoomLabel = IconButton.create(result.info, {}, {0, 0, ImageInfoWidth - 2 * ViewerInfoControlInset, 32}, "scope.image.zoom", .CenterContent)
        {
            .dockStyle = .Center
            .margin    = {ViewerInfoControlInset, 0, ViewerInfoControlInset, 0}
            .setText("100%")
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(result.theme().createDefaultFontFS(11), .Regular)
            .toolTip    = imageStrings().ui_ZoomMenu
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.showZoomMenu()
            }
        }

        result.imageView = ImageView.create(result)
        result.imageView.dockStyle      = .Center
        result.imageView.sigZoomChanged += func|view = result|(imageView)
        {
            discard imageView
            view.refreshZoom()
        }

        result.imageView.sigFrameChanged += func|view = result|(imageView)
        {
            discard imageView
            view.refreshFrame()
        }

        result.imageView.sigDecodeFailed += func|view = result|(imageView)
        {
            if view.reportFailure do
                view.reportFailure(view, imageView.movie.failureReason.toString())
        }

        result.applyLayout()
        result.setInitialFocus(result.imageView)
        result.load.start(host.fileName(), &loadImageViewerContent)
        result.loadTimer = result.addTimer(Viewer.BackgroundPollInterval)
        return result
    }
}

// Creates the integrated image view.
func createImageViewer(host: Viewer.Host)
{
    let view = ImageViewer.create(host)
    host.attachView(view)
    host.setLifecycle({
        isLoading: func(wnd)->bool { return (cast(*ImageViewer) wnd).loadTimer != null },
        needsLoadingOverlay: func(wnd)->bool { return (cast(*ImageViewer) wnd).loadTimer != null },
        retire: func(wnd)->bool { return (cast(*ImageViewer) wnd).retire() }})
}
