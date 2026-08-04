using Core, Gui

// A titled, framed panel with an empty body the caller fills in. The two vault
// cards of the main window share this shape.
struct VaultCard
{
    frame: *FrameWnd = undefined
    body:  *Wnd      = undefined
}

impl VaultCard
{
    func create(parent: *Wnd, title, subtitle: string)->VaultCard
    {
        let frame = Wnd.create'FrameWnd(parent)
        frame.setFrameForm(.Square)
        frame.setFrameFlags(.Borders)

        let view = frame.createView'Wnd()
        view.padding = {18, 16, 18, 16}

        with let brandRail = Wnd.create'Wnd(view, {0, 0, 4})
        {
            .dockStyle       = .Left
            .margin.z        = 18
            .backgroundStyle = .Window
            .style.addStyleSheetColors("wnd_Bk $hilight")
        }

        let titleLabel = Label.create(view, title, {0, 0, 0, 34})
        titleLabel.dockStyle = .Top
        titleLabel.setTextAlignment(.Left, .Center)
        titleLabel.style.setFont(view.theme().createDefaultFont(21, .Bold), .Regular)

        let subtitleLabel = Label.create(view, subtitle, {0, 0, 0, 54}, null, .WordWrap | .SecondaryText)
        subtitleLabel.dockStyle = .Top
        subtitleLabel.setTextAlignment(.Left, .Top)

        let body = Wnd.create'Wnd(view)
        body.dockStyle       = .Center
        body.backgroundStyle = .Transparent
        view.applyLayout()
        return {frame, body}
    }
}
