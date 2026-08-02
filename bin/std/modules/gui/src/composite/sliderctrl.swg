#global public

using Core, Pixel

// Combines a label, slider, and validated numeric editor into one control.
struct SliderCtrl
{
    using
    frameWnd: FrameWnd     // Embedded frame wnd state.

    sigChanged: SigArray'func||(*SliderCtrl)     // Emitted after the slider value changes.

    readonly
    {
        labelWidth:     f32  = 60       // Width reserved for the label.
        valueWidth:     f32  = 60       // Minimum or fixed width of the numeric editor.
        spacing:        f32  = 8        // Gap on each side of the slider track.
        autoValueWidth: bool = true     // Whether the numeric editor grows to fit the configured range.

        #[Swag.Late]
        {
            label:  *Label       // Descriptive label.
            slider: *Slider      // Interactive value slider.
            edit:   *EditBox     // Validated numeric editor.
        }
    }
}

impl IWnd for SliderCtrl
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        if !@isset(.label) do
            return
        let rect    = .clientRect()
        let metrics = .themeMetrics()

        .label.setPosition(0, 0, .labelWidth, rect.height)

        // Size the value box. With `autoValueWidth` the box grows to fit its numeric
        // range so values are never clipped; otherwise the caller-provided `valueWidth`
        // is used verbatim (e.g. to force a common width across several sliders).
        // In both cases keep the track usable by capping at 60% of the available width.
        // Reserve a gap on each side of the slider (between the label and the track,
        // and between the track and the value box) so the controls aren't cramped.
        let available = Math.max(rect.width - .labelWidth - .spacing * 2, 0.0)
        var es        = .valueWidth
        if .autoValueWidth
        {
            let adaptive = .edit.numericPreferredWidth()
            if adaptive > es do
                es = Math.min(adaptive, Math.max(available * 0.6, .valueWidth))
        }

        es = Math.min(es, available)

        let w = available - es
        .slider.setPosition(.label.position.right() + .spacing, rect.vertCenter() - metrics.slider_Height / 2, w, metrics.slider_Height)

        .edit.setPosition(.slider.position.right() + .spacing, rect.vertCenter() - metrics.editBox_Height / 2, es, metrics.editBox_Height)
    }
}

impl SliderCtrl
{
    // Creates a labelled numeric slider.
    #[Swag.Discardable]
    func create(parent: *Wnd, name: #null string, position: Math.Rectangle = {}, id: #null WndId = null)->*SliderCtrl
    {
        Debug.assert(parent != null)
        let metrics = parent.themeMetrics()
        var pos     = position
        if pos.width == 0 do
            pos.width = metrics.slider_Width + metrics.editBox_Width * 2
        if pos.height == 0 do
            pos.height = Math.max(metrics.slider_Height, metrics.editBox_Height)

        with let ctrl = Wnd.create'SliderCtrl(parent, pos, id)
        {
            .label = Label.create(ctrl, name, {})
            .label.setTextAlignment(.Right, .Center)

            .slider            = Slider.create(ctrl, {})
            .slider.sigChanged += func|ctrl|(wnd)
            {
                var val: String
                switch ctrl.edit.inputMode
                {
                case .UnsignedInteger: val = Format.toString("%", cast(u64) wnd.value())
                case .SignedInteger:   val = Format.toString("%", cast(s64) wnd.value())
                case .FloatingPoint:   val = Format.toString("%{f2}", wnd.value())
                }

                ctrl.edit.setText(val)
                ctrl.sigChanged.call(ctrl)
            }

            .edit = EditBox.create(ctrl, "", {})
            .edit.setForm(.Rectangle)
            .edit.updateFlags(.RightAligned)
            .edit.setTrailingMargin(metrics.editBox_UnitMargin)
            .edit.sigFocusLost += func|ctrl|(edit)
            {
                switch edit.inputMode
                {
                case .UnsignedInteger: let {val, ?, ?} = catch StrConv.parseU64(edit.text())
                    ctrl.slider.setValue(cast(f32) val)

                case .SignedInteger: let {val, ?, ?} = catch StrConv.parseS64(edit.text())
                    ctrl.slider.setValue(cast(f32) val)

                case .FloatingPoint: let {val, ?, ?} = catch StrConv.parseF64(edit.text())
                    ctrl.slider.setValue(cast(f32) val)
                }
            }

            .sendResizeEvent()
        }

        return ctrl
    }

    // Changes the label width, value-editor width, and spacing between child controls.
    mtd setLayoutMetrics(labelWidth, valueWidth, spacing: f32 = 8)
    {
        Debug.assert(labelWidth >= 0 and valueWidth >= 0 and spacing >= 0, "layout metrics cannot be negative")
        if .labelWidth == labelWidth and .valueWidth == valueWidth and .spacing == spacing do
            return
        .labelWidth = labelWidth
        .valueWidth = valueWidth
        .spacing    = spacing
        .sendResizeEvent()
    }

    // Enables or disables automatic growth of the numeric editor to fit its configured range.
    mtd setAutomaticValueWidth(enabled: bool)
    {
        if .autoValueWidth == enabled do
            return
        .autoValueWidth = enabled
        .sendResizeEvent()
    }

    // Configures floating-point bounds and input validation.
    mtd setFloatBounds(min, max: f32)
    {
        .slider.setBounds(cast(f32) min, cast(f32) max)
        .slider.flags.remove(.Integer)
        .edit.setFloatingPointRange(cast(f64) min, cast(f64) max)
    }

    // Configures unsigned-integer bounds and input validation.
    mtd setUnsignedBounds(min, max: u64)
    {
        .slider.setBounds(cast(f32) min, cast(f32) max)
        .slider.flags |= .Integer
        .edit.setUnsignedIntegerRange(min, max)
    }

    // Configures signed-integer bounds and input validation.
    mtd setSignedBounds(min, max: s64)
    {
        .slider.setBounds(cast(f32) min, cast(f32) max)
        .slider.flags |= .Integer
        .edit.setSignedIntegerRange(min, max)
    }

    // Sets the value and emits the normal value-change gesture.
    mtd setValue(value: f32)
    {
        .slider.setValue(value)
    }

    // Sets the value without emitting a value-change gesture.
    mtd setValueWithoutGesture(value: f32)
    {
        .slider.setValueWithoutGesture(value)
    }

    // Returns the current value.
    mtd const value()->f32
    {
        return .slider.value()
    }
}
