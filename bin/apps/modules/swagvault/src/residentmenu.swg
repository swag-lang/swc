using Core, Gui

// A detached menu snapshots mount identities, so a security event cannot retarget a choice.
struct ResidentMenu
{
    using wnd:   Wnd
    late window: *MainWindow
    late menu:   *MenuCtrl
    paths:       Array'String
    watch:       *Timer?
    wasActive:   bool
    armed:       bool
}

impl ResidentMenu
{
    #[Swag.Discardable]
    func open(window: *MainWindow)->*ResidentMenu?
    {
        window.resident.notice?.close()
        window.resident.menu?.close()
        let pointer = Input.mousePosition()
        let surface = PopupMenuSurface.create(window.app(), pointer)
        if not surface do
            return null
        let result = create(surface.wnd, window)
        window.resident.menu = result
        PopupMenuSurface.show(result, result.menu, {pointer.x, pointer.y, 0, 0}, .AtPoint, pointer)
        result.watch = result.addTimer(30'ms)
        return result
    }

    func create(parent: *Wnd, window: *MainWindow)->*ResidentMenu
    {
        with let result = Wnd.create'ResidentMenu(parent)
        {
            .window      = window
            .dockStyle   = .Center
            .focusPolicy = .Click
        }

        result.menu = Wnd.create'MenuCtrl(result)
        let menu = result.menu
        menu.owner     = result
        menu.dockStyle = .Center
        menu.padding   = result.themeMetrics().menuPopup_Padding
        menu.setFramePainting(true)
        menu.addItem(VaultCommands.ShowWindow)
        menu.addItem(VaultCommands.OpenFile)
        let texts = appStrings()
        if window.operation.kind != .None
        {
            menu.addNote(texts.msg_ResidentOperation)
            menu.addItem(VaultCommands.Stop)
        }

        if window.mountedDrives.drives.count
        {
            menu.addSeparator()
            menu.addLabel(Format.toString("% · %", texts.ui_SectionMounted, window.mountedDrives.drives.count))
        }

        for &drive, index in window.mountedDrives.drives
        {
            result.paths.add(drive.path)
            let child = MenuCtrl.createPopup(menu, owner: result)
            let ready = window.operation.kind == .None and not window.resident.batch
            child.addItem(texts.cmd_OpenDrive, Format.toString("vault.resident.open.%", index))
            child.addItem(texts.ui_Unmount, Format.toString("vault.resident.unmount.%", index), disabled: not ready)
            child.addItem(texts.cmd_ForceUnmount, Format.toString("vault.resident.force.%", index), disabled: not ready)
            var label = String.from(drive.mountLabel)
            #static if #os != Swag.TargetOs.Windows
            {
                if window.privacyMode do
                    label = Format.toString(texts.ui_ResidentDrive, index + 1)
            }

            menu.addPopup(label, child)
        }

        menu.addItem(VaultCommands.UnmountAll)
        menu.addSeparator()
        menu.addItem(VaultCommands.Options)
        menu.addItem(VaultCommands.Quit)
        menu.updateState()
        menu.computeLayoutPopup()
        return result
    }

    mtd close()
    {
        .stopTimer(&.watch)
        if .window.resident.menu == me do
            .window.resident.menu = null
        .surface?.destroy()
    }

    mtd choose(id: WndId?)
    {
        let window  = .window
        var path: String
        var command = String.from(id orelse "")
        const DriveCommands = [VaultCommands.OpenDrive, VaultCommands.Unmount, VaultCommands.ForceUnmount]
        for value, index in .paths
        {
            for action, actionIndex in ["open", "unmount", "force"]
            {
                if id == Format.toString("vault.resident.%.%", action, index)
                {
                    path    = value
                    command = DriveCommands[actionIndex]
                }
            }
        }

        .close()
        if not id do
            return
        if path.count
        {
            if not window.isMounted(path) do
                return
            window.chosenPath = path
        }

        if command == VaultCommands.OpenFile or command == VaultCommands.Options do
            window.resident.showWindow()
        window.postCommandEvent(command)
    }
}

impl IWnd for ResidentMenu
{
    mtd impl onComputeStateEvent(evt: *CommandStateEvent)
    {
        if not .window.computeCommandState(evt) do
            evt.accepted = true

        // The window may be hidden on this page; its tray command remains a way back.
        if evt.id == VaultCommands.Options
        {
            evt.hidden = false
            evt.updatedFields.add(.Hidden)
        }
    }

    mtd impl onTimerEvent(_: *TimerEvent)
    {
        if PopupMenuSurface.shouldDismiss(me, .menu, &.wasActive, &.armed) do
            .choose(.menu.modalResult())
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        .menu.handleKeyboard(evt)
        if .menu.isModalEnded() do
            .choose(.menu.modalResult())
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .stopTimer(&.watch)
        if .window.resident.menu == me do
            .window.resident.menu = null
    }
}
