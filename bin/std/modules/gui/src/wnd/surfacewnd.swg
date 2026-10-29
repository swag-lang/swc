using Core, Pixel, Serialization

// Identifies the edges of a surface a pointer position resizes; a corner combines two.
#[Swag.EnumFlags]
public enum SizingBorder
{
    None = 0     // Not over a sizing border.
    Left         // Left edge.
    Top          // Top edge.
    Right        // Right edge.
    Bottom       // Bottom edge.
}

// Reports whether a surface position, under the strip, is ground of the window that drags it.
public alias GroundHitTest = func||(Math.Point)->bool

// Provides the root GUI frame and the window chrome of a [[Gui.Surface]].
//
// The chrome follows the charter: no caption band, no rail and no glow. The top strip carries
// only a faint application glyph, the title centred in small faint type, and faint window
// buttons, and it stays draggable wherever no control sits.
//
// On an application window ([[Gui.SurfaceFlags.LargeCaption]]) the view takes the whole body and
// the strip floats over it, so a document can start under the title. A part of the content that
// must keep clear of the chrome — a band of controls, a page header, a form — insets itself by
// [[Gui.Wnd.stripInset]]. A dialog or a tool window ([[Gui.SurfaceFlags.SmallCaption]]) keeps its
// compact strip above the view.
public struct SurfaceWnd
{
    public
    {
        using base:    FrameWnd                // Frame hosting the surface view.
        icon:          Icon                    // Glyph at the leading corner, drawn in the chrome's one ink; an invalid one shows the application glyph.
        minimizeBtn:   *IconButton?            // Caption minimize button, present with [[Gui.SurfaceFlags.MinimizeButton]].
        maximizeBtn:   *IconButton?            // Caption maximize button, present with [[Gui.SurfaceFlags.MaximizeButton]].
        closeBtn:      *IconButton?            // Caption close button, present with [[Gui.SurfaceFlags.CloseButton]].
        movingSurface: bool                    // Whether a pointer drag is moving or resizing the surface.
        groundHitTest: GroundHitTest?          // Answers, under the strip, whether a surface position is ground that drags the window.
        sizingBorder:  SizingBorder = None     // Border under the pointer, or being dragged.

        readonly titleHidden: bool     // Whether the document writes the title itself, so the strip does not.
    }

    captionButtons: Array'(*IconButton)     // Application actions immediately before the native caption controls.
}

impl IWnd for SurfaceWnd
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let srfn = unwrap .surface
        switch evt.kind
        {
        case .Pressed:
            if evt.button != .Left do
                break
            srfn.bringToFront()
            if srfn.isMaximized do
                break
            if srfn.flags.has(.Resizable) do
                .sizingBorder = .hitTestBorders(evt.surfacePos)
            else do
                .sizingBorder = .None
            if .sizingBorder == .None and not .hitTestCaption(evt.surfacePos) do
                break
            .captureMouse()
            .movingSurface = true

        case .Leave:
            .sizingBorder = .None

        case .Released:
            if evt.button != .Left do
                break

            .releaseMouse()
            .movingSurface = false
            .sizingBorder  = .None
            fallthrough

        case .Move:
            if srfn.isMaximized do
                break
            if .app().mouseEnterWnd != me do
                break

            if not .movingSurface and srfn.flags.has(.Resizable)
            {
                let newSizingBorder = .hitTestBorders(evt.surfacePos)
                if newSizingBorder != .sizingBorder do
                    .sizingBorder = newSizingBorder
            }

            switch .sizingBorder
            {
            case .Left, .Right:              srfn.app.setFrameCursor(Cursor.from(.ResizeHorizontal))
            case .Top, .Bottom:              srfn.app.setFrameCursor(Cursor.from(.ResizeVertical))
            case Right | Bottom, Left | Top: srfn.app.setFrameCursor(Cursor.from(.ResizeNorthwestSoutheast))
            case Right | Top, Left | Bottom: srfn.app.setFrameCursor(Cursor.from(.ResizeNortheastSouthwest))
            }

            if not .movingSurface do
                break

            // The event delta is logical; the surface rectangle it moves is in
            // physical screen pixels.
            var hasChanged = false
            var pos        = srfn.position
            let dx         = evt.delta.x * srfn.dpiScale
            let dy         = evt.delta.y * srfn.dpiScale

            if .sizingBorder & .Left
            {
                pos.x      += dx
                pos.width  -= dx
                hasChanged = true
            }

            if .sizingBorder & .Top
            {
                pos.y      += dy
                pos.height -= dy
                hasChanged = true
            }

            if .sizingBorder & .Right
            {
                pos.width  += dx
                hasChanged = true
            }

            if .sizingBorder & .Bottom
            {
                pos.height += dy
                hasChanged = true
            }

            if .sizingBorder == .None
            {
                pos.offset(dx, dy)
                hasChanged = true
            }

            if hasChanged
            {
                srfn.setPosition(pos)
                srfn.invalidate()
            }
        }
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        let surface = unwrap .surface
        surface.app.destroySurface(surface)
    }

    mtd impl onSysCommandEvent(evt: *SysCommandEvent)
    {
        let srfn = unwrap .surface
        switch evt.kind
        {
        case .Maximize:
            srfn.showMaximized()

        case .Minimize:
            srfn.showMinimized()

        case .Restore:
            if srfn.isMinimized and srfn.isMaximized do
                srfn.showMaximized()
            else do
                srfn.showNormal()

        case .Close:
            srfn.destroy()
        }
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        let clientRect = .clientRect()
        let metrics    = .themeMetrics()

        var buttonCount = 0'u32
        if .closeBtn do
            buttonCount += 1
        if .maximizeBtn do
            buttonCount += 1
        if .minimizeBtn do
            buttonCount += 1
        for button in .captionButtons where isShownCaptionButton(button) do
            buttonCount += 1
        var gapCount = buttonCount > 0 ? buttonCount - 1 : 0

        // The buttons keep one size whatever the height of the strip, and sit on its middle line
        // with the glyph and the title.
        let strip = .stripHeight()
        var pos   = clientRect
        pos.height = Math.max(0, Math.min(strip - 2 * metrics.wnd_CaptionButtonMargin, metrics.wnd_CaptionButtonHeight))
        pos.width  = Math.max(metrics.wnd_CaptionButtonMinWidth, pos.height * metrics.wnd_CaptionButtonAspect)
        pos.x      = clientRect.right() - pos.width - metrics.wnd_CaptionButtonMargin
        pos.y      = Math.round((strip - pos.height) * 0.5)

        if .closeBtn
        {
            .closeBtn.setPosition(pos)
            pos.x -= pos.width
            if gapCount > 0
            {
                pos.x    -= metrics.wnd_CaptionButtonGap
                gapCount -= 1
            }
        }

        if .maximizeBtn
        {
            .maximizeBtn.setPosition(pos)
            pos.x -= pos.width
            if gapCount > 0
            {
                pos.x    -= metrics.wnd_CaptionButtonGap
                gapCount -= 1
            }
        }

        if .minimizeBtn
        {
            .minimizeBtn.setPosition(pos)
            pos.x -= pos.width
            if gapCount > 0
            {
                pos.x    -= .hasShownCaptionButton() ? metrics.wnd_CaptionActionGap : metrics.wnd_CaptionButtonGap
                gapCount -= 1
            }
        }

        var buttonRight = pos.x + pos.width
        for button in .captionButtons
        {
            if not isShownCaptionButton(button) do
                continue
            var appButtonPos = pos
            appButtonPos.width = Math.max(metrics.wnd_CaptionButtonGlyph + 2 * metrics.wnd_CaptionButtonMargin, pos.height * 0.75)
            appButtonPos.x     = buttonRight - appButtonPos.width
            button.setPosition(appButtonPos)
            buttonRight = appButtonPos.x
            if gapCount > 0
            {
                buttonRight -= metrics.wnd_CaptionActionGap
                gapCount    -= 1
            }
        }

        .base.IWnd.onResizeEvent(evt)
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let srfn = unwrap .surface
        if .isPendingDestroy do
            return
        let painter    = evt.paintContext.painter
        let clientRect = .clientRect()
        let radius     = srfn.cornerRadius()

        // The ground follows the silhouette the surface stamps into its alpha channel, so a
        // rounded surface never lays opaque ink outside its own corner. The outline is not
        // drawn here either: the surface strokes it above the whole hierarchy, see
        // Surface.paintBorder.
        if radius > 0 do
            painter.fillRoundRect(clientRect, radius, radius, .themeColors().wnd_Bk)
        else do
            painter.fillRect(clientRect, .themeColors().wnd_Bk)
    }

    // The glyph and the title are drawn once the view has painted, since the strip floats over
    // it: a document reaching the top edge passes under them.
    mtd impl onAfterPaint(evt: *PaintEvent)
    {
        if .isPendingDestroy or .stripHeight() <= 0 do
            return
        .paintTopStrip(evt.paintContext.painter)
    }
}

impl SurfaceWnd
{
    // Draws the chrome of the top strip on the ground the content sits on.
    //
    // There is no band to draw: the strip is the window's own ground, so the work reads as
    // starting at the top edge. What remains is quiet enough to read past — the application glyph
    // in one faint ink at the leading corner, and the title centred in small faint type, kept
    // clear of both the glyph and the buttons and cut with an ellipsis rather than run under them.
    private mtd paintTopStrip(painter: *Painter)
    {
        let srfn    = unwrap .surface
        let metrics = .themeMetrics()
        let colors  = .themeColors()

        var strip = .clientRect()
        strip.height = .stripHeight()

        var leading = strip.x + metrics.wnd_CaptionMarginTitle
        var icon    = .icon
        if not icon.isValid() do
            icon = srfn.app.appGlyph(metrics.wnd_CaptionIconSize)
        if icon.isValid()
        {
            icon.paint(painter, leading, strip.vertCenter() - icon.sizeY * 0.5, colors.wnd_CaptionMark)
            leading += icon.sizeX + metrics.wnd_CaptionMarginTitle
        }

        let center   = strip.horzCenter()
        let halfSpan = Math.min(center - leading, .chromeButtonsLeft() - metrics.wnd_CaptionMarginTitle - center)
        if halfSpan <= 0 or .name.isEmpty() or .titleHidden do
            return

        var sf: RichStringFormat
        sf.font          = .theme().createDefaultFontFamily(metrics.wnd_TitleFontSize)
        sf.horzAlignment = .Center
        sf.vertAlignment = .Center
        sf.flags         = .Ellipsis
        sf.palette[0]    = colors.wnd_CaptionText
        painter.drawRichString(Math.Rectangle{center - halfSpan, strip.y, 2 * halfSpan, strip.height}, &.name, sf)
    }

    // Leaves the title out of the strip, or writes it there again.
    //
    // A document that takes the whole window — a film — writes the title itself where it can be
    // read over its picture, and only while the reader asks for it; the strip then keeps the glyph
    // and the window buttons alone. The surface keeps its title for the system all the same.
    public mtd showTitle(shown: bool)
    {
        if .titleHidden == not shown do
            return
        .titleHidden = not shown
        .invalidate()
    }

    // Returns where the window buttons and the application actions beside them begin.
    private mtd chromeButtonsLeft()->f32
    {
        var result = .clientRect().right()
        if .closeBtn do
            result = Math.min(result, .closeBtn.position.x)
        if .maximizeBtn do
            result = Math.min(result, .maximizeBtn.position.x)
        if .minimizeBtn do
            result = Math.min(result, .minimizeBtn.position.x)
        for button in .captionButtons where isShownCaptionButton(button) do
            result = Math.min(result, button.position.x)
        return result
    }

    // The voice of every button in the top strip: a faint glyph that reaches full contrast under
    // the pointer, with no ground until it is pressed.
    private const ChromeButtonColors = """btnIcon_Icon         $wnd_BtnIcon
                                          btnIcon_HotIcon      $wnd_BtnHotIcon
                                          btnIcon_HotBk        $transparent
                                          btnIcon_PressedIcon  $wnd_BtnHotIcon
                                          btnIcon_PressedBk    $wnd_BtnPressedBk"""

    // Close has the same voice, but turns critical under the pointer, since it is the one that
    // destroys.
    private const CloseButtonColors = """btnIcon_Icon         $wnd_BtnIcon
                                         btnIcon_HotIcon      $wnd_BtnCloseHotIcon
                                         btnIcon_HotBk        $transparent
                                         btnIcon_PressedIcon  $wnd_BtnCloseHotIcon
                                         btnIcon_PressedBk    $wnd_BtnClosePressedBk"""

    mtd hitTestCaptionButton(surfacePos: Math.Point)->bool
    {
        let pos = .surfaceToLocal(surfacePos)
        if .closeBtn and .closeBtn.position.contains(pos.x, pos.y) do
            return true
        if .maximizeBtn and .maximizeBtn.position.contains(pos.x, pos.y) do
            return true
        if .minimizeBtn and .minimizeBtn.position.contains(pos.x, pos.y) do
            return true
        for button in .captionButtons where isShownCaptionButton(button)
        {
            if button.position.contains(pos.x, pos.y) do
                return true
        }

        return false
    }

    // Reports whether any application caption action is shown.
    private mtd hasShownCaptionButton()->bool
    {
        for button in .captionButtons where isShownCaptionButton(button) do
            return true
        return false
    }

    // Registers an application action in the caption, immediately before the native controls.
    internal mtd registerCaptionButton(button: *IconButton)
    {
        Swag.assert(button.parent == me)
        button.style.addStyleSheetColors(ChromeButtonColors)
        .captionButtons.add(button)
        .sendResizeEvent()
        .invalidate()
    }

    // Removes an application caption action before its deferred storage release.
    internal mtd unregisterCaptionButton(button: *IconButton)
    {
        .captionButtons.remove(button)
        if not .isPendingDestroy do
            .sendResizeEvent()
        .invalidate()
    }

    // Returns the height of the top strip, measured from the top edge of the window.
    //
    // On an application window ([[Gui.SurfaceFlags.LargeCaption]]) it is
    // [[Gui.ThemeMetrics.wnd_StripHeight]], and the strip floats over the view. On a dialog or a
    // tool window ([[Gui.SurfaceFlags.SmallCaption]]) it is the compact strip kept above the view.
    // It is zero on a surface without a caption, such as a window in full screen.
    mtd stripHeight()->f32
    {
        let srfn = .surface
        if not srfn do
            return 0
        if srfn.flags.has(.LargeCaption) do
            return .themeMetrics().wnd_StripHeight
        if srfn.flags.has(.SmallCaption) do
            return .padding.y
        return 0
    }

    // Reports whether the surface position `surfacePos` drags the window.
    //
    // The strip drags the window wherever no control sits: over its own ground, the glyph and
    // the title, and over the content passing under it. A control placed in the strip — a window
    // that can hold the keyboard focus or is a button, lying within the strip, or an entry of a
    // menu bar — keeps its clicks. Content that only reaches up into the strip, such as a
    // document or a list continuing below it, drags the window there. The window buttons never
    // drag.
    //
    // A [[Gui.SurfaceFlags.Sheet]] has no strip: its body's own ground — the title, the inset
    // around the content and the air beside the actions — drags it instead.
    //
    // Under the strip, the view may name more of its own ground through `groundHitTest`, such as
    // the empty ground around a picture in an editor whose whole body is otherwise the work.
    mtd hitTestCaption(surfacePos: Math.Point)->bool
    {
        let srfn = .surface
        if srfn and srfn.flags.has(.Sheet)
        {
            let target = .windowAt(surfacePos.x, surfacePos.y, true)
            if not target do
                return true

            // A sheet has no visible caption. Its whole ground can move it, while controls keep
            // pointer input. Walk ancestors too: a child of an interactive composite is part of
            // that control even when the child itself does not take focus.
            var wnd: *Wnd? = target
            while wnd and wnd != me and wnd != .view
            {
                if wnd.focusPolicy != .None or wnd is Button do
                    return false
                wnd = wnd.parent
            }

            return true
        }

        let strip = .stripHeight()
        if strip <= 0 do
            return false

        if .hitTestCaptionButton(surfacePos) do
            return false

        let pos = .surfaceToLocal(surfacePos)
        if pos.x < 0 or pos.x >= .position.width do
            return false
        if pos.y >= strip and .groundHitTest do
            return .groundHitTest(surfacePos)
        if pos.y < 0 or pos.y >= strip do
            return false

        let target = .windowAt(pos.x, pos.y, true)
        if not target or target == me do
            return true
        if target is MenuCtrl as menu where menu.bar do
            return menu.hitTestBar(surfacePos) == Swag.U32.Max

        // A window keeps the pointer when it, or a composite it belongs to, is a control set in
        // the strip. The view itself is the ground the strip floats over, so it never counts.
        let stripBottom = .surfaceRect().y + strip
        var wnd: *Wnd?  = target
        while wnd and wnd != me and wnd != .view
        {
            let isControl = wnd.focusPolicy != .None or wnd is Button
            if isControl and wnd.surfaceRect().bottom() <= stripBottom do
                return false
            wnd = wnd.parent
        }

        return true
    }

    mtd hitTestBorders(surfacePos: Math.Point)->SizingBorder
    {
        // `surfacePos` is logical, so the surface extent must be logical as well.
        let srfn    = unwrap .surface
        let metrics = .themeMetrics()
        let sdw     = srfn.shadowMargin()
        let size    = srfn.size()

        var newSizingBorder = SizingBorder.None
        if srfn.flags.has(.Resizable)
        {
            let SizeBorder    = metrics.wnd_SizingBorderSize
            let TopSizeBorder = Math.min(SizeBorder, metrics.wnd_TopSizingBorderSize)
            if surfacePos.x > sdw - SizeBorder and
               surfacePos.x < sdw + SizeBorder and
               surfacePos.y > sdw - SizeBorder and
               surfacePos.y < size.y - sdw + SizeBorder
            {
                newSizingBorder |= .Left
            }

            if surfacePos.y > sdw - TopSizeBorder and
               surfacePos.y < sdw + TopSizeBorder and
               surfacePos.x > sdw - SizeBorder and
               surfacePos.x < size.x - sdw + SizeBorder
            {
                newSizingBorder |= .Top
            }

            if surfacePos.x > size.x - sdw - SizeBorder and
               surfacePos.x < size.x - sdw + SizeBorder and
               surfacePos.y > sdw - SizeBorder and
               surfacePos.y < size.y - sdw + SizeBorder
            {
                newSizingBorder |= .Right
            }

            if surfacePos.y > size.y - sdw - SizeBorder and
               surfacePos.y < size.y - sdw + SizeBorder and
               surfacePos.x > sdw - SizeBorder and
               surfacePos.x < size.x - sdw + SizeBorder
            {
                newSizingBorder |= .Bottom
            }
        }

        return newSizingBorder
    }

    func onMinimize(btn: *Button)
    {
        btn.surface!.requestMinimize()
    }

    func onMaximize(btn: *Button)
    {
        let srfn = unwrap btn.surface
        if srfn.isMaximized do
            srfn.requestRestore()
        else do
            srfn.requestMaximize()
    }

    func onClose(btn: *Button)
    {
        btn.surface!.requestClose()
    }

    internal mtd applySurfaceFlags()
    {
        // The glyph and the title are drawn after the view, which the strip floats over.
        .wndFlags.add(.AfterChildrenPaint)

        let srfn  = unwrap .surface
        let theme = srfn.app.theme
        if not theme.initialized do
            return

        if srfn.flags.has(.MinimizeButton)
        {
            if not .minimizeBtn
            {
                with me.minimizeBtn = IconButton.create(me, theme.icon(ThemeIcons.WndMinimize, theme.metrics.wnd_CaptionButtonGlyph), {0, 0, 0, 0})
                {
                    .setForm(.RoundedRectangle)
                    .focusPolicy = .None
                    .sigPressed  += &onMinimize
                    .style.addStyleSheetColors(ChromeButtonColors)
                }
            }
        }
        elif .minimizeBtn
        {
            .minimizeBtn.destroy()
            .minimizeBtn = null
        }

        if srfn.flags.has(.MaximizeButton)
        {
            if not .maximizeBtn
            {
                with me.maximizeBtn = IconButton.create(me, theme.icon(ThemeIcons.WndMaximize, theme.metrics.wnd_CaptionButtonGlyph), {0, 0, 0, 0})
                {
                    .setForm(.RoundedRectangle)
                    .focusPolicy = .None
                    .sigPressed  += &onMaximize
                    .style.addStyleSheetColors(ChromeButtonColors)
                }
            }
        }
        elif .maximizeBtn
        {
            .maximizeBtn.destroy()
            .maximizeBtn = null
        }

        if srfn.flags.has(.CloseButton)
        {
            if not .closeBtn
            {
                with me.closeBtn = IconButton.create(me, theme.icon(ThemeIcons.WndClose, theme.metrics.wnd_CaptionButtonGlyph), {0, 0, 0, 0})
                {
                    .setForm(.RoundedRectangle)
                    .focusPolicy = .None
                    .sigPressed  += &onClose
                    .style.addStyleSheetColors(CloseButtonColors)
                }
            }
        }
        elif .closeBtn
        {
            .closeBtn.destroy()
            .closeBtn = null
        }
    }

    mtd create(userView: *Wnd?, hook: HookEvent?)
    {
        .computeStyle()

        // The view is the first child, so the window buttons and the popups joined to them are
        // drawn above the part of it the strip floats over.
        if userView
        {
            .view = userView
            .view.hookOnEvent = hook
            .view.setParent(me)
            .view.sendToBack()
        }
        else
        {
            .createView'Wnd(hook)
        }

        .applySurfaceFlags()
    }
}

// Reports whether an application caption action is shown: an application may keep one hidden and
// still use it, as the appearance choice it offers through the lens.
private func isShownCaptionButton(button: *IconButton)->bool => not button.isPendingDestroy and button.isLocallyVisible()
