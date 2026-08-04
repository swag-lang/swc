using Core, Win32, Gdi32, Pixel

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

struct CaptureRectWnd
{
    using wnd: Wnd

    #[Swag.Late]
    main:          *MainWnd
    startGrab:     bool
    cancelGrab:    bool
    tryStartGrab:  bool
    autoGrab:      bool
    lerpGrab:      Math.Rectangle
    clickStartPos: Math.Point     // Track where the click started
}

impl IWnd for CaptureRectWnd
{
    mtd testAutoGrab()
    {
        let pt = Input.mousePosition()
        let r  = screenToDesktopRect(getWndRectAtPos(notnull .surface, pt.x, pt.y))
        if !r.isEmpty()
        {
            g_StartGrabX = r.x
            g_StartGrabY = r.y
            g_EndGrabX   = r.right()
            g_EndGrabY   = r.bottom()
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind == .Pressed and evt.key == .Escape do
            g_Exit = true

        .invalidate()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        // Grab coordinates are canonical desktop-physical pixels (they crop the
        // physical desktop image); the event position is logical surface units.
        let k        = .deviceScale()
        let physPosX = evt.surfacePos.x * k
        let physPosY = evt.surfacePos.y * k

        switch evt.kind
        {
        case .Pressed where evt.button == .Right:
            .startGrab    = false
            .tryStartGrab = false
            .cancelGrab   = true
            .autoGrab     = true     // Return to auto grab mode

        case .Pressed where evt.button == .Left:
            .tryStartGrab    = true
            .clickStartPos.x = physPosX
            .clickStartPos.y = physPosY

        case .Released where evt.button == .Left:
            if .cancelGrab
            {
                .cancelGrab = false
                break
            }

            // If we're still in tryStartGrab mode (didn't move mouse significantly)
            if .tryStartGrab
            {
                // Validate the current auto grab selection
                g_GrabDone = true
                g_Exit     = true
            }
            elif .startGrab
            {
                // Manual rectangle selection completed
                g_GrabDone = true
                g_Exit     = true
            }

        case .Move where .tryStartGrab:
            g_EndGrabX = physPosX
            g_EndGrabY = physPosY

            // Check if mouse moved significantly from click start position
            if Math.abs(physPosX - .clickStartPos.x) > k or
               Math.abs(physPosY - .clickStartPos.y) > k
            {
                // Switch to manual rectangle selection mode
                .tryStartGrab = false
                .startGrab    = true
                .autoGrab     = false

                // Set grab start to click position
                g_StartGrabX = .clickStartPos.x
                g_StartGrabY = .clickStartPos.y
            }

        case .Move where .startGrab:
            g_EndGrabX = physPosX
            g_EndGrabY = physPosY
            .invalidate()

        case .Move:

            // Auto grab is always active when not dragging
            if !.startGrab
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

        // Lerp grab rectangle only in auto grab mode
        if .autoGrab and !.startGrab
        {
            .lerpGrab.x      = easeGrab(.lerpGrab.x, grabRect.x)
            .lerpGrab.y      = easeGrab(.lerpGrab.y, grabRect.y)
            .lerpGrab.width  = easeGrab(.lerpGrab.width, grabRect.width)
            .lerpGrab.height = easeGrab(.lerpGrab.height, grabRect.height)
            var roundRect = .lerpGrab
            roundRect.round()
            if !grabRect.isEqualEpsilon(roundRect) do
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
        let k = .deviceScale()
        var dstGrab = grabRect
        dstGrab.x      /= k
        dstGrab.y      /= k
        dstGrab.width  /= k
        dstGrab.height /= k

        // Redraw the selected region at full brightness from the same texture. The
        // desktop texture texels are physical desktop pixels, so the grab rect is
        // the source rect directly.
        if !grabRect.isEmpty() do
            painter.drawTexture(dstGrab, grabRect, g_DesktopTexture)

        let col = .themeColors().hilight
        painter.drawRect(dstGrab, col, 2)

        // Crosshair guides - only in manual grab mode. The cursor sits on the dragged
        // corner, so split each line around the selection instead of running it along
        // (and hiding it behind) the rectangle border. The cross then meets the corner
        // and stays clearly visible over the dimmed background.
        if .main.captureOptions.drawCross and !.autoGrab
        {
            let cross = Argb.White
            let endX  = g_EndGrabX / k
            let endY  = g_EndGrabY / k
            painter.drawLine(endX, 0, endX, dstGrab.y, cross)
            painter.drawLine(endX, dstGrab.bottom(), endX, cast(f32) g_ScreenHeight / k, cross)
            painter.drawLine(0, endY, dstGrab.x, endY, cross)
            painter.drawLine(dstGrab.right(), endY, cast(f32) g_ScreenWidth / k, endY, cross)
        }

        // Dimensions, reported in physical desktop pixels: that is the size of the
        // captured image.
        if grabRect.width > 0 and grabRect.height > 0
        {
            let fontR = notnull .font().regular
            let str   = Format.toString("% x %", grabRect.width, grabRect.height)
            var xx    = dstGrab.x + 4
            var yy    = dstGrab.y - fontR.height - 8
            if xx < 0 or yy < 0
            {
                xx = dstGrab.x + 5
                yy = dstGrab.y + 5
            }

            let m = Painter.measureString(str, fontR)
            painter.fillRoundRect({xx - 4, yy - 4, m.width + 8, fontR.height + 8}, 2, 2, col)

            painter.drawString(xx, yy, str, fontR, Argb.White)
        }
    }
}
