using Core, Pixel

// Ease-out one component of the auto-selection rectangle toward its target. Advancing
// a fraction of the remaining distance each frame makes long jumps (e.g. moving from
// one monitor to another) close quickly while decelerating smoothly near the target.
// A minimum step keeps short moves responsive and guarantees the animation settles.
func easeGrab(current, target: f32)->f32
{
    let factor  = 0.35'f32
    let minStep = 16.0'f32
    let step    = Math.max(Math.abs(target - current) * factor, minStep)
    return Math.moveTowards(current, target, step)
}

// The area overlay: the chosen zone at full brightness with a 1 px Voltage edge, its
// size in a mono chip, and, while a zone is dragged, a pixel loupe with a Voltage crosshair.
const AreaChipPadding = 8.0      // Air inside the size chip and the loupe reading.
const AreaChipGap     = 6.0      // Air between the size chip and the zone.
const AreaLoupeRadius = 60.0     // Radius of the pixel loupe.
const AreaLoupePixels = 21.0     // Desktop pixels across the loupe; odd, so one sits in the middle.
const AreaLoupeOffset = 28.0     // Distance between the pointer and the loupe.

// The overlay over the frozen desktop where the user drags the area to capture.
struct CaptureRectWnd
{
    using wnd: Wnd

    late main:     *MainWnd
    startGrab:     bool
    tryStartGrab:  bool
    autoGrab:      bool
    detachWindow:  bool     // A keeps a selected area at screen coordinates.
    lerpGrab:      Math.Rectangle
    clickStartPos: Math.Point

    // Where the pointer is, in logical units, for the loupe.
    pointer: Math.Point
}

impl IWnd for CaptureRectWnd
{
    mtd testAutoGrab()
    {
        let pt     = Input.mousePosition()
        let window = getCaptureWindowAtPos(unwrap .surface, pt.x, pt.y)
        let r      = screenToDesktopRect(window.rect)
        if not r.isEmpty()
        {
            g_StartGrabX    = r.x
            g_StartGrabY    = r.y
            g_EndGrabX      = r.right()
            g_EndGrabY      = r.bottom()
            g_CaptureWindow = window.info
            g_CaptureAnchored = window.info.nativeWindow != 0 and not .detachWindow
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind == .Pressed and evt.key == .Escape and evt.modifiers == .None do
            g_Exit = true

        // Tab changes what the capture keeps, before it is taken.
        if evt.kind == .Pressed and evt.key == .Tab and evt.modifiers == .None do
            g_CaptureMedia = nextCaptureMedia(g_CaptureMedia)

        if evt.kind == .Pressed and evt.key == .A and evt.modifiers == .None
        {
            .detachWindow = not .detachWindow
            g_CaptureAnchored = g_CaptureWindow.nativeWindow != 0 and not .detachWindow
        }

        // Enter takes the zone on screen, as a click without a drag does.
        if evt.kind == .Pressed and
           evt.key == .Enter and
           evt.modifiers == .None and
           not getGrabRect().isEmpty()
        {
            g_GrabDone = true
            g_Exit     = true
        }

        .invalidate()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        // Grab coordinates are canonical desktop-physical pixels (they crop the
        // physical desktop image); the event position is logical surface units.
        let k        = .deviceScale()
        let physPosX = evt.surfacePos.x * k
        let physPosY = evt.surfacePos.y * k
        .pointer = evt.surfacePos

        switch evt.kind
        {
        case .Pressed where evt.button == .Right:
            if .startGrab or .tryStartGrab
            {
                // Abandon only the rectangle in progress. The first drag's release must not
                // accept the auto-detected zone, and the pointer can start a new drag.
                .startGrab               = false
                .tryStartGrab            = false
                .autoGrab                = true
                g_StartGrabX, g_EndGrabX = physPosX
                g_StartGrabY, g_EndGrabY = physPosY
                g_CaptureWindow          = {}
                g_CaptureAnchored        = false
                .testAutoGrab()
                .lerpGrab = getGrabRect()
                .invalidate()
            }
            else
            {
                g_Exit = true
            }

        case .Pressed where evt.button == .Left:
            .tryStartGrab    = true
            .clickStartPos.x = physPosX
            .clickStartPos.y = physPosY

        case .Released where evt.button == .Left:

            // If we're still in tryStartGrab mode (didn't move mouse significantly)
            if .tryStartGrab
            {
                // A click without a drag accepts the auto-detected rectangle.
                g_GrabDone = true
                g_Exit     = true
            }
            elif .startGrab
            {
                g_EndGrabX = physPosX
                g_EndGrabY = physPosY

                // Resolve which window owns the manually selected rectangle.
                let rect       = getGrabRect()
                let screenRect = Math.Rectangle{g_DesktopX + rect.x, g_DesktopY + rect.y, rect.width, rect.height}
                g_CaptureWindow = getCaptureWindowForRect(unwrap .surface, screenRect)
                g_CaptureAnchored = g_CaptureWindow.nativeWindow != 0 and not .detachWindow
                g_GrabDone      = true
                g_Exit          = true
            }

        case .Move where .tryStartGrab:

            // Wait for more than one device pixel of movement before switching modes.
            if Math.abs(physPosX - .clickStartPos.x) > k or
               Math.abs(physPosY - .clickStartPos.y) > k
            {
                // A drag selects a rectangle instead of accepting the auto-grab.
                .tryStartGrab = false
                .startGrab    = true
                .autoGrab     = false

                // Anchor the manual rectangle at the original press location.
                g_StartGrabX = .clickStartPos.x
                g_StartGrabY = .clickStartPos.y
                g_EndGrabX   = physPosX
                g_EndGrabY   = physPosY
                .invalidate()
            }

        case .Move where .startGrab:
            g_EndGrabX = physPosX
            g_EndGrabY = physPosY
            .invalidate()

        case .Move:

            // Track the window under the pointer until a manual drag begins.
            if not .startGrab
            {
                .autoGrab = true
                .testAutoGrab()
                .invalidate()
            }
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        var grabRect = getGrabRect()

        // Smooth auto-grab changes between frames; manual selection follows the pointer.
        if .autoGrab and not .startGrab
        {
            .lerpGrab.x      = easeGrab(.lerpGrab.x, grabRect.x)
            .lerpGrab.y      = easeGrab(.lerpGrab.y, grabRect.y)
            .lerpGrab.width  = easeGrab(.lerpGrab.width, grabRect.width)
            .lerpGrab.height = easeGrab(.lerpGrab.height, grabRect.height)
            var roundRect = .lerpGrab
            roundRect.round()
            if not grabRect.isEqualEpsilon(roundRect) do
                .invalidate()
            grabRect = roundRect
        }
        else
        {
            .lerpGrab = grabRect
        }

        let painter = evt.paintContext.painter
        painter.setInterpolationMode(.Linear)

        // Dim the whole desktop in a single opaque, tinted texture draw. The shader
        // multiplies the texture by the brush color, so a gray tint darkens the image
        // exactly like the former {0,0,0,100} black overlay (100/255 ~= 0.61 -> 155),
        // but without alpha-blending the entire virtual desktop every frame.
        let dimTint: Color = {155, 155, 155, 255}
        painter.drawTexture(.position, g_DesktopTexture, dimTint)

        // The grab rectangle lives in desktop-physical pixels; drawing works in
        // logical surface units.
        let k       = .deviceScale()
        var dstGrab = grabRect
        dstGrab.x      /= k
        dstGrab.y      /= k
        dstGrab.width  /= k
        dstGrab.height /= k

        // Redraw the selected region at full brightness from the same texture. The
        // desktop texture texels are physical desktop pixels, so the grab rect is
        // the source rect directly.
        if not grabRect.isEmpty() do
            painter.drawTexture(dstGrab, grabRect, g_DesktopTexture)

        // The cursor, where it stood, when the capture keeps it.
        if .main.captureOptions.captureCursor and g_CursorTexture.isValid()
        {
            let patch = g_CursorPatchRect
            painter.drawTexture({patch.x / k, patch.y / k, patch.width / k, patch.height / k}, g_CursorTexture, dimTint)
            let inside = Math.Rectangle.intersect(patch, grabRect)
            if not inside.isEmpty()
            {
                let src = Math.Rectangle{inside.x - patch.x, inside.y - patch.y, inside.width, inside.height}
                painter.drawTexture({inside.x / k, inside.y / k, inside.width / k, inside.height / k}, src, g_CursorTexture)
            }
        }

        // A hairline in the signature states where the edge is, and nothing more lies on the
        // pixels about to be captured.
        let colors = .themeColors()
        painter.setParams(.Antialiased)
        painter.drawRect(dstGrab, colors.signature, 1)

        // Crosshair guides - only in manual grab mode. The cursor sits on the dragged
        // corner, so split each line around the selection instead of running it along
        // (and hiding it behind) the rectangle border. The cross then meets the corner
        // and stays clearly visible over the dimmed background.
        if .main.captureOptions.drawCross and not .autoGrab
        {
            // Translucent: the cross has to guide the eye without cutting the image.
            let cross: Color = {255, 255, 255, 110}
            let endX         = g_EndGrabX / k
            let endY         = g_EndGrabY / k
            painter.drawLine(endX, 0, endX, dstGrab.y, cross)
            painter.drawLine(endX, dstGrab.bottom(), endX, cast(f32, g_ScreenHeight) / k, cross)
            painter.drawLine(0, endY, dstGrab.x, endY, cross)
            painter.drawLine(dstGrab.right(), endY, cast(f32, g_ScreenWidth) / k, endY, cross)
        }

        .paintSizeChip(painter, grabRect, dstGrab)

        // The loupe serves the corner being dragged; while the zone follows the windows, the
        // pointer only names a window and the loupe would hide the work beside it.
        if .startGrab do
            .paintLoupe(painter)
    }
}

impl CaptureRectWnd
{
    // Writes what the capture keeps and the size of the zone, in physical desktop pixels — the size
    // of the captured image — in a mono chip standing on the top edge of the zone, or inside it
    // when the screen has no room above. The key that changes what is kept follows, fainter: the
    // chip is where the eye already is, so the overlay needs no line of keys of its own.
    mtd paintSizeChip(painter: *Painter, grabRect, dstGrab: Math.Rectangle)
    {
        if grabRect.width <= 0 or grabRect.height <= 0 do
            return

        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let font    = .theme().createDefaultFontFs(metrics.defaultFontSize - 1)
        let media   = kindName(g_CaptureMedia)
        let text    = Format.toString("% · % × %", media, grabRect.width, grabRect.height)
        let key     = Format.toString("  %", Gui.strings().key_Tab)
        let anchor  = g_CaptureWindow.nativeWindow ?
                      (g_CaptureAnchored ? appStrings().ui_AimAnchored : appStrings().ui_AimDetached) : ""
        let anchorText = anchor.count ? Format.toString(" · %  A", anchor) : String{}
        let width   = Painter.measureString(text, font).width + Painter.measureString(key, font).width +
                      Painter.measureString(anchorText, font).width + 2 * AreaChipPadding
        let height  = font.height + AreaChipPadding

        var chip = Math.Rectangle{dstGrab.x, dstGrab.y - height - AreaChipGap, width, height}
        if chip.y < 0 do
            chip.y = dstGrab.y + AreaChipGap
        painter.fillRoundRect(chip, metrics.corner_Chip, metrics.corner_Chip, colors.surface)

        let top = font.opticalLineTop(chip.vertCenter())
        let x   = chip.x + AreaChipPadding
        painter.drawString(x, top, text, font, colors.text)
        painter.drawString(x + Painter.measureString(text, font).width, top, key, font, colors.faintText)
        painter.drawString(x + Painter.measureString(text, font).width + Painter.measureString(key, font).width,
                           top, anchorText, font, colors.faintText)
    }

    // Draws the pixels around the pointer enlarged in a round loupe beside it, on their grid, the
    // pixel under the pointer marked by a Voltage crosshair, and its position under the loupe.
    mtd paintLoupe(painter: *Painter)
    {
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let k       = .deviceScale()
        let screen  = .clientRect()
        let r       = AreaLoupeRadius

        var cx = .pointer.x + AreaLoupeOffset + r
        var cy = .pointer.y + AreaLoupeOffset + r
        if cx + r > screen.right() do
            cx = .pointer.x - AreaLoupeOffset - r
        if cy + r + 32 > screen.bottom() do
            cy = .pointer.y - AreaLoupeOffset - r

        // The source is a square of desktop pixels centred on the one under the pointer.
        let px   = Math.floor(.pointer.x * k)
        let py   = Math.floor(.pointer.y * k)
        let half = Math.floor(AreaLoupePixels * 0.5)
        let src  = Math.Rectangle{px - half, py - half, AreaLoupePixels, AreaLoupePixels}
        let dst  = Math.Rectangle{cx - r, cy - r, 2 * r, 2 * r}
        let cell = 2 * r / AreaLoupePixels

        painter.startClippingRegion()
        painter.fillCircle(cx, cy, r, Argb.White)
        painter.endClippingRegion()
        painter.setInterpolationMode(.Pixel)
        painter.fillRect(dst, colors.ground)
        painter.drawTexture(dst, src, g_DesktopTexture)
        painter.setInterpolationMode(.Linear)

        let grid = Color.fromArgb(40, Argb.Black)
        for i in 1 until cast(s32, AreaLoupePixels)
        {
            let d = cast(f32, i) * cell
            painter.drawLine(dst.x + d, dst.y, dst.x + d, dst.bottom(), grid, 1)
            painter.drawLine(dst.x, dst.y + d, dst.right(), dst.y + d, grid, 1)
        }

        painter.drawLine(cx, dst.y, cx, dst.bottom(), colors.signature, 1)
        painter.drawLine(dst.x, cy, dst.right(), cy, colors.signature, 1)
        painter.resetClippingRegion()

        painter.setParams(.Antialiased)
        painter.drawCircle(cx, cy, r, colors.surface, 3)
        painter.drawCircle(cx, cy, r + 1.5, colors.line, 1)

        // The position under the loupe, a measure in the fixed-width family.
        let font  = .theme().createDefaultFontFs(metrics.defaultFontSize - 1)
        let text  = Format.toString("x % · y %", cast(s32, px + g_DesktopX), cast(s32, py + g_DesktopY))
        let width = Painter.measureString(text, font).width + 2 * AreaChipPadding
        let chip  = Math.Rectangle{Math.round(cx - width * 0.5), cy + r + AreaChipGap, width, font.height + AreaChipPadding}
        painter.fillRoundRect(chip, metrics.corner_Chip, metrics.corner_Chip, colors.surface)
        painter.drawString(chip.x + AreaChipPadding, font.opticalLineTop(chip.vertCenter()), text, font, colors.text)
    }
}
