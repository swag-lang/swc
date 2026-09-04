#global public

using Core, Pixel

// Reports that work is under way, without claiming to know how much is left.
//
// The ring is drawn, never sampled from an atlas, so it is exact at any size and at any
// display density — a spinner is the one piece of theme art that is always in motion, which
// is exactly where a resampled bitmap shows. Use it for a wait with no measurable progress;
// a [[Gui.ProgressBar]] carrying `Indeterminate` says the same thing along a docked edge.
//
// It animates while it is visible and costs nothing while it is not, so the caller only
// shows and hides it:
//
// ```swag
// let busy = Spinner.create(view, {4, 4})
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

        let count = Math.max(cast(s32) metrics.spinner_DotCount, 2)
        let rect  = .paddedClientRect()

        // A ring of pulsing dots, rather than a rotating arc: an arc needs a stroke weight to
        // read, and loses it under about sixteen pixels, which is where a spinner usually sits.
        // The dots carry the same rotation with nothing thinner than a dot at any size.
        let ringRadius = Math.min(rect.width, rect.height) * 0.5
        let dotRadius  = ringRadius * 0.22
        let centerX    = rect.horzCenter()
        let centerY    = rect.vertCenter()
        let color      = .themeColors().spinner_Dot

        painter.setAntialiased(true)

        for i in count
        {
            // The dot that just passed the head of the cycle is the faintest, so the ring
            // reads as one bright point trailing off behind it.
            let t     = Math.fract(.animationPhase + cast(f32) i / cast(f32) count)
            let angle = t * Math.ConstF32.TwoPi
            let x     = centerX + Math.sin(angle) * (ringRadius - dotRadius)
            let y     = centerY - Math.cos(angle) * (ringRadius - dotRadius)

            let brush = Brush.createSolid(color.withAlphaF32(0.15 + 0.85 * t))
            painter.fillCircle(x, y, dotRadius * (0.35 + 0.65 * t), brush)
        }

        .animationPhase = Math.fract(.animationPhase + .timing().deltaSeconds * metrics.spinner_Speed)
        .invalidate()
    }
}

impl Spinner
{
    // Creates a spinner, square by default and sized by the theme when `position` says nothing.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: WndId? = null)->*Spinner
    {
        Debug.assert(parent != null)

        var pos = position
        if pos.width == 0 do
            pos.width = parent.themeMetrics().spinner_Size
        if pos.height == 0 do
            pos.height = pos.width

        return Wnd.create'Spinner(parent, null, pos, id)
    }
}
