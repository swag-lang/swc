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

// Image zoom is a compact reading beside the full picture transform in the action bar. Its
// narrower side insets leave more of the information band to the file details at small widths.
private const InfoWidth              = Viewer.ZoomButtonWidth + 2 * 6.0
private const SvgRasterLimit         = 2048.0
private const ImageItemSelectorWidth = 272.0
private const ImageItemSelectorLimit = 128
private const ImageThumbnailWidth    = 32
private const ImageThumbnailHeight   = 24

private func commandWidth(metrics: const *ThemeMetrics)->f32 => 2 * themeActionButtonSize(metrics) + 2 * themeDropDownButtonWidth(metrics) + 16
private func imageSetCommandWidth(metrics: const *ThemeMetrics, animated: bool)->f32 =>
    Viewer.pageControlWidth(metrics) + 2 * themeDropDownButtonWidth(metrics) + 16 +
    (animated ? 128 + 12 : ImageItemSelectorWidth + 12) +
    (animated ? themeActionButtonSize(metrics) + 10 : 0)

private func imageItemDescription(info: const *ImageFrameInfo, index, count: s32)->String
{
    var result = Viewer.pageText(cast(u64, index), cast(u64, count))
    result += Format.toString(" · % × %", info.width, info.height)
    switch info.kind
    {
    case .Page:
        result += Format.toString(" · %", texts().ui_ItemPage)

    case .Variant:
        result += Format.toString(" · %", texts().ui_ItemVariant)

    case .Layer:
        result += Format.toString(" · %", Format.toString(texts().ui_ItemLayer, info.layer))

    case .Texture:
        result += Format.toString(" · %", Format.toString(texts().ui_ItemLevel, info.level))
        if info.layer do
            result += Format.toString(" · %", Format.toString(texts().ui_ItemLayer, info.layer))
        if info.face do
            result += Format.toString(" · %", Format.toString(texts().ui_ItemFace, info.face))

    default:
        break
    }

    // Decoder-owned names can be as large as the source file. Only copy short names into the
    // bounded selector; dimensions and item position remain available for every entry.
    if not info.name.isEmpty() and info.name.count <= 64 do
        result += Format.toString(" · %", info.name)
    return result
}

// What the worker decodes for the picture viewer, handed to the view in one move.
struct ViewerContent
{
    image:       Image
    movie:       Movie
    drawing:     Svg.Drawing     // Vector document, for a format that has no pixels of its own.
    facts:       ViewerFacts
    information: MediaInfoData
}

// Decodes only one indexed image on a worker and bounds the largest temporary pixel buffer.
private func loadItemThumbnail(fileName: string, index: u32)->Image fail
{
    if Swag.isCancelled() do
        return Image{}
    var reader = try ImageReader.load(fileName, {maxPixels: 4 * 1024 * 1024,
                                                 maxDecodedBytes: 16 * 1024 * 1024,
                                                 maxInputBytes: 128 * 1024 * 1024})
    if Swag.isCancelled() do
        return Image{}
    var result = try reader.read(index)
    result.orient(Exif.orientationOf(result.metadata.toSlice()))
    if result.width > ImageThumbnailWidth or result.height > ImageThumbnailHeight do
        result.fitInside(ImageThumbnailWidth, ImageThumbnailHeight, .Bilinear)
    return result
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
    if Path.lowercaseExtension(fileName) != ".svg"
    {
        var image   = try loadViewerImage(fileName)
        let largest = Math.max(image.width, image.height)
        let side    = Math.max(maxSide, 1'u32)
        if largest > side
        {
            let scale = cast(f32, side) / cast(f32, largest)
            image.resize(Math.max(1, cast(s32, Math.round(cast(f32, image.width) * scale))),
                         Math.max(1, cast(s32, Math.round(cast(f32, image.height) * scale))),
                         .CatmullRom)
        }

        return image
    }

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

// Loads an image for the viewer and fills the facts shown beside it.
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
        let jpeg = Jpg.matchesFileName(fileName)
        var originalMetadata: Array'ImageMetadata

        // JPEG has one still frame. Decode straight into the picture the view will own.
        if jpeg
        {
            result.image = try Image.load(fileName)
            let orientation = Exif.orientationOf(result.image.metadata.toSlice())
            if orientation != 1
            {
                // The information sheet shows the encoded orientation, even after the pixels
                // are upright and their own orientation tag has been reset.
                originalMetadata = result.image.metadata
                result.image.orient(orientation)
            }
        }
        else
        {
            try result.movie.load(fileName)
            try result.movie.prepareCache()
            if result.movie.frameCount == 1
            {
                result.image = result.movie.frame
                result.image.orient(Exif.orientationOf(result.image.metadata.toSlice()))
            }
        }

        let frameCount = Math.max(1, result.movie.frameCount)
        let animated   = frameCount > 1
        let shown      = animated ? &result.movie.frame : &result.image
        result.facts.width  = Format.toString("%", shown.width)
        result.facts.height = Format.toString("%", shown.height)
        result.facts.bits   = shown.bitsPerPixel
        result.facts.frames = frameCount

        // Adding information can move what 'result' holds: read the frame first.
        let dimensions  = Format.toString("% × % px", shown.width, shown.height)
        let pixelFormat = Reflection.enumName(PixelFormat, &shown.pixelFormat, fullyQualified: false)
        let depth       = Format.toString("%", shown.bitsPerPixel)
        var transparency: String
        if not animated and shown.pixelFormat.hasAlpha() do
            transparency = transparencyText(shown)
        result.information.add(.Dimensions, dimensions)
        result.information.add(.PixelFormat, pixelFormat)
        result.information.add(.Depth, depth)
        if animated do
            result.information.add(.Frames, Format.toString("%", frameCount))
        if transparency.count do
            result.information.add(.Transparency, transparency)

        var metadata = result.movie.frame.metadata.toSlice()
        if jpeg do
            metadata = originalMetadata.isEmpty() ? result.image.metadata.toSlice() : originalMetadata.toSlice()
        result.information.addImageMetadata(metadata, extension == ".png" or extension == ".apng")
        if result.movie.frameCount == 1 do
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

    frameSteps: Viewer.PageSteps

    late
    {
        actions:         *Wnd
        info:            *Wnd
        previousButton:  *IconButton
        nextButton:      *IconButton
        imageView:       *ImageView
        zoomLabel:       *IconButton
        optionsButton:   *IconButton
        transformButton: *IconButton
        playModeButton:  *Viewer.PlaybackButton
        playButton:      *IconButton
        timeline:        *Slider
        itemSelector:    *ComboBox
        frameLabel:      *IconButton
    }

    services:                   Viewer.HostServices
    information:                MediaInfoData
    lastCompletedLoops:         u32      // Playback cycles observed by the latest frame refresh.
    handedOff:                  bool     // The host was told the animation has run its cycle, and answered that it moves on.
    load:                       Viewer.BackgroundLoad'ViewerContent
    failureReason:              String
    shownItem:                  String              // What the summary last said of the item in view.
    selectorStart:              s32                 // First movie index represented by the bounded item selector.
    thumbnailPixels:            Image               // Fixed 128-cell RGBA8 atlas (384 KiB CPU and GPU).
    thumbnailList:              ImageList           // GPU atlas borrowed by selector and popup icons.
    thumbnailReady:             Array'bool          // Decoded cells in the current selector window.
    thumbnailFailed:            Array'bool          // Failed cells are not retried until the window changes.
    thumbnailRequested:         Array'bool          // Requested cells in this window, for bounded scheduling and verification.
    thumbnailPopup:             *PopupListCtrl?     // Borrowed popup while its selector is open.
    thumbnailGeneration:        u32                 // Invalidates work from an old selector window or file.
    thumbnailRequestLocalIndex: u32                 // Selector position receiving the in-flight result.
    thumbnailRequestGeneration: u32                 // Window generation captured when work was submitted.
    thumbnailTask:              Swag.Task'Image     // At most one visible-first decode at a time.
    probed:                     Math.Point          // Pixel of the stored picture the pointer last read.
    hasProbe:                   bool                // Whether the pointer has read a pixel of the picture shown.
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

        result = Format.toString("% × % px", info.width, info.height)
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

    // Independent pages report the dimensions of the displayed image. An animated frame can add its delay.
    mtd shownDetails()->String
    {
        let item = .itemText()
        if item.isEmpty() do
            return String.from(.details)
        return .imageView.movie.isAnimated() ? Format.toString("% · %", .details, item) : item
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
            .services.showDetails(me, .shownDetails())
        }

        if movie.isAnimated() do
            .timeline.setValueWithoutGesture(cast(f32, movie.frameIndex))
        .frameSteps.unit = movie.isAnimated() ? .Frame : .Page
        .frameSteps.setPageRange(cast(u64, movie.frameIndex), cast(u64, movie.frameCount))
        .refreshItemSelector()
        .frameSteps.previousButton.enable(movie.frameIndex > 0)
        .frameSteps.nextButton.enable(movie.frameIndex + 1 < movie.frameCount)
        .playButton.setIcon(.theme().icon(movie.isPaused ? .Play : .Pause, themeActionIconSize(.themeMetrics())))

        // The movie records elapsed cycles independently of frame seeks and encoded loop limits.
        let completed = movie.completedLoopCount()
        let finished  = completed != 0 and .lastCompletedLoops == 0
        .lastCompletedLoops = completed
        if finished do
            .finishCycle()
    }

    // Fills a bounded window of metadata-only choices around the current independent image.
    mtd populateItemSelector(start: s32)
    {
        let movie = &.imageView.movie
        if movie.isAnimated() or movie.frameCount <= 1 do
            return

        let lastStart = Math.max(movie.frameCount - ImageItemSelectorLimit, 0)
        .selectorStart = Math.clamp(start, 0, lastStart)
        if .thumbnailPopup do
            .itemSelector.closePopup()
        .resetThumbnailWindow()
        let end = Math.min(.selectorStart + ImageItemSelectorLimit, movie.frameCount)
        .itemSelector.clear()
        for index in range(.selectorStart, end)
        {
            let info  = movie.frameInfo(index)
            let label = info ? imageItemDescription(info, index, movie.frameCount) : Viewer.pageText(cast(u64, index), cast(u64, movie.frameCount))
            .itemSelector.addItem(label)
        }

        .refreshItemSelector()
    }

    // Synchronizes the selected description with the shown image, recentering only when it leaves
    // the fixed-size window used for very large image sets.
    mtd refreshItemSelector()
    {
        let movie = &.imageView.movie
        if movie.isAnimated() or movie.frameCount <= 1 do
            return
        let end = .selectorStart + cast(s32, .itemSelector.items.count)
        if movie.frameIndex < .selectorStart or movie.frameIndex >= end
        {
            .populateItemSelector(.itemSelectorStart(movie.frameIndex, movie.frameCount))
            return
        }

        .itemSelector.setSelectedIndex(cast(u32, movie.frameIndex - .selectorStart), notify: false)
    }

    mtd itemSelectorStart(frameIndex, frameCount: s32)->s32
    {
        let lastStart = Math.max(frameCount - ImageItemSelectorLimit, 0)
        return Math.clamp(frameIndex - ImageItemSelectorLimit / 2, 0, lastStart)
    }

    mtd resetThumbnailWindow()
    {
        .thumbnailGeneration += 1
        if .thumbnailTask.isPending() do
            .thumbnailTask.cancel()
        .thumbnailReady.resize(ImageItemSelectorLimit)
        .thumbnailFailed.resize(ImageItemSelectorLimit)
        .thumbnailRequested.resize(ImageItemSelectorLimit)
        for index in ImageItemSelectorLimit
        {
            .thumbnailReady[index]     = false
            .thumbnailFailed[index]    = false
            .thumbnailRequested[index] = false
        }

        if .thumbnailPixels.isValid()
        {
            .thumbnailPixels.fill(Color{r: 0, g: 0, b: 0, a: 0})
            discard .app().renderer.updateTexture(.thumbnailList.texture, cast(const *u8, .thumbnailPixels.pixels.storage()))
        }
    }

    mtd ensureThumbnailAtlas()
    {
        if .thumbnailList.isValid() do
            return
        .thumbnailPixels = Image.create(ImageThumbnailWidth * 8, ImageThumbnailHeight * 16, .RGBA8)
        .thumbnailPixels.fill(Color{r: 0, g: 0, b: 0, a: 0})
        let texture = .app().renderer.addImage(&.thumbnailPixels)
        .thumbnailList = ImageList.create(texture, ImageThumbnailWidth, ImageThumbnailHeight, ImageItemSelectorLimit)
    }

    mtd updateVisibleThumbnails(popup: *PopupListCtrl)
    {
        if .imageView.movie.isAnimated() or .imageView.movie.frameCount <= 1 do
            return
        .ensureThumbnailAtlas()
        let visible = popup.visibleItemRange()
        if visible.end > .itemSelector.items.count do
            return
        for localIndex in visible.first until visible.end
        {
            if .thumbnailReady[localIndex]
            {
                let icon = Icon.from(&.thumbnailList, cast(s32, localIndex), ImageThumbnailWidth, ImageThumbnailHeight)
                popup.setItemIcon(localIndex, icon)
            }
        }

        .scheduleVisibleThumbnail(visible.first, visible.end)
    }

    mtd scheduleVisibleThumbnail(first, end: u32)
    {
        if .thumbnailTask.isPending() or first >= end do
            return
        let selected = .itemSelector.selectedIndex
        if selected >= first and
           selected < end and
           not .thumbnailReady[selected] and
           not .thumbnailFailed[selected]
        {
            .submitThumbnail(selected)
            return
        }

        for localIndex in first until end
        {
            if not .thumbnailReady[localIndex] and not .thumbnailFailed[localIndex]
            {
                .submitThumbnail(localIndex)
                return
            }
        }
    }

    mtd submitThumbnail(localIndex: u32)
    {
        let movieIndex = cast(u32, .selectorStart) + localIndex
        .thumbnailRequestLocalIndex     = localIndex
        .thumbnailRequestGeneration     = .thumbnailGeneration
        .thumbnailRequested[localIndex] = true
        .thumbnailTask.submit(func|view = me, movieIndex|()->Image fail => try loadItemThumbnail(view.load.fileName.toString(), movieIndex),
                              me.taskNotifier(&.thumbnailTask),
                              .Background)
    }

    mtd installThumbnail(image: *Image, localIndex: u32)->bool
    {
        if not image.isValid() or localIndex >= ImageItemSelectorLimit do
            return false
        let cellX   = cast(s32, localIndex % 8) * ImageThumbnailWidth
        let cellY   = cast(s32, localIndex / 8) * ImageThumbnailHeight
        let offsetX = Math.max((ImageThumbnailWidth - image.width) / 2, 0)
        let offsetY = Math.max((ImageThumbnailHeight - image.height) / 2, 0)
        for y in 0 until image.height
        {
            for x in 0 until image.width
            {
                let color = image.pixelColor(x, y)
                let dstY  = .thumbnailPixels.height - (cellY + offsetY + y) - 1
                let dst   = cast([*] u8, .thumbnailPixels.pixels.storage()) + cast(u64, dstY * .thumbnailPixels.rowStride + (cellX + offsetX + x) * 4)
                dst[0] = color.r
                dst[1] = color.g
                dst[2] = color.b
                dst[3] = color.a
            }
        }

        return .app().renderer.updateTexture(.thumbnailList.texture, cast(const *u8, .thumbnailPixels.pixels.storage()))
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
        let animated = .imageView.movie.isAnimated()
        let width    = imageSetCommandWidth(.themeMetrics(), animated)
        .actions.preferredSize.x = width
        .actions.resize(width, themeActionButtonSize(.themeMetrics()))
        .fitCommandBar()
        if animated
        {
            .timeline.setBounds(0, cast(f32, .imageView.movie.frameCount) - 1, 1)
        }
        else
        {
            .populateItemSelector(0)
        }

        .refreshFrame()
        .services.chromeChanged(me)
    }

    // Spend the available width on the operation that belongs to the picture: file, page or frame.
    mtd fitCommandBar()
    {
        let width = .actions.position.width
        let movie = &.imageView.movie
        let paged = movie.frameCount > 1
        let animated = paged and movie.isAnimated()
        let metrics = .themeMetrics()
        let action = themeActionButtonSize(metrics)
        let compact = width < (paged ? imageSetCommandWidth(metrics, animated) : commandWidth(metrics))
        let room = width - (compact ? .optionsButton.position.width : 0)
        let stepWidth = animated ? Viewer.pageControlWidth(metrics) + 3 * action : 2 * action
        let steps = room >= stepWidth
        let counter = paged and steps and room >= Viewer.pageControlWidth(metrics)
        .optionsButton.show(compact)
        .transformButton.show(not compact)
        .playModeButton.show(not compact)
        .previousButton.show(not paged and steps)
        .nextButton.show(not paged and steps)
        .frameSteps.previousButton.show(paged and steps)
        .frameSteps.nextButton.show(paged and steps)
        .frameLabel.show(counter)
        .playButton.margin.x = compact ? 0 : 10
        .playButton.show(animated and room >= action)
        let free = room - (steps ? 2 * action : 0) - (counter ? Viewer.PageReadoutWidth : 0) -
                   (animated ? action + .playButton.margin.x : 0) - 12
        .timeline.resize(compact ? Math.clamp(free, 0, 128) : 128, .timeline.position.height, computeLayout: false)
        .timeline.show(animated and (not compact or free >= action))
        .itemSelector.resize(compact ? Math.clamp(free, 0, ImageItemSelectorWidth) : ImageItemSelectorWidth,
                             .itemSelector.position.height, computeLayout: false)
        let selectItem = paged and not animated and (not compact or free >= 3 * action)
        if .thumbnailPopup and not selectItem do
            .itemSelector.closePopup()
        .itemSelector.show(selectItem)
    }

    mtd showCompactOptions()
    {
        let sheet = OptionSheet.View.create(.optionsButton, func|view = me|(page)
        {
            let strings = texts()
            let movie = &view.imageView.movie
            if movie.frameCount > 1
            {
                let index = movie.frameIndex
                if movie.isAnimated() and not view.playButton.isLocallyVisible() do
                    page.addAction(movie.isPaused ? appStrings().cmd_Play : appStrings().cmd_Pause,
                                   func|view|() { view.toggleAnimation() },
                                   icon: view.theme().icon(movie.isPaused ? .Play : .Pause, themeRowIconSize(view.themeMetrics())))
                page.addStepper(movie.isAnimated() ? strings.ui_Frame : strings.ui_Image,
                                Viewer.pageText(cast(u64, index), cast(u64, movie.frameCount)),
                                func|view|(step) { view.turnPage(step) }, index > 0, index + 1 < movie.frameCount)
            }
            if not view.previousButton.isLocallyVisible() and movie.frameCount <= 1
            {
                page.addAction(strings.ui_TipPrevious, func|view|() { view.navigate(-1) }, disabled: not view.previousButton.isEnabled(), closesSheet: true)
                page.addAction(strings.ui_TipNext, func|view|() { view.navigate(1) }, disabled: not view.nextButton.isEnabled(), closesSheet: true)
            }
            page.addAction(strings.ui_TipTransform, func|view|() { view.showTransformMenu() }, closesSheet: true,
                           icon: view.theme().icon(.Redo, themeRowIconSize(view.themeMetrics())))
            view.services.playback.addOptionRows(page, view, showSlideDuration: true)
        }, owner: me)
        sheet.doModal(.optionsButton, autoDestroy: true)
    }

    mtd navigate(delta: s32) => .services.navigate(me, delta)

    mtd toggleAnimation()
    {
        .imageView.setPaused(not .imageView.movie.isPaused)
        .refreshFrame()
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
        let texts = texts()
        let menu  = MenuCtrl.createPopup(me, owner: me)
        menu.addItem(texts.ui_RotateCounterClockwise,
                     "scope.image.rotateLeft",
                     .theme().icon(.Undo, themeRowIconSize(.themeMetrics())),
                     rightName: .keyShortcutName("scope.image.rotateCounterClockwise", "Shift R"))
        menu.addItem(texts.ui_RotateClockwise,
                     "scope.image.rotateRight",
                     .theme().icon(.Redo, themeRowIconSize(.themeMetrics())),
                     rightName: .keyShortcutName("scope.image.rotateClockwise", "R"))
        menu.addSeparator()
        menu.addItem(texts.ui_MirrorHorizontal,
                     "scope.image.mirrorHorizontal",
                     .theme().icon(.MirrorHorizontal, themeRowIconSize(.themeMetrics())),
                     rightName: .keyShortcutName("scope.image.mirrorHorizontal", "H"))
        menu.addItem(texts.ui_MirrorVertical,
                     "scope.image.mirrorVertical",
                     .theme().icon(.MirrorVertical, themeRowIconSize(.themeMetrics())),
                     rightName: .keyShortcutName("scope.image.mirrorVertical", "V"))
        menu.addSeparator()
        menu.addItem(texts.ui_ResetTransform,
                     "scope.image.reset",
                     .theme().icon(.Update, themeRowIconSize(.themeMetrics())),
                     rightName: .keyShortcutName("scope.image.resetTransform", "Ctrl R"))
        if .imageView.picture()
        {
            menu.addSeparator()
            menu.addItem(texts.ui_CopyImage,
                         "scope.image.copy",
                         .theme().icon(.Copy, themeRowIconSize(.themeMetrics())),
                         rightName: .keyShortcutName("scope.image.copyImage", "Ctrl C"))
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
        entries.add(texts.ui_TipPrevious, .ChevronLeft, func|view = me|() { view.navigate(-1) }, defaultKey: {modifiers: .None, key: .Left}, bindId: "scope.image.tipPrevious")
        entries.add(texts.ui_TipNext, .ChevronRight, func|view = me|() { view.navigate(1) }, defaultKey: {modifiers: .None, key: .Right}, bindId: "scope.image.tipNext")
        entries.add(texts.ui_RotateCounterClockwise, .Undo, func|view = me|() { view.rotateCounterClockwise() }, defaultKey: {modifiers: .Shift, key: .R}, bindId: "scope.image.rotateCounterClockwise")
        entries.add(texts.ui_RotateClockwise, .Redo, func|view = me|() { view.rotateClockwise() }, defaultKey: {modifiers: .None, key: .R}, bindId: "scope.image.rotateClockwise")
        entries.add(texts.ui_MirrorHorizontal, .MirrorHorizontal, func|view = me|() { view.mirrorHorizontally() }, defaultKey: {modifiers: .None, key: .H}, bindId: "scope.image.mirrorHorizontal")
        entries.add(texts.ui_MirrorVertical, .MirrorVertical, func|view = me|() { view.mirrorVertically() }, defaultKey: {modifiers: .None, key: .V}, bindId: "scope.image.mirrorVertical")
        entries.add(texts.ui_ResetTransform, .Update, func|view = me|() { view.resetTransform() }, defaultKey: {modifiers: .Control, key: .R}, bindId: "scope.image.resetTransform")
        if .imageView.picture() do
            entries.add(texts.ui_CopyImage, .Copy, func|view = me|() { view.copyPicture() }, defaultKey: {modifiers: .Control, key: .C}, bindId: "scope.image.copyImage")

        // The pixel the pointer read last, whose color the reader may want elsewhere.
        let color = .probedColorText()
        if color.count do
            entries.add(Format.toString(texts.ui_CopyColor, color, Format.toString(texts.ui_ProbePixel, cast(s32, .probed.x), cast(s32, .probed.y))), .Copy, func|view = me|() { view.copyProbedColor() }, defaultKey: {modifiers: Input.KeyModifiers.Control | .Shift, key: .C}, bindId: "scope.image.copyColor")

        // The picture zooms by factors, far past the shared bounds, so only actual size, the 100 %
        // of the readout, is the shared row; it reads as chosen while the picture shows at it.
        // The steps read as unavailable at the picture view's own limits.
        entries.add(texts.ui_TipFit, .FitView, func|view = me|() { view.imageView.zoomToFit() }, checked: .imageView.isFitted, defaultKey: {modifiers: .None, key: .F}, bindId: "scope.image.tipFit")
        entries.add(lens.cmd_ZoomIn, .ZoomIn, func|view = me|() { view.imageView.zoomIn() }, disabled: not .imageView.canZoomIn(), defaultKey: {modifiers: .Control, key: .OemPlus}, bindId: "scope.image.zoomIn")
        entries.add(lens.cmd_ZoomOut, .ZoomOut, func|view = me|() { view.imageView.zoomOut() }, disabled: not .imageView.canZoomOut(), defaultKey: {modifiers: .Control, key: .OemMinus}, bindId: "scope.image.zoomOut")
        entries.addZoom(.Reset, .zoomPercent(), func|view = me|() { view.imageView.actualSize() })
        if .imageView.movie.frameCount > 1
        {
            // An animation steps by frames, an image set by pages.
            let info      = .imageView.movie.frameInfo()
            let animation = info and info.kind == .Animation
            .frameSteps.addPageJump(entries, "scope.image.goToPage")
            entries.add(animation ? lens.cmd_PreviousFrame : lens.ui_PreviousPage, .ChevronLeft, func|view = me|() { view.turnPage(-1) }, disabled: not .frameSteps.previousButton.isEnabled(), defaultKey: {modifiers: .Control, key: .PageUp}, bindId: "scope.image.previousPage")
            entries.add(animation ? lens.cmd_NextFrame : lens.ui_NextPage, .ChevronRight, func|view = me|() { view.turnPage(1) }, disabled: not .frameSteps.nextButton.isEnabled(), defaultKey: {modifiers: .Control, key: .PageDown}, bindId: "scope.image.nextPage")
        }

        entries.add(lens.cmd_ZoomMenu, .ZoomLevels, func|view = me|() { view.showZoomMenu() }, bindId: "scope.image.zoomMenu")
        if .imageView.movie.isAnimated()
        {
            entries.add(.imageView.movie.isPaused ? lens.cmd_Play : lens.cmd_Pause,
                        .imageView.movie.isPaused ? .Play : .Pause,
                        func|view = me|() { view.toggleAnimation() },
                        defaultKey: {modifiers: .None, key: .Space},
                        bindId: "scope.image.playPause")
        }

        entries.add(lens.cmd_PlayMode, .RepeatAll, func|view = me|()
        {
            view.playModeButton.showOptions(view.optionsButton.isLocallyVisible() ? view.optionsButton : null)
        }, bindId: "scope.image.playMode")
    }

    mtd showTransformMenu()
    {
        let menu = .createTransformMenu()
        let anchor = .optionsButton.isLocallyVisible() ? .optionsButton : .transformButton
        switch menu.doModal(anchor, autoDestroy: true) orelse ""
        {
        case "scope.image.rotateLeft":       .rotateCounterClockwise()
        case "scope.image.rotateRight":      .rotateClockwise()
        case "scope.image.mirrorHorizontal": .mirrorHorizontally()
        case "scope.image.mirrorVertical":   .mirrorVertically()
        case "scope.image.reset":            .resetTransform()
        case "scope.image.copy":             .copyPicture()
        }
    }

    // Offers the zoom presets and the fit, with the level in use and the fit checked, as the lens
    // checks them. A picture can be far larger than the window, so the levels reach down to 25 %
    // rather than staying around 100 % as a document's do.
    mtd showZoomMenu()
    {
        let menu    = MenuCtrl.createPopup(me, owner: me)
        let percent = .zoomPercent()
        menu.addItem("25 %", "scope.image.zoom25", checked: percent == 25)
        menu.addItem("50 %", "scope.image.zoom50", checked: percent == 50)
        menu.addItem("100 %", "scope.image.zoom100", checked: percent == 100)
        menu.addItem("200 %", "scope.image.zoom200", checked: percent == 200)
        menu.addSeparator()
        menu.addItem(texts().ui_TipFit,
                     "scope.image.zoomFit",
                     .theme().icon(.FitView, themeRowIconSize(.themeMetrics())),
                     rightName: .keyShortcutName("scope.image.tipFit", "F"),
                     checked: .imageView.isFitted)
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
            .frameSteps.previousButton.toolTip    = appStrings().ui_PreviousPage
            .frameSteps.nextButton.toolTip        = appStrings().ui_NextPage
            .transformButton.toolTip = texts().ui_TipTransform
            .playButton.toolTip      = texts().ui_TipPlay
            .optionsButton.toolTip   = appStrings().ui_Options
            .zoomLabel.toolTip       = texts().ui_ZoomMenu
            .refreshZoom()
            if not .facts.width.isEmpty()
            {
                .details = .facts.text()
                .services.showDetails(me, .shownDetails())
            }
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if evt.task == &.thumbnailTask
        {
            .thumbnailTask.waitSubmission(evt.submission)
            if evt.submission != .thumbnailTask.currentSubmission() or not .thumbnailTask.isDone() do
                return
            var thumbnailErrorOutcome: Swag.Error
            var thumbnail: Image
            catch { thumbnail = try .thumbnailTask.take() } as thumbnailErrorOutcome
            let thumbnailError = thumbnailErrorOutcome.value()
            let localIndex     = .thumbnailRequestLocalIndex
            if .thumbnailRequestGeneration == .thumbnailGeneration and localIndex < .thumbnailReady.count
            {
                if thumbnailError == null and .installThumbnail(&thumbnail, localIndex) do
                    .thumbnailReady[localIndex] = true
                else do
                    .thumbnailFailed[localIndex] = true
            }

            if .thumbnailPopup do
                .updateVisibleThumbnails(.thumbnailPopup)
            return
        }

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
        .services.showDetails(me, .shownDetails())
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

        case .D0 where evt.modifiers == .Control:
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
        .itemSelector.closePopup()
        if .thumbnailTask.isPending()
        {
            .thumbnailTask.cancel()
            if not .thumbnailTask.isDone() do
                return false
        }

        if .thumbnailTask.isDone() do
            discard catch .thumbnailTask.take()
        if .thumbnailList.isValid() do
            .thumbnailList.release(.app().renderer)
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
            if evt is ResizeEvent do
                view.fitCommandBar()
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
        with .optionsButton = Viewer.createOptionsButton(.actions)
        {
            .dockStyle = .Right
            .hide()
            .sigPressed += func|view = me|(_) { view.showCompactOptions() }
        }
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
            .sigPressed += func|view = me|(_) { view.toggleAnimation() }
        }

        with .timeline = Slider.create(.actions, {0, 0, 128, 36})
        {
            .dockStyle = .Left
            .margin    = {6, 1, 6, 1}
            .hide()
            .sigChanged += func|view = me|(slider) { view.imageView.setFrameIndex(cast(s32, Math.round(slider.value()))) }
        }

        with .itemSelector = ComboBox.create(.actions, {0, 0, ImageItemSelectorWidth, 36})
        {
            .dockStyle          = .Left
            .margin             = {6, 1, 6, 1}
            .maximumPopupHeight = 360
            .minimumPopupWidth  = ImageItemSelectorWidth
            .popupItemHeight    = 36
            .popupIconSize      = ImageThumbnailWidth
            .toolTip            = texts().ui_ItemSelector
            .hide()
            .sigPopupChanged += func|view = me|(_, popup, opened)
            {
                if opened
                {
                    view.thumbnailPopup = popup
                    popup.scrollWnd.sigScrollPositionChanged += func|view = view, popup = popup|(_, _, _)
                    {
                        if view.thumbnailPopup == popup do
                            view.updateVisibleThumbnails(popup)
                    }

                    view.updateVisibleThumbnails(popup)
                }
                else
                {
                    view.thumbnailPopup      = null
                    view.thumbnailGeneration += 1
                    if view.thumbnailTask.isPending() do
                        view.thumbnailTask.cancel()
                }
            }

            .sigChanged += func|view = me|(_, index)
            {
                view.imageView.setFrameIndex(view.selectorStart + cast(s32, index))
                view.refreshFrame()
            }
        }

        .frameLabel = .frameSteps.create(.actions, "scope.image.page", .Page,
            func|view = me|(dir) { view.turnPage(dir) }, func|view = me|(index) { view.imageView.setFrameIndex(cast(s32, index)) })
        discard .frameSteps.showSteps(false)

        .timeline.sendToBack()
        .itemSelector.sendToBack()
        .playButton.sendToBack()
        .frameSteps.nextButton.sendToBack()
        .frameLabel.sendToBack()
        .frameSteps.previousButton.sendToBack()
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
        .zoomLabel            = Viewer.createZoomButton(.info, "scope.image.zoom", texts().ui_ZoomMenu)
        .zoomLabel.margin     = {6, 0, 6, 0}
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
    //
    // The pointer sends many moves over one pixel, or beside the picture. The host sets a summary
    // it already shows aside, so each move reports what it reads.
    mtd showProbe(local: Math.Point)
    {
        let probe = .probeText(local)
        let shown = .shownDetails()
        .services.showDetails(me, probe.isEmpty() ? shown : Format.toString("% · %", shown, probe))
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
                        view.services.showDetails(view, view.shownDetails())
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
