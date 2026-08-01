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
    using wnd: Wnd     // Embedded window behavior and presentation.

    readonly
    {
        value: f32                       // Finite progress, clamped to the zero-to-one range.
        flags = ProgressBarFlags.None     // Active presentation options.
    }

    internal animationPhase: f32     // Position of the indeterminate marker from zero to one.
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

        var colorBk:     Color = undefined
        var colorBorder: Color = undefined
        var colorMark:   Color = undefined

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

        let subRectBk     = &rects.progressBar_Bk
        let subRectBorder = &rects.progressBar_Border
        let subRectMark   = &rects.progressBar_Mark

        // Bk
        let clientRect = .clientRect()
        theme.drawSubRect(painter, clientRect, subRectBk, colorBk)

        painter.startClippingRegion()
        var clip = clientRect
        clip.inflate(-metrics.progressBar_ClipOffset)
        theme.drawSubRect(painter, clip, subRectBk, Argb.White)
        painter.endClippingRegion()

        // Bar
        var posBox = clientRect
        posBox.y = clientRect.vertCenter() - (posBox.height * 0.5)
        if .flags.has(.Indeterminate)
        {
            let w = Math.max(clientRect.width / 5, 1)
            posBox.width = w

            let wt = clientRect.width + 2 * w
            posBox.x = -w + (.animationPhase * wt)

            // Advance only presentation; the caller's finite value remains intact.
            .animationPhase += .timing().deltaSeconds * metrics.progressBar_SpeedInf
            if .animationPhase > 1 do
                .animationPhase = 0
            .invalidate()
        }
        else
        {
            posBox.width = clientRect.width * .value
        }

        theme.drawSubRect(painter, posBox, subRectMark, colorMark)
        painter.resetClippingRegion()

        // Border
        theme.drawSubRect(painter, clientRect, subRectBorder, colorBorder)
    }
}

impl ProgressBar
{
    // Creates a progress bar with optional initial presentation options.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null, flags = ProgressBarFlags.None)->*ProgressBar
    {
        Debug.assert(parent != null)
        var pos = position
        if pos.height == 0 do
            pos.height = parent.themeMetrics().progressBar_Height
        let result   = Wnd.create'ProgressBar(parent, null, pos, id)
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
        if !oldFlags.has(.Indeterminate) and .flags.has(.Indeterminate) do
            .animationPhase = 0
        .invalidate()
    }
}
