#global public

using Core, Pixel

// Pairs a descriptive label with a combo box in one horizontal row.
struct ComboCtrl
{
    public using frameWnd: FrameWnd     // Embedded framed-window behavior and presentation.

    public readonly
    {
        labelWidth: f32 = 60     // Width reserved for the label.
        comboWidth: f32 = 60     // Combo width, or zero to fill remaining space.
        spacing:    f32 = 5      // Gap between label and combo box.

        late label: *Label        // Descriptive label owned by this control.
        late combo: *ComboBox     // Combo box owned by this control.
    }
}

impl IWnd for ComboCtrl
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        if !(.label != null) do
            return

        let rect   = .clientRect()
        let height = .themeMetrics().comboBox_Height
        let y      = rect.vertCenter() - height * 0.5
        let width  = .comboWidth == 0 ? Math.max(rect.width - .spacing - .labelWidth, 0) : .comboWidth
        .label.setPosition(0, y, .labelWidth, height)
        .combo.setPosition(.label.position.right() + .spacing, y, width, height)
    }
}

impl ComboCtrl
{
    // Creates a labelled combo box.
    #[Swag.Discardable]
    func create(parent: *Wnd, name: string?, position: Math.Rectangle = {}, id: WndId? = null)->*ComboCtrl
    {
        Debug.assert(parent != null)
        let metrics = parent.themeMetrics()
        var pos     = position
        if pos.width == 0 do
            pos.width = metrics.comboBox_Width * 2
        if pos.height == 0 do
            pos.height = metrics.comboBox_Height

        with let ctrl = Wnd.create'ComboCtrl(parent, pos, id)
        {
            .label = Label.create(ctrl, name)
            .label.setTextHorizontalAlignment(.Right)
            .combo = ComboBox.create(ctrl)
            .sendResizeEvent()
        }

        return ctrl
    }

    // Changes label width, combo width, and spacing, then reapplies layout.
    mtd setLayoutMetrics(labelWidth, comboWidth, spacing: f32 = 5)
    {
        Debug.assert(labelWidth >= 0 and comboWidth >= 0 and spacing >= 0, "layout metrics cannot be negative")
        if .labelWidth == labelWidth and .comboWidth == comboWidth and .spacing == spacing do
            return
        .labelWidth = labelWidth
        .comboWidth = comboWidth
        .spacing    = spacing
        .sendResizeEvent()
    }
}
