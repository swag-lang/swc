using Core, Pixel

// A capture pinned on the screen: the picture in a small window that stays above the others,
// where the zone was taken, so it can be read while working elsewhere.
//
// The window is a floating sheet. The picture is a control rather than the sheet's ground: it
// takes the pointer itself, so a drag moves the window, a double click takes it off the screen,
// and a click gives it the keyboard, where `Esc` takes it off the screen too.
struct PinnedCapture
{
    using wnd: Wnd

    image:      Image
    texture:    Texture
    isDragging: bool
    dragFrom:   Math.Point         // Pointer at the start of a drag, in physical screen pixels.
    dragOrigin: Math.Rectangle     // Window at the start of a drag, in physical screen pixels.
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

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let surface = .surface
        if not surface do
            return

        switch evt.kind
        {
        case .DoubleClick where evt.button == .Left:
            .isDragging = false
            .releaseMouse()
            .close()

        case .Pressed where evt.button == .Left:
            .setFocus()
            .isDragging = true
            .dragFrom   = .app().mouse.position()
            .dragOrigin = surface.position
            .captureMouse()

        case .Move where .isDragging:
            let pointer = .app().mouse.position()
            var moved   = .dragOrigin
            moved.x += pointer.x - .dragFrom.x
            moved.y += pointer.y - .dragFrom.y
            surface.setPosition(moved)

        case .Released where .isDragging:
            .isDragging = false
            .releaseMouse()
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
    // Pins `image` on the screen over `screenRect`, in physical screen pixels, at the size of
    // its pixels.
    #[Swag.Discardable]
    func open(image: Image, screenRect: Math.Rectangle)->*PinnedCapture?
    {
        // The sheet casts its shadow into a margin around its body: the window is the picture
        // grown by that margin. It is created where it stands, so it takes the scale of that
        // monitor from the start.
        let scale   = Env.monitorForPoint({screenRect.horzCenter(), screenRect.vertCenter()}).scaleFactor
        let margin  = Math.ceil(g_App.theme.floatingShadowMargin() * scale)
        let outer   = Math.Rectangle{screenRect.x - margin, screenRect.y - margin, screenRect.width + 2 * margin, screenRect.height + 2 * margin}
        let width   = cast(s32, Math.ceil(screenRect.width / scale))
        let height  = cast(s32, Math.ceil(screenRect.height / scale))
        let surface = catch g_App.createSurface(cast(s32, outer.x), cast(s32, outer.y), width, height, .ToolWindow | .TopMost | .Sheet)
        {
            return null
        }

        with let result = Wnd.create'PinnedCapture(surface.wnd)
        {
            .image           = image
            .backgroundStyle = .Transparent
            .dockStyle       = .Center
            .focusPolicy     = .Click
            .cursor          = Cursor.from(CursorShape.Move)
        }

        // A small zone is smaller than the default minimum size of a surface.
        surface.minSize = {}
        surface.setView(result)
        surface.setPosition(outer)
        surface.show()
        surface.bringToFront()
        result.setFocus()
        return result
    }

    // Takes the picture off the screen.
    mtd close()
    {
        .surface?.destroy()
    }
}
