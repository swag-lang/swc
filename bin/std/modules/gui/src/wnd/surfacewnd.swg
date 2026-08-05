using Core, Pixel, Serialization

// Selects sizing border.
#[Swag.EnumFlags]
public enum SizingBorder
{
    None = 0     // No flags are enabled.
    Left         // Selects left.
    Top          // Selects top.
    Right        // Selects right.
    Bottom       // Selects bottom.
}

// Provides the root GUI frame and native caption controls for a [[Gui.Surface]].
public struct SurfaceWnd
{
    using base:    FrameWnd                // Embedded base state.
    icon:          Icon                    // Icon associated with this value.
    minimizeBtn:   #null *IconButton       // Minimize btn associated with this value.
    maximizeBtn:   #null *IconButton       // Maximize btn associated with this value.
    closeBtn:      #null *IconButton       // Close btn associated with this value.
    movingSurface: bool                    // Moving surface associated with this value.
    sizingBorder:  SizingBorder = None     // Sizing border associated with this value.
}

impl IWnd for SurfaceWnd
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let srfn = .surface!
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
            if .sizingBorder == .None and !.hitTestCaption(evt.surfacePos) do
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

            if !.movingSurface and srfn.flags.has(.Resizable)
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

            if !.movingSurface do
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

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        let surface = .surface!
        surface.app.destroySurface(surface)
    }

    mtd impl onSysCommandEvent(evt: *SysCommandEvent)
    {
        let srfn = .surface!
        switch evt.kind
        {
        case .Maximize: srfn.showMaximized()
        case .Minimize: srfn.showMinimized()
        case .Restore:  srfn.showNormal()
        case .Close:    srfn.destroy()
        }
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        let srfn       = .surface!
        let clientRect = .clientRect()
        let metrics    = .themeMetrics()

        var pos = clientRect
        pos.height = Math.max(0, srfn.wnd.padding.y - 2 * metrics.wnd_CaptionButtonMargin)
        pos.width  = Math.max(metrics.wnd_CaptionButtonMinWidth, pos.height * metrics.wnd_CaptionButtonAspect)
        pos.x      = clientRect.right() - pos.width - metrics.wnd_CaptionButtonMargin
        pos.y      = metrics.wnd_CaptionButtonMargin

        if .closeBtn
        {
            .closeBtn.setPosition(pos)
            pos.x -= pos.width
        }

        if .maximizeBtn
        {
            .maximizeBtn.setPosition(pos)
            pos.x -= pos.width
        }

        if .minimizeBtn
        {
            .minimizeBtn.setPosition(pos)
            pos.x -= pos.width
        }

        .base.IWnd.onResizeEvent(evt)
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let srfn = .surface!
        if .isPendingDestroy do
            return
        let bc      = evt.paintContext
        let theme   = .theme()
        let colors  = .themeColors()
        let metrics = .themeMetrics()

        let clientRect = .clientRect()
        let radius     = srfn.cornerRadius()

        if radius > 0 and metrics.surfaceWnd_ShadowSize > 0 do
            bc.painter.fillRoundRect(clientRect, radius, radius, colors.wnd_Bk)
        else do
            bc.painter.fillRect(clientRect, colors.wnd_Bk)

        var posCaption = clientRect
        if srfn.flags.has(.LargeCaption) do
            posCaption.height = srfn.wnd.padding.y

        if srfn.flags.has(.SmallCaption) do
            posCaption.height = srfn.wnd.padding.y

        let captionColor = srfn.app.isActivated ? colors.wnd_CaptionBk : colors.wnd_CaptionBkNotActived
        if srfn.flags.has(.LargeCaption | .SmallCaption) do
            bc.painter.fillRect(posCaption, captionColor)

        // A window that asks for a border gets one, whether or not the theme also draws a
        // shadow. Tied to the shadow, a theme that leaves the drop shadow to the system —
        // as the Swag palettes do — silently lost the outline too, and a modal box over an
        // application of the same ink had nothing at all to say where it began.
        if srfn.flags.has(.Border)
        {
            var pen = Pen.createSolid(colors.wnd_Border, bc.painter.hairline(metrics.wnd_BorderSize))
            pen.borderPos = .Inside
            if radius > 0 do
                bc.painter.drawRoundRect(clientRect, radius, radius, pen)
            else do
                bc.painter.drawRect(clientRect, pen)
        }

        if srfn.flags.has(.LargeCaption | .SmallCaption)
        {
            posCaption.x += theme.metrics.wnd_CaptionMarginTitle

            var posClip = posCaption
            if srfn.flags.has(.MinimizeButton) do
                posClip.setRight(.minimizeBtn!.position.x)
            elif srfn.flags.has(.MaximizeButton) do
                posClip.setRight(.maximizeBtn!.position.x)
            elif srfn.flags.has(.CloseButton) do
                posClip.setRight(.closeBtn!.position.x)
            bc.painter.pushClippingRect(posClip)
            defer bc.painter.popClippingRect()

            let captionTextColor = srfn.app.isActivated ? colors.wnd_CaptionText : colors.wnd_CaptionNotActivatedText

            // A window says which application it belongs to before its title is read, so the
            // caption falls back to the application mark when the surface names no icon of
            // its own. A caption is chrome: the mark is set at the row size of the chart and
            // never grows with the bar it sits in.
            var icon = .icon
            if !icon.isValid() do
                icon = srfn.app.appIconAt(theme.metrics.wnd_CaptionIconSize)
            if icon.isValid()
            {
                let iconColor = icon.color.a ? icon.color : captionTextColor
                icon.paint(bc.painter, posCaption.x, opticalTop(.font(), posCaption.vertCenter(), icon.sizeY), iconColor)
                posCaption.x += icon.sizeX + theme.metrics.iconText_Margin
            }

            var sf: Pixel.RichStringFormat
            sf.vertAlignment = .Center
            sf.font          = .font()
            sf.palette[0]    = captionTextColor
            bc.painter.drawRichString(posCaption, &.name, sf)
        }
    }
}

impl SurfaceWnd
{
    mtd hitTestCaptionButton(surfacePos: Math.Point)->bool
    {
        let pos = .surfaceToLocal(surfacePos)
        if .closeBtn and .closeBtn.position.contains(pos.x, pos.y) do
            return true
        if .maximizeBtn and .maximizeBtn.position.contains(pos.x, pos.y) do
            return true
        if .minimizeBtn and .minimizeBtn.position.contains(pos.x, pos.y) do
            return true
        return false
    }

    mtd hitTestCaption(surfacePos: Math.Point)->bool
    {
        let srfn = .surface!
        if !srfn.flags.has(.LargeCaption | .SmallCaption) do
            return false
        if .hitTestCaptionButton(surfacePos) do
            return false

        let pos = .surfaceToLocal(surfacePos)
        if pos.x < 0 or pos.x >= .position.width do
            return false
        if pos.y < 0 or pos.y >= srfn.wnd.padding.y do
            return false

        let target = .windowAt(pos.x, pos.y, true)
        if target and target != me
        {
            if target.type == MenuCtrl
            {
                let menu = cast(#null *MenuCtrl) target
                if menu.bar and menu.hitTestBar(surfacePos) == Swag.U32.Max do
                    return true
            }

            return false
        }

        return true
    }

    mtd hitTestBorders(surfacePos: Math.Point)->SizingBorder
    {
        // `surfacePos` is logical, so the surface extent must be logical as well.
        let srfn    = .surface!
        let metrics = .themeMetrics()
        let sdw     = metrics.surfaceWnd_ShadowSize
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
        let srfn = btn.surface!
        srfn.requestMinimize()
    }

    func onMaximize(btn: *Button)
    {
        let srfn = btn.surface!
        if srfn.isMaximized do
            srfn.requestRestore()
        else do
            srfn.requestMaximize()
    }

    func onClose(btn: *Button)
    {
        let srfn = btn.surface!
        srfn.requestClose()
    }

    private mtd applySurfaceFlags()
    {
        let srfn  = .surface!
        let theme = srfn.app.theme
        if !theme.initialized do
            return

        if srfn.flags.has(.MinimizeButton)
        {
            if !.minimizeBtn
            {
                with me.minimizeBtn = IconButton.create(me, theme.icon(ThemeIcons.WndMinimize, theme.metrics.wnd_CaptionButtonGlyph), {0, 0, 0, 0})
                {
                    .setForm(.RoundedRectangle)
                    .focusPolicy = .None
                    .sigPressed  += &onMinimize
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
            if !.maximizeBtn
            {
                with me.maximizeBtn = IconButton.create(me, theme.icon(ThemeIcons.WndMaximize, theme.metrics.wnd_CaptionButtonGlyph), {0, 0, 0, 0})
                {
                    .setForm(.RoundedRectangle)
                    .focusPolicy = .None
                    .sigPressed  += &onMaximize
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
            if !.closeBtn
            {
                with me.closeBtn = IconButton.create(me, theme.icon(ThemeIcons.WndClose, theme.metrics.wnd_CaptionButtonGlyph), {0, 0, 0, 0})
                {
                    .setForm(.RoundedRectangle)
                    .focusPolicy = .None
                    .sigPressed  += &onClose
                    .style.addStyleSheetColors(#nameof(ThemeColors.btnIcon_HotBk) ++ " $" ++ #nameof(ThemeColors.wnd_BtnCloseBk))
                    .style.addStyleSheetColors(#nameof(ThemeColors.btnIcon_PressedBk) ++ " $" ++ #nameof(ThemeColors.wnd_BtnCloseHotBk))
                    .style.addStyleSheetColors(#nameof(ThemeColors.btnIcon_HotIcon) ++ " $" ++ #nameof(ThemeColors.wnd_BtnCloseHotIcon))
                    .style.addStyleSheetColors(#nameof(ThemeColors.btnIcon_PressedIcon) ++ " $" ++ #nameof(ThemeColors.wnd_BtnClosePressedIcon))
                }
            }
        }
        elif .closeBtn
        {
            .closeBtn.destroy()
            .closeBtn = null
        }
    }

    mtd create(userView: #null *Wnd, hook: #null HookEvent)
    {
        .computeStyle()

        if userView
        {
            .view             = userView
            .view.hookOnEvent = hook
            .view.setParent(me)
        }
        else
        {
            .createView'Wnd(hook)
        }

        .applySurfaceFlags()
    }
}
