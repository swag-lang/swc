#global public

using Core, Pixel

// Steps a whole number between two bounds: a field holding the value, with a quiet `−` at its
// leading end and a quiet `+` at its trailing end.
//
// The value is a measure, so it is written in the fixed-width face, centred between the two
// buttons. The reader changes it with the buttons or, once the field holds the keyboard, with the
// arrow keys (`Page Up` and `Page Down` take ten steps, `Home` and `End` reach the bounds). It is
// not typed: a value a reader types belongs in an [[Gui.EditBox]] with a numeric range.
//
// ```swag
// with let size = Stepper.create(parent, {0, 0, 120, 0})
// {
//     .setRange(8, 96)
//     .setValue(48)
//     .sigChanged += func(wnd) { applySize(cast(*Stepper, wnd).value) }
// }
// ```
struct Stepper
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        sigChanged: SigArray'func||(*Wnd)     // Emitted after the reader changes the value.

        readonly
        {
            value:    s64                    // Current value, always within the bounds.
            minValue: s64 = Swag.S64.Min     // Smallest value the stepper reaches.
            maxValue: s64 = Swag.S64.Max     // Largest value the stepper reaches.
            step:     s64 = 1                // Amount one press adds or removes.

            late
            {
                decreaseBtn: *IconButton     // Quiet `−` at the leading end.
                increaseBtn: *IconButton     // Quiet `+` at the trailing end.
            }
        }
    }

    isHot: bool     // Whether the pointer is over the field.
}

impl IWnd for Stepper
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        // The window is sized once before its buttons exist; `create` lays them out then.
        if .decreaseBtn == null do
            return

        // Each button is a square cell standing inside the field's frame, one at each end.
        let rect  = .clientRect()
        let inset = .themeMetrics().stepper_ButtonInset
        let side  = Math.max(rect.height - 2 * inset, 0)
        .decreaseBtn.setPosition(rect.x + inset, rect.y + inset, side, side)
        .increaseBtn.setPosition(rect.right() - inset - side, rect.y + inset, side, side)
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let bc      = evt.paintContext
        let painter = bc.painter
        let theme   = .theme()
        let colors  = .themeColors()
        let rects   = .themeRects()
        let metrics = .themeMetrics()

        var colorBk:     Color
        var colorBorder: Color
        var colorText = colors.edit_Text
        switch
        {
        case bc.isDisabled:
            colorBk     = colors.edit_DisabledBk
            colorBorder = colors.edit_DisabledBorder
            colorText   = colors.edit_DisabledText

        case .isHot:
            colorBk     = colors.edit_HotBk
            colorBorder = colors.edit_HotBorder

        default:
            colorBk     = colors.edit_Bk
            colorBorder = colors.edit_Border
        }

        let clientRect = .clientRect()
        .focusRingRadius = rects.edit_SquareBk.radius
        theme.drawSubRect(painter, clientRect, &rects.edit_SquareBk, colorBk)
        theme.drawSubRect(painter, clientRect, &rects.edit_SquareBorder, colorBorder)

        var valueRect = clientRect
        valueRect.x = .decreaseBtn.position.right()
        valueRect.setRight(.increaseBtn.position.x)

        let font  = nnFont(theme.createDefaultFontFamilyFs(metrics.defaultFontSize).regular)
        let text  = Format.toString("%", .value)
        let width = Painter.measureStringSnapped(text.toString(), font, deviceScale: .deviceScale())
        let x     = valueRect.horzCenter() - width * 0.5
        painter.pushClippingRect(valueRect)
        painter.drawString(x, font.opticalLineTop(valueRect.vertCenter()), text.toString(), font, colorText)
        painter.popClippingRect()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        switch evt.kind
        {
        case .Enter:
            .isHot = true
            .invalidate()

        case .Leave:
            .isHot = false
            .invalidate()

        default:
            evt.accepted = false
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed do
            return

        switch evt.key
        {
        case .Up, .Right:  .stepBy(1)
        case .Down, .Left: .stepBy(-1)
        case .PageUp:      .stepBy(PageSteps)
        case .PageDown:    .stepBy(-PageSteps)
        case .Home:        .changeValue(.minValue)
        case .End:         .changeValue(.maxValue)
        default:           return
        }

        evt.accepted = true
    }
}

impl Stepper
{
    // Steps `Page Up` and `Page Down` take at once.
    const PageSteps = 10's64

    // Creates a stepper holding zero, with no bounds and a step of one.
    //
    // A zero height takes the height of a field and a zero width the width the theme gives a
    // stepper; the theme height is also the floor, so the value is never clipped.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: WndId? = null)->*Stepper
    {
        Swag.assert(parent != null)
        let metrics = parent.themeMetrics()
        var pos     = position
        pos.height = Math.max(pos.height, metrics.editBox_Height)
        if pos.width == 0 do
            pos.width = metrics.stepper_Width

        with let result = Wnd.create'Stepper(parent, null, pos, id)
        {
            .focusPolicy = .Tab
            .minSize.y   = metrics.editBox_Height
        }

        result.decreaseBtn = result.createButton(.Minus, -1)
        result.increaseBtn = result.createButton(.Plus, 1)
        result.sendResizeEvent()
        result.updateButtons()
        return result
    }

    // Sets the bounds of the value and brings the value inside them, without notifying.
    mtd setRange(min, max: s64)
    {
        Swag.assert(min <= max, "the smallest value of a stepper is above its largest")
        .minValue = min
        .maxValue = max
        .setValue(.value)
    }

    // Sets the amount one press adds or removes.
    mtd setStep(step: s64)
    {
        Swag.assert(step > 0, "a stepper steps by a positive amount")
        .step = step
    }

    // Sets the value, brought inside the bounds; emits [[Gui.Stepper.sigChanged]] only when `notify` is true and the value moved.
    mtd setValue(value: s64, notify = false)
    {
        let clamped = Math.clamp(value, .minValue, .maxValue)
        if clamped == .value
        {
            .updateButtons()
            return
        }

        .value = clamped
        .updateButtons()
        .invalidate()
        if notify do
            .sigChanged.call(me)
    }

    // Adds `count` steps to the value, as the reader does, and emits [[Gui.Stepper.sigChanged]] when it moved.
    //
    // The sum saturates at the bounds instead of wrapping.
    mtd stepBy(count: s64)
    {
        let delta = count * .step
        if delta > 0 and .value > .maxValue - delta do
            .changeValue(.maxValue)
        elif delta < 0 and .value < .minValue - delta do
            .changeValue(.minValue)
        else do
            .changeValue(.value + delta)
    }
}

private impl Stepper
{
    mtd changeValue(value: s64) => .setValue(value, notify: true)

    // A button that reaches a bound is unavailable, so the field says which way is left.
    mtd updateButtons()
    {
        .decreaseBtn.enable(.value > .minValue)
        .increaseBtn.enable(.value < .maxValue)
    }

    mtd createButton(glyph: ThemeIcons, direction: s64)->*IconButton
    {
        with let result = IconButton.create(me, .theme().icon(glyph, .themeMetrics().stepper_Glyph))
        {
            .setForm(.RoundedRectangle)
            .focusPolicy = .None
            .sigPressed  += func|stepper = me, direction|(_) { stepper.stepBy(direction) }
        }

        return result
    }
}
