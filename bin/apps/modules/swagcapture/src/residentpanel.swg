using Core, Pixel, Gui

// Where the same resident home opens.
enum ResidentPanelPlacement
{
    Centered      // Centered on the monitor, as at startup.
    AtPointer     // Beside the pointer, as a menu of the notification-area icon.
}

// The floating list a resident Swag Capture answers its icon with, on a surface of its own: the
// main window may be hidden while it is on screen.
//
// One home lists what to capture, what to record and the capture settings,
// then the editor, the library and the way back behind the icon. It opens centered at startup
// or beside the pointer from the icon. While recording, it offers to stop or abandon the session.
//
// The panel runs no loop of its own. A timer watches for a choice, so the application keeps
// running under it and can quit while it is on screen. It leaves on a choice, on `Esc`, and when
// another application takes the desktop.
struct ResidentPanel
{
    using wnd: Wnd

    late main: *MainWnd
    late menu: *MenuCtrl
    placement: ResidentPanelPlacement
    anchor:    Math.Point       // Original screen anchor, retained when switching pages.
    listSize:  Math.Point       // Size the list asks for, before the surface docks it to its own.
    pictureChoices: *StackLayoutCtrl?
    watch:     *Gui.Timer?      // Watches for a choice while the panel floats.
    floating:  bool             // Whether the panel owns its surface, rather than standing in a host.
    wasActive: bool             // Whether the application was the active one since the panel opened.
    armed:     bool             // Whether the detached menu has claimed pointer input after opening.
    captureQueued: bool         // The capture command will close the hub when it takes the screen.
    otherCaptures: bool          // The page for less common capture and recording targets.
}

impl IWnd for ResidentPanel
{
    mtd impl onTimerEvent(_: *TimerEvent)
    {
        if .menu.isModalEnded()
        {
            .choose(.menu.modalResult())
            return
        }

        if .placement == .AtPointer
        {
            if PopupMenuSurface.shouldDismiss(me, .menu, &.wasActive, &.armed) do
                .choose(null)
            return
        }

        // A click anywhere else gives the desktop to another application: the hub leaves.
        if .hasDesktopFocus() do
            .wasActive = true
        elif .wasActive do
            .choose(null)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if .otherCaptures and evt.kind == .Pressed and evt.key == .Escape
        {
            .choose(BackToCaptures)
            evt.accepted = true
            return
        }

        .menu.handleKeyboard(evt)
        if .menu.isModalEnded() do
            .choose(.menu.modalResult())
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        if .main.residentPanel == me do
            .main.residentPanel = null
    }
}

impl ResidentPanel
{
    // Period of the watch for a choice: short enough that a click feels immediate.
    const WatchPeriod: Time.Duration = 30'ms
    const MoreCaptures   = "capture.hub.moreCaptures"
    const BackToCaptures = "capture.hub.backToCaptures"

    // On Windows, activation belongs to the process, so another window in this process can
    // take the foreground while Application.isActivated remains true.
    private mtd hasDesktopFocus()->bool
    {
        #static if #os == Swag.TargetOs.Windows
        {
            if .floating do
                return Win32.GetForegroundWindow() == .surface!.win32Handle()
        }

        return .app().isActivated
    }

    // Opens the resident home at `placement`, replacing the one on screen.
    #[Swag.Discardable]
    func open(main: *MainWnd, placement: ResidentPanelPlacement)->*ResidentPanel?
    {
        main.residentNotice?.close()
        main.residentPanel?.close()

        // The surface is created where the pointer is, so it takes the scale of that monitor.
        let pointer = Input.mousePosition()
        let surface = PopupMenuSurface.create(main.app(), pointer)
        if not surface do
            return null

        let result = create(surface.wnd, main, placement)
        result.floating = true
        if placement == .AtPointer
        {
            result.place(pointer)
        }
        else
        {
            surface.setView(result)
            result.place(pointer)
            surface.show()
            surface.bringToFront()
            #static if #os == Swag.TargetOs.Windows
            {
                if surface.win32Handle() do
                    discard Win32.SetForegroundWindow(surface.win32Handle())
            }

            result.setFocus()
        }

        result.watch = result.addTimer(WatchPeriod)
        return result
    }

    // Builds the same home in `parent`, regardless of where it will open.
    func create(parent: *Wnd, main: *MainWnd, placement: ResidentPanelPlacement)->*ResidentPanel
    {
        with let result = Wnd.create'ResidentPanel(parent)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Window
            .focusPolicy     = .Click
            .main            = main
            .placement       = placement
        }

        result.fill()
        main.residentPanel = result
        return result
    }

    // Takes the panel off the screen.
    mtd close()
    {
        .stopTimer(&.watch)
        if .main.residentPanel == me do
            .main.residentPanel = null
        if .floating do
            .surface?.destroy()
        else do
            .destroy()
    }

    // Leaves the screen, then runs the command `id` on the main window. A null `id` only leaves.
    mtd choose(id: WndId?)
    {
        let main = .main
        if .captureQueued do
            return

        if id == MoreCaptures or id == BackToCaptures
        {
            .otherCaptures = id == MoreCaptures
            .rebuild()
            return
        }

        // Keep the origin until the queued capture starts, then clear the hub before the grab.
        if id and ActionCapture.pictureTarget(id).found
        {
            .captureQueued = true
            .stopTimer(&.watch)
            main.postCommandEvent(id)
            return
        }

        // Once the hub leaves, the application is resident behind its notification-area icon.
        let showNotice = (not id or id == ActionGlobal.Minimize) and main.surface!.isHidden
        .close()
        if showNotice do
            main.enterResident()

        if not id do
            return

        // The library and the options stand in the main window, which may be hidden.
        if id == ActionGlobal.ShowLibrary or id == ActionOptions.Options do
            main.showWindow()

        // The library command switches pages: asked for from the library, it would leave it.
        if id == ActionGlobal.ShowLibrary and main.libraryMode do
            return
        main.postCommandEvent(id)
    }

    // Lists what the panel offers now.
    private mtd fill()
    {
        .menu    = Wnd.create'MenuCtrl(me)
        .pictureChoices = null

        // Every command that starts a recording stops the one that runs: it is offered once.
        if g_Recorder do
            .addRecordingItems()
        elif .otherCaptures do
            .addOtherCaptures()
        else do
            .addHubItems()

        with .menu
        {
            if not me.otherCaptures or g_Recorder
            {
                .addItem(ActionOptions.Options)
                .addSeparator()
                .addItem(null, ActionGlobal.Minimize, rightName: Input.formatKeyShortcut(.None, .Escape), disabled: me.placement == .AtPointer)
                .addItem(ActionGlobal.Exit)
            }

            .owner     = me.main
            .dockStyle = .Center
            .padding   = 10
            .setFramePainting(true)
            .updateState()
            .computeLayoutPopup()
        }

        .listSize = {.menu.position.width, .menu.position.height}
    }

    // Fills the panel again where it stands, when what it offers changed.
    private mtd rebuild()
    {
        .menu.destroy()
        .armed = false
        .fill()
        .applyLayout()

        // The list that left may have held the keyboard: `Esc` stays with the panel.
        .setFocus()

        // A floating panel stays on the monitor it stands on, whatever the pointer did since.
        if .floating
        {
            .place(.anchor)
        }
    }

    private mtd addRecordingItems()
    {
        with .menu
        {
            .addItem(ActionCapture.RecordVideo)
            .addItem(ActionCapture.CancelRecording)
            .addSeparator()
            .addItem(ActionGlobal.ShowEditor)
        }
    }

    private mtd addHubItems()
    {
        let texts   = appStrings()
        with .menu
        {
            .addLabel(texts.ui_MenuCapture)
            .addItem(ActionCapture.Area)
            .addItem(ActionCapture.FullScreen)
            .addItem(ActionCapture.ActiveWnd)
        }

        .addPictureChoices()

        with .menu
        {
            .addSeparator()
            .addItem(ActionCapture.RecordVideo)
            .addItem(texts.ui_HubMoreCaptures, MoreCaptures, me.theme().icon(.More))
            .addLabel(texts.ui_MenuCaptureSetup)
        }

        .main.addDelayChoices(.menu, includeCursor: true)

        with .menu
        {
            .addSeparator()
            .addItem(ActionGlobal.ShowEditor)
            .addItem(ActionGlobal.ShowLibrary)
        }
    }

    private mtd addOtherCaptures()
    {
        let texts   = appStrings()
        let screens = .main.monitors.count > 1 ? .main.monitors.count : 0
        with .menu
        {
            .addItem(texts.ui_HubBackToCaptures, BackToCaptures, me.theme().icon(.ChevronLeft))
            .addLabel(texts.ui_MenuCapture)
            .addItem(ActionCapture.LastArea)
            for index in screens do
                .addItem(ActionCapture.screenId(index))
        }

        .addPictureChoices()

        with .menu
        {
            .addLabel(texts.ui_HubRecord)
            .addItem(ActionCapture.RecordScreen)
            .addItem(ActionCapture.RecordActiveWindow)
            .addItem(ActionCapture.Record)
            for index in screens do
                .addItem(ActionCapture.recordScreenId(index))
        }
    }

    const PictureChoiceCommands = [ActionCapture.ToClipboard, ActionCapture.ToInPlace, ActionCapture.ToEditor]

    // A radio row changes the destination without closing the hub. The same commands are
    // available from the editor's lens and command menu.
    private mtd addPictureChoices()
    {
        let texts   = appStrings()
        let main    = .main
        let metrics = .themeMetrics()
        let labels  = [texts.prop_PictureClipboard, texts.prop_PictureInPlace, texts.ui_SectionEditor]
        .menu.addLabel(texts.ui_AfterPictureCapture)

        with let choices = StackLayoutCtrl.create(.menu, .HorizontalCenter)
        {
            .backgroundStyle = .Transparent
            .spacing         = metrics.menuPopup_SpaceLines
            .hookOnEvent    = func|panel = me|(_, evt)->bool
            {
                if evt is KeyEvent as key where key.kind == .Pressed and (key.key == .Left or key.key == .Right)
                {
                    panel.stepPictureChoice(key.key == .Right)
                    key.accepted = true
                    return true
                }
                return false
            }
        }

        for id, index in PictureChoiceCommands
        {
            let state = main.sendComputeCommandStateEvent(id)
            with let button = IconButton.create(choices, state.icon,
                                                {0, 0, 0, metrics.menuPopup_ItemHeight - metrics.menuPopup_SpaceLines * 0.75}, flags: .Radio)
            {
                .preferredSize.x = 0
                .padding         = metrics.btnIcon_Padding * 0.5
                .setIconSize(metrics.menuPopup_IconSize, metrics.menuPopup_IconSize)
                .setText(labels[index])
                .setTextPosition(.Right)
                .setForm(.RoundedRectangle)
                .setCheckIndicator(.Frame)
                .toolTip = state.name
                .sigCheckedChanged += func|main, id|(_) { main.sendCommandEvent(id) }
            }
        }

        .pictureChoices = choices
        .updatePictureChoices()
        .menu.addWidget(choices, fullWidth: true)
    }

    mtd updatePictureChoices()
    {
        if let choices = .pictureChoices
        {
            for id, index in PictureChoiceCommands
            {
                let button = assume cast(*IconButton, choices.children[index])
                button.setChecked(ActionCapture.destination(id).value == .main.captureOptions.pictureDestination)
            }
        }
    }

    private mtd stepPictureChoice(forward: bool)
    {
        let count = PictureChoiceCommands.count
        for id, index in PictureChoiceCommands where ActionCapture.destination(id).value == .main.captureOptions.pictureDestination
        {
            let next = (index + (forward ? 1 : count - 1)) % count
            .main.sendCommandEvent(PictureChoiceCommands[next])
            return
        }
    }

    // Stands the same home centered on the monitor or beside `pointer`.
    // The list uses logical units; the surface and its anchor use physical screen pixels.
    mtd place(pointer: Math.Point)
    {
        .anchor = pointer
        if .placement == .AtPointer
        {
            PopupMenuSurface.show(me, .menu, {pointer.x, pointer.y, 0, 0}, .AtPoint, pointer)
            return
        }

        let surface = unwrap .surface
        let shadow  = .themeMetrics().surfaceWnd_ShadowSize
        let width   = (.listSize.x + 2 * shadow) * surface.dpiScale
        let height  = (.listSize.y + 2 * shadow) * surface.dpiScale

        let area   = Env.monitorForPoint(pointer).physicalWorkArea
        let corner = Math.Point{area.horzCenter() - width * 0.5, area.vertCenter() - height * 0.5}

        surface.setPosition({corner.x, corner.y, width, height})
        surface.constrainPositionToScreen()
    }
}
