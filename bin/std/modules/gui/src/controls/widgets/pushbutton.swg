#global public

using Core, Pixel

// Selects push button visual emphasis.
//
// The charter has four buttons: the primary action, filled with what acts; the secondary one,
// transparent in a hairline ring; the quiet one, its words alone; and the destructive one, a
// secondary button whose words say what is lost. A surface shows one primary action at most.
enum PushButtonForm
{
    Normal          // The secondary button: transparent, a hairline ring, the body ink.
    Default         // The primary action because the keyboard says so: the dialog's default answer.
    Flat            // The quiet button: its words alone, raised under the pointer.
    Strong          // The primary action because the surface says so, with a bold label.
    Destructive     // A secondary button whose label, in the critical tone, says what is lost.

    // A mode the reader has turned on. Arc chooses, so it wears the selection ground, writes in
    // Arc and keeps a faint Arc ring — the same mark as a checked tool. It is a state, not an
    // action: a surface shows its one primary action beside it.
    Alternate
}

// Invokes an action from pointer or keyboard input.
struct PushButton
{
    public
    {
        using button: Button     // Embedded button behavior and presentation.

        readonly form = PushButtonForm.Normal     // Current visual emphasis.
    }

    // Color animations of the painted parts, driven by the hover and press state.
    aniBk:     BlendColor     // Color animation of the background.
    aniBorder: BlendColor     // Color animation of the border.
    aniText:   BlendColor     // Color animation of the label.
}

impl IWnd for PushButton
{
    mtd impl onStateEvent(evt: *StateEvent)
    {
        .button.IWnd.onStateEvent(evt)
        if evt.kind == .Hide or evt.kind == .Disable
        {
            .aniBk.reset()
            .aniBorder.reset()
            .aniText.reset()
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let bc      = evt.paintContext
        let theme   = .theme()
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let rects   = .themeRects()

        var subRectBk:     *ThemeImageRect?
        var subRectBorder: *ThemeImageRect?
        var colorBk:       Color
        var colorBorder:   Color
        var colorText:     Color

        // The emphasis is decided here rather than stored, because it follows the keyboard.
        let form = .paintedForm()
        if form == .Default
        {
            switch
            {
            case bc.isDisabled:
                colorBk       = colors.btnPushDefault_DisabledBk
                colorBorder   = colors.btnPushDefault_DisabledBorder
                colorText     = colors.btnPushDefault_DisabledText
                subRectBk     = &rects.btnPush_Disabled
                subRectBorder = &rects.btnPush_DisabledBorder

            case .isPressed:
                colorBk       = colors.btnPushDefault_PressedBk
                colorBorder   = colors.btnPushDefault_PressedBorder
                colorText     = colors.btnPushDefault_PressedText
                subRectBk     = &rects.btnPush_Pressed
                subRectBorder = &rects.btnPush_PressedBorder

            case .isHot:
                colorBk       = colors.btnPushDefault_HotBk
                colorBorder   = colors.btnPushDefault_HotBorder
                colorText     = colors.btnPushDefault_HotText
                subRectBk     = &rects.btnPush_Hot
                subRectBorder = &rects.btnPush_HotBorder

            default:
                colorBk       = colors.btnPushDefault_Bk
                colorBorder   = colors.btnPushDefault_Border
                colorText     = colors.btnPushDefault_Text
                subRectBk     = &rects.btnPush_Normal
                subRectBorder = &rects.btnPush_NormalBorder
            }
        }
        elif form == .Flat
        {
            switch
            {
            case bc.isDisabled:
                colorBk       = colors.btnPushFlat_DisabledBk
                colorBorder   = colors.btnPushFlat_DisabledBorder
                colorText     = colors.btnPushFlat_DisabledText
                subRectBk     = &rects.btnPush_Disabled
                subRectBorder = &rects.btnPush_DisabledBorder

            case .isPressed:
                colorBk       = colors.btnPushFlat_PressedBk
                colorBorder   = colors.btnPushFlat_PressedBorder
                colorText     = colors.btnPushFlat_PressedText
                subRectBk     = &rects.btnPush_Pressed
                subRectBorder = &rects.btnPush_PressedBorder

            case .isHot:
                colorBk       = colors.btnPushFlat_HotBk
                colorBorder   = colors.btnPushFlat_HotBorder
                colorText     = colors.btnPushFlat_HotText
                subRectBk     = &rects.btnPush_Hot
                subRectBorder = &rects.btnPush_HotBorder

            default:
                colorBk       = colors.btnPushFlat_Bk
                colorBorder   = colors.btnPushFlat_Border
                colorText     = colors.btnPushFlat_Text
                subRectBk     = &rects.btnPush_Normal
                subRectBorder = &rects.btnPush_NormalBorder
            }
        }
        else
        {
            // The plain button and the two filled ones draw the same shape from three sets of
            // colors, and the set never changes while the button is painted. Choosing it once
            // keeps the states below reading as states rather than as a form test repeated in
            // each of them — which is what a second filled form would otherwise have doubled.
            //
            // A filled action keeps its own color through every state. Handed the neutral hover
            // of a plain button, it dropped the tone that made it the action of the surface
            // exactly as the reader reached it.
            var rest, hot, pressed: {bk, border, text: Color}
            switch form
            {
            case .Strong: rest = {bk: colors.btnPush_StrongBk, border: colors.btnPush_StrongBorder, text: colors.btnPush_StrongText}
                hot     = {bk: colors.btnPush_StrongHotBk, border: colors.btnPush_StrongHotBorder, text: colors.btnPush_StrongHotText}
                pressed = {bk: colors.btnPush_StrongPressedBk, border: colors.btnPush_StrongPressedBorder, text: colors.btnPush_StrongPressedText}

            case .Alternate: rest = {bk: colors.btnPush_AlternateBk, border: colors.btnPush_AlternateBorder, text: colors.btnPush_AlternateText}
                hot     = {bk: colors.btnPush_AlternateHotBk, border: colors.btnPush_AlternateHotBorder, text: colors.btnPush_AlternateHotText}
                pressed = {bk: colors.btnPush_AlternatePressedBk, border: colors.btnPush_AlternatePressedBorder, text: colors.btnPush_AlternatePressedText}

            case .Destructive: rest = {bk: colors.btnPush_Bk, border: colors.btnPush_Border, text: colors.btnPush_DestructiveText}
                hot     = {bk: colors.btnPush_HotBk, border: colors.btnPush_HotBorder, text: colors.btnPush_DestructiveHotText}
                pressed = {bk: colors.btnPush_PressedBk, border: colors.btnPush_PressedBorder, text: colors.btnPush_DestructiveHotText}

            default: rest = {bk: colors.btnPush_Bk, border: colors.btnPush_Border, text: colors.btnPush_Text}
                hot     = {bk: colors.btnPush_HotBk, border: colors.btnPush_HotBorder, text: colors.btnPush_HotText}
                pressed = {bk: colors.btnPush_PressedBk, border: colors.btnPush_PressedBorder, text: colors.btnPush_PressedText}
            }

            switch
            {
            case bc.isDisabled:
                colorBk       = colors.btnPush_DisabledBk
                colorBorder   = colors.btnPush_DisabledBorder
                colorText     = colors.btnPush_DisabledText
                subRectBk     = &rects.btnPush_Disabled
                subRectBorder = &rects.btnPush_DisabledBorder

            case .isPressed:
                colorBk       = pressed.bk
                colorBorder   = pressed.border
                colorText     = pressed.text
                subRectBk     = &rects.btnPush_Pressed
                subRectBorder = &rects.btnPush_PressedBorder

            case .isHot:
                colorBk       = hot.bk
                colorBorder   = hot.border
                colorText     = hot.text
                subRectBk     = &rects.btnPush_Hot
                subRectBorder = &rects.btnPush_HotBorder

            default:
                colorBk       = rest.bk
                colorBorder   = rest.border
                colorText     = rest.text
                subRectBk     = &rects.btnPush_Normal
                subRectBorder = &rects.btnPush_NormalBorder
            }
        }

        // Background
        let clientRect = .clientRect()
        .aniBk.apply(me, colorBk)
        theme.drawSubRect(bc.painter, clientRect, subRectBk, .aniBk.cur())

        // The ring is drawn last, around a button whose shape was only just decided, and follows
        // the corner of the tile it was drawn from.
        .focusRingRadius = subRectBk!.radius

        // Border
        .aniBorder.apply(me, colorBorder)
        theme.drawSubRect(bc.painter, clientRect, subRectBorder, .aniBorder.cur())

        // Content
        var format: RichStringFormat
        .aniText.apply(me, colorText)
        theme.setTextColors(&format, .aniText.cur())
        format.horzAlignment = .Center
        format.vertAlignment = .Center
        format.flags         = .Clip
        format.font          = .font()

        // The bold weight is what makes a filled button the primary action of the surface,
        // whether the surface or the keyboard made it so: a dialog's default answer is its primary
        // action too. A button that cannot be pressed is the primary action of nothing, and kept
        // bold it read as a lighter grey than the plain button beside it, in the same disabled state.
        if (form == .Strong or form == .Default) and not bc.isDisabled do
            format.fontStyle = .Bold
        var labelPos = clientRect
        labelPos.inflate(-metrics.btnPush_Padding)
        Theme.drawIconText(bc.painter, labelPos, .icon, &.name, format, metrics.iconText_Margin)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if .processMouseEvent(evt) do
            .postCommandEvent(.id)
    }

    // Space or Enter activates the focused button.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed do
            return
        if evt.key != .Space and evt.key != .Return do
            return

        .sigPressed.call(cast(*Button, me))
        .postCommandEvent(.id)
        evt.accepted = true
    }

    // Reports the room the caption, the optional icon, and the button padding need.
    //
    // The theme push-button width stays a floor, so a short caption keeps the regular
    // button size of the surface and only a caption that would not fit widens it.
    mtd impl measureContent(_: Math.Point)->Math.Point
    {
        let metrics = .themeMetrics()
        return Math.Point{Math.max(.labelWidth(), metrics.btnPush_Width), metrics.btnPush_Height}
    }
}

impl PushButton
{
    // Replaces the displayed icon.
    mtd setIcon(icon: Icon) => .button.setIcon(icon)

    // Removes the displayed icon.
    mtd clearIcon() => .button.clearIcon()

    // Overrides the icon draw size; zero preserves an axis from the icon descriptor.
    mtd setIconSize(width, height: f32) => .button.setIconSize(width, height)

    // Creates a push button with optional command identifier and visual emphasis.
    //
    // A zero `position` height takes the theme height. A zero width starts at the theme width
    // and then follows the caption, keeping the theme width as a floor.
    #[Swag.Discardable]
    func create(parent: *Wnd, name: string, position: Math.Rectangle = {}, id: WndId? = null, form = PushButtonForm.Normal)->*PushButton
    {
        Swag.assert(parent != null)
        var pos = position
        if pos.height == 0 do
            pos.height = parent.themeMetrics().btnPush_Height
        if pos.width == 0 do
            pos.width = parent.themeMetrics().btnPush_Width
        let res = Wnd.create'PushButton(parent, name, pos, id)
        res.focusPolicy = .Tab
        res.wndFlags    |= .ActivatesOnKey
        res.form        = form

        // An unstated width belongs to the caption: the theme width above only gives the
        // button a sane size until the first layout pass measures it, and stays its floor.
        if position.width == 0 do
            res.preferredSize.x = 0
        if id != null do
            res.updateCommandState()
        return res
    }

    // Returns the emphasis the button is drawn with, which is not always the one it was given.
    //
    // A surface that names a dominant action draws it filled, and the reader takes that fill to
    // mean "this is what Enter runs". A focused button runs Enter itself, so once the keyboard
    // stands on another action the fill has to be there and not on the one the box was built
    // around — otherwise the box shows two answers to the same question, and the wrong one is
    // the loud one. It goes back to the named action as soon as the keyboard leaves the bar.
    //
    // Only the two plain emphases take part. A quiet button belongs to a tool bar, a strong one is
    // the primary action already, a destructive one must never become the answer Enter gives, and
    // a button that is on is a state; none of them stands for the answer to a box.
    mtd paintedForm()->PushButtonForm
    {
        if .form != .Normal and .form != .Default do
            return .form

        let srf = .surface
        if not srf or not srf.defaultButton do
            return .form

        var dominant = srf.defaultButton
        let focus    = srf.app.keyboardFocusWnd
        if focus and focus != dominant and focus.surface == srf
        {
            if focus is PushButton as other
            {
                if other.form == .Normal or other.form == .Default do
                    dominant = focus
            }
        }

        return dominant == cast(*Wnd, me) ? PushButtonForm.Default : PushButtonForm.Normal
    }

    // Changes visual emphasis and repaints the button.
    mtd setForm(form: PushButtonForm)
    {
        if .form == form do
            return
        .form = form
        .invalidate()
    }

    // Pins the button width to its label instead of leaving it to the layout pass.
    //
    // A button created without a width already follows its caption, so this is for a
    // button that must carry a settled width right away — one placed by hand, or one that
    // has to agree with a sibling before any container measures it. `minWidth` keeps a
    // floor under very short captions. Call it again after changing the name, the icon,
    // or the emphasis.
    mtd fitWidthToLabel(minWidth: f32 = 0)
    {
        .position.width  = Math.max(.labelWidth(), minWidth)
        .preferredSize.x = .position.width
        .invalidateLayout()
    }

    // Returns the width the caption, the optional icon, and the side margins need.
    //
    // The margin is [[Gui.ThemeMetrics.btnPush_TextMargin]], not the paint padding: a
    // button that follows its caption has to look like a button, and the few pixels the
    // painter insets by would leave the words against its border. An icon asks for the
    // icon gap on the trailing side as well, because it is measured on its cell while
    // the caption is measured on its ink, and the two would not read as balanced.
    private mtd labelWidth()->f32
    {
        let metrics = .themeMetrics()

        var result = .captionWidth(bold: .form == .Strong) + 2 * metrics.btnPush_TextMargin
        if .icon.isValid() and not .name.isEmpty() do
            result += metrics.iconText_Margin
        return result
    }
}
