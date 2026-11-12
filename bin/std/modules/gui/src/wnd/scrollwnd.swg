using Core, Pixel

// Configures scrollbar presentation and visibility.
#[Swag.EnumFlags]
public enum ScrollWndFlags
{
    None = 0                 // Reserves a gutter for each overflowing axis.
    AlwaysShowHorizontal     // Keeps the horizontal bar visible without overflow.
    AlwaysShowVertical       // Keeps the vertical bar visible without overflow.
    TransparentBars          // Omits the scrollbar track background.
    DisableHorizontal        // Never exposes horizontal scrolling, even when content is wider.
    HideBars                 // Keeps the viewport scrollable without painting or hitting bars.
}

// Hosts one view in a scrollable viewport with bars in their own edge gutters.
//
// A bar reserves its gutter while content overflows. A padded parent lets the control
// grow into its trailing or bottom padding, so the view keeps its size and leading edge.
public struct ScrollWnd
{
    public
    {
        using frameWnd: FrameWnd     // Frame hosting the scrolled view.

        verticalScrollStep:   f32 = 50     // Vertical distance applied per mouse-wheel notch.
        horizontalScrollStep: f32 = 50     // Horizontal distance applied per shifted wheel notch.

        readonly
        {
            scrollSize: Math.Point          // Virtual content size.
            flags = ScrollWndFlags.None     // Active scrollbar options.
        }

        sigScrollPositionChanged: SigArray'func||(*Wnd, Math.Point, Math.Point)     // Emitted with old and new scroll positions.
        sigScrollSizeChanged:     SigArray'func||(*Wnd, Math.Point, Math.Point)     // Emitted with old and new virtual sizes.
    }

    // Scrollbar geometry, hover and drag state, and the color animations that follow them.
    // The layout pass and the mouse events maintain all of it; scroll with `setScrollPos`
    // and connect to the signals to react.
    oldMouseCapture: *Wnd?     // Window that held the pointer capture before a drag took it.

    scrollRequestPos: Math.Point     // Destination of the running glide, or the current position.
    scrollVelocity:   Math.Point     // Logical units per second, retained when a glide is retargeted.
    scrollAnimation:  AnimationHandle

    showBarV:   bool     // Whether the vertical bar is shown.
    needV:      bool     // Whether the content overflows vertically, so the bar carries a thumb.
    posBoxV:    f32      // Top of the vertical thumb, in local units.
    sizeBoxV:   f32      // Height of the vertical thumb.
    isHotV:     bool     // Whether the pointer is over the vertical thumb.
    isHotBarV:  bool     // Whether the pointer is over the vertical track.
    isPressedV: bool     // Whether the vertical thumb is being dragged.

    showBarH:   bool     // Whether the horizontal bar is shown.
    needH:      bool     // Whether the content overflows horizontally, so the bar carries a thumb.
    posBoxH:    f32      // Left of the horizontal thumb, in local units.
    sizeBoxH:   f32      // Width of the horizontal thumb.
    isHotH:     bool     // Whether the pointer is over the horizontal thumb.
    isHotBarH:  bool     // Whether the pointer is over the horizontal track.
    isPressedH: bool     // Whether the horizontal thumb is being dragged.

    isMoving:      bool     // Whether a thumb is being dragged with the left button.
    isGrabbing:    bool     // Whether the content is being panned with the middle button.
    correcMoving:  f32      // Offset of the pointer inside the dragged thumb.
    barWidthV:     f32      // Width reserved for the vertical bar.
    barHeightH:    f32      // Height reserved for the horizontal bar.
    balanceX:      f32      // Width borrowed from the parent's trailing padding.
    balanceY:      f32      // Height borrowed from the parent's bottom padding.

    // A view can update its extent while it is being resized. Finish that one
    // resize before computing the bars from the resulting extent.
    layingView:      bool

    aniBkBarV: BlendColor     // Hover color of the vertical track.
    aniBkBarH: BlendColor     // Hover color of the horizontal track.
    aniBoxV:   BlendColor     // Color of the vertical thumb.
    aniBoxH:   BlendColor     // Color of the horizontal thumb.

    grabbingPos: Math.Point     // Pointer position at the last step of a middle-button pan.

    // A quiet thumb remains in its gutter at rest; motion and hover bring it to full contrast.
    barPresence: f32         // Animated bar presence before the resting visibility floor is applied.
    restTimer:   *Timer?     // Pending fade of the bars.
    barExpansionV: f32       // Animated extra thickness of the vertical bar.
    barExpansionH: f32       // Animated extra thickness of the horizontal bar.
}

public impl IWnd for ScrollWnd
{
    mtd impl onCreateEvent(_: *CreateEvent)
    {
        .wndFlags.add(.AfterChildrenPaint)
        .hookOnChildEvent = func(wnd, evt)->bool => onHookChildEvent(wnd, evt)
    }

    mtd impl onTimerEvent(_: *TimerEvent)
    {
        .restTimer = null

        // Pointer motion starts the rest timer; only an active drag keeps it alive.
        if .isMoving
        {
            .restTimer = .addTimer(Time.Duration.fromSeconds(.themeMetrics().motion_ScrollRest))
            return
        }

        var options: AnimationOptions
        options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_PageSeconds)
        options.easing   = .Linear
        discard .app().animator.animateF32(me, AnimationChannel.from("Gui.Scroll.Bars"), .barPresence,
                                           .themeMetrics().scrollBar_RestPresence,
                                           func(wnd, value) { wnd.barPresence = value }, options)
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        if .restTimer
        {
            .app().removeTimer(.restTimer)
            .restTimer = null
        }
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .layingView do
            return

        .layingView = true
        defer .layingView = false
        if .view == null do
            return
        .computeLayout()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let pos        = .surfaceToLocal(evt.surfacePos)

        switch evt.kind
        {
        case .Wheel:
            if evt.modifiers & .Shift or not .needV do
                .setScrollPos(.view.scrollPos.x - (evt.delta.y * .horizontalScrollStep), .view.scrollPos.y)
            else do
                .setScrollPos(.view.scrollPos.x, .view.scrollPos.y - (evt.delta.y * .verticalScrollStep))

        case .Leave:
            .isHotV, .isHotH, .isHotBarV, .isHotBarH = false
            .animateBarExpansion(true, true)
            .invalidate()

        case .Move:
            .revealScrollBars()
            if .isGrabbing
            {
                let move   = evt.surfacePos - .grabbingPos
                let scroll = .scrollRequestPos - move
                .scrollRequestPos = .clampedScrollPos(scroll.x, scroll.y)
                .grabbingPos      = evt.surfacePos

                var options: AnimationOptions
                options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_PanelSeconds)
                options.easing   = .EaseOut
                discard .app().animator.animatePointBorrowed(me,
                                                             AnimationChannel.from("Gui.Scroll.Position"),
                                                             &.view.scrollPos,
                                                             &.scrollRequestPos,
                                                             func|scrollWnd=me|(_, value)
                                                             {
                                                                 discard scrollWnd.applyScrollPos(value.x, value.y)
                                                             },
                                                             options)
                break
            }

            if not .isMoving
            {
                .hitTest(evt.surfacePos)
                break
            }

            if .isPressedV
            {
                let travel = Math.max(.view.position.height - .sizeBoxV, 1)
                let f = (pos.y - .correcMoving - .view.position.y) / travel *
                        Math.max(.scrollSize.y - .view.position.height, 0)
                .setScrollPos(.view.scrollPos.x, f)
            }
            elif .isPressedH
            {
                let travel = Math.max(.view.position.width - .sizeBoxH, 1)
                let f = (pos.x - .correcMoving - .view.position.x) / travel *
                        Math.max(.scrollSize.x - .view.position.width, 0)
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
            elif evt.button == .Left and (.isHotV or .isHotH or .isHotBarV or .isHotBarH)
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
                    let travel = Math.max(.view.position.height - .sizeBoxV, 1)
                    let f = (pos.y - .view.position.y) / travel *
                            Math.max(.scrollSize.y - .view.position.height, 0)
                    .setScrollPos(.view.scrollPos.x, f)
                }
                elif .isHotBarH
                {
                    .correcMoving = 0
                    .isPressedH   = true
                    let travel = Math.max(.view.position.width - .sizeBoxH, 1)
                    let f = (pos.x - .view.position.x) / travel *
                            Math.max(.scrollSize.x - .view.position.width, 0)
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
                .oldMouseCapture?.captureMouse()
                .hitTest(evt.surfacePos)
                .invalidate()
                .isGrabbing = false
            }
            elif .isMoving and evt.button == .Left
            {
                .releaseMouse()
                .oldMouseCapture?.captureMouse()
                .isPressedV, .isPressedH, .isMoving = false
                .hitTest(evt.surfacePos)
                .invalidate()
            }
        }
    }

    mtd impl onAfterPaint(evt: *PaintEvent)
    {
        .frameWnd.IWnd.onAfterPaint(evt)
        let bc      = evt.paintContext
        let theme   = .theme()
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let rects   = .themeRects()

        // The reserved gutter keeps a quiet thumb visible at rest.
        let presence = Math.max(.barPresence, metrics.scrollBar_RestPresence)
        if presence <= 0 do
            return

        var colorBk: Color
        switch
        {
        case .flags.has(.TransparentBars): break
        case bc.isDisabled: colorBk = colors.scrollBar_DisabledBk
        default: colorBk = colors.scrollBar_Bk
        }

        // Vertical bar
        if .showBarV
        {
            var clientRect = .barClientRect()
            let edge = clientRect.right() - metrics.scrollBar_EdgeInset
            clientRect.width = metrics.scrollBar_Size +
                               .barExpansionV * (metrics.scrollBar_HoverSize - metrics.scrollBar_Size)
            clientRect.x     = edge - clientRect.width
            clientRect.y      = .view.position.y
            clientRect.height = .view.position.height
            theme.drawSubRect(bc.painter, clientRect, &rects.scrollBar_BkV, fadeColor(colorBk, presence))

            var colBk = colors.scrollBar_HotBk
            if not .isHotBarV do
                colBk.a = 0
            .aniBkBarV.apply(me, colBk)
            theme.drawSubRect(bc.painter, clientRect, &rects.scrollBar_BkV, fadeColor(.aniBkBarV.cur(), presence))

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
                theme.drawSubRect(bc.painter, clientRect, &rects.scrollBar_BoxV, fadeColor(.aniBoxV.cur(), presence))
            }
        }

        // Horizontal bar
        if .showBarH
        {
            var clientRect = .barClientRect()
            let edge = clientRect.bottom() - metrics.scrollBar_EdgeInset
            clientRect.height = metrics.scrollBar_Size +
                                .barExpansionH * (metrics.scrollBar_HoverSize - metrics.scrollBar_Size)
            clientRect.y      = edge - clientRect.height
            clientRect.x     = .view.position.x
            clientRect.width = .view.position.width
            theme.drawSubRect(bc.painter, clientRect, &rects.scrollBar_BkH, fadeColor(colorBk, presence))

            var colBk = colors.scrollBar_HotBk
            if not .isHotBarH do
                colBk.a = 0
            .aniBkBarH.apply(me, colBk)
            theme.drawSubRect(bc.painter, clientRect, &rects.scrollBar_BkH, fadeColor(.aniBkBarH.cur(), presence))

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
                theme.drawSubRect(bc.painter, clientRect, &rects.scrollBar_BoxH, fadeColor(.aniBoxH.cur(), presence))
            }
        }

        // Corner
        if .showBarV and .showBarH
        {
            var clientRect = .barClientRect()
            clientRect.x      = clientRect.right() - metrics.scrollBar_EdgeInset - .barWidthV
            clientRect.y      = clientRect.bottom() - metrics.scrollBar_EdgeInset - .barHeightH
            clientRect.width  = .barWidthV
            clientRect.height = .barHeightH
            theme.drawSubRect(bc.painter, clientRect, &rects.scrollBar_Corner, fadeColor(colors.scrollBar_Bk, presence))
        }
    }
}

impl ScrollWnd
{
    mtd barClientRect()->Math.Rectangle
    {
        var result = .paddedClientRect()
        result.applyPadding(.view.margin)
        return result
    }

    // Motion over the content reveals the bar, while the reserved gutter owns its hit target.
    func onHookChildEvent(wnd: *Wnd, evt: IEvent)->bool
    {
        let scroll = assume cast(*ScrollWnd, wnd)
        if evt is MouseEvent as mouse
        {
            if mouse.kind == .Move or mouse.kind == .Pressed
            {
                if mouse.kind == .Move do
                    scroll.revealScrollBars()
                scroll.hitTest(mouse.surfacePos)
                if scroll.isHotV or scroll.isHotH or scroll.isHotBarV or scroll.isHotBarH
                {
                    if mouse.kind == .Pressed do
                        scroll.IWnd.onMouseEvent(mouse)
                    return true
                }
            }
        }

        return false
    }

    mtd hitTest(surfacePos: Math.Point)
    {
        let pos = .surfaceToLocal(surfacePos)
        let wasHotV = .isHotV or .isHotBarV
        let wasHotH = .isHotH or .isHotBarH
        defer .animateBarExpansion(wasHotV, wasHotH)
        if .isHotV or .isHotH or .isHotBarV or .isHotBarH
        {
            .invalidate()
            .isHotV, .isHotH, .isHotBarV, .isHotBarH = false
        }

        var rect = .verticalThumbRect()
        if .showBarV and .needV and rect.contains(pos)
        {
            .isHotV, .isHotBarV = true
            .revealScrollBars()
            .invalidate()
            return
        }

        rect = .horizontalThumbRect()
        if .showBarH and .needH and rect.contains(pos)
        {
            .isHotH, .isHotBarH = true
            .revealScrollBars()
            .invalidate()
            return
        }

        rect = .verticalThumbRect(true)
        if .showBarV and .needV and rect.contains(pos)
        {
            .isHotBarV = true
            .revealScrollBars()
            .invalidate()
            return
        }

        rect = .horizontalThumbRect(true)
        if .showBarH and .needH and rect.contains(pos)
        {
            .isHotBarH = true
            .revealScrollBars()
            .invalidate()
            return
        }
    }

    mtd verticalThumbRect(full = false)->Math.Rectangle
    {
        var result: #returntype = .barClientRect()
        let metrics = .themeMetrics()
        let right   = result.right()
        if full
        {
            result.width = metrics.scrollBar_HitSize
            result.x     = right - metrics.scrollBar_EdgeInset - result.width
            result.y = .view.position.y
            result.height = .view.position.height
        }
        else
        {
            result.width = metrics.scrollBar_Size
            result.x     = right - metrics.scrollBar_EdgeInset - result.width
        }
        if not full
        {
            result.y      = .posBoxV
            result.height = .sizeBoxV
        }

        return result
    }

    mtd horizontalThumbRect(full = false)->Math.Rectangle
    {
        var result: #returntype = .barClientRect()
        let metrics = .themeMetrics()
        let bottom  = result.bottom()
        if full
        {
            result.height = metrics.scrollBar_HitSize
            result.y      = bottom - metrics.scrollBar_EdgeInset - result.height
            result.x = .view.position.x
            result.width  = .view.position.width
        }
        else
        {
            result.height = metrics.scrollBar_Size
            result.y      = bottom - metrics.scrollBar_EdgeInset - result.height
        }
        if not full
        {
            result.x     = .posBoxH
            result.width = .sizeBoxH
        }

        return result
    }

    // Expands the painted bar after the pointer enters its larger hit target.
    mtd animateBarExpansion(wasHotV: bool, wasHotH: bool)
    {
        if wasHotV != (.isHotV or .isHotBarV)
        {
            var options: AnimationOptions
            options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_QuickSeconds)
            options.easing   = .EaseOut
            let target = (.isHotV or .isHotBarV) ? 1 : 0
            discard .app().animator.animateF32(me,
                                               AnimationChannel.from("Gui.Scroll.Width.V"),
                                               .barExpansionV,
                                               target,
                                               func(wnd, value) { wnd.barExpansionV = value },
                                               options)
        }

        if wasHotH != (.isHotH or .isHotBarH)
        {
            var options: AnimationOptions
            options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_QuickSeconds)
            options.easing   = .EaseOut
            let target = (.isHotH or .isHotBarH) ? 1 : 0
            discard .app().animator.animateF32(me,
                                               AnimationChannel.from("Gui.Scroll.Width.H"),
                                               .barExpansionH,
                                               target,
                                               func(wnd, value) { wnd.barExpansionH = value },
                                               options)
        }
    }

    mtd computeLayout()
    {
        if .position.width == 0 or .position.height == 0 do
            return
        let wasLaying = .layingView
        .layingView = true
        defer .layingView = wasLaying

        let metrics = .themeMetrics()
        let gutter  = metrics.scrollBar_HitSize + metrics.scrollBar_EdgeInset

        // A responsive view may have reported an extent for a narrower, previously
        // barred viewport. Measure it at full width first so a bar does not keep itself
        // alive after content would fit without one.
        .showBarV = false
        .showBarH = false
        var clientRect = .barClientRect()
        clientRect.width  = Math.max(clientRect.width - .balanceX, 1)
        clientRect.height = Math.max(clientRect.height - .balanceY, 1)
        if .view.position != clientRect do
            .view.setPosition(clientRect)
        var needV   = .scrollSize.y > clientRect.height
        var needH   = not .flags.has(.DisableHorizontal) and .scrollSize.x > clientRect.width

        // A bar owns its gutter. Check cross-axis overflow after each gutter appears.
        for index in 4
        {
            discard index
            .showBarV = not .flags.has(.HideBars) and (needV or .flags.has(.AlwaysShowVertical))
            .showBarH = not .flags.has(.HideBars) and (needH or .flags.has(.AlwaysShowHorizontal))
            .barWidthV  = .showBarV ? gutter : 0
            .barHeightH = .showBarH ? gutter : 0

            // Expand only the trailing edges into the room supplied by the parent.
            // The leading edges and the available view size stay fixed when a bar appears.
            let borrowX = .dockStyle == .Center and .parent and .showBarV ? Math.min(gutter, Math.max(.parent.padding.z, 0)) : 0
            let borrowY = .dockStyle == .Center and .parent and .showBarH ? Math.min(gutter, Math.max(.parent.padding.w, 0)) : 0
            if borrowX != .balanceX or borrowY != .balanceY
            {
                .margin.z += .balanceX - borrowX
                .margin.w += .balanceY - borrowY
                .balanceX = borrowX
                .balanceY = borrowY
                if .parent do
                    .parent.applyLayout()
            }
            clientRect = .barClientRect()

            var viewport = clientRect
            viewport.width  = Math.max(viewport.width - .barWidthV, 1)
            viewport.height = Math.max(viewport.height - .barHeightH, 1)
            if viewport != .view.position do
                .view.setPosition(viewport)

            let nextV = needV or .scrollSize.y > viewport.height
            let nextH = needH or (not .flags.has(.DisableHorizontal) and .scrollSize.x > viewport.width)
            if nextV == needV and nextH == needH do
                break
            needV = nextV
            needH = nextH
        }

        .needV = needV
        .needH = needH
        let viewWidth  = .view.position.width
        let viewHeight = .view.position.height
        if .showBarV
        {
            let virtualHeight = Math.max(.scrollSize.y, viewHeight)
            .sizeBoxV = Math.min(viewHeight, Math.max(metrics.scrollBar_BoxMinSize,
                                                     viewHeight * viewHeight / virtualHeight))
            let range  = Math.max(.scrollSize.y - viewHeight, 0)
            .view.scrollPos.y = Math.clamp(.view.scrollPos.y, 0, range)
        }

        if .showBarH
        {
            let virtualWidth = Math.max(.scrollSize.x, viewWidth)
            .sizeBoxH = Math.min(viewWidth, Math.max(metrics.scrollBar_BoxMinSize,
                                                    viewWidth * viewWidth / virtualWidth))
            let range  = Math.max(.scrollSize.x - viewWidth, 0)
            .view.scrollPos.x = Math.clamp(.view.scrollPos.x, 0, range)
        }

        .positionThumbs()
    }

    mtd positionThumbs()
    {
        if .showBarV
        {
            let range  = Math.max(.scrollSize.y - .view.position.height, 0)
            let travel = Math.max(.view.position.height - .sizeBoxV, 0)
            .posBoxV = .view.position.y + (range > 0 ? .view.scrollPos.y / range * travel : 0)
        }
        if .showBarH
        {
            let range  = Math.max(.scrollSize.x - .view.position.width, 0)
            let travel = Math.max(.view.position.width - .sizeBoxH, 0)
            .posBoxH = .view.position.x + (range > 0 ? .view.scrollPos.x / range * travel : 0)
        }
        .invalidate()
    }
}

public impl ScrollWnd
{
    // Returns the current viewport origin in content coordinates.
    mtd const scrollPosition()->Math.Point => .view.scrollPos

    // Returns where a running smooth scroll is heading, which is the current position when none is running.
    mtd const scrollTarget()->Math.Point => .scrollRequestPos

    // Glides to `pt` over the surface's panel motion instead of jumping there.
    //
    // The target is clamped exactly as [[Gui.ScrollWnd.setScrollPos]] clamps one. A call made
    // while a previous glide is still running retains its position and forward velocity, so
    // repeated steps — wheel notches, held arrows — accumulate into one continuous movement
    // rather than restarting at each of them. Read [[Gui.ScrollWnd.scrollTarget]] to compose the
    // next step on top of the one in flight.
    mtd smoothScrollTo(pt: Math.Point)
    {
        let target   = .clampedScrollPos(pt.x, pt.y)
        let origin   = .view.scrollPos
        let distance = target - origin
        let duration = .themeMetrics().motion_PanelSeconds
        var tangent  = distance * 3
        if .app().animator.isActive(.scrollAnimation)
        {
            // A Hermite segment arrives at rest. Bound its outgoing tangent to keep it
            // monotone, and discard momentum pointing away from a reversed request.
            tangent.x = distance.x * .scrollVelocity.x > 0 ? Math.sign(distance.x) * Math.min(Math.abs(.scrollVelocity.x * duration), Math.abs(distance.x * 3)) : 0
            tangent.y = distance.y * .scrollVelocity.y > 0 ? Math.sign(distance.y) * Math.min(Math.abs(.scrollVelocity.y * duration), Math.abs(distance.y * 3)) : 0
        }

        // The scalar track is elapsed progress, not a scroll coordinate. Its new segment
        // starts at zero; the retained tangent carries momentum across the replacement.
        .app().animator.cancel(me, AnimationChannel.from("Gui.Scroll.Position"))
        .scrollRequestPos = target
        if target == origin or duration <= 0
        {
            .setScrollPos(target)
            return
        }

        var options: AnimationOptions
        options.duration = Time.Duration.fromSeconds(duration)
        options.easing   = .Linear
        .scrollAnimation = .app().animator.animateF32(me,
                                                      AnimationChannel.from("Gui.Scroll.Position"),
                                                      0,
                                                      1,
                                                      func|scrollWnd=me, origin, distance, tangent, duration|(_, progress)
                                                      {
                                                          let t2    = progress * progress
                                                          let t3    = t2 * progress
                                                          let value = origin + distance * (3 * t2 - 2 * t3) + tangent * (t3 - 2 * t2 + progress)
                                                          scrollWnd.scrollVelocity = (distance * (6 * progress - 6 * t2) + tangent * (3 * t2 - 4 * progress + 1)) / duration
                                                          discard scrollWnd.applyScrollPos(value.x, value.y)
                                                      },
                                                      options)
    }

    // Returns `x`, `y` clamped to the scrollable range and rounded to whole logical units.
    private mtd clampedScrollPos(x, y: f32)->Math.Point
    {
        var newSP: Math.Point

        let clientRect = .view.clientRect()
        newSP.x = .flags.has(.DisableHorizontal) ? 0 : Math.max(x, 0)
        newSP.y = Math.max(y, 0)
        if not .flags.has(.DisableHorizontal) do
            newSP.x = Math.min(newSP.x, .scrollSize.x - clientRect.width)
        newSP.y = Math.min(newSP.y, .scrollSize.y - clientRect.height)
        if not .flags.has(.DisableHorizontal) do
            newSP.x = Math.max(newSP.x, 0)
        newSP.y = Math.max(newSP.y, 0)
        if not .flags.has(.DisableHorizontal) do
            newSP.x = Math.round(newSP.x)
        newSP.y = Math.round(newSP.y)

        return newSP
    }

    // Briefly reveals the available scrollbars and restarts their normal fade delay.
    //
    // A composite can call this when its content is hovered or receives keyboard focus, so
    // scrolling is discoverable at full contrast. This changes neither layout nor scroll
    // position and has no effect before the window belongs to a surface.
    mtd revealScrollBars()
    {
        // A view not yet on a surface has no bars to show and no clock to count stillness on.
        if not .surface do
            return

        if .barPresence < 1
        {
            var options: AnimationOptions
            options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_QuickSeconds)
            options.easing   = .EaseOut
            discard .app().animator.animateF32(me, AnimationChannel.from("Gui.Scroll.Bars"), .barPresence, 1, func(wnd, value) { wnd.barPresence = value }, options)
        }

        if .restTimer do
            .app().removeTimer(.restTimer)
        .restTimer = .addTimer(Time.Duration.fromSeconds(.themeMetrics().motion_ScrollRest))
    }

    // Moves the view to the clamped position without touching a running glide, and returns it.
    private mtd applyScrollPos(x, y: f32)->Math.Point
    {
        let newSP = .clampedScrollPos(x, y)
        if newSP == .view.scrollPos do
            return newSP
        let oldPos = .view.scrollPos
        .view.scrollPos = newSP
        .sigScrollPositionChanged.call(me, oldPos, newSP)
        .positionThumbs()
        .revealScrollBars()
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
        .scrollVelocity   = {}
        .scrollRequestPos = .applyScrollPos(x, y)
    }

    // Sets the non-negative virtual content size and clamps the current position.
    mtd setScrollSize(x, y: f32)
    {
        let newSize = Math.Point{Math.max(x, 0), Math.max(y, 0)}
        if .scrollSize == newSize do
            return

        let oldScrollSize = .scrollSize
        .scrollSize = newSize

        // Appending streamed content must not cancel the glide or discard its velocity.
        // Only a size that clips the current position or destination interrupts it.
        let position = .clampedScrollPos(.view.scrollPos.x, .view.scrollPos.y)
        let target   = .clampedScrollPos(.scrollRequestPos.x, .scrollRequestPos.y)
        if not .app().animator.isActive(.scrollAnimation) or
           position != .view.scrollPos or
           target != .scrollRequestPos do
            .setScrollPos(position)
        .sigScrollSizeChanged.call(me, oldScrollSize, .scrollSize)
        .sendResizeEvent()
    }

    // Adds and removes scrollbar options and immediately recomputes the viewport.
    mtd updateFlags(add: ScrollWndFlags = .None, remove = ScrollWndFlags.None)
    {
        .flags.add(add)
        .flags.remove(remove)
        if .flags.has(.DisableHorizontal) and
           .view != null and
           (.view.scrollPos.x != 0 or .scrollRequestPos.x != 0) do
            .setScrollPos(0, .view.scrollPos.y)
        .sendResizeEvent()
    }

    // Returns the complete virtual content rectangle.
    mtd const scrollableClientRect()->Math.Rectangle
    {
        var result: #returntype
        result.width  = Math.max(.scrollSize.x, .view.position.width)
        result.height = Math.max(.scrollSize.y, .view.position.height)
        return result
    }
}
