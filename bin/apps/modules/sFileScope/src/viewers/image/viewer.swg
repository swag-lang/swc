#global internal

using Core, Pixel, Gui

private const ImageGlyphSize   = 18.0
private const ImageActionWidth = 326.0
private const GifActionWidth   = 570.0
private const ImageInfoWidth   = 156.0
private const SvgRasterLimit   = 2048.0

struct ImageViewerContent
{
    image:   Image
    movie:   Movie
    details: String
}

internal func loadViewerImage(fileName: string)->Image fail
{
    if Path.lowercaseExtension(fileName) != ".svg" do
        return try Image.load(fileName)

    let source  = try File.readAllText(fileName)
    let drawing = try Svg.Drawing.parse(source.toString())
    let largest = Math.max(drawing.width, drawing.height)
    let scale   = largest > SvgRasterLimit ? SvgRasterLimit / largest : 1
    let width   = cast(s32) Math.max(Math.round(drawing.width * scale), 1)
    let height  = cast(s32) Math.max(Math.round(drawing.height * scale), 1)
    return drawing.rasterize(width, height, 1)
}

private func loadImageViewerContent(fileName: string)->ImageViewerContent fail
{
    var result: retval
    var extension = String.from(Path.extension(fileName) orelse "")
    extension = extension.toLower()
    if extension == ".gif"
    {
        try result.movie.load(fileName)

        // Decode the complete animation on the worker. Once published, playback only exchanges
        // cached frames and cannot stall the GUI on a complex GIF frame.
        result.movie.setFrameIndex(result.movie.frameCount - 1)
        result.movie.setFrameIndex(0)
        let frame = &result.movie.frame
        result.details = Format.toString(imageStrings().ui_DetailsMovie, frame.width, frame.height, frameCountText(result.movie.frameCount))
    }
    else
    {
        result.image   = try loadViewerImage(fileName)
        result.details = Format.toString(imageStrings().ui_DetailsStill, result.image.width, result.image.height, result.image.bitsPerPixel)
    }

    return #move result
}

internal struct ImageViewer
{
    using wnd: Wnd
    details:   String

    #[Swag.Late]
    {
        actions:         *ViewerCommandBar
        info:            *ViewerCommandBar
        previousButton:  *IconButton
        nextButton:      *IconButton
        imageView:       *ImageView
        zoomLabel:       *Label
        transformButton: *IconButton
        playButton:      *IconButton
        timeline:        *Slider
        frameLabel:      *Label
    }

    navigateFile:         #null ViewerNavigateFile
    reportFailure:        #null ViewerReportFailure
    reportDetails:        #null ViewerReportDetails
    reportChromeChanged:  #null ViewerReportChromeChanged
    reportLoadingChanged: #null ViewerReportLoadingChanged
    load:                 ViewerBackgroundLoad'ImageViewerContent
    loadTimer:            #null *Timer
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
            .reportChromeChanged!(me)
    }

    mtd refreshFrame()
    {
        let movie = &.imageView.movie
        if movie.frameCount <= 1 do
            return
        .timeline.setValueWithoutGesture(cast(f32) movie.frameIndex)
        .frameLabel.setText(Format.toString("% / %", movie.frameIndex + 1, movie.frameCount))
        .playButton.setIcon(.theme().icon(movie.isPaused ? .Play : .Pause, ImageGlyphSize))
    }

    mtd showPlayback()
    {
        .actions.resize(GifActionWidth, 36)
        .playButton.show()
        .timeline.show()
        .frameLabel.show()
        .timeline.setBounds(0, cast(f32) .imageView.movie.frameCount - 1, 1)
        .refreshFrame()
        if .reportChromeChanged do
            .reportChromeChanged!(me)
    }

    mtd navigate(delta: s32)
    {
        if .navigateFile do
            .navigateFile!(me, delta)
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

    mtd showTransformMenu(position: Math.Point)
    {
        let texts = imageStrings()
        let menu  = MenuCtrl.createPopup(me, owner: me)
        menu.addItem(texts.ui_RotateCounterClockwise, "sFileScope.image.rotateLeft", .theme().icon(.Undo, ImageGlyphSize))
        menu.addItem(texts.ui_RotateClockwise, "sFileScope.image.rotateRight", .theme().icon(.Redo, ImageGlyphSize))
        menu.addSeparator()
        menu.addItem(texts.ui_MirrorHorizontal, "sFileScope.image.mirrorHorizontal")
        menu.addItem(texts.ui_MirrorVertical, "sFileScope.image.mirrorVertical")
        menu.addSeparator()
        menu.addItem(texts.ui_ResetTransform, "sFileScope.image.reset", .theme().icon(.Update, ImageGlyphSize))

        switch menu.doModal(position, .TopLeft, autoDestroy: true) orelse ""
        {
        case "sFileScope.image.rotateLeft":       .rotateCounterClockwise()
        case "sFileScope.image.rotateRight":      .rotateClockwise()
        case "sFileScope.image.mirrorHorizontal": .mirrorHorizontally()
        case "sFileScope.image.mirrorVertical":   .mirrorVertically()
        case "sFileScope.image.reset":            .resetTransform()
        }
    }
}

private impl IWnd for ImageViewer
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .loadTimer
        {
            evt.accepted = false
            return
        }

        if !.load.isDone() do
            return

        .removeTimer(evt.timer)
        .loadTimer = null
        var content: ImageViewerContent
        .failureReason = .load.finish(&content)
        if !.failureReason.isEmpty()
        {
            if .reportFailure do
                .reportFailure!(me, .failureReason.toString())
            return
        }

        if content.movie.isValid()
        {
            .imageView.exchangeMovie(&content.movie)
            if .imageView.movie.frameCount > 1 do
                .showPlayback()
        }
        else do
            .imageView.setImage(content.image)

        .details = #move content.details
        .refreshZoom()
        .applyLayout()
        .setInitialFocus(.imageView)
        if .reportDetails do
            .reportDetails!(me, .details.toString())
        if .reportLoadingChanged do
            .reportLoadingChanged!(me)
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

        case .Space where .imageView.movie.frameCount > 1:
            .imageView.setPaused(!.imageView.movie.isPaused)
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
        if !.load.retire() do
            return false
        if .loadTimer
        {
            .removeTimer(.loadTimer!)
            .loadTimer = null
        }

        return true
    }

    func create(contentParent, actionParent, infoParent: *Wnd, fileName: string, navigateFile: #null ViewerNavigateFile = null, reportFailure: #null ViewerReportFailure = null, reportDetails: #null ViewerReportDetails = null, reportChromeChanged: #null ViewerReportChromeChanged = null, reportLoadingChanged: #null ViewerReportLoadingChanged = null)->*ImageViewer
    {
        let result = Wnd.create'ImageViewer(contentParent, "sFileScope.image")
        result.backgroundStyle      = .View
        result.navigateFile         = navigateFile
        result.reportFailure        = reportFailure
        result.reportDetails        = reportDetails
        result.reportChromeChanged  = reportChromeChanged
        result.reportLoadingChanged = reportLoadingChanged

        result.actions = ViewerCommandBar.create(actionParent, ImageActionWidth)
        result.info    = ViewerCommandBar.create(infoParent, ImageInfoWidth)

        with result.previousButton = IconButton.create(result.actions, result.theme().icon(.ChevronLeft, ImageGlyphSize), {0, 0, 36, 36})
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

        with result.nextButton = IconButton.create(result.actions, result.theme().icon(.ChevronRight, ImageGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle = .Left
            .margin.z  = 8
            .toolTip   = imageStrings().ui_TipNext
            .enable(navigateFile != null)
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.navigate(1)
            }
        }

        with let zoomOut = IconButton.create(result.actions, result.theme().icon(.ZoomOut, ImageGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = imageStrings().ui_TipZoomOut
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.zoomOut()
            }
        }

        with let zoomIn = IconButton.create(result.actions, result.theme().icon(.ZoomIn, ImageGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.z   = 8
            .toolTip    = imageStrings().ui_TipZoomIn
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.zoomIn()
            }
        }

        with let fit = IconButton.create(result.actions, result.theme().icon(.FitView, ImageGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = imageStrings().ui_TipFit
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.zoomToFit()
            }
        }

        with let actual = IconButton.create(result.actions, result.theme().icon(.ActualSize, ImageGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = imageStrings().ui_TipActual
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.actualSize()
            }
        }

        with result.transformButton = IconButton.create(result.actions, result.theme().icon(.Redo, ImageGlyphSize), {0, 0, 52, 36}, flags: .CenterContent)
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = imageStrings().ui_TipTransform
            .setArrowPosition(.RightDownward)
            .sigPressed += func|view = result|(button)
            {
                let rect = button.surfaceRect()
                view.showTransformMenu({rect.x, rect.bottom()})
            }
        }

        with result.playButton = IconButton.create(result.actions, result.theme().icon(.Pause, ImageGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle = .Left
            .margin.x  = 10
            .toolTip   = imageStrings().ui_TipPlay
            .hide()
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.setPaused(!view.imageView.movie.isPaused)
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

        with result.zoomLabel = Label.create(result.info, "100%", {0, 0, ImageInfoWidth, 32}, null, .SecondaryText | .Ellipsis)
        {
            .dockStyle = .Center
            .setTextAlignment(.Right, .Center)
        }

        result.imageView                = ImageView.create(result)
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

        result.applyLayout()
        result.setInitialFocus(result.imageView)
        result.load.start(fileName, &loadImageViewerContent)
        result.loadTimer = result.addTimer(ViewerBackgroundPollInterval)
        return result
    }
}

// Creates the integrated image view.
func createImageViewer(request: const *ViewerRequest, result: *ViewerResult)
{
    let view = ImageViewer.create(request.contentParent, request.actionParent, request.infoParent, request.fileName, request.navigateFile, request.reportFailure, request.reportDetails, request.reportChromeChanged, request.reportLoadingChanged)
    result.view                = view
    result.actions             = view.actions
    result.info                = view.info
    result.isLoading           = func(wnd)->bool { return (cast(*ImageViewer) wnd).loadTimer != null }
    result.needsLoadingOverlay = func(wnd)->bool { return (cast(*ImageViewer) wnd).loadTimer != null }
    result.retire              = func(wnd)->bool { return (cast(*ImageViewer) wnd).retire() }
}
