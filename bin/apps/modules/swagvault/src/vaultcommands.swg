using Core, Gui

// The commands of the window.
//
// Each command is an entry of the lens, found by its name. The lens writes shortcuts beside their
// commands. The context menu and the unfolded card offer the same commands by identifier.
namespace VaultCommands
{
    const Lens             = "vault.lens"
    const NewVault         = "vault.new"
    const OpenFile         = "vault.openFile"
    const Vaults           = "vault.vaults"
    const Options          = "vault.options"
    const Mount            = "vault.mount"
    const Unmount          = "vault.unmount"
    const OpenDrive        = "vault.openDrive"
    const ReadOnly         = "vault.readOnly"
    const ProtectHidden    = "vault.protectHidden"
    const AtStartup        = "vault.atStartup"
    const ChangePassword   = "vault.changePassword"
    const ChangeKeyFiles   = "vault.changeKeyFiles"
    const Resize           = "vault.resize"
    const CreateHidden     = "vault.createHidden"
    const Forget           = "vault.forget"
    const Stop             = "vault.stop"
    const PrivacyMode      = "vault.privacyMode"
    const UnmountOnLock    = "vault.unmountOnLock"
    const UnmountOnSuspend = "vault.unmountOnSuspend"
    const UnmountOnIdle    = "vault.unmountOnIdle"
    const ShowWindow       = "vault.showWindow"
    const UnmountAll       = "vault.unmountAll"
    const Quit             = "vault.quit"
    const ForceUnmount     = "vault.forceUnmount"
    const Resident         = "vault.resident"
    const SessionStartup   = "vault.sessionStartup"
    const InstallWinFsp    = "vault.installWinFsp"
}

impl MainWindow
{
    // The commands of the chosen vault, in the order the lens and the context menu of a row list them.
    const VaultCommandIds = [VaultCommands.Mount, VaultCommands.Unmount, VaultCommands.ForceUnmount, VaultCommands.OpenDrive, VaultCommands.ReadOnly,
                             VaultCommands.ProtectHidden, VaultCommands.AtStartup, VaultCommands.ChangePassword,
                             VaultCommands.ChangeKeyFiles, VaultCommands.Resize, VaultCommands.CreateHidden,
                             VaultCommands.Forget, VaultCommands.Stop]

    // The actions of the chosen vault the lens offers at rest; only those that apply to it now show.
    const RestVaultIds = [VaultCommands.OpenDrive, VaultCommands.Mount, VaultCommands.Unmount, VaultCommands.Stop]

    // Creates the lens, registers every command of the window under its family, the vaults it
    // knows as a source, and the appearance. At rest the lens keeps New Vault and Open File
    // first, followed by the actions of the chosen vault.
    mtd createLens()
    {
        with .lens = Lens.View.create(me)
        {
            .addRestSource(func|window = me|(results)
            {
                let section = results.addSection(appStrings().lens_File)
                window.lens.addCommandRows(section, [VaultCommands.NewVault, VaultCommands.OpenFile, VaultCommands.Options], enabledOnly: true)
            })
            .addRestSource(func|window = me|(results) { window.describeChosenVault(results) })
            .addSource(.File, func|window = me|(results) { window.describeVaults(results) })
            .addCommand(func()->string => appStrings().lens_File, VaultCommands.NewVault, func()->string => appStrings().search_Create)
            .addCommand(func()->string => appStrings().lens_File, VaultCommands.OpenFile, func()->string => appStrings().search_Open)
            .addCommands(func()->string => appStrings().lens_File, [VaultCommands.Vaults, VaultCommands.Options, VaultCommands.ShowWindow,
                                                                    VaultCommands.UnmountAll, VaultCommands.Quit, VaultCommands.Resident, VaultCommands.SessionStartup])
            .addCommands(func()->string => appStrings().lens_Vault, VaultCommandIds)
            #static if SupportsWinFspInstall do
                .addCommands(func()->string => appStrings().lens_File, [VaultCommands.InstallWinFsp])
            .addCommands(func()->string => appStrings().lens_Privacy, [VaultCommands.PrivacyMode, VaultCommands.UnmountOnLock, VaultCommands.UnmountOnSuspend,
                                                                       VaultCommands.UnmountOnIdle])
        }

        .appearanceButton.addToLens(.lens)

        // The lens uses one chord everywhere. Escape folds the unfolded vault, or leads back to
        // the list from another page.
        .registerKeyShortcut(.Control, .Space, VaultCommands.Lens)
        .registerKeyShortcut(.Control, .N, VaultCommands.NewVault)
        .registerKeyShortcut(.Control, .O, VaultCommands.OpenFile)
        .registerKeyShortcut(.None, .Escape, VaultCommands.Vaults)
    }

    // Answers the lens at rest with the actions of the chosen vault, under its name.
    mtd describeChosenVault(results: *Lens.Results)
    {
        if .chosenPath.isEmpty() do
            return
        let path    = .chosenPath.toString()
        let section = results.addSection(Path.fileName(path) orelse path)
        .lens.addCommandRows(section, RestVaultIds, enabledOnly: true)
    }

    // Answers the lens with the vaults the list knows; choosing one unfolds it.
    mtd describeVaults(results: *Lens.Results)
    {
        var section: *Lens.Section?
        for &vault in .vaults
        {
            let path  = vault.path.toString()
            let name  = Path.fileName(path) orelse path
            var found = Lens.match(results.folded, name)
            if not found.matched do
                continue
            if not section do
                section = results.addSection(appStrings().lens_Vaults)
            with let entry = section.addEntry(name, #move found)
            {
                .detail     = me.vaultIdentity(path)
                .monoDetail = true
                .checked    = me.chosenPath == path
                .glyph      = me.theme().fileGlyph(path, false, me.themeMetrics().menuPopup_IconSize)
                .run        = func|window = me, path|() { window.chooseVault(path) }
            }
        }
    }

    // Shows the commands of the chosen vault at `surfacePos`, as a row's context menu.
    mtd showVaultMenu(surfacePos: Math.Point)
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItems(VaultCommandIds)
        let chosen = menu.doModal(surfacePos, .TopLeft, autoDestroy: true)
        if chosen do
            discard .runCommand(chosen)
    }

    // Opens the modification commands from the unfolded vault's header.
    mtd showVaultEditMenu(button: *IconButton)
    {
        if .chosenLockedPath().count == 0 do
            return

        let menu = MenuCtrl.createPopup(button, owner: me)
        menu.addItems([VaultCommands.ChangePassword, VaultCommands.ChangeKeyFiles, VaultCommands.Resize])
        discard menu.doModal(button, autoDestroy: true)
    }

    // Describes one command of the window for the lens and every other presenter: its name, and
    // whether it applies, is available and is in force now.
    mtd computeCommandState(evt: *CommandStateEvent)->bool
    {
        let texts    = appStrings()
        let ready    = .operation.kind == .None and not .resident.batch
        let chosen   = not .chosenPath.isEmpty()
        let drive    = .mountedDrives.find(.chosenPath)
        let locked   = chosen and drive == null
        let stopping = .operation.kind == .Create or .operation.kind == .Resize

        var name:     String
        var hidden:   bool
        var disabled: bool
        var toggle:   bool
        var checked:  bool
        var icon:     ThemeIcons
        switch evt.id
        {
        case VaultCommands.ShowWindow:
            name = texts.cmd_ShowWindow
            icon = .OpenExternal

        case VaultCommands.UnmountAll:
            name     = texts.cmd_UnmountAll
            icon     = .Remove
            disabled = not ready or .mountedDrives.drives.count == 0

        case VaultCommands.Quit:
            name     = texts.cmd_Quit
            icon     = .WndClose
            disabled = not ready

        case VaultCommands.Resident:
            name    = texts.ui_Resident
            icon    = .Options
            toggle  = true
            checked = .resident.settings.enabled

        case VaultCommands.SessionStartup:
            name     = texts.ui_SessionStartup
            icon     = .Update
            toggle   = true
            checked  = .resident.settings.startWithSession
            disabled = not .resident.settings.enabled

        case VaultCommands.Lens:
            return false

        case VaultCommands.NewVault:
            name     = texts.ui_NewVault
            icon     = .Plus
            disabled = not ready

        case VaultCommands.OpenFile:
            name     = texts.ui_OpenFile
            icon     = .OpenFile
            disabled = not ready

        case VaultCommands.Vaults:
            name   = texts.ui_VaultsTitle
            icon   = .Folder
            hidden = .page == .List and not locked

        case VaultCommands.Options:
            name   = texts.cmd_Options
            icon   = .Settings
            hidden = .page == .Options

        case VaultCommands.InstallWinFsp:
            name     = texts.cmd_InstallWinFsp
            hidden   = not SupportsWinFspInstall or hasInstalledWinFsp()
            disabled = not ready or not .mountedDrives.drives.isEmpty()

        case VaultCommands.Mount:
            name     = texts.ui_Mount
            icon     = .Link
            hidden   = not locked
            disabled = not ready or not .canMount()

        case VaultCommands.Unmount:
            name     = texts.ui_Unmount
            icon     = .Remove
            hidden   = drive == null
            disabled = not ready

        case VaultCommands.ForceUnmount:
            name     = texts.cmd_ForceUnmount
            icon     = .Remove
            hidden   = drive == null
            disabled = not ready

        case VaultCommands.OpenDrive:
            icon   = .OpenExternal
            hidden = drive == null
            if drive do
                name = Format.toString(texts.ui_OpenDrive, drive.mountLabel)

        case VaultCommands.ReadOnly:
            name    = texts.ui_ReadOnly
            icon    = .Lock
            hidden  = not locked
            toggle  = true
            checked = .readOnly.isChecked()

        case VaultCommands.ProtectHidden:
            name     = texts.ui_ProtectHidden
            icon     = .Eye
            hidden   = not locked
            disabled = .readOnly.isChecked()
            toggle   = true
            checked  = .protectHiddenOnMount

        case VaultCommands.AtStartup:
            name   = texts.ui_MountAtStartup
            icon   = .Update
            hidden = drive == null or .privacyMode
            toggle = true
            if drive do
                checked = drive.atStartup

        case VaultCommands.ChangePassword:
            name     = texts.ui_ChangePassword
            icon     = .Lock
            hidden   = not locked
            disabled = not ready

        case VaultCommands.ChangeKeyFiles:
            name     = texts.ui_ChangeKeyFiles
            icon     = .File
            hidden   = not locked
            disabled = not ready

        case VaultCommands.Resize:
            name     = texts.ui_Resize
            icon     = .FitWidth
            hidden   = not locked
            disabled = not ready

        case VaultCommands.CreateHidden:
            name     = texts.ui_CreateHidden
            icon     = .Plus
            hidden   = not locked
            disabled = not ready

        case VaultCommands.Forget:
            name     = texts.ui_Forget
            icon     = .Remove
            hidden   = not locked or .privacyMode
            disabled = not ready

        case VaultCommands.Stop:
            name     = .operation.kind == .Resize ? texts.ui_StopResizing : texts.ui_StopCreating
            icon     = .Stop
            hidden   = not stopping
            disabled = .operation.progress.isCanceled()

        case VaultCommands.PrivacyMode:
            name    = texts.ui_PrivacyMode
            icon    = .Lock
            toggle  = true
            checked = .privacyMode

        case VaultCommands.UnmountOnLock:
            name    = texts.ui_UnmountOnLock
            icon    = .Lock
            toggle  = true
            checked = .autoUnmount.onSessionLock

        case VaultCommands.UnmountOnSuspend:
            name    = texts.ui_UnmountOnSuspend
            icon    = .Pause
            toggle  = true
            checked = .autoUnmount.onSuspend

        case VaultCommands.UnmountOnIdle:
            name    = texts.ui_UnmountOnIdle
            icon    = .HourGlass
            toggle  = true
            checked = .autoUnmount.onIdle

        default:
            return false
        }

        evt.name = name
        evt.updatedFields.add(.Name)
        evt.icon = .theme().icon(icon, .themeMetrics().menuPopup_IconSize)
        evt.updatedFields.add(.Icon)

        if hidden
        {
            evt.hidden = true
            evt.updatedFields.add(.Hidden)
        }

        if disabled
        {
            evt.disabled = true
            evt.updatedFields.add(.Disabled)
        }

        if toggle
        {
            evt.checked = checked
            evt.updatedFields.add(.Checked)
        }

        evt.accepted = true
        return true
    }

    // Runs one command of the window, and reports whether it was one.
    mtd runCommand(id: WndId)->bool
    {
        switch id
        {
        case VaultCommands.ShowWindow:       .resident.showWindow()
        case VaultCommands.UnmountAll:       .resident.unmountAll(quit: false)
        case VaultCommands.Quit:             .resident.unmountAll(quit: true)
        case VaultCommands.ForceUnmount:     .forceUnmountVault(String.from(.chosenPath))
        case VaultCommands.Resident:         .resident.setEnabled(not .resident.settings.enabled)
        case VaultCommands.SessionStartup:   .resident.setSessionStartup(not .resident.settings.startWithSession)
        case VaultCommands.Lens:             .lens.open()
        case VaultCommands.NewVault:         .showPage(.Create)
        case VaultCommands.OpenFile:         .openVaultFile()
        case VaultCommands.Vaults:           .goBack()
        case VaultCommands.Options:          .showPage(.Options)
        case VaultCommands.InstallWinFsp:    .startDriverInstall()
        case VaultCommands.Mount:            .mountContainer()
        case VaultCommands.Unmount:          .unmountVault(String.from(.chosenPath))
        case VaultCommands.OpenDrive:        .openDrive(String.from(.chosenPath))
        case VaultCommands.ReadOnly:         .toggleReadOnly()
        case VaultCommands.ProtectHidden:    .toggleProtectHidden()
        case VaultCommands.AtStartup:        .toggleStartup(String.from(.chosenPath))
        case VaultCommands.ChangePassword:   .changeVaultPassword()
        case VaultCommands.ChangeKeyFiles:   .changeVaultKeyFiles()
        case VaultCommands.Resize:           .resizeVault()
        case VaultCommands.CreateHidden:     .createHiddenContainer()
        case VaultCommands.Forget:           .forgetVault(String.from(.chosenPath))
        case VaultCommands.Stop:             .stopLongOperation()
        case VaultCommands.PrivacyMode:      .privacyModeControl.toggle()
        case VaultCommands.UnmountOnLock:    .unmountOnLock.toggle()
        case VaultCommands.UnmountOnSuspend: .unmountOnSuspend.toggle()
        case VaultCommands.UnmountOnIdle:    .unmountOnIdle.toggle()
        default: return false
        }

        return true
    }

    // Folds the unfolded vault, or leads back to the list from another page. A running creation
    // keeps its page: the way off it is to stop it.
    mtd goBack()
    {
        switch .page
        {
        case .List:     .foldVault()
        case .Progress: break
        default:        .showPage(.List)
        }
    }

    // Puts the container at `path` on the list and unfolds it, ready for its access.
    mtd openVault(path: string)
    {
        .addVault(path)
        .chooseVault(path)
    }

    // Lets the reader pick a container to mount or unlock.
    mtd openVaultFile()
    {
        if .operation.kind != .None do
            return

        // Privacy controls persistence, not the convenience of returning to the last folder
        // during this run. Serialization remains the only path from this state to disk.
        with var options: FileDlgOptions
        {
            .state = &me.fileDlgState
            .mode  = .SelectFile
            .title = appStrings().dlg_TitleOpen
            .confirmButtonText = appStrings().dlg_BtnOpen
            .shortcuts.add({type: Env.SpecialDirectory.Desktop, name: appStrings().ui_Desktop})
            .shortcuts.add({type: Env.SpecialDirectory.UserDocuments, name: "Documents"})
        }

        let dialog = FileDlg.create(unwrap .surface, options)
        if dialog.doModal() == Dialog.BtnOk do
            .queueAutomaticMount(dialog.selectedPath())
    }

    // Opens the drive of the mounted vault at `path` in the file explorer.
    mtd openDrive(path: string)
    {
        let drive = .mountedDrives.find(path)
        if not drive do
            return

        // A letter names a drive, not its root folder: the shell opens the folder it is given.
        var target = String.from(drive.mountLabel)
        if Utf8.endsWith(target.toSlice(), ":") do
            target += "\\"
        Env.openFile(target)
    }

    // Turns read-only mounting of the unfolded vault on or off, as its check box does.
    mtd toggleReadOnly()
    {
        if .chosenLockedPath().count == 0 do
            return
        .readOnly.toggle()
    }

    // Asks the next mount of the unfolded vault to protect its hidden volume, or not.
    //
    // A drive opened for reading alone writes nothing over a hidden volume, so it needs no
    // protection and the choice waits until read only is off.
    mtd toggleProtectHidden()
    {
        if .chosenLockedPath().count == 0 or .readOnly.isChecked() do
            return
        .protectHiddenOnMount = not .protectHiddenOnMount
        .refreshVaults()
    }

    // Takes the vault at `path` off the list, and out of the vaults mounted at startup with it.
    mtd forgetVault(path: string)
    {
        if .operation.kind != .None or .isMounted(path) do
            return

        let known = .startupIndex(path)
        if known != Swag.U64.Max do
            .startupVaults.removeAtOrdered(known)
        for &one, index in .vaults where one.path == path
        {
            .vaults.removeAtOrdered(index)
            break
        }

        if .chosenPath == path
        {
            .forgetAccess()
            .chosenPath.clear()
        }

        .refreshVaults()
        catch g_App.saveState()
    }

    // Lets the reader state the key files of an access in a box of their own, starting from
    // `paths`, and writes the choice back there. Returns whether the box was confirmed.
    mtd chooseKeyFiles(paths: *Array'String, canGenerate: bool)->bool
    {
        with var options: FormDlgOptions
        {
            .title = appStrings().dlg_TitleAccessKeyFiles
            .confirmButtonText = appStrings().dlg_BtnApply
        }

        let dialog = FormDlg.create(unwrap .surface, options)
        let field  = buildKeyFileChangeForm(dialog, paths.toSlice(), canGenerate)
        if dialog.doModal() != Dialog.BtnOk do
            return false
        field.copyPaths(paths)
        return true
    }

    // Opens the key-file list on the unfolded vault's mount card.
    mtd chooseUnlockKeyFiles()
    {
        .list.card.toggleKeyFiles()
    }

    // States the key files the new vault will need besides its password.
    mtd chooseCreateKeyFiles()
    {
        if .chooseKeyFiles(&.createKeyFiles, canGenerate: true) do
            .createPage.setKeyFileCount(.createKeyFiles.count)
    }
}
