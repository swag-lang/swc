#global public

using Core, Pixel

// Configures progress bar presentation.
#[Swag.EnumFlags]
enum ProgressBarFlags
{
    None = 0          // Displays a finite value from zero to one.
    Indeterminate     // Displays animated activity without a known value.
}

// Displays finite progress or indeterminate activity.
struct ProgressBar
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        readonly
        {
            value: f32     // Finite progress, clamped to the zero-to-one range.
            flags = ProgressBarFlags.None     // Active presentation options.
        }
    }

    animationPhase: f32     // Position of the indeterminate marker from zero to one.
}

impl IWnd for ProgressBar
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let bc      = evt.paintContext
        let painter = bc.painter
        let theme   = .theme()
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let rects   = .themeRects()

        var colorBk:     Color
        var colorBorder: Color
        var colorMark:   Color

        switch
        {
        case bc.isDisabled:
            colorBk     = colors.progressBar_DisabledBk
            colorBorder = colors.progressBar_DisabledBorder
            colorMark   = colors.progressBar_DisabledMark

        default:
            colorBk     = colors.progressBar_Bk
            colorBorder = colors.progressBar_Border
            colorMark   = colors.progressBar_Mark
        }

        // The bar is a thin track centered in the control, filled in Arc from its leading end; an
        // indeterminate bar runs one Arc segment along it. The fill is clipped to the track so its
        // round ends follow the track's, wherever the segment stands.
        let clientRect = .clientRect()
        var track      = clientRect
        track.height = Math.min(metrics.progressBar_TrackSize, clientRect.height)
        track.y      = clientRect.vertCenter() - track.height * 0.5
        theme.drawSubRect(painter, track, &rects.progressBar_Bk, colorBk)

        var fill = track
        if .flags.has(.Indeterminate)
        {
            let w = Math.max(track.width / 5, 1)
            fill.width = w
            fill.x     = track.x - w + (.animationPhase * (track.width + 2 * w))

            // Advance only presentation; the caller's finite value remains intact.
            .animationPhase += .paintDeltaSeconds() * metrics.progressBar_SpeedInf
            if .animationPhase > 1 do
                .animationPhase = 0
            .invalidate()
        }
        else
        {
            fill.width = track.width * .value
        }

        painter.startClippingRegion()
        theme.drawSubRect(painter, track, &rects.progressBar_Bk, Argb.White)
        painter.endClippingRegion()
        theme.drawSubRect(painter, fill, &rects.progressBar_Mark, colorMark)
        painter.resetClippingRegion()

        theme.drawSubRect(painter, track, &rects.progressBar_Border, colorBorder)
    }
}

impl ProgressBar
{
    // Creates a progress bar with optional initial presentation options.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: WndId? = null, flags = ProgressBarFlags.None)->*ProgressBar
    {
        Swag.assert(parent != null)
        var pos = position
        if pos.height == 0 do
            pos.height = parent.themeMetrics().progressBar_Height
        let result = Wnd.create'ProgressBar(parent, null, pos, id)
        result.flags = flags
        return result
    }

    // Sets finite progress after clamping it to the zero-to-one range.
    mtd setValue(value: f32)
    {
        let newValue = Math.saturate(value)
        if newValue == .value do
            return
        .value = newValue
        .invalidate()
    }

    // Adds and removes presentation options and restarts indeterminate animation when needed.
    mtd updateFlags(add: ProgressBarFlags = .None, remove = ProgressBarFlags.None)
    {
        let oldFlags = .flags
        .flags.add(add)
        .flags.remove(remove)
        if not oldFlags.has(.Indeterminate) and .flags.has(.Indeterminate) do
            .animationPhase = 0
        .invalidate()
    }
}
