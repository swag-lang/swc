#global public

using Core, Pixel

// Selects push button visual emphasis.
enum PushButtonForm
{
    Normal      // Uses standard action emphasis.
    Default     // Highlights the dialog's default action.
    Flat        // Minimizes the idle background and border.
    Strong      // Uses a strong filled background and bold label.
}

// Invokes an action from pointer or keyboard input.
struct PushButton
{
    using button: Button     // Embedded button behavior and presentation.

    readonly
    form = PushButtonForm.Normal     // Current visual emphasis.

    // Color animations of the painted parts, driven by the hover and press state.
    internal
    {
        aniBk:     BlendColor     // Color animation of the background.
        aniBorder: BlendColor     // Color animation of the border.
        aniText:   BlendColor     // Color animation of the label.
    }
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

        if .form == .Default
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
        elif .form == .Flat
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
            switch
            {
            case bc.isDisabled:
                colorBk       = colors.btnPush_DisabledBk
                colorBorder   = colors.btnPush_DisabledBorder
                colorText     = colors.btnPush_DisabledText
                subRectBk     = &rects.btnPush_Disabled
                subRectBorder = &rects.btnPush_DisabledBorder

            // A filled action keeps its own color through every state. Handed the neutral
            // hover of a plain button, it dropped the accent that made it the primary action
            // of the surface exactly as the reader reached it.
            case .isPressed:
                let strong    = .form == .Strong
                colorBk       = strong ? colors.btnPush_StrongPressedBk : colors.btnPush_PressedBk
                colorBorder   = strong ? colors.btnPush_StrongPressedBorder : colors.btnPush_PressedBorder
                colorText     = strong ? colors.btnPush_StrongPressedText : colors.btnPush_PressedText
                subRectBk     = &rects.btnPush_Pressed
                subRectBorder = &rects.btnPush_PressedBorder

            case .isHot:
                let strong    = .form == .Strong
                colorBk       = strong ? colors.btnPush_StrongHotBk : colors.btnPush_HotBk
                colorBorder   = strong ? colors.btnPush_StrongHotBorder : colors.btnPush_HotBorder
                colorText     = strong ? colors.btnPush_StrongHotText : colors.btnPush_HotText
                subRectBk     = &rects.btnPush_Hot
                subRectBorder = &rects.btnPush_HotBorder

            default:
                if .form == .Strong
                {
                    colorBk     = colors.btnPush_StrongBk
                    colorBorder = colors.btnPush_StrongBorder
                    colorText   = colors.btnPush_StrongText
                }
                else
                {
                    colorBk     = colors.btnPush_Bk
                    colorBorder = colors.btnPush_Border
                    colorText   = colors.btnPush_Text
                }

                subRectBk     = &rects.btnPush_Normal
                subRectBorder = &rects.btnPush_NormalBorder
            }
        }

        // Background
        let clientRect = .clientRect()
        .aniBk.apply(me, colorBk)
        theme.drawSubRect(bc.painter, clientRect, subRectBk, .aniBk.cur())

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
        if .form == .Strong and !bc.isDisabled do
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
        res.form = form

        // An unstated width belongs to the caption: the theme width above only gives the
        // button a sane size until the first layout pass measures it, and stays its floor.
        if position.width == 0 do
            res.preferredSize.x = 0
        if id != null do
            res.updateCommandState()
        return res
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
