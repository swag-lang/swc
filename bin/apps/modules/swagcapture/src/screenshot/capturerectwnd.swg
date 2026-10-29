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

// The area overlay of the charter: the chosen zone at full brightness with a 1 px Voltage edge, its
// size in a mono chip, a pixel loupe with a Voltage crosshair, the capture modes as text tabs on a
// floating bar, and the keys at the foot.
const AreaChipPadding  = 8.0      // Air inside the size chip and the loupe reading.
const AreaChipGap      = 6.0      // Air between the size chip and the zone.
const AreaLoupeRadius  = 60.0     // Radius of the pixel loupe.
const AreaLoupePixels  = 21.0     // Desktop pixels across the loupe; odd, so one sits in the middle.
const AreaLoupeOffset  = 28.0     // Distance between the pointer and the loupe.
const AreaBarTop       = 24.0     // Air between the top of the screen and the mode bar.
const AreaBarHeight    = 34.0     // Height of the mode bar.
const AreaBarPadding   = 16.0     // Air inside the mode bar, and between two of its tabs.
const AreaTabUnderline = 2.0      // Weight of the Arc underline of the mode in use.
const AreaBarSeparatorGap    = 12.0     // Air around the hairline between the modes and how the screen is read.
const AreaBarSeparatorHeight = 16.0     // Height of that hairline.
const AreaChevronSize        = 8.0      // Width of the chevron saying the delay opens a list.
const AreaChevronGap         = 6.0      // Air between the delay and its chevron.

// The modes the bar of the area overlay offers, in their order.
const AreaModes = [CaptureMode.Area, CaptureMode.ActiveWindow, CaptureMode.FullScreen, CaptureMode.LastArea]

// The delays, in seconds, the bar of the area overlay offers before the screen is read.
const AreaDelays = [0, 3, 5, 10]

// Returns the words of the delay before the screen is read, on the bar of the area overlay.
func areaDelayName(delay: s32)->String
{
    let value = delay ? Format.toString(appStrings().ui_DelaySeconds, delay) : String.from(appStrings().ui_DelayNone)
    return Format.toString(appStrings().ui_Delay, value)
}

// Returns the word of a capture mode on the bar of the area overlay.
func areaModeName(mode: CaptureMode)->string
{
    switch mode
    {
    case .ActiveWindow: return appStrings().ui_ModeActiveWindow
    case .FullScreen:   return appStrings().ui_ModeFullScreen
    case .LastArea:     return appStrings().ui_ModeLastArea
    }

    return appStrings().ui_ModeArea
}

// A mode the reader chose on the bar of the area overlay, which the capture starts once the
// overlay has closed.
var g_SwitchCaptureMode: bool
var g_SwitchCaptureTo:   CaptureMode

// The overlay over the frozen desktop where the user drags the area to capture.
struct CaptureRectWnd
{
    using wnd: Wnd

    late main:     *MainWnd
    late hintLine: *HintLine
    startGrab:     bool
    cancelGrab:    bool
    tryStartGrab:  bool
    autoGrab:      bool
    lerpGrab:      Math.Rectangle
    clickStartPos: Math.Point

    // Where the pointer is, in logical units, for the loupe.
    pointer: Math.Point

    // The bar of the modes and the tab of each mode, then the delay and the cursor, from the
    // latest paint.
    barRect:    Math.Rectangle
    modeTabs:   Array'Math.Rectangle
    delayRect:  Math.Rectangle
    cursorRect: Math.Rectangle
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
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind == .Pressed and evt.key == .Escape do
            g_Exit = true

        // Enter takes the zone on screen, as a click without a drag does.
        if evt.kind == .Pressed and evt.key == .Enter and not getGrabRect().isEmpty()
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

        // The bar of the modes takes its own clicks: a mode other than the area closes the
        // overlay and starts that capture instead.
        if .barRect.contains(evt.surfacePos) and not .startGrab
        {
            if evt.kind == .Pressed and evt.button == .Left
            {
                let index = .modeAt(evt.surfacePos)
                if index < AreaModes.count and AreaModes[index] != .Area
                {
                    g_SwitchCaptureMode = true
                    g_SwitchCaptureTo   = AreaModes[index]
                    g_Exit              = true
                }
                elif .delayRect.contains(evt.surfacePos)
                {
                    .pickDelay()
                }
                elif .cursorRect.contains(evt.surfacePos)
                {
                    // The screen was read before the overlay came: it is read again, with or
                    // without the cursor.
                    .main.captureOptions.captureCursor = not .main.captureOptions.captureCursor
                    .restartArea()
                }
            }

            .invalidate()
            return
        }

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
                // A click without a drag accepts the auto-detected rectangle.
                g_GrabDone = true
                g_Exit     = true
            }
            elif .startGrab
            {
                // Resolve which window owns the manually selected rectangle.
                let rect       = getGrabRect()
                let screenRect = Math.Rectangle{g_DesktopX + rect.x, g_DesktopY + rect.y, rect.width, rect.height}
                g_CaptureWindow = getCaptureWindowForRect(unwrap .surface, screenRect)
                g_GrabDone      = true
                g_Exit          = true
            }

        case .Move where .tryStartGrab:
            g_EndGrabX = physPosX
            g_EndGrabY = physPosY

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
        .paintLoupe(painter)
        .paintModeBar(painter)
    }
}

impl CaptureRectWnd
{
    // Returns the mode tab under `pos`, in logical units, or `U64.Max`.
    // Creates the keys at the foot of the overlay. They stand over the frozen screen, which can be
    // as busy as any picture, so they take the floating ground.
    mtd createHintLine()
    {
        with .hintLine = HintLine.create(me)
        {
            .setGrounded(true)
            .addHint(Gui.strings().key_Enter, appStrings().hint_Capture)
            .addHint(Gui.strings().key_Escape, appStrings().hint_Cancel)
        }
    }

    // Closes the overlay and starts the area capture again, which reads the screen anew.
    mtd restartArea()
    {
        g_SwitchCaptureMode = true
        g_SwitchCaptureTo   = .Area
        g_Exit              = true
    }

    // Lists the delays under the delay of the bar. A delay waits before the screen is read, so
    // picking one closes the overlay and reads the screen again once it has elapsed.
    mtd pickDelay()
    {
        with let menu = MenuCtrl.createPopup(me)
        {
            for delay in AreaDelays do
                .addItem(areaDelayName(delay), Format.toString("%", delay))
        }

        .releaseMouse()
        let result = menu.doModal(Math.Point{.delayRect.x, .barRect.bottom()}, autoDestroy: true)
        .captureMouse()
        if not result do
            return

        let delay = catch StrConv.parseS32(result)
        .main.captureOptions.delay = delay.value
        if delay.value do
            .restartArea()
        .invalidate()
    }

    mtd modeAt(pos: Math.Point)->u64
    {
        for rect, i in .modeTabs where rect.contains(pos) do
            return i
        return Swag.U64.Max
    }

    // Writes the size of the zone, in physical desktop pixels — the size of the captured image —
    // in a mono chip standing on the top edge of the zone, or inside it when the screen has no
    // room above.
    mtd paintSizeChip(painter: *Painter, grabRect, dstGrab: Math.Rectangle)
    {
        if grabRect.width <= 0 or grabRect.height <= 0 do
            return

        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let font    = .theme().createDefaultFontFs(metrics.defaultFontSize - 1)
        let text    = Format.toString("% × %", grabRect.width, grabRect.height)
        let width   = Painter.measureString(text, font).width + 2 * AreaChipPadding
        let height  = font.height + AreaChipPadding

        var chip = Math.Rectangle{dstGrab.x, dstGrab.y - height - AreaChipGap, width, height}
        if chip.y < 0 do
            chip.y = dstGrab.y + AreaChipGap
        painter.fillRoundRect(chip, metrics.corner_Chip, metrics.corner_Chip, colors.surface)
        painter.drawString(chip.x + AreaChipPadding, font.opticalLineTop(chip.vertCenter()), text, font, colors.text)
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

    // Draws the modes as text tabs on a floating bar at the top of the screen, the area — the
    // mode in use — in the text ink over an Arc underline.
    mtd paintModeBar(painter: *Painter)
    {
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let font    = .theme().createDefaultFont(metrics.defaultFontSize - 1)     // A step under the body, as the picture.
        let screen  = .clientRect()

        let delayText  = areaDelayName(cast(s32, .main.captureOptions.delay))
        let cursorText = appStrings().ui_Cursor
        let chevron    = AreaChevronSize + AreaChevronGap
        let delayW     = Painter.measureString(delayText, font).width + chevron
        let cursorW    = Painter.measureString(cursorText, font).width

        var width = AreaBarPadding
        for mode in AreaModes do
            width += Painter.measureString(areaModeName(mode), font).width + AreaBarPadding
        width += AreaBarSeparatorGap + delayW + AreaBarPadding + cursorW + AreaBarPadding

        .barRect = Math.Rectangle{Math.round(screen.horzCenter() - width * 0.5), AreaBarTop, Math.ceil(width), AreaBarHeight}
        painter.setParams(.Antialiased)
        .theme().drawFloatingShadow(painter, .barRect, metrics.corner_Floating)
        painter.fillRoundRect(.barRect, metrics.corner_Floating, metrics.corner_Floating, colors.surface)
        painter.drawRoundRect(.barRect, metrics.corner_Floating, metrics.corner_Floating, colors.line, metrics.separator_HairlineSize)

        .modeTabs.clear()
        var x = .barRect.x + AreaBarPadding
        for mode in AreaModes
        {
            let name   = areaModeName(mode)
            let w      = Painter.measureString(name, font).width
            let active = mode == .Area
            let hot    = Math.Rectangle{x - AreaBarPadding * 0.5, .barRect.y, w + AreaBarPadding, .barRect.height}
            .modeTabs.add(hot)

            let ink = active or hot.contains(.pointer) ? colors.text : colors.softText
            painter.drawString(x, font.opticalLineTop(.barRect.vertCenter()), name, font, ink)
            if active do
                painter.fillRect(Math.Rectangle{x, .barRect.bottom() - 6, w, AreaTabUnderline}, colors.arc)
            x += w + AreaBarPadding
        }

        // A hairline, then how the screen is read: after a delay, with the cursor or not.
        let lineX = Math.round(x - AreaBarPadding * 0.5 + AreaBarSeparatorGap * 0.5)
        painter.fillRect(Math.Rectangle{lineX, .barRect.vertCenter() - AreaBarSeparatorHeight * 0.5, metrics.separator_HairlineSize, AreaBarSeparatorHeight}, colors.line)
        x += AreaBarSeparatorGap

        .delayRect = Math.Rectangle{x - AreaBarPadding * 0.5, .barRect.y, delayW + AreaBarPadding, .barRect.height}
        let delayInk = .delayRect.contains(.pointer) ? colors.text : colors.softText
        painter.drawString(x, font.opticalLineTop(.barRect.vertCenter()), delayText, font, delayInk)
        let cx = x + delayW - AreaChevronSize * 0.5
        let cy = .barRect.vertCenter()
        painter.drawLine(cx - AreaChevronSize * 0.5, cy - AreaChevronSize * 0.25, cx, cy + AreaChevronSize * 0.25, colors.faintText, 1.5)
        painter.drawLine(cx, cy + AreaChevronSize * 0.25, cx + AreaChevronSize * 0.5, cy - AreaChevronSize * 0.25, colors.faintText, 1.5)
        x += delayW + AreaBarPadding

        // The cursor is a switch: in the text ink over the Arc underline when it is read too.
        let cursorOn = .main.captureOptions.captureCursor
        .cursorRect = Math.Rectangle{x - AreaBarPadding * 0.5, .barRect.y, cursorW + AreaBarPadding, .barRect.height}
        let cursorInk = cursorOn or .cursorRect.contains(.pointer) ? colors.text : colors.softText
        painter.drawString(x, font.opticalLineTop(.barRect.vertCenter()), cursorText, font, cursorInk)
        if cursorOn do
            painter.fillRect(Math.Rectangle{x, .barRect.bottom() - 6, cursorW, AreaTabUnderline}, colors.arc)
    }
}
