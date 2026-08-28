#global public

using Core, Pixel

// Selects push button visual emphasis.
enum PushButtonForm
{
    Normal      // Uses standard action emphasis.
    Default     // Highlights the dialog's default action.
    Flat        // Minimizes the idle background and border.
    Strong      // Uses a strong filled background and bold label.

    // Fills with the theme's alternate tone, for the action that leads somewhere else rather
    // than the one that does the work of the surface.
    //
    // It is not a weaker strong button and it does not compete with one: a surface shows the
    // action it is for, and beside it the page the reader can leave to. Both are filled, and
    // only the tone tells them apart — which is what the second tone of a theme is for.
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

        var subRectBk:     #null *ThemeImageRect
        var subRectBorder: #null *ThemeImageRect
        var colorBk:       Color = undefined
        var colorBorder:   Color = undefined
        var colorText:     Color = undefined

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
            var rest, hot, pressed: {bk, border, text: Color} = undefined
            switch form
            {
            case .Strong: rest = {colors.btnPush_StrongBk, colors.btnPush_StrongBorder, colors.btnPush_StrongText}
                hot     = {colors.btnPush_StrongHotBk, colors.btnPush_StrongHotBorder, colors.btnPush_StrongHotText}
                pressed = {colors.btnPush_StrongPressedBk, colors.btnPush_StrongPressedBorder, colors.btnPush_StrongPressedText}

            case .Alternate: rest = {colors.btnPush_AlternateBk, colors.btnPush_AlternateBorder, colors.btnPush_AlternateText}
                hot     = {colors.btnPush_AlternateHotBk, colors.btnPush_AlternateHotBorder, colors.btnPush_AlternateHotText}
                pressed = {colors.btnPush_AlternatePressedBk, colors.btnPush_AlternatePressedBorder, colors.btnPush_AlternatePressedText}

            default: rest = {colors.btnPush_Bk, colors.btnPush_Border, colors.btnPush_Text}
                hot     = {colors.btnPush_HotBk, colors.btnPush_HotBorder, colors.btnPush_HotText}
                pressed = {colors.btnPush_PressedBk, colors.btnPush_PressedBorder, colors.btnPush_PressedText}
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

        // The ring is drawn last, over a button whose shape and fill were only just decided, so it
        // is told both: the Swag palette points a push button at the edit tiles, and a pill is not
        // marked like a square corner; a button that has become the dominant action of the surface
        // is filled with the accent the ring itself points in. The fill it is told about is the
        // animated one, so the ring stays readable through a hover rather than only at rest.
        .focusRingRadius = subRectBk!.radius
        .focusRingGround = .aniBk.cur()

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

        // The bold weight is what makes a filled button the primary action of the surface.
        // A button that cannot be pressed is the primary action of nothing, and kept bold it
        // read as a lighter grey than the plain button beside it, in the same disabled state.
        if form == .Strong and !bc.isDisabled do
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

        .sigPressed.call(cast(*Button) me)
        .postCommandEvent(.id)
        evt.accepted = true
    }

    // Reports the room the caption, the optional icon, and the button padding need.
    //
    // The theme push-button width stays a floor, so a short caption keeps the regular
    // button size of the surface and only a caption that would not fit widens it.
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        discard available

        let metrics = .themeMetrics()
        return {Math.max(.labelWidth(), metrics.btnPush_Width), metrics.btnPush_Height}
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
    #[Swag.Discardable]
    func create(parent: *Wnd, name: string, position: Math.Rectangle = {}, id: #null WndId = null, form = PushButtonForm.Normal)->*PushButton
    {
        Debug.assert(parent != null)
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
    // Only the two plain emphases take part. A flat button belongs to a tool bar, and a filled
    // one — strong or alternate — carries its own tone through every state; none of them stands
    // for the answer to a box.
    mtd paintedForm()->PushButtonForm
    {
        if .form == .Flat or .form == .Strong or .form == .Alternate do
            return .form

        let srf = .surface
        if !srf or !srf.defaultButton do
            return .form

        var dominant = srf.defaultButton!
        let focus    = srf.app.keyboardFocusWnd
        if focus and focus != dominant and focus.surface == srf and focus.type == PushButton
        {
            let other = cast(*PushButton) focus
            if other.form == .Normal or other.form == .Default do
                dominant = focus
        }

        return dominant == cast(*Wnd) me ? PushButtonForm.Default : PushButtonForm.Normal
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
        if .icon.isValid() and @countof(.name) != 0 do
            result += metrics.iconText_Margin
        return result
    }
}
