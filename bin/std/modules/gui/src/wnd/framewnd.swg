#global public

using Core, Pixel

// Selects the background and border geometry of a frame window.
enum FrameWndForm
{
    Transparent     // Draws no frame background or border.
    Square          // Uses square corners and square-frame theme metrics.
    Round           // Uses rounded corners and rounded-frame theme metrics.
}

// Configures optional frame decoration.
#[Swag.EnumFlags]
enum FrameWndFlags
{
    None = 0        // Draws no optional decoration.
    Borders         // Draws the themed outer border.
    FocusBorder     // Uses the focused border while a descendant owns focus.
    SmallShadow     // Draws the compact themed shadow outside the frame.
}

// Selects the edge from which a popup callout anchor protrudes.
enum FrameWndAnchor
{
    None       // Draws no callout anchor.
    Left       // Draws an anchor on the left edge.
    Top        // Draws an anchor on the top edge.
    Right      // Draws an anchor on the right edge.
    Bottom     // Draws an anchor on the bottom edge.
}

// Hosts one view inside an optional themed frame, border, shadow, and callout anchor.
struct FrameWnd
{
    public
    {
        using wnd: Wnd     // Embedded wnd state.

        late view:      *Wnd                      // Hosted content view.
        frameForm  = FrameWndForm.Transparent     // Background and border geometry.
        frameFlags = FrameWndFlags.Borders        // Active optional decoration.
        anchor     = FrameWndAnchor.None          // Edge carrying the callout anchor.
        anchorPosition: f32                       // Anchor center along the selected edge.
    }

    usedBackgroundColor: Color     // Background color selected during the latest paint.
}

impl IWnd for FrameWnd
{
    mtd impl onBeforePaint(evt: *PaintEvent)
    {
        if .frameFlags.has(.SmallShadow)
        {
            let bc      = evt.paintContext
            let painter = bc.painter
            let theme   = .theme()
            let colors  = .themeColors()
            let metrics = .themeMetrics()

            var clientRect = .clientRect()
            clientRect.applyPadding(-metrics.frameWnd_SmallShadowSize)
            let subRect = &theme.rects.frameWnd_SmallShadow
            theme.drawSubRect(painter, clientRect, subRect, colors.frameWnd_SmallShadow)
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        if .frameForm == .Transparent do
            return

        let bc      = evt.paintContext
        let painter = bc.painter
        let theme   = .theme()
        let colors  = .themeColors()
        let rects   = .themeRects()

        var subRectBk: *ThemeImageRect?
        var colorBk:   Color

        switch .frameForm
        {
        case .Square: subRectBk = &rects.frameWnd_SquareBk
        case .Round:  subRectBk = &rects.frameWnd_RoundBk
        }

        // Display focus borders when the focus wnd is a child of me
        var showFocus = .frameFlags.has(.FocusBorder)
        if showFocus
        {
            let focus = .focusedWindow()
            if !focus or !.isAncestorOf(focus) do
                showFocus = false
        }

        switch
        {
        case bc.isDisabled: colorBk = colors.frameWnd_DisabledBk
        case showFocus:     colorBk = colors.frameWnd_FocusBk
        default:            colorBk = colors.frameWnd_Bk
        }

        let clientRect = .clientRect()
        theme.drawSubRect(painter, clientRect, subRectBk, colorBk)
        .usedBackgroundColor = colorBk
    }

    mtd impl onAfterPaint(evt: *PaintEvent)
    {
        if .frameForm == .Transparent do
            return
        if !(.frameFlags & .Borders) do
            return

        let bc      = evt.paintContext
        let painter = bc.painter
        let theme   = .theme()
        let colors  = .themeColors()
        let rects   = .themeRects()
        let metrics = .themeMetrics()

        var subRectBorder: *ThemeImageRect?
        var colorBorder:   Color

        switch .frameForm
        {
        case .Square: subRectBorder = &rects.frameWnd_SquareBorder
        case .Round:  subRectBorder = &rects.frameWnd_RoundBorder
        }

        // Display focus borders when the focus wnd is a child of me
        var showFocus = .frameFlags.has(.FocusBorder)
        if showFocus
        {
            let focus = .focusedWindow()
            if !focus or !.isAncestorOf(focus) do
                showFocus = false
        }

        switch
        {
        case bc.isDisabled: colorBorder = colors.frameWnd_DisabledBorder
        case showFocus:     colorBorder = colors.frameWnd_FocusBorder
        default:            colorBorder = colors.frameWnd_Border
        }

        var clientRect = .clientRect()
        theme.drawSubRect(painter, clientRect, subRectBorder, colorBorder, false)

        // Anchor
        if .anchor != .None
        {
            var posA = .anchorPosition
            var marginA: f32
            switch .frameForm
            {
            case .Square: marginA = metrics.frameWnd_AnchorSquareBorderMargin
            case .Round:  marginA = metrics.frameWnd_AnchorRoundBorderMargin
            }

            switch .anchor
            {
            case .Top:
                posA              = Math.clamp(posA, marginA, clientRect.width - marginA)
                clientRect.x      = clientRect.x + posA - metrics.frameWnd_AnchorWidth * 0.5
                clientRect.y      -= metrics.frameWnd_AnchorHeight
                clientRect.width  = metrics.frameWnd_AnchorWidth
                clientRect.height = metrics.frameWnd_AnchorHeight + metrics.frameWnd_AnchorOverlap
                theme.drawSubRect(painter, clientRect, &rects.frameWnd_AnchorTopBk, .usedBackgroundColor)
                theme.drawSubRect(painter, clientRect, &rects.frameWnd_AnchorTop, colorBorder, false)

            case .Bottom:
                posA              = Math.clamp(posA, marginA, clientRect.width - marginA)
                clientRect.x      = clientRect.x + posA - metrics.frameWnd_AnchorWidth * 0.5
                clientRect.y      = clientRect.bottom() - metrics.frameWnd_AnchorOverlap
                clientRect.width  = metrics.frameWnd_AnchorWidth
                clientRect.height = metrics.frameWnd_AnchorHeight + metrics.frameWnd_AnchorOverlap
                theme.drawSubRect(painter, clientRect, &rects.frameWnd_AnchorBottomBk, .usedBackgroundColor)
                theme.drawSubRect(painter, clientRect, &rects.frameWnd_AnchorBottom, colorBorder, false)

            case .Left:
                posA              = Math.clamp(posA, marginA, clientRect.height - marginA)
                clientRect.x      -= metrics.frameWnd_AnchorHeight
                clientRect.y      = clientRect.y + posA - metrics.frameWnd_AnchorHeight * 0.5
                clientRect.width  = metrics.frameWnd_AnchorHeight + metrics.frameWnd_AnchorOverlap
                clientRect.height = metrics.frameWnd_AnchorWidth
                theme.drawSubRect(painter, clientRect, &rects.frameWnd_AnchorLeftBk, .usedBackgroundColor)
                theme.drawSubRect(painter, clientRect, &rects.frameWnd_AnchorLeft, colorBorder, false)

            case .Right:
                posA              = Math.clamp(posA, marginA, clientRect.height - marginA)
                clientRect.x      = clientRect.right() - metrics.frameWnd_AnchorOverlap
                clientRect.y      = clientRect.y + posA - metrics.frameWnd_AnchorHeight * 0.5
                clientRect.width  = metrics.frameWnd_AnchorHeight + metrics.frameWnd_AnchorOverlap
                clientRect.height = metrics.frameWnd_AnchorWidth
                theme.drawSubRect(painter, clientRect, &rects.frameWnd_AnchorRightBk, .usedBackgroundColor)
                theme.drawSubRect(painter, clientRect, &rects.frameWnd_AnchorRight, colorBorder, false)
            }
        }
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        if !(.view != null) do
            return
        var rect = .paddedClientRect()
        rect.applyPadding(.view.margin)
        .view.setPosition(rect)
    }
}

impl FrameWnd
{
    // Creates and attaches a typed child as this frame's view.
    #[Swag.Discardable]
    mtd(T) createView(hook: HookEvent? = null)->*T
    {
        // The view is born at its final laid-out rectangle — the frame minus its
        // caption and border paddings — because a hook may lay out its content from
        // the client rectangle it sees in the create event.
        .view                 = Wnd.create'T(me, "", .paddedClientRect(), hook: hook)
        .view.backgroundStyle = .Transparent
        .sendResizeEvent()
        return cast(*T) .view!
    }

    // Replaces and destroys the current view, then attaches `what` to this frame.
    mtd setView(what: *Wnd)
    {
        if (.view != null) and .view == what do
            return
        if .view != null do
            .view.destroy()
        what.setParent(me)
        .view = what
        .sendResizeEvent()
    }

    // Adds and removes frame decoration flags.
    mtd setFrameFlags(add, remove = FrameWndFlags.None)
    {
        .frameFlags.add(add)
        .frameFlags.remove(remove)

        if .frameFlags.has(.SmallShadow) do
            .wndFlags.add(.BeforeChildrenPaint)
        else do
            .wndFlags.remove(.BeforeChildrenPaint)

        if .frameFlags.has(.SmallShadow) do
            .invalidatePadding = -.themeMetrics().frameWnd_SmallShadowSize
        else do
            .invalidatePadding.setZero()

        .invalidate()
    }

    // Changes the frame geometry and updates content padding.
    mtd setFrameForm(form: FrameWndForm)
    {
        if .frameForm == form do
            return
        .frameForm = form

        switch #complete .frameForm
        {
        case .Square:
            .wndFlags.add(.AfterChildrenPaint)
            .setAllPaddings(.themeMetrics().frameWnd_SquarePadding)

        case .Round:
            .wndFlags.add(.AfterChildrenPaint)
            .setAllPaddings(.themeMetrics().frameWnd_RoundPadding)

        case .Transparent:
            .wndFlags.remove(.AfterChildrenPaint)
            .setAllPaddings(0)
        }

        .sendResizeEvent()
    }
}
