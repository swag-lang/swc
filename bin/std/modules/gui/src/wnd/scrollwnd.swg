using Core, Pixel

// Configures scrollbar presentation and visibility.
#[Swag.EnumFlags]
public enum ScrollWndFlags
{
    None = 0                 // Uses normal bars that appear only when content overflows.
    CompactBars              // Uses the compact scrollbar thickness.
    AlwaysShowHorizontal     // Keeps the horizontal bar visible without overflow.
    AlwaysShowVertical       // Keeps the vertical bar visible without overflow.
    TransparentBars          // Omits the scrollbar track background.
    DisableHorizontal        // Never exposes horizontal scrolling, even when content is wider.
}

// Hosts one view in a scrollable viewport with optional smooth panning and scrollbars.
public struct ScrollWnd
{
    public
    {
        using frameWnd: FrameWnd     // Embedded frame wnd state.

        verticalScrollStep:   f32 = 50     // Vertical distance applied per mouse-wheel notch.
        horizontalScrollStep: f32 = 50     // Horizontal distance applied per shifted wheel notch.

        readonly
        {
            scrollSize: Math.Point          // Virtual content size.
            flags = ScrollWndFlags.None     // Active scrollbar options.
        }

        sigScrollPositionChanged: SigArray'func||(*ScrollWnd, Math.Point, Math.Point)     // Emitted with old and new scroll positions.
        sigScrollSizeChanged:     SigArray'func||(*ScrollWnd, Math.Point, Math.Point)     // Emitted with old and new virtual sizes.
    }

    // Scrollbar geometry, hover and drag state, and the color animations that follow them.
    // The layout pass and the mouse events maintain all of it; scroll with 'setScrollPos'
    // and connect to the signals to react.
    oldMouseCapture: *Wnd?     // Old mouse capture associated with this value.

    scrollRequestPos: Math.Point     // Scroll request pos associated with this value.

    showBarV:   bool     // Show bar v associated with this value.
    needV:      bool     // Need v associated with this value.
    posBoxV:    f32      // Pos box v associated with this value.
    sizeBoxV:   f32      // Size box v associated with this value.
    isHotV:     bool     // Whether this value is hot v.
    isHotBarV:  bool     // Whether this value is hot bar v.
    isPressedV: bool     // Whether this value is pressed v.

    showBarH:   bool     // Show bar h associated with this value.
    needH:      bool     // Need h associated with this value.
    posBoxH:    f32      // Pos box h associated with this value.
    sizeBoxH:   f32      // Size box h associated with this value.
    isHotH:     bool     // Whether this value is hot h.
    isHotBarH:  bool     // Whether this value is hot bar h.
    isPressedH: bool     // Whether this value is pressed h.

    isMoving:      bool     // Whether this value is moving.
    isGrabbing:    bool     // Whether this value is grabbing.
    correcMoving:  f32      // Correc moving associated with this value.
    offsetClientV: f32      // Offset client v associated with this value.
    offsetClientH: f32      // Offset client h associated with this value.
    paddingZ:      f32      // Padding z associated with this value.
    paddingW:      f32      // Padding w associated with this value.

    aniBkBarV: BlendColor     // Ani bk bar v associated with this value.
    aniBkBarH: BlendColor     // Ani bk bar h associated with this value.
    aniBoxV:   BlendColor     // Ani box v associated with this value.
    aniBoxH:   BlendColor     // Ani box h associated with this value.

    grabbingPos: Math.Point     // Grabbing pos associated with this value.
}

public impl IWnd for ScrollWnd
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .computeLayout()
        if !(.view != null) do
            return
        var rect = .paddedClientRect()
        rect.width  -= .paddingZ
        rect.height -= .paddingW
        rect.applyPadding(.view.margin)
        .view.setPosition(rect)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let clientRect = .clientRect()
        let pos        = .surfaceToLocal(evt.surfacePos)

        switch evt.kind
        {
        case .Wheel:
            if evt.modifiers & .Shift or !.showBarV do
                .setScrollPos(.view.scrollPos.x - (evt.delta.y * .horizontalScrollStep), .view.scrollPos.y)
            else do
                .setScrollPos(.view.scrollPos.x, .view.scrollPos.y - (evt.delta.y * .verticalScrollStep))

        case .Leave:
            .isHotV, .isHotH, .isHotBarV, .isHotBarH = false
            .invalidate()

        case .Move:
            if .isGrabbing
            {
                let move   = evt.surfacePos - .grabbingPos
                let scroll = .scrollRequestPos - move
                .scrollRequestPos = .scrollPositionPrivate(scroll.x, scroll.y)
                .grabbingPos      = evt.surfacePos

                var options: AnimationOptions
                options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_PanelSeconds)
                options.easing   = .EaseOut
                discard .app().animator.animatePoint(me,
                                                     AnimationChannel.from("Gui.Scroll.Position"),
                                                     .view.scrollPos,
                                                     .scrollRequestPos,
                                                     func|scrollWnd=me|(animationWnd, value)
                                                     {
                                                         discard animationWnd
                                                         discard scrollWnd.setScrollPosPrivate(value.x, value.y)
                                                     },
                                                     options)
                break
            }

            if !.isMoving
            {
                .hitTest(evt.surfacePos)
                break
            }

            if .isPressedV
            {
                let vh = .position.height - .paddingW
                var f  = (pos.y - .correcMoving) / (vh - .offsetClientV)
                f *= .scrollSize.y
                .setScrollPos(.view.scrollPos.x, f)
            }
            elif .isPressedH
            {
                let vh = .position.width - .paddingZ
                var f  = (pos.x - .correcMoving) / (vh - .offsetClientH)
                f *= .scrollSize.x
                .setScrollPos(f, .view.scrollPos.y)
            }

            .invalidate()

        case .Pressed:
            if evt.button == .Middle
            {
                .isGrabbing      = true
                .grabbingPos     = evt.surfacePos
                .oldMouseCapture = .mouseCapture()
                .captureMouse()
                .invalidate()
            }
            elif evt.button == .Left
            {
                .isMoving = true
                if .isHotV
                {
                    .isPressedV   = true
                    .correcMoving = pos.y - .posBoxV
                }
                elif .isHotH
                {
                    .isPressedH   = true
                    .correcMoving = pos.x - .posBoxH
                }
                elif .isHotBarV
                {
                    .correcMoving = 0
                    .isPressedV   = true
                    var f = pos.y / clientRect.height
                    f *= .scrollSize.y
                    .setScrollPos(.view.scrollPos.x, f)
                }
                elif .isHotBarH
                {
                    .correcMoving = 0
                    .isPressedH   = true
                    var f = pos.x / clientRect.width
                    f *= .scrollSize.x
                    .setScrollPos(f, .view.scrollPos.y)
                }

                .oldMouseCapture = .mouseCapture()
                .captureMouse()
                .invalidate()
            }

        case .Released:
            if .isGrabbing and evt.button == .Middle
            {
                .releaseMouse()
                if .oldMouseCapture do
                    .oldMouseCapture.captureMouse()
                .hitTest(evt.surfacePos)
                .invalidate()
                .isGrabbing = false
            }
            elif .isMoving and evt.button == .Left
            {
                .releaseMouse()
                if .oldMouseCapture do
                    .oldMouseCapture.captureMouse()
                .isPressedV, .isPressedH, .isMoving = false
                .hitTest(evt.surfacePos)
                .invalidate()
            }
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let bc      = evt.paintContext
        let theme   = .theme()
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let rects   = .themeRects()

        var colorBk: Color
        switch
        {
        case .flags.has(.TransparentBars): break
        case bc.isDisabled:                colorBk = colors.scrollBar_DisabledBk
        default:                           colorBk = colors.scrollBar_Bk
        }

        // Vertical bar
        if .showBarV
        {
            var clientRect = .clientRect()
            clientRect.x     = clientRect.right() - .paddingZ
            clientRect.width = .paddingZ
            if .showBarH do
                clientRect.height -= .paddingW
            theme.drawSubRect(bc.painter, clientRect, &rects.scrollBar_BkV, colorBk)

            var colBk = colors.scrollBar_HotBk
            if !.isHotBarV do
                colBk.a = 0
            .aniBkBarV.apply(me, colBk)
            theme.drawSubRect(bc.painter, clientRect, &rects.scrollBar_BkV, .aniBkBarV.cur())

            if .needV
            {
                clientRect.y      = .posBoxV
                clientRect.height = .sizeBoxV

                var colorBox: Color
                if .isHotV and .isPressedV do
                    colorBox = colors.scrollBar_PressedBox
                elif .isHotV do
                    colorBox = colors.scrollBar_HotBox
                else do
                    colorBox = colors.scrollBar_Box
                clientRect.inflate(-metrics.scrollBar_BoxPadding)
                .aniBoxV.apply(me, colorBox)
                theme.drawSubRect(bc.painter, clientRect, &rects.scrollBar_BoxV, .aniBoxV.cur())
            }
        }

        // Horizontal bar
        if .showBarH
        {
            var clientRect = .clientRect()
            clientRect.y      = clientRect.bottom() - .paddingW
            clientRect.height = .paddingW
            if .showBarV do
                clientRect.width -= .paddingW
            theme.drawSubRect(bc.painter, clientRect, &rects.scrollBar_BkH, colorBk)

            var colBk = colors.scrollBar_HotBk
            if !.isHotBarH do
                colBk.a = 0
            .aniBkBarH.apply(me, colBk)
            theme.drawSubRect(bc.painter, clientRect, &rects.scrollBar_BkH, .aniBkBarH.cur())

            if .needH
            {
                clientRect.x     = .posBoxH
                clientRect.width = .sizeBoxH

                var colorBox: Color
                if .isHotH and .isPressedH do
                    colorBox = colors.scrollBar_PressedBox
                elif .isHotH do
                    colorBox = colors.scrollBar_HotBox
                else do
                    colorBox = colors.scrollBar_Box
                clientRect.inflate(-metrics.scrollBar_BoxPadding)
                .aniBoxH.apply(me, colorBox)
                theme.drawSubRect(bc.painter, clientRect, &rects.scrollBar_BoxH, .aniBoxH.cur())
            }
        }

        // Corner
        if .showBarV and .showBarH
        {
            var clientRect = .clientRect()
            clientRect.x      = clientRect.right() - .paddingZ
            clientRect.y      = clientRect.bottom() - .paddingW
            clientRect.width  = .paddingZ
            clientRect.height = .paddingW
            theme.drawSubRect(bc.painter, clientRect, &rects.scrollBar_Corner, colors.scrollBar_Bk)
        }
    }
}

impl ScrollWnd
{
    mtd hitTest(surfacePos: Math.Point)
    {
        let pos = .surfaceToLocal(surfacePos)
        if .isHotV or .isHotH or .isHotBarV or .isHotBarH
        {
            .invalidate()
            .isHotV, .isHotH, .isHotBarV, .isHotBarH = false
        }

        var rect = .verticalThumbRect()
        if rect.contains(pos)
        {
            .isHotV, .isHotBarV = true
            .invalidate()
            return
        }

        rect = .horizontalThumbRect()
        if rect.contains(pos)
        {
            .isHotH, .isHotBarH = true
            .invalidate()
            return
        }

        rect = .verticalThumbRect(true)
        if rect.contains(pos)
        {
            .isHotBarV = true
            .invalidate()
            return
        }

        rect = .horizontalThumbRect(true)
        if rect.contains(pos)
        {
            .isHotBarH = true
            .invalidate()
            return
        }
    }

    mtd verticalThumbRect(full = false)->Math.Rectangle
    {
        var result: retval = .clientRect()
        result.x     = result.right() - .paddingZ
        result.width = .paddingZ
        if !full
        {
            result.y      = .posBoxV
            result.height = .sizeBoxV
        }

        return result
    }

    mtd horizontalThumbRect(full = false)->Math.Rectangle
    {
        var result: retval = .clientRect()
        result.y      = result.bottom() - .paddingW
        result.height = .paddingW
        if !full
        {
            result.x     = .posBoxH
            result.width = .sizeBoxH
        }

        return result
    }

    mtd computeLayout()
    {
        if .position.width == 0 or .position.height == 0 do
            return
        let clientRect = .paddedClientRect()
        let metrics    = .themeMetrics()
        let barSize    = .flags.has(.CompactBars) ? metrics.scrollBar_SmallSize : metrics.scrollBar_NormalSize
        var sx         = Math.max(.scrollSize.x, clientRect.width)
        var sy         = Math.max(.scrollSize.y, clientRect.height)

        .showBarV, .showBarH = false
        .needH, .needV       = false

        if sy > clientRect.height do
            .needV = true
        if .needV or .flags.has(.AlwaysShowVertical) do
            .showBarV = true

        if !.flags.has(.DisableHorizontal) and sx > clientRect.width do
            .needH = true
        if .needH or .flags.has(.AlwaysShowHorizontal) do
            .showBarH = true

        if !.flags.has(.DisableHorizontal) and .showBarV and .scrollSize.x > clientRect.width - barSize do
            .needH = true
        if .needH or .flags.has(.AlwaysShowHorizontal) do
            .showBarH = true

        if .showBarH and .scrollSize.y > clientRect.height - barSize do
            .needV = true
        if .needV or .flags.has(.AlwaysShowVertical) do
            .showBarV = true

        .paddingZ, .paddingW = 0
        if .showBarV do
            .paddingZ = barSize
        if .showBarH do
            .paddingW = barSize

        let viewWidth  = Math.max(clientRect.width - .paddingZ, 1)
        let viewHeight = Math.max(clientRect.height - .paddingW, 1)
        sx = Math.max(.scrollSize.x, viewWidth)
        sy = Math.max(.scrollSize.y, viewHeight)

        if .showBarV
        {
            let vh0 = viewHeight
            var vh1 = .position.height - .paddingW
            .sizeBoxV = (vh0 / sy) * vh1
            if .sizeBoxV < metrics.scrollBar_BoxMinSize
            {
                .offsetClientV = metrics.scrollBar_BoxMinSize - .sizeBoxV
                vh1            -= .offsetClientV
                .sizeBoxV      = metrics.scrollBar_BoxMinSize
            }

            .posBoxV = .view.scrollPos.y / sy
            .posBoxV *= vh1

            if .view.scrollPos.y > .scrollSize.y - viewHeight do
                .view.scrollPos.y = Math.max(.scrollSize.y - viewHeight, 0)
        }

        if .showBarH
        {
            let vh0 = viewWidth
            var vh1 = .position.width - .paddingZ
            .sizeBoxH = (vh0 / sx) * vh1
            if .sizeBoxH < metrics.scrollBar_BoxMinSize
            {
                .offsetClientH = metrics.scrollBar_BoxMinSize - .sizeBoxH
                vh1            -= .offsetClientH
                .sizeBoxH      = metrics.scrollBar_BoxMinSize
            }

            .posBoxH = .view.scrollPos.x / sx
            .posBoxH *= vh1

            if .view.scrollPos.x > .scrollSize.x - viewWidth do
                .view.scrollPos.x = Math.max(.scrollSize.x - viewWidth, 0)
        }

        .invalidate()
    }
}

public impl ScrollWnd
{
    // Returns the current viewport origin in content coordinates.
    mtd const scrollPosition()->Math.Point
    {
        return .view.scrollPos
    }

    private mtd scrollPositionPrivate(x, y: f32)->Math.Point
    {
        var newSP: Math.Point

        let clientRect = .view.clientRect()
        newSP.x = Math.max(x, 0)
        newSP.y = Math.max(y, 0)
        newSP.x = Math.min(newSP.x, .scrollSize.x - clientRect.width)
        newSP.y = Math.min(newSP.y, .scrollSize.y - clientRect.height)
        newSP.x = Math.max(newSP.x, 0)
        newSP.y = Math.max(newSP.y, 0)
        newSP.x = Math.round(newSP.x)
        newSP.y = Math.round(newSP.y)

        return newSP
    }

    private mtd setScrollPosPrivate(x, y: f32)->Math.Point
    {
        let newSP = .scrollPositionPrivate(x, y)
        if newSP == .view.scrollPos do
            return newSP
        let oldPos = .view.scrollPos
        .view.scrollPos = newSP
        .sigScrollPositionChanged.call(me, oldPos, newSP)
        .computeLayout()
        return newSP
    }

    // Sets and clamps the viewport origin in content coordinates.
    mtd setScrollPos(pt: Math.Point)
    {
        .setScrollPos(pt.x, pt.y)
    }

    mtd setScrollPos(x, y: f32)
    {
        .app().animator.cancel(me, AnimationChannel.from("Gui.Scroll.Position"))
        let newSP = .setScrollPosPrivate(x, y)
        .scrollRequestPos = newSP
    }

    // Sets the non-negative virtual content size and clamps the current position.
    mtd setScrollSize(x, y: f32)
    {
        let newSize = Math.Point{Math.max(x, 0), Math.max(y, 0)}
        if .scrollSize == newSize do
            return

        let oldScrollSize = .scrollSize
        .scrollSize = newSize
        .setScrollPos(.view.scrollPos.x, .view.scrollPos.y)
        .sigScrollSizeChanged.call(me, oldScrollSize, .scrollSize)
        .sendResizeEvent()
    }

    // Adds and removes scrollbar options and immediately recomputes the viewport.
    mtd updateFlags(add: ScrollWndFlags = .None, remove = ScrollWndFlags.None)
    {
        .flags.add(add)
        .flags.remove(remove)
        .sendResizeEvent()
    }

    // Returns the complete virtual content rectangle.
    mtd const scrollableClientRect()->Math.Rectangle
    {
        var result: retval
        result.width  = Math.max(.scrollSize.x, .view.position.width)
        result.height = Math.max(.scrollSize.y, .view.position.height)
        return result
    }
}
