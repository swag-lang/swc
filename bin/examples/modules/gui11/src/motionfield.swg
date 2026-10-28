using Core, Gui, Pixel

const TrailLength = 44
const PuckSize    = 15.0
const FieldGrid   = 32.0

// A surface where every click retargets the same property of the same window.
//
// One [[Gui.AnimationChannel]] owns the puck position for the whole page, so a second click never
// stacks a second animation: it replaces the first one from the value currently on screen. The
// trail is what makes that visible — an interrupted run bends, it does not restart.
struct MotionField
{
    using wnd: Wnd

    puck:    Math.Point
    goal:    Math.Point
    hasGoal: bool

    trail:     [TrailLength] Math.Point
    trailUsed: u32
    trailNext: u32

    easing:           AnimationEasing = .EaseOut     // Curve the page asked for.
    travelTime:       Time.Duration   = 900'ms       // Duration the page asked for.
    preserveProgress: bool     // Whether a replacement keeps the progress of the run it replaces.
}

impl MotionField
{
    func create(parent: *Wnd)->*MotionField
    {
        let result = Wnd.create'MotionField(parent, {})
        result.backgroundStyle = .Transparent
        result.cursor = Cursor.from(CursorShape.Hand)
        return result
    }

    // Sends the puck to `point`, replacing whatever run is in flight.
    mtd moveTo(point: Math.Point)
    {
        .goal    = point
        .hasGoal = true

        let curve    = .easing
        let time     = .travelTime
        let preserve = .preserveProgress

        var options: AnimationOptions
        options.duration         = time
        options.easing           = curve
        options.preserveProgress = preserve

        discard .app().animator.animatePoint(me,
                                             AnimationChannel.from("Gui11.Field.Puck"),
                                             .puck,
                                             point,
                                             func|field = me|(_, value)
                                             {
                                                 field.puck = value
                                                 field.pushTrail(value)
                                             },
                                             options)
    }

    // Records one sampled position in the fixed-size trail ring.
    mtd pushTrail(point: Math.Point)
    {
        .trail[.trailNext] = point
        .trailNext         = (.trailNext + 1) % TrailLength
        if .trailUsed < TrailLength do
            .trailUsed += 1
    }

    mtd clearTrail()
    {
        .trailUsed = 0
        .trailNext = 0
    }

    // Returns whether an animation currently owns the puck.
    mtd isMoving()->bool => .app().animator.isActive(me, AnimationChannel.from("Gui11.Field.Puck"))
}

impl IWnd for MotionField
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind != .Pressed do
            return
        .setFocus()
        .moveTo(.surfaceToLocal(evt.surfacePos))
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        // The first size is what decides where the puck starts; a later resize leaves it alone so
        // a run in flight is not teleported under the reader.
        if .hasGoal do
            return
        let rect = .clientRect()
        .puck = Math.Point{rect.horzCenter(), rect.vertCenter()}
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let rect    = .clientRect()

        // The field is the raised ground the puck travels on; what moves is in progress, so Arc.
        let corner = .themeMetrics().corner_Control
        painter.fillRoundRect(rect, corner, corner, colors.raised)

        painter.pushClippingRect(rect)
        defer painter.popClippingRect()

        let dotColor = colors.strongLine.withAlphaF32(0.7)
        var y        = rect.y + FieldGrid
        while y < rect.bottom()
        {
            var x = rect.x + FieldGrid
            while x < rect.right()
            {
                painter.fillRect(Math.Rectangle{x - 1, y - 1, 2, 2}, dotColor)
                x += FieldGrid
            }

            y += FieldGrid
        }

        if .hasGoal
        {
            painter.drawCircle(.goal.x, .goal.y, PuckSize * 0.55, colors.arc.withAlphaF32(0.45), 1)
            painter.drawLine(.puck.x, .puck.y, .goal.x, .goal.y, colors.arc.withAlphaF32(0.22), 1)
        }

        // Oldest sample first, so the newest one is drawn on top of the ones it came from.
        for step in .trailUsed
        {
            let index = (.trailNext + TrailLength - .trailUsed + step) % TrailLength
            let ratio = cast(f32, (step + 1)) / cast(f32, .trailUsed)
            let point = .trail[index]
            painter.fillCircle(point.x, point.y, 1.5 + 4 * ratio, colors.arc.withAlphaF32(0.05 + 0.22 * ratio))
        }

        painter.fillCircle(.puck.x, .puck.y, PuckSize + 5, colors.arc.withAlphaF32(0.16))
        painter.fillCircle(.puck.x, .puck.y, PuckSize, colors.arc)

        if not .hasGoal
        {
            let font = .theme().createDefaultFont(14)
            let text = "Click anywhere. Click again before it lands."
            painter.drawStringCenter(rect.horzCenter(),
                                     rect.vertCenter() + PuckSize + 26,
                                     text,
                                     font,
                                     colors.label_TextLight)
        }
    }
}
