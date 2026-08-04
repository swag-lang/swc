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

// Owns the complete application state. The UI thread owns this object; long
// operations use `operation` and report their result back through the timer.
struct MainWindow
{
    using wnd: Wnd

    #[Swag.Late]
    {
        createPath:      *EditBox
        createSize:      *EditBox
        createUnit:      *ComboBox
        createPassword:  *PasswordEdit
        confirmPassword: *PasswordEdit
        createButton:    *PushButton
        mountPath:       *EditBox
        drive:           *ComboBox
        mountPassword:   *PasswordEdit
        mountButton:     *PushButton
        unmountButton:   *PushButton
        status:          *Label
    }

    fileDlgState: FileDlgState
    mounted:      WinFsp.MountedVolume
    state:        AppState
    shuttingDown: bool

    operation:         Jobs.Job
    operationKind:     OperationKind
    operationTimer:    #null *Timer
    operationError:    #null any
    operationPath:     String
    operationMount:    String
    operationSize:     u64
    operationPassword: Array'u8
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

private func createVaultFields()->Array'FormFieldDefinition
{
    var result: retval
    result.add({id: "create.path", label: "CONTAINER FILE", placeholder: "C:\\path\\private.scrypt", actionText: "Browse"})

    with var capacity: FormFieldDefinition
    {
        .id          = "create.size"
        .label       = "FIXED CAPACITY"
        .initialText = "256"
        .choices.add({"MiB", "mib"})
        .choices.add({"GiB", "gib"})
    }

    result.add(#move capacity)

    result.add({id: "create.password", label: "PASSWORD", kind: FormFieldKind.Password, placeholder: "Required password"})
    result.add({id: "create.confirm", label: "CONFIRM PASSWORD", kind: FormFieldKind.Password, placeholder: "Enter the password again"})
    return result
}

private func mountVaultFields()->Array'FormFieldDefinition
{
    var result: retval
    result.add({id: "mount.path", label: "CONTAINER FILE", placeholder: "Existing encrypted container", actionText: "Browse"})
    result.add({id: "mount.password", label: "PASSWORD", kind: FormFieldKind.Password, placeholder: "Container password"})

    // Windows keeps A and B for floppies and C for the system disk, so the
    // letters a user expects come first and the unusual ones stay available
    // further down the list.
    let available = File.availableDriveLetters()
    with var drive: FormFieldDefinition
    {
        .id    = "mount.drive"
        .label = "DRIVE LETTER"
        .kind  = .Choice
        for letter in available where letter >= 'D' do
            .choices.add({Format.toString("%:", letter)})
        for letter in available where letter < 'D' do
            .choices.add({Format.toString("%:", letter)})
    }

    result.add(#move drive)
    return result
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
            .setCell(result.createCreateCard(cards), 0, 0)
            .setCell(result.createMountCard(cards), 1, 0)
        }

        result.applyLayout()
        cards.computeLayout()
        result.setState(.Ready)
        return result
    }

    // Releases any pending operation and mounted volume before application exit.
    mtd shutdown()
    {
        .shutdownInternal()
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

    mtd createCreateCard(parent: *GridLayoutCtrl)->*FrameWnd
    {
        let card = VaultCard.create(parent, "Create a new vault", "Choose a fixed capacity. The complete container is randomized before it is ready.")

        var options: FormLayoutOptions
        options.labelPlacement = .Above
        options.rowSpacing     = 10
        let definitions = createVaultFields()
        let form        = FormCtrl.create(card.body, definitions.toSlice(), options, {0, 0, 0, 304})
        form.dockStyle = .Top

        .createPath      = notnull form.textField("create.path")
        .createSize      = notnull form.textField("create.size")
        .createUnit      = notnull (notnull form.findField("create.size")).accessoryChoice
        .createPassword  = notnull form.passwordField("create.password")
        .confirmPassword = notnull form.passwordField("create.confirm")
        .createPath.setIcon(.theme().icon24(ThemeIcons24.OpenFile, 17))
        let browse = notnull (notnull form.findField("create.path")).action
        browse.setIcon(.theme().icon24(ThemeIcons24.OpenFile, 16))
        let window = me
        form.sigAction += func|window|(form, id)
        {
            discard form
            if id == "create.path" do
                window.chooseContainer(window.createPath, true)
        }
        .createSize.setUnsignedIntegerRange(1, 1024 * 1024)

        let actions = StackLayoutCtrl.create(card.body, .Right, {0, 0, 0, 38})
        actions.dockStyle = .Bottom
        .createButton     = PushButton.create(actions, "Create encrypted vault", {0, 0, 228, 38}, form: .Strong)
        .createButton.setIcon(.theme().icon24(ThemeIcons24.SaveAs, 18))
        .createButton.sigPressed += func|window|(btn)
        {
            discard btn
            window.createContainer()
        }
        actions.computeLayout()
        card.body.applyLayout()
        return card.frame
    }

    mtd createMountCard(parent: *GridLayoutCtrl)->*FrameWnd
    {
        let card = VaultCard.create(parent, "Mount an existing vault", "Unlock a container and expose it on any currently available drive letter.")

        var options: FormLayoutOptions
        options.labelPlacement = .Above
        options.rowSpacing     = 10
        let definitions = mountVaultFields()
        let form        = FormCtrl.create(card.body, definitions.toSlice(), options, {0, 0, 0, 224})
        form.dockStyle = .Top

        .mountPath     = notnull form.textField("mount.path")
        .mountPassword = notnull form.passwordField("mount.password")
        .drive         = notnull form.choiceField("mount.drive")
        .mountPath.setIcon(.theme().icon24(ThemeIcons24.OpenFile, 17))
        let browse = notnull (notnull form.findField("mount.path")).action
        browse.setIcon(.theme().icon24(ThemeIcons24.OpenFile, 16))
        let window = me
        form.sigAction += func|window|(form, id)
        {
            discard form
            if id == "mount.path" do
                window.chooseContainer(window.mountPath, false)
        }

        let note = Label.create(card.body, "The drive is available to Windows while sCrypt runs, then disappears when the app closes.", {0, 0, 0, 54}, null, .WordWrap | .SecondaryText)
        note.dockStyle = .Top
        note.setTextAlignment(.Left, .Top)

        let actions = StackLayoutCtrl.create(card.body, .Right, {0, 0, 0, 38})
        actions.dockStyle = .Bottom
        .unmountButton    = PushButton.create(actions, "Unmount", {0, 0, 140, 38})
        .unmountButton.setIcon(.theme().icon24(ThemeIcons24.Stop, 18))
        .unmountButton.sigPressed += func|window|(btn)
        {
            discard btn
            window.unmountContainer()
        }
        .mountButton = PushButton.create(actions, "Mount drive", {0, 0, 140, 38}, form: .Strong)
        .mountButton.setIcon(.theme().icon24(ThemeIcons24.Play, 18))
        .mountButton.sigPressed += func|window|(btn)
        {
            discard btn
            window.mountContainer()
        }
        actions.computeLayout()
        card.body.applyLayout()
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

        .createPath.enable(ready)
        .createSize.enable(ready)
        .createUnit.enable(ready)
        .createPassword.enable(ready)
        .confirmPassword.enable(ready)
        .createButton.enable(ready)
        .mountPath.enable(ready)
        .drive.enable(ready)
        .mountPassword.enable(ready)
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
        Debug.assert(.operationKind == .None)
        .operationKind    = kind
        .operationError   = null
        .operation.lambda = &runMainWindowOperation
        .operation.data   = me
        .operationTimer   = .app().addTimer(50'ms, me)
        Jobs.schedule(&.operation)
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

        .operationPath = path
        .operationSize = size
        .operationPassword.add(.createPassword.bytes())
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

        .operationPath  = path
        .operationMount = mountPoint
        .operationPassword.add(.mountPassword.bytes())
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
        switch #complete .operationKind
        {
        case .None:
            return

        case .Create:
            var volume = catch Volume.create(.operationPath.toString(), .operationPassword.toSlice(), .operationSize) as createError
            .operationError = createError
            if createError == null do
                volume.close()

        case .Mount:
            discard catch .mounted.open(.operationPath.toString(), .operationPassword.toSlice(), .operationMount.toString()) as mountError
            .operationError = mountError

        case .Unmount:
            discard catch .mounted.close() as unmountError
            .operationError = unmountError
        }

        Core.Crypto.secureClear(.operationPassword.toSlice())
        .operationPassword.clear()
    }

    mtd finishOperation()
    {
        Jobs.wait(&.operation)
        if .operationTimer
        {
            .removeTimer(notnull .operationTimer)
            .operationTimer = null
        }

        switch #complete .operationKind
        {
        case .None:
            return

        case .Create:
            if .operationError != null
            {
                .showError("Could not create the container.", .operationError)
                .status.setText("Container creation stopped.")
            }
            else
            {
                .status.setText("Container created. It is ready to mount.")
                .mountPath.setText(.operationPath)
            }

            .setState(.Ready)

        case .Mount:
            if .operationError != null
            {
                .showError("Could not mount the virtual disk.", .operationError)
                .status.setText("Mount stopped.")
                .setState(.Ready)
            }
            else
            {
                .status.setText(Format.toString("Encrypted drive mounted on %. It will unmount when sCrypt closes.", .operationMount))
                .setState(.Mounted)
            }

        case .Unmount:
            if .operationError != null do
                .showError("The drive was unmounted, but final synchronization stopped.", .operationError)
            .status.setText("Drive unmounted safely.")
            .setState(.Ready)
        }

        .operationKind  = .None
        .operationError = null
        .operationPath.clear()
        .operationMount.clear()
        .operationSize = 0
    }

    mtd shutdownInternal()
    {
        if .shuttingDown do
            return
        .shuttingDown = true

        if .operationTimer
        {
            .removeTimer(notnull .operationTimer)
            .operationTimer = null
        }

        if .operationKind != .None
        {
            Jobs.wait(&.operation)
            .operationKind = .None
        }

        discard catch .mounted.close()
        Core.Crypto.secureClear(.operationPassword.toSlice())
        .operationPassword.clear()
        .createPassword.clear()
        .confirmPassword.clear()
        .mountPassword.clear()
        .operationError = null
    }
}

impl IWnd for MainWindow
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .operationTimer and Jobs.isDone(&.operation) do
            .finishOperation()
        .wnd.IWnd.onTimerEvent(evt)
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .shutdownInternal()
        .wnd.IWnd.onDestroyEvent(evt)
    }
}
