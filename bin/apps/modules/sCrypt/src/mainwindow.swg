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

// Emphasis of the status line, from what the latest step left behind.
internal enum StatusTone
{
    Idle        // Nothing is running and nothing has failed.
    Active      // Work is running, or a drive is mounted.
    Stopped     // The latest operation stopped.
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

    // The single status line displayed above the footer, and the glyph whose color reports its
    // tone. Both are written only through `setStatus`.
    #[Swag.Late]
    {
        status:     *Label
        statusIcon: *Label
    }

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
    let window = cast(*MainWindow) data!
    window.runOperation()
}

// Sets a control in the fixed-width theme family.
//
// A path, a capacity, a unit, and a drive letter are read by the system, not by a reader, so
// they are set like the compiler sets a name it knows and never look like prose.
internal func setMachineFont(wnd: *Wnd)
{
    let theme = wnd.theme()
    wnd.style.setFont(theme.createDefaultFontFS(theme.metrics.defaultFixedFontSize), .Regular)
}

impl MainWindow
{
    func create(parent: *Wnd)->*MainWindow
    {
        let result  = Wnd.create'MainWindow(parent, "sCrypt.mainWindow")
        let surface = result.surface!
        surface.setView(result)
        surface.minSize        = {1100, 790}
        result.backgroundStyle = .View

        // One accent rule across the top identifies every standard Swag application surface.
        Separator.create(result, .Top, .Accent)

        result.createHeader()
        result.createFooter()

        // Two equal columns: create on the left, mount on the right.
        let cards = GridLayoutCtrl.create(result, 2, 1)
        with cards
        {
            .dockStyle         = .Center
            .margin            = {32, 16, 32, 16}
            .horizontalSpacing = 24
            .setColumnTrack(0, .Fraction, 1)
            .setColumnTrack(1, .Fraction, 1)
            .setRowTrack(0, .Fraction, 1)
            .setCell(result.createNewVaultCard(cards), 0, 0)
            .setCell(result.createMountVaultCard(cards), 1, 0)
        }

        result.applyLayout()
        cards.computeLayout()
        result.setState(.Ready)
        result.setStatus(.Idle, "Ready — create a vault or choose one to mount.")
        return result
    }

    mtd createHeader()
    {
        let header = Wnd.create'Wnd(me, {0, 0, 0, 72})
        header.dockStyle = .Top
        header.margin    = {32, 20, 32, 0}

        // The badge shares the line of the product name rather than floating between the name
        // and its explanation, so the header reads as two rows instead of three.
        let titleRow = Wnd.create'Wnd(header, {0, 0, 0, 44})
        titleRow.dockStyle = .Top

        // The badge is a compact claim about the product, so it is set fixed-width and sized
        // from its own text: a hand-tuned width clips it as soon as the theme font changes.
        const BadgeText = "PORTABLE  |  PASSWORD-LOCKED  |  NO SETUP"
        let badgeFont = .theme().createDefaultFontFS(12, .Bold)
        let badge     = Label.create(titleRow, BadgeText, {0, 0, Painter.measureString(BadgeText, badgeFont).width}, null, .SecondaryText)
        badge.dockStyle = .Right
        badge.setTextAlignment(.Right, .Center)
        badge.style.setFont(badgeFont, .Regular)

        let title = Label.create(titleRow, "sCrypt")
        title.dockStyle = .Center
        title.setTextAlignment(.Left, .Center)
        title.style.setFont(.theme().createDefaultFont(34, .Bold), .Regular)

        let subtitle = Label.create(header, "Encrypted storage that looks and behaves like a regular Windows drive.")
        subtitle.dockStyle = .Center
        subtitle.setTextAlignment(.Left, .Top)
        subtitle.updateFlags(add: .SecondaryText)
        header.applyLayout()
    }

    mtd createFooter()
    {
        let footer = Label.create(me, "WinFsp — Windows File System Proxy, Copyright (C) Bill Zissimopoulos — github.com/winfsp/winfsp", {0, 0, 0, 22}, null, .SecondaryText)
        footer.dockStyle = .Bottom
        footer.margin    = {32, 0, 32, 12}
        footer.setTextAlignment(.Left, .Center)

        // The status line is raised off the ground by its own fill. A border around it would
        // draw a third box on a surface that already reads without one.
        let statusView = Wnd.create'Wnd(me, {0, 0, 0, 52})
        statusView.dockStyle       = .Bottom
        statusView.margin          = {32, 0, 32, 12}
        statusView.backgroundStyle = .Window
        statusView.padding         = {20, 8, 20, 8}

        .statusIcon           = Label.create(statusView, "", {0, 0, 24})
        .statusIcon.dockStyle = .Left
        .statusIcon.margin.z  = 12

        .status           = Label.create(statusView, "")
        .status.dockStyle = .Center
        .status.setTextAlignment(.Left, .Center)
        statusView.applyLayout()
    }

    // Reports the outcome of the latest step on the single status line.
    //
    // One glyph, three colors: the theme atlas has no monochrome success or failure glyph, and
    // borrowing a colored one would put a third hue on a two-color surface. The color alone
    // separates a line that is waiting from one that reports work, or one that stopped.
    mtd setStatus(tone: StatusTone, text: string)
    {
        let colors = .themeColors()

        var glyphColor, textColor: Color = undefined
        switch #complete tone
        {
        case .Idle:
            glyphColor = colors.label_TextLight
            textColor  = colors.label_TextLight

        case .Active:
            glyphColor = colors.hilight
            textColor  = colors.label_Text

        case .Stopped:
            glyphColor = colors.error
            textColor  = colors.error
        }

        var glyph = .theme().icon(ThemeIcons.About, 20)
        glyph.color = glyphColor
        .statusIcon.setIcon(glyph)
        .status.setTextColor(textColor)
        .status.setText(text)
    }

    mtd createNewVaultCard(parent: *GridLayoutCtrl)->*Wnd
    {
        let card = VaultCard.create(parent, "Create a new vault", "Choose a fixed capacity. The complete container is randomized before it is ready.")
        let form = card.form
        .createForm = form

        .createPath = form.addTextField("CONTAINER FILE", placeholder: "C:\\path\\private.scrypt", icon: .theme().icon(ThemeIcons.OpenFile, 17))
        setMachineFont(.createPath)
        let browse = form.addRowAction("Browse", .theme().icon(ThemeIcons.OpenFile, 16))
        browse.sigPressed += func|window = me|(btn)
        {
            discard btn
            window.chooseContainer(window.createPath, true)
        }

        .createSize = form.addTextField("FIXED CAPACITY", "256")
        .createSize.setUnsignedIntegerRange(1, 1024 * 1024)
        setMachineFont(.createSize)

        // The multiplier read by `containerSize` follows this order.
        .createUnit = form.addRowChoice()
        .createUnit.addItem("MiB")
        .createUnit.addItem("GiB")
        .createUnit.setSelectedIndex(0, notify: false)
        setMachineFont(.createUnit)

        .createPassword  = form.addPasswordField("PASSWORD", placeholder: "Required password")
        .confirmPassword = form.addPasswordField("CONFIRM PASSWORD", placeholder: "Enter the password again")

        .createButton = PushButton.create(card.actions, "Create encrypted vault", {0, 0, 224, 36}, form: .Strong)
        .createButton.setIcon(.theme().icon(ThemeIcons.SaveAs, 18))
        .createButton.sigPressed += func|window = me|(btn)
        {
            discard btn
            window.createContainer()
        }

        card.actions.computeLayout()
        card.endForm()
        return card.panel
    }

    mtd createMountVaultCard(parent: *GridLayoutCtrl)->*Wnd
    {
        let card = VaultCard.create(parent, "Mount an existing vault", "Unlock a container and expose it on any currently available drive letter.")
        let form = card.form
        .mountForm = form

        .mountPath = form.addTextField("CONTAINER FILE", placeholder: "Existing encrypted container", icon: .theme().icon(ThemeIcons.OpenFile, 17))
        setMachineFont(.mountPath)
        let browse = form.addRowAction("Browse", .theme().icon(ThemeIcons.OpenFile, 16))
        browse.sigPressed += func|window = me|(btn)
        {
            discard btn
            window.chooseContainer(window.mountPath, false)
        }

        .mountPassword = form.addPasswordField("PASSWORD", placeholder: "Container password")

        // The lifetime of the drive belongs to the letter that carries it, so it is said under
        // that field rather than as a loose paragraph at the bottom of the card.
        .drive = form.addChoiceField("DRIVE LETTER", help: "The drive is available to Windows while sCrypt runs, then disappears when the app closes.")
        setMachineFont(.drive)

        // Windows keeps A and B for floppies and C for the system disk, so the letters a
        // user expects come first and the unusual ones stay available further down.
        let available = File.availableDriveLetters()
        for letter in available where letter >= 'D' do
            .drive.addItem(Format.toString("%:", letter))
        for letter in available where letter < 'D' do
            .drive.addItem(Format.toString("%:", letter))
        if .drive.items.count do
            .drive.setSelectedIndex(0, notify: false)

        .unmountButton = PushButton.create(card.actions, "Unmount", {0, 0, 136, 36})
        .unmountButton.setIcon(.theme().icon(ThemeIcons.Stop, 18))
        .unmountButton.sigPressed += func|window = me|(btn)
        {
            discard btn
            window.unmountContainer()
        }

        .mountButton = PushButton.create(card.actions, "Mount drive", {0, 0, 136, 36}, form: .Strong)
        .mountButton.setIcon(.theme().icon(ThemeIcons.Play, 18))
        .mountButton.sigPressed += func|window = me|(btn)
        {
            discard btn
            window.mountContainer()
        }

        card.actions.computeLayout()
        card.endForm()
        return card.panel
    }

    mtd showError(message: string, err: #null any = null)
    {
        var detail = String.from(message)
        if err != null do
            detail = Format.toString("%\n\n%", message, caughtMessage(err))
        MessageDlg.error(.surface!, detail)
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

        let dialog = FileDlg.create(.surface!, options)
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
        return item ? String.from(item!.name.raw) : String.from("")
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
        .setStatus(.Active, "Creating and randomizing the container...")
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
        .setStatus(.Active, "Starting the portable filesystem driver...")
        .setState(.Mounting)
        .beginOperation(.Mount)
    }

    mtd unmountContainer()
    {
        if .state != .Mounted do
            return
        .setStatus(.Active, "Synchronizing and unmounting the encrypted drive...")
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
            .removeTimer(.operation.timer!)
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
                .setStatus(.Stopped, "Container creation stopped.")
            }
            else
            {
                .setStatus(.Idle, "Container created. It is ready to mount.")
                .mountPath.setText(.operation.path)
            }

            .setState(.Ready)

        case .Mount:
            if .operation.error != null
            {
                .showError("Could not mount the virtual disk.", .operation.error)
                .setStatus(.Stopped, "Mount stopped.")
                .setState(.Ready)
            }
            else
            {
                .setStatus(.Active, Format.toString("Encrypted drive mounted on %. It will unmount when sCrypt closes.", .operation.mount))
                .setState(.Mounted)
            }

        case .Unmount:
            if .operation.error != null do
                .showError("The drive was unmounted, but final synchronization stopped.", .operation.error)
            .setStatus(.Idle, "Drive unmounted safely.")
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
            .removeTimer(.operation.timer!)
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

    mtd impl onStateEvent(evt: *StateEvent)
    {
        if evt.kind == .Init
        {
            // Runs before the surface is first displayed: restore the persisted window
            // placement and dialog state, then keep the window on a visible screen area.
            catch g_App.loadState()
            .surface?.constrainPositionToScreen(topLeft: true, margin: 10)
            evt.accepted = true
        }
    }

    mtd impl onSerializeStateEvent(evt: *SerializeStateEvent)
    {
        // The browse dialogs share this state, so they reopen on the folder that held
        // the last accepted container, with its recent locations.
        catch evt.serializer.serialize("MainWindow.fileDlgState", &me.fileDlgState)
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        catch g_App.saveState()
        .shutdown()
        .wnd.IWnd.onDestroyEvent(evt)
    }
}
