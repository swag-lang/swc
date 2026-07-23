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
    using wnd:         Wnd

    main:              #late *MainWnd
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
        let pt = Input.getMousePos()
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
        if evt.kind == .KeyPressed and evt.key == .Escape do
            g_Exit = true

        .invalidate()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        switch evt.kind
        {
        case MousePressed where evt.button == .Right:
            .startGrab    = false
            .tryStartGrab = false
            .cancelGrab   = true
            .autoGrab     = true     // Return to auto grab mode

        case MousePressed where evt.button == .Left:
            .tryStartGrab    = true
            .clickStartPos.x = evt.surfacePos.x
            .clickStartPos.y = evt.surfacePos.y

        case MouseReleased where evt.button == .Left:
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

        case MouseMove where .tryStartGrab:
            g_EndGrabX = evt.surfacePos.x
            g_EndGrabY = evt.surfacePos.y

            // Check if mouse moved significantly from click start position
            if Math.abs(evt.surfacePos.x - .clickStartPos.x) > 1 or
               Math.abs(evt.surfacePos.y - .clickStartPos.y) > 1
            {
                // Switch to manual rectangle selection mode
                .tryStartGrab = false
                .startGrab    = true
                .autoGrab     = false

                // Set grab start to click position
                g_StartGrabX = .clickStartPos.x
                g_StartGrabY = .clickStartPos.y
            }

        case MouseMove where .startGrab:
            g_EndGrabX = evt.surfacePos.x
            g_EndGrabY = evt.surfacePos.y
            .invalidate()

        case MouseMove:
            // Auto grab is always active when not dragging
            if !.startGrab
            {
                .autoGrab = true
                .testAutoGrab()
                .invalidate()
            }
        }
    }

    mtd impl onPaintEvent(evt: *PaintEvent)
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

        let painter = evt.bc.painter
        painter.setInterpolationMode(.Linear)

        // Dim the whole desktop in a single opaque, tinted texture draw. The shader
        // multiplies the texture by the brush color, so a gray tint darkens the image
        // exactly like the former {0,0,0,100} black overlay (100/255 ~= 0.61 -> 155),
        // but without alpha-blending the entire virtual desktop every frame.
        let dimTint: Color = {155, 155, 155, 255}
        painter.drawTexture(.position, g_DesktopTexture, dimTint)

        // Redraw the selected region at full brightness from the same texture. The
        // desktop texture maps 1:1 onto the surface, so the source rect is the grab
        // rect relative to the surface origin.
        if !grabRect.isEmpty()
        {
            var srcRect = grabRect
            srcRect.x -= .position.x
            srcRect.y -= .position.y
            painter.drawTexture(grabRect, srcRect, g_DesktopTexture)
        }

        let col = .getThemeColors().hilight
        painter.drawRect(grabRect, col, 2)

        // Crosshair guides - only in manual grab mode. The cursor sits on the dragged
        // corner, so split each line around the selection instead of running it along
        // (and hiding it behind) the rectangle border. The cross then meets the corner
        // and stays clearly visible over the dimmed background.
        if .main.captureOptions.drawCross and !.autoGrab
        {
            let cross = Argb.White
            painter.drawLine(g_EndGrabX, 0, g_EndGrabX, grabRect.y, cross)
            painter.drawLine(g_EndGrabX, grabRect.bottom(), g_EndGrabX, cast() g_ScreenHeight, cross)
            painter.drawLine(0, g_EndGrabY, grabRect.x, g_EndGrabY, cross)
            painter.drawLine(grabRect.right(), g_EndGrabY, cast() g_ScreenWidth, g_EndGrabY, cross)
        }

        // Dimensions
        if grabRect.width > 0 and grabRect.height > 0
        {
            let fontR = captmeFont(.getFont().regular)
            let str   = Format.toString("% x %", grabRect.width, grabRect.height)
            var xx    = grabRect.x + 4
            var yy    = grabRect.y - fontR.height - 8
            if xx < 0 or yy < 0
            {
                xx = grabRect.x + 5
                yy = grabRect.y + 5
            }

            let m = Painter.measureString(str, fontR)
            painter.fillRoundRect({xx - 4, yy - 4, m.width + 8, fontR.height + 8}, 2, 2, col)

            painter.drawString(xx, yy, str, fontR, Argb.White)
        }
    }
}
