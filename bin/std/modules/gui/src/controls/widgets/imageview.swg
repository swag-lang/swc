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

        sigZoomChanged:      SigArray'func||(*ImageView)     // Emitted after the effective zoom changes.
        sigFrameChanged:     SigArray'func||(*ImageView)     // Emitted after an animation frame changes.
        sigTransformChanged: SigArray'func||(*ImageView)     // Emitted after the temporary view transform changes.

        readonly
        {
            zoom:                 f32  = 1        // Requested scale outside fitted mode.
            isFitted:             bool = true     // Whether the image is scaled to the available viewport.
            panOffset:            Math.Point      // Image-centre offset from the viewport centre, in logical units.
            movie:                Movie           // GIF playback state, or an empty movie for a still image.
            rotationQuarterTurns: u32             // Clockwise quarter turns applied to the displayed content.
            isMirrored:           bool            // Whether the displayed content is reflected before rotation.
        }
    }

    image:           Image          // Still image owned by the view, empty for a planar picture.
    uploadedTexture: Texture        // Renderer texture for the current still, movie or planar frame.
    isPanning:       bool           // Whether the left mouse button currently pans the image.
    lastPointer:     Math.Point     // Previous surface position of a pan gesture.

    // Vector document shown instead of a bitmap, or an empty drawing.
    //
    // A drawing is not rasterized once and magnified: every paint draws the contours at the
    // scale the view is showing them at, so the picture is as sharp at 800% as at 100% and a
    // zoom step costs a repaint rather than a re-rasterization.
    drawing: Svg.Drawing

    // Size of the planar picture the view shows, in its own pixels.
    //
    // Such a picture never becomes an image: the renderer keeps it in the layout the decoder
    // produced and converts it where it samples, so the view knows its geometry and nothing else.
    planarWidth:  s32
    planarHeight: s32

    // Size the content is laid out and drawn at, when that is not its own pixel size.
    //
    // A picture whose samples are not square is stored with fewer or more columns than it is
    // shown with. Zero on either axis means the content states its own shape.
    displayWidth:  s32
    displayHeight: s32
}

private impl ImageView
{
    mtd const currentImage()->const *Image
    {
        if .movie.isValid() do
            return &.movie.frame
        return &.image
    }

    // Reports whether the view holds a vector document rather than a bitmap.
    mtd const hasDrawing()->bool => .drawing.width > 0 and .drawing.height > 0

    // Reports whether the view has something to paint, whatever kind of content it holds.
    mtd const hasContent()->bool => .currentImage().isValid() or .planarWidth > 0 or .hasDrawing()

    // Returns the size the content is laid out and drawn at.
    //
    // That is its own pixel size unless a caller stated another one, which is what a picture
    // whose samples are not square needs: the texture keeps every sample it was given and the
    // rectangle it is drawn into carries the shape.
    mtd const sourceSize()->{ width, height: s32 }
    {
        if .displayWidth > 0 and .displayHeight > 0 do
            return {.displayWidth, .displayHeight}
        let source = .currentImage()
        if source.isValid() do
            return {source.width, source.height}
        if .hasDrawing() do
            return {cast(s32) Math.max(Math.round(.drawing.width), 1.0'f32), cast(s32) Math.max(Math.round(.drawing.height), 1.0'f32)}
        return {.planarWidth, .planarHeight}
    }

    // Returns the axis-aligned size after the temporary view transform.
    mtd const contentSize()->{ width, height: s32 }
    {
        let source = .sourceSize()
        if .rotationQuarterTurns & 1 do
            return {source.height, source.width}
        return source
    }

    mtd const contentRect()->Math.Rectangle
    {
        if !.hasContent() do
            return {}

        let size   = .contentSize()
        let client = .paddedClientRect()
        let scale  = .effectiveZoom()

        var result: retval
        result.width  = size.width * scale
        result.height = size.height * scale
        result.x      = client.horzCenter() - result.width * 0.5 + .panOffset.x
        result.y      = client.vertCenter() - result.height * 0.5 + .panOffset.y
        return result
    }

    // Returns the untransformed draw rectangle centred inside the transformed content bounds.
    mtd const sourceRect()->Math.Rectangle
    {
        let content = .contentRect()
        let source  = .sourceSize()
        let scale   = .effectiveZoom()
        let width   = source.width * scale
        let height  = source.height * scale
        return {content.horzCenter() - width * 0.5, content.vertCenter() - height * 0.5, width, height}
    }

    // Composes the source-space reflection and rotation beneath the window's paint transform.
    mtd const transformedPaint(base: Math.Transform2, center: Math.Point)->Math.Transform2
    {
        var result = Math.Transform2.Identity
        if .isMirrored do
            result.multiply(Math.Transform2.createScale(-1, 1, center.x, center.y))
        if .rotationQuarterTurns do
            result.multiply(Math.Transform2.createRotation(Math.toRadians(cast(f32) .rotationQuarterTurns * 90), center.x, center.y))
        result.multiply(base)
        return result
    }

    mtd updateUploadedFrame()
    {
        if !.uploadedTexture.isValid() do
            return
        .app().renderer.updateTexture(.uploadedTexture, nnPixels(.movie.frame.pixels.buffer))
    }

    mtd applyZoom(value: f32, anchor: const *Math.Point? = null)
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

    // Draws the vector document at the scale the view currently shows it at.
    //
    // Nothing is rasterized: the contours go through the painter under the view's own zoom,
    // which is what keeps a magnified drawing sharp instead of magnifying pixels. The clip
    // keeps a zoomed document inside the view, and the ground under it is the same
    // transparency check a picture with an alpha channel gets.
    mtd paintDrawing(painter: *Painter, client: Math.Rectangle)
    {
        painter.fillRect(client, .themeColors().view_Bk)

        let content = .sourceRect()
        let scale   = .effectiveZoom()
        if content.width <= 0 or content.height <= 0 or scale <= 0 do
            return

        painter.pushClippingRect(client)
        defer painter.popClippingRect()
        painter.fillRect(.contentRect(), Brush.createHatch(.CheckBoardLarge, .themeColors().colorPicker_BackAlpha))

        let base = painter.transform()
        if .rotationQuarterTurns or .isMirrored do
            painter.setTransform(.transformedPaint(base, {content.horzCenter(), content.vertCenter()}))
        .drawing.paint(painter, content.x, content.y, scale)
        painter.setTransform(base)
    }

    mtd applyTransform(quarterTurns: u32, mirrored: bool)
    {
        .rotationQuarterTurns = quarterTurns & 3
        .isMirrored           = mirrored
        .panOffset            = {}
        .sigTransformChanged.call(me)
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
        let client  = .clientRect()

        if .movie.isValid() and .movie.update(.app().timing.deltaSeconds)
        {
            .updateUploadedFrame()
            .sigFrameChanged.call(me)
        }

        if .hasDrawing()
        {
            .paintDrawing(painter, client)
            return
        }

        if !.hasContent() or !.uploadedTexture.isValid()
        {
            painter.fillRect(client, .themeColors().view_Bk)
            return
        }

        let source      = .currentImage()
        let destination = .contentRect()
        let sourceRect  = .sourceRect()
        let tint        = .themeColors().imageRect_Fg
        let transparent = source.isValid() and source.pixelFormat.hasAlpha()

        // A picture that covers the view with opaque samples hides the ground completely, and a
        // video repaints this view as many times a second as it has frames. Filling first would
        // be one whole-view fill per frame that nothing can ever see.
        if transparent or !tint.isOpaque() or !destination.contains(client) do
            painter.fillRect(client, .themeColors().view_Bk)

        if transparent do
            painter.fillRect(destination, Brush.createHatch(.CheckBoardLarge, .themeColors().colorPicker_BackAlpha))

        if .rotationQuarterTurns or .isMirrored
        {
            let base = painter.transform()
            painter.setTransform(.transformedPaint(base, {sourceRect.horzCenter(), sourceRect.vertCenter()}))
            painter.drawTexture(sourceRect, .uploadedTexture, tint)
            painter.setTransform(base)
        }
        else do
            painter.drawTexture(sourceRect, .uploadedTexture, tint)

        if .movie.isValid() and .movie.frameCount > 1 and !.movie.isPaused do
            .invalidate()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        switch evt.kind
        {
        case .Wheel:
            if !.hasContent()
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
            if !.hasContent() do
                return
            .isPanning   = true
            .lastPointer = evt.surfacePos
            .captureMouse()

        case .Move:
            if !.isPanning
            {
                if .hasContent() do
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
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: WndId? = null)->*ImageView
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
        Swag.drop(&.image, 1)
        Swag.init(&.image, 1)
        Swag.drop(&.drawing, 1)
        Swag.init(&.drawing, 1)
        .planarWidth          = 0
        .planarHeight         = 0
        .zoom                 = 1
        .isFitted             = true
        .panOffset            = {}
        .rotationQuarterTurns = 0
        .isMirrored           = false
        .invalidate()
    }

    // Displays a vector document and fits it to the viewport.
    //
    // The view takes ownership of `drawing` and paints its contours at the scale it is
    // showing them at, so zooming stays sharp and costs a repaint instead of a new
    // rasterization. Zoom, pan, fit, rotation, and mirroring behave as they do for a
    // picture; the document's view box is the size they work from.
    //
    // ```swag
    // view.setDrawing(try Svg.Drawing.parse(source))
    // ```
    mtd setDrawing(drawing: Svg.Drawing)
    {
        .clear()
        .drawing = drawing
        .zoomToFit()
    }

    // Displays an owned copy of `image` and fits it to the viewport.
    mtd setImage(image: Image)
    {
        .clear()
        .image           = image
        .uploadedTexture = .app().renderer.addImage(.image)
        .zoomToFit()
    }

    // Takes an image's pixel storage and fits it to the viewport.
    //
    // `image` is left empty. Use this after a one-shot decode when the caller has no reason to
    // retain a second pixel buffer; use [[Gui.ImageView.setImage]] when the caller keeps its own
    // independent image.
    mtd takeImage(image: *Image)
    {
        .clear()
        if !image.isValid() do
            return

        .image           = #move image[]
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

    // Displays a planar 4:2:0 picture, which the renderer converts while it draws.
    //
    // This is what a video stream should reach the screen through. Converting a picture to packed
    // RGB costs more processor time at high resolutions than decoding it did, and none of it is
    // needed: the renderer holds the planes the decoder produced and converts them where it
    // samples. The view never owns the picture, so `view` is borrowed for the call alone.
    //
    // ```swag
    // try reader.decodeFramePlanesInto(&picture, index)
    // view.updateVideoFrame(picture.view())
    // ```
    // States the size the content is shown at, whatever size it is stored in.
    //
    // A picture mastered for a television standard stores samples that are not square: 720 by 576
    // samples shown across sixteen units by nine. Pass that shown size here and the view lays out
    // and draws the picture with it; pass zero to go back to the content's own size. The texture
    // is untouched, so nothing is resampled twice.
    //
    // ```swag
    // view.setDisplaySize(reader.displayWidth(), reader.displayHeight())
    // ```
    mtd setDisplaySize(width, height: s32)
    {
        if width == .displayWidth and height == .displayHeight do
            return
        .displayWidth  = Math.max(width, 0)
        .displayHeight = Math.max(height, 0)
        if .isFitted do
            .zoomToFit()
        .invalidate()
    }

    mtd updateVideoFrame(view: const *Yuv420View)
    {
        if view.width <= 0 or view.height <= 0
        {
            .clear()
            return
        }

        if .movie.isValid() or .image.isValid() or !.uploadedTexture.isValid() or view.width != .planarWidth or view.height != .planarHeight
        {
            .clear()
            .planarWidth     = view.width
            .planarHeight    = view.height
            .uploadedTexture = .app().renderer.addImage(view)
            .zoomToFit()
            return
        }

        .app().renderer.updateTexture(.uploadedTexture, view)
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
        let turns  = .rotationQuarterTurns
        let mirror = .isMirrored

        .clear()
        .image                = image
        .uploadedTexture      = .app().renderer.addImage(.image)
        .isFitted             = fitted
        .zoom                 = Math.clamp(scaled, MinZoom, MaxZoom)
        .panOffset            = offset
        .rotationQuarterTurns = turns
        .isMirrored           = mirror
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

        .exchangeMovie(&movie)
    }

    // Displays a prepared movie by exchanging its owned decoding state with the view.
    //
    // This is the publication counterpart to loading or decoding a [[Gui.Movie]] outside the GUI
    // thread. On return, `movie` owns the content that previously belonged to the view, or an
    // empty movie when the view had none. An invalid movie clears the view.
    mtd exchangeMovie(movie: *Movie)
    {
        if .uploadedTexture.isValid() do
            .app().renderer.removeTexture(&.uploadedTexture)
        Swag.drop(&.image, 1)
        Swag.init(&.image, 1)
        .planarWidth, .planarHeight = 0
        swap(&.movie, movie)
        if .movie.isValid() do
            .uploadedTexture = .app().renderer.addImage(.movie.frame)
        .isFitted  = true
        .zoom      = 1
        .panOffset = {}
        .sigZoomChanged.call(me)
        .invalidate()
    }

    // Returns the scale currently used to paint the image.
    mtd const effectiveZoom()->f32
    {
        if !.hasContent() do
            return 1
        if !.isFitted do
            return .zoom

        let client = .paddedClientRect()
        if client.width <= 0 or client.height <= 0 do
            return 1

        let size = .contentSize()
        return Math.min(client.width / size.width, client.height / size.height)
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

    // Rotates the displayed content clockwise without changing its source pixels.
    mtd rotateClockwise()
    {
        if !.hasContent() do
            return
        .applyTransform(.rotationQuarterTurns + 1, .isMirrored)
    }

    // Rotates the displayed content counter-clockwise without changing its source pixels.
    mtd rotateCounterClockwise()
    {
        if !.hasContent() do
            return
        .applyTransform(.rotationQuarterTurns + 3, .isMirrored)
    }

    // Reflects the displayed content across the viewport's vertical axis.
    mtd mirrorHorizontally()
    {
        if !.hasContent() do
            return
        .applyTransform((4 - .rotationQuarterTurns) & 3, !.isMirrored)
    }

    // Reflects the displayed content across the viewport's horizontal axis.
    mtd mirrorVertically()
    {
        if !.hasContent() do
            return
        .applyTransform((6 - .rotationQuarterTurns) & 3, !.isMirrored)
    }

    // Removes every temporary rotation and reflection without changing zoom.
    mtd resetTransform()
    {
        if !.rotationQuarterTurns and !.isMirrored do
            return
        .applyTransform(0, false)
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
