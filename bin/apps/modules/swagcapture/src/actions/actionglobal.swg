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

            // A deferred save that hasn't fired yet, and a background save still
            // writing, must both land before the process goes away.
            let capture = main.editWnd.getCapture()
            if capture and capture.changed do
                main.saveCapture(capture)
            main.flushCaptureSave()

            if main.libWnd != null do
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
        .updateLibraryButtonAppearance()

        // The tool rail and the tool column belong to the editor: in library mode there is
        // no form to draw and no form to style, so both leave instead of standing empty.
        .rightBar.show(!.libraryMode)
        .recentBar.show(!.libraryMode)
        .toolRail.show(!.libraryMode)
        .commandReadouts.show(!.libraryMode)

        if .libraryMode do
            .libWnd.fill()

        let outgoing = .libraryMode ? cast(*Wnd) .editWnd : cast(*Wnd) .libWnd
        let incoming = .libraryMode ? cast(*Wnd) .libWnd : cast(*Wnd) .editWnd

        // This change replaces nearly the whole client area. Fading both pages records two
        // full-size subtrees into off-screen layers on every frame, which is disproportionately
        // expensive for an image editor and its thumbnail library. Local control motion remains
        // animated; the workspace handoff is immediate.
        outgoing.hide()
        incoming.show()

        .applyLayout()
        if .libraryMode do
            .libWnd.layoutSidebarColumns()
    }

    // Keeps Library a regular push button until it represents the page currently on screen.
    //
    // Filled, it takes the theme's alternate tone, which is the whole reason a theme owns one:
    // Capture is what this surface is for and wears the signature, and Library is the other
    // page the reader can be on. Borrowing the informational notice colors for it said "notice"
    // in a place nothing was being reported, and left the app answering for nine colors the
    // theme should have answered for.
    mtd updateLibraryButtonAppearance()
    {
        .libraryBtn.setForm(.libraryMode ? .Alternate : .Normal)
        .libraryBtn.invalidate()
    }
}
