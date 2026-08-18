using Pixel

// Renders a callback into an owned offscreen image through the GUI renderer.
#[Swag.Opaque]
public struct PaintImage
{
    // Called to paint one image. This is the only thing a caller sets.
    public paint: #null func||(app: *Application, painter: *Painter)

    // The offscreen application, its painter and the surface backing the render target.
    private
    {
        app:     Application     // Headless application driving the offscreen paint.
        painter: Painter         // Painter the callback draws into.
        #[Swag.Late]
        surface: *Surface     // Surface owning the render target.
        image:   Image        // Last painted result.
        w, h:    s32          // Size of the render target, in pixels.
    }
}

impl PaintImage
{
    private func onEvent(wnd: *Wnd, evt: IEvent)->bool
    {
        if !evt is PaintEvent do
            return false

        let pt    = cast(*PaintImage) wnd.surface!.userData!
        let paint = pt.paint
        if !paint do
            return false

        let painter = &pt.painter
        painter.begin()
        painter.setParams(.Antialiased)
        painter.clear(Argb.Zero)
        paint(wnd.app(), painter)
        painter.end()

        let r  = wnd.app().renderer
        let rt = r.acquireRenderTarget(pt.w, pt.h)
        r.bindRenderTarget(rt)
        r.draw(painter)
        pt.image = r.unbindRenderTargetToImage(0, 0, pt.w, pt.h)
        r.end()
        r.releaseRenderTarget(rt)

        return false
    }

    // Releases resources owned by this value.
    public mtd opDrop()
    {
        if @isset(.surface) do
            .surface.destroy()
    }

    // Initializes an offscreen target of `w` by `h` pixels.
    public mtd init(w, h: s32)
    {
        Debug.assert(w > 0 and h > 0, "paint image dimensions must be positive")
        .surface          = expect .app.createSurface(0, 0, 1, 1, hook: &onEvent)!
        .surface.userData = me
        .w                = w
        .h                = h
    }

    // Renders one callback and returns the resulting image.
    public mtd draw(call: func||(*Application, *Painter))->Image
    {
        .paint = call
        .surface.invalidate()
        .app.runFrame()
        return .image
    }

    // Initializes, renders, and returns an image in one call.
    public func draw(w, h: s32, call: func||(*Application, *Painter))->Image
    {
        var pt: PaintImage
        pt.init(w, h)
        return pt.draw(call)
    }
}
