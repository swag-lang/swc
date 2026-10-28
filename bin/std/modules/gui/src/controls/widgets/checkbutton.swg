#global public

using Core, Pixel

// Selects the unchecked, checked, or indeterminate state displayed by a check button.
enum CheckState
{
    Unchecked         // The option is not selected.
    Checked           // The option is selected.
    Indeterminate     // The represented values have mixed states.
}

// Configures check button interaction and marker placement.
#[Swag.EnumFlags]
enum CheckButtonFlags
{
    None = 0         // Uses a two-state button with a left-aligned marker.
    TriState         // Includes the indeterminate state in the user toggle cycle.
    RightAligned     // Places the marker at the right edge.
}

// Lets the user enable an option or choose among three check states.
struct CheckButton
{
    public
    {
        using button: Button     // Embedded button behavior and presentation.

        readonly
        {
            state = CheckState.Unchecked      // Current displayed state.
            flags = CheckButtonFlags.None     // Active interaction and placement options.
        }

        sigChanged: SigArray'func||(*Wnd)     // Emitted after a user action changes the state.
    }

    // The chosen look is laid over the resting one at `markPresence`, which eases when the state
    // changes, so a box fills and empties instead of snapping. `markState` is the chosen state
    // being shown, which an emptying box still needs once its state is back to unchecked.
    markPresence: f32
    markState     = CheckState.Checked
}

impl IWnd for CheckButton
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let bc      = evt.paintContext
        let painter = bc.painter
        let theme   = .theme()
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let rects   = .themeRects()

        var restBk, restBorder:     Color
        var chosenBk, chosenBorder: Color
        var colorMark, colorText:   Color

        // The answer a box holds survives the pointer: a checked box stays an Arc box under it and
        // only deepens, and an unchecked one only strengthens its ring.
        let checked = .state != .Unchecked
        if bc.isDisabled
        {
            restBk       = colors.btnCheck_DisabledBk
            restBorder   = colors.btnCheck_DisabledBorder
            chosenBk     = colors.btnCheck_CheckedDisabledBk
            chosenBorder = colors.btnCheck_CheckedDisabledBk
            colorMark    = colors.btnCheck_DisabledMark
            colorText    = colors.btnCheck_DisabledText
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
            chosenBk     = engaged ? colors.btnCheck_CheckedHotBk : colors.btnCheck_CheckedBk
            chosenBorder = engaged ? colors.btnCheck_CheckedHotBk : colors.btnCheck_CheckedBorder
            colorMark    = colors.btnCheck_CheckedMark
            if checked do
                colorText = colors.btnCheck_CheckedText
        }

        // A disabled box shows its state as it is; an enabled one at the share its mark has reached.
        let presence = bc.isDisabled ? (checked ? 1'f32 : 0) : .markPresence
        let shown    = checked ? .state : .markState
        var subRectBk:     *ThemeImageRect = &rects.btnCheck_Checked
        var subRectBorder: *ThemeImageRect = &rects.btnCheck_CheckedBorder
        var subRectMark:   *ThemeImageRect = &rects.btnCheck_CheckedMark
        if shown == .Indeterminate
        {
            subRectBk     = &rects.btnCheck_Undefined
            subRectBorder = &rects.btnCheck_UndefinedBorder
            subRectMark   = &rects.btnCheck_UndefinedMark
        }

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
            theme.drawSubRect(painter, posBox, &rects.btnCheck_Normal, fadeColor(restBk, 1 - presence))
            theme.drawSubRect(painter, posBox, &rects.btnCheck_NormalBorder, fadeColor(restBorder, 1 - presence))
        }

        // The mark grows into its box as the box fills.
        if presence > 0
        {
            var posMark = posBox
            posMark.inflate(-posBox.width * 0.2 * (1 - presence))
            theme.drawSubRect(painter, posBox, subRectBk, fadeColor(chosenBk, presence))
            theme.drawSubRect(painter, posBox, subRectBorder, fadeColor(chosenBorder, presence))
            theme.drawSubRect(painter, posMark, subRectMark, fadeColor(colorMark, presence))
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
        Theme.drawIconText(painter, labelPos, .icon, &.name, format, metrics.iconText_Margin)

        // The box and the wording are one target, and the ring is drawn around that rather than
        // around the cell the layout gave the control. See [[Gui.Button.markerFocusRect]].
        if not bc.isDisabled and .showsFocusRing() do
            theme.drawFocusRing(painter, .markerFocusRect(posBox))
    }

    // Reports the room the check box, its padding, and the caption need.
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
            .toggle()
    }

    // Space or Enter toggles the focused check button.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed do
            return

        switch evt.key
        {
        case .Space, .Return:
            .toggle()
            evt.accepted = true
        }
    }
}

impl CheckButton
{
    // Creates a check button with an optional command identifier and initial options.
    #[Swag.Discardable]
    func create(parent: *Wnd, name: string, position: Math.Rectangle = {}, id: WndId? = null, flags = CheckButtonFlags.None)->*CheckButton
    {
        Swag.assert(parent != null)
        var pos = position
        if pos.height == 0 do
            pos.height = parent.themeMetrics().btnPush_Height
        if pos.width == 0 do
            pos.width = parent.themeMetrics().btnPush_Width
        let result = Wnd.create'CheckButton(parent, name, pos, id)
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

    // Advances to the next state and emits the same notifications as a user action.
    mtd toggle()
    {
        switch .state
        {
        case .Unchecked:     .state = .Checked
        case .Checked:       .state = .flags.has(.TriState) ? .Indeterminate : .Unchecked
        case .Indeterminate: .state = .Unchecked
        }

        .easeMark()
        .sigChanged.call(me)
        .postCommandEvent(.id)
    }

    // Changes the displayed state without emitting a change signal or command.
    mtd setState(newState: CheckState)
    {
        if .state == newState do
            return
        .state = newState
        .easeMark()
    }

    // Adds and removes interaction and placement options, then repaints the button.
    mtd updateFlags(add: CheckButtonFlags = .None, remove = CheckButtonFlags.None)
    {
        .flags.add(add)
        .flags.remove(remove)
        .invalidate()
    }

    // Reports whether the option is selected.
    mtd const isChecked()->bool => .state == .Checked

    // Reports whether the represented values have mixed states.
    mtd const isIndeterminate()->bool => .state == .Indeterminate
}

private impl CheckButton
{
    // Eases the chosen look toward the current state; a control nobody can see takes it at once.
    mtd easeMark()
    {
        if .state != .Unchecked do
            .markState = .state
        .invalidate()

        let destination = .state != .Unchecked ? 1'f32 : 0
        if not .surface or not .isVisible() or .app().isReducedMotion()
        {
            if .surface do
                .app().animator.cancel(me, AnimationChannel.from("Gui.Check.Mark"))
            .markPresence = destination
            return
        }

        var options: AnimationOptions
        options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_QuickSeconds)
        options.easing   = .EaseOut
        discard .app().animator.animateF32(me, AnimationChannel.from("Gui.Check.Mark"), .markPresence, destination, func(button, value) { button.markPresence = value }, options)
    }
}
