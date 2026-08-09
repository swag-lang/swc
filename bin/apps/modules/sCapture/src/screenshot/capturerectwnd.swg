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

// The selection marks: four corner brackets whose outer corner is cut at 45 degrees, the
// mark's own vocabulary. They frame the region instead of outlining it, so the pixels
// about to be captured stay visible under the selection.
const BracketArm   = 26.0
const BracketThick = 3.0
const BracketCut   = 8.0
const BracketHalo  = 1.5     // Ink counter-form, so the accent reads on a white capture too.

// The readout badge sitting above the selection.
const BadgePad = 6.0
const BadgeGap = 6.0

// Paints one corner bracket. `dirX` and `dirY` are +1 or -1 and point from the corner
// toward the inside of the selection, so the same seven points serve all four corners.
func paintCornerBracket(painter: *Painter, x, y, dirX, dirY, arm, thick, cut: f32, color: Color)
{
    let armX   = arm * dirX
    let armY   = arm * dirY
    let thickX = thick * dirX
    let thickY = thick * dirY
    let cutX   = cut * dirX
    let cutY   = cut * dirY

    var path: LinePath
    path.start(x + armX, y)
    path.lineTo(x + cutX, y)
    path.lineTo(x, y + cutY)
    path.lineTo(x, y + armY)
    path.lineTo(x + thickX, y + armY)
    path.lineTo(x + thickX, y + thickY)
    path.lineTo(x + armX, y + thickY)
    path.close()
    painter.fillPolygon(&path, color)
}

// The four brackets of one selection, each backed by an ink counter-form. The overlay
// lies over whatever is on screen, and Voltage alone disappears on a white document —
// the chart forbids the accent on paper for exactly that reason.
func paintCornerBrackets(painter: *Painter, rect: Math.Rectangle, color, backColor: Color)
{
    #[Swag.Mixin]
    func corner(x, y, dx, dy: f32)
    {
        paintCornerBracket(painter, x - dx * BracketHalo, y - dy * BracketHalo, dx, dy, BracketArm + BracketHalo, BracketThick + 2 * BracketHalo, BracketCut, backColor)
        paintCornerBracket(painter, x, y, dx, dy, BracketArm, BracketThick, BracketCut, color)
    }

    corner(rect.x, rect.y, 1, 1)
    corner(rect.right(), rect.y, -1, 1)
    corner(rect.x, rect.bottom(), 1, -1)
    corner(rect.right(), rect.bottom(), -1, -1)
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
        let pt     = Input.mousePosition()
        let window = getCaptureWindowAtPos(.surface!, pt.x, pt.y)
        let r      = screenToDesktopRect(window.rect)
        if !r.isEmpty()
        {
            g_StartGrabX    = r.x
            g_StartGrabY    = r.y
            g_EndGrabX      = r.right()
            g_EndGrabY      = r.bottom()
            g_CaptureWindow = window.info
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
                let rect       = getGrabRect()
                let screenRect = Math.Rectangle{g_DesktopX + rect.x, g_DesktopY + rect.y, rect.width, rect.height}
                g_CaptureWindow = getCaptureWindowForRect(.surface!, screenRect)
                g_GrabDone      = true
                g_Exit          = true
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
        let k       = .deviceScale()
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

        let colors = .themeColors()
        let col    = colors.hilight

        // A hairline states where the edge is; the brackets say it is a selection. A
        // full accent rectangle would sit on top of the pixels being captured.
        painter.setParams(.Antialiased)
        painter.drawRect(dstGrab, colors.bk, 3)
        painter.drawRect(dstGrab, col, 1)

        if dstGrab.width >= 2 * BracketArm and dstGrab.height >= 2 * BracketArm do
            paintCornerBrackets(painter, dstGrab, col, colors.bk)

        // Crosshair guides - only in manual grab mode. The cursor sits on the dragged
        // corner, so split each line around the selection instead of running it along
        // (and hiding it behind) the rectangle border. The cross then meets the corner
        // and stays clearly visible over the dimmed background.
        if .main.captureOptions.drawCross and !.autoGrab
        {
            // Translucent: the cross has to guide the eye without cutting the image.
            let cross: Color = {255, 255, 255, 110}
            let endX         = g_EndGrabX / k
            let endY         = g_EndGrabY / k
            painter.drawLine(endX, 0, endX, dstGrab.y, cross)
            painter.drawLine(endX, dstGrab.bottom(), endX, cast(f32) g_ScreenHeight / k, cross)
            painter.drawLine(0, endY, dstGrab.x, endY, cross)
            painter.drawLine(dstGrab.right(), endY, cast(f32) g_ScreenWidth / k, endY, cross)
        }

        // The readout, in physical desktop pixels: that is the size of the captured
        // image, and the origin the user needs to reproduce the same frame later. Both
        // are machine data, so both are set in the fixed-width theme family.
        if grabRect.width > 0 and grabRect.height > 0
        {
            let fontR = .theme().res.fontDefaultFs.regular!
            let size  = Format.toString("%×%", grabRect.width, grabRect.height)
            let org   = Format.toString("+%,%", grabRect.x, grabRect.y)

            let mSize  = Painter.measureString(size, fontR)
            let mOrg   = Painter.measureString(org, fontR)
            let width  = Math.max(mSize.width, mOrg.width) + 2 * BadgePad
            let height = 2 * fontR.height + 2 * BadgePad

            var xx = dstGrab.x
            var yy = dstGrab.y - height - BadgeGap
            if xx < 0 or yy < 0
            {
                xx = dstGrab.x + BadgeGap
                yy = dstGrab.y + BadgeGap
            }

            painter.fillRect({xx, yy, width, height}, colors.bk)
            painter.drawString(xx + BadgePad, yy + BadgePad, size, fontR, col)
            painter.drawString(xx + BadgePad, yy + BadgePad + fontR.height, org, fontR, colors.label_TextLight)
        }
    }
}
