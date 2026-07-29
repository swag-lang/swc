using Pixel

// Represents paint image.
#[Swag.Opaque]
public struct PaintImage
{
    app:     Application // App associated with this value.
    painter: Painter // Painter associated with this value.
    #[Swag.Late]
    surface: *Surface // Surface associated with this value.
    image:   Image // Image associated with this value.
    w, h:    s32 // W component.
    paint:   #null func||(app: *Application, painter: *Painter) // Paint associated with this value.
}

impl PaintImage
{
    private func onEvent(wnd: *Wnd, evt: IEvent)->bool
    {
        if !evt is PaintEvent do
            return false

        let pt    = notnull cast(#null *PaintImage) (notnull wnd.surface).userData
        let paint = pt.paint
        if !paint do
            return false

        let painter = &pt.painter
        painter.begin()
        painter.setParams(.Antialiased)
        painter.clear(Argb.Zero)
        paint(wnd.getApp(), painter)
        painter.end()

        let r  = &wnd.getApp().renderer
        let rt = r.getRenderTarget(pt.w, pt.h)
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

    // First init the PaintImage instance
    public mtd init(w, h: s32)
    {
        .surface          = notnull expect .app.createSurface(0, 0, 1, 1, hook: &onEvent)
        .surface.userData = me
        .w                = w
        .h                = h
    }

    // Draw to an image by calling the func
    public mtd draw(call: func||(*Application, *Painter))->Image
    {
        .paint = call
        .surface.invalidate()
        .app.runFrame()
        return .image
    }

    // One shot paint to image
    public func draw(w, h: s32, call: func||(*Application, *Painter))->Image
    {
        var pt: PaintImage
        pt.init(w, h)
        return pt.draw(call)
    }
}
