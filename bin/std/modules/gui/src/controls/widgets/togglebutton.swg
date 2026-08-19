#global public

using Core, Pixel

// Lets the user switch a Boolean option on or off.
struct ToggleButton
{
    public
    {
        using button: Button     // Embedded button behavior and presentation.

        sigChanged: SigArray'func||(*ToggleButton)     // Emitted after a user action changes the state.
    }

    // Color animations of the painted parts, driven by the toggle and hover state.
    aniBk:     BlendColor     // Color animation of the background.
    aniBorder: BlendColor     // Color animation of the border.
    aniMark:   BlendColor     // Color animation of the toggle mark.
    checked:   bool           // Current programmatic state.
}

impl IWnd for ToggleButton
{
    mtd impl onStateEvent(evt: *StateEvent)
    {
        .button.IWnd.onStateEvent(evt)
        if evt.kind == .Hide or evt.kind == .Disable
        {
            .aniBk.reset()
            .aniBorder.reset()
            .aniMark.reset()
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let bc     = evt.paintContext
        let theme  = .theme()
        let colors = .themeColors()
        let rects  = .themeRects()

        var subRectBk:     #null *ThemeImageRect
        var subRectBorder: #null *ThemeImageRect
        var subRectMark:   #null *ThemeImageRect
        var colorBk:       Color = undefined
        var colorBorder:   Color = undefined
        var colorMark:     Color = undefined

        switch
        {
        case bc.isDisabled:
            colorBk     = colors.btnToggle_DisabledBk
            colorBorder = colors.btnToggle_DisabledBorder
            colorMark   = colors.btnToggle_DisabledMark

        case .isPressed:
            colorBk     = .checked ? colors.btnToggle_OnPressedBk : colors.btnToggle_OffPressedBk
            colorBorder = .checked ? colors.btnToggle_OnPressedBorder : colors.btnToggle_OffPressedBorder
            colorMark   = .checked ? colors.btnToggle_OnPressedMark : colors.btnToggle_OffPressedMark

        case .isHot:
            colorBk     = .checked ? colors.btnToggle_OnHotBk : colors.btnToggle_OffHotBk
            colorBorder = .checked ? colors.btnToggle_OnHotBorder : colors.btnToggle_OffHotBorder
            colorMark   = .checked ? colors.btnToggle_OnHotMark : colors.btnToggle_OffHotMark

        default:
            colorBk     = .checked ? colors.btnToggle_OnBk : colors.btnToggle_OffBk
            colorBorder = .checked ? colors.btnToggle_OnBorder : colors.btnToggle_OffBorder
            colorMark   = .checked ? colors.btnToggle_OnMark : colors.btnToggle_OffMark
        }

        subRectBk     = &rects.btnToggle_Bk
        subRectBorder = &rects.btnToggle_Border
        subRectMark   = &rects.btnToggle_Mark

        .aniBk.apply(me, colorBk)
        .aniBorder.apply(me, colorBorder)
        .aniMark.apply(me, colorMark)

        // A toggle switched on is filled with the accent, which is what the ring points in, so the
        // ring is told what it will be drawn over. Left to the accent it was invisible on exactly
        // the state a reader most often lands on with the keyboard.
        .focusRingRadius = subRectBk!.radius
        .focusRingGround = .aniBk.cur()

        // Box
        let clientRect = .clientRect()
        theme.drawSubRect(bc.painter, clientRect, subRectBk, .aniBk.cur())
        theme.drawSubRect(bc.painter, clientRect, subRectBorder, .aniBorder.cur())

        // Content
        var posBox = clientRect
        posBox.y     = clientRect.vertCenter() - (posBox.height * 0.5)
        posBox.width = posBox.height
        if .checked do
            posBox.x = clientRect.right() - posBox.width
        theme.drawSubRect(bc.painter, posBox, subRectMark, .aniMark.cur())
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if .processMouseEvent(evt) do
            .toggle()
    }

    // Space or Enter toggles the focused button.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed do
            return

        if evt.key == .Space or evt.key == .Return
        {
            .toggle()
            evt.accepted = true
        }
    }
}

impl ToggleButton
{
    // Creates a toggle button with an optional command identifier.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null)->*ToggleButton
    {
        Debug.assert(parent != null)
        var pos = position
        if pos.height == 0 do
            pos.height = parent.themeMetrics().btnToggle_Height
        if pos.width == 0 do
            pos.width = parent.themeMetrics().btnToggle_Width
        let result = Wnd.create'ToggleButton(parent, null, pos, id)
        result.focusPolicy = .Tab
        result.wndFlags    |= .ActivatesOnKey
        return result
    }

    // Reports whether the option is on.
    mtd const isChecked()->bool => .checked

    // Changes the state without emitting a change signal or command.
    mtd setChecked(checked: bool)
    {
        if .checked == checked do
            return
        .checked = checked
        .invalidate()
    }

    // Flips the state and emits the same notifications as a user action.
    mtd toggle()
    {
        .checked = !.checked
        .invalidate()
        .sigChanged.call(me)
        .postCommandEvent(.id)
    }
}
