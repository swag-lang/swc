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
    // The informational palette is deliberately distinct from Capture's yellow action accent.
    mtd updateLibraryButtonAppearance()
    {
        .libraryBtn.style.clearStyleSheetColors()
        if .libraryMode
        {
            .libraryBtn.style.addStyleSheetColors("btnPush_Text          $embInfo_InformationBk")
            .libraryBtn.style.addStyleSheetColors("btnPush_Border        $embInfo_InformationText")
            .libraryBtn.style.addStyleSheetColors("btnPush_Bk            $embInfo_InformationText")
            .libraryBtn.style.addStyleSheetColors("btnPush_HotText       $embInfo_InformationBk")
            .libraryBtn.style.addStyleSheetColors("btnPush_HotBorder     $embInfo_InformationText")
            .libraryBtn.style.addStyleSheetColors("btnPush_HotBk         $embInfo_InformationText")
            .libraryBtn.style.addStyleSheetColors("btnPush_PressedText   $embInfo_InformationBk")
            .libraryBtn.style.addStyleSheetColors("btnPush_PressedBorder $embInfo_InformationText")
            .libraryBtn.style.addStyleSheetColors("btnPush_PressedBk     $embInfo_InformationText")
        }

        .libraryBtn.invalidate()
    }
}
