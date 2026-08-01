#global public

using Core, Pixel

// Pairs a descriptive label with a single-line edit box in one horizontal row.
struct EditCtrl
{
    using frameWnd: FrameWnd     // Embedded framed-window behavior and presentation.

    readonly
    {
        labelWidth: f32 = 60     // Width reserved for the label.
        editWidth:  f32 = 60     // Edit width, or zero to fill remaining space.
        spacing:    f32 = 5      // Gap between label and edit box.

        #[Swag.Late]
        label: *Label     // Descriptive label owned by this control.
        #[Swag.Late]
        edit: *EditBox     // Edit box owned by this control.
    }
}

impl IWnd for EditCtrl
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        if !@isset(.label) do
            return

        let rect   = .clientRect()
        let height = .themeMetrics().editBox_Height
        let y      = rect.vertCenter() - height * 0.5
        let width  = .editWidth == 0 ? Math.max(rect.width - .spacing - .labelWidth, 0) : .editWidth
        .label.setPosition(0, y, .labelWidth, height)
        .edit.setPosition(.label.position.right() + .spacing, y, width, height)
    }
}

impl EditCtrl
{
    // Creates a labelled single-line edit box.
    #[Swag.Discardable]
    func create(parent: *Wnd, name: #null string, text: #null string, position: Math.Rectangle = {}, id: #null WndId = null, flags: EditBoxFlags = .None)->*EditCtrl
    {
        Debug.assert(parent != null)
        let metrics = parent.themeMetrics()
        var pos     = position
        if pos.width == 0 do
            pos.width = metrics.editBox_Width * 2
        if pos.height == 0 do
            pos.height = metrics.editBox_Height

        with let ctrl = Wnd.create'EditCtrl(parent, pos, id)
        {
            .label = Label.create(ctrl, name)
            .label.setTextHorizontalAlignment(.Right)
            .edit = EditBox.create(ctrl, text, flags: flags)
            .sendResizeEvent()
        }

        return ctrl
    }

    // Changes label width, edit width, and spacing, then reapplies layout.
    mtd setLayoutMetrics(labelWidth, editWidth, spacing: f32 = 5)
    {
        Debug.assert(labelWidth >= 0 and editWidth >= 0 and spacing >= 0, "layout metrics cannot be negative")
        if .labelWidth == labelWidth and .editWidth == editWidth and .spacing == spacing do
            return
        .labelWidth = labelWidth
        .editWidth  = editWidth
        .spacing    = spacing
        .sendResizeEvent()
    }
}
