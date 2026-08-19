struct EditView
{
    using wnd: Wnd
    #[Swag.Late]
    main: *MainWnd
    #[Swag.Late]
    scroll:     *ScrollWnd
    capture:    #null *Capture
    zoom:       f32 = 1
    viewMargin: f32 = 32
    firstPaint      = true

    // Set by [EditView.setInPlaceEdit], which owns the zoom from then on.
    readonly
    inPlaceEdit: bool
}

impl IWnd for EditView
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        evt.accepted = false
        if !.capture do
            return

        if .capture.mouse(me, evt)
        {
            .invalidate()
            evt.accepted = true
            .setFocus()
            return
        }

        switch evt.kind
        {
        case .Wheel where !.inPlaceEdit:
            if evt.modifiers & .Control
            {
                evt.accepted = true
                let z = .zoom + (evt.delta.y > 0 ? 0.1 : -0.1)
                .setZoom(z, true)
            }
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        if .firstPaint
        {
            .zoomToFit(false)
            .firstPaint = false
        }

        let painter = evt.paintContext.painter

        // Background
        let matte = .main.editorOptions.editBackColor.a ? .main.editorOptions.editBackColor : .themeColors().view_Bk

        var rect = .clientRect()
        rect.offset(.scrollPos)
        painter.fillRect(rect, matte)
        if !.capture do
            return

        // Capture content
        let captureRect = .getCaptureRect()
        var clip        = rect
        clip.inflate(100, 100)
        .capture.paint(painter, clip, captureRect)

        // Around capture
        var col = matte
        col.a = .main.editorOptions.clipToSelection ? 255 : 200
        painter.fillRect({rect.x, rect.y, captureRect.x, rect.height}, col)
        painter.fillRect({captureRect.x, rect.y, captureRect.width, captureRect.y}, col)
        painter.fillRect({captureRect.right(), rect.y, rect.right() - captureRect.right(), rect.height}, col)
        painter.fillRect({captureRect.x, captureRect.bottom(), captureRect.width, rect.bottom() - captureRect.bottom()}, col)

        // Capture gizmo
        painter.pushTransform()
        painter.translateTransform(captureRect.x, captureRect.y)
        .capture.gizmo.rect = Math.Rectangle{0, 0, captureRect.width, captureRect.height}

        // The drag is where the minimum capture size is enforced, so the undo record the
        // gizmo produces is already valid and stays an exact inverse of itself. The gizmo
        // works in view pixels, hence the zoom. There is no maximum: a capture is as wide
        // as the screens it was taken from.
        .capture.gizmo.minSizeX = Capture.MinSize * .zoom
        .capture.gizmo.minSizeY = Capture.MinSize * .zoom

        // Neutral, not Voltage: this gizmo lies over arbitrary captured pixels, where the
        // accent competes with the content instead of reading against it. The application
        // spends Voltage on the rail, the active tool, and the primary action only.
        .capture.gizmo.paint(painter, false, Argb.White)
        painter.popTransform()
    }
}

impl EditView
{
    mtd opDrop()
    {
        Memory.delete(.capture)
    }

    mtd getCaptureRect()->Math.Rectangle
    {
        var captureRect: retval
        let rect    = .scroll.scrollableClientRect()
        let capture = .capture!
        captureRect.width  = capture.width * .zoom
        captureRect.height = capture.height * .zoom
        if .inPlaceEdit
        {
            // The grab origin is a desktop-physical pixel position and the view draws in
            // logical units, so it converts through the zoom like every other capture
            // measurement. The rectangle stays fractional: a whole desktop pixel is not a
            // whole logical unit on a scaled display, and rounding here would slide the
            // capture off the desktop showing through underneath.
            captureRect.x = -capture.backImagePos.x * .zoom
            captureRect.y = -capture.backImagePos.y * .zoom
            return captureRect
        }

        captureRect.x = rect.horzCenter() - captureRect.width * 0.5
        captureRect.y = rect.vertCenter() - captureRect.height * 0.5
        captureRect.round()
        return captureRect
    }

    const MinZoom = 0.1
    const MaxZoom = 10.0

    // Locks the view onto the desktop underneath, at one capture texel per device pixel.
    //
    // The in-place overlay draws the captured desktop back over the real one, so its zoom is
    // a consequence of the surface density and not a user setting: [zoomIn], [zoomOut],
    // [zoomToFit] and [setZoom] stop answering once this mode is on.
    mtd setInPlaceEdit(deviceScale: f32)
    {
        .inPlaceEdit = true
        .applyZoom(1.0 / deviceScale)
    }

    mtd setZoom(z: f32, mouseCenter = false)
    {
        if .inPlaceEdit do
            return
        .applyZoom(z, mouseCenter)
    }

    private mtd applyZoom(z: f32, mouseCenter = false)
    {
        var mousePos, mousePos1: Math.Point
        if mouseCenter
        {
            mousePos  = .app().mouse.position()
            mousePos  = .screenToSurface(mousePos)
            mousePos  = .surfaceToLocal(mousePos)
            mousePos1 = mousePos + .scrollPos
            mousePos1 /= .zoom
        }

        .zoom = Math.clamp(z, MinZoom, MaxZoom)
        let captureRect = .getCaptureRect()
        .scroll.setScrollSize(captureRect.width + (2 * .viewMargin), captureRect.height + (2 * .viewMargin))

        if mouseCenter
        {
            mousePos1 *= .zoom
            mousePos1 -= mousePos
            .scroll.setScrollPos(mousePos1.x, mousePos1.y)
        }

        .invalidate()
    }

    mtd canZoomIn()  => !.inPlaceEdit and !Math.isEqualEpsilon(.zoom, MaxZoom, 0.001)
    mtd canZoomOut() => !.inPlaceEdit and !Math.isEqualEpsilon(.zoom, MinZoom, 0.001)

    mtd zoomIn()
    {
        .setZoom(.zoom + 0.1)
    }

    mtd zoomOut()
    {
        .setZoom(.zoom - 0.1)
    }

    mtd zoomToFit(canZoom = true)
    {
        if .inPlaceEdit or !.capture do
            return

        // A degenerate (zero-sized) capture would divide by zero below.
        if .capture.width == 0 or .capture.height == 0 do
            return
        var rect = .clientRect()
        rect.inflate(-.viewMargin * 2)

        var zx = rect.width / .capture.width
        var zy = rect.height / .capture.height

        if !canZoom
        {
            zx = Math.min(zx, 1)
            zy = Math.min(zy, 1)
        }

        .setZoom(Math.min(zx, zy))
    }

    mtd setCapture(c: *Capture)
    {
        if .capture do
            Memory.delete(.capture)
        .capture = c
        if .capture do
            .capture.setup(me)
        if @isset(.main) do
            .main.captureHasChanged()
        .invalidate()
    }
}
