#global public

using Core, Pixel

// Lets the user select one option from an optional group.
struct RadioButton
{
    public
    {
        using button: Button     // Embedded button behavior and presentation.

        groupId: WndId?     // Identifier shared by mutually exclusive siblings; null leaves the button ungrouped.

        readonly
        {
            flags = RadioButtonFlags.None     // Active marker placement options.
            checked: bool     // Whether this option is selected.
        }

        sigChanged: SigArray'func||(*Wnd)     // Emitted after a user action selects the button.
    }

    // The chosen look is laid over the resting one at `markPresence`, which eases when the button
    // is chosen or left, so the dot grows in one option as it fades from the other.
    markPresence: f32
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

        var restBk, restBorder:     Color
        var chosenBk, chosenBorder: Color
        var colorMark, colorText:   Color

        // A chosen button is an Arc ring around an Arc dot, and stays one under the pointer; an
        // unchosen one only strengthens its ring.
        if bc.isDisabled
        {
            restBk, chosenBk = colors.btnCheck_DisabledBk
            restBorder       = colors.btnCheck_DisabledBorder
            chosenBorder     = colors.btnCheck_DisabledBorder
            colorMark        = colors.btnCheck_CheckedDisabledBk
            colorText        = colors.btnCheck_DisabledText
        }
        else
        {
            switch
            {
            case .isPressed:
                restBk     = colors.btnCheck_PressedBk
                restBorder = colors.btnCheck_PressedBorder
                colorText  = colors.btnCheck_PressedText

            case .isHot:
                restBk     = colors.btnCheck_HotBk
                restBorder = colors.btnCheck_HotBorder
                colorText  = colors.btnCheck_HotText

            default:
                restBk     = colors.btnCheck_Bk
                restBorder = colors.btnCheck_Border
                colorText  = colors.btnCheck_Text
            }

            let engaged = .isHot or .isPressed
            chosenBk     = colors.btnCheck_Bk
            chosenBorder = engaged ? colors.btnRadio_CheckedHotMark : colors.btnRadio_CheckedBorder
            colorMark    = engaged ? colors.btnRadio_CheckedHotMark : colors.btnRadio_CheckedMark
            if .checked do
                colorText = colors.btnCheck_CheckedText
        }

        // A disabled button shows its state as it is; an enabled one at the share its dot has reached.
        let presence = bc.isDisabled ? (.checked ? 1'f32 : 0) : .markPresence

        // Box
        let clientRect = .clientRect()
        var posBox     = clientRect
        posBox.height = metrics.btnCheck_Size

        // Level with the wording, not with the box: a mark centered on the cell reads as
        // sitting under the label it belongs to.
        posBox.y     = .name.isEmpty() ? clientRect.vertCenter() - posBox.height * 0.5 : opticalTop(.font(), clientRect.vertCenter(), posBox.height)
        posBox.width = posBox.height
        if .flags.has(.RightAligned) do
            posBox.x = clientRect.right() - posBox.width
        if presence < 1
        {
            theme.drawSubRect(bc.painter, posBox, &rects.btnRadio_Normal, fadeColor(restBk, 1 - presence))
            theme.drawSubRect(bc.painter, posBox, &rects.btnRadio_NormalBorder, fadeColor(restBorder, 1 - presence))
        }

        // The dot grows from the center of its ring.
        if presence > 0
        {
            var posMark = posBox
            posMark.inflate(-posBox.width * 0.3 * (1 - presence))
            theme.drawSubRect(bc.painter, posBox, &rects.btnRadio_Checked, fadeColor(chosenBk, presence))
            theme.drawSubRect(bc.painter, posBox, &rects.btnRadio_CheckedBorder, fadeColor(chosenBorder, presence))
            theme.drawSubRect(bc.painter, posMark, &rects.btnRadio_CheckedMark, fadeColor(colorMark, presence))
        }

        // Content
        var format: RichStringFormat
        theme.setTextColors(&format, colorText)
        if .flags.has(.RightAligned) do
            format.horzAlignment = .Right
        else do
            format.horzAlignment = .Left
        format.vertAlignment = .Center
        format.flags         = .Clip
        format.font          = .font()
        var labelPos = clientRect
        if not .flags.has(.RightAligned) do
            labelPos.x += posBox.width + metrics.btnCheck_Padding
        labelPos.width -= posBox.width + metrics.btnCheck_Padding
        Theme.drawIconText(bc.painter, labelPos, .icon, &.name, format, metrics.iconText_Margin)

        // The box and the wording are one target, and the ring is drawn around that rather than
        // around the cell the layout gave the control. See [[Gui.Button.markerFocusRect]].
        if not bc.isDisabled and .showsFocusRing() do
            theme.drawFocusRing(bc.painter, .markerFocusRect(posBox))
    }

    // Reports the room the radio box, its padding, and the caption need.
    //
    // The caption keeps the same trailing margin it has leading room, so a box followed
    // by a long label does not end flush against the edge of the control.
    mtd impl measureContent(_: Math.Point)->Math.Point
    {
        let metrics = .themeMetrics()
        let width   = metrics.btnCheck_Size + metrics.btnCheck_Padding + .captionWidth() + metrics.btnPush_TextMargin
        return Math.Point{Math.max(width, metrics.btnPush_Width), metrics.btnPush_Height}
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if .processMouseEvent(evt) do
            .selectFromUser()
    }

    // Space or Enter selects the focused radio button, and the arrows move inside its group.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed do
            return

        if evt.key == .Space or evt.key == .Return
        {
            .selectFromUser()
            evt.accepted = true
            return
        }

        // A group of options is one stop of the keyboard traversal, so Tab is what leaves it and
        // the arrows are what choose inside it. Selecting is what moving means here: an option
        // the keyboard passes over without taking is not a state a radio group can be in.
        switch evt.key
        {
        case .Up, .Left:    evt.accepted = .selectSibling(forward: false)
        case .Down, .Right: evt.accepted = .selectSibling(forward: true)
        }
    }
}

impl RadioButton
{
    // Creates a radio button with an optional command identifier and initial options.
    #[Swag.Discardable]
    func create(parent: *Wnd, name: string, position: Math.Rectangle = {}, id: WndId? = null, flags = RadioButtonFlags.None)->*RadioButton
    {
        Swag.assert(parent != null)
        var pos = position
        if pos.height == 0 do
            pos.height = parent.themeMetrics().btnPush_Height
        if pos.width == 0 do
            pos.width = parent.themeMetrics().btnPush_Width
        let result = Wnd.create'RadioButton(parent, name, pos, id)
        result.flags       = flags
        result.focusPolicy = .Tab
        result.wndFlags    |= .ActivatesOnKey

        // The ring is drawn by the paint, around the box and its wording rather than around the
        // cell, so the generic one is turned off.
        result.wndFlags |= .NoFocusRing

        // An unstated width belongs to the caption; the theme width above stays its floor.
        if position.width == 0 do
            result.preferredSize.x = 0
        return result
    }

    // Changes the selected state without emitting a change signal or command.
    //
    // Selecting a grouped button clears its selected siblings.
    mtd setChecked(checked: bool)
    {
        if .checked == checked do
            return
        .checked = checked
        if checked do
            .uncheckGroupSiblings()
        .easeMark()
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

    // Selects the next or previous option of this button's group and reports whether one was found.
    //
    // The order is the order the options were created in and it wraps, so the arrows stay inside
    // the group however long they are held: a group that let the last option pass the key on
    // would hand the keyboard to whatever stands beside it, which is what Tab is for. An ungrouped
    // button has nothing to move to. The selected option takes the keyboard with it, so the ring
    // keeps standing on the option that is checked.
    mtd selectSibling(forward: bool)->bool
    {
        if (.groupId).count == 0 or not .parent do
            return false

        var group: Array'(*RadioButton)
        var current = 0's64
        for child in .parent.children
        {
            if child is RadioButton as other where other.groupId == .groupId
            {
                if child == cast(*Wnd, me) do
                    current = cast(s64, group.count)
                group.add(other)
            }
        }

        let count = cast(s64, group.count)
        if count < 2 do
            return false

        let step = forward ? 1's64 : count - 1
        let next = group[cast(u64, ((current + step) % count))]
        next.selectFromUser()
        next.setFocus()
        return true
    }

    // Clears selected sibling radios from the same non-null group.
    mtd uncheckGroupSiblings()
    {
        if (.groupId).count == 0 or not .parent do
            return

        for c in .parent.children
        {
            if c == cast(*Wnd, me) do
                continue
            if c is RadioButton as other where other.groupId == .groupId do
                other.setChecked(false)
        }
    }
}

private impl RadioButton
{
    // Eases the chosen look toward the current state; a control nobody can see takes it at once.
    mtd easeMark()
    {
        .invalidate()

        let destination = .checked ? 1'f32 : 0
        if not .surface or not .isVisible() or .app().isReducedMotion()
        {
            if .surface do
                .app().animator.cancel(me, AnimationChannel.from("Gui.Radio.Mark"))
            .markPresence = destination
            return
        }

        var options: AnimationOptions
        options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_QuickSeconds)
        options.easing   = .EaseOut
        discard .app().animator.animateF32(me, AnimationChannel.from("Gui.Radio.Mark"), .markPresence, destination, func(button, value) { button.markPresence = value }, options)
    }
}
