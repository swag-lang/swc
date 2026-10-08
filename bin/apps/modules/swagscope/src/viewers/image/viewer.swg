#global internal
#global namespace Viewers.Picture

using Core, Pixel, Gui

// Describes the picture viewer to the host.
//
// It offers itself for every raster format the imaging module can decode, plus SVG, so a decoder
// added there reaches the viewer without a list to update here.
func viewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "image"
        .staticName   = "Image"
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Image)
        .create       = &createViewer
        .smokeFixture = "sample.svg"
    }

    for format in Image.decodableFormats() do
        result.addSelectors(format.extensions)
    result.addSelectors(".svg")
    return result
}

private const InfoWidth      = 156.0
private const SvgRasterLimit = 2048.0

private func commandWidth(metrics: const *ThemeMetrics)->f32         => 2 * themeActionButtonSize(metrics) + 2 * themeDropDownButtonWidth(metrics) + 16
private func imageSetCommandWidth(metrics: const *ThemeMetrics)->f32 => commandWidth(metrics) + themeActionButtonSize(metrics) + 10 + 128 + 12 + 58

// What the worker decodes for the picture viewer, handed to the view in one move.
struct ViewerContent
{
    image:       Image
    movie:       Movie
    drawing:     Svg.Drawing     // Vector document, for a format that has no pixels of its own.
    facts:       ViewerFacts
    information: MediaInfoData
}

// Rasterizes a vector document at the size it declares, bounded so a poster-sized view box
// cannot ask for an unbounded bitmap.
//
// The viewer itself shows the drawing as vectors, so this is for the callers that genuinely
// need pixels — a thumbnail, an export, a comparison against a decoded picture.
func loadViewerImage(fileName: string)->Image fail
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
    let width   = cast(s32, Math.max(Math.round(drawing.width * scale), 1))
    let height  = cast(s32, Math.max(Math.round(drawing.height * scale), 1))
    return drawing.rasterize(width, height, 1)
}

// Parses the vector document of an SVG file.
func loadViewerDrawing(fileName: string)->Svg.Drawing fail
{
    var file   = try File.MappedFile.open(fileName)
    let region = try file.mapAll()
    return try Svg.Drawing.parse(cast(string, region.bytes()))
}

private func loadViewerContent(fileName: string)->ViewerContent fail
{
    var result: retval
    let extension = String.toLower(Path.extension(fileName))
    result.information.add(.Image, group: true)
    result.information.add(.Format, extension.toUpper())
    if extension == ".svg"
    {
        result.drawing      = try loadViewerDrawing(fileName)
        result.facts.width  = formatViewBoxExtent(result.drawing.width)
        result.facts.height = formatViewBoxExtent(result.drawing.height)
        result.facts.vector = true
        result.information.add(.Dimensions, Format.toString("% × %", formatViewBoxExtent(result.drawing.width), formatViewBoxExtent(result.drawing.height)))
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
        result.information.add(.Dimensions, Format.toString("% × % px", frame.width, frame.height))
        result.information.add(.PixelFormat, Format.toString("%", frame.pixelFormat))
        result.information.add(.Depth, Format.toString("%", frame.bitsPerPixel))
        if result.movie.frameCount > 1 do
            result.information.add(.Frames, Format.toString("%", result.movie.frameCount))
        else do
            result.image = frame[]

        result.information.addImageMetadata(frame.metadata.toSlice(), extension == ".png" or extension == ".apng")
        if result.movie.frameCount <= 1 do
            result.movie.clear()
    }

    return result
}

// Writes one view-box extent the way the document authored it: a whole number stays whole.
private func formatViewBoxExtent(value: f32)->String
{
    if value == Math.round(value) do
        return Format.toString("%", cast(s64, value))
    return Format.toString("%", value)
}

// Keeps decoded facts independent of the language active while the worker was running.
struct ViewerFacts
{
    width, height: String
    bits:          u32
    frames:        s32
    vector:        bool
}

private impl ViewerFacts
{
    mtd const text()->String
    {
        if .vector do
            return Format.toString(texts().ui_DetailsVector, .width, .height)
        if .frames > 1 do
            return Format.toString(texts().ui_DetailsMovie, .width, .height, frameCountText(.frames))
        return Format.toString(texts().ui_DetailsStill, .width, .height, .bits)
    }
}

// The picture viewer: a still or animated image, its frame and zoom controls, the transform menu,
// and the media information panel.
struct Panel
{
    using wnd: Wnd
    details:   String
    facts:     ViewerFacts

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

    services:           Viewer.HostServices
    lastCompletedLoops: u32      // Playback cycles observed by the latest frame refresh.
    handedOff:          bool     // The host was told the animation has run its cycle, and answered that it moves on.
    load:               Viewer.BackgroundLoad'ViewerContent
    failureReason:      String
}

impl Panel
{
    mtd refreshZoom()
    {
        let zoom = cast(s32, Math.round(.imageView.effectiveZoom() * 100))
        if .imageView.rotationQuarterTurns or .imageView.isMirrored
        {
            let angle = .imageView.rotationQuarterTurns * 90
            if .imageView.isMirrored do
                .zoomLabel.setText(Format.toString("% % · %° · %", zoom, "%", angle, texts().word_Mirrored))
            else do
                .zoomLabel.setText(Format.toString("% % · %°", zoom, "%", angle))
        }
        else
        {
            .zoomLabel.setText(Viewer.zoomText(zoom))
        }

        .services.chromeChanged(me)
    }

    mtd refreshFrame()
    {
        let movie = &.imageView.movie
        if movie.frameCount <= 1 do
            return
        .timeline.setValueWithoutGesture(cast(f32, movie.frameIndex))
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
        if .handedOff or not .services.reportFinished do
            return
        switch #complete .services.finished(me)
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
        .timeline.setBounds(0, cast(f32, .imageView.movie.frameCount) - 1, 1)
        .refreshFrame()
        .services.chromeChanged(me)
    }

    mtd navigate(delta: s32) => .services.navigate(me, delta)

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
        let texts = texts()
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
        menu.addItem(texts().ui_TipFit, "scope.image.zoomFit", .theme().icon(.FitView, themeRowIconSize(.themeMetrics())), rightName: "F")
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

private impl IWnd for Panel
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged
        {
            .previousButton.toolTip  = texts().ui_TipPrevious
            .nextButton.toolTip      = texts().ui_TipNext
            .transformButton.toolTip = texts().ui_TipTransform
            .playButton.toolTip      = texts().ui_TipPlay
            .zoomLabel.toolTip       = texts().ui_ZoomMenu
            .refreshZoom()
            if not .facts.width.isEmpty()
            {
                .details = .facts.text()
                .services.showDetails(me, .details)
            }
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .load.timer
        {
            evt.accepted = false
            return
        }

        if not .load.poll() do
            return

        var content: ViewerContent
        .failureReason = .load.finish(&content)
        if not .failureReason.isEmpty()
        {
            .services.failed(me, .failureReason)
            return
        }

        if content.movie.isValid()
        {
            if .services.reportFinished do
                content.movie.loops = false
            .imageView.exchangeMovie(&content.movie)
            if .imageView.movie.frameCount > 1 do
                .showPlayback()
        }
        elif content.drawing.width > 0 and content.drawing.height > 0
        {
            .imageView.setDrawing(#move content.drawing)
        }
        else
        {
            .imageView.takeImage(&content.image)
        }

        .facts   = #move content.facts
        .details = .facts.text()
        .information.publish(&content.information)
        .refreshZoom()
        .applyLayout()
        .setInitialFocus(.imageView)
        .services.showDetails(me, .details)
        .services.loadingChanged(me)

        // A still picture has no end of its own; the host's slideshow gives it one.
        let still = not .imageView.movie.isValid() or .imageView.movie.frameCount <= 1
        if still do
            .services.shown(me)
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
            if .services.navigateFile do
                .navigate(-1)
            else do
                evt.accepted = false

        case .Right where evt.modifiers == .None:
            if .services.navigateFile do
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

private impl Panel
{
    mtd retire()->bool
    {
        return .load.retire()
    }

    func create(host: Viewer.Host)->*Panel
    {
        let services    = host.services()
        with let result = Wnd.create'Panel(host.contentParent(), "scope.image")
        {
            .backgroundStyle = .View
            .services        = services
        }

        result.actions     = host.createCommandGroup(commandWidth(result.themeMetrics()))
        result.info        = host.createInfoGroup(InfoWidth)
        result.information = MediaInfoPanel.create(host)

        result.createCommandBar(services.playback)
        result.createFrameControls()
        result.createZoomControl()
        result.createImageView()

        result.applyLayout()
        result.setInitialFocus(result.imageView)
        result.load.startPolled(result, host.fileName(), &loadViewerContent)
        return result
    }

    // Creates the folder navigation, the transform menu, and the play-mode menu in the command group.
    mtd createCommandBar(playback: Viewer.PlaybackApi)
    {
        with .previousButton = IconButton.create(.actions, .theme().icon(.ChevronLeft, themeActionIconSize(.themeMetrics())), {0, 0, themeActionButtonSize(.themeMetrics()), themeActionButtonSize(.themeMetrics())})
        {
            .dockStyle = .Left
            .toolTip   = texts().ui_TipPrevious
            .enable(me.services.navigateFile != null)
            .sigPressed += func|view = me|(?) { view.navigate(-1) }
        }

        with .nextButton = IconButton.create(.actions, .theme().icon(.ChevronRight, themeActionIconSize(.themeMetrics())), {0, 0, themeActionButtonSize(.themeMetrics()), themeActionButtonSize(.themeMetrics())})
        {
            .dockStyle = .Left
            .toolTip   = texts().ui_TipNext
            .enable(me.services.navigateFile != null)
            .sigPressed += func|view = me|(?) { view.navigate(1) }
        }

        with .transformButton = IconButton.create(.actions, .theme().icon(.Redo, themeActionIconSize(.themeMetrics())), {0, 0, themeDropDownButtonWidth(.themeMetrics()), themeActionButtonSize(.themeMetrics())}, flags: .CenterContent)
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = texts().ui_TipTransform
            .setArrowPosition(.RightUpward)
            .sigPressed += func|view = me|(?) { view.showTransformMenu() }
        }

        with .playModeButton = Viewer.PlaybackButton.create(.actions, me, playback, showSlideDuration: true)
        {
            .dockStyle = .Left
            .margin.x  = 8
        }
    }

    // Creates the transport of an animated picture, hidden until the picture turns out to have frames.
    mtd createFrameControls()
    {
        with .playButton = IconButton.create(.actions, .theme().icon(.Pause, themeActionIconSize(.themeMetrics())), {0, 0, themeActionButtonSize(.themeMetrics()), themeActionButtonSize(.themeMetrics())})
        {
            .dockStyle = .Left
            .margin.x  = 10
            .toolTip   = texts().ui_TipPlay
            .hide()
            .sigPressed += func|view = me|(?)
            {
                view.imageView.setPaused(not view.imageView.movie.isPaused)
                view.refreshFrame()
            }
        }

        with .timeline = Slider.create(.actions, {0, 0, 128, 36})
        {
            .dockStyle = .Left
            .margin    = {6, 1, 6, 1}
            .hide()
            .sigChanged += func|view = me|(slider) { view.imageView.setFrameIndex(cast(s32, Math.round(slider.value()))) }
        }

        with .frameLabel = Label.create(.actions, "", {0, 0, 58, 36}, null, .SecondaryText)
        {
            .dockStyle = .Left
            .setTextAlignment(.Center, .Center)
            .hide()
        }
    }

    // Creates the zoom menu button in the information group.
    mtd createZoomControl()
    {
        .zoomLabel = Viewer.createZoomButton(.info, "scope.image.zoom", texts().ui_ZoomMenu, InfoWidth - 2 * Viewer.ZoomButtonInset)
        .zoomLabel.sigPressed += func|view = me|(?) { view.showZoomMenu() }
    }

    // Creates the picture view and keeps the zoom readout and the frame transport in step with it.
    mtd createImageView()
    {
        with .imageView = ImageView.create(me)
        {
            .dockStyle      = .Center
            .sigZoomChanged += func|view = me|(?)
            {
                view.refreshZoom()
            }

            .sigFrameChanged += func|view = me|(?)
            {
                view.refreshFrame()
            }

            .sigDecodeFailed += func|view = me|(imageView)
            {
                view.services.failed(view, imageView.movie.failureReason)
            }
        }
    }
}

// Creates the integrated image view.
func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    host.attachView(view)

    host.setLifecycle(Viewer.loadLifecycle(view))
}
