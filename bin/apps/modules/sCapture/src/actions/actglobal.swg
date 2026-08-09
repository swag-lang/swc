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
            evt.name          = appStrings().act_ShowEditor

        case .ShowLibrary:
            evt.updatedFields |= .Name | .Checked
            evt.name          = appStrings().act_Library
            evt.checked       = main.libraryMode

        case .Exit:
            evt.updatedFields |= .Name | .Icon
            evt.name          = appStrings().act_Quit
            evt.icon          = main.theme().icon(.Quit)

        case .Minimize:
            evt.updatedFields |= .Name | .Icon
            evt.name          = appStrings().act_Minimize
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

        // The tool rail and the tool column belong to the editor: in library mode there is
        // no form to draw and no form to style, so both leave instead of standing empty.
        .editWnd.show(!.libraryMode)
        .rightBar.show(!.libraryMode)
        .recentBar.show(!.libraryMode)
        .toolRail.show(!.libraryMode)
        .commandReadouts.show(!.libraryMode)

        .libWnd.show(.libraryMode)

        if .libraryMode do
            .libWnd.fill()

        .applyLayout()
        if .libraryMode do
            .libWnd.layoutSidebarColumns()
    }
}
