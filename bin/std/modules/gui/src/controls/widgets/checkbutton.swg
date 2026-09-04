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

        sigChanged: SigArray'func||(*CheckButton)     // Emitted after a user action changes the state.
    }
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

        var subRectBk:     #null *ThemeImageRect
        var subRectBorder: #null *ThemeImageRect
        var subRectMark:   #null *ThemeImageRect
        var colorBk:       Color
        var colorBorder:   Color
        var colorMark:     Color
        var colorText:     Color

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

        case .state == .Checked or .state == .Indeterminate:
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

        switch .state
        {
        case .Unchecked:
            subRectBk     = &rects.btnCheck_Normal
            subRectBorder = &rects.btnCheck_NormalBorder

        case .Checked:
            subRectBk     = &rects.btnCheck_Checked
            subRectBorder = &rects.btnCheck_CheckedBorder
            subRectMark   = &rects.btnCheck_CheckedMark

        case .Indeterminate:
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
        theme.drawSubRect(painter, posBox, subRectBk, colorBk)
        theme.drawSubRect(painter, posBox, subRectBorder, colorBorder)
        theme.drawSubRect(painter, posBox, subRectMark, colorMark)

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
        if !.flags.has(.RightAligned) do
            labelPos.x += posBox.width + metrics.btnCheck_Padding
        labelPos.width -= posBox.width + metrics.btnCheck_Padding
        Theme.drawIconText(painter, labelPos, .icon, &.name, format, metrics.iconText_Margin)

        // The box and the wording are one target, and the ring is drawn around that rather than
        // around the cell the layout gave the control. See [[Gui.Button.markerFocusRect]].
        if !bc.isDisabled and .showsFocusRing() do
            theme.drawFocusRing(painter, .markerFocusRect(posBox))
    }

    // Reports the room the check box, its padding, and the caption need.
    //
    // The caption keeps the same trailing margin it has leading room, so a box followed
    // by a long label does not end flush against the edge of the control.
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        discard available

        let metrics = .themeMetrics()
        let width   = metrics.btnCheck_Size + metrics.btnCheck_Padding + .captionWidth() + metrics.btnPush_TextMargin
        return {Math.max(width, metrics.btnPush_Width), metrics.btnPush_Height}
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
    func create(parent: *Wnd, name: string, position: Math.Rectangle = {}, id: #null WndId = null, flags = CheckButtonFlags.None)->*CheckButton
    {
        Debug.assert(parent != null)
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

        .invalidate()
        .sigChanged.call(me)
        .postCommandEvent(.id)
    }

    // Changes the displayed state without emitting a change signal or command.
    mtd setState(newState: CheckState)
    {
        if .state == newState do
            return
        .state = newState
        .invalidate()
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
