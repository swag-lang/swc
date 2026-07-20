#global public
using Core, Pixel

enum IconButtonForm
{
    Square
    Round
    RoundSquare
}

#[Swag.EnumFlags]
enum IconButtonFlags
{
    Zero            = 0
    Checkable
    CheckableToggle
    Popup
    Center
    HideName
    Flat            // No background box (and no checked fill): paint only the icon/swatch and arrow
    Overlay         // No opaque box: hot/pressed/checked is a translucent state layer (Material-
                    // style) drawn over the content, so it blends with whatever is underneath
                    // (a pastel accent row, a color swatch) instead of clashing as a solid fill.
}

enum IconButtonArrowPos
{
    None
    Left
    Top
    Right
    RightUp
    RightDown
    Bottom
}

enum IconButtonTextPos
{
    Left
    Top
    Right
    Bottom
}

enum IconButtonCheckedForm
{
    None
    Bottom
    Top
    Left
    Right
    Full
}

struct IconButton
{
    using button:        Button

    form                 = IconButtonForm.Square
    iconBtnFlags         = IconButtonFlags.Zero
    checkedForm          = IconButtonCheckedForm.Full
    arrowPos             = IconButtonArrowPos.None
    textPos              = IconButtonTextPos.Bottom
    iconColor:           Color
    textColor:           Color

    sigHidePopup:        SigArray'func||(*IconButton)
    sigShowPopup:        SigArray'func||(*IconButton)
    sigCheckChanged:     SigArray'func||(*IconButton)
    sigPaintIcon:        func||(*IconButton, *PaintContext, Math.Rectangle, PaintItemFlags)

    aniBk:               BlendColor
    isChecked:           bool
    popup:               #null *Wnd
}

impl IWnd for IconButton
{
    mtd hidePopup()
    {
        if !.popup do
            return

        .getApp().unregisterHookEvents(me)
        .sigHidePopup.call(me)
        .popup.destroy()
        .popup     = null
        .isChecked = false
        .invalidate()
    }

    mtd impl onHookEvent(evt: IEvent)
    {
        if !.popup do
            return

        if let ptr = evt as MouseEvent where ptr.kind == .MousePressed
        {
            if ptr.target == me or ptr.target == .popup do
                return
            if ptr.target and .popup.isParentOf(ptr.target) do
                return
            .hidePopup()
        }
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .hidePopup()
    }

    mtd impl onStateEvent(evt: *StateEvent)
    {
        .button.IWnd.onStateEvent(evt)
        if evt.kind == .Hide or evt.kind == .Disable do
            .aniBk.reset()
    }

    mtd impl onApplyStateEvent(evt: *CommandStateEvent)
    {
        if evt.id != .id do
            return

        if evt.setFlags.has(.ToolTip)
        {
            .toolTip = evt.toolTip
        }

        if evt.setFlags.has(.Checked) and .isChecked != evt.checked
        {
            evt.accepted = true
            .isChecked   = evt.checked
            .invalidate()
        }

        .button.IWnd.onApplyStateEvent(evt)
    }

    mtd impl onPaintEvent(evt: *PaintEvent)
    {
        let bc      = evt.bc
        let theme   = .getTheme()
        let colors  = .getThemeColors()
        let rects   = .getThemeRects()
        let metrics = .getThemeMetrics()

        var subRectBk:    #null *ThemeImageRect
        var colorBk:      Color = undefined
        var colorIcon:    Color = undefined
        var colorText:    Color = undefined
        var colorChecked: Color = undefined

        switch .form
        {
        case Square:
            subRectBk = &rects.btnIcon_SquareBk
        case Round:
            subRectBk = &rects.btnIcon_RoundBk
        case RoundSquare:
            subRectBk = &rects.btnIcon_RoundSquareBk
        }

        var paintFlags: PaintItemFlags = .Zero
        switch
        {
        case bc.isDisabled:
            colorBk      = .isChecked ? colors.btnIcon_CheckedDisabledBk : colors.btnIcon_DisabledBk
            colorIcon    = .isChecked ? colors.btnIcon_CheckedDisabledIcon : colors.btnIcon_DisabledIcon
            colorText    = .isChecked ? colors.btnIcon_CheckedDisabledText : colors.btnIcon_DisabledText
            colorChecked = colors.btnIcon_CheckedDisabledMark
        case (.isPressed or .isChecked) and .checkedForm == .None:
            colorBk      = .isChecked ? colors.btnIcon_CheckedPressedBk : colors.btnIcon_PressedBk
            colorIcon    = colors.btnIcon_PressedIcon
            colorText    = colors.btnIcon_PressedText
            colorChecked = colors.btnIcon_CheckedPressedMark
        case .isPressed:
            colorBk      = .isChecked ? colors.btnIcon_CheckedPressedBk : colors.btnIcon_PressedBk
            colorIcon    = .isChecked ? colors.btnIcon_CheckedPressedIcon : colors.btnIcon_PressedIcon
            colorText    = .isChecked ? colors.btnIcon_CheckedPressedText : colors.btnIcon_PressedText
            colorChecked = colors.btnIcon_CheckedPressedMark
        case .isHot:
            colorBk      = .isChecked ? colors.btnIcon_CheckedHotBk : colors.btnIcon_HotBk
            colorIcon    = .isChecked ? colors.btnIcon_CheckedHotIcon : colors.btnIcon_HotIcon
            colorText    = .isChecked ? colors.btnIcon_CheckedHotText : colors.btnIcon_HotText
            colorChecked = colors.btnIcon_CheckedHotMark
        default:
            colorBk      = .isChecked ? colors.btnIcon_CheckedBk : colors.btnIcon_Bk
            colorIcon    = .isChecked ? colors.btnIcon_CheckedIcon : colors.btnIcon_Icon
            colorText    = .isChecked ? colors.btnIcon_CheckedText : colors.btnIcon_Text
            colorChecked = colors.btnIcon_CheckedMark
        }

        if bc.isDisabled do
            paintFlags.add(.Disabled)
        if .isChecked do
            paintFlags.add(.Checked)
        if .isHot do
            paintFlags.add(.Hot)
        if .isPressed do
            paintFlags.add(.Pressed)

        if .icon.color.a do
            colorIcon = .icon.color
        if .iconColor.a do
            colorIcon = .iconColor
        if .textColor.a do
            colorText = .textColor

        // Background. A flat button paints no box in any state; an overlay button paints its
        // hot/pressed/checked state as a translucent layer over the content instead (drawn at the
        // end of this method). Both are useful for inline affordances (a color swatch, the reset
        // arrow) where a solid themed fill would clash with the row background, especially over a
        // selected (accent) row.
        let clientRect = .getClientRect()
        let flat       = .iconBtnFlags.has(.Flat)
        let overlay    = .iconBtnFlags.has(.Overlay)
        if !flat and !overlay
        {
            .aniBk.apply(me, colorBk)
            theme.drawSubRect(bc.painter, clientRect, subRectBk, .aniBk.cur())
        }

        if !flat and !overlay and .isChecked and .checkedForm != .None
        {
            switch .checkedForm
            {
            case Bottom:
                subRectBk = &rects.btnIcon_CheckedBottom
            case Top:
                subRectBk = &rects.btnIcon_CheckedTop
            case Left:
                subRectBk = &rects.btnIcon_CheckedLeft
            case Right:
                subRectBk = &rects.btnIcon_CheckedRight
            case Full:
                if .form == .Square do
                    subRectBk = &rects.btnIcon_CheckedSquare
                elif .form == .Round do
                    subRectBk = &rects.btnIcon_CheckedRound
                else do
                    subRectBk = &rects.btnIcon_CheckedRoundSquare
            }

            theme.drawSubRect(bc.painter, clientRect, subRectBk, colorChecked)
        }

        var pos     = .getClientRectPadding()
        let hasIcon = .icon.isValid() or .sigPaintIcon != null

        if .iconSizeX do
            .icon.sizeX = .iconSizeX
        if .iconSizeY do
            .icon.sizeY = .iconSizeY

        // Center everything
        var marginArrow = metrics.btnIcon_MarginArrow
        if .iconBtnFlags.has(.Center)
        {
            var nw, nh = 0'f32
            marginArrow = 0

            #[Swag.Complete]
            switch .arrowPos
            {
            case Left, Right, RightUp, RightDown:
                nw += metrics.btnIcon_WidthArrow + metrics.btnIcon_SpacingArrowH
            case Top, Bottom:
                nh += metrics.btnIcon_HeightArrow + metrics.btnIcon_SpacingArrowV
            case None:
                break
            }

            let fontR = nnFont(.getFont().regular)
            let sm    = Painter.measureString(.name.raw.toString(), fontR)
            nw += sm.width
            nh += fontR.height

            if hasIcon
            {
                #[Swag.Complete]
                switch .textPos
                {
                case Left, Right:
                    nw += metrics.btnIcon_SpacingTextH
                    nw += .icon.sizeX
                case Top, Bottom:
                    nh += metrics.btnIcon_SpacingTextV
                    nh += .icon.sizeY
                }
            }

            pos.x      = pos.horzCenter() - nw * 0.5
            pos.y      = pos.vertCenter() - nh * 0.5
            pos.width  = nw
            pos.height = nh
        }

        // Arrow
        if .arrowPos != .None
        {
            var posArrow = pos
            let w        = metrics.btnIcon_WidthArrow
            let h        = metrics.btnIcon_HeightArrow

            switch .arrowPos
            {
            case Left:
                subRectBk       = &rects.btnIcon_ArrowLeft
                posArrow.width  = h
                posArrow.height = w
                posArrow.x      = pos.x + marginArrow
                posArrow.y      = pos.vertCenter() - w * 0.5
                theme.drawSubRect(bc.painter, posArrow, subRectBk, colorIcon)
                pos.moveLeft(marginArrow + w + metrics.btnIcon_SpacingArrowH)

            case Top:
                subRectBk       = &rects.btnIcon_ArrowUp
                posArrow.width  = w
                posArrow.height = h
                posArrow.x      = pos.horzCenter() - w * 0.5
                posArrow.y      = pos.y + marginArrow
                theme.drawSubRect(bc.painter, posArrow, subRectBk, colorIcon)
                pos.moveTop(marginArrow + h + metrics.btnIcon_SpacingArrowV)

            case Right:
                subRectBk       = &rects.btnIcon_ArrowRight
                posArrow.width  = h
                posArrow.height = w
                posArrow.x      = pos.right() - w - marginArrow
                posArrow.y      = pos.vertCenter() - h * 0.5
                theme.drawSubRect(bc.painter, posArrow, subRectBk, colorIcon)
                pos.setRight(posArrow.x - metrics.btnIcon_SpacingArrowH)

            case RightUp:
                subRectBk       = &rects.btnIcon_ArrowUp
                posArrow.width  = w
                posArrow.height = h
                posArrow.x      = pos.right() - w - marginArrow
                posArrow.y      = pos.vertCenter() - h * 0.5
                theme.drawSubRect(bc.painter, posArrow, subRectBk, colorIcon)
                pos.setRight(posArrow.x - metrics.btnIcon_SpacingArrowH)

            case RightDown:
                subRectBk       = &rects.btnIcon_ArrowDown
                posArrow.width  = w
                posArrow.height = h
                posArrow.x      = pos.right() - w - marginArrow
                posArrow.y      = pos.vertCenter() - h * 0.5
                theme.drawSubRect(bc.painter, posArrow, subRectBk, colorIcon)
                pos.setRight(posArrow.x - metrics.btnIcon_SpacingArrowH)

            case Bottom:
                subRectBk       = &rects.btnIcon_ArrowDown
                posArrow.width  = w
                posArrow.height = h
                posArrow.x      = pos.horzCenter() - w * 0.5
                posArrow.y      = pos.bottom() - h - marginArrow
                theme.drawSubRect(bc.painter, posArrow, subRectBk, colorIcon)
                pos.setBottom(posArrow.y - metrics.btnIcon_SpacingArrowV)
            }
        }

        // Name
        if !.name.isEmpty() and !.iconBtnFlags.has(.HideName)
        {
            var sf: RichStringFormat
            theme.setTextColors(&sf, colorText)
            sf.font          = .getFont()
            sf.horzAlignment = .Center
            sf.vertAlignment = .Center
            sf.flags         = .DontAdaptSingleLineHeight
            switch .textPos
            {
            case Left:
                sf.horzAlignment = .Left
                if !hasIcon and (.arrowPos == .Top or .arrowPos == .Bottom) do
                    sf.horzAlignment = .Center
                bc.painter.drawRichString(pos, &.name, sf)
                pos.moveLeft(.name.boundRect.width + metrics.btnIcon_SpacingTextH)

                if !.icon.isValid() do
                    .icon.sizeX = pos.width
                if pos.width < .icon.sizeX
                {
                    let ratio = .icon.sizeX / .icon.sizeY
                    .icon.sizeX = pos.width * ratio
                    .icon.sizeY = pos.width
                }
                else
                {
                    pos.x     = pos.right() - .icon.sizeX
                    pos.width = .icon.sizeX
                }

            case Right:
                sf.horzAlignment = .Right
                if !hasIcon and (.arrowPos == .Top or .arrowPos == .Bottom) do
                    sf.horzAlignment = .Center
                bc.painter.drawRichString(pos, &.name, sf)
                pos.width -= .name.boundRect.width + metrics.btnIcon_SpacingTextH

                if !.icon.isValid() do
                    .icon.sizeX = pos.width
                if pos.width < .icon.sizeX
                {
                    let ratio = .icon.sizeX / .icon.sizeY
                    .icon.sizeX = pos.width * ratio
                    .icon.sizeY = pos.width
                }
                else
                {
                    pos.width = .icon.sizeX
                }

            case Top:
                sf.vertAlignment = .Top
                bc.painter.drawRichString(pos, &.name, sf)
                pos.moveTop(sf.font.regular.height + metrics.btnIcon_SpacingTextV)

                if !.icon.isValid() do
                    .icon.sizeY = pos.height
                if pos.height < .icon.sizeY
                {
                    let ratio = .icon.sizeX / .icon.sizeY
                    .icon.sizeX = pos.height * ratio
                    .icon.sizeY = pos.height
                }
                else
                {
                    pos.y      = pos.bottom() - .icon.sizeY
                    pos.height = .icon.sizeY
                }

            case Bottom:
                sf.vertAlignment = .Bottom
                bc.painter.drawRichString(pos, &.name, sf)

                pos.height -= sf.font.regular.height + metrics.btnIcon_SpacingTextV
                if !.icon.isValid() do
                    .icon.sizeY = pos.height
                if pos.height < .icon.sizeY
                {
                    let ratio = .icon.sizeX / .icon.sizeY
                    .icon.sizeX = pos.height * ratio
                    .icon.sizeY = pos.height
                }
                else do
                    pos.height = .icon.sizeY
            }
        }

        // Icon
        if .sigPaintIcon
        {
            .sigPaintIcon(me, bc, pos, paintFlags)
        }
        elif .name.isEmpty() or .iconBtnFlags.has(.HideName)
        {
            pos.x = pos.horzCenter() - .icon.sizeX * 0.5
            pos.y = pos.vertCenter() - .icon.sizeY * 0.5
            .icon.paint(bc.painter, pos.x, pos.y, colorIcon)
        }
        else
        {
            switch .textPos
            {
            case Left:
                pos.x = pos.right() - .icon.sizeX
                pos.y = pos.vertCenter() - .icon.sizeY * 0.5
                .icon.paint(bc.painter, pos.x, pos.y, colorIcon)
            case Right:
                pos.y = pos.vertCenter() - .icon.sizeY * 0.5
                .icon.paint(bc.painter, pos.x, pos.y, colorIcon)
            case Top:
                pos.x = pos.horzCenter() - .icon.sizeX * 0.5
                pos.y = pos.bottom() - .icon.sizeY
                .icon.paint(bc.painter, pos.x, pos.y, colorIcon)
            case Bottom:
                pos.x = pos.horzCenter() - .icon.sizeX * 0.5
                .icon.paint(bc.painter, pos.x, pos.y, colorIcon)
            }
        }

        // Overlay state layer: a translucent wash of the foreground color drawn over everything,
        // so hover/press/checked reads elegantly on ANY background (it darkens on light themes and
        // lightens on dark ones) instead of an opaque box that clashes with a pastel accent row or
        // tints a color swatch with a hard fill.
        if overlay and !bc.isDisabled
        {
            var a = 0'f32
            switch
            {
            case .isPressed:
                a = 0.14
            case .isChecked:
                a = 0.10
            case .isHot:
                a = 0.07
            }

            // Animate the alpha in/out for a smooth fade (aniBk is unused in overlay mode).
            .aniBk.apply(me, colorText.withAlpha(cast(u8) (a * 255)))
            let cur = .aniBk.cur()
            if cur.a
            {
                bc.painter.setParams(.Antialiased)
                let rad = .overlayRadius(clientRect)
                bc.painter.fillRoundRect(clientRect, rad, rad, cur)
            }
        }
    }

    // Corner radius of the overlay state layer, matching the button's form.
    mtd overlayRadius(r: Math.Rectangle)->f32
    {
        let m = Math.min(r.width, r.height)
        switch .form
        {
        case Round:
            return m * 0.5
        case RoundSquare:
            return Math.min(m * 0.28, 8.0)
        case Square:
            return 3
        }
        return 4
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if .processMouseEvent(evt)
        {
            if .iconBtnFlags.has(.CheckableToggle)
            {
                .isChecked = !.isChecked
                .postCommandEvent(.id)
                .sigCheckChanged.call(me)
            }
            elif .iconBtnFlags.has(.Checkable)
            {
                if !.isChecked
                {
                    .isChecked = true
                    .postCommandEvent(.id)
                    .sigCheckChanged.call(me)
                }
            }
            else
            {
                .postCommandEvent(.id)
            }

            // Display/Hide popup
            if .iconBtnFlags.has(.Popup)
            {
                if !.popup
                {
                    .sigShowPopup.call(me)
                    if .popup do
                        .getApp().registerHookEvents(me)
                }
            }
        }
    }
}

impl IconButton
{
    #[Swag.Discardable]
    func create(parent: *Wnd, icon: Icon, position: Math.Rectangle = {}, id: #null WndId = null)->*IconButton
    {
        Debug.assert(parent != null)
        var pos = position
        if pos.height == 0 do
            pos.height = parent.getThemeMetrics().btnPush_Height
        if pos.width == 0 do
            pos.width = parent.getThemeMetrics().btnPush_Width
        let res = Wnd.create'IconButton(parent, null, pos, id)
        res.icon    = icon
        res.padding = res.getThemeMetrics().btnIcon_Padding
        if id != null do
            res.updateCommandState()
        return res
    }

    // Set the check state of the button (if the button is checkable)
    mtd setCheck(checked: bool)
    {
        if !.iconBtnFlags.has(.Checkable) do
            return
        if .isChecked == checked do
            return
        .isChecked = checked
        .postCommandEvent(.id)
        .invalidate()
    }

    // Set the button form
    mtd setForm(form: IconButtonForm)
    {
        .form = form
        .invalidate()
    }

    // Creates a popup window linked to the button position.
    mtd createAnchorPopup(w, h: f32)->*FrameWnd
    {
        let pos          = .getSurfaceRect()
        let topView      = .getTopView()
        let metrics      = .getThemeMetrics()
        let anchorHeight = metrics.frameWnd_AnchorHeight
        let sdw          = metrics.frameWnd_SmallShadowSize

        let ptTop        = topView.surfaceToLocal({pos.x, pos.y})
        let ptBottom     = topView.surfaceToLocal({pos.x, pos.bottom()})
        let anchorCenter = topView.surfaceToLocal({pos.horzCenter(), pos.y}).x

        var anchor = FrameWndAnchor.Top
        var x      = ptBottom.x
        var y      = ptBottom.y + anchorHeight

        let availableBelow = topView.position.height - sdw.w - y
        let availableAbove = ptTop.y - anchorHeight - sdw.y
        if availableBelow < h and availableAbove > availableBelow
        {
            anchor = .Bottom
            y      = ptTop.y - anchorHeight - h
        }

        if x + w > topView.position.width - sdw.z do
            x = topView.position.width - w - sdw.z
        x = Math.max(x, sdw.x)

        if y + h > topView.position.height - sdw.w do
            y = topView.position.height - h - sdw.w
        y = Math.max(y, sdw.y)

        with let frame = Wnd.create'FrameWnd(topView, {x, y, w, h})
        {
            .owner = me
            .setFrameForm(.Round)
            .setFrameFlags(.SmallShadow)
            .style.addStyleSheetColors("frameWnd_Border $frameWnd_PopupBorder")
            .anchor    = anchor
            .anchorPos = anchorCenter - .position.x
        }

        .popup = frame
        return frame
    }
}
