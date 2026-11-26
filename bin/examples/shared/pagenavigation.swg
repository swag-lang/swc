using Gui

const PageNavWidth = 176.0

func createPageNavigation(parent: *Wnd, previous, next: func(*Button))->*StackLayoutCtrl
{
    with let nav = StackLayoutCtrl.create(parent, .HorizontalFit)
    {
        .spacing         = 8
        .backgroundStyle = .Transparent
    }

    with let backButton = PushButton.create(nav, "Previous", {0, 0, 84, 32}, form: .Flat)
    {
        .toolTip    = "Previous page (F2)"
        .sigPressed += previous
    }

    with let nextButton = PushButton.create(nav, "Next", {0, 0, 84, 32}, form: .Flat)
    {
        .toolTip    = "Next page (F1)"
        .sigPressed += next
    }

    return nav
}
