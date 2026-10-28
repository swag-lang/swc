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
    None       // Draws no separate checked-state indicator, and reads as pressed while checked.
    Ink        // Draws no indicator either, and says it is checked with the checked ink alone.
    Frame      // Draws the selection ground and an Arc outline around the complete button.
    Bottom     // Draws a two-pixel Arc rule along the bottom edge.
    Top        // Draws a two-pixel Arc rule along the top edge.
    Left       // Draws a two-pixel Arc rule along the left edge.
    Right      // Draws a two-pixel Arc rule along the right edge.
    Full       // Fills the button with the selection ground inside a faint Arc ring.
}

// Displays an icon action with optional label, checked state, arrow, and owned popup.
struct IconButton
{
    public
    {
        using button: Button     // Embedded button behavior and presentation.

        sigPopupClosed:    SigArray'func||(*Wnd)     // Emitted before the owned popup is destroyed.
        sigPopupRequested: SigArray'func||(*Wnd)     // Emitted when activation requests popup creation.
        sigCheckedChanged: SigArray'func||(*Wnd)     // Emitted after user activation changes checked state.
        iconPainter:       (func||(*IconButton, *PaintContext, Math.Rectangle, PaintItemFlags))?     // Custom icon painter, or null for `icon`.

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
    }

    // The popup this button owns while it is open, and the background animation.
    aniBk: BlendColor     // Color animation of the background.
    popup: *Wnd?          // Popup currently shown by this button.
}

// Returns the chevron a given arrow placement points with.
//
// `RightUpward` and `RightDownward` place the arrow where `Right` does and point it elsewhere,
// which is why the placement alone cannot say which glyph to draw.
private func arrowGlyph(position: IconButtonArrowPosition)->ThemeIcons
{
    switch #complete position
    {
    case .Left:                   return .ChevronLeft
    case .Top, .RightUpward:      return .ChevronUp
    case .Right:                  return .ChevronRight
    case .Bottom, .RightDownward: return .ChevronDown
    case .None:                   return .ChevronDown
    }
}

impl IWnd for IconButton
{
    // Reports the room the icon, the label, and the arrow need.
    //
    // The label sits beside the icon or under it, so the axis it grows along follows
    // [[Gui.IconButton.textPosition]]: a toolbar showing captions widens with a longer
    // translation rather than crowding it. A button hiding its label
    // ([[Gui.IconButtonFlags.IconOnly]]) answers for its icon alone.
    mtd impl measureContent(_: Math.Point)->Math.Point
    {
        let metrics = .themeMetrics()

        var iconWidth  = .iconWidth != 0 ? .iconWidth : .icon.sizeX
        var iconHeight = .iconHeight != 0 ? .iconHeight : .icon.sizeY
        if not .icon.isValid()
        {
            iconWidth  = 0
            iconHeight = 0
        }

        var width  = iconWidth
        var height = iconHeight

        let showsLabel = not .name.isEmpty() and not .flags.has(.IconOnly)
        if showsLabel
        {
            .name.compute()
            var format: RichStringFormat
            format.font = .font()
            Painter.computeLayout({0, 0, MaxTextLayoutExtent, MaxTextLayoutExtent}, &.name, format, .deviceScale())

            let labelWidth  = .name.boundRect.width
            let labelHeight = .name.boundRect.height
            switch #complete .textPosition
            {
            case .Left, .Right:
                width  += labelWidth + (iconWidth != 0 ? metrics.btnIcon_SpacingTextH : 0)
                height = Math.max(height, labelHeight)

            case .Top, .Bottom:
                width  = Math.max(width, labelWidth)
                height += labelHeight + (iconHeight != 0 ? metrics.btnIcon_SpacingTextV : 0)
            }
        }

        // The arrow stands on one side of the whole group, with its own margin and spacing. It is
        // a chevron of the theme icon set, so its box is square whichever way it points.
        let arrowSize   = metrics.btnIcon_ArrowSize
        let arrowMargin = .flags.has(.CenterContent) ? 0 : metrics.btnIcon_MarginArrow
        switch #complete .arrowPosition
        {
        case .None:
            break

        case .Left, .Right, .RightUpward, .RightDownward:
            width  += arrowSize + arrowMargin + metrics.btnIcon_SpacingArrowH
            height = Math.max(height, arrowSize)

        case .Top, .Bottom:
            width  = Math.max(width, arrowSize)
            height += arrowSize + arrowMargin + metrics.btnIcon_SpacingArrowV
        }

        let padding = 2 * metrics.btnIcon_Padding
        return Math.Point{width + padding, height + padding}
    }

    mtd impl onHookEvent(evt: IEvent)
    {
        if not .popup do
            return

        if evt is MouseEvent as ptr where ptr.kind == .Pressed
        {
            if ptr.target == me or ptr.target == .popup do
                return
            if ptr.target and .popup.isAncestorOf(ptr.target) do
                return
            .hidePopup()
        }
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
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

        var subRectBk:    *ThemeImageRect?
        var colorBk:      Color
        var colorIcon:    Color
        var colorText:    Color
        var colorChecked: Color

        switch .form
        {
        case .Rectangle:        subRectBk = &rects.btnIcon_SquareBk
        case .Circle:           subRectBk = &rects.btnIcon_RoundBk
        case .RoundedRectangle: subRectBk = &rects.btnIcon_RoundSquareBk
        }

        // The form is the shape, so the focus ring follows it and a circular tool is never
        // marked with a box. It is published even for a flat button, which paints no box: the
        // ring is the only edge such a button has, and it stands for the form all the same.
        //
        // The checked frame answers to the form for the same reason. It is drawn over the fill the
        // hovered state leaves under it, so a corner the two do not share is a corner where the
        // mark cuts across its own button: a square tool marked with a rounded hairline reads as
        // two controls stacked rather than as one that is picked.
        let framedRadius = Math.max(subRectBk!.radius - 0.5, 0)
        .focusRingRadius = subRectBk.radius

        var paintFlags: PaintItemFlags = .None
        switch
        {
        case bc.isDisabled:
            colorBk      = .isChecked and .checkIndicator == .Frame ? colors.btnIcon_CheckedFrameDisabledBk : (.isChecked ? colors.btnIcon_CheckedDisabledBk : colors.btnIcon_DisabledBk)
            colorIcon    = .isChecked ? colors.btnIcon_CheckedDisabledIcon : colors.btnIcon_DisabledIcon
            colorText    = .isChecked ? colors.btnIcon_CheckedDisabledText : colors.btnIcon_DisabledText
            colorChecked = .checkIndicator == .Frame ? colors.btnIcon_CheckedFrameDisabledBorder : colors.btnIcon_CheckedDisabledMark

        case (.isPressed or .isChecked) and .checkIndicator == .None:
            colorBk      = .isChecked ? colors.btnIcon_CheckedPressedBk : colors.btnIcon_PressedBk
            colorIcon    = colors.btnIcon_PressedIcon
            colorText    = colors.btnIcon_PressedText
            colorChecked = colors.btnIcon_CheckedPressedMark

        case .isPressed:
            colorBk      = .isChecked and .checkIndicator == .Frame ? colors.btnIcon_CheckedFramePressedBk : (.isChecked ? colors.btnIcon_CheckedPressedBk : colors.btnIcon_PressedBk)
            colorIcon    = .isChecked ? colors.btnIcon_CheckedPressedIcon : colors.btnIcon_PressedIcon
            colorText    = .isChecked ? colors.btnIcon_CheckedPressedText : colors.btnIcon_PressedText
            colorChecked = .checkIndicator == .Frame ? colors.btnIcon_CheckedFramePressedBorder : colors.btnIcon_CheckedPressedMark

        case .isHot:
            colorBk      = .isChecked and .checkIndicator == .Frame ? colors.btnIcon_CheckedFrameHotBk : (.isChecked ? colors.btnIcon_CheckedHotBk : colors.btnIcon_HotBk)
            colorIcon    = .isChecked ? colors.btnIcon_CheckedHotIcon : colors.btnIcon_HotIcon
            colorText    = .isChecked ? colors.btnIcon_CheckedHotText : colors.btnIcon_HotText
            colorChecked = .checkIndicator == .Frame ? colors.btnIcon_CheckedFrameHotBorder : colors.btnIcon_CheckedHotMark

        default:
            colorBk      = .isChecked and .checkIndicator == .Frame ? colors.btnIcon_CheckedFrameBk : (.isChecked ? colors.btnIcon_CheckedBk : colors.btnIcon_Bk)
            colorIcon    = .isChecked ? colors.btnIcon_CheckedIcon : colors.btnIcon_Icon
            colorText    = .isChecked ? colors.btnIcon_CheckedText : colors.btnIcon_Text
            colorChecked = .checkIndicator == .Frame ? colors.btnIcon_CheckedFrameBorder : colors.btnIcon_CheckedMark
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

        if not flat and not overlay
        {
            .aniBk.apply(me, colorBk)
            theme.drawSubRect(bc.painter, clientRect, subRectBk, .aniBk.cur())
        }

        // A checked button says so with a mark of its own, unless it was told to draw none:
        // `None` then reads as pressed and `Ink` keeps the checked ink, and both leave the box
        // exactly as the state colors above left it.
        let marked = not flat and
                     not overlay and
                     .isChecked and
                     .checkIndicator != .None and
                     .checkIndicator != .Ink
        if marked and .checkIndicator == .Frame
        {
            bc.painter.drawRoundRect(clientRect, framedRadius, framedRadius, colorChecked, 1)
        }
        elif marked
        {
            // A rule on one edge is the two-pixel Arc underline of a tab; a full mark is the
            // selection ground inside a faint Arc ring, which keeps the cell an object on any ground.
            switch .checkIndicator
            {
            case .Bottom: theme.drawSubRect(bc.painter, clientRect, &rects.btnIcon_CheckedBottom, bc.isDisabled ? colors.btnIcon_CheckedDisabledMark : colors.btnIcon_CheckedRule)
            case .Top:    theme.drawSubRect(bc.painter, clientRect, &rects.btnIcon_CheckedTop, bc.isDisabled ? colors.btnIcon_CheckedDisabledMark : colors.btnIcon_CheckedRule)
            case .Left:   theme.drawSubRect(bc.painter, clientRect, &rects.btnIcon_CheckedLeft, bc.isDisabled ? colors.btnIcon_CheckedDisabledMark : colors.btnIcon_CheckedRule)
            case .Right:  theme.drawSubRect(bc.painter, clientRect, &rects.btnIcon_CheckedRight, bc.isDisabled ? colors.btnIcon_CheckedDisabledMark : colors.btnIcon_CheckedRule)

            case .Full:
                switch .form
                {
                case .Rectangle: subRectBk = &rects.btnIcon_CheckedSquare
                case .Circle:    subRectBk = &rects.btnIcon_CheckedRound
                default:         subRectBk = &rects.btnIcon_CheckedRoundSquare
                }

                theme.drawSubRect(bc.painter, clientRect, subRectBk, colorChecked)
                if .form != .Circle and not bc.isDisabled do
                    theme.drawSubRect(bc.painter, clientRect, &rects.btnIcon_CheckedRing, colors.btnIcon_CheckedRing)
                .focusRingRadius = subRectBk.radius
            }
        }

        var pos     = .paddedClientRect()
        let hasIcon = icon.isValid() or .iconPainter

        if .iconWidth do
            icon.sizeX = .iconWidth
        if .iconHeight do
            icon.sizeY = .iconHeight

        // Center the exact group that will be painted. A label-less button is an icon and an
        // optional disclosure marker on one line; counting the absent label's font height used to
        // treat that icon as if it were stacked above text, so neither part was centered in the
        // button and the two marks appeared to run into each other.
        var marginArrow = metrics.btnIcon_MarginArrow
        if .flags.has(.CenterContent)
        {
            var nw = hasIcon ? icon.sizeX : 0
            var nh = hasIcon ? icon.sizeY : 0
            marginArrow = 0

            let showsLabel = not .name.isEmpty() and not .flags.has(.IconOnly)
            if showsLabel
            {
                let fontR = nnFont(.font().regular)
                let sm    = Painter.measureString(.name.raw.toString(), fontR)
                switch #complete .textPosition
                {
                case .Left, .Right:
                    nw += sm.width + (hasIcon ? metrics.btnIcon_SpacingTextH : 0)
                    nh = Math.max(nh, fontR.height)

                case .Top, .Bottom:
                    nw = Math.max(nw, sm.width)
                    nh += fontR.height + (hasIcon ? metrics.btnIcon_SpacingTextV : 0)
                }
            }

            switch #complete .arrowPosition
            {
            case .Left, .Right, .RightUpward, .RightDownward:
                nw += metrics.btnIcon_ArrowSize + metrics.btnIcon_SpacingArrowH
                nh = Math.max(nh, metrics.btnIcon_ArrowSize)

            case .Top, .Bottom:
                nw = Math.max(nw, metrics.btnIcon_ArrowSize)
                nh += metrics.btnIcon_ArrowSize + metrics.btnIcon_SpacingArrowV

            case .None:
                break
            }

            pos.x      = pos.horzCenter() - nw * 0.5
            pos.y      = pos.vertCenter() - nh * 0.5
            pos.width  = nw
            pos.height = nh
        }

        // Arrow. It is a chevron of the theme icon set — the same glyph a combo box, a submenu and
        // a tree row use — so the button says "there is more this way" in the one shape the rest of
        // the interface says it in. Its box is square, and the ink inside it is centered, so one
        // size answers for every direction.
        if .arrowPosition != .None
        {
            let side  = metrics.btnIcon_ArrowSize
            let arrow = theme.icon(arrowGlyph(.arrowPosition), side)

            var arrowX, arrowY: f32
            switch .arrowPosition
            {
            case .Left:
                arrowX = pos.x + marginArrow
                arrowY = .lineTop(pos.vertCenter(), side)
                pos.moveLeft(marginArrow + side + metrics.btnIcon_SpacingArrowH)

            case .Top:
                arrowX = pos.horzCenter() - side * 0.5
                arrowY = pos.y + marginArrow
                pos.moveTop(marginArrow + side + metrics.btnIcon_SpacingArrowV)

            case .Right, .RightUpward, .RightDownward:
                arrowX = pos.right() - side - marginArrow
                arrowY = .lineTop(pos.vertCenter(), side)
                pos.setRight(arrowX - metrics.btnIcon_SpacingArrowH)

            case .Bottom:
                arrowX = pos.horzCenter() - side * 0.5
                arrowY = pos.bottom() - side - marginArrow
                pos.setBottom(arrowY - metrics.btnIcon_SpacingArrowV)
            }

            arrow.paint(bc.painter, arrowX, arrowY, colorIcon)
        }

        // Name
        if not .name.isEmpty() and not .flags.has(.IconOnly)
        {
            var sf: RichStringFormat
            theme.setTextColors(&sf, colorText)
            sf.font = .font()
            sf.horzAlignment = .Center
            sf.vertAlignment = .Center
            switch .textPosition
            {
            case .Left:
                sf.horzAlignment = .Left
                if not hasIcon and (.arrowPosition == .Top or .arrowPosition == .Bottom) do
                    sf.horzAlignment = .Center
                bc.painter.drawRichString(pos, &.name, sf)
                pos.moveLeft(.name.boundRect.width + metrics.btnIcon_SpacingTextH)

                if not icon.isValid() do
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

                // The label stands beside the glyph, not against the far edge of the cell:
                // pushed to the other end of a wide row it reads as a second column rather
                // than as the name of the glyph it belongs to.
                sf.horzAlignment = .Left
                if not hasIcon and (.arrowPosition == .Top or .arrowPosition == .Bottom) do
                    sf.horzAlignment = .Center

                // A painter that declares no size keeps taking what the label leaves it.
                if not icon.isValid() and not .iconWidth
                {
                    let textWidth = Painter.measureString(.name.raw.toString(), nnFont(sf.font.regular)).width
                    icon.sizeX = Math.max(pos.width - textWidth - metrics.btnIcon_SpacingTextH, 0)
                }

                if pos.width < icon.sizeX
                {
                    let ratio = icon.sizeX / icon.sizeY
                    icon.sizeX = pos.width * ratio
                    icon.sizeY = pos.width
                }

                var posText = pos
                posText.moveLeft(icon.sizeX + metrics.btnIcon_SpacingTextH)
                bc.painter.drawRichString(posText, &.name, sf)
                pos.width = icon.sizeX

            case .Top:
                sf.vertAlignment = .Top
                bc.painter.drawRichString(pos, &.name, sf)
                pos.moveTop(sf.font.regular!.height + metrics.btnIcon_SpacingTextV)

                if not icon.isValid() do
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
                if not icon.isValid() do
                    icon.sizeY = pos.height
                if pos.height < icon.sizeY
                {
                    let ratio = icon.sizeX / icon.sizeY
                    icon.sizeX = pos.height * ratio
                    icon.sizeY = pos.height
                }
                else
                {
                    pos.height = icon.sizeY
                }
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
            // A glyph on the same line as the label is placed level with the word, not with
            // the middle of the cell; one stacked above or below it keeps the geometric edge.
            switch .textPosition
            {
            case .Left:
                pos.x = pos.right() - icon.sizeX
                pos.y = opticalTop(.font(), pos.vertCenter(), icon.sizeY)
                icon.paint(bc.painter, pos.x, pos.y, colorIcon)

            case .Right:
                pos.y = opticalTop(.font(), pos.vertCenter(), icon.sizeY)
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
        if overlay and not bc.isDisabled
        {
            var a = 0'f32
            switch
            {
            case .isPressed: a = 0.14
            case .isChecked: a = 0.10
            case .isHot:     a = 0.07
            }

            // Animate the alpha in/out for a smooth fade (aniBk is unused in overlay mode).
            .aniBk.apply(me, colorText.withAlpha(cast(u8, (a * 255))))
            let cur = .aniBk.cur()
            if cur.a
            {
                bc.painter.setParams(.Antialiased)
                let rad = subRectBk.radius
                bc.painter.fillRoundRect(clientRect, rad, rad, cur)
            }
        }
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

        .sigPressed.call(cast(*Button, me))
        .activateFromUser()
        evt.accepted = true
    }
}

private impl IconButton
{
    // Y of the top edge of `size` placed on the content line, `centerY` being the middle of
    // the box it stands in.
    //
    // A glyph or an arrow sharing the line of a label is levelled with the word rather than
    // with the box, or it reads as having slipped under the text. A button showing no label
    // has nothing to be level with and keeps the middle.
    mtd lineTop(centerY, size: f32)->f32
    {
        if .name.isEmpty() or .flags.has(.IconOnly) do
            return centerY - size * 0.5
        return opticalTop(.font(), centerY, size)
    }

    mtd activateFromUser()
    {
        var stateChanged: bool
        if .flags.has(.Toggle)
        {
            .isChecked   = not .isChecked
            stateChanged = true
        }
        elif .flags.has(.Radio) and not .isChecked
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
        elif not .flags.has(.Radio) and not .flags.has(.Toggle)
        {
            .postCommandEvent(.id)
        }

        if .flags.has(.Popup) and not .popup
        {
            .sigPopupRequested.call(me)
            if .popup do
                .app().registerHookEvents(me)
        }
    }
}

impl IconButton
{
    // Paints the compact identity of this button inside the tab an attached menu owns while it is open.
    //
    // Menu buttons use one horizontal reading order here: glyph, wording, disclosure.
    // The popup supplies the selected background and border, while this helper preserves the
    // exact glyph sizes, font and spacing of the closed button.
    internal mtd paintMenuAnchorContent(painter: *Painter, rect: Math.Rectangle, color: Color)
    {
        let metrics = .themeMetrics()
        let theme   = .theme()
        var icon    = .icon
        if .iconWidth do
            icon.sizeX = .iconWidth
        if .iconHeight do
            icon.sizeY = .iconHeight

        let hasIcon   = icon.isValid()
        let showsText = not .name.isEmpty() and not .flags.has(.IconOnly)
        var textWidth = 0'f32
        if showsText do
            textWidth = Painter.measureString(.name.raw.toString(), nnFont(.font().regular)).width

        var width = hasIcon ? icon.sizeX : 0
        if showsText
        {
            if hasIcon do
                width += metrics.btnIcon_SpacingTextH
            width += textWidth
        }

        if .arrowPosition != .None
        {
            if width do
                width += metrics.btnIcon_SpacingArrowH
            width += metrics.btnIcon_ArrowSize
        }

        var x = rect.horzCenter() - width * 0.5
        if hasIcon
        {
            icon.paint(painter, x, .lineTop(rect.vertCenter(), icon.sizeY), color)
            x += icon.sizeX
            if showsText do
                x += metrics.btnIcon_SpacingTextH
        }

        if showsText
        {
            var format: RichStringFormat
            theme.setTextColors(&format, color)
            format.font          = .font()
            format.horzAlignment = .Left
            format.vertAlignment = .Center
            format.flags         = .Clip
            painter.drawRichString(Math.Rectangle{x, rect.y, textWidth, rect.height}, &.name, format)
            x += textWidth
        }

        if .arrowPosition != .None
        {
            if hasIcon or showsText do
                x += metrics.btnIcon_SpacingArrowH
            let side  = metrics.btnIcon_ArrowSize
            let arrow = theme.icon(arrowGlyph(.arrowPosition), side)
            arrow.paint(painter, x, .lineTop(rect.vertCenter(), side), color)
        }
    }

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
    mtd setIconPainter(painter: (func||(*IconButton, *PaintContext, Math.Rectangle, PaintItemFlags))?)
    {
        .iconPainter = painter
        .invalidate()
    }

    // Closes and destroys the owned popup, if any.
    mtd hidePopup()
    {
        if not .popup do
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
    func create(parent: *Wnd, icon: Icon, position: Math.Rectangle = {}, id: WndId? = null, flags = IconButtonFlags.None)->*IconButton
    {
        Swag.assert(parent != null)
        var pos = position
        if pos.height == 0 do
            pos.height = parent.themeMetrics().btnPush_Height
        if pos.width == 0 do
            pos.width = parent.themeMetrics().btnPush_Width
        let res = Wnd.create'IconButton(parent, null, pos, id)
        res.focusPolicy = .Tab
        res.wndFlags    |= .ActivatesOnKey
        res.setIcon(icon)
        res.padding = res.themeMetrics().btnIcon_Padding
        res.updateFlags(flags)
        if id != null do
            res.updateCommandState()
        return res
    }

    // Creates a quiet control: its words, with no ground of its own until the pointer comes.
    //
    // With `menu`, a faint chevron after the words says a menu opens; without it, the control acts
    // at once. A `heading` names what the page or the column shows, in the text ink and bold. Write
    // its words with [[Gui.IconButton.setQuietText]], which fits the control to them.
    #[Swag.Discardable]
    func createQuiet(parent: *Wnd, id: WndId? = null, menu = true, heading = false)->*IconButton
    {
        Swag.assert(parent != null)
        let metrics = parent.themeMetrics()
        with let result = IconButton.create(parent, {}, Math.Rectangle{0, 0, 0, metrics.quiet_Height}, id, flags: .CenterContent)
        {
            .setForm(.RoundedRectangle)
            .setTextPosition(.Right)
            if menu do
                .setArrowPosition(.RightDownward)
            if heading
            {
                .style.setFont(parent.theme().createDefaultFont(metrics.defaultFontSize, .Bold), .Regular)
                .style.addStyleSheetColors("btnIcon_Text $label_Text")
            }
        }

        return result
    }

    // Writes `text` on a quiet control and fits the control to its words, and its chevron when it opens a menu.
    mtd setQuietText(text: string)
    {
        // The chevron follows the words at the arrow spacing, as the control measures itself: a
        // chevron set at the far end of a drop-down's arrow cell reads as a separate control.
        .setText(text)
        let content = .itf.measureContent({})
        .resize(Math.ceil(content.x), .position.height)
    }

    // Changes the checked state of a radio or toggle button without emitting a signal or command.
    mtd setChecked(checked: bool)
    {
        Swag.assert(.flags.has(.Radio) or .flags.has(.Toggle))
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
        Swag.assert(not (newFlags.has(.Radio) and newFlags.has(.Toggle)), "radio and toggle modes are mutually exclusive")
        .flags = newFlags
        if not .flags.has(.Radio) and not .flags.has(.Toggle) do
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

    // Creates a `width` by `height` popup frame anchored to the button and makes it the owned popup.
    //
    // The frame opens below the button, or above it when it does not fit below and there is more
    // room above, and stays inside the top view. A popup already open is closed first; [[Gui.IconButton.hidePopup]]
    // destroys the new one.
    mtd createAnchorPopup(width, height: f32)->*FrameWnd
    {
        Swag.assert(width >= 0 and height >= 0)
        if .popup do
            .hidePopup()
        let pos          = .surfaceRect()
        let topView      = .topView()
        let metrics      = .themeMetrics()
        let anchorHeight = metrics.frameWnd_AnchorHeight
        let sdw          = metrics.frameWnd_SmallShadowSize

        let ptTop        = topView.surfaceToLocal(Math.Point{pos.x, pos.y})
        let ptBottom     = topView.surfaceToLocal(Math.Point{pos.x, pos.bottom()})
        let anchorCenter = topView.surfaceToLocal(Math.Point{pos.horzCenter(), pos.y}).x

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

        with let frame = Wnd.create'FrameWnd(topView, Math.Rectangle{x, y, width, height})
        {
            .owner = me
            .setFrameForm(.Round)
            .setFrameFlags(.SmallShadow)
            .style.addStyleSheetColors("frameWnd_Border $frameWnd_PopupBorder")
            .anchor         = anchor
            .anchorPosition = anchorCenter - .position.x
        }

        .popup = frame
        return frame
    }
}
