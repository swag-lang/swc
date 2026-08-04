#global public

using Core, Pixel

// Selects icon button background geometry.
enum IconButtonForm
{
    Rectangle            // Uses a rectangular background.
    Circle               // Uses a circular background.
    RoundedRectangle     // Uses a rounded rectangular background.
}

// Configures icon button interaction and content presentation.
#[Swag.EnumFlags]
enum IconButtonFlags
{
    None = 0          // Uses a plain button with normal background and label placement.
    Radio             // Checks once on activation and remains checked until changed programmatically.
    Toggle            // Toggles the checked state on every activation.
    Popup             // Requests an owned popup after activation.
    CenterContent     // Centers the combined icon, label, and arrow group.
    IconOnly          // Hides the label while preserving the icon and arrow.
    Flat              // Omits all background and checked-state fills.
    Overlay           // Paints translucent interaction feedback over the content.
}

// Selects arrow placement and direction around icon button content.
enum IconButtonArrowPosition
{
    None              // Draws no arrow.
    Left              // Places a left-pointing arrow before the content.
    Top               // Places an upward arrow above the content.
    Right             // Places a right-pointing arrow after the content.
    RightUpward       // Places an upward arrow after the content.
    RightDownward     // Places a downward arrow after the content.
    Bottom            // Places a downward arrow below the content.
}

// Selects label placement relative to the icon.
enum IconButtonTextPosition
{
    Left       // Places the label before the icon.
    Top        // Places the label above the icon.
    Right      // Places the label after the icon.
    Bottom     // Places the label below the icon.
}

// Selects checked-state indicator placement.
enum IconButtonCheckIndicator
{
    None       // Draws no separate checked-state indicator.
    Bottom     // Draws an indicator along the bottom edge.
    Top        // Draws an indicator along the top edge.
    Left       // Draws an indicator along the left edge.
    Right      // Draws an indicator along the right edge.
    Full       // Fills the complete button background.
}

// Displays an icon action with optional label, checked state, arrow, and owned popup.
struct IconButton
{
    using button: Button     // Embedded button behavior and presentation.

    sigPopupClosed:    SigArray'func||(*IconButton)                                                 // Emitted before the owned popup is destroyed.
    sigPopupRequested: SigArray'func||(*IconButton)                                                 // Emitted when activation requests popup creation.
    sigCheckedChanged: SigArray'func||(*IconButton)                                                 // Emitted after user activation changes checked state.
    iconPainter:       #null func||(*IconButton, *PaintContext, Math.Rectangle, PaintItemFlags)     // Custom icon painter, or null for `icon`.

    readonly
    {
        iconColor: Color                                   // Explicit icon color, or transparent for theme color.
        textColor: Color                                   // Explicit label color, or transparent for theme color.
        form           = IconButtonForm.Rectangle          // Background geometry.
        checkIndicator = IconButtonCheckIndicator.Full     // Checked-state indicator placement.
        arrowPosition  = IconButtonArrowPosition.None      // Optional arrow placement and direction.
        textPosition   = IconButtonTextPosition.Bottom     // Label placement relative to the icon.
        flags          = IconButtonFlags.None              // Active interaction and content options.
        isChecked: bool                                    // Whether the button is checked.
    }

    // The popup this button owns while it is open, and the background animation.
    internal
    {
        aniBk: BlendColor     // Color animation of the background.
        popup: #null *Wnd     // Popup currently shown by this button.
    }
}

impl IWnd for IconButton
{
    mtd impl onHookEvent(evt: IEvent)
    {
        if !.popup do
            return

        if let ptr = evt as MouseEvent where ptr.kind == .Pressed
        {
            if ptr.target == me or ptr.target == .popup do
                return
            if ptr.target and .popup.isAncestorOf(ptr.target) do
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

        if evt.updatedFields.has(.ToolTip)
        {
            .toolTip = evt.toolTip
        }

        if evt.updatedFields.has(.Checked) and .isChecked != evt.checked
        {
            evt.accepted = true
            .isChecked   = evt.checked
            .invalidate()
        }

        .button.IWnd.onApplyStateEvent(evt)
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let bc      = evt.paintContext
        let theme   = .theme()
        let colors  = .themeColors()
        let rects   = .themeRects()
        let metrics = .themeMetrics()
        var icon    = .icon

        var subRectBk:    #null *ThemeImageRect
        var colorBk:      Color = undefined
        var colorIcon:    Color = undefined
        var colorText:    Color = undefined
        var colorChecked: Color = undefined

        switch .form
        {
        case .Rectangle:        subRectBk = &rects.btnIcon_SquareBk
        case .Circle:           subRectBk = &rects.btnIcon_RoundBk
        case .RoundedRectangle: subRectBk = &rects.btnIcon_RoundSquareBk
        }

        var paintFlags: PaintItemFlags = .None
        switch
        {
        case bc.isDisabled:
            colorBk      = .isChecked ? colors.btnIcon_CheckedDisabledBk : colors.btnIcon_DisabledBk
            colorIcon    = .isChecked ? colors.btnIcon_CheckedDisabledIcon : colors.btnIcon_DisabledIcon
            colorText    = .isChecked ? colors.btnIcon_CheckedDisabledText : colors.btnIcon_DisabledText
            colorChecked = colors.btnIcon_CheckedDisabledMark

        case (.isPressed or .isChecked) and .checkIndicator == .None:
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

        if icon.color.a do
            colorIcon = icon.color
        if .iconColor.a do
            colorIcon = .iconColor
        if .textColor.a do
            colorText = .textColor

        // Background. A flat button paints no box in any state; an overlay button paints its
        // hot/pressed/checked state as a translucent layer over the content instead (drawn at the
        // end of this method). Both are useful for inline affordances (a color swatch, the reset
        // arrow) where a solid themed fill would clash with the row background, especially over a
        // selected (accent) row.
        let clientRect = .clientRect()
        let flat       = .flags.has(.Flat)
        let overlay    = .flags.has(.Overlay)
        if !flat and !overlay
        {
            .aniBk.apply(me, colorBk)
            theme.drawSubRect(bc.painter, clientRect, subRectBk, .aniBk.cur())
        }

        if !flat and !overlay and .isChecked and colors.activeRail.a
        {
            let thickness = Math.min(4'f32, Math.min(clientRect.width, clientRect.height))
            var rail      = clientRect
            switch .checkIndicator
            {
            case .Top:
                rail.height = thickness

            case .Left:
                rail.width = thickness

            case .Right:
                rail.x     = rail.right() - thickness
                rail.width = thickness

            case .None, .Bottom, .Full:
                rail.y      = rail.bottom() - thickness
                rail.height = thickness
            }

            bc.painter.fillRect(rail, colors.activeRail)
        }
        elif !flat and !overlay and .isChecked and .checkIndicator != .None
        {
            switch .checkIndicator
            {
            case .Bottom:
                subRectBk = &rects.btnIcon_CheckedBottom

            case .Top:
                subRectBk = &rects.btnIcon_CheckedTop

            case .Left:
                subRectBk = &rects.btnIcon_CheckedLeft

            case .Right:
                subRectBk = &rects.btnIcon_CheckedRight

            case .Full:
                if .form == .Rectangle do
                    subRectBk = &rects.btnIcon_CheckedSquare
                elif .form == .Circle do
                    subRectBk = &rects.btnIcon_CheckedRound
                else do
                    subRectBk = &rects.btnIcon_CheckedRoundSquare
            }

            theme.drawSubRect(bc.painter, clientRect, subRectBk, colorChecked)
        }

        var pos     = .paddedClientRect()
        let hasIcon = icon.isValid() or .iconPainter

        if .iconWidth do
            icon.sizeX = .iconWidth
        if .iconHeight do
            icon.sizeY = .iconHeight

        // Center everything
        var marginArrow = metrics.btnIcon_MarginArrow
        if .flags.has(.CenterContent)
        {
            var nw, nh = 0'f32
            marginArrow = 0

            switch #complete .arrowPosition
            {
            case .Left, .Right, .RightUpward, .RightDownward: nw += metrics.btnIcon_WidthArrow + metrics.btnIcon_SpacingArrowH
            case .Top, .Bottom:                               nh += metrics.btnIcon_HeightArrow + metrics.btnIcon_SpacingArrowV
            case .None:                                       break
            }

            let fontR = nnFont(.font().regular)
            let sm    = Painter.measureString(.name.raw.toString(), fontR)
            nw += sm.width
            nh += fontR.height

            if hasIcon
            {
                switch #complete .textPosition
                {
                case .Left, .Right:
                    nw += metrics.btnIcon_SpacingTextH
                    nw += icon.sizeX

                case .Top, .Bottom:
                    nh += metrics.btnIcon_SpacingTextV
                    nh += icon.sizeY
                }
            }

            pos.x      = pos.horzCenter() - nw * 0.5
            pos.y      = pos.vertCenter() - nh * 0.5
            pos.width  = nw
            pos.height = nh
        }

        // Arrow
        if .arrowPosition != .None
        {
            var posArrow = pos
            let w        = metrics.btnIcon_WidthArrow
            let h        = metrics.btnIcon_HeightArrow

            switch .arrowPosition
            {
            case .Left:
                subRectBk       = &rects.btnIcon_ArrowLeft
                posArrow.width  = h
                posArrow.height = w
                posArrow.x      = pos.x + marginArrow
                posArrow.y      = pos.vertCenter() - w * 0.5
                theme.drawSubRect(bc.painter, posArrow, subRectBk, colorIcon)
                pos.moveLeft(marginArrow + w + metrics.btnIcon_SpacingArrowH)

            case .Top:
                subRectBk       = &rects.btnIcon_ArrowUp
                posArrow.width  = w
                posArrow.height = h
                posArrow.x      = pos.horzCenter() - w * 0.5
                posArrow.y      = pos.y + marginArrow
                theme.drawSubRect(bc.painter, posArrow, subRectBk, colorIcon)
                pos.moveTop(marginArrow + h + metrics.btnIcon_SpacingArrowV)

            case .Right:
                subRectBk       = &rects.btnIcon_ArrowRight
                posArrow.width  = h
                posArrow.height = w
                posArrow.x      = pos.right() - w - marginArrow
                posArrow.y      = pos.vertCenter() - h * 0.5
                theme.drawSubRect(bc.painter, posArrow, subRectBk, colorIcon)
                pos.setRight(posArrow.x - metrics.btnIcon_SpacingArrowH)

            case .RightUpward:
                subRectBk       = &rects.btnIcon_ArrowUp
                posArrow.width  = w
                posArrow.height = h
                posArrow.x      = pos.right() - w - marginArrow
                posArrow.y      = pos.vertCenter() - h * 0.5
                theme.drawSubRect(bc.painter, posArrow, subRectBk, colorIcon)
                pos.setRight(posArrow.x - metrics.btnIcon_SpacingArrowH)

            case .RightDownward:
                subRectBk       = &rects.btnIcon_ArrowDown
                posArrow.width  = w
                posArrow.height = h
                posArrow.x      = pos.right() - w - marginArrow
                posArrow.y      = pos.vertCenter() - h * 0.5
                theme.drawSubRect(bc.painter, posArrow, subRectBk, colorIcon)
                pos.setRight(posArrow.x - metrics.btnIcon_SpacingArrowH)

            case .Bottom:
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
        if !.name.isEmpty() and !.flags.has(.IconOnly)
        {
            var sf: RichStringFormat
            theme.setTextColors(&sf, colorText)
            sf.font          = .font()
            sf.horzAlignment = .Center
            sf.vertAlignment = .Center
            sf.flags         = .DontAdaptSingleLineHeight
            switch .textPosition
            {
            case .Left:
                sf.horzAlignment = .Left
                if !hasIcon and (.arrowPosition == .Top or .arrowPosition == .Bottom) do
                    sf.horzAlignment = .Center
                bc.painter.drawRichString(pos, &.name, sf)
                pos.moveLeft(.name.boundRect.width + metrics.btnIcon_SpacingTextH)

                if !icon.isValid() do
                    icon.sizeX = pos.width
                if pos.width < icon.sizeX
                {
                    let ratio = icon.sizeX / icon.sizeY
                    icon.sizeX = pos.width * ratio
                    icon.sizeY = pos.width
                }
                else
                {
                    pos.x     = pos.right() - icon.sizeX
                    pos.width = icon.sizeX
                }

            case .Right:
                sf.horzAlignment = .Right
                if !hasIcon and (.arrowPosition == .Top or .arrowPosition == .Bottom) do
                    sf.horzAlignment = .Center
                bc.painter.drawRichString(pos, &.name, sf)
                pos.width -= .name.boundRect.width + metrics.btnIcon_SpacingTextH

                if !icon.isValid() do
                    icon.sizeX = pos.width
                if pos.width < icon.sizeX
                {
                    let ratio = icon.sizeX / icon.sizeY
                    icon.sizeX = pos.width * ratio
                    icon.sizeY = pos.width
                }
                else
                {
                    pos.width = icon.sizeX
                }

            case .Top:
                sf.vertAlignment = .Top
                bc.painter.drawRichString(pos, &.name, sf)
                pos.moveTop(sf.font.regular!.height + metrics.btnIcon_SpacingTextV)

                if !icon.isValid() do
                    icon.sizeY = pos.height
                if pos.height < icon.sizeY
                {
                    let ratio = icon.sizeX / icon.sizeY
                    icon.sizeX = pos.height * ratio
                    icon.sizeY = pos.height
                }
                else
                {
                    pos.y      = pos.bottom() - icon.sizeY
                    pos.height = icon.sizeY
                }

            case .Bottom:
                sf.vertAlignment = .Bottom
                bc.painter.drawRichString(pos, &.name, sf)

                pos.height -= sf.font.regular!.height + metrics.btnIcon_SpacingTextV
                if !icon.isValid() do
                    icon.sizeY = pos.height
                if pos.height < icon.sizeY
                {
                    let ratio = icon.sizeX / icon.sizeY
                    icon.sizeX = pos.height * ratio
                    icon.sizeY = pos.height
                }
                else do
                    pos.height = icon.sizeY
            }
        }

        // Icon
        if .iconPainter
        {
            .iconPainter(me, bc, pos, paintFlags)
        }
        elif .name.isEmpty() or .flags.has(.IconOnly)
        {
            pos.x = pos.horzCenter() - icon.sizeX * 0.5
            pos.y = pos.vertCenter() - icon.sizeY * 0.5
            icon.paint(bc.painter, pos.x, pos.y, colorIcon)
        }
        else
        {
            switch .textPosition
            {
            case .Left:
                pos.x = pos.right() - icon.sizeX
                pos.y = pos.vertCenter() - icon.sizeY * 0.5
                icon.paint(bc.painter, pos.x, pos.y, colorIcon)

            case .Right:
                pos.y = pos.vertCenter() - icon.sizeY * 0.5
                icon.paint(bc.painter, pos.x, pos.y, colorIcon)

            case .Top:
                pos.x = pos.horzCenter() - icon.sizeX * 0.5
                pos.y = pos.bottom() - icon.sizeY
                icon.paint(bc.painter, pos.x, pos.y, colorIcon)

            case .Bottom:
                pos.x = pos.horzCenter() - icon.sizeX * 0.5
                icon.paint(bc.painter, pos.x, pos.y, colorIcon)
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
            case .isPressed: a = 0.14
            case .isChecked: a = 0.10
            case .isHot:     a = 0.07
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
        case .Circle:           return m * 0.5
        case .RoundedRectangle: return Math.min(m * 0.28, 8.0)
        case .Rectangle:        return 3
        }

        return 4
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if .processMouseEvent(evt) do
            .activateFromUser()
    }

    // Space or Enter activates the focused button.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed or (evt.key != .Space and evt.key != .Return) do
            return

        .sigPressed.call(cast(*Button) me)
        .activateFromUser()
        evt.accepted = true
    }
}

private impl IconButton
{
    mtd activateFromUser()
    {
        var stateChanged: bool
        if .flags.has(.Toggle)
        {
            .isChecked   = !.isChecked
            stateChanged = true
        }
        elif .flags.has(.Radio) and !.isChecked
        {
            .isChecked   = true
            stateChanged = true
        }

        if stateChanged
        {
            .invalidate()
            .postCommandEvent(.id)
            .sigCheckedChanged.call(me)
        }
        elif !.flags.has(.Radio) and !.flags.has(.Toggle) do
            .postCommandEvent(.id)

        if .flags.has(.Popup) and !.popup
        {
            .sigPopupRequested.call(me)
            if .popup do
                .app().registerHookEvents(me)
        }
    }
}

impl IconButton
{
    // Replaces the displayed icon.
    mtd setIcon(icon: Icon) => .button.setIcon(icon)

    // Removes the displayed icon.
    mtd clearIcon() => .button.clearIcon()

    // Overrides the icon draw size; zero preserves an axis from the icon descriptor.
    mtd setIconSize(width, height: f32) => .button.setIconSize(width, height)

    // Changes the icon tint; a transparent color restores the current theme color.
    mtd setIconColor(color: Color)
    {
        if .iconColor == color do
            return
        .iconColor = color
        .invalidate()
    }

    // Changes the label color; a transparent color restores the current theme color.
    mtd setTextColor(color: Color)
    {
        if .textColor == color do
            return
        .textColor = color
        .invalidate()
    }

    // Installs a custom icon painter, or restores descriptor painting when null.
    mtd setIconPainter(painter: #null func||(*IconButton, *PaintContext, Math.Rectangle, PaintItemFlags))
    {
        .iconPainter = painter
        .invalidate()
    }

    // Closes and destroys the owned popup, if any.
    mtd hidePopup()
    {
        if !.popup do
            return

        .app().unregisterHookEvents(me)
        .sigPopupClosed.call(me)
        .popup.destroy()
        .popup     = null
        .isChecked = false
        .invalidate()
    }

    // Creates an icon button with optional command identifier and interaction flags.
    #[Swag.Discardable]
    func create(parent: *Wnd, icon: Icon, position: Math.Rectangle = {}, id: #null WndId = null, flags = IconButtonFlags.None)->*IconButton
    {
        Debug.assert(parent != null)
        var pos = position
        if pos.height == 0 do
            pos.height = parent.themeMetrics().btnPush_Height
        if pos.width == 0 do
            pos.width = parent.themeMetrics().btnPush_Width
        let res = Wnd.create'IconButton(parent, null, pos, id)
        res.setIcon(icon)
        res.padding = res.themeMetrics().btnIcon_Padding
        res.updateFlags(flags)
        if id != null do
            res.updateCommandState()
        return res
    }

    // Changes checked state silently for a radio or toggle button.
    mtd setChecked(checked: bool)
    {
        Debug.assert(.flags.has(.Radio) or .flags.has(.Toggle))
        if .isChecked == checked do
            return
        .isChecked = checked
        .invalidate()
    }

    // Adds and removes interaction options and repaints the button.
    mtd updateFlags(add: IconButtonFlags = .None, remove = IconButtonFlags.None)
    {
        var newFlags = .flags
        newFlags.add(add)
        newFlags.remove(remove)
        Debug.assert(!(newFlags.has(.Radio) and newFlags.has(.Toggle)), "radio and toggle modes are mutually exclusive")
        .flags = newFlags
        if !.flags.has(.Radio) and !.flags.has(.Toggle) do
            .isChecked = false
        .invalidate()
    }

    // Changes background geometry and repaints the button.
    mtd setForm(form: IconButtonForm)
    {
        if .form == form do
            return
        .form = form
        .invalidate()
    }

    // Changes checked-state indicator placement and repaints the button.
    mtd setCheckIndicator(indicator: IconButtonCheckIndicator)
    {
        if .checkIndicator == indicator do
            return
        .checkIndicator = indicator
        .invalidate()
    }

    // Changes arrow placement and direction and repaints the button.
    mtd setArrowPosition(position: IconButtonArrowPosition)
    {
        if .arrowPosition == position do
            return
        .arrowPosition = position
        .invalidate()
    }

    // Changes label placement relative to the icon and repaints the button.
    mtd setTextPosition(position: IconButtonTextPosition)
    {
        if .textPosition == position do
            return
        .textPosition = position
        .invalidate()
    }

    // Creates and owns a popup anchored above or below the button.
    mtd createAnchorPopup(width, height: f32)->*FrameWnd
    {
        Debug.assert(width >= 0 and height >= 0)
        if .popup do
            me.hidePopup()
        let pos          = .surfaceRect()
        let topView      = .topView()
        let metrics      = .themeMetrics()
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
        if availableBelow < height and availableAbove > availableBelow
        {
            anchor = .Bottom
            y      = ptTop.y - anchorHeight - height
        }

        if x + width > topView.position.width - sdw.z do
            x = topView.position.width - width - sdw.z
        x = Math.max(x, sdw.x)

        if y + height > topView.position.height - sdw.w do
            y = topView.position.height - height - sdw.w
        y = Math.max(y, sdw.y)

        with let frame = Wnd.create'FrameWnd(topView, {x, y, width, height})
        {
            .owner = me
            .setFrameForm(.themeColors().activeRail.a ? .Square : .Round)
            .setFrameFlags(.SmallShadow)
            .style.addStyleSheetColors("frameWnd_Border $frameWnd_PopupBorder")
            .anchor         = anchor
            .anchorPosition = anchorCenter - .position.x
        }

        .popup = frame
        return frame
    }
}
