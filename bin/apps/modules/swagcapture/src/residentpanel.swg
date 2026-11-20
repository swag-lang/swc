using Core, Pixel, Gui

// The capture window and the transient menu share the same controls.
enum ResidentPanelPlacement
{
    Centered      // The movable window, centered before the user first moves it.
    AtPointer     // The menu of the notification-area icon.
}

struct ResidentPanel
{
    using wnd: Wnd

    late main: *MainWnd
    late menu: *MenuCtrl
    placement: ResidentPanelPlacement
    anchor:    Math.Point
    listSize:  Math.Point
    pictureChoices: *StackLayoutCtrl?
    watch:     *Gui.Timer?
    floating:  bool             // Whether the panel owns its surface.
    wasActive: bool             // Whether the detached menu has had desktop focus.
    armed:     bool             // Whether the detached menu has claimed pointer input.
    otherCaptures: bool
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

        if .placement == .AtPointer and PopupMenuSurface.shouldDismiss(me, .menu, &.wasActive, &.armed) do
            .close()
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind == .Pressed and evt.key == .Escape
        {
            if .otherCaptures do
                .choose(BackToCaptures)
            elif .placement == .AtPointer do
                .close()
            evt.accepted = true
            return
        }

        .menu.handleKeyboard(evt)
        if .menu.isModalEnded() do
            .choose(.menu.modalResult())
    }

    mtd impl onSysCommandEvent(evt: *SysCommandEvent)
    {
        evt.accepted = evt.kind == .Close
        if evt.accepted
        {
            if .placement == .AtPointer do
                .close()
            else do
                .main.postCommandEvent(ActionGlobal.Exit)
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
    const WatchPeriod: Time.Duration = 30'ms
    const MoreCaptures   = "capture.hub.moreCaptures"
    const BackToCaptures = "capture.hub.backToCaptures"

    #[Swag.Discardable]
    func open(main: *MainWnd, placement: ResidentPanelPlacement)->*ResidentPanel?
    {
        let pointer = Input.mousePosition()
        var surface: *Surface?
        if placement == .AtPointer
        {
            surface = PopupMenuSurface.create(main.app(), pointer)
        }
        else
        {
            let point = main.hubBounds.isEmpty() ? pointer : main.hubBounds.topLeft()
            surface = catch main.app().createSurface(cast(s32, point.x), cast(s32, point.y), 300, 300,
                                                     .SmallCaption | .CloseButton)
            {
                return null
            }
        }
        if not surface do
            return null

        main.residentPanel?.close()
        let result = create(surface.wnd, main, placement, placement == .Centered and main.hubOtherCaptures)
        result.floating = true
        if placement == .AtPointer
        {
            result.place(pointer)
        }
        else
        {
            surface.minSize = {}
            surface.setTitle(ProductName)
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

    func create(parent: *Wnd, main: *MainWnd, placement: ResidentPanelPlacement, otherCaptures = false)->*ResidentPanel
    {
        with let result = Wnd.create'ResidentPanel(parent)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Window
            .focusPolicy     = .Click
            .main            = main
            .placement       = placement
            .otherCaptures   = otherCaptures
        }

        result.fill()
        main.residentPanel = result
        return result
    }

    mtd close()
    {
        .stopTimer(&.watch)
        if .placement == .Centered and .floating
        {
            .main.hubBounds = .surface!.position
            .main.hubOtherCaptures = .otherCaptures
        }
        if .main.residentPanel == me do
            .main.residentPanel = null
        if .floating do
            .surface?.destroy()
        else do
            .destroy()
    }

    // Dispatches after the input event. Options and a failed tray registration keep the window.
    mtd choose(id: WndId?)
    {
        if id == MoreCaptures or id == BackToCaptures
        {
            .otherCaptures = id == MoreCaptures
            .rebuild()
            return
        }

        let main = .main
        if .placement == .AtPointer do
            .close()
        elif not id or id == ActionOptions.Options or id == ActionGlobal.Minimize do
            .rebuild()

        if id do
            main.postCommandEvent(id)
    }

    private mtd fill()
    {
        .menu = Wnd.create'MenuCtrl(me)
        .pictureChoices = null
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
                if me.placement == .Centered
                {
                    .addItem(ActionOptions.Options)
                    .addSeparator()
                    .addItem(ActionGlobal.Minimize)
                }
                else
                {
                    .addItem(ActionGlobal.ShowHub)
                    .addSeparator()
                    .addItem(ActionGlobal.Exit)
                }
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

    private mtd rebuild()
    {
        .menu.destroy()
        .armed = false
        .fill()
        .applyLayout()
        .setFocus()
        if .floating
        {
            if .placement == .Centered do
                .main.hubBounds = .surface!.position
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
                .toolTip = HubCopyQuits and me.placement == .Centered and id == ActionCapture.ToClipboard ?
                           texts.tip_InpCopyQuit : state.name
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
        let shadow  = surface.shadowMargin()
        let caption = surface.flags.has(.SmallCaption) ? .themeMetrics().wnd_SmallCaptionCY : 0
        let width   = (.listSize.x + 2 * shadow) * surface.dpiScale
        let height  = (.listSize.y + 2 * shadow + caption) * surface.dpiScale

        let area   = Env.monitorForPoint(pointer).physicalWorkArea
        let corner = .main.hubBounds.isEmpty() ? Math.Point{area.horzCenter() - width * 0.5, area.vertCenter() - height * 0.5} :
                                                 .main.hubBounds.topLeft()

        surface.setPosition({corner.x, corner.y, width, height})
        surface.constrainPositionToScreen()
    }
}
