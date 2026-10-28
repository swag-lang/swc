using Core, Pixel

// A capture pinned on the screen: the picture in a small window that stays above the others,
// where the zone was taken, so it can be read while working elsewhere.
//
// The window is a sheet: its ground drags it. A double click or `Esc` takes it off the screen.
struct PinnedCapture
{
    using wnd: Wnd

    image:   Image
    texture: Texture
}

impl IWnd for PinnedCapture
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        if not .texture.isValid() do
            .texture = evt.paintContext.renderer.addImage(.image)
        painter.setInterpolationMode(.Linear)
        painter.drawTexture(.clientRect(), .texture)
    }

    // A double click takes the picture off the screen; a press anywhere else is left to the
    // sheet, which drags it.
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        evt.accepted = false
        if evt.kind == .DoubleClick and evt.button == .Left
        {
            .close()
            evt.accepted = true
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind == .Pressed and evt.key == .Escape
        {
            .close()
            evt.accepted = true
        }
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        if .texture.isValid() do
            .app().renderer.removeTexture(&.texture)
    }
}

impl PinnedCapture
{
    // Pins `image` on the screen over `screenRect`, in physical screen pixels.
    #[Swag.Discardable]
    func open(image: Image, screenRect: Math.Rectangle)->*PinnedCapture?
    {
        let surface = catch g_App.createSurface(0, 0, 16, 16, .ToolWindow | .TopMost | .Sheet)
        {
            return null
        }

        with let result = Wnd.create'PinnedCapture(surface.wnd)
        {
            .image           = image
            .backgroundStyle = .Transparent
            .dockStyle       = .Center
        }

        surface.setView(result)
        surface.setPosition(screenRect)
        surface.show()
        surface.bringToFront()
        return result
    }

    // Takes the picture off the screen.
    mtd close()
    {
        .surface?.destroy()
    }
}
