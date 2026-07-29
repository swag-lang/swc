#global public

using Core, Pixel

// Selects frame wnd form.
enum FrameWndForm
{
    Transparent // Uses the transparent form.
    Square // Uses the square form.
    Round // Uses the round form.
}

// Selects frame wnd flags.
#[Swag.EnumFlags]
enum FrameWndFlags
{
    Zero = 0 // No flags are enabled.
    Borders // Enables borders.
    FocusBorder // Enables focus border.
    SmallShadow // Enables small shadow.
}

// Selects frame wnd anchor.
enum FrameWndAnchor
{
    None // No option is selected.
    Left // Selects left.
    Top // Selects top.
    Right // Selects right.
    Bottom // Selects bottom.
}

// Represents frame wnd.
struct FrameWnd
{
    using wnd: Wnd // Embedded wnd state.

    #[Swag.Late]
    view:        *Wnd // View associated with this value.
    frameForm  = FrameWndForm.Transparent // Frame form associated with this value.
    frameFlags = FrameWndFlags.Borders // Frame flags associated with this value.
    anchor     = FrameWndAnchor.None // Anchor associated with this value.
    anchorPos:   f32 // Anchor pos associated with this value.
    usedColorBk: Color // Used color bk associated with this value.
}

impl IWnd for FrameWnd
{
    mtd impl onPrePaintEvent(evt: *PaintEvent)
    {
        if .frameFlags.has(.SmallShadow)
        {
            let bc      = evt.bc
            let painter = bc.painter
            let theme   = .getTheme()
            let colors  = .getThemeColors()
            let metrics = .getThemeMetrics()

            var clientRect = .getClientRect()
            clientRect.applyPadding(-metrics.frameWnd_SmallShadowSize)
            let subRect = &theme.rects.frameWnd_SmallShadow
            theme.drawSubRect(painter, clientRect, subRect, colors.frameWnd_SmallShadow)
        }
    }

    mtd impl onPaintEvent(evt: *PaintEvent)
    {
        if .frameForm == .Transparent do
            return

        let bc      = evt.bc
        let painter = bc.painter
        let theme   = .getTheme()
        let colors  = .getThemeColors()
        let rects   = .getThemeRects()

        var subRectBk: #null *ThemeImageRect
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
            let focus = .getFocus()
            if !focus or !.isParentOf(focus) do
                showFocus = false
        }

        switch
        {
        case bc.isDisabled: colorBk = colors.frameWnd_DisabledBk
        case showFocus:     colorBk = colors.frameWnd_FocusBk
        default:            colorBk = colors.frameWnd_Bk
        }

        let clientRect = .getClientRect()
        theme.drawSubRect(painter, clientRect, subRectBk, colorBk)
        .usedColorBk = colorBk
    }

    mtd impl onPostPaintEvent(evt: *PaintEvent)
    {
        if .frameForm == .Transparent do
            return
        if !(.frameFlags & .Borders) do
            return

        let bc      = evt.bc
        let painter = bc.painter
        let theme   = .getTheme()
        let colors  = .getThemeColors()
        let rects   = .getThemeRects()
        let metrics = .getThemeMetrics()

        var subRectBorder: #null *ThemeImageRect
        var colorBorder:   Color = undefined

        switch .frameForm
        {
        case .Square: subRectBorder = &rects.frameWnd_SquareBorder
        case .Round:  subRectBorder = &rects.frameWnd_RoundBorder
        }

        // Display focus borders when the focus wnd is a child of me
        var showFocus = .frameFlags.has(.FocusBorder)
        if showFocus
        {
            let focus = .getFocus()
            if !focus or !.isParentOf(focus) do
                showFocus = false
        }

        switch
        {
        case bc.isDisabled: colorBorder = colors.frameWnd_DisabledBorder
        case showFocus:     colorBorder = colors.frameWnd_FocusBorder
        default:            colorBorder = colors.frameWnd_Border
        }

        var clientRect = .getClientRect()
        theme.drawSubRect(painter, clientRect, subRectBorder, colorBorder, false)

        // Anchor
        if .anchor != .None
        {
            var posA = .anchorPos
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
                theme.drawSubRect(painter, clientRect, &rects.frameWnd_AnchorTopBk, .usedColorBk)
                theme.drawSubRect(painter, clientRect, &rects.frameWnd_AnchorTop, colorBorder, false)

            case .Bottom:
                posA              = Math.clamp(posA, marginA, clientRect.width - marginA)
                clientRect.x      = clientRect.x + posA - metrics.frameWnd_AnchorWidth * 0.5
                clientRect.y      = clientRect.bottom() - metrics.frameWnd_AnchorOverlap
                clientRect.width  = metrics.frameWnd_AnchorWidth
                clientRect.height = metrics.frameWnd_AnchorHeight + metrics.frameWnd_AnchorOverlap
                theme.drawSubRect(painter, clientRect, &rects.frameWnd_AnchorBottomBk, .usedColorBk)
                theme.drawSubRect(painter, clientRect, &rects.frameWnd_AnchorBottom, colorBorder, false)

            case .Left:
                posA              = Math.clamp(posA, marginA, clientRect.height - marginA)
                clientRect.x      -= metrics.frameWnd_AnchorHeight
                clientRect.y      = clientRect.y + posA - metrics.frameWnd_AnchorHeight * 0.5
                clientRect.width  = metrics.frameWnd_AnchorHeight + metrics.frameWnd_AnchorOverlap
                clientRect.height = metrics.frameWnd_AnchorWidth
                theme.drawSubRect(painter, clientRect, &rects.frameWnd_AnchorLeftBk, .usedColorBk)
                theme.drawSubRect(painter, clientRect, &rects.frameWnd_AnchorLeft, colorBorder, false)

            case .Right:
                posA              = Math.clamp(posA, marginA, clientRect.height - marginA)
                clientRect.x      = clientRect.right() - metrics.frameWnd_AnchorOverlap
                clientRect.y      = clientRect.y + posA - metrics.frameWnd_AnchorHeight * 0.5
                clientRect.width  = metrics.frameWnd_AnchorHeight + metrics.frameWnd_AnchorOverlap
                clientRect.height = metrics.frameWnd_AnchorWidth
                theme.drawSubRect(painter, clientRect, &rects.frameWnd_AnchorRightBk, .usedColorBk)
                theme.drawSubRect(painter, clientRect, &rects.frameWnd_AnchorRight, colorBorder, false)
            }
        }
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        if !@isset(.view) do
            return
        var rect = .getClientRectPadding()
        rect.applyPadding(.view.margin)
        .view.setPosition(rect)
    }
}

impl FrameWnd
{
    // Creates and attaches a typed child as this frame's view.
    #[Swag.Discardable]
    mtd(T) createView(hook: #null HookEvent = null)->*T
    {
        .view                 = Wnd.create'T(me, "", .position, hook: hook)
        .view.backgroundStyle = .Transparent
        .sendResizeEvent()
        return notnull cast(#null *T) .view
    }

    // Sets view.
    mtd setView(what: *Wnd)
    {
        if @isset(.view) do
            .view.destroy()
        what.setParent(me)
        .view = what
        .sendResizeEvent()
    }

    // Set the frame wnd flags
    mtd setFrameFlags(add, remove = FrameWndFlags.Zero)
    {
        .frameFlags.add(add)
        .frameFlags.remove(remove)

        if .frameFlags.has(.SmallShadow) do
            .wndFlags.add(.PreChildsPaint)
        else do
            .wndFlags.remove(.PreChildsPaint)

        if .frameFlags.has(.SmallShadow) do
            .invalidatePadding = -.getThemeMetrics().frameWnd_SmallShadowSize
        else do
            .invalidatePadding.setZero()
    }

    // Set the frame wnd form
    mtd setFrameForm(form: FrameWndForm)
    {
        if .frameForm == form do
            return
        .frameForm = form

        switch #complete .frameForm
        {
        case .Square:
            .wndFlags.add(.PostChildsPaint)
            .setAllPaddings(.getThemeMetrics().frameWnd_SquarePadding)

        case .Round:
            .wndFlags.add(.PostChildsPaint)
            .setAllPaddings(.getThemeMetrics().frameWnd_RoundPadding)

        case .Transparent:
            .wndFlags.remove(.PostChildsPaint)
            .setAllPaddings(0)
        }

        .sendResizeEvent()
    }
}
