#global public

using Core, Pixel

// Configures circular-slider value behavior.
#[Swag.EnumFlags]
enum CircularFlags
{
    None = 0     // No flags are enabled.
    Range        // Displays independent lower and upper markers.
    Integer      // Snaps values to integers when no explicit step is configured.
}

// Selects how discrete positions are drawn around the track.
enum CircularStepForm
{
    None = 0     // Draws no step indicators.
    Dot          // Draws a dot at each indicated position.
    Tick         // Draws a radial tick at each indicated position.
}

// Selects how current values are marked on the track.
enum CircularMarkerForm
{
    None = 0     // Draws no value markers.
    Circle       // Draws a circular thumb centered on the track.
    Needle       // Draws a radial needle from the center.
}

// Provides a circular single-value or range slider.
struct Circular
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        flags:      CircularFlags                    // Active value-behavior flags.
        stepForm:   CircularStepForm   = .Tick       // Visual form of the step indicators.
        markerForm: CircularMarkerForm = .Circle     // Visual form of the value markers.

        startAngle: f32 = 0                       // Angle of the minimum value, in radians clockwise from the top.
        endAngle:   f32 = Math.ConstF32.TwoPi     // Angle of the maximum value, in radians clockwise from the top.

        tickCount:             u32 = 20     // Number of step indicators drawn around the track.
        tickInnerRadiusFactor: f32 = 2      // Distance from the track to the inner end of a step indicator, in logical units.
        tickOuterRadiusFactor: f32 = 6      // Distance from the track to the outer end of a step indicator, in logical units.
        circleGap:             f32 = 0      // Gap between two concentric track circles; zero draws a single circle.
        rangeColor:            Color        // Explicit range-arc color, or transparent for the theme color.

        sigStartChange: SigArray'func||(*Circular)     // Emitted when a user-style change transaction starts.
        sigChanged:     SigArray'func||(*Circular)     // Emitted after either value changes.
        sigEndChange:   SigArray'func||(*Circular)     // Emitted when a user-style change transaction ends.
    }

    lowerRatio: f32         // Lower value normalized to the closed range 0 through 1.
    upperRatio: f32 = 1     // Upper value normalized to the closed range 0 through 1.
    min:        f32         // Inclusive value-space minimum.
    max:        f32 = 1     // Inclusive value-space maximum.
    steps:      f32         // Configured step normalized to the value range.

    // Drag and hover state of the two markers. The mouse events maintain all of it.
    isMoving:       bool     // Whether a drag gesture is in progress.
    isLowerPressed: bool     // Whether the first marker is held down.
    isUpperPressed: bool     // Whether the second marker is held down.
    isLowerHot:     bool     // Whether the mouse is over the first marker.
    isUpperHot:     bool     // Whether the mouse is over the second marker.
    hasLowerValue:  bool     // Whether the first value was established.
    hasUpperValue:  bool     // Whether the second value was established.

    // Track geometry, computed by `updateGeometry`.
    radius:       f32     // Radius of the main circular track.
    centerX:      f32     // X coordinate of the track center.
    centerY:      f32     // Y coordinate of the track center.

    lowerMarkerAnimation: BlendColor     // Color animation of the first marker.
    upperMarkerAnimation: BlendColor     // Color animation of the second marker.
    aniStep: BlendColor                  // Color animation of the step indicators.
}

impl IWnd for Circular
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let bc     = evt.paintContext
        let colors = .themeColors()

        var colorBk:     Color
        var colorCircle: Color
        var colorMark1:  Color
        var colorMark2:  Color
        var colorStep:   Color

        if bc.isDisabled
        {
            colorBk     = colors.circular_DisabledBk
            colorCircle = colors.circular_DisabledCircle
            colorMark1  = colors.circular_DisabledMark
            colorMark2  = colors.circular_DisabledMark
            colorStep   = colors.circular_DisabledStep
        }
        else
        {
            colorBk     = colors.circular_Bk
            colorCircle = colors.circular_Circle
            colorStep   = colors.circular_Step

            if .isLowerPressed do
                colorMark1 = colors.circular_PressedMark
            elif .isLowerHot do
                colorMark1 = colors.circular_HotMark
            else do
                colorMark1 = colors.circular_Mark

            if .isUpperPressed do
                colorMark2 = colors.circular_PressedMark
            elif .isUpperHot do
                colorMark2 = colors.circular_HotMark
            else do
                colorMark2 = colors.circular_Mark
        }

        .updateGeometry()

        bc.painter.setAntialiased(true)

        // Draw range arc if enabled
        if .flags.has(.Range) do
            .drawRangeArc(bc.painter)

        // Draw circular track
        .drawCircularTrack(bc.painter, colorCircle)

        // Draw steps if enabled
        if .stepForm != .None and .tickCount > 0 do
            .drawSteps(bc.painter, colorStep)

        // Draw value1 marker
        .lowerMarkerAnimation.apply(me, colorMark1)
        .drawValueMarker(bc.painter, .lowerMarkerAnimation.cur(), .lowerRatio)

        // Draw value2 marker if range mode
        if .flags.has(.Range)
        {
            .upperMarkerAnimation.apply(me, colorMark2)
            .drawValueMarker(bc.painter, .upperMarkerAnimation.cur(), .upperRatio)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let pos = .surfaceToLocal(evt.surfacePos)
        .updateGeometry()

        switch evt.kind
        {
        case .Wheel:
            evt.accepted = false
            return

        case .Leave:
            .isLowerHot, .isUpperHot = false
            .invalidate()

        case .Move:
            if not .isMoving
            {
                .hitTest(evt.surfacePos)
                break
            }

            let angle = .angleAt(pos)
            let normalizedValue = .angleToValue(angle)

            if .isLowerPressed do
                .setLowerRatio(normalizedValue)
            elif .isUpperPressed do
                .setUpperRatio(normalizedValue)
            .invalidate()

        case .Pressed:
            if evt.button == .Left
            {
                .isMoving = true
                .startChange()

                let angle = .angleAt(pos)
                let normalizedValue = .angleToValue(angle)

                if .isLowerHot
                {
                    .isLowerPressed = true
                }
                elif .isUpperHot
                {
                    .isUpperPressed = true
                }
                elif not .flags.has(.Range)
                {
                    .isLowerPressed = true
                    .setLowerRatio(normalizedValue)
                }
                else
                {
                    // Determine which marker is closest
                    let m = (.lowerRatio + .upperRatio) * 0.5
                    if normalizedValue <= m
                    {
                        .isLowerPressed = true
                        .setLowerRatio(normalizedValue)
                    }
                    else
                    {
                        .isUpperPressed = true
                        .setUpperRatio(normalizedValue)
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
}

private impl Circular
{
    mtd updateGeometry()
    {
        let clientRect = .clientRect()
        .centerX = clientRect.x + clientRect.width * 0.5
        .centerY = clientRect.y + clientRect.height * 0.5
        .radius  = Math.min(clientRect.width, clientRect.height) * 0.5
        .radius  -= 2
        if .tickOuterRadiusFactor > 0 do
            .radius -= .tickOuterRadiusFactor
    }

    mtd angleToValue(angle: f32)->f32
    {
        let totalAngle      = .endAngle - .startAngle
        var normalizedAngle = angle

        // For partial arcs, we need to find the closest valid angle
        if normalizedAngle > totalAngle
        {
            // Determine which boundary is closer
            let distanceToEnd   = normalizedAngle - totalAngle
            let distanceToStart = (Math.ConstF32.TwoPi - normalizedAngle)

            // If we're closer to the start (going around the circle), snap to 0
            // Otherwise snap to the end
            if distanceToStart < distanceToEnd do
                normalizedAngle = 0
            else do
                normalizedAngle = totalAngle
        }

        if normalizedAngle < 0 do
            normalizedAngle = 0

        return normalizedAngle / totalAngle
    }

    mtd const valueToAngle(val: f32)->f32
    {
        let totalAngle = .endAngle - .startAngle
        return .startAngle + (val * totalAngle)
    }

    mtd angleAt(pos: Math.Point)->f32
    {
        let dx = pos.x - .centerX
        let dy = pos.y - .centerY

        // Use atan2(dx, -dy) to have 0° pointing up and 90° pointing right
        // -dy because Y axis is inverted (down = positive)
        var angle = Math.atan2(dx, -dy)

        // Normalize the angle according to our coordinate system
        angle = angle - .startAngle

        // Normalize to range [0, 2π]
        while angle < 0 do
            angle += Math.ConstF32.TwoPi
        while angle > Math.ConstF32.TwoPi do
            angle -= Math.ConstF32.TwoPi

        return angle
    }

    mtd positionAtAngle(angle: f32)->Math.Vector2
    {
        var result: retval

        // For 0° pointing up: x = sin(angle), y = -cos(angle)
        result.x = .centerX + Math.sin(angle) * .radius
        result.y = .centerY - Math.cos(angle) * .radius
        return result
    }

    // Range arc drawing
    mtd drawRangeArc(painter: *Painter)
    {
        let color    = .rangeColor.a ? .rangeColor : .themeColors().circular_RangeArc
        let penSize  = .circleGap ? .circleGap : 4.0
        let pen      = Pen.createSolid(color, penSize)
        let startArc = .valueToAngle(.lowerRatio)
        let endArc   = .valueToAngle(.upperRatio)
        painter.drawArc(.centerX, .centerY, .radius, startArc, endArc, pen)
    }

    // Main marker drawing dispatcher
    mtd drawValueMarker(painter: *Painter, color: Color, value: f32)
    {
        switch #complete .markerForm
        {
        case .None:   return
        case .Circle: .drawCircleMarker(painter, color, value)
        case .Needle: .drawNeedleMarker(painter, color, value)
        }
    }

    // Circle marker
    mtd drawCircleMarker(painter: *Painter, color: Color, value: f32)
    {
        let angle        = .valueToAngle(value)
        let pos          = .positionAtAngle(angle)
        let markerRadius = .themeMetrics().circular_MarkerSize

        let brush = Brush.createSolid(color)
        let pen   = Pen.createSolid(color, 1.5)

        // Draw filled circle with border
        painter.fillCircle(pos.x, pos.y, markerRadius, brush)
        painter.drawCircle(pos.x, pos.y, markerRadius, pen)
    }

    // Needle marker (line from center to current position)
    mtd drawNeedleMarker(painter: *Painter, color: Color, value: f32)
    {
        let angle     = .valueToAngle(value)
        let trackPos  = .positionAtAngle(angle)
        let centerPos = Math.Vector2{.centerX, .centerY}

        // Create gradient pen for nice visual effect
        let pen = Pen.createSolid(color, 2.5)

        // Draw needle line from center to track
        painter.drawLine(centerPos, trackPos, pen)

        // Draw small circle at center as pivot point
        let pivotRadius = 3.0
        let brush       = Brush.createSolid(color)
        painter.fillCircle(.centerX, .centerY, pivotRadius, brush)

        // Draw small circle at track position as tip
        let tipRadius = 2.0
        painter.fillCircle(trackPos.x, trackPos.y, tipRadius, brush)
    }

    // Main step drawing dispatcher
    mtd drawSteps(painter: *Painter, color: Color)
    {
        switch #complete .stepForm
        {
        case .None: return
        case .Dot:  .drawStepDots(painter, color)
        case .Tick: .drawStepTicks(painter, color)
        }
    }

    // Dots implementation
    mtd drawStepDots(painter: *Painter, color: Color)
    {
        if .tickCount <= 1 do
            return

        let totalAngle  = .endAngle - .startAngle
        let stepAngle   = totalAngle / cast(f32) (.tickCount - 1)
        let brush       = Brush.createSolid(color)
        let dotRadius   = (.tickOuterRadiusFactor - .tickInnerRadiusFactor) * 0.5
        let dotDistance = .radius + (.tickOuterRadiusFactor + .tickInnerRadiusFactor) * 0.5

        for i in .tickCount
        {
            let angle = .startAngle + stepAngle * cast(f32) i

            let pos = Math.Vector2{.centerX + Math.sin(angle) * dotDistance, .centerY - Math.cos(angle) * dotDistance}
            painter.fillCircle(pos.x, pos.y, dotRadius, brush)
        }
    }

    // Tick marks implementation
    mtd drawStepTicks(painter: *Painter, color: Color)
    {
        if .tickCount <= 1 do
            return

        let totalAngle = .endAngle - .startAngle
        let stepAngle  = totalAngle / cast(f32) (.tickCount - 1)
        let pen        = Pen.createSolid(color, 3.0)

        let innerRadius = .radius + .tickInnerRadiusFactor
        let outerRadius = .radius + .tickOuterRadiusFactor

        for i in .tickCount
        {
            let angle = .startAngle + stepAngle * cast(f32) i

            let innerPos = Math.Vector2{.centerX + Math.sin(angle) * innerRadius, .centerY - Math.cos(angle) * innerRadius}
            let outerPos = Math.Vector2{.centerX + Math.sin(angle) * outerRadius, .centerY - Math.cos(angle) * outerRadius}
            painter.drawLine(innerPos, outerPos, pen)
        }
    }

    mtd drawCircularTrack(painter: *Painter, color: Color)
    {
        let pen = Pen.createSolid(color, 2.0)
        painter.drawCircle(.centerX, .centerY, .radius - .circleGap * 0.5, pen)
        if .circleGap != 0 do
            painter.drawCircle(.centerX, .centerY, .radius + .circleGap * 0.5, pen)
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
        .updateGeometry()

        if .isLowerHot or .isUpperHot
        {
            .invalidate()
            .isLowerHot, .isUpperHot = false
        }

        // Check value2 first if range mode (like in horizontal slider)
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

        // Check value1
        let rect = .firstThumbRect()
        if rect.contains(pos)
        {
            .isLowerHot = true
            .invalidate()
        }
    }

    mtd thumbRectAt(val, size: f32)->Math.Rectangle
    {
        .updateGeometry()

        let angle = .valueToAngle(val)
        let pos   = .positionAtAngle(angle)
        var result: retval
        result.x      = pos.x - size
        result.y      = pos.y - size
        result.width  = size * 2
        result.height = size * 2
        return result
    }

    mtd firstThumbRect()->Math.Rectangle => .thumbRectAt(.lowerRatio, .themeMetrics().circular_MarkerSize)

    mtd secondThumbRect()->Math.Rectangle => .thumbRectAt(.upperRatio, .themeMetrics().circular_MarkerSize)

    mtd startChange()
    {
        .sigStartChange.call(me)
    }

    mtd endChange()
    {
        .sigEndChange.call(me)
    }
}

impl Circular
{
    // Returns the single value, or the lower value in range mode.
    mtd const value()->f32 => .lowerValue()

    // Returns the lower value in configured value-space units.
    mtd const lowerValue()->f32 => .min + (.max - .min) * .lowerRatio

    // Returns the upper value in configured value-space units.
    mtd const upperValue()->f32 => .min + (.max - .min) * .upperRatio

    // Returns the inclusive minimum accepted by the control.
    mtd const minimum()->f32 => .min

    // Returns the inclusive maximum accepted by the control.
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
    // [[Gui.Circular.sigChanged]] is still emitted when the effective value changes.
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

    // Sets both range endpoints and emits at most one change notification.
    mtd setRange(lower, upper: f32)
    {
        Swag.assert(lower <= upper)
        Swag.assert(.flags.has(.Range))
        let diff     = .max - .min
        let newLower = .clamp((lower - .min) / diff)
        let newUpper = .clamp((upper - .min) / diff)
        Swag.assert(newLower <= newUpper)

        let changed = not .hasLowerValue or not .hasUpperValue or newLower != .lowerRatio or newUpper != .upperRatio
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

    // Configures inclusive bounds and an optional value-space step.
    //
    // `steps` may span the complete range, which creates a two-value control at the bounds. The
    // current values keep their relative positions on the track, so configure the bounds before
    // setting values.
    mtd setBounds(min, max: f32, steps: f32 = 0)
    {
        Swag.assert(min < max)
        Swag.assert(steps >= 0 and steps <= (max - min))
        .min = min
        .max = max
        if steps > 0 do
            .steps = steps / (max - min)     // Convert to normalized step size
        else do
            .steps = 0
        .invalidate()
    }

    // Configures the clockwise angular span used for the value range.
    func setAngleRange(me, startAngle, endAngle: Math.Angle)
    {
        Swag.assert(endAngle.radians > startAngle.radians)
        Swag.assert((endAngle.radians - startAngle.radians) <= Math.ConstF32.TwoPi)
        .startAngle = startAngle.radians
        .endAngle   = endAngle.radians
        .invalidate()
    }

    // Changes the visual form of step indicators.
    mtd setStepForm(form: CircularStepForm)
    {
        if .stepForm == form do
            return
        .stepForm = form
        .invalidate()
    }

    // Changes the number of dot or tick step indicators.
    mtd setStepCount(count: u32)
    {
        if .tickCount == count do
            return
        .tickCount = count
        .invalidate()
    }

    // Creates a circular slider, optionally with independent range markers.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: WndId? = null, range = false)->*Circular
    {
        Swag.assert(parent != null)
        var pos = position

        if pos.width == 0 do
            pos.width = parent.themeMetrics().circular_Size
        if pos.height == 0 do
            pos.height = pos.width

        let res = Wnd.create'Circular(parent, null, pos, id)
        res.focusPolicy = .Click
        if range do
            res.flags.add(.Range)
        return res
    }
}
