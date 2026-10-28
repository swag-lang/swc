#global public

using Core, Pixel

// Reports that work is under way, without claiming to know how much is left.
//
// It is the circular progress of the charter: an Arc arc turning on a raised ring. The ring is
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
        Spinner.paintRing(painter, rect, .animationPhase, colors.spinner_Track, colors.spinner_Mark, metrics)

        .animationPhase = Math.fract(.animationPhase + .paintDeltaSeconds() * metrics.spinner_Speed)
        .invalidate()
    }
}

impl Spinner
{
    // Shares the widget's ring with loading indicators drawn inside document image boxes.
    //
    // `phase` is the position of the turning arc in its cycle, from zero to one.
    internal func paintRing(painter: *Painter, rect: Math.Rectangle, phase: f32, track, mark: Color, metrics: const *ThemeMetrics)
    {
        let stroke = metrics.spinner_StrokeSize
        let radius = Math.min(rect.width, rect.height) * 0.5 - stroke * 0.5
        if radius <= 0 do
            return

        let centerX = rect.horzCenter()
        let centerY = rect.vertCenter()
        painter.setAntialiased(true)
        painter.drawCircle(centerX, centerY, radius, track, stroke)

        let start = Math.Angle.fromDegrees(phase * 360)
        let end   = Math.Angle.fromDegrees((phase + metrics.spinner_ArcSweep) * 360)
        painter.drawArc(centerX, centerY, radius, start, end, mark, stroke)
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
