#global #[Swag.ExplicitNullability]
struct EditWnd
{
    using scrollWnd:     ScrollWnd
    editView:            #null *EditView
}

impl EditWnd
{
    func create(main: #nonull *MainWnd, parent: #nonull *Wnd)->#nonull *EditWnd
    {
        let scroll = Wnd.create'EditWnd(parent)
        let view   = Wnd.create'EditView(scroll)
        view.scroll     = scroll
        view.main       = main
        scroll.editView = view
        scroll.view     = view
        return scroll
    }

    mtd getCapture()->#null *Capture
    {
        return .editView.capture
    }
}