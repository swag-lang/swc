#global public

using Core, Pixel

// Displays a still image or animated GIF with viewer-oriented zooming and panning.
//
// The view owns its image data and renderer texture. Mouse-wheel zoom is centred on the pointer,
// dragging pans the content, and a double click toggles between fitted and actual size.
struct ImageView
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        sigZoomChanged:  SigArray'func||(*ImageView)     // Emitted after the effective zoom changes.
        sigFrameChanged: SigArray'func||(*ImageView)     // Emitted after an animation frame changes.

        readonly
        {
            zoom:      f32  = 1        // Requested scale outside fitted mode.
            isFitted:  bool = true     // Whether the image is scaled to the available viewport.
            panOffset: Math.Point      // Image-centre offset from the viewport centre, in logical units.
            movie:     Movie           // GIF playback state, or an empty movie for a still image.
        }
    }

    image:           Image          // Still image owned by the view.
    uploadedTexture: Texture        // Renderer texture for the current still or movie frame.
    isPanning:       bool           // Whether the left mouse button currently pans the image.
    lastPointer:     Math.Point     // Previous surface position of a pan gesture.
}

private impl ImageView
{
    mtd const currentImage()->const *Image
    {
        if .movie.isValid() do
            return &.movie.frame
        return &.image
    }

    mtd const contentRect()->Math.Rectangle
    {
        let source = .currentImage()
        if !source.isValid() do
            return {}

        let client = .paddedClientRect()
        let scale  = .effectiveZoom()

        var result: retval
        result.width  = source.width * scale
        result.height = source.height * scale
        result.x      = client.horzCenter() - result.width * 0.5 + .panOffset.x
        result.y      = client.vertCenter() - result.height * 0.5 + .panOffset.y
        return result
    }

    mtd updateUploadedFrame()
    {
        if !.uploadedTexture.isValid() do
            return
        .app().renderer.updateTexture(.uploadedTexture, nnPixels(.movie.frame.pixels.buffer))
    }

    mtd applyZoom(value: f32, anchor: #null const *Math.Point = null)
    {
        let oldZoom = .effectiveZoom()
        let oldRect = .contentRect()

        .isFitted = false
        .zoom     = Math.clamp(value, MinZoom, MaxZoom)

        if anchor and oldRect.width > 0 and oldRect.height > 0 and oldZoom > 0
        {
            let point  = anchor
            let ratioX = (point.x - oldRect.x) / oldRect.width
            let ratioY = (point.y - oldRect.y) / oldRect.height
            let next   = .contentRect()
            .panOffset.x += point.x - (next.x + next.width * ratioX)
            .panOffset.y += point.y - (next.y + next.height * ratioY)
        }

        .sigZoomChanged.call(me)
        .invalidate()
    }
}

impl IWnd for ImageView
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .clear()
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        if .isFitted do
            .sigZoomChanged.call(me)
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        painter.fillRect(.clientRect(), .themeColors().view_Bk)

        if .movie.isValid() and .movie.update(.app().timing.deltaSeconds)
        {
            .updateUploadedFrame()
            .sigFrameChanged.call(me)
        }

        let source = .currentImage()
        if !source.isValid() or !.uploadedTexture.isValid() do
            return

        let destination = .contentRect()
        if source.pixelFormat.hasAlpha() do
            painter.fillRect(destination, Brush.createHatch(.CheckBoardLarge, .themeColors().colorPicker_BackAlpha))
        painter.drawTexture(destination, .uploadedTexture, .themeColors().imageRect_Fg)

        if .movie.isValid() and .movie.frameCount > 1 and !.movie.isPaused do
            .invalidate()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        switch evt.kind
        {
        case .Wheel:
            if !.currentImage().isValid()
            {
                evt.accepted = false
                return
            }

            let factor = evt.delta.y > 0 ? 1.12'f32 : 1.0'f32 / 1.12
            let anchor = .surfaceToLocal(evt.surfacePos)
            .applyZoom(.effectiveZoom() * factor, &anchor)

        case .DoubleClick where evt.button == .Left:
            if .isFitted do
                .actualSize()
            else do
                .zoomToFit()

        case .Pressed where evt.button == .Left:
            if !.currentImage().isValid() do
                return
            .isPanning   = true
            .lastPointer = evt.surfacePos
            .captureMouse()

        case .Move:
            if !.isPanning
            {
                if .currentImage().isValid() do
                    .app().setFrameCursor(Cursor.from(.Hand))
                return
            }

            .panOffset   += evt.surfacePos - .lastPointer
            .lastPointer = evt.surfacePos
            .invalidate()

        case .Released where evt.button == .Left:
            if .isPanning
            {
                .isPanning = false
                .releaseMouse()
            }

        default:
            evt.accepted = false
        }
    }
}

impl ImageView
{
    const MinZoom = 0.02'f32     // Smallest supported scale.
    const MaxZoom = 64.0'f32     // Largest supported scale.

    // Creates an empty image viewer.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null)->*ImageView
    {
        Debug.assert(parent != null)
        let result = Wnd.create'ImageView(parent, null, position, id)
        result.focusPolicy = .Click
        return result
    }

    // Releases renderer-owned content and restores an empty fitted view.
    mtd clear()
    {
        if .uploadedTexture.isValid() do
            .app().renderer.removeTexture(&.uploadedTexture)
        .movie.clear()
        @drop(&.image, 1)
        @init(&.image, 1)
        .zoom      = 1
        .isFitted  = true
        .panOffset = {}
        .invalidate()
    }

    // Displays an owned copy of `image` and fits it to the viewport.
    mtd setImage(image: Image)
    {
        .clear()
        .image           = image
        .uploadedTexture = .app().renderer.addImage(.image)
        .zoomToFit()
    }

    // Updates a still image while reusing its renderer texture and viewing position.
    //
    // `image` is borrowed for the call and its pixels are copied. When its dimensions or pixel
    // format differ from the current still image, this behaves like [[Gui.ImageView.setImage]]
    // and fits the replacement to the viewport. An animated image is replaced by a still one.
    mtd updateImage(image: const *Image)
    {
        if !image.isValid()
        {
            .clear()
            return
        }

        if .movie.isValid() or !.image.isValid() or !.uploadedTexture.isValid() or image.width != .image.width or image.height != .image.height or image.pixelFormat != .image.pixelFormat
        {
            .setImage(image[])
            return
        }

        Memory.copy(.image.pixels.buffer!, image.pixels.buffer!, .image.byteCount)
        .app().renderer.updateTexture(.uploadedTexture, nnPixels(.image.pixels.buffer))
        .invalidate()
    }

    // Displays `image` by exchanging pixel storage with the view instead of copying it.
    //
    // A source that produces a new picture many times a second — a decoded video stream, a
    // camera, a live render — otherwise pays a full copy of every picture on the very thread
    // that has to present it, and at high resolutions that copy is the same order of magnitude
    // as the upload it feeds. Here the view takes the pixels of `image` and leaves its own in
    // their place, so the caller keeps a buffer of exactly the right shape to produce the next
    // picture into and nothing is copied.
    //
    // `image` must carry the geometry and pixel format the view is already showing. Anything
    // else behaves like [[Gui.ImageView.setImage]], which copies and refits.
    //
    // ```swag
    // try decoder.decodeFrameInto(&frame, index)
    // view.exchangeImage(&frame)     // `frame` now owns the picture that just left the screen
    // ```
    mtd exchangeImage(image: *Image)
    {
        if !image.isValid()
        {
            .clear()
            return
        }

        if .movie.isValid() or !.image.isValid() or !.uploadedTexture.isValid() or image.width != .image.width or image.height != .image.height or image.pixelFormat != .image.pixelFormat
        {
            .setImage(image[])
            return
        }

        swap(&.image, image)
        .app().renderer.updateTexture(.uploadedTexture, nnPixels(.image.pixels.buffer))
        .invalidate()
    }

    // Replaces the image with another rendering of the same content, keeping the view.
    //
    // A viewer whose content is scalable — a document page, a drawing — does not zoom by
    // magnifying pixels: it rasterizes again at the resolution it is now being shown at, so
    // the result stays as sharp as the display allows. What it must not do is lose the
    // reader's place while doing so. `scaleRatio` is how much larger the new image is than
    // the one it replaces, which is what lets the zoom follow the content instead of the
    // pixel count and leaves the visible region exactly where it was.
    //
    // ```swag
    // let sharper = renderPage(pageIndex, newScale)
    // view.replaceImage(sharper, newScale / oldScale)
    // ```
    mtd replaceImage(image: Image, scaleRatio: f32)
    {
        if scaleRatio <= 0 or !image.isValid()
        {
            .setImage(image)
            return
        }

        let fitted = .isFitted
        let scaled = .zoom / scaleRatio
        let offset = .panOffset

        .clear()
        .image           = image
        .uploadedTexture = .app().renderer.addImage(.image)
        .isFitted        = fitted
        .zoom            = Math.clamp(scaled, MinZoom, MaxZoom)
        .panOffset       = offset
        .sigZoomChanged.call(me)
        .invalidate()
    }

    // Loads an animated GIF and fits its first frame to the viewport.
    //
    // Existing content remains unchanged when decoding fails.
    mtd loadGif(fileName: string) fail
    {
        var movie: Movie
        try movie.load(fileName)

        .clear()
        .movie           = #move movie
        .uploadedTexture = .app().renderer.addImage(.movie.frame)
        .isFitted        = true
        .panOffset       = {}
        .sigZoomChanged.call(me)
        .invalidate()
    }

    // Returns the scale currently used to paint the image.
    mtd const effectiveZoom()->f32
    {
        let source = .currentImage()
        if !source.isValid() do
            return 1
        if !.isFitted do
            return .zoom

        let client = .paddedClientRect()
        if client.width <= 0 or client.height <= 0 do
            return 1
        return Math.min(client.width / source.width, client.height / source.height)
    }

    // Sets an explicit image scale and leaves fitted mode.
    mtd setZoom(value: f32)
    {
        .applyZoom(value)
    }

    // Increases the current image scale by one viewer step.
    mtd zoomIn()
    {
        .applyZoom(.effectiveZoom() * 1.25)
    }

    // Decreases the current image scale by one viewer step.
    mtd zoomOut()
    {
        .applyZoom(.effectiveZoom() / 1.25)
    }

    // Fits the complete image inside the viewport and recentres it.
    mtd zoomToFit()
    {
        .isFitted  = true
        .panOffset = {}
        .sigZoomChanged.call(me)
        .invalidate()
    }

    // Displays one image pixel per logical unit and recentres it.
    mtd actualSize()
    {
        .panOffset = {}
        .applyZoom(1)
    }

    // Rotates a still image clockwise and keeps the current viewing mode.
    //
    // Animated sources are left unchanged; their frame sequence remains owned by [[Gui.Movie]].
    mtd rotateClockwise()
    {
        if .movie.isValid() or !.image.isValid() do
            return

        .image.rotate(.Clockwise90)
        if .uploadedTexture.isValid() do
            .app().renderer.removeTexture(&.uploadedTexture)
        .uploadedTexture = .app().renderer.addImage(.image)
        .panOffset       = {}
        .sigZoomChanged.call(me)
        .invalidate()
    }

    // Pauses or resumes GIF playback.
    mtd setPaused(paused: bool)
    {
        .movie.setPaused(paused)
        .invalidate()
    }

    // Selects one GIF frame, clamped to the available frame range.
    mtd setFrameIndex(index: s32)
    {
        .movie.setFrameIndex(index)
        if .movie.isValid() do
            .updateUploadedFrame()
        .sigFrameChanged.call(me)
        .invalidate()
    }
}
