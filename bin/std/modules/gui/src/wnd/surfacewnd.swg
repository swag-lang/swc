using Core, Pixel, Serialization

#[Swag.EnumFlags]
public enum SizingBorder
{
    Zero   = 0
    Left
    Top
    Right
    Bottom
}

public struct SurfaceWnd
{
    using base:        FrameWnd
    icon:              Icon
    minimizeBtn:       #null *IconButton
    maximizeBtn:       #null *IconButton
    closeBtn:          #null *IconButton
    movingSurface:     bool
    sizingBorder:      SizingBorder = Zero
}

impl IWnd for SurfaceWnd
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        switch evt.kind
        {
        case MousePressed:
            if evt.button != .Left do
                break
            .surface.bringToTop()
            if .surface.isMaximized do
                break
            if .surface.flags.has(.Sizeable) do
                .sizingBorder = .hitTestBorders(evt.surfacePos)
            else do
                .sizingBorder = .Zero
            if .sizingBorder == .Zero and !.hitTestCaption(evt.surfacePos) do
                break
            .captureMouse()
            .movingSurface = true

        case MouseLeave:
            .sizingBorder = .Zero

        case MouseReleased:
            if evt.button != .Left do
                break

            .releaseMouse()
            .movingSurface = false
            .sizingBorder  = .Zero
            fallthrough

        case MouseMove:
            if .surface.isMaximized do
                break
            if .getApp().mouseEnterWnd != me do
                break

            if !.movingSurface and .surface.flags.has(.Sizeable)
            {
                let newSizingBorder = .hitTestBorders(evt.surfacePos)
                if newSizingBorder != .sizingBorder do
                    .sizingBorder = newSizingBorder
            }

            switch .sizingBorder
            {
            case Left, Right:
                .surface.app.setFrameCursor(Cursor.from(.SizeWE))
            case Top, Bottom:
                .surface.app.setFrameCursor(Cursor.from(.SizeNS))
            case Right | Bottom, Left | Top:
                .surface.app.setFrameCursor(Cursor.from(.SizeNWSE))
            case Right | Top, Left | Bottom:
                .surface.app.setFrameCursor(Cursor.from(.SizeNESW))
            }

            if !.movingSurface do
                break

            var hasChanged = false
            var pos        = .surface.position

            if .sizingBorder & .Left
            {
                pos.x += evt.move.x
                pos.width -= evt.move.x
                hasChanged = true
            }

            if .sizingBorder & .Top
            {
                pos.y += evt.move.y
                pos.height -= evt.move.y
                hasChanged = true
            }

            if .sizingBorder & .Right
            {
                pos.width += evt.move.x
                hasChanged = true
            }

            if .sizingBorder & .Bottom
            {
                pos.height += evt.move.y
                hasChanged = true
            }

            if .sizingBorder == .Zero
            {
                pos.offset(evt.move.x, evt.move.y)
                hasChanged = true
            }

            if hasChanged
            {
                .surface.setPosition(pos)
                .surface.invalidate()
            }
        }
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        let surface = notnull .surface
        surface.app.destroySurface(surface)
    }

    mtd impl onSysCommandEvent(evt: *SysCommandEvent)
    {
        switch evt.kind
        {
        case Maximize:
            .surface.showMaximized()
        case Minimize:
            .surface.showMinimized()
        case Restore:
            .surface.showNormal()
        case Close:
            .surface.destroy()
        }
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        let clientRect = .getClientRect()
        let metrics    = .getThemeMetrics()

        var pos = clientRect
        pos.height = Math.max(0, .surface.wnd.padding.y - 2 * metrics.wnd_CaptionButtonMargin)
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

    mtd impl onPaintEvent(evt: *PaintEvent)
    {
        if .isPendingDestroy do
            return
        let bc     = evt.bc
        let theme  = .getTheme()
        let colors = .getThemeColors()
        let metrics = .getThemeMetrics()

        let clientRect = .getClientRect()
        let radius     = .surface.getCornerRadius()

        if radius > 0 and metrics.surfaceWnd_ShadowSize > 0 do
            bc.painter.fillRoundRect(clientRect, radius, radius, colors.wnd_Bk)
        else do
            bc.painter.fillRect(clientRect, colors.wnd_Bk)

        var posCaption = clientRect
        if .surface.flags.has(.BigCaption) do
            posCaption.height = .surface.wnd.padding.y

        if .surface.flags.has(.SmallCaption) do
            posCaption.height = .surface.wnd.padding.y

        let captionColor = .surface.app.isActivated ? colors.wnd_CaptionBk : colors.wnd_CaptionBkNotActived
        if .surface.flags.has(.BigCaption | .SmallCaption) do
            bc.painter.fillRect(posCaption, captionColor)

        if .surface.flags.has(.Border) and metrics.surfaceWnd_ShadowSize > 0
        {
            var pen = Pen.createSolid(colors.wnd_Border, metrics.wnd_BorderSize)
            pen.borderPos = .Inside
            if radius > 0 do
                bc.painter.drawRoundRect(clientRect, radius, radius, pen)
            else do
                bc.painter.drawRect(clientRect, pen)
        }

        if .surface.flags.has(.BigCaption | .SmallCaption)
        {
            posCaption.x += theme.metrics.wnd_CaptionMarginTitle

            var posClip = posCaption
            if .surface.flags.has(.MinimizeBtn) do
                posClip.setRight(.minimizeBtn.position.x)
            elif .surface.flags.has(.MaximizeBtn) do
                posClip.setRight(.maximizeBtn.position.x)
            elif .surface.flags.has(.CloseBtn) do
                posClip.setRight(.closeBtn.position.x)
            bc.painter.pushClippingRect(posClip)
            defer bc.painter.popClippingRect()

            let captionTextColor = .surface.app.isActivated ? colors.wnd_CaptionText : colors.wnd_CaptionNotActivatedText
            if .icon.isValid()
            {
                .icon.paint(bc.painter, posCaption.x, posCaption.vertCenter() - .icon.sizeY * 0.5, captionTextColor)
                posCaption.x += .icon.sizeX + theme.metrics.iconText_Margin
            }

            var sf: Pixel.RichStringFormat
            sf.vertAlignment = .Center
            sf.font          = .getFont()
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
        if !.surface.flags.has(.BigCaption | .SmallCaption) do
            return false
        if .hitTestCaptionButton(surfacePos) do
            return false

        let pos = .surfaceToLocal(surfacePos)
        if pos.x < 0 or pos.x >= .position.width do
            return false
        if pos.y < 0 or pos.y >= .surface.wnd.padding.y do
            return false

        let target = .getWndAt(pos.x, pos.y, true)
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
        let metrics = .getThemeMetrics()
        let sdw     = metrics.surfaceWnd_ShadowSize

        var newSizingBorder = SizingBorder.Zero
        if .surface.flags.has(.Sizeable)
        {
            let SizeBorder    = metrics.wnd_SizingBorderSize
            let TopSizeBorder = Math.min(SizeBorder, metrics.wnd_TopSizingBorderSize)
            if surfacePos.x > sdw - SizeBorder and
               surfacePos.x < sdw + SizeBorder and
               surfacePos.y > sdw - SizeBorder and
               surfacePos.y < .surface.position.height - sdw + SizeBorder
            {
                newSizingBorder |= .Left
            }

            if surfacePos.y > sdw - TopSizeBorder and
               surfacePos.y < sdw + TopSizeBorder and
               surfacePos.x > sdw - SizeBorder and
               surfacePos.x < .surface.position.width - sdw + SizeBorder
            {
                newSizingBorder |= .Top
            }

            if surfacePos.x > .surface.position.width - sdw - SizeBorder and
               surfacePos.x < .surface.position.width - sdw + SizeBorder and
               surfacePos.y > sdw - SizeBorder and
               surfacePos.y < .surface.position.height - sdw + SizeBorder
            {
                newSizingBorder |= .Right
            }

            if surfacePos.y > .surface.position.height - sdw - SizeBorder and
               surfacePos.y < .surface.position.height - sdw + SizeBorder and
               surfacePos.x > sdw - SizeBorder and
               surfacePos.x < .surface.position.width - sdw + SizeBorder
            {
                newSizingBorder |= .Bottom
            }
        }

        return newSizingBorder
    }

    func onMinimize(btn: *Button)
    {
        btn.surface.requestMinimize()
    }

    func onMaximize(btn: *Button)
    {
        if btn.surface.isMaximized do
            btn.surface.requestRestore()
        else do
            btn.surface.requestMaximize()
    }

    func onClose(btn: *Button)
    {
        btn.surface.requestClose()
    }

    private mtd applySurfaceFlags()
    {
        let theme = .surface.app.theme
        if !theme.intialized do
            return

        if .surface.flags.has(.MinimizeBtn)
        {
            if !.minimizeBtn
            {
                with me.minimizeBtn = IconButton.create(me, theme.getIcon24(ThemeIcons24.WndMinimize), {0, 0, 0, 0})
                {
                    .form          = .RoundSquare
                    .focusStrategy = .None
                    .sigPressed += &onMinimize
                }
            }
        }
        elif .minimizeBtn
        {
            .minimizeBtn.destroy()
            .minimizeBtn = null
        }

        if .surface.flags.has(.MaximizeBtn)
        {
            if !.maximizeBtn
            {
                with me.maximizeBtn = IconButton.create(me, theme.getIcon24(ThemeIcons24.WndMaximize), {0, 0, 0, 0})
                {
                    .form          = .RoundSquare
                    .focusStrategy = .None
                    .sigPressed += &onMaximize
                }
            }
        }
        elif .maximizeBtn
        {
            .maximizeBtn.destroy()
            .maximizeBtn = null
        }

        if .surface.flags.has(.CloseBtn)
        {
            if !.closeBtn
            {
                with me.closeBtn = IconButton.create(me, theme.getIcon24(ThemeIcons24.WndClose), {0, 0, 0, 0})
                {
                    .form          = .RoundSquare
                    .focusStrategy = .None
                    .sigPressed += &onClose
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
