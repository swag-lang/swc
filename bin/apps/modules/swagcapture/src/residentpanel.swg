using Core, Pixel, Gui

// What a resident panel lists.
enum ResidentPanelKind
{
    Hub      // What to capture or record, the recent captures, then the pages of the window.
    Menu     // Every capture command and its settings, as the menu of the notification-area icon.
}

// The last captures, as one row of pictures in the hub. A click opens one in the editor.
//
// The pictures are the ones of the recent strip, drawn as it draws them: the row only shows the
// first of them, and follows the strip while it is still loading.
struct HubRecents
{
    using wnd: Wnd

    late main: *MainWnd
    hovered:   u64 = Swag.U64.Max
    chosen:    u64 = Swag.U64.Max     // The picture clicked, which the panel opens on its next watch.
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
                .hot        = index == me.hovered
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
// The hub stands in the upper middle of the screen and is what the application starts on by
// default: what to capture, what to record, the last captures, then the editor and the library.
// The menu of the notification-area icon stands at the pointer and carries every capture command
// with its settings. While a recording runs, both offer to stop it instead of starting another.
//
// The panel runs no loop of its own. A timer watches for a choice, so the application keeps
// running under it and can quit while it is on screen. It leaves on a choice, on `Esc`, and when
// another application takes the desktop.
struct ResidentPanel
{
    using wnd: Wnd

    late main: *MainWnd
    late menu: *MenuCtrl
    kind:      ResidentPanelKind
    listSize:  Math.Point       // Size the list asks for, before the surface docks it to its own.
    recents:   *HubRecents?     // The row of recent captures, when the hub has some to show.
    watch:     *Gui.Timer?      // Watches for a choice while the panel floats.
    floating:  bool             // Whether the panel owns its surface, rather than standing in a host.
    wasActive: bool             // Whether the application was the active one since the panel opened.
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

        // The recent captures load after the application started: a hub opened before them
        // takes their row when the first one arrives, and follows the others.
        if let recents = .recents
        {
            if recents.chosen != Swag.U64.Max
            {
                .openRecent(recents.chosen)
                return
            }

            if not .main.recentWnd.loadDone do
                recents.invalidate()
        }
        elif .kind == .Hub and not g_Recorder and HubRecents.available(.main)
        {
            .rebuild()
        }

        // A click anywhere else gives the desktop to another application: the panel leaves.
        if .app().isActivated do
            .wasActive = true
        elif .wasActive do
            .choose(null)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind == .Pressed and evt.key == .Escape
        {
            .choose(null)
            evt.accepted = true
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

    // Opens the panel of `kind` on a surface of its own, in place of the one on screen.
    #[Swag.Discardable]
    func open(main: *MainWnd, kind: ResidentPanelKind)->*ResidentPanel?
    {
        main.residentPanel?.close()

        // The surface is created where the pointer is, so it takes the scale of that monitor.
        let pointer = Input.mousePosition()
        let surface = catch main.app().createSurface(cast(s32, pointer.x), cast(s32, pointer.y), 300, 300, .ToolWindow | .TopMost)
        {
            return null
        }

        let result = create(surface.wnd, main, kind)
        result.floating = true
        surface.setView(result)
        result.place(pointer)

        surface.show()
        surface.bringToFront()
        result.setFocus()
        result.watch = result.addTimer(WatchPeriod)
        return result
    }

    // Builds the panel of `kind` in `parent`, without a surface of its own.
    func create(parent: *Wnd, main: *MainWnd, kind: ResidentPanelKind)->*ResidentPanel
    {
        with let result = Wnd.create'ResidentPanel(parent)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Window
            .focusPolicy     = .Click
            .main            = main
            .kind            = kind
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
        .close()
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
        elif .kind == .Hub do
            .addHubItems()
        else do
            .addMenuItems()

        with .menu
        {
            .addItem(ActionOptions.Options)
            .addSeparator()
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
        .fill()
        .applyLayout()

        // A floating panel stays on the monitor it stands on, whatever the pointer did since.
        if .floating
        {
            let stands = .surface!.position
            .place({stands.horzCenter(), stands.vertCenter()})
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
        let texts = appStrings()
        with .menu
        {
            .addLabel(texts.ui_MenuCapture)
            .addItem(ActionCapture.Area)
            .addItem(ActionCapture.FullScreen)
            .addItem(ActionCapture.ActiveWnd)
            .addItem(ActionCapture.LastArea)

            .addLabel(texts.ui_HubRecord)
            .addItem(ActionCapture.RecordVideo)
            .addItem(ActionCapture.RecordFullScreen)
            .addItem(ActionCapture.RecordActiveWindow)
            .addItem(ActionCapture.Record)
        }

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

    private mtd addMenuItems()
    {
        // One monitor is the whole screen: its own entries would only repeat that command.
        let main    = .main
        let screens = main.monitors.count > 1 ? main.monitors.count : 0

        with .menu
        {
            .addItem(ActionGlobal.ShowHub)
            .addItem(ActionGlobal.ShowEditor)

            .addSeparator()
            .addItem(ActionCapture.Area)
            .addItem(ActionCapture.LastArea)
            .addItem(ActionCapture.FullScreen)
            .addItem(ActionCapture.ActiveWnd)
            for index in screens do
                .addItem(ActionCapture.screenId(index))

            .addSeparator()
            .addItem(ActionCapture.RecordVideo)
            .addItem(ActionCapture.RecordFullScreen)
            .addItem(ActionCapture.RecordActiveWindow)
            for index in screens do
                .addItem(ActionCapture.recordScreenId(index))

            .addSeparator()
            .addItem(ActionCapture.Record)

            .addSeparator()
            .addItem(ActionCapture.CaptureCursor)
        }

        main.addDelayChoices(.menu)
        .menu.addSeparator()
    }

    // Stands the surface around its list: the hub in the upper middle of the monitor under
    // `pointer`, the menu at `pointer`. The list is measured in logical units and the surface
    // placed in physical screen pixels.
    mtd place(pointer: Math.Point)
    {
        let surface = unwrap .surface
        let shadow  = .themeMetrics().surfaceWnd_ShadowSize
        let width   = (.listSize.x + 2 * shadow) * surface.dpiScale
        let height  = (.listSize.y + 2 * shadow) * surface.dpiScale

        var corner = pointer
        if .kind == .Hub
        {
            let area = Env.monitorForPoint(pointer).physicalWorkArea
            corner = {area.horzCenter() - width * 0.5, area.y + (area.height - height) * 0.4}
        }

        surface.setPosition({corner.x, corner.y, width, height})
        surface.constrainPositionToScreen()
    }
}
