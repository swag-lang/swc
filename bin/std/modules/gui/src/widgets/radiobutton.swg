#global public

using Core, Pixel

// Lets the user select one option from an optional group.
struct RadioButton
{
    using button: Button     // Embedded button behavior and presentation.

    groupId: #null WndId     // Identifier shared by mutually exclusive siblings; null leaves the button ungrouped.

    readonly
    {
        flags = RadioButtonFlags.None     // Active marker placement options.
        checked: bool                    // Whether this option is selected.
    }

    sigChanged: SigArray'func||(*RadioButton)     // Emitted after a user action selects the button.
}

// Configures radio button marker placement.
#[Swag.EnumFlags]
enum RadioButtonFlags
{
    None = 0         // Places the marker at the left edge.
    RightAligned     // Places the marker at the right edge.
}

impl IWnd for RadioButton
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let bc      = evt.paintContext
        let theme   = .theme()
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let rects   = .themeRects()

        var subRectBk:     #null *ThemeImageRect
        var subRectBorder: #null *ThemeImageRect
        var subRectMark:   #null *ThemeImageRect
        var colorBk:       Color = undefined
        var colorBorder:   Color = undefined
        var colorMark:     Color = undefined
        var colorText:     Color = undefined

        switch
        {
        case bc.isDisabled:
            colorBk     = colors.btnCheck_DisabledBk
            colorBorder = colors.btnCheck_DisabledBorder
            colorMark   = colors.btnCheck_DisabledMark
            colorText   = colors.btnCheck_DisabledText

        case .isPressed:
            colorBk     = colors.btnCheck_PressedBk
            colorBorder = colors.btnCheck_PressedBorder
            colorMark   = colors.btnCheck_PressedMark
            colorText   = colors.btnCheck_PressedText

        case .isHot:
            colorBk     = colors.btnCheck_HotBk
            colorBorder = colors.btnCheck_HotBorder
            colorMark   = colors.btnCheck_HotMark
            colorText   = colors.btnCheck_HotText

        case .checked:
            colorBk     = colors.btnCheck_CheckedBk
            colorText   = colors.btnCheck_CheckedText
            colorBorder = colors.btnCheck_CheckedBorder
            colorMark   = colors.btnCheck_CheckedMark

        default:
            colorBk     = colors.btnCheck_Bk
            colorBorder = colors.btnCheck_Border
            colorMark   = colors.btnCheck_Mark
            colorText   = colors.btnCheck_Text
        }

        if .checked
        {
            subRectBk     = &rects.btnRadio_Checked
            subRectBorder = &rects.btnRadio_CheckedBorder
            subRectMark   = &rects.btnRadio_CheckedMark
        }
        else
        {
            subRectBk     = &rects.btnRadio_Normal
            subRectBorder = &rects.btnRadio_NormalBorder
        }

        // Box
        let clientRect = .clientRect()
        var posBox     = clientRect
        posBox.height = metrics.btnCheck_Size
        posBox.y      = clientRect.vertCenter() - (posBox.height * 0.5)
        posBox.width  = posBox.height
        if .flags.has(.RightAligned) do
            posBox.x = clientRect.right() - posBox.width
        theme.drawSubRect(bc.painter, posBox, subRectBk, colorBk)
        theme.drawSubRect(bc.painter, posBox, subRectBorder, colorBorder)
        theme.drawSubRect(bc.painter, posBox, subRectMark, colorMark)

        // Content
        var format: RichStringFormat
        theme.setTextColors(&format, colorText)
        if .flags.has(.RightAligned) do
            format.horzAlignment = .Right
        else do
            format.horzAlignment = .Left
        format.vertAlignment     = .Center
        format.flags             = .Clip
        format.font              = .font()
        var labelPos = clientRect
        if !.flags.has(.RightAligned) do
            labelPos.x += posBox.width + metrics.btnCheck_Padding
        labelPos.width -= posBox.width + metrics.btnCheck_Padding
        Theme.drawIconText(bc.painter, labelPos, .icon, &.name, format, metrics.iconText_Margin)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if .processMouseEvent(evt) do
            .selectFromUser()
    }

    // Space or Enter selects the focused radio button.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed do
            return

        if evt.key == .Space or evt.key == .Return
        {
            .selectFromUser()
            evt.accepted = true
        }
    }
}

impl RadioButton
{
    // Creates a radio button with an optional command identifier and initial options.
    #[Swag.Discardable]
    func create(parent: *Wnd, name: string, position: Math.Rectangle = {}, id: #null WndId = null, flags = RadioButtonFlags.None)->*RadioButton
    {
        Debug.assert(parent != null)
        var pos = position
        if pos.height == 0 do
            pos.height = parent.themeMetrics().btnPush_Height
        if pos.width == 0 do
            pos.width = parent.themeMetrics().btnPush_Width
        let result   = Wnd.create'RadioButton(parent, name, pos, id)
        result.flags = flags
        return result
    }

    // Changes the selected state without emitting a change signal or command.
    // Selecting a grouped button clears its selected siblings.
    mtd setChecked(checked: bool)
    {
        if .checked == checked do
            return
        .checked = checked
        if checked do
            .uncheckGroupSiblings()
        .invalidate()
    }

    // Reports whether this option is selected.
    mtd const isChecked()->bool => .checked

    // Adds and removes marker placement options, then repaints the button.
    mtd updateFlags(add: RadioButtonFlags = .None, remove = RadioButtonFlags.None)
    {
        .flags.add(add)
        .flags.remove(remove)
        .invalidate()
    }

    internal mtd selectFromUser()
    {
        if .checked do
            return
        .setChecked(true)
        .sigChanged.call(me)
        .postCommandEvent(.id)
    }

    // Clears selected sibling radios from the same non-null group.
    mtd uncheckGroupSiblings()
    {
        if @countof(.groupId) == 0 or !.parent do
            return

        for c in .parent.children
        {
            if c == cast(*Wnd) me or c.type != RadioButton do
                continue
            let other = cast(*RadioButton) c
            if other.groupId == .groupId do
                other.setChecked(false)
        }
    }
}
