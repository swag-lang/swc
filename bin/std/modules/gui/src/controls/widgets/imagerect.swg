#global public

using Core, Pixel

// Displays a texture, sprite-sheet animation, or animated GIF inside a window.
struct ImageRect
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        sigFrameChanged: SigArray'func||(*ImageRect)     // Emitted after the visible animation frame changes.

        readonly
        {
            movie: Movie     // Playback state for the current content.
        }
    }

    uploadedTexture: Texture     // Renderer texture owned by this window, if any.
}

impl IWnd for ImageRect
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .clear()
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        if !.movie.isValid() do
            return

        // Advance playback and upload a newly decoded GIF frame when necessary.
        if .movie.update(.app().timing.deltaSeconds)
        {
            if .movie.source != .SpriteSheet
            {
                .app().renderer.updateTexture(.uploadedTexture, nnPixels(.movie.frame.pixels.buffer))
            }
        }

        let painter = evt.paintContext.painter
        let rect    = .paddedClientRect()

        let color = .themeColors().imageRect_Fg

        switch #complete .movie.source
        {
        case .None:
            break

        case .SpriteSheet:
            let icon = Icon.from(&.movie.imgList, .movie.frameIndex, rect.width, rect.height)
            icon.paint(painter, rect.x, rect.y, color)

        case .Gif:
            painter.drawTexture(rect, .uploadedTexture, color)
        }

        if .movie.frameCount > 1 and !.movie.isPaused do
            .invalidate()
    }
}

impl ImageRect
{
    // Creates an empty image window.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: WndId? = null)->*ImageRect
    {
        Debug.assert(parent != null)
        let result = Wnd.create'ImageRect(parent, null, position, id)
        result.movie.sigFrameChanged += func|result|(movie)
        {
            result.sigFrameChanged.call(result)
            result.invalidate()
        }
        return result
    }

    // Releases renderer-owned content and restores an empty image window.
    mtd clear()
    {
        if .uploadedTexture.isValid() do
            .app().renderer.removeTexture(&.uploadedTexture)
        .movie.clear()
        .invalidate()
    }

    // Uses a borrowed image-list atlas as an animated sprite sheet.
    mtd setSpriteSheet(imageList: ImageList)
    {
        .clear()
        .movie.setSpriteSheet(imageList)
        .movie.setPaused(false)
        .invalidate()
    }

    // Displays the first frame of a borrowed image-list atlas without animation.
    mtd setImageList(imageList: ImageList)
    {
        .clear()
        .movie.setSpriteSheet(imageList)
        .movie.setPaused(true)
        .invalidate()
    }

    // Displays a borrowed renderer texture as one frame.
    //
    // The whole texture becomes one frame: an image rectangle shows a picture, not an animation.
    mtd setTexture(texture: Texture)
    {
        .clear()
        .movie.setSpriteSheet(ImageList.create(texture))
        .movie.setPaused(true)
        .invalidate()
    }

    // Uploads and displays an owned copy of an image.
    mtd setImage(image: Image)
    {
        .clear()
        .uploadedTexture = .app().renderer.addImage(image)
        .movie.setSpriteSheet(ImageList.create(.uploadedTexture))
        .movie.setPaused(true)
        .invalidate()
    }

    // Selects a frame, clamping the index to the available range.
    mtd setFrameIndex(index: s32)
    {
        .movie.setFrameIndex(index)
        .invalidate()
    }

    // Pauses or resumes time-based playback.
    mtd setPaused(paused: bool)
    {
        if .movie.isPaused == paused do
            return
        .movie.setPaused(paused)
        .invalidate()
    }

    // Changes the duration of every frame, in seconds.
    mtd setFrameDuration(seconds: f32)
    {
        Debug.assert(seconds > 0, "frame duration must be positive")
        .movie.frameDurationSeconds = seconds
    }

    // Enables or disables restart after the final frame.
    mtd setLooping(looping: bool)
    {
        .movie.loops = looping
    }

    // Loads and displays an animated GIF without changing the current content on failure.
    mtd loadGif(fileName: string) fail
    {
        try .movie.load(fileName)
        .movie.setPaused(false)
        if .uploadedTexture.isValid() do
            .app().renderer.removeTexture(&.uploadedTexture)
        .uploadedTexture = .app().renderer.addImage(.movie.frame)
        .invalidate()
    }
}
