#global internal
#global namespace Viewers.Picture

using Core, Pixel, Gui

// Describes the picture viewer to the host.
//
// It offers itself for every raster format the imaging module can decode, plus SVG, so a decoder
// added there reaches the viewer without a list to update here.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "image"
        .staticName   = "Image"
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Image)
        .create       = &createViewer
        .thumbnail    = &loadThumbnail
        .smokeFixture = "sample.svg"
    }

    for format in Image.decodableFormats() do
        result.addSelectors(format.extensions)
    result.addSelectors(".svg")
    return result
}

private const InfoWidth      = Viewer.ZoomSlotWidth
private const SvgRasterLimit = 2048.0

private func commandWidth(metrics: const *ThemeMetrics)->f32 => 2 * themeActionButtonSize(metrics) + 2 * themeDropDownButtonWidth(metrics) + 16
private func imageSetCommandWidth(metrics: const *ThemeMetrics, animated: bool)->f32 =>
    Viewer.pageControlWidth(metrics) + 2 * themeDropDownButtonWidth(metrics) + 16 + 128 + 12 +
    (animated ? themeActionButtonSize(metrics) + 10 : 0)

// What the worker decodes for the picture viewer, handed to the view in one move.
struct ViewerContent
{
    image:       Image
    movie:       Movie
    drawing:     Svg.Drawing     // Vector document, for a format that has no pixels of its own.
    facts:       ViewerFacts
    information: MediaInfoData
}

// Decodes a picture standing upright, as the EXIF orientation a camera recorded asks, or
// rasterizes a vector document at the size it declares, bounded so a poster-sized view box cannot
// ask for an unbounded bitmap.
//
// The viewer itself shows the drawing as vectors, so this is for the callers that genuinely
// need pixels — a thumbnail, an export, a comparison against a decoded picture.
func loadViewerImage(fileName: string)->Image fail
{
    if Path.lowercaseExtension(fileName) != ".svg"
    {
        var file   = try File.MappedFile.open(fileName)
        let region = try file.mapAll()
        var image  = try Image.decode(fileName, region.bytes())
        image.orient(Exif.orientationOf(image.metadata.toSlice()))
        return image
    }

    let drawing = try loadViewerDrawing(fileName)
    let largest = Math.max(drawing.width, drawing.height)
    let scale   = largest > SvgRasterLimit ? SvgRasterLimit / largest : 1
    let width   = cast(s32, Math.max(Math.round(drawing.width * scale), 1))
    let height  = cast(s32, Math.max(Math.round(drawing.height * scale), 1))
    return drawing.rasterize(width, height, 1)
}

// Produces a thumbnail whose longest side is at most `maxSide`.
//
// A drawing is rasterized straight at that size: filling its pixels is the whole cost, and
// filling them at the drawing's own size only to shrink the result costs ten times as much for a
// softer picture than sampling twice per axis at the size that is kept.
func loadThumbnail(fileName: string, maxSide: u32)->Image fail
{
    if Path.lowercaseExtension(fileName) != ".svg" do
        return try loadViewerImage(fileName)

    let drawing = try loadViewerDrawing(fileName)
    let largest = Math.max(drawing.width, drawing.height, 1)
    let scale   = Math.min(cast(f32, maxSide) / largest, 1)
    let width   = cast(s32, Math.max(Math.round(drawing.width * scale), 1))
    let height  = cast(s32, Math.max(Math.round(drawing.height * scale), 1))
    return drawing.rasterize(width, height, 2)
}

// Parses the vector document of an SVG file.
func loadViewerDrawing(fileName: string)->Svg.Drawing fail
{
    var file   = try File.MappedFile.open(fileName)
    let region = try file.mapAll()
    return try Svg.Drawing.parse(cast(string, region.bytes()))
}

// Loads an image for the viewer: SVG as a vector drawing, anything else through the movie decoder,
// keeping the frames only for an animation. Also fills the facts and information rows shown beside
// it.
private func loadViewerContent(fileName: string)->ViewerContent fail
{
    var result: #returntype
    let extension = String.toLower(Path.extension(fileName))
    result.information.add(.Image, group: true)
    result.information.add(.Format, String.toUpper(extension.toString()[Math.min(extension.count, 1) to]))
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
        let frame    = &result.movie.frame
        let animated = result.movie.frameCount > 1

        // A camera stores a portrait photograph on its side and records how to stand it up. A
        // still picture is turned once here, so every reading of it, rotations included, starts
        // upright.
        var shown = frame
        if not animated
        {
            result.image = frame[]
            result.image.orient(Exif.orientationOf(frame.metadata.toSlice()))
            shown = &result.image
        }

        result.facts.width  = Format.toString("%", shown.width)
        result.facts.height = Format.toString("%", shown.height)
        result.facts.bits   = frame.bitsPerPixel
        result.facts.frames = result.movie.frameCount

        // Adding information can move what 'result' holds: read the frame first.
        let dimensions  = Format.toString("% × % px", shown.width, shown.height)
        let pixelFormat = Reflection.enumName(PixelFormat, &frame.pixelFormat, fullyQualified: false)
        let depth       = Format.toString("%", frame.bitsPerPixel)
        var transparency: String
        if not animated and frame.pixelFormat.hasAlpha() do
            transparency = transparencyText(shown)
        result.information.add(.Dimensions, dimensions)
        result.information.add(.PixelFormat, pixelFormat)
        result.information.add(.Depth, depth)
        if animated do
            result.information.add(.Frames, Format.toString("%", result.movie.frameCount))
        if transparency.count do
            result.information.add(.Transparency, transparency)

        result.information.addImageMetadata(result.movie.frame.metadata.toSlice(), extension == ".png" or extension == ".apng")
        if result.movie.frameCount <= 1 do
            result.movie.clear()
    }

    return result
}

// Says how much of a picture its alpha channel hides: none of it, or the share of pixels it makes
// wholly transparent and the share it lets show through. Read from 8-bit alpha only; empty for
// other formats.
func transparencyText(image: const *Image)->String
{
    var step = 4'u64
    switch image.pixelFormat
    {
    case .RGBA8, .BGRA8: step = 4
    case .GrayAlpha8:    step = 2
    default: return {}
    }

    let offset = step - 1

    var transparent, partial: u64
    let bytes = image.pixels.toSlice()
    var at    = offset
    while at < bytes.count
    {
        let alpha = bytes[at]
        if alpha == 0 do
            transparent += 1
        elif alpha != 255 do
            partial += 1
        at += step
    }

    if not transparent and not partial do
        return String.from(texts().ui_Opaque)
    let total = Math.max(cast(u64, image.width) * cast(u64, image.height), 1)
    var result: String
    if transparent do
        result = Format.toString(texts().ui_Transparent, shareText(transparent, total))
    if partial
    {
        if not result.isEmpty() do
            result += " · "
        result += Format.toString(texts().ui_Translucent, shareText(partial, total))
    }

    return result
}

// Writes `count` out of `total` as a whole percentage, or `<1%` for a share too small to round.
func shareText(count, total: u64)->String
{
    let percent = count * 100 / total
    if not percent do
        return String.from("<1%")
    var result = Format.toString("%", percent)
    result += "%"
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
        previousPage:    *IconButton
        nextPage:        *IconButton
        frameLabel:      *Label
    }

    services:           Viewer.HostServices
    information:        MediaInfoData
    lastCompletedLoops: u32      // Playback cycles observed by the latest frame refresh.
    handedOff:          bool     // The host was told the animation has run its cycle, and answered that it moves on.
    load:               Viewer.BackgroundLoad'ViewerContent
    failureReason:      String
    shownItem:          String         // What the summary last said of the item in view.
    reported:           String         // The details line the host was last given.
    probed:             Math.Point     // Pixel of the stored picture the pointer last read.
    hasProbe:           bool           // Whether the pointer has read a pixel of the picture shown.
}

impl Panel
{
    mtd describeInformation(sheet: *InfoSheet)
    {
        .information.describe(sheet)
    }

    // Returns the scale the picture is painted at, in percent, as the zoom readout shows it.
    mtd zoomPercent()->u32 => cast(u32, Math.round(.imageView.effectiveZoom() * 100))

    // Keeps the zoom readout numeric and reports orientation at the transform menu.
    mtd refreshZoom()
    {
        .zoomLabel.setText(Viewer.zoomText(.zoomPercent()))
        .transformButton.setIconColor(.imageView.rotationQuarterTurns != 0 or .imageView.isMirrored ? .themeColors().arc : .themeColors().softText)
        .transformButton.toolTip = texts().ui_TipTransform
        if .imageView.rotationQuarterTurns or .imageView.isMirrored
        {
            let angle = .imageView.rotationQuarterTurns * 90
            .transformButton.toolTip = Format.toString("% · %°", texts().ui_TipTransform, angle)
            if .imageView.isMirrored do
                .transformButton.toolTip = Format.toString("% · %", .transformButton.toolTip, texts().word_Mirrored)
        }

        .services.chromeChanged(me)
    }

    // Returns what the image set says of the item in view when the items stand apart — an icon
    // size, a page, a layer or a texture level — rather than following one another in time: its
    // size, then its place in a texture and its name. Empty for a single image or an animation.
    mtd itemText()->String
    {
        var result: String
        let movie = &.imageView.movie
        if movie.frameCount <= 1 do
            return result
        let info = movie.frameInfo()
        if not info do
            return result

        // A paused animation says how long its frame stays on screen; a playing one says nothing,
        // the frames passing too quickly to be read.
        if info.kind == .Animation
        {
            if movie.isPaused do
                result = Format.toString(texts().ui_FrameDelay, cast(u32, Math.round(movie.currentFrameDuration() * 1000)))
            return result
        }

        result = Format.toString("% × %", info.width, info.height)
        if info.kind == .Texture
        {
            if info.level do
                result += Format.toString(" · %", Format.toString(texts().ui_ItemLevel, info.level))
            if info.layer do
                result += Format.toString(" · %", Format.toString(texts().ui_ItemLayer, info.layer))
            if info.face do
                result += Format.toString(" · %", Format.toString(texts().ui_ItemFace, info.face))
        }

        if not info.name.isEmpty() do
            result += Format.toString(" · %", info.name)
        return result
    }

    // Returns the summary of the picture, followed by what the image set says of the item in view.
    mtd shownDetails()->String
    {
        let item = .itemText()
        return item.isEmpty() ? String.from(.details) : Format.toString("% · %", .details, item)
    }

    // Gives the host `details` unless they are what it shows already. The pointer sends many moves
    // over one pixel, or beside the picture, and each report lays the footer out again and
    // refreshes an open information sheet.
    mtd reportDetails(details: String)
    {
        if details == .reported do
            return
        .reported = details
        .services.showDetails(me, details)
    }

    // Updates the frame controls of an animation, and ends the cycle the first time the movie
    // completes a loop. Over a set of independent images, the summary follows the item in view.
    mtd refreshFrame()
    {
        let movie = &.imageView.movie
        if movie.frameCount <= 1 do
            return
        let item = .itemText()
        if item != .shownItem
        {
            .shownItem = item
            .reportDetails(.shownDetails())
        }

        .timeline.setValueWithoutGesture(cast(f32, movie.frameIndex))
        .frameLabel.setText(Viewer.pageText(cast(u64, movie.frameIndex), cast(u64, movie.frameCount)))
        .previousPage.enable(movie.frameIndex > 0)
        .nextPage.enable(movie.frameIndex + 1 < movie.frameCount)
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
        let width = imageSetCommandWidth(.themeMetrics(), .imageView.movie.isAnimated())
        .actions.preferredSize.x = width
        .actions.resize(width, themeActionButtonSize(.themeMetrics()))
        .playButton.show(.imageView.movie.isAnimated())
        .timeline.show()
        .frameLabel.show()
        .previousPage.show()
        .nextPage.show()
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
        menu.addItem(texts.ui_RotateCounterClockwise, "scope.image.rotateLeft", .theme().icon(.Undo, themeRowIconSize(.themeMetrics())), rightName: "Shift R")
        menu.addItem(texts.ui_RotateClockwise, "scope.image.rotateRight", .theme().icon(.Redo, themeRowIconSize(.themeMetrics())), rightName: "R")
        menu.addSeparator()
        menu.addItem(texts.ui_MirrorHorizontal, "scope.image.mirrorHorizontal", .theme().icon(.MirrorHorizontal, themeRowIconSize(.themeMetrics())), rightName: "H")
        menu.addItem(texts.ui_MirrorVertical, "scope.image.mirrorVertical", .theme().icon(.MirrorVertical, themeRowIconSize(.themeMetrics())), rightName: "V")
        menu.addSeparator()
        menu.addItem(texts.ui_ResetTransform, "scope.image.reset", .theme().icon(.Update, themeRowIconSize(.themeMetrics())), rightName: "Ctrl R")
        if .imageView.picture()
        {
            menu.addSeparator()
            menu.addItem(texts.ui_CopyImage, "scope.image.copy", .theme().icon(.Copy, themeRowIconSize(.themeMetrics())), rightName: "Ctrl C")
        }

        return menu
    }

    // Returns the color of the pixel the pointer last read, as `#RRGGBB`, or `#RRGGBBAA` when it is
    // not opaque; empty when no pixel of the bitmap shown has been read.
    mtd probedColorText()->String
    {
        var result: #returntype
        let picture = .imageView.picture()
        if not .hasProbe or not picture do
            return result
        let x = cast(s32, .probed.x)
        let y = cast(s32, .probed.y)
        if x >= picture.width or y >= picture.height do
            return result
        let color = picture.pixelColor(x, y)
        result = Format.toString("#%{X02}%{X02}%{X02}", color.r, color.g, color.b)
        if color.a != 255 do
            result += Format.toString("%{X02}", color.a)
        return result
    }

    // Puts the color of the pixel the pointer last read on the clipboard, as the lens names it.
    mtd copyProbedColor()
    {
        let color = .probedColorText()
        if color.count do
            Clipboard.setString(color)
    }

    // Puts the picture on the clipboard as decoded and stood upright, without the view's own
    // rotation or zoom.
    mtd copyPicture()
    {
        let picture = .imageView.picture()
        if picture do
            Clipboard.addImage(picture[])
    }

    // Gives the lens the neighbouring pictures, the orientation, the zoom, the animation and the
    // play mode of the picture.
    mtd describeLens(entries: *Viewer.LensEntries)
    {
        let texts = texts()
        let lens  = appStrings()
        entries.add(texts.ui_TipPrevious, .ChevronLeft, func|view = me|() { view.navigate(-1) }, shortcut: Input.formatKeyShortcut(.None, .Left))
        entries.add(texts.ui_TipNext, .ChevronRight, func|view = me|() { view.navigate(1) }, shortcut: Input.formatKeyShortcut(.None, .Right))
        entries.add(texts.ui_RotateCounterClockwise, .Undo, func|view = me|() { view.rotateCounterClockwise() }, shortcut: Input.formatKeyShortcut(.Shift, .R))
        entries.add(texts.ui_RotateClockwise, .Redo, func|view = me|() { view.rotateClockwise() }, shortcut: Input.formatKeyShortcut(.None, .R))
        entries.add(texts.ui_MirrorHorizontal, .MirrorHorizontal, func|view = me|() { view.mirrorHorizontally() }, shortcut: Input.formatKeyShortcut(.None, .H))
        entries.add(texts.ui_MirrorVertical, .MirrorVertical, func|view = me|() { view.mirrorVertically() }, shortcut: Input.formatKeyShortcut(.None, .V))
        entries.add(texts.ui_ResetTransform, .Update, func|view = me|() { view.resetTransform() }, shortcut: Input.formatKeyShortcut(.Control, .R))
        if .imageView.picture() do
            entries.add(texts.ui_CopyImage, .Copy, func|view = me|() { view.copyPicture() }, shortcut: Input.formatKeyShortcut(.Control, .C))

        // The pixel the pointer read last, whose color the reader may want elsewhere.
        let color = .probedColorText()
        if color.count do
            entries.add(Format.toString(texts.ui_CopyColor, color, Format.toString(texts.ui_ProbePixel, cast(s32, .probed.x), cast(s32, .probed.y))), .Copy, func|view = me|() { view.copyProbedColor() }, shortcut: Input.formatKeyShortcut(Input.KeyModifiers.Control | .Shift, .C))

        // The picture zooms by factors, far past the shared bounds, so only actual size, the 100 %
        // of the readout, is the shared row; it reads as chosen while the picture shows at it.
        entries.add(texts.ui_TipFit, .FitView, func|view = me|() { view.imageView.zoomToFit() }, checked: .imageView.isFitted, shortcut: Input.formatKeyShortcut(.None, .F))
        entries.add(lens.cmd_ZoomIn, .ZoomIn, func|view = me|() { view.imageView.zoomIn() }, shortcut: Input.formatKeyShortcut(.Control, .OemPlus))
        entries.add(lens.cmd_ZoomOut, .ZoomOut, func|view = me|() { view.imageView.zoomOut() }, shortcut: Input.formatKeyShortcut(.Control, .OemMinus))
        entries.addZoom(.Reset, .zoomPercent(), func|view = me|() { view.imageView.actualSize() })
        if .imageView.movie.frameCount > 1
        {
            // An animation steps by frames, an image set by pages.
            let info      = .imageView.movie.frameInfo()
            let animation = info and info.kind == .Animation
            entries.add(animation ? lens.cmd_PreviousFrame : lens.ui_PreviousPage, .ChevronLeft, func|view = me|() { view.turnPage(-1) }, disabled: not .previousPage.isEnabled(), shortcut: Input.formatKeyShortcut(.Control, .PageUp))
            entries.add(animation ? lens.cmd_NextFrame : lens.ui_NextPage, .ChevronRight, func|view = me|() { view.turnPage(1) }, disabled: not .nextPage.isEnabled(), shortcut: Input.formatKeyShortcut(.Control, .PageDown))
        }

        entries.add(lens.cmd_ZoomMenu, .ZoomIn, func|view = me|() { view.showZoomMenu() })
        if .playButton.isLocallyVisible()
        {
            entries.add(.imageView.movie.isPaused ? lens.cmd_Play : lens.cmd_Pause,
                        .imageView.movie.isPaused ? .Play : .Pause,
                        func|view = me|()
                        {
                            view.imageView.setPaused(not view.imageView.movie.isPaused)
                            view.refreshFrame()
                        },
                        shortcut: Input.formatKeyShortcut(.None, .Space))
        }

        entries.add(lens.cmd_PlayMode, .RepeatAll, func|view = me|() { view.playModeButton.showOptions() })
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
        case "scope.image.copy":             .copyPicture()
        }
    }

    mtd showZoomMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem("25 %", "scope.image.zoom25", .theme().icon(.ZoomOut, themeRowIconSize(.themeMetrics())))
        menu.addItem("50 %", "scope.image.zoom50", .theme().icon(.ZoomOut, themeRowIconSize(.themeMetrics())))
        menu.addItem("100 %", "scope.image.zoom100", .theme().icon(.ActualSize, themeRowIconSize(.themeMetrics())))
        menu.addItem("200 %", "scope.image.zoom200", .theme().icon(.ZoomIn, themeRowIconSize(.themeMetrics())))
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
            .previousPage.toolTip    = appStrings().ui_PreviousPage
            .nextPage.toolTip        = appStrings().ui_NextPage
            .transformButton.toolTip = texts().ui_TipTransform
            .playButton.toolTip      = texts().ui_TipPlay
            .zoomLabel.toolTip       = texts().ui_ZoomMenu
            .refreshZoom()
            if not .facts.width.isEmpty()
            {
                .details = .facts.text()
                .reportDetails(.shownDetails())
            }
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if not .load.claim(evt)
        {
            evt.accepted = false
            return
        }

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
            if not .imageView.exchangeMovie(&content.movie)
            {
                .services.failed(me, "renderer cannot allocate the movie texture")
                return
            }

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

        .facts       = #move content.facts
        .details     = .facts.text()
        .information = #move content.information
        .refreshZoom()
        .applyLayout()
        .reportDetails(.shownDetails())
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

        case .Add, .OemPlus where evt.modifiers == .Control:
            .imageView.zoomIn()

        case .Subtract, .OemMinus where evt.modifiers == .Control:
            .imageView.zoomOut()

        case .D0 where evt.modifiers.has(.Control):
            .imageView.actualSize()

        case .F where evt.modifiers == .None:
            .imageView.zoomToFit()

        case .R where evt.modifiers == .None:
            .rotateClockwise()

        case .R where evt.modifiers == .Shift:
            .rotateCounterClockwise()

        case .R where evt.modifiers == .Control:
            .resetTransform()

        case .C where evt.modifiers == .Control:
            .copyPicture()

        case .C where evt.modifiers == (Input.KeyModifiers.Control | .Shift):
            .copyProbedColor()

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
    internal mtd retire()->bool
    {
        return .load.retire()
    }

    // Builds the image panel: commands, information group and media details, frame and zoom
    // controls, and the image view. Loads the image in the background.
    func create(host: Viewer.Host)->*Panel
    {
        let services    = host.services()
        with let result = Wnd.create'Panel(host.contentParent(), "scope.image")
        {
            .backgroundStyle = .View
            .services        = services
        }

        if host.isEmbedded()
        {
            result.actions = Wnd.create'Wnd(result)
            result.actions.hide()
        }
        else
        {
            result.actions = host.createCommandGroup(commandWidth(result.themeMetrics()))
        }

        result.info = host.createInfoGroup(InfoWidth)

        result.createCommandBar(services.playback)
        result.createFrameControls()
        result.createZoomControl()
        result.createImageView()
        result.actions.hookOnEvent = func|view = result|(_, evt)->bool
        {
            if evt is ResizeEvent
            {
                let paged = view.imageView.movie.frameCount > 1
                let width = view.actions.position.width
                view.timeline.show(paged and width >= imageSetCommandWidth(view.themeMetrics(), view.imageView.movie.isAnimated()))
                view.previousButton.show(not paged)
                view.nextButton.show(not paged)
                view.transformButton.show(not paged or width >= Viewer.pageControlWidth(view.themeMetrics()) + themeDropDownButtonWidth(view.themeMetrics()) + 8)
                view.playModeButton.show(not paged or width >= imageSetCommandWidth(view.themeMetrics(), false) - 128 - 12 + (view.imageView.movie.isAnimated() ? themeActionButtonSize(view.themeMetrics()) + 10 : 0))
            }

            return false
        }

        result.hookOnChildEvent = func|view = result, nested = host.isEmbedded()|(_, evt)->bool
        {
            if evt is KeyEvent as key
            {
                let direction = Viewer.pageKeyDirection(key)
                if direction and not nested and view.imageView.movie.frameCount > 1
                {
                    view.turnPage(direction)
                    return true
                }
            }

            return false
        }

        result.applyLayout()
        result.load.start(host.fileName(), &loadViewerContent, result)
        return result
    }

    // Creates the folder navigation, the transform menu, and the play-mode menu in the command group.
    mtd createCommandBar(playback: Viewer.PlaybackApi)
    {
        with .previousButton = Viewer.createActionButton(.actions, .ChevronLeft)
        {
            .dockStyle = .Left
            .toolTip   = texts().ui_TipPrevious
            .enable(me.services.navigateFile != null)
            .sigPressed += func|view = me|(_) { view.navigate(-1) }
        }

        with .nextButton = Viewer.createActionButton(.actions, .ChevronRight)
        {
            .dockStyle = .Left
            .toolTip   = texts().ui_TipNext
            .enable(me.services.navigateFile != null)
            .sigPressed += func|view = me|(_) { view.navigate(1) }
        }

        with .transformButton = Viewer.createActionDropDown(.actions, .Redo)
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = texts().ui_TipTransform
            .setArrowPosition(.RightUpward)
            .sigPressed += func|view = me|(_) { view.showTransformMenu() }
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
        with .playButton = Viewer.createActionButton(.actions, .Pause)
        {
            .dockStyle = .Left
            .margin.x  = 10
            .toolTip   = texts().ui_TipPlay
            .hide()
            .sigPressed += func|view = me|(_)
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

        with .previousPage = Viewer.createPageStep(.actions, -1)
        {
            .hide()
            .sigPressed += func|view = me|(_) { view.turnPage(-1) }
        }

        with .frameLabel = Label.create(.actions, "", {0, 0, Viewer.PageReadoutWidth, 36}, null, .SecondaryText)
        {
            .dockStyle = .Left
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Center, .OpticalCenter)
            .hide()
        }

        with .nextPage = Viewer.createPageStep(.actions, 1)
        {
            .hide()
            .sigPressed += func|view = me|(_) { view.turnPage(1) }
        }

        .timeline.sendToBack()
        .playButton.sendToBack()
        .nextPage.sendToBack()
        .frameLabel.sendToBack()
        .previousPage.sendToBack()
    }

    // Changes the existing image-set page or animation frame without wrapping at its ends.
    mtd turnPage(direction: s32)
    {
        let movie = &.imageView.movie
        if movie.frameCount > 1 do
            .imageView.setFrameIndex(Math.clamp(movie.frameIndex + direction, 0, movie.frameCount - 1))
    }

    // Creates the zoom menu button in the information group.
    mtd createZoomControl()
    {
        .zoomLabel = Viewer.createZoomButton(.info, "scope.image.zoom", texts().ui_ZoomMenu, InfoWidth - 2 * Viewer.ZoomButtonInset)
        .zoomLabel.sigPressed += func|view = me|(_) { view.showZoomMenu() }
    }

    // Returns the reading of the content under `local`, a point of the picture view: the pixel
    // and, for a bitmap, its color and opacity; or an empty string beside the picture.
    mtd probeText(local: Math.Point)->String
    {
        var result: String
        let pixel = .imageView.pixelAt(local)
        if not pixel.inside do
            return result

        result    = Format.toString(texts().ui_ProbePixel, pixel.x, pixel.y)
        .probed   = {cast(f32, pixel.x), cast(f32, pixel.y)}
        .hasProbe = true
        let picture = .imageView.picture()
        if picture
        {
            let color = picture.pixelColor(pixel.x, pixel.y)
            result += Format.toString(" · #%{X02}%{X02}%{X02}", color.r, color.g, color.b)
            if color.a != 255 do
                result += Format.toString(" · %", Format.toString(texts().ui_ProbeAlpha, shareText(color.a, 255)))
        }

        return result
    }

    // Shows the reading of the point under the pointer after the summary, or the summary alone.
    mtd showProbe(local: Math.Point)
    {
        let probe = .probeText(local)
        let shown = .shownDetails()
        .reportDetails(probe.isEmpty() ? shown : Format.toString("% · %", shown, probe))
    }

    // Creates the picture view and keeps the zoom readout and the frame transport in step with it.
    // The pointer over the picture reads the pixel it stands on into the summary.
    mtd createImageView()
    {
        with .imageView = ImageView.create(me)
        {
            .hookOnEvent = func|view = me|(imageView, evt)->bool
            {
                if evt is MouseEvent as mouse
                {
                    if mouse.kind == .Move do
                        view.showProbe(imageView.surfaceToLocal(mouse.surfacePos))
                    elif mouse.kind == .Leave do
                        view.reportDetails(view.shownDetails())
                }

                return false
            }

            .dockStyle = .Center
            .setAllPaddings(.themeMetrics().floating_Inset)     // A fitted picture keeps the air of the window around it.
            .sigZoomChanged += func|view = me|(_)
            {
                view.refreshZoom()
            }

            .sigFrameChanged += func|view = me|(_)
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
    registerMediaInfoStrings(&host.application().resources)
    let view = Panel.create(host)
    host.attachView(view)
    host.setInformation(func|view|(sheet) { view.describeInformation(sheet) })
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })

    host.setLifecycle(Viewer.loadLifecycle(view))
}
