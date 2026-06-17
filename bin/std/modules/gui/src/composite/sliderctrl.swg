#global public
using Core, Pixel

struct SliderCtrl
{
    using frameWnd:     FrameWnd
    labelSize:          f32 = 60
    editSize:           f32 = 60
    gap:                f32 = 8
    autoEditSize:       bool = true     // When true, grow the value box to fit its numeric range; when false, use `editSize` as-is

    sigChanged:         SigArray'func||(*SliderCtrl)

    label:              *Label
    slider:             *Slider
    edit:               *EditBox
}

impl IWnd for SliderCtrl
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        if !.label do
            return
        let rect    = .getClientRect()
        let metrics = .getThemeMetrics()

        .label.setPosition(0, 0, .labelSize, rect.height)

        // Size the value box. With `autoEditSize` the box grows to fit its numeric
        // range so values are never clipped; otherwise the caller-provided `editSize`
        // is used verbatim (e.g. to force a common width across several sliders).
        // In both cases keep the track usable by capping at 60% of the available width.
        // Reserve a gap on each side of the slider (between the label and the track,
        // and between the track and the value box) so the controls aren't cramped.
        let available = Math.max(rect.width - .labelSize - .gap * 2, 0.0)
        var es        = .editSize
        if .autoEditSize
        {
            let adaptive = .edit.numericPreferredWidth()
            if adaptive > es do
                es = Math.min(adaptive, Math.max(available * 0.6, .editSize))
        }
        es = Math.min(es, available)

        let w = available - es
        .slider.setPosition(.label.position.right() + .gap, rect.vertCenter() - metrics.slider_Height / 2, w, metrics.slider_Height)

        .edit.setPosition(.slider.position.right() + .gap, rect.vertCenter() - metrics.editBox_Height / 2, es, metrics.editBox_Height)
    }
}

impl SliderCtrl
{
    // Create the popup list, but: not display it
    func create(parent: *Wnd, name: #null string, position: Math.Rectangle = {}, id: WndId = null)->*SliderCtrl
    {
        let metrics = parent.getThemeMetrics()
        var pos     = position
        if pos.width == 0 do
            pos.width = metrics.slider_Width + metrics.editBox_Width * 2
        if pos.height == 0 do
            pos.height = Math.max(metrics.slider_Height, metrics.editBox_Height)

        with let ctrl = Wnd.create'SliderCtrl(parent, pos, id)
        {
            .label                   = Label.create(ctrl, name, {})
            .label.vertAlignmentText = .Center
            .label.horzAlignmentText = .Right

            .slider = Slider.create(ctrl, {})
            .slider.sigChanged += func|ctrl|(wnd)
            {
                var val: String
                switch ctrl.edit.inputMode
                {
                case .U64:
                    val = Format.toString("%", cast(u64) wnd.getValue())
                case .S64:
                    val = Format.toString("%", cast(s64) wnd.getValue())
                case .F64:
                    val = Format.toString("%{f2}", wnd.getValue())
                }

                ctrl.edit.setText(val)
                ctrl.sigChanged.call(ctrl)
            }

            .edit = EditBox.create(ctrl, "", {})
            .edit.setForm(.Square)
            .edit.editBoxFlags |= .RightAlign
            .edit.rightMargin = metrics.editBox_UnitMargin
            .edit.sigLoseFocus += func|ctrl|(edit)
            {
                switch edit.inputMode
                {
                case .U64:
                    let (val, ?, ?) = catch StrConv.parseU64(edit.text)
                    ctrl.slider.setValue(cast(f32) val)
                case .S64:
                    let (val, ?, ?) = catch StrConv.parseS64(edit.text)
                    ctrl.slider.setValue(cast(f32) val)
                case .F64:
                    let (val, ?, ?) = catch StrConv.parseF64(edit.text)
                    ctrl.slider.setValue(cast(f32) val)
                }
            }

            .sendResizeEvent()
        }

        return ctrl
    }

    // Set a f32 range
    mtd setMinMaxF32(min, max: f32)
    {
        .slider.setMinMax(cast(f32) min, cast(f32) max)
        .edit.setInputF64(cast(f64) min, cast(f64) max)
    }

    // Set a u64 range
    mtd setMinMaxU64(min, max: u64)
    {
        .slider.setMinMax(cast(f32) min, cast(f32) max)
        .slider.sliderFlags |= .Integer
        .edit.setInputU64(min, max)
    }

    // Set a f64 range
    mtd setMinMaxS64(min, max: s64)
    {
        .slider.setMinMax(cast(f32) min, cast(f32) max)
        .slider.sliderFlags |= .Integer
        .edit.setInputS64(min, max)
    }

    // Set the slider current value
    mtd setValue(value: f32)
    {
        .slider.setValue(value)
    }

    // Set the slider current value
    mtd setValueNoChange(value: f32)
    {
        .slider.setValueNoChange(value)
    }

    // Get the slider current value
    mtd getValue()->f32
    {
        return .slider.getValue()
    }
}
