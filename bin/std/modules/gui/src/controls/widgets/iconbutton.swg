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
    Frame      // Draws a softly rounded outline and a light fill around the complete button.
    Bottom     // Draws an indicator along the bottom edge.
    Top        // Draws an indicator along the top edge.
    Left       // Draws an indicator along the left edge.
    Right      // Draws an indicator along the right edge.
    Full       // Fills the complete button background.
}

// Displays an icon action with optional label, checked state, arrow, and owned popup.
struct IconButton
{
    public
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
    }

    // The popup this button owns while it is open, and the background animation.
    aniBk: BlendColor     // Color animation of the background.
    popup: #null *Wnd     // Popup currently shown by this button.
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
    // Reports the room the icon, the label, the arrow, and the indicator rail need.
    //
    // The label sits beside the icon or under it, so the axis it grows along follows
    // [[Gui.IconButton.textPosition]]: a toolbar showing captions widens with a longer
    // translation rather than crowding it. A button hiding its label
    // ([[Gui.IconButtonFlags.IconOnly]]) answers for its icon alone.
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        discard available

        let metrics = .themeMetrics()

        var iconWidth  = .iconWidth != 0 ? .iconWidth : .icon.sizeX
        var iconHeight = .iconHeight != 0 ? .iconHeight : .icon.sizeY
        if !.icon.isValid()
        {
            iconWidth  = 0
            iconHeight = 0
        }

        var width  = iconWidth
        var height = iconHeight

        let showsLabel = !.name.isEmpty() and !.flags.has(.IconOnly)
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
        let arrowSize = metrics.chevron_Size
        switch #complete .arrowPosition
        {
        case .None:
            break

        case .Left, .Right, .RightUpward, .RightDownward:
            width  += arrowSize + metrics.btnIcon_MarginArrow + metrics.btnIcon_SpacingArrowH
            height = Math.max(height, arrowSize)

        case .Top, .Bottom:
            width  = Math.max(width, arrowSize)
            height += arrowSize + metrics.btnIcon_MarginArrow + metrics.btnIcon_SpacingArrowV
        }

        // The checked-state rail runs in a lane of its own, so it never eats into the group.
        // A full indicator is a background fill and asks for nothing, and the two indicator-less
        // placements draw nothing at all.
        switch #complete .checkIndicator
        {
        case .None, .Ink, .Frame, .Full: break
        case .Left, .Right:              width += metrics.activeRail_Size + metrics.activeRail_Margin
        case .Bottom, .Top:              height += metrics.activeRail_Size + metrics.activeRail_Margin
        }

        let padding = 2 * metrics.btnIcon_Padding
        return {width + padding, height + padding}
    }

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

        // The form is the shape, so the focus ring follows it and a circular tool is never
        // marked with a box. It is published even for a flat button, which paints no box: the
        // ring is the only edge such a button has, and it stands for the form all the same.
        //
        // The checked frame answers to the form for the same reason. It is drawn over the fill the
        // hovered state leaves under it, so a corner the two do not share is a corner where the
        // mark cuts across its own button: a square tool marked with a rounded hairline reads as
        // two controls stacked rather than as one that is picked.
        let framedRadius = Math.max(subRectBk!.radius - 0.5, 0)
        .focusRingRadius = subRectBk!.radius

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

        // A framed selection has a neutral ground in every palette, so its glyph remains the
        // accent mark. The generic checked ink is the inverse ink used by a filled selection in
        // neutral themes; reusing it here made checked tools white on the light theme.
        if .isChecked and .checkIndicator == .Frame and !bc.isDisabled
        {
            if .isPressed do
                colorIcon = colors.btnIcon_CheckedPressedMark
            elif .isHot do
                colorIcon = colors.btnIcon_CheckedHotMark
            else do
                colorIcon = colors.btnIcon_CheckedMark
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

        // The focus ring is drawn over the last fill this method leaves under it, and every branch
        // below can change that. It points in the accent, and a picked tool is filled with the
        // accent, so it has to be told; a flat or overlay button paints no box at all, and
        // publishing one would send the ring after a fill that is not there.
        .focusRingGround = {}

        if !flat and !overlay
        {
            .aniBk.apply(me, colorBk)
            theme.drawSubRect(bc.painter, clientRect, subRectBk, .aniBk.cur())
            .focusRingGround = .aniBk.cur()
        }

        // A checked button says so with a mark of its own, unless it was told to draw none:
        // `None` then reads as pressed and `Ink` keeps the checked ink, and both leave the box
        // exactly as the state colors above left it.
        let marked = !flat and !overlay and .isChecked and .checkIndicator != .None and .checkIndicator != .Ink
        if marked and .checkIndicator == .Frame
        {
            var frame = clientRect
            frame.inflate(-0.5)
            bc.painter.drawRoundRect(frame, framedRadius, framedRadius, colorChecked, 1)
        }
        elif marked and colors.activeRail.a
        {
            // The rule stops short of both ends of the edge it runs along, so it reads as a
            // mark placed against the cell rather than as a bar filling one of its sides.
            let thickness = Math.min(metrics.activeRail_Size, Math.min(clientRect.width, clientRect.height))
            var rail      = clientRect
            switch .checkIndicator
            {
            case .Top:
                rail.height = thickness
                rail.inflate(-.railInset(rail.width), 0)

            case .Left:
                rail.width = thickness
                rail.inflate(0, -.railInset(rail.height))

            case .Right:
                rail.x     = rail.right() - thickness
                rail.width = thickness
                rail.inflate(0, -.railInset(rail.height))

            default:
                rail.y      = rail.bottom() - thickness
                rail.height = thickness
                rail.inflate(-.railInset(rail.width), 0)
            }

            // A tool that cannot be picked keeps its mark, at the weight of everything else
            // it cannot do. Drawn at full accent, the rule says the tool is available.
            bc.painter.fillRect(rail, bc.isDisabled ? colors.btnIcon_CheckedDisabledMark : colors.activeRail)
        }
        elif marked
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

            // The checked mark covers the background it was drawn over, so it becomes the ground
            // the ring has to read on — and when it fills the cell it is also the shape the ring
            // has to follow. An indicator on one edge leaves the box in charge of both.
            if .checkIndicator == .Full
            {
                .focusRingRadius = subRectBk!.radius
                .focusRingGround = colorChecked
            }
        }

        var pos     = .paddedClientRect()
        let hasIcon = icon.isValid() or .iconPainter

        // A rule running down one side belongs to the cell, so the content steps aside for
        // it whether the button is checked or not: reserved only while checked, the glyph
        // would jump sideways as the tool is picked, and pressed against it the rule would
        // read as an outline of the glyph rather than as a mark beside it.
        if colors.activeRail.a
        {
            let railRoom = metrics.activeRail_Size + metrics.activeRail_Margin
            switch .checkIndicator
            {
            case .Left:  pos.moveLeft(railRoom)
            case .Right: pos.moveRight(-railRoom)
            }
        }

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
            case .Left, .Right, .RightUpward, .RightDownward: nw += metrics.chevron_Size + metrics.btnIcon_SpacingArrowH
            case .Top, .Bottom: nh += metrics.chevron_Size + metrics.btnIcon_SpacingArrowV
            case .None:         break
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

        // Arrow. It is a chevron of the theme icon set — the same glyph a combo box, a submenu and
        // a tree row use — so the button says "there is more this way" in the one shape the rest of
        // the interface says it in. Its box is square, and the ink inside it is centered, so one
        // size answers for every direction.
        if .arrowPosition != .None
        {
            let side  = metrics.chevron_Size
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
        if !.name.isEmpty() and !.flags.has(.IconOnly)
        {
            var sf: RichStringFormat
            theme.setTextColors(&sf, colorText)
            sf.font          = .font()
            sf.horzAlignment = .Center
            sf.vertAlignment = .Center
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

                // The label stands beside the glyph, not against the far edge of the cell:
                // pushed to the other end of a wide row it reads as a second column rather
                // than as the name of the glyph it belongs to.
                sf.horzAlignment = .Left
                if !hasIcon and (.arrowPosition == .Top or .arrowPosition == .Bottom) do
                    sf.horzAlignment = .Center

                // A painter that declares no size keeps taking what the label leaves it.
                if !icon.isValid() and !.iconWidth
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
                let rad = subRectBk!.radius
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

        .sigPressed.call(cast(*Button) me)
        .activateFromUser()
        evt.accepted = true
    }
}

private impl IconButton
{
    // Air the active rule leaves at each end of the edge it runs along.
    //
    // The margin is a ceiling, not a promise: a cell too short to spare it keeps a rule
    // covering a third of the edge rather than none at all.
    mtd railInset(length: f32)->f32
    {
        return Math.min(.themeMetrics().activeRail_Margin, length / 3)
    }

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
        res.focusPolicy = .Tab
        res.wndFlags    |= .ActivatesOnKey
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
