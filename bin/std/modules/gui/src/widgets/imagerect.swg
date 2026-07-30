#global public

using Core, Pixel

// Represents image rect.
struct ImageRect
{
    using wnd:    Wnd         // Embedded wnd state.
    movie:        Movie       // Movie associated with this value.
    textureFrame: Texture     // Texture frame associated with this value.
}

impl IWnd for ImageRect
{
    mtd impl onPaintEvent(evt: *PaintEvent)
    {
        if !.movie.isValid() do
            return

        // Update movie, and update resulting texture frame if necessary
        if .movie.update(.getApp().timing.dt)
        {
            if .movie.source != .SpriteSheet
            {
                .getApp().renderer.updateTexture(.textureFrame, nnPixels(.movie.frame.pixels.buffer))
            }
        }

        let painter = evt.bc.painter
        let rect    = .getClientRectPadding()

        let color = .getThemeColors().imageRect_Fg

        switch #complete .movie.source
        {
        case .None:
            break

        case .SpriteSheet:
            let icon = Icon.from(&.movie.imgList, .movie.frameIndex, rect.width, rect.height)
            icon.paint(painter, rect.x, rect.y, color)

        case .Gif:
            painter.drawTexture(rect, .textureFrame, color)
        }

        if !.movie.numFrames or .movie.numFrames > 1 do
            .invalidate()
    }
}

impl ImageRect
{
    // Performs the create operation.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null)->*ImageRect
    {
        Debug.assert(parent != null)
        let res = Wnd.create'ImageRect(parent, null, position, id)
        return res
    }

    // Removes all content.
    mtd clear()
    {
        .getApp().renderer.removeTexture(&.textureFrame)
    }

    // Set movie as an image list
    mtd setMovie(image: ImageList)
    {
        .clear()
        .movie.set(image)
        .invalidate()
    }

    // Associate image
    mtd setImage(image: ImageList)
    {
        .setImage(image.texture)
    }

    // Associate image
    //
    // The whole texture becomes one frame: an image rectangle shows a picture, not an animation.
    mtd setImage(image: Texture)
    {
        .clear()
        var tmp: ImageList
        tmp.set(image)
        .movie.set(tmp)
    }

    // Associate image
    mtd setImage(image: Image)
    {
        .setImage(.getApp().renderer.addImage(image))
    }

    // Load and set movie
    mtd setFile(fileName: string) fail
    {
        .clear()
        try .movie.set(fileName)
        .textureFrame = .getApp().renderer.addImage(.movie.frame)
        .invalidate()
    }
}
