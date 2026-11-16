using Core, Pixel, Gui

// Where the same resident home opens.
enum ResidentPanelPlacement
{
    Centered      // Centered on the monitor, as at startup.
    AtPointer     // Beside the pointer, as a menu of the notification-area icon.
}

// The last captures, as one row of pictures in the hub. A click opens one in the editor.
//
// The pictures are the ones of the recent strip, drawn as it draws them: the row only shows the
// first of them, and follows the strip while it is still loading.
struct HubRecents
{
    using wnd: Wnd

    late main:     *MainWnd
    hovered:       u64 = Swag.U64.Max
    keyboardIndex: u64 = Swag.U64.Max
    chosen:        u64 = Swag.U64.Max     // The picture clicked, which the panel opens on its next watch.
}

impl IWnd for HubRecents
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        for index in .count()
        {
            let item = unwrap .main.recentWnd.recentView.items[index]
            with var infos: RecentInfos
            {
                .hot        = index == (me.keyboardIndex != Swag.U64.Max ? me.keyboardIndex : me.hovered)
                .duration   = item.duration
                .showLinked = false
            }

            RecentView.paintRecent(me, evt.paintContext.painter, item.preview, .tileRect(index), infos)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        var hit = Swag.U64.Max
        if evt.kind != .Leave
        {
            let pos = .surfaceToLocal(evt.surfacePos)
            for index in .count() where .tileRect(index).contains(pos) do
                hit = index
        }

        if hit != .hovered
        {
            .hovered = hit
            .invalidate()
        }

        if evt.kind == .Released and evt.button == .Left and hit != Swag.U64.Max do
            .chosen = hit
        evt.accepted = true
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed or not .count() do
            return

        switch evt.key
        {
        case .Left:
            .keyboardIndex = .keyboardIndex == Swag.U64.Max ? .count() - 1 :
                             (.keyboardIndex + .count() - 1) % .count()

        case .Right:
            .keyboardIndex = .keyboardIndex == Swag.U64.Max ? 0 : (.keyboardIndex + 1) % .count()

        case .Return, .Space:
            .chosen = .keyboardIndex == Swag.U64.Max ? 0 : .keyboardIndex

        default:
            return
        }

        .invalidate()
        evt.accepted = true
    }
}

impl HubRecents
{
    // The row holds five pictures at 4:3, with the air the ring of a tile needs around them.
    const MaxShown   = 5'u64
    const TileWidth  = 80.0
    const TileHeight = 60.0
    const TileGap    = 8.0
    const RowInset   = 6.0

    func create(parent: *Wnd, main: *MainWnd)->*HubRecents
    {
        let width  = cast(f32, MaxShown) * TileWidth + cast(f32, MaxShown - 1) * TileGap + 2 * RowInset
        let height = TileHeight + 2 * RowInset

        with let result = Wnd.create'HubRecents(parent, {0, 0, width, height})
        {
            .main = main
            .backgroundStyle = .Transparent
            .preferredSize   = {width, height}
        }

        return result
    }

    // Returns how many captures `main` can show in the row now.
    func available(main: *MainWnd)->u64
    {
        if main.recentWnd == null do
            return 0
        return Math.min(main.recentWnd.recentView.items.count, MaxShown)
    }

    mtd count()->u64 => available(.main)

    mtd clearKeyboardSelection()
    {
        if .keyboardIndex == Swag.U64.Max do
            return
        .keyboardIndex = Swag.U64.Max
        .invalidate()
    }

    // Returns the cell of the picture `index`.
    mtd tileRect(index: u64)->Math.Rectangle
    {
        let room = .clientRect()
        let left = room.x + RowInset + cast(f32, index) * (TileWidth + TileGap)
        return {left, room.vertCenter() - TileHeight * 0.5, TileWidth, TileHeight}
    }
}

// The floating list a resident Swag Capture answers its icon with, on a surface of its own: the
// main window may be hidden while it is on screen.
//
// One home lists what to capture, what to record, the capture settings and recent captures,
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
    anchor:    Math.Point       // Original screen anchor, retained while recent captures load.
    listSize:  Math.Point       // Size the list asks for, before the surface docks it to its own.
    recents:   *HubRecents?     // The row of recent captures, when the hub has some to show.
    watch:     *Gui.Timer?      // Watches for a choice while the panel floats.
    floating:  bool             // Whether the panel owns its surface, rather than standing in a host.
    wasActive: bool             // Whether the application was the active one since the panel opened.
    armed:     bool             // Whether the detached menu has claimed pointer input after opening.
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

        // A hub opened before the recent captures takes their row when the first one arrives.
        // RecentWnd invalidates this row whenever a later thumbnail changes.
        if let recents = .recents
        {
            if recents.chosen != Swag.U64.Max
            {
                .openRecent(recents.chosen)
                return
            }
        }
        elif not g_Recorder and HubRecents.available(.main)
        {
            .rebuild()
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
        if evt.kind == .Character or
           (evt.kind == .Pressed and (evt.key == .Up or evt.key == .Down or evt.key == .Home or evt.key == .End)) do
            .recents?.clearKeyboardSelection()

        .menu.handleKeyboard(evt)
        if .menu.isModalEnded()
        {
            .choose(.menu.modalResult())
        }
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

        // Once the hub leaves, the application is resident behind its notification-area icon.
        let showNotice = (not id or id == ActionGlobal.Minimize) and main.surface!.isHidden
        .close()
        if showNotice do
            main.noticeResident()

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

    // Leaves the screen, then opens the recent capture `index` in the editor.
    mtd openRecent(index: u64)
    {
        let main = .main
        .close()
        main.showWindow()
        main.openRecent(index)
    }

    // Lists what the panel offers now.
    private mtd fill()
    {
        .menu    = Wnd.create'MenuCtrl(me)
        .recents = null

        // Every command that starts a recording stops the one that runs: it is offered once.
        if g_Recorder do
            .addRecordingItems()
        else do
            .addHubItems()

        with .menu
        {
            .addItem(ActionOptions.Options)
            .addSeparator()

            .addItem(null, ActionGlobal.Minimize, rightName: Input.formatKeyShortcut(.None, .Escape), disabled: me.placement == .AtPointer)
            .addItem(ActionGlobal.Exit)

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
        let main    = .main
        let screens = main.monitors.count > 1 ? main.monitors.count : 0
        with .menu
        {
            .addLabel(texts.ui_MenuCapture)
            .addItem(ActionCapture.Area)
            .addItem(ActionCapture.FullScreen)
            .addItem(ActionCapture.ActiveWnd)
            .addItem(ActionCapture.LastArea)
            for index in screens do
                .addItem(ActionCapture.screenId(index))
            .addLabel(texts.ui_HubRecord)
            .addItem(ActionCapture.RecordVideo)
            .addItem(ActionCapture.RecordScreen)
            .addItem(ActionCapture.RecordActiveWindow)
            .addItem(ActionCapture.Record)
            for index in screens do
                .addItem(ActionCapture.recordScreenId(index))
            .addLabel(texts.ui_MenuCaptureSetup)
        }

        .main.addDelayChoices(.menu, includeCursor: true)

        if HubRecents.available(.main)
        {
            .recents = HubRecents.create(.menu, .main)
            .menu.addLabel(texts.lens_Recent)
            .menu.addWidget(.recents, fullWidth: true)
        }

        with .menu
        {
            .addSeparator()
            .addItem(ActionGlobal.ShowEditor)
            .addItem(ActionGlobal.ShowLibrary)
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
