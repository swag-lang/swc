using Gui

// The application commands that switch between the library and the editor, open the hub,
// minimize, and exit.
struct ActionGlobal {}

impl ActionGlobal
{
    newCmdId("ShowLibrary")
    newCmdId("Exit")
    newCmdId("Minimize")
    newCmdId("ShowEditor")
    newCmdId("ShowHub")
}

impl IActionUI for ActionGlobal
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main = mainWndOf(cxt)

        switch cxt.id
        {
        case .ShowEditor:
            evt.updatedFields |= .Name | .Icon
            evt.name = appStrings().act_ShowEditor
            evt.icon = main.theme().icon(.Edit)

        case .ShowHub:
            evt.updatedFields |= .Name | .Icon
            evt.name = appStrings().act_ShowHub
            evt.icon = main.icon(.Capture)

        case .ShowLibrary:
            evt.updatedFields |= .Name | .Checked | .Icon
            evt.name          = appStrings().act_Library
            evt.checked       = main.libraryMode
            evt.icon          = main.icon(.Library)

        case .Exit:
            evt.updatedFields |= .Name | .Icon
            evt.name = appStrings().act_Quit
            evt.icon = main.theme().icon(.Quit)

        case .Minimize:
            evt.updatedFields |= .Name | .Icon
            evt.name = appStrings().act_Minimize
            evt.icon = main.icon(.Resident)
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = mainWndOf(cxt)

        switch cxt.id
        {
        case .ShowEditor:
            main.showWindow()

        case .ShowHub:
            if not main.recentWnd.hubSizeReady() do
                main.openHubAfterRecentLoad = true
            else do
                ResidentPanel.open(main, .Hub)

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
            if let surface = main.surface
            {
                if not surface.isHidden
                {
                    surface.hide()
                    main.noticeResident()
                }
            }
        }

        return true
    }
}

impl MainWnd
{
    // Switches between the editor and the library.
    mtd swapLibraryMode()
    {
        if .libraryMode and .recentWnd.returnToEditor do
            .recentWnd.cancelRequestedSelection()
        .libraryMode = not .libraryMode

        // The work area carries the dock, the inspector, the mini-bar and the hint line of the
        // editor: in library mode there is no form to draw and no form to style, so they leave
        // with it instead of standing empty. The recent strip is a strip of the editor too.
        .recentBar.show(.showRecent and not .libraryMode)
        if .libraryMode
        {
            if g_UpdatingLib do
                .libWnd.view.imgSpin.show()
            .libWnd.fill()
        }
        else
        {
            .libWnd.view.imgSpin.hide()
        }

        let outgoing = .libraryMode ? .editArea : cast(*Wnd, .libWnd)
        let incoming = .libraryMode ? cast(*Wnd, .libWnd) : .editArea

        // Slide the incoming page without fading it: opacity would record the whole
        // editor or library into an off-screen layer on every animation frame.
        incoming.show()
        outgoing.hide()
        .surface?.clearFocus()
        outgoing.resetPresentation()
        let travel = Math.Point{0, .themeMetrics().motion_PageOffset}
        incoming.setPresentationOffset(travel)
        var options: AnimationOptions
        options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_PageSeconds)
        options.easing   = .EaseOut
        discard .app().animator.animatePoint(incoming,
                                             AnimationChannel.from("Capture.Page.Offset"),
                                             travel,
                                             {},
                                             func(wnd, value) { wnd.setPresentationOffset(value) },
                                             options)

        .applyLayout()
        .updateState()
    }
}
