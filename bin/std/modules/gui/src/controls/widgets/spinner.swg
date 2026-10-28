#global public

using Core, Pixel

// Reports that work is under way, without claiming to know how much is left.
//
// It is the waiting mark of the charter, and it carries the hand of the Swag mark: three leaning
// bars, their corners cut at 45 degrees like the bars of the S. A wave of Arc light runs across
// them from the leading one; as it passes, each bar lifts, grows a little taller and leans a
// little further, then settles back, and the three rest a moment before the next wave. It is
// drawn, never sampled from an atlas, so it is exact at any size and at any display density — a
// spinner is the one piece of theme art that is always in motion, which is exactly where a
// resampled bitmap shows. Use it for a wait with no measurable progress; a [[Gui.ProgressBar]]
// carrying `Indeterminate` says the same thing along a docked edge.
//
// It animates while it is visible and costs nothing while it is not, so the caller only
// shows and hides it:
//
// ```swag
// let busy = Spinner.create(view, Math.Rectangle{4, 4})
// busy.hide()
// ```
struct Spinner
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.
    }

    animationPhase: f32     // Position in the cycle, from zero to one.
}

impl IWnd for Spinner
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let metrics = .themeMetrics()

        let colors = .themeColors()
        let rect   = .paddedClientRect()
        Spinner.paintRing(painter, rect, .animationPhase, colors.spinner_Mark)

        .animationPhase = Math.fract(.animationPhase + .paintDeltaSeconds() * metrics.spinner_Speed)
        .invalidate()
    }
}

impl Spinner
{
    // Shares the widget's mark with loading indicators drawn inside document image boxes.
    //
    // `phase` is the position in the cycle, from zero to one: the wave crosses the bars over the
    // first four fifths of it, and the last fifth is the rest between two waves.
    internal func paintRing(painter: *Painter, rect: Math.Rectangle, phase: f32, mark: Color)
    {
        let side = Math.min(rect.width, rect.height)
        if side <= 0 do
            return

        // The bars at rest, in proportion to the box, leaning like the mark.
        let height = side * 0.46
        let width  = side * 0.12
        let gap    = side * 0.10
        let lean   = height * 0.34
        let cut    = width * 0.34
        let total  = 3 * width + 2 * gap + lean
        let left   = rect.horzCenter() - total * 0.5
        let top    = rect.vertCenter() - height * 0.5 + side * 0.03

        painter.setAntialiased(true)
        let alpha = cast(f32, mark.a) / 255
        for i in 3
        {
            // Where the wave stands on this bar: a bell from nothing to its crest and back.
            let t     = (phase * 1.25 - cast(f32, i) * 0.17) / 0.62
            var crest = 0'f32
            if t > 0 and t < 1
            {
                let s = Math.sin(Math.ConstF32.Pi * t)
                crest = s * s
            }

            // The crest lifts the bar, stretches it and leans it further; its top stays above its foot.
            let barHeight = height * (1 + 0.14 * crest)
            let barLean   = lean * (1 + 0.35 * crest)
            let x         = left + cast(f32, i) * (width + gap) - (barLean - lean)
            let y         = top - side * 0.05 * crest - (barHeight - height)

            var points: [6] Math.Vector2 = [
                Math.Vector2{x + barLean + cut, y},
                Math.Vector2{x + barLean + width, y},
                Math.Vector2{x + width, y + barHeight - cut},
                Math.Vector2{x + width - cut, y + barHeight},
                Math.Vector2{x, y + barHeight},
                Math.Vector2{x + barLean, y + cut}]
            painter.fillPolygon(points[0 until 6], Brush.createSolid(mark.withAlphaF32(alpha * (0.3 + 0.7 * crest))))
        }
    }

    // Creates a spinner, square by default and sized by the theme when `position` says nothing.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: WndId? = null)->*Spinner
    {
        Swag.assert(parent != null)

        var pos = position
        if pos.width == 0 do
            pos.width = parent.themeMetrics().spinner_Size
        if pos.height == 0 do
            pos.height = pos.width

        return Wnd.create'Spinner(parent, null, pos, id)
    }
}
