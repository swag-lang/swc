// How much the desktop around the zone of the in-place editor is darkened, out of 255.
const InPlaceDimAlpha = 110'u8

// The editor surface: the capture at its zoom, inside a margin, and the mouse edits on its forms.
// Air around the picture where a press still reaches its edges and their handles, not the ground.
const GroundPictureMargin = 12.0

// How near the edges of the picture, inside or out, the pointer brings out the handles that
// resize it. Away from them the picture shows no handle, so the only handles on screen are those
// of the selection.
const CaptureEdgeReach = 28.0

// Let a wheel gesture settle before rebuilding form layers at its final zoom.
const ZoomRefineDelay: Time.Duration = 180'ms

struct EditView
{
    using wnd:   Wnd
    late main:   *MainWnd
    late scroll: *ScrollWnd
    capture:     *Capture?
    inPlaceKindButton: *IconButton?
    zoom:        f32  = 1
    viewMargin:  f32  = 32
    firstPaint:  bool = true
    zoomTimer:   *Gui.Timer?

    // Set by [EditView.setInPlaceEdit], which owns the zoom from then on.
    readonly inPlaceEdit: bool

    // The words of a form typed in place (see inlinetext.swg): a field per line over the form,
    // the form, what it gives the fields, their font, and the angle the form turns back to.
    textLines:  Array'(*EditBox)
    textForm:   *BaseForm?
    textSpec:   InlineText
    textFont:   FontFamily
    textRotate: f32

    // Whether the pointer is near the edges of the picture, which shows the handles resizing it.
    pointerNearEdges: bool
}

impl IWnd for EditView
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .zoomTimer do
            return
        .stopTimer(&.zoomTimer)
        .invalidate()
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .stopTimer(&.zoomTimer)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        evt.accepted = false
        if not .capture do
            return

        .followPointerNearEdges(evt)

        // A double click on a form with words types them in place.
        if evt.kind == .DoubleClick and evt.button == .Left and .capture.hotForm < .capture.forms.count
        {
            let form = .capture.forms[.capture.hotForm]
            if inlineTextOf(form).found
            {
                .capture.selection.clear()
                .capture.selection.add(.capture.hotForm)
                .capture.selectionHasChanged()
                .beginTextEdit(form)
                evt.accepted = true
                return
            }
        }

        if .capture.mouse(me, evt)
        {
            .invalidate()
            evt.accepted = true
            .setFocus()

            // The mini-bar stands beside the selection, so it follows a form being moved.
            .main.placeMiniBar()
            return
        }

        switch evt.kind
        {
        case .Wheel where not .inPlaceEdit:
            if evt.modifiers & .Control
            {
                evt.accepted = true
                let z = .zoom + (evt.delta.y > 0 ? 0.1 : -0.1)
                .setZoom(z, true)
            }
        }
    }

    // Enter on the one selected form with words types them in place. The in-place editor keeps
    // Enter for copying the capture, and types words on a double click or F2.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed or
           evt.key != .Return or
           not evt.modifiers.equals(.None) or
           .inPlaceEdit do
            return
        let capture = .capture
        if not capture or capture.selection.count != 1 do
            return
        let form = capture.forms[capture.selection[0]]
        if not inlineTextOf(form).found do
            return
        .beginTextEdit(form)
        evt.accepted = true
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        if .firstPaint
        {
            .zoomToFit(false)
            .firstPaint = false
        }

        let painter = evt.paintContext.painter

        // The capture lies on the ground of the window, which nothing frames: the work area is
        // the window itself.
        let matte = .main.editorOptions.editBackColor.a ? .main.editorOptions.editBackColor : .themeColors().ground

        var rect = .clientRect()
        rect.offset(.scrollPos)
        painter.fillRect(rect, matte)
        if not .capture do
            return

        // Dim the matte, then paint the opaque capture back over its center: what a form draws
        // outside the capture shows through the dim, or not at all when the view clips to it.
        let captureRect = .getCaptureRect()
        var col         = matte
        col.a = .main.editorOptions.clipToSelection ? 255 : 200
        painter.fillRect(rect, col)

        var clip = rect
        clip.inflate(100, 100)
        .capture.paint(painter, clip, captureRect)

        // In place, the desktop stays dimmed around the zone, which keeps a white hairline and
        // says its size in a mono chip.
        if .inPlaceEdit do
            .paintInPlaceZone(painter, captureRect)

        painter.pushTransform()
        painter.translateTransform(captureRect.x, captureRect.y)
        .capture.gizmo.rect = Math.Rectangle{0, 0, captureRect.width, captureRect.height}

        // The drag is where the minimum capture size is enforced, so the undo record the
        // gizmo produces is already valid and stays an exact inverse of itself. The gizmo
        // works in view pixels, hence the zoom. There is no maximum: a capture is as wide
        // as the screens it was taken from.
        .capture.gizmo.minSizeX = Capture.MinSize * .zoom
        .capture.gizmo.minSizeY = Capture.MinSize * .zoom

        // The handles that resize the capture take the selection ink, like those of a form. They
        // stand where they serve: near the pointer at the edges, during their own drag, and all
        // the time in place, where the zone is what the reader adjusts.
        if .showsCaptureHandles() do
            .capture.gizmo.paint(painter, false, selectionInk())
        else do
            .capture.gizmo.placeAnchors()
        painter.popTransform()
    }
}

impl EditView
{
    // Reports whether the handles that resize the picture are shown.
    mtd showsCaptureHandles()->bool
    {
        let capture = .capture
        if not capture do
            return false
        return .inPlaceEdit or
               .pointerNearEdges or
               capture.gizmo.moving or
               capture.gizmo.hotAnchor != Swag.U32.Max
    }

    // Follows the pointer near the edges of the picture, and repaints when the handles come or go.
    mtd followPointerNearEdges(evt: *MouseEvent)
    {
        var near = false
        if evt.kind != .Leave and .capture
        {
            let pos     = .surfaceToLocal(evt.surfacePos) + .scrollPos
            let picture = .getCaptureRect()
            var outer   = picture
            outer.inflate(CaptureEdgeReach)
            var inner = picture
            inner.inflate(-CaptureEdgeReach)
            near = outer.contains(pos) and (inner.width <= 0 or inner.height <= 0 or not inner.contains(pos))
        }

        if near == .pointerNearEdges do
            return
        .pointerNearEdges = near
        .invalidate()
    }

    // Reports whether `surfacePos` falls on the ground around the picture, which moves the window
    // rather than the work.
    //
    // A tool that draws would only start a form off the picture there, so the ground is the
    // window's: nothing floats over it, and no form or handle of the picture stands there. The
    // selection tool keeps the ground for its lasso. Without a picture, the whole view is ground.
    mtd isWindowGround(surfacePos: Math.Point)->bool
    {
        if .inPlaceEdit or .textForm or not .isVisible() do
            return false
        let root = .surface?.wnd
        if not root or root.windowAt(surfacePos.x, surfacePos.y, true) != me do
            return false
        if not .capture do
            return true
        if .main.editMode == .Selection or .capture.mouseMode != .None do
            return false

        // The handles that resize the picture stand across its edges.
        var pos     = .surfaceToLocal(surfacePos) + .scrollPos
        var picture = .capture.paintRect
        picture.inflate(GroundPictureMargin)
        if picture.contains(pos) do
            return false

        pos.x -= .capture.paintRect.x
        pos.y -= .capture.paintRect.y
        return .capture.hitTest(pos) == Swag.U64.Max
    }

    mtd opDrop()
    {
        Memory.delete(.capture)
    }

    // Dims the desktop around the zone the in-place editor shows, rings the zone with a white
    // hairline and writes its size, in desktop pixels, in a mono chip on its top edge.
    mtd paintInPlaceZone(painter: *Painter, zone: Math.Rectangle)
    {
        let view = .clientRect()
        let veil = Color.fromArgb(InPlaceDimAlpha, Argb.Black)
        painter.fillRect(Math.Rectangle{view.x, view.y, view.width, zone.y - view.y}, veil)
        painter.fillRect(Math.Rectangle{view.x, zone.bottom(), view.width, view.bottom() - zone.bottom()}, veil)
        painter.fillRect(Math.Rectangle{view.x, zone.y, zone.x - view.x, zone.height}, veil)
        painter.fillRect(Math.Rectangle{zone.right(), zone.y, view.right() - zone.right(), zone.height}, veil)
        painter.setParams(.Default)
        painter.drawRect(zone, Argb.White, 1)

        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let capture = unwrap .capture
        let font    = .theme().createDefaultFontFs(metrics.defaultFontSize - 1)
        let text    = Format.toString("% × %", capture.width, capture.height)
        let pad     = metrics.hintLine_KeyGap
        let textWidth = Painter.measureString(text, font).width
        let chip      = .inPlaceSizeChipRect(zone, textWidth, font.height, pad)
        var textX   = chip.x + pad
        if .inPlaceKindButton
        {
            textX += .inPlaceKindButton.position.width + metrics.menuPopup_IconTextMargin + pad * 0.5
        }
        painter.setParams(.Antialiased)
        painter.fillRoundRect(chip, metrics.corner_Chip, metrics.corner_Chip, colors.surface)
        painter.drawString(textX, font.opticalLineTop(chip.vertCenter()), text, font, colors.text)
    }

    // Gives the dimensions and kind control one chip at the capture's top edge.
    mtd inPlaceSizeChipRect(zone: Math.Rectangle, textWidth, textHeight, pad: f32)->Math.Rectangle
    {
        let metrics = .themeMetrics()
        let buttonWidth = .inPlaceKindButton ? .inPlaceKindButton.position.width : 0.0
        let leading = buttonWidth > 0 ? buttonWidth + metrics.menuPopup_IconTextMargin + pad * 0.5 : 0.0
        let width  = leading + textWidth + 2 * pad
        let bounds = .clientRect()
        let x = Math.clamp(zone.x, bounds.x, Math.max(bounds.x, bounds.right() - width))
        return {x, zone.y - textHeight - pad - metrics.miniBar_Padding, width, textHeight + pad}
    }

    // Returns where the capture is painted in the view at the current zoom: centered, or at the
    // grabbed area in the in-place editor.
    mtd getCaptureRect()->Math.Rectangle
    {
        var captureRect: #returntype
        let rect    = .scroll.scrollableClientRect()
        let capture = unwrap .capture
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

        // Centred in the room the dock and the inspector leave, so neither covers the capture.
        let insets = .main.floatingInsets()
        captureRect.x = rect.x + insets.left + (rect.width - insets.left - insets.right) * 0.5 - captureRect.width * 0.5
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

    // Sets the zoom to `z`; with `mouseCenter`, scrolls so the point under the mouse stays put.
    private mtd applyZoom(z: f32, mouseCenter = false)
    {
        // Without a capture there is nothing to measure or scroll: keep the zoom for the next one.
        if not .capture
        {
            .zoom = Math.clamp(z, MinZoom, MaxZoom)
            return
        }

        let previousZoom = .zoom
        var mousePos, mousePos1: Math.Point
        if mouseCenter
        {
            mousePos  = .app().mouse.position()
            mousePos  = .screenToSurface(mousePos)
            mousePos  = .surfaceToLocal(mousePos)
            mousePos1 = mousePos + .scrollPos
            let before = .getCaptureRect()
            mousePos1 -= Math.Point{before.x, before.y}
            mousePos1 /= .zoom
        }

        .zoom = Math.clamp(z, MinZoom, MaxZoom)
        let captureRect = .getCaptureRect()
        var insets: FloatingInsets
        if not .inPlaceEdit do
            insets = .main.floatingInsets()
        .scroll.setScrollSize(captureRect.width + (2 * .viewMargin) + insets.left + insets.right, captureRect.height + (2 * .viewMargin))

        if mouseCenter
        {
            // Updating the virtual extent also moves its centred capture origin.
            let after = .getCaptureRect()
            mousePos1 *= .zoom
            mousePos1 += Math.Point{after.x, after.y}
            mousePos1 -= mousePos
            .scroll.setScrollPos(mousePos1.x, mousePos1.y)
        }

        let capture = .capture
        if not .inPlaceEdit and
           previousZoom != .zoom and
           capture != null and
           capture.formCaches.count != 0
        {
            .stopTimer(&.zoomTimer)
            .zoomTimer = .addTimer(ZoomRefineDelay)
        }

        .invalidate()
    }

    mtd canZoomIn()  => not .inPlaceEdit and not Math.isEqualEpsilon(.zoom, MaxZoom, 0.001)
    mtd canZoomOut() => not .inPlaceEdit and not Math.isEqualEpsilon(.zoom, MinZoom, 0.001)

    mtd zoomIn()
    {
        .setZoom(.zoom + 0.1)
    }

    mtd zoomOut()
    {
        .setZoom(.zoom - 0.1)
    }

    // Zooms so the whole capture fits in the view, never past 100% unless `canZoom`.
    mtd zoomToFit(canZoom = true)
    {
        if .inPlaceEdit or not .capture do
            return

        // A degenerate (zero-sized) capture would divide by zero below.
        if .capture.width == 0 or .capture.height == 0 do
            return
        let insets = .main.floatingInsets()
        var rect   = .clientRect()
        rect.inflate(-.viewMargin * 2)
        rect.width -= insets.left + insets.right

        var zx = rect.width / .capture.width
        var zy = rect.height / .capture.height

        if not canZoom
        {
            zx = Math.min(zx, 1)
            zy = Math.min(zy, 1)
        }

        .setZoom(Math.min(zx, zy))
    }

    mtd setCapture(c: *Capture)
    {
        .stopTimer(&.zoomTimer)
        if .capture do
            Memory.delete(.capture)
        .capture = c
        .capture?.setup(me)
        if .main != null
        {
            .main.captureHasChanged()
            .main.updateState()

            // A timed capture whose media is gone opens empty: say why.
            if c.isTimed() and c.mediaMissing do
                .main.reportFailure(appStrings().msg_MissingFrames,
                                    Path.fileName(Capture.mediaPathOf(c.file, c.media)) orelse "")
        }

        .invalidate()
    }
}
