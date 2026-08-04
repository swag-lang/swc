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
        let main = cast(*MainWnd) notnull cxt.wnd

        switch cxt.id
        {
        case .ShowEditor:
            evt.updatedFields |= .Name
            evt.name          = appStrings().act_ShowEditor

        case .ShowLibrary:
            evt.updatedFields |= .Name | .ToolTip | .Checked
            evt.name          = appStrings().act_Library
            evt.toolTip       = appStrings().tip_ShowLibrary
            evt.checked       = main.libraryMode

        case .Exit:
            evt.updatedFields |= .Name | .Icon
            evt.name          = appStrings().act_Quit
            evt.icon          = main.theme().icon24(.Quit)

        case .Minimize:
            evt.updatedFields |= .Name | .Icon
            evt.name          = appStrings().act_Minimize
            evt.icon          = main.theme().icon24(.Minimize)
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = cast(*MainWnd) notnull cxt.wnd

        switch cxt.id
        {
        case .ShowEditor:
            let srf = notnull main.surface
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
