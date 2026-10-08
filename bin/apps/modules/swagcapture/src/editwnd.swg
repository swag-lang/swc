// The scrolling frame around the editor surface.
struct EditWnd
{
    using scrollWnd: ScrollWnd
    late editView:   *EditView
}

impl EditWnd
{
    func create(main: *MainWnd, parent: *Wnd)->*EditWnd
    {
        let scroll = Wnd.create'EditWnd(parent)

        with let view = Wnd.create'EditView(scroll)
        {
            .scroll = scroll
            .main   = main
        }

        scroll.editView = view
        scroll.view     = view
        return scroll
    }

    mtd getCapture()->*Capture? => .editView.capture
}
