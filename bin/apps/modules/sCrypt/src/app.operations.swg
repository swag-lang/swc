using Core, Gui

internal impl MainWindow
{
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
