using Core, Gui, Pixel

// Every curve [[Gui.AnimationEasing]] offers, in the order the wall shows them.
const WallCurves = [
    AnimationEasing.Linear,
    .EaseIn,
    .EaseOut,
    .EaseInOut,
    .EaseInBack,
    .EaseOutBack,
    .EaseInOutBack,
    .EaseOutElastic,
    .EaseOutBounce]

// Vertical window of a plot, in track value.
//
// It is the same on every card so the curves can be compared, and it is wider than the unit
// interval because the back, elastic, and bounce curves leave it on purpose.
const PlotLow  = -0.42'f32
const PlotHigh = 1.42'f32

const CardGap      = 12.0
const CardPadding  = 12.0
const MinCardWidth = 240.0
const NameHeight   = 20.0
const RailHeight   = 22.0
const RailGap      = 10.0
const PuckRadius   = 7.0
const CurveSamples = 64

// Draws every easing curve of the toolkit against one shared clock.
//
// The dot on the graph and the puck on the rail below it read the same number, which is the whole
// argument of the page: the shape above is the movement below. A single endless track drives all
// nine cards, so the wall repaints once per frame however many curves it shows.
struct CurveWall
{
    using wnd: Wnd

    phase: f32     // Normalized position in the shared clock, from zero through one.
}

impl CurveWall
{
    func create(parent: *Wnd)->*CurveWall
    {
        let result = Wnd.create'CurveWall(parent, {})
        result.backgroundStyle = .Transparent
        return result
    }

    // Starts the endless ping-pong clock every card reads.
    //
    // The track is decorative, so turning reduced motion on parks the wall on its resting frame
    // instead of leaving nine animations running behind a preference that asked for none.
    mtd startClock()
    {
        var options: AnimationOptions
        options.duration    = 1500'ms
        options.easing      = .Linear
        options.repeatCount = 0
        options.autoReverse = true

        discard .app().animator.animateF32(me,
                                           AnimationChannel.from("Gui11.Curves.Clock"),
                                           0,
                                           1,
                                           func|wall = me|(animationWnd, value)
                                           {
                                               discard animationWnd
                                               wall.phase = value
                                           },
                                           options)
    }

    // Returns the ordinate of `value` inside `plot`.
    func plotY(plot: Math.Rectangle, value: f32)->f32
    {
        return plot.bottom() - (value - PlotLow) / (PlotHigh - PlotLow) * plot.height
    }

    mtd paintCard(painter: *Painter, card: Math.Rectangle, easing: AnimationEasing)
    {
        let colors = .themeColors()
        let theme  = .theme()

        painter.fillRoundRect(card, 8, 8, colors.wnd_Bk)
        painter.drawRoundRect(card, 8, 8, colors.border, 1)

        let nameFont = theme.createDefaultFont(13, .Bold)
        let nameY    = nameFont.opticalTop(card.y + CardPadding + NameHeight * 0.5, 13)
        painter.drawString(card.x + CardPadding, nameY, curveName(easing), nameFont, colors.label_Text)

        var plot = card
        plot.applyPadding({CardPadding, CardPadding + NameHeight, CardPadding, CardPadding + RailHeight + RailGap})
        if plot.width < 24 or plot.height < 24 do
            return

        // The two rules are the endpoints of the track: everything a curve draws outside them is
        // the overshoot it was chosen for.
        let restY  = plotY(plot, 1)
        let startY = plotY(plot, 0)
        painter.fillRect({plot.x, startY, plot.width, 1}, colors.border)
        painter.fillRect({plot.x, restY, plot.width, 1}, colors.hilight.withAlphaF32(0.35))

        // The straight line is the same motion with no curve at all, kept faint behind each card
        // as the reference every other shape is read against.
        if easing != .Linear do
            painter.drawLine(plot.x, startY, plot.right(), restY, colors.label_TextFaint.withAlphaF32(0.5), 1)

        var path: LinePath
        path.start(plot.x, plotY(plot, easing.evaluate(0)))
        for [step] in CurveSamples
        {
            let t = cast(f32) (step + 1) / cast(f32) CurveSamples
            path.lineTo(plot.x + t * plot.width, plotY(plot, easing.evaluate(t)))
        }

        painter.drawPath(&path, colors.hilight, 2)

        let eased   = easing.evaluate(.phase)
        let markerX = plot.x + .phase * plot.width
        let markerY = plotY(plot, eased)
        painter.fillCircle(markerX, markerY, 4, colors.hilight)
        painter.drawCircle(markerX, markerY, 4, colors.wnd_Bk, 1.5)

        // The rail turns the ordinate back into travel, which is what a reader is actually
        // choosing a curve for.
        var rail = Math.Rectangle{card.x + CardPadding, card.bottom() - CardPadding - RailHeight, card.width - 2 * CardPadding, RailHeight}
        let midY = rail.y + rail.height * 0.5
        painter.fillRoundRect({rail.x, midY - 2, rail.width, 4}, 2, 2, colors.border)

        let travel = rail.width - 2 * PuckRadius
        let puckX  = rail.x + PuckRadius + eased * travel
        painter.fillCircle(puckX, midY, PuckRadius, colors.hilight)
    }
}

impl IWnd for CurveWall
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let rect    = .clientRect()
        let count   = cast(s32) @countof(WallCurves)

        let columns = Math.clamp(cast(s32) ((rect.width + CardGap) / (MinCardWidth + CardGap)), 1, 3)
        let rows    = (count + columns - 1) / columns
        let cardW   = (rect.width - cast(f32) (columns - 1) * CardGap) / cast(f32) columns
        let cardH   = (rect.height - cast(f32) (rows - 1) * CardGap) / cast(f32) rows
        if cardW < 60 or cardH < 60 do
            return

        for [index] in count
        {
            let column = cast(f32) (index % columns)
            let row    = cast(f32) (index / columns)
            let card   = Math.Rectangle{rect.x + column * (cardW + CardGap), rect.y + row * (cardH + CardGap), cardW, cardH}
            .paintCard(painter, card, WallCurves[index])
        }
    }
}

// Returns the name of `easing` as the reference spells it.
func curveName(easing: AnimationEasing)->string
{
    switch #complete easing
    {
    case .Linear:         return "Linear"
    case .EaseIn:         return "EaseIn"
    case .EaseOut:        return "EaseOut"
    case .EaseInOut:      return "EaseInOut"
    case .EaseInBack:     return "EaseInBack"
    case .EaseOutBack:    return "EaseOutBack"
    case .EaseInOutBack:  return "EaseInOutBack"
    case .EaseOutElastic: return "EaseOutElastic"
    case .EaseOutBounce:  return "EaseOutBounce"
    }

    unreachable
}
