using Core, Gui, Pixel

internal enum AppState
{
    Ready
    Creating
    Mounting
    Mounted
    Unmounting
}

internal enum OperationKind
{
    None
    Create
    Mount
    Unmount
}

// Long operation running outside the UI thread. Only one runs at a time, and the window
// polls `job` with `timer` until the result is ready to be reported.
struct VaultOperation
{
    job:      Jobs.Job          // Worker scheduled for `kind`.
    kind:     OperationKind     // Work the job performs, or `None` while the window is idle.
    timer:    #null *Timer      // Polls the job while it runs.
    error:    #null any         // Failure captured by the job, or null when it succeeded.
    path:     String            // Container file the operation acts on.
    mount:    String            // Drive letter requested by a mount operation.
    size:     u64               // Container size requested by a create operation.
    password: Array'u8          // Password copy owned by the operation and wiped when it ends.
}

// Owns the complete application state. The UI thread owns this object; long
// operations use `operation` and report their result back through the timer.
struct MainWindow
{
    using wnd: Wnd

    // Controls of the "create a new vault" card.
    #[Swag.Late]
    {
        createForm:      *FormLayoutCtrl
        createPath:      *EditBox
        createSize:      *EditBox
        createUnit:      *ComboBox
        createPassword:  *PasswordEdit
        confirmPassword: *PasswordEdit
        createButton:    *PushButton
    }

    // Controls of the "mount an existing vault" card.
    #[Swag.Late]
    {
        mountForm:     *FormLayoutCtrl
        mountPath:     *EditBox
        mountPassword: *PasswordEdit
        drive:         *ComboBox
        mountButton:   *PushButton
        unmountButton: *PushButton
    }

    #[Swag.Late]
    status: *Label     // Single status line displayed above the footer.

    fileDlgState: FileDlgState
    mounted:      WinFsp.MountedVolume
    state:        AppState
    shuttingDown: bool
    operation:    VaultOperation
}

internal func caughtMessage(err: #null any)->string
{
    switch err
    {
    case Error:            return (cast(Error) err).message orelse "sCrypt error."
    case Swag.SystemError: return (cast(Swag.SystemError) err).message orelse "System error."
    }

    return "The operation stopped."
}

internal func runMainWindowOperation(data: #null *void)
{
    let window = cast(*MainWindow) (notnull data)
    window.runOperation()
}

impl MainWindow
{
    func create(parent: *Wnd)->*MainWindow
    {
        let result  = Wnd.create'MainWindow(parent, "sCrypt.mainWindow")
        let surface = notnull result.surface
        surface.setView(result)
        surface.minSize        = {1100, 790}
        result.backgroundStyle = .View

        result.createHeader()
        result.createFooter()

        // Two equal columns: create on the left, mount on the right.
        let cards = GridLayoutCtrl.create(result, 2, 1)
        with cards
        {
            .dockStyle         = .Center
            .margin            = {30, 0, 30, 14}
            .horizontalSpacing = 30
            .setColumnTrack(0, .Fraction, 1)
            .setColumnTrack(1, .Fraction, 1)
            .setRowTrack(0, .Fraction, 1)
            .setCell(result.createNewVaultCard(cards), 0, 0)
            .setCell(result.createMountVaultCard(cards), 1, 0)
        }

        result.applyLayout()
        cards.computeLayout()
        result.setState(.Ready)
        return result
    }

    mtd createHeader()
    {
        let header = Wnd.create'Wnd(me, {0, 0, 0, 104})
        header.dockStyle = .Top
        header.margin    = {30, 18, 30, 0}

        // `.` already means `me` in this method, so the rail is configured
        // through its own name rather than through a `with` block.
        let brandRail = Wnd.create'Wnd(header, {0, 0, 4})
        brandRail.dockStyle       = .Left
        brandRail.margin.z        = 12
        brandRail.backgroundStyle = .Window
        brandRail.style.addStyleSheetColors("wnd_Bk $hilight")

        let badge = Label.create(header, "PORTABLE  |  PASSWORD-LOCKED  |  NO SETUP", {0, 0, 330}, null, .SecondaryText)
        badge.dockStyle = .Right
        badge.setTextAlignment(.Right, .Center)
        badge.style.setFont(.theme().createDefaultFontFS(12, .Bold), .Regular)

        let title = Label.create(header, "sCrypt", {0, 0, 0, 48})
        title.dockStyle = .Top
        title.setTextAlignment(.Left, .Center)
        title.style.setFont(.theme().createDefaultFont(36, .Bold), .Regular)

        let subtitle = Label.create(header, "Encrypted storage that looks and behaves like a regular Windows drive.")
        subtitle.dockStyle = .Center
        subtitle.setTextAlignment(.Left, .Top)
        subtitle.updateFlags(add: .SecondaryText)
        header.applyLayout()
    }

    mtd createFooter()
    {
        let footer = Label.create(me, "WinFsp - Windows File System Proxy, Copyright (C) Bill Zissimopoulos - github.com/winfsp/winfsp", {0, 0, 0, 24}, null, .SecondaryText)
        footer.dockStyle = .Bottom
        footer.margin    = {34, 4, 34, 12}
        footer.setTextAlignment(.Left, .Center)

        let statusFrame = Wnd.create'FrameWnd(me, {0, 0, 0, 64})
        statusFrame.dockStyle = .Bottom
        statusFrame.margin    = {30, 0, 30, 10}
        statusFrame.setFrameForm(.Square)
        statusFrame.setFrameFlags(.Borders)

        let statusView = statusFrame.createView'Wnd()
        statusView.padding = {14, 8, 14, 8}
        let statusIcon = Label.create(statusView, "", {0, 0, 30})
        statusIcon.dockStyle = .Left
        statusIcon.margin.z  = 8
        var statusGlyph = .theme().icon24(ThemeIcons24.About, 22)
        statusGlyph.color = .themeColors().label_TextLight
        statusIcon.setIcon(statusGlyph)

        .status           = Label.create(statusView, "Ready - create a vault or choose one to mount.")
        .status.dockStyle = .Center
        .status.setTextAlignment(.Left, .Center)
        statusView.applyLayout()
    }

    mtd createNewVaultCard(parent: *GridLayoutCtrl)->*FrameWnd
    {
        let card = VaultCard.create(parent, "Create a new vault", "Choose a fixed capacity. The complete container is randomized before it is ready.")
        let form = card.form
        .createForm = form

        .createPath = form.addTextField("CONTAINER FILE", placeholder: "C:\\path\\private.scrypt", icon: .theme().icon24(ThemeIcons24.OpenFile, 17))
        let browse = form.addRowAction("Browse", .theme().icon24(ThemeIcons24.OpenFile, 16))
        browse.sigPressed += func|window = me|(btn)
        {
            discard btn
            window.chooseContainer(window.createPath, true)
        }

        .createSize = form.addTextField("FIXED CAPACITY", "256")
        .createSize.setUnsignedIntegerRange(1, 1024 * 1024)

        // The multiplier read by `containerSize` follows this order.
        .createUnit = form.addRowChoice()
        .createUnit.addItem("MiB")
        .createUnit.addItem("GiB")
        .createUnit.setSelectedIndex(0, notify: false)

        .createPassword  = form.addPasswordField("PASSWORD", placeholder: "Required password")
        .confirmPassword = form.addPasswordField("CONFIRM PASSWORD", placeholder: "Enter the password again")

        let actions = StackLayoutCtrl.create(card.body, .Right, {0, 0, 0, 38})
        actions.dockStyle = .Bottom
        .createButton     = PushButton.create(actions, "Create encrypted vault", {0, 0, 228, 38}, form: .Strong)
        .createButton.setIcon(.theme().icon24(ThemeIcons24.SaveAs, 18))
        .createButton.sigPressed += func|window = me|(btn)
        {
            discard btn
            window.createContainer()
        }

        actions.computeLayout()
        card.endForm()
        return card.frame
    }

    mtd createMountVaultCard(parent: *GridLayoutCtrl)->*FrameWnd
    {
        let card = VaultCard.create(parent, "Mount an existing vault", "Unlock a container and expose it on any currently available drive letter.")
        let form = card.form
        .mountForm = form

        .mountPath = form.addTextField("CONTAINER FILE", placeholder: "Existing encrypted container", icon: .theme().icon24(ThemeIcons24.OpenFile, 17))
        let browse = form.addRowAction("Browse", .theme().icon24(ThemeIcons24.OpenFile, 16))
        browse.sigPressed += func|window = me|(btn)
        {
            discard btn
            window.chooseContainer(window.mountPath, false)
        }

        .mountPassword = form.addPasswordField("PASSWORD", placeholder: "Container password")
        .drive         = form.addChoiceField("DRIVE LETTER")

        // Windows keeps A and B for floppies and C for the system disk, so the letters a
        // user expects come first and the unusual ones stay available further down.
        let available = File.availableDriveLetters()
        for letter in available where letter >= 'D' do
            .drive.addItem(Format.toString("%:", letter))
        for letter in available where letter < 'D' do
            .drive.addItem(Format.toString("%:", letter))
        if .drive.items.count do
            .drive.setSelectedIndex(0, notify: false)

        let note = Label.create(card.body, "The drive is available to Windows while sCrypt runs, then disappears when the app closes.", {0, 0, 0, 54}, null, .WordWrap | .SecondaryText)
        note.dockStyle = .Top
        note.setTextAlignment(.Left, .Top)

        let actions = StackLayoutCtrl.create(card.body, .Right, {0, 0, 0, 38})
        actions.dockStyle = .Bottom
        .unmountButton    = PushButton.create(actions, "Unmount", {0, 0, 140, 38})
        .unmountButton.setIcon(.theme().icon24(ThemeIcons24.Stop, 18))
        .unmountButton.sigPressed += func|window = me|(btn)
        {
            discard btn
            window.unmountContainer()
        }

        .mountButton = PushButton.create(actions, "Mount drive", {0, 0, 140, 38}, form: .Strong)
        .mountButton.setIcon(.theme().icon24(ThemeIcons24.Play, 18))
        .mountButton.sigPressed += func|window = me|(btn)
        {
            discard btn
            window.mountContainer()
        }

        actions.computeLayout()
        card.endForm()
        return card.frame
    }

    mtd showError(message: string, err: #null any = null)
    {
        var detail = String.from(message)
        if err != null do
            detail = Format.toString("%\n\n%", message, caughtMessage(err))
        MessageDlg.error(notnull .surface, detail)
    }

    mtd setState(state: AppState)
    {
        .state = state
        let ready   = state == .Ready
        let mounted = state == .Mounted

        // Disabling a form disables every field and trailing control it owns.
        .createForm.enable(ready)
        .createButton.enable(ready)
        .mountForm.enable(ready)
        .mountButton.enable(ready)
        .unmountButton.enable(mounted)
    }

    mtd chooseContainer(target: *EditBox, create: bool)
    {
        var options: FileDlgOptions
        options.state             = &.fileDlgState
        options.mode              = create ? .CreateFile : .SelectFile
        options.title             = create ? "Create an sCrypt container" : "Open an encrypted container"
        options.confirmButtonText = create ? "Create" : "Open"
        options.initialName       = create ? "volume.scrypt" : ""
        options.filters.add({"sCrypt encrypted container (*.scrypt)", ".scrypt"})
        options.shortcuts.add({Env.SpecialDirectory.Desktop, "Desktop"})
        options.shortcuts.add({Env.SpecialDirectory.UserDocuments, "Documents"})

        let dialog = FileDlg.create(notnull .surface, options)
        if dialog.doModal() == Dialog.BtnOk do
            target.setText(dialog.selectedPath())
    }

    mtd containerSize()->u64 fail
    {
        let text   = .createSize.text()
        let parsed = catch StrConv.parseU64(text) as parseError
        if parseError != null or parsed.ovf or parsed.eat != @countof(text) or !parsed.value do
            failWith("The container size is invalid.", .InvalidInput)

        let multiplier = .createUnit.selectedIndex == 0 ? 1024'u64 * 1024 : 1024'u64 * 1024 * 1024
        if parsed.value > Swag.U64.Max / multiplier do
            failWith("The container size is too large.", .InvalidInput)

        let result = parsed.value * multiplier
        if result < MinimumSize do
            failWith(Format.toString("The minimum container size is % MiB.", (MinimumSize + 1024 * 1024 - 1) / (1024 * 1024)), .InvalidInput)
        return result
    }

    mtd selectedMountPoint()->String
    {
        let item = .drive.selectedItem()
        return item ? String.from((notnull item).name.raw) : String.from("")
    }

    mtd beginOperation(kind: OperationKind)
    {
        Debug.assert(.operation.kind == .None)
        .operation.kind       = kind
        .operation.error      = null
        .operation.job.lambda = &runMainWindowOperation
        .operation.job.data   = me
        .operation.timer      = .app().addTimer(50'ms, me)
        Jobs.schedule(&.operation.job)
    }

    mtd createContainer()
    {
        let path = .createPath.text()
        if !@countof(path)
        {
            .showError("Choose the container file to create.")
            return
        }

        if File.exists(path)
        {
            .showError("This file already exists. Choose a new name to avoid data loss.")
            return
        }

        if .createPassword.isEmpty()
        {
            .showError("A password is required.")
            return
        }

        if !Core.Crypto.constantTimeEqual(.createPassword.bytes(), .confirmPassword.bytes())
        {
            .showError("The passwords do not match.")
            return
        }

        let size = catch .containerSize() as sizeError
        if sizeError != null
        {
            .showError("Could not create the container.", sizeError)
            return
        }

        .operation.path = path
        .operation.size = size
        .operation.password.add(.createPassword.bytes())
        .createPassword.clear()
        .confirmPassword.clear()
        .status.setText("Creating and randomizing the container...")
        .setState(.Creating)
        .beginOperation(.Create)
    }

    mtd mountContainer()
    {
        let path = .mountPath.text()
        if !@countof(path)
        {
            .showError("Choose an existing container.")
            return
        }

        if .mountPassword.isEmpty()
        {
            .showError("A password is required.")
            return
        }

        let mountPoint = .selectedMountPoint()
        if mountPoint.isEmpty()
        {
            .showError("No drive letter is available.")
            return
        }

        .operation.path  = path
        .operation.mount = mountPoint
        .operation.password.add(.mountPassword.bytes())
        .mountPassword.clear()
        .status.setText("Starting the portable filesystem driver...")
        .setState(.Mounting)
        .beginOperation(.Mount)
    }

    mtd unmountContainer()
    {
        if .state != .Mounted do
            return
        .status.setText("Synchronizing and unmounting the encrypted drive...")
        .setState(.Unmounting)
        .beginOperation(.Unmount)
    }

    mtd runOperation()
    {
        switch #complete .operation.kind
        {
        case .None:
            return

        case .Create:
            var volume = catch Volume.create(.operation.path.toString(), .operation.password.toSlice(), .operation.size) as createError
            .operation.error = createError
            if createError == null do
                volume.close()

        case .Mount:
            discard catch .mounted.open(.operation.path.toString(), .operation.password.toSlice(), .operation.mount.toString()) as mountError
            .operation.error = mountError

        case .Unmount:
            discard catch .mounted.close() as unmountError
            .operation.error = unmountError
        }

        Core.Crypto.secureClear(.operation.password.toSlice())
        .operation.password.clear()
    }

    mtd finishOperation()
    {
        Jobs.wait(&.operation.job)
        if .operation.timer
        {
            .removeTimer(notnull .operation.timer)
            .operation.timer = null
        }

        switch #complete .operation.kind
        {
        case .None:
            return

        case .Create:
            if .operation.error != null
            {
                .showError("Could not create the container.", .operation.error)
                .status.setText("Container creation stopped.")
            }
            else
            {
                .status.setText("Container created. It is ready to mount.")
                .mountPath.setText(.operation.path)
            }

            .setState(.Ready)

        case .Mount:
            if .operation.error != null
            {
                .showError("Could not mount the virtual disk.", .operation.error)
                .status.setText("Mount stopped.")
                .setState(.Ready)
            }
            else
            {
                .status.setText(Format.toString("Encrypted drive mounted on %. It will unmount when sCrypt closes.", .operation.mount))
                .setState(.Mounted)
            }

        case .Unmount:
            if .operation.error != null do
                .showError("The drive was unmounted, but final synchronization stopped.", .operation.error)
            .status.setText("Drive unmounted safely.")
            .setState(.Ready)
        }

        .operation.kind  = .None
        .operation.error = null
        .operation.path.clear()
        .operation.mount.clear()
        .operation.size = 0
    }

    // Releases the pending operation and the mounted volume. Safe to call more than once.
    mtd shutdown()
    {
        if .shuttingDown do
            return
        .shuttingDown = true

        if .operation.timer
        {
            .removeTimer(notnull .operation.timer)
            .operation.timer = null
        }

        if .operation.kind != .None
        {
            Jobs.wait(&.operation.job)
            .operation.kind = .None
        }

        discard catch .mounted.close()
        Core.Crypto.secureClear(.operation.password.toSlice())
        .operation.password.clear()
        .createPassword.clear()
        .confirmPassword.clear()
        .mountPassword.clear()
        .operation.error = null
    }
}

impl IWnd for MainWindow
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .operation.timer and Jobs.isDone(&.operation.job) do
            .finishOperation()
        .wnd.IWnd.onTimerEvent(evt)
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .shutdown()
        .wnd.IWnd.onDestroyEvent(evt)
    }
}
