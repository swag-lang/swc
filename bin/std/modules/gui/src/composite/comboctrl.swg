#global public

using Core, Pixel

// Represents combo ctrl.
struct ComboCtrl
{
    using frameWnd: FrameWnd // Embedded frame wnd state.
    labelSize:      f32 = 60 // Label size associated with this value.
    comboSize:      f32 = 60     // 0 to fit to parent size

    #[Swag.Late]
    label: *Label // Label associated with this value.
    #[Swag.Late]
    combo: *ComboBox // Combo associated with this value.
}

impl IWnd for ComboCtrl
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        if !@isset(.label) do
            return

        let rect    = .getClientRect()
        let metrics = .getThemeMetrics()

        .label.setPosition(0, 0, .labelSize, metrics.comboBox_Height)
        let comboW = .comboSize == 0 ? .position.width - 5 - .labelSize : .comboSize
        .combo.setPosition(.label.position.right() + 5, rect.vertCenter() - metrics.comboBox_Height / 2, comboW, metrics.comboBox_Height)
    }
}

impl ComboCtrl
{
    // Performs the create operation.
    func create(parent: *Wnd, name: string, position: Math.Rectangle = {}, id: #null WndId = null)->*ComboCtrl
    {
        let metrics = parent.getThemeMetrics()
        var pos     = position
        if pos.width == 0 do
            pos.width = metrics.comboBox_Width * 2
        if pos.height == 0 do
            pos.height = metrics.comboBox_Height

        with let ctrl = Wnd.create'ComboCtrl(parent, pos, id)
        {
            .label                   = Label.create(ctrl, name)
            .label.horzAlignmentText = .Right

            .combo = ComboBox.create(ctrl)

            .sendResizeEvent()
        }

        return ctrl
    }
}
