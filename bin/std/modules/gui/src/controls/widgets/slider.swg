#global public

using Core, Pixel

// Configures linear-slider behavior and presentation.
#[Swag.EnumFlags]
enum SliderFlags
{
    None = 0       // No flags are enabled.
    Range          // Displays independent lower and upper thumbs.
    HilightBar     // Highlights the selected portion of the track.
    Vertical       // Lays out the track from top to bottom.
    Integer        // Snaps values to integers when no explicit step is configured.
    ShowSteps      // Draws explicit step markers when a step is configured.
}

// Provides a linear single-value or range slider.
struct Slider
{
    public
    {
        using wnd: Wnd     // Embedded wnd state.

        flags = SliderFlags.HilightBar               // Active behavior and presentation flags.
        sigStartChange: SigArray'func||(*Slider)     // Emitted when a user-style change transaction starts.
        sigChanged:     SigArray'func||(*Slider)     // Emitted after either value changes.
        sigEndChange:   SigArray'func||(*Slider)     // Emitted when a user-style change transaction ends.
    }

    // Drag and hover state of the two markers, and the color animations that follow it. The
    // mouse and keyboard events maintain all of it; connect to the signals to react to a change.
    lowerRatio: f32         // Lower value normalized to the closed range 0 through 1.
    upperRatio: f32 = 1     // Upper value normalized to the closed range 0 through 1.
    min:        f32         // Inclusive value-space minimum.
    max:        f32 = 1     // Inclusive value-space maximum.
    steps:      f32         // Configured step normalized to the value range.

    isMoving:       bool     // Whether a drag gesture is in progress.
    isLowerPressed: bool     // Whether the first marker is held down.
    isUpperPressed: bool     // Whether the second marker is held down.
    isLowerHot:     bool     // Whether the mouse is over the first marker.
    isUpperHot:     bool     // Whether the mouse is over the second marker.
    hasLowerValue:  bool     // Whether the first value was established.
    hasUpperValue:  bool     // Whether the second value was established.
    correcMoving:   f32      // Grab offset inside the marker, kept for the drag.

    lowerMarkerAnimation: BlendColor     // Color animation of the first marker.
    upperMarkerAnimation: BlendColor     // Color animation of the second marker.
    lowerStepAnimation:   BlendColor     // Color animation of the first step indicator.
    upperStepAnimation:   BlendColor     // Color animation of the second step indicator.
}

impl IWnd for Slider
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let bc      = evt.paintContext
        let theme   = .theme()
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let rects   = .themeRects()

        var colorBkLeft:   Color
        var colorBkMiddle: Color
        var colorBkRight:  Color
        var colorMark1:    Color
        var colorMark2:    Color

        if bc.isDisabled
        {
            colorBkLeft   = colors.slider_DisabledBk
            colorBkMiddle = colors.slider_DisabledBk
            colorBkRight  = colors.slider_DisabledBk
            if .flags.has(.HilightBar)
            {
                if .flags.has(.Range) do
                    colorBkMiddle = colors.slider_DisabledHilightBk
                else do
                    colorBkLeft = colors.slider_DisabledHilightBk
            }

            colorMark1 = colors.slider_DisabledMark
            colorMark2 = colors.slider_DisabledMark
        }
        else
        {
            colorBkRight = colors.slider_BkRight
            if !.flags.has(.Range) and .flags.has(.HilightBar) do
                colorBkLeft = colors.slider_HilightBk
            else do
                colorBkLeft = colors.slider_BkLeft
            if .flags.has(.Range) and .flags.has(.HilightBar) do
                colorBkMiddle = colors.slider_HilightBk
            else do
                colorBkMiddle = colors.slider_BkMiddle

            if .isLowerPressed do
                colorMark1 = colors.slider_PressedMark
            elif .isLowerHot do
                colorMark1 = colors.slider_HotMark
            else do
                colorMark1 = colors.slider_Mark

            if .isUpperPressed do
                colorMark2 = colors.slider_PressedMark
            elif .isUpperHot do
                colorMark2 = colors.slider_HotMark
            else do
                colorMark2 = colors.slider_Mark
        }

        // Pos box
        let posBox1 = .firstThumbRect()
        let posBox2 = .secondThumbRect()

        let isVertical = .flags.has(.Vertical)
        let trackRect  = .trackRect()

        // Bar left
        var left = trackRect
        if isVertical
        {
            left.height = (trackRect.height * .lowerRatio)
            theme.drawSubRect(bc.painter, left, &rects.slider_BkLeftVert, colorBkLeft)
        }
        else
        {
            left.width = (trackRect.width * .lowerRatio)
            theme.drawSubRect(bc.painter, left, &rects.slider_BkLeft, colorBkLeft)
        }

        // Bar right
        let valueRight = .flags.has(.Range) ? .upperRatio : .lowerRatio
        var right      = trackRect
        if isVertical
        {
            right.y      += (trackRect.height * valueRight)
            right.height -= (trackRect.height * valueRight)
            theme.drawSubRect(bc.painter, right, &rects.slider_BkRightVert, colorBkRight)
        }
        else
        {
            right.x     += (trackRect.width * valueRight)
            right.width -= (trackRect.width * valueRight)
            theme.drawSubRect(bc.painter, right, &rects.slider_BkRight, colorBkRight)
        }

        // Bar middle
        if .flags.has(.Range)
        {
            var middle = trackRect
            if isVertical
            {
                middle.y = left.bottom()
                middle.setBottom(right.y)
                theme.drawSubRect(bc.painter, middle, &rects.slider_BkMiddleVert, colorBkMiddle)
            }
            else
            {
                middle.x = left.right()
                middle.setRight(right.x)
                theme.drawSubRect(bc.painter, middle, &rects.slider_BkMiddle, colorBkMiddle)
            }
        }

        // Display steps
        if .steps > 0 and .flags.has(.ShowSteps)
        {
            if .isLowerHot or .isUpperHot or .isMoving
            {
                .lowerStepAnimation.apply(me, colors.slider_HotStepBk)
                .upperStepAnimation.apply(me, colors.slider_HotStepBk)
            }
            else
            {
                .lowerStepAnimation.apply(me, colors.slider_StepBk)
                .upperStepAnimation.apply(me, colors.slider_HilightStepBk)
            }

            for var x = 0'f32; x < 1 + .steps; x += .steps
            {
                let posStep = .thumbRectAt(x, metrics.slider_StepSize)

                var colorStep: Color
                if x <= .lowerRatio and .flags.has(.HilightBar) do
                    colorStep = .upperStepAnimation.cur()
                elif x >= .lowerRatio and x <= .upperRatio and .flags.has(.HilightBar) and .flags.has(.Range) do
                    colorStep = .upperStepAnimation.cur()
                else do
                    colorStep = .lowerStepAnimation.cur()
                theme.drawSubRect(bc.painter, posStep, &rects.slider_Step, colorStep)
            }
        }

        // Box value1
        .lowerMarkerAnimation.apply(me, colorMark1)
        theme.drawSubRect(bc.painter, posBox1, &rects.slider_Mark, .lowerMarkerAnimation.cur())

        // Box value2
        if .flags.has(.Range)
        {
            .upperMarkerAnimation.apply(me, colorMark2)
            theme.drawSubRect(bc.painter, posBox2, &rects.slider_Mark, .upperMarkerAnimation.cur())
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let pos        = .surfaceToLocal(evt.surfacePos)
        let isVertical = .flags.has(.Vertical)

        switch evt.kind
        {
        case .Wheel:
            evt.accepted = false
            return

        case .Leave:
            .isLowerHot, .isUpperHot = false
            .invalidate()

        case .Move:
            if !.isMoving
            {
                .hitTest(evt.surfacePos)
                break
            }

            let clientRect = .offsetClientRect()
            var f: f32
            if isVertical
            {
                let diff = (pos.y - .correcMoving) - clientRect.y
                f = diff / clientRect.height
            }
            else
            {
                let diff = (pos.x - .correcMoving) - clientRect.x
                f = diff / clientRect.width
            }

            if .isLowerPressed do
                .setLowerRatio(f)
            elif .isUpperPressed do
                .setUpperRatio(f)
            .invalidate()

        case .Pressed:
            if evt.button == .Left
            {
                .isMoving = true
                .startChange()
                if .isLowerHot
                {
                    .isLowerPressed = true
                    let posBox = .firstThumbRect()
                    if isVertical do
                        .correcMoving = pos.y - posBox.vertCenter()
                    else do
                        .correcMoving = pos.x - posBox.horzCenter()
                }
                elif .isUpperHot
                {
                    .isUpperPressed = true
                    let posBox = .secondThumbRect()
                    if isVertical do
                        .correcMoving = pos.y - posBox.vertCenter()
                    else do
                        .correcMoving = pos.x - posBox.horzCenter()
                }
                elif !.flags.has(.Range)
                {
                    .correcMoving   = 0
                    .isLowerPressed = true
                    let clientRect = .offsetClientRect()
                    if isVertical
                    {
                        let diff = pos.y - clientRect.y
                        .setLowerRatio(diff / clientRect.height)
                    }
                    else
                    {
                        let diff = pos.x - clientRect.x
                        .setLowerRatio(diff / clientRect.width)
                    }
                }
                else
                {
                    .correcMoving = 0
                    let clientRect = .offsetClientRect()
                    var f: f32
                    if isVertical
                    {
                        let diff = pos.y - clientRect.y
                        f = diff / clientRect.height
                    }
                    else
                    {
                        let diff = pos.x - clientRect.x
                        f = diff / clientRect.width
                    }

                    let m = (.lowerRatio + .upperRatio) * 0.5
                    if f <= m
                    {
                        .isLowerPressed = true
                        .setLowerRatio(f)
                    }
                    else
                    {
                        .isUpperPressed = true
                        .setUpperRatio(f)
                    }
                }

                .captureMouse()
                .invalidate()
            }

        case .Released:
            if .isMoving and evt.button == .Left
            {
                .releaseMouse()
                .isLowerPressed, .isUpperPressed, .isMoving = false
                .hitTest(evt.surfacePos)
                .invalidate()
                .endChange()
            }
        }
    }

    // Keyboard control of the focused slider. Left/Down decrease and Right/Up
    // increase the (left) value by one step; Home/End jump to min/max; Page keys
    // move by a larger amount. The step is the configured step, one integer unit
    // for an integer slider, or 5% of the range otherwise.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed do
            return

        let bigBy = Math.max(.keyStep() * 5, 0.1)

        switch evt.key
        {
        case .Left, .Down: .stepBy(-1)
        case .Right, .Up:  .stepBy(1)
        case .PageDown:    .stepActiveValue(-bigBy)
        case .PageUp:      .stepActiveValue(bigBy)
        case .Home:        .setActiveRatio(0)
        case .End:         .setActiveRatio(1)
        default:           return
        }

        evt.accepted = true
    }
}

private impl Slider
{
    // Normalized step used by keyboard control: the configured step, one integer
    // unit, or 5% of the range as a fallback.
    mtd keyStep()->f32
    {
        if .steps > 0 do
            return .steps
        if .flags.has(.Integer) and .max > .min do
            return 1.0 / (.max - .min)
        return 0.05
    }

    // Adjust the active value by a normalized delta. For a range slider the right
    // mark is moved, mirroring the convention that the rightmost mark is the one a
    // user most often tweaks; otherwise the single value is moved.
    mtd stepActiveValue(delta: f32)
    {
        .startChange()
        if .flags.has(.Range) do
            .setUpperRatio(.upperRatio + delta)
        else do
            .setLowerRatio(.lowerRatio + delta)
        .endChange()
    }

    // Maps a normalized track position to the active value and optionally notifies listeners.
    mtd setActiveRatio(f: f32)
    {
        .startChange()
        if .flags.has(.Range) do
            .setUpperRatio(f)
        else do
            .setLowerRatio(f)
        .endChange()
    }

    mtd clamp(f: f32)->f32
    {
        let normalized = Math.clamp(f, 0, 1)
        if .steps > 0
        {
            let r = cast(s32) ((normalized / .steps) + 0.5)
            return Math.clamp(r * .steps, 0, 1)
        }

        if .flags.has(.Integer)
        {
            let val = Math.round((.min + (.max - .min) * normalized))
            return (val - .min) / (.max - .min)
        }

        return normalized
    }

    mtd setLowerRatio(f: f32)
    {
        var fc = .clamp(f)
        if .flags.has(.Range) do
            fc = Math.min(fc, .upperRatio)
        if fc == .lowerRatio and .hasLowerValue do
            return
        .hasLowerValue = true
        .lowerRatio    = fc
        .sigChanged.call(me)
        .invalidate()
    }

    mtd setUpperRatio(f: f32)
    {
        var fc = .clamp(f)
        if .flags.has(.Range) do
            fc = Math.max(fc, .lowerRatio)
        if fc == .upperRatio and .hasUpperValue do
            return
        .hasUpperValue = true
        .upperRatio    = fc
        .sigChanged.call(me)
        .invalidate()
    }

    mtd hitTest(surfacePos: Math.Point)
    {
        let pos = .surfaceToLocal(surfacePos)
        if .isLowerHot or .isUpperHot
        {
            .invalidate()
            .isLowerHot, .isUpperHot = false
        }

        if .flags.has(.Range)
        {
            let rect = .secondThumbRect()
            if rect.contains(pos)
            {
                .isUpperHot = true
                .invalidate()
                return
            }
        }

        let rect = .firstThumbRect()
        if rect.contains(pos)
        {
            .isLowerHot = true
            .invalidate()
        }
    }

    mtd offsetClientRect()->Math.Rectangle
    {
        var result: retval = .clientRect()
        let boxSize        = .themeMetrics().slider_BoxSize

        if .flags.has(.Vertical)
        {
            result.y      += (boxSize * 0.5)
            result.height -= boxSize
        }
        else
        {
            result.x     += (boxSize * 0.5)
            result.width -= boxSize
        }

        return result
    }

    mtd trackRect()->Math.Rectangle
    {
        var result: retval = .offsetClientRect()
        let trackSize      = .themeMetrics().slider_TrackSize

        if .flags.has(.Vertical)
        {
            result.x     = result.horzCenter() - (trackSize * 0.5)
            result.width = trackSize
        }
        else
        {
            result.y      = result.vertCenter() - (trackSize * 0.5)
            result.height = trackSize
        }

        return result
    }

    mtd thumbRectAt(val, size: f32)->Math.Rectangle
    {
        var result: retval = .offsetClientRect()

        if .flags.has(.Vertical)
        {
            result.y += result.height * val
            result.y -= (size * 0.5)
            result.x = result.horzCenter() - (size * 0.5)
        }
        else
        {
            result.x += result.width * val
            result.x -= (size * 0.5)
            result.y = result.vertCenter() - (size * 0.5)
        }

        result.width, result.height = size
        return result
    }

    mtd firstThumbRect()->Math.Rectangle
    {
        return .thumbRectAt(.lowerRatio, .themeMetrics().slider_BoxSize)
    }

    mtd secondThumbRect()->Math.Rectangle
    {
        return .thumbRectAt(.upperRatio, .themeMetrics().slider_BoxSize)
    }

    mtd startChange()
    {
        .sigStartChange.call(me)
    }

    mtd endChange()
    {
        .sigEndChange.call(me)
    }
}

impl Slider
{
    // Move the active value by one keyboard step (dir = +1/-1). Public so a host
    // (e.g. the property grid) can drive the slider from its own key handling.
    mtd stepBy(dir: s32)
    {
        let s = .keyStep()
        .stepActiveValue(dir > 0 ? s : -s)
    }

    // Returns the single value, or the lower value in range mode.
    mtd const value()->f32 => .lowerValue()

    // Returns the lower value in configured value-space units.
    mtd const lowerValue()->f32 => .min + (.max - .min) * .lowerRatio

    // Returns the upper value in configured value-space units.
    mtd const upperValue()->f32 => .min + (.max - .min) * .upperRatio

    // Returns the inclusive minimum accepted by the slider.
    mtd const minimum()->f32 => .min

    // Returns the inclusive maximum accepted by the slider.
    mtd const maximum()->f32 => .max

    // Returns the configured value-space step, or zero for continuous values.
    mtd const step()->f32 => .steps * (.max - .min)

    // Sets the single value, emitting start/change/end signals as one transaction.
    mtd setValue(f: f32)
    {
        .setLowerValue(f)
    }

    // Sets the single value without emitting start/end transaction signals.
    //
    // [sigChanged] is still emitted when the effective value changes.
    mtd setValueWithoutGesture(f: f32)
    {
        .setLowerRatio((f - .min) / (.max - .min))
    }

    // Sets the lower value and emits one start/change/end transaction.
    mtd setLowerValue(f: f32)
    {
        .startChange()
        .setValueWithoutGesture(f)
        .endChange()
    }

    // Sets the upper value and emits one start/change/end transaction.
    mtd setUpperValue(f: f32)
    {
        .startChange()
        .setUpperRatio((f - .min) / (.max - .min))
        .endChange()
    }

    // Configures inclusive bounds and an optional value-space step.
    func setBounds(me, min, max: f32, steps: f32 = 0)
    {
        Debug.assert(min < max)
        Debug.assert(steps >= 0 and steps < (max - min))
        .min = min
        .max = max
        if steps > 0 do
            .steps = steps / (max - min)     // Convert to normalized step size
        else do
            .steps = 0
        .invalidate()
    }

    // Sets both range endpoints and emits at most one change notification.
    mtd setRange(lower, upper: f32)
    {
        Debug.assert(lower <= upper)
        Debug.assert(.flags.has(.Range))
        let diff     = .max - .min
        let newLower = .clamp((lower - .min) / diff)
        let newUpper = .clamp((upper - .min) / diff)
        Debug.assert(newLower <= newUpper)

        let changed = !.hasLowerValue or !.hasUpperValue or newLower != .lowerRatio or newUpper != .upperRatio
        .hasLowerValue, .hasUpperValue = true
        .lowerRatio = newLower
        .upperRatio = newUpper
        if changed
        {
            .startChange()
            .sigChanged.call(me)
            .invalidate()
            .endChange()
        }
    }

    // Creates a horizontal slider, optionally configured for ranges or vertical layout.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null, range = false, vertical = false)->*Slider
    {
        Debug.assert(parent != null)
        var pos = position

        if pos.height == 0
        {
            if vertical do
                pos.height = parent.themeMetrics().slider_Width
            else do
                pos.height = parent.themeMetrics().slider_Height
        }

        if pos.width == 0
        {
            if vertical do
                pos.width = parent.themeMetrics().slider_Height
            else do
                pos.width = parent.themeMetrics().slider_Width
        }

        let res = Wnd.create'Slider(parent, null, pos, id)
        res.focusPolicy = .Tab
        if range do
            res.flags.add(.Range)
        if vertical do
            res.flags.add(.Vertical)
        return res
    }
}
