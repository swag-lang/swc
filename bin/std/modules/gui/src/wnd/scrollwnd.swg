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
        using frameWnd: FrameWnd     // Frame hosting the scrolled view.

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
    offsetClientV: f32      // Travel the vertical thumb loses to its minimum size.
    offsetClientH: f32      // Travel the horizontal thumb loses to its minimum size.
    paddingZ:      f32      // Width the vertical bar takes from the view.
    paddingW:      f32      // Height the horizontal bar takes from the view.

    aniBkBarV: BlendColor     // Hover color of the vertical track.
    aniBkBarH: BlendColor     // Hover color of the horizontal track.
    aniBoxV:   BlendColor     // Color of the vertical thumb.
    aniBoxH:   BlendColor     // Color of the horizontal thumb.

    grabbingPos: Math.Point     // Pointer position at the last step of a middle-button pan.
}

public impl IWnd for ScrollWnd
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .computeLayout()
        if .view == null do
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
            if evt.modifiers & .Shift or not .showBarV do
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
                .scrollRequestPos = .clampedScrollPos(scroll.x, scroll.y)
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
        case bc.isDisabled: colorBk = colors.scrollBar_DisabledBk
        default: colorBk = colors.scrollBar_Bk
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
            if not .isHotBarV do
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
            if not .isHotBarH do
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
        if not full
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
        if not full
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

        if not .flags.has(.DisableHorizontal) and sx > clientRect.width do
            .needH = true
        if .needH or .flags.has(.AlwaysShowHorizontal) do
            .showBarH = true

        if not .flags.has(.DisableHorizontal) and .showBarV and .scrollSize.x > clientRect.width - barSize do
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
                                                      func|scrollWnd=me, origin, distance, tangent, duration|(animationWnd, progress)
                                                      {
                                                          discard animationWnd
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

    // Moves the view to the clamped position without touching a running glide, and returns it.
    private mtd applyScrollPos(x, y: f32)->Math.Point
    {
        let newSP = .clampedScrollPos(x, y)
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
        if not .app().animator.isActive(.scrollAnimation) or position != .view.scrollPos or target != .scrollRequestPos do
            .setScrollPos(position)
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
