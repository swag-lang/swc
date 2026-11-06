// The scrolling frame around the editor surface.
struct EditWnd
{
    using scrollWnd: ScrollWnd
    late editView:   *EditView
    late main:       *MainWnd
}

impl IWnd for EditWnd
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .scrollWnd.IWnd.onResizeEvent(evt)
        if .main.hintLine != null do
            .main.placeReadings()
        if .main.miniBar != null do
            .main.placeMiniBar()
    }
}

impl EditWnd
{
    func create(main: *MainWnd, parent: *Wnd)->*EditWnd
    {
        let scroll = Wnd.create'EditWnd(parent)
        scroll.main = main

        with let view = Wnd.create'EditView(scroll)
        {
            .scroll      = scroll
            .main        = main
            .focusPolicy = .Click
        }

        scroll.editView = view
        scroll.view     = view
        return scroll
    }

    mtd getCapture()->*Capture? => .editView.capture
}
