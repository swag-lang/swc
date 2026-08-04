using Gui

struct ActionGlobal {}

impl ActionGlobal
{
    newCmdId("ShowLibrary")
    newCmdId("Exit")
    newCmdId("Minimize")
    newCmdId("ShowEditor")
}

impl IActionUI for ActionGlobal
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main = cast(*MainWnd) cxt.wnd!

        switch cxt.id
        {
        case .ShowEditor:
            evt.updatedFields |= .Name
            evt.name          = "Show Editor"

        case .ShowLibrary:
            evt.updatedFields |= .Name | .ToolTip | .Checked
            evt.name          = "Library"
            evt.toolTip       = "Display captures library"
            evt.checked       = main.libraryMode

        case .Exit:
            evt.updatedFields |= .Name | .Icon
            evt.name          = "Quit"
            evt.icon          = main.theme().icon(.Quit)

        case .Minimize:
            evt.updatedFields |= .Name | .Icon
            evt.name          = "Minimize"
            evt.icon          = main.theme().icon(.Minimize)
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = cast(*MainWnd) cxt.wnd!

        switch cxt.id
        {
        case .ShowEditor:
            let srf = main.surface!
            srf.show()
            srf.bringToFront()

        case .ShowLibrary:
            main.swapLibraryMode()

        case .Exit:
            main.saveAppState()
            if @isset(main.libWnd) do
                main.libWnd.requestClose()
            main.postQuitEvent()

        case .Minimize:
            main.saveAppState()
            main.surface?.hide()
        }

        return true
    }
}

impl MainWnd
{
    mtd swapLibraryMode()
    {
        .libraryMode = !.libraryMode

        .editWnd.show(!.libraryMode)
        .quickStyleBar.show(!.libraryMode)
        .recentBar.show(!.libraryMode)
        .editZoomBar.show(!.libraryMode)
        .editToolBar.show(!.libraryMode)

        .libWnd.show(.libraryMode)

        if .libraryMode do
            .libWnd.fill()

        .applyLayout()
    }
}
