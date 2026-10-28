impl MainWindow
{
    // Starts `kind` on the worker and polls it until `finishOperation` takes the result.
    //
    // A creation and a resize write every byte of the container, so they get the page that follows
    // them; the other operations wait on the driver or on a key derivation, and the notice line
    // under the list's title says what they are doing.
    mtd beginOperation(kind: OperationKind)
    {
        Swag.assert(.operation.kind == .None)
        .operation.kind = kind
        .operation.error.reset()
        .operation.timer = .addTimer(50'ms)

        // Arming the tracker before the task starts is what clears the cancellation a previous
        // operation left behind.
        .operation.progress.begin(0)

        if kind == .Create or kind == .Resize
        {
            let texts = appStrings()
            var what, help: string
            switch
            {
            case kind == .Create:
                what = texts.ui_Randomizing
                help = texts.ui_RandomizeHelp

            case .operation.camouflageOnly:
                what = texts.ui_Camouflaging
                help = texts.ui_KeepCapacityHelp

            default:
                what = texts.ui_Resizing
                help = texts.ui_NewCapacityHelp
            }

            .progressPage.begin(.operation.path, what, help, kind == .Create ? texts.ui_StopCreating : texts.ui_StopResizing)
            .progressClock.restart()
            .showOperation()
            .showPage(.Progress)
        }
        else
        {
            .showOperation()
            .showBusy(true)
        }

        .operation.task.submit(func|window = me|() { window.runOperation() })
    }

    // Checks the create page, then creates the container in the background.
    mtd createContainer()
    {
        let path = .createPath.text()
        if path.count == 0
        {
            .showError(appStrings().msg_ChooseCreateFile)
            return
        }

        if File.exists(path)
        {
            .showError(appStrings().msg_FileExists)
            return
        }

        if not Core.Crypto.constantTimeEqual(.createPassword.bytes(), .confirmPassword.bytes())
        {
            .showError(appStrings().msg_PasswordMismatch)
            return
        }

        let size = parseCapacity(.createSize.text(), .createUnit.selectedIndex)
        if not size.error.isEmpty()
        {
            .showError(size.error)
            return
        }

        if size.bytes < MinimumSize
        {
            .showError(minimumSizeMessage())
            return
        }

        .operation.createHidden  = false
        .operation.protectHidden = false
        .operation.hiddenAccess.clear()
        .operation.path = path
        .operation.size = size.bytes
        .operation.access.setInputs(.createPassword.bytes(), .createKeyFiles.toSlice())
        .createPassword.clear()
        .confirmPassword.clear()
        .statusProgress = 0
        .setStatus(.Randomizing)
        .beginOperation(.Create)
    }

    // Creates the container when the create page holds everything it needs.
    //
    // A form that cannot answer stays silent instead of opening a box: the button is already down
    // for the same reason, so Enter says exactly what the button says.
    mtd submitCreate()
    {
        if .operation.kind != .None or not .canCreate() do
            return
        .createContainer()
    }

    // Mounts the drive when the unfolded vault holds everything it needs.
    mtd submitMount()
    {
        if .operation.kind != .None or not .canMount() do
            return
        .mountContainer()
    }

    // The unfolded vault identifies the outer container; this form owns only the new hidden access.
    mtd createHiddenContainer()
    {
        if not .canChangeVault() do
            return

        with var options: FormDlgOptions
        {
            .title = appStrings().ui_CreateHidden
            .confirmButtonText = appStrings().ui_CreateVault
        }

        let dialog = FormDlg.create(unwrap .surface, options)
        let fields = buildHiddenCreateForm(dialog)
        if dialog.doModal() != Dialog.BtnOk do
            return
        if not Core.Crypto.constantTimeEqual(fields.password.bytes(), fields.confirm.bytes())
        {
            .showError(appStrings().msg_PasswordMismatch)
            return
        }

        let size = parseCapacity(fields.capacity.text(), fields.unit.selectedIndex)
        if not size.error.isEmpty()
        {
            .showError(size.error)
            return
        }

        let reserve = parseCapacity(fields.reserve.text(), fields.reserveUnit.selectedIndex)
        if not reserve.error.isEmpty()
        {
            .showError(reserve.error)
            return
        }

        .operation.outerReserve = reserve.bytes
        .operation.hiddenAccess.setInputs(fields.password.bytes(), fields.keyFiles.paths.toSlice())
        if not .operation.hiddenAccess.isProtected()
        {
            .showError(appStrings().msg_PasswordRequired)
            return
        }

        .operation.path          = .chosenPath
        .operation.size          = size.bytes
        .operation.createHidden  = true
        .operation.protectHidden = false
        .operation.access.setInputs(.mountPassword.bytes(), .unlockKeyFiles.toSlice())
        .operation.resultKeyFiles = fields.keyFiles.paths
        .mountPassword.clear()
        .statusProgress = 0
        .setStatus(.Randomizing)
        .beginOperation(.Create)
    }

    // Asks for the access of the hidden volume the outer drive must not write over.
    mtd askHiddenProtection()->bool
    {
        with var options: FormDlgOptions
        {
            .title = appStrings().ui_ProtectHidden
            .confirmButtonText = appStrings().ui_Mount
        }

        let dialog = FormDlg.create(unwrap .surface, options)
        let fields = buildHiddenProtectionForm(dialog)
        if dialog.doModal() != Dialog.BtnOk do
            return false
        .operation.hiddenAccess.setInputs(fields.password.bytes(), fields.keyFiles.paths.toSlice())
        if not .operation.hiddenAccess.isProtected()
        {
            .showError(appStrings().msg_PasswordRequired)
            return false
        }

        return true
    }

    // Asks the running creation or growth to stop.
    //
    // The worker gives up at its next chunk boundary and unwinds like any other failure, which
    // is what deletes the partial container or puts a grown one back to its previous size. The
    // button goes down immediately so a second press cannot start anything while that happens.
    mtd stopLongOperation()
    {
        if .operation.kind != .Create and .operation.kind != .Resize do
            return
        .operation.progress.cancel()
        .progressPage.stop.enable(false)
        .setStatus(.StopRequested)
    }

    // Checks the unfolded vault, then mounts its container in the background.
    mtd mountContainer()
    {
        let path = String.from(.chosenLockedPath())
        if path.isEmpty()
        {
            .showError(appStrings().msg_ChooseExisting)
            return
        }

        if .isMounted(path)
        {
            .showError(appStrings().msg_AlreadyMounted)
            return
        }

        let mountPoint = .selectedMountPoint()
        if mountPoint.isEmpty()
        {
            .showError(appStrings().msg_NoDriveLetter)
            return
        }

        .operation.createHidden = false
        .operation.hiddenAccess.clear()
        .operation.protectHidden = .protectHiddenOnMount and not .readOnly.isChecked()
        .protectHiddenOnMount    = false
        if .operation.protectHidden and not .askHiddenProtection() do
            return
        .operation.access.setInputs(.mountPassword.bytes(), .unlockKeyFiles.toSlice())
        .mountPassword.clear()
        .startMount(path, mountPoint, false, .readOnly.isChecked())
    }

    // Starts the mount the password already staged in the operation opens.
    mtd startMount(path, mountPoint: String, fromStartup: bool, readOnly: bool)
    {
        .operation.path           = path
        .operation.mount          = mountPoint
        .operation.mountLabel     = .mountPointLabel(.operation.mount)
        .operation.fromStartup    = fromStartup
        .operation.readOnly       = readOnly
        .operation.usedProtection = .operation.access.isProtected() or .operation.protectHidden
        .operation.securityEpoch  = .securityEpoch
        .setStatus(.StartingDriver)
        .beginOperation(.Mount)
    }

    // Detaches the drive of the vault at `path` and unmounts it in the background.
    mtd unmountVault(path: string)
    {
        if .operation.kind != .None do
            return
        let index = .mountedDrives.indexOf(path)
        if index == Swag.U64.Max do
            return

        .operation.path       = .mountedDrives.drives[index].path
        .operation.mount      = .mountedDrives.drives[index].drive
        .operation.mountLabel = .mountedDrives.drives[index].mountLabel
        .operation.volume     = .mountedDrives.detach(index)

        // The row goes back to rest rather than unfolding: unmounting is not asking to open it again.
        if .chosenPath == path do
            .chosenPath.clear()
        .pruneVaults()
        .refreshVaults()
        .setStatus(.Unmounting)
        .beginOperation(.Unmount)
    }

    // Whether the unfolded vault names a container that can be changed now, saying why when it cannot.
    //
    // A mounted container is in use by Windows: changing its geometry or its key slots under the
    // driver would corrupt what the drive is reading.
    mtd canChangeVault()->bool
    {
        if .operation.kind != .None or not .canModifyVault() do
            return false
        if .isMounted(.chosenPath)
        {
            .showError(appStrings().msg_UnmountFirst)
            return false
        }

        return true
    }

    // Changes only the password. Current access and the retained key-file set come from the
    // unfolded vault, so the box contains the new password and its confirmation alone.
    mtd changeVaultPassword()
    {
        if not .canChangeVault() do
            return

        with var options: FormDlgOptions
        {
            .title = appStrings().dlg_TitlePassword
            .confirmButtonText = appStrings().dlg_BtnApply
        }

        let dialog = FormDlg.create(unwrap .surface, options)
        let fields = buildPasswordChangeForm(dialog)
        if dialog.doModal() != Dialog.BtnOk do
            return

        if not Core.Crypto.constantTimeEqual(fields.replacement.bytes(), fields.confirm.bytes())
        {
            .showError(appStrings().msg_PasswordMismatch)
            return
        }

        .operation.path = .chosenPath
        .operation.access.setInputs(.mountPassword.bytes(), .unlockKeyFiles.toSlice())
        .operation.replacement.setInputs(fields.replacement.bytes(), .unlockKeyFiles.toSlice())
        .mountPassword.clear()
        .operation.accessChange      = .Password
        .operation.leavesUnprotected = not .operation.replacement.isProtected()
        .operation.removesPassword   = fields.replacement.isEmpty()
        .setStatus(.ChangingPassword)
        .beginOperation(.ChangeAccess)
    }

    // Changes only the ordered key-file set. The box starts from the files already stated on the
    // unfolded vault, and current access is verified before the replacement slot is published.
    mtd changeVaultKeyFiles()
    {
        if not .canChangeVault() do
            return

        with var options: FormDlgOptions
        {
            .title = appStrings().dlg_TitleChangeKeyFiles
            .confirmButtonText = appStrings().dlg_BtnApply
        }

        let dialog = FormDlg.create(unwrap .surface, options)
        let files  = buildKeyFileChangeForm(dialog, .unlockKeyFiles.toSlice())
        if dialog.doModal() != Dialog.BtnOk or files.samePaths(.unlockKeyFiles.toSlice()) do
            return

        .operation.path = .chosenPath
        .operation.access.setInputs(.mountPassword.bytes(), .unlockKeyFiles.toSlice())
        .operation.replacement.setInputs(.mountPassword.bytes(), files.paths.toSlice())
        files.copyPaths(&.operation.resultKeyFiles)
        .mountPassword.clear()
        .operation.accessChange      = .KeyFiles
        .operation.leavesUnprotected = not .operation.replacement.isProtected()
        .setStatus(.ChangingKeyFiles)
        .beginOperation(.ChangeAccess)
    }

    // Asks only for another capacity, then resizes with the access stated on the unfolded vault.
    mtd resizeVault()
    {
        if not .canChangeVault() do
            return

        let path = String.from(.chosenPath)
        if not File.exists(path)
        {
            .showError(appStrings().msg_ChooseExisting)
            return
        }

        with var options: FormDlgOptions
        {
            .title = appStrings().dlg_TitleResize
            .confirmButtonText = appStrings().dlg_BtnApply
        }

        let dialog = FormDlg.create(unwrap .surface, options)
        let fields = buildVaultResizeForm(dialog)
        if dialog.doModal() != Dialog.BtnOk do
            return

        var requestedSize  = 0'u64
        let camouflageOnly = fields.keepCapacity.isChecked()
        if not camouflageOnly
        {
            let size = parseCapacity(fields.capacity.text(), fields.unit.selectedIndex)
            if not size.error.isEmpty()
            {
                .showError(size.error)
                return
            }

            requestedSize = size.bytes
        }

        .operation.path = path
        .operation.size = requestedSize
        .operation.camouflageOnly = camouflageOnly
        .operation.access.setInputs(.mountPassword.bytes(), .unlockKeyFiles.toSlice())
        .mountPassword.clear()
        .statusProgress = 0
        .setStatus(camouflageOnly ? .Camouflaging : .Resizing)
        .beginOperation(.Resize)
    }

    // The worker side of an operation: derives the credentials it needs, then creates, mounts,
    // unmounts, resizes, or changes access, and leaves any failure in `operation.error`.
    mtd runOperation()
    {
        defer .operation.hiddenAccess.clear()
        var hiddenCredential: VaultCredential
        if .operation.createHidden or .operation.protectHidden
        {
            hiddenCredential = catch .operation.hiddenAccess.derive()
            {
                .operation.error.capture(Swag.err)
                .operation.access.clear()
                return
            }
        }

        var current: VaultCredential
        if .operation.kind != .None and .operation.kind != .Unmount
        {
            current = catch .operation.access.derive()
            {
                .operation.error.capture(Swag.err)
                .operation.access.clear()
                .operation.replacement.clear()
                return
            }
        }

        switch #complete .operation.kind
        {
        case .None:
            return

        case .Create:
            if .operation.createHidden
            {
                var volume = catch Volume.createHidden(.operation.path,
                                                       current.toSlice(),
                                                       hiddenCredential.toSlice(),
                                                       .operation.size,
                                                       &.operation.progress,
                                                       .operation.outerReserve) as .operation.error
                {
                    break
                }

                volume.close()
            }
            else
            {
                var volume = catch Volume.create(.operation.path,
                                                 current.toSlice(),
                                                 .operation.size,
                                                 &.operation.progress) as .operation.error
                {
                    break
                }

                volume.close()
            }

        case .Mount:
            let mounted = Memory.new'MountedVault()
            discard catch mounted.open(.operation.path,
                                       current.toSlice(),
                                       .operation.mount,
                                       .operation.readOnly,
                                       hiddenCredential.toSlice()) as .operation.error
            {
                Memory.delete(mounted)
                .operation.volume = null
                break
            }

            .operation.volume = mounted

        case .Unmount:
            let mounted = .operation.volume
            if mounted
            {
                discard catch mounted.close() as .operation.error
                Memory.delete(mounted)
                .operation.volume = null
            }

        case .Resize:
            var volume = catch Volume.open(.operation.path, current.toSlice()) as .operation.error { break }
            if .operation.camouflageOnly
            {
                discard catch volume.reapplyCamouflage(&.operation.progress) as .operation.error
            }
            else
            {
                discard catch volume.resize(.operation.size, &.operation.progress) as .operation.error
            }

            volume.close()

        case .ChangeAccess:
            var replacement = catch .operation.replacement.derive() as .operation.error { break }
            var volume      = catch Volume.open(.operation.path, current.toSlice()) as .operation.error { break }
            discard catch volume.changePassword(current.toSlice(), replacement.toSlice()) as .operation.error
            volume.close()
        }

        .operation.access.clear()
        .operation.replacement.clear()
        .operation.hiddenAccess.clear()
    }

    // Says how far the running creation or resize is, on its page and in the status it keeps.
    //
    // Only the two operations that write bytes know how far along they are; the others wait on
    // the driver or on a key derivation, and the spinner already says everything that can
    // honestly be said about them.
    mtd reportProgress()
    {
        if .operation.kind != .Create and .operation.kind != .Resize do
            return
        if .operation.progress.isCanceled() do
            return

        let ratio = .operation.progress.ratio()
        let bytes = .operation.progress.counts()
        .statusProgress = cast(s32, ratio * 100)
        .progressPage.setProgress(ratio, bytes.done, bytes.total, .timeLeft(ratio))

        if .operation.kind == .Create do
            .setStatus(.Randomizing)
        elif .operation.camouflageOnly do
            .setStatus(.Camouflaging)
        else do
            .setStatus(.Resizing)
    }

    // Says how long the running operation still needs, from how long the part done took; empty
    // until enough is done to say it honestly.
    mtd timeLeft(ratio: f32)->String
    {
        var result: #returntype
        const MinimumRatio = 0.02'f32
        if ratio < MinimumRatio or ratio >= 1 do
            return result

        let elapsed = cast(f64, .progressClock.elapsedMilliseconds()) / 1000
        let seconds = cast(u64, Math.ceil(elapsed * (1 - ratio) / ratio))
        if seconds < 120 do
            result = Format.toString(appStrings().ui_SecondsLeft, seconds)
        else do
            result = Format.toString(appStrings().ui_MinutesLeft, (seconds + 59) / 60)
        return result
    }

    // Waits for the worker, then hands the outcome to the finish step of the operation kind.
    mtd finishOperation()
    {
        .operation.task.wait()
        var operationErrorOutcome: Swag.Error
        catch .operation.error.raise() as operationErrorOutcome
        let operationError = operationErrorOutcome.value()
        .stopTimer(&.operation.timer)
        .showBusy(false)

        switch #complete .operation.kind
        {
        case .None:         return
        case .Create:       .finishCreate(operationError)
        case .Mount:        .finishMount(operationError)
        case .Unmount:      .finishUnmount(operationError)
        case .Resize:       .finishResize(operationError)
        case .ChangeAccess: .finishAccessChange(operationError)
        }

        .operation.forgetRequest()
        .showOperation()
        .refreshActions()

        // A protected startup vault still unfolded for its access holds the queue: a mount of it
        // that failed leaves it there for another try.
        if .startupQueue.count and (.startupWaiting.isEmpty() or .isMounted(.startupWaiting)) do
            .pumpStartupQueue()
    }

    // Reports how a creation ended. A new vault joins the list, unfolded and ready to mount; a
    // creation that stopped leads back to where it was asked for.
    mtd finishCreate(operationError: any?)
    {
        let hidden = .operation.createHidden
        if isCanceledError(operationError)
        {
            // A creation the user stopped is an outcome, not a failure, so it reports on
            // the notice line and never opens a dialog.
            .setStatus(hidden ? .HiddenCreateCanceled : .CreateCanceled)
            .showPage(hidden ? .List : .Create)
        }
        elif operationError != null
        {
            .showError(appStrings().msg_CreateFailed, operationError)
            .setStatus(.CreateStopped)
            .showPage(hidden ? .List : .Create)
        }
        else
        {
            .setStatus(.Created)
            let path = String.from(.operation.path)
            .openVault(path)
            if hidden do
                .unlockKeyFiles = .operation.resultKeyFiles
            else do
                .unlockKeyFiles = .createKeyFiles
            .list.card.setKeyFileCount(.unlockKeyFiles.count)
            .showPage(.List)
        }
    }

    // Reports how a mount ended. A mount that finished after a security event is closed at once.
    mtd finishMount(operationError: any?)
    {
        if operationError != null
        {
            // A startup mount reports on the notice line alone: a box per vault would meet
            // the reader with a stack of them before the window is even readable.
            if not .operation.fromStartup and not .operation.securityStopped do
                .showError(appStrings().msg_MountFailed, operationError)
            .setStatus(.operation.securityStopped ? .AutoUnmounted : .MountStopped)
        }
        elif .operation.usedProtection and .operation.securityEpoch != .securityEpoch
        {
            let mounted = .operation.volume
            if mounted
            {
                discard catch mounted.close() { .setStatus(.AutoUnmountStopped) }
                Memory.delete(mounted)
                .operation.volume = null
            }

            if .statusMessage != .AutoUnmountStopped do
                .setStatus(.AutoUnmounted)
        }
        else
        {
            .rememberMountedDrive()
            .statusDrive = .operation.mountLabel
            if .operation.readOnly do
                .setStatus(.MountedReadOnly)
            elif .operation.protectHidden do
                .setStatus(.MountedProtected)
            else do
                .setStatus(.Mounted)
        }

        .fillDriveChoice()
        .refreshVaults()
    }

    // Reports an unmount; a drive that could not flush is still gone.
    mtd finishUnmount(operationError: any?)
    {
        if operationError != null do
            .showError(appStrings().msg_UnmountSyncStopped, operationError)
        .setStatus(.Unmounted)
        .fillDriveChoice()
        .refreshVaults()
    }

    // Reports how a resize or a camouflage refresh ended, back on the list.
    mtd finishResize(operationError: any?)
    {
        if isCanceledError(operationError)
        {
            .setStatus(.ResizeCanceled)
        }
        elif operationError != null
        {
            .showError(appStrings().msg_ResizeFailed, operationError)
            .setStatus(.ResizeStopped)
        }
        elif .operation.camouflageOnly
        {
            .setStatus(.Camouflaged)
        }
        else
        {
            .statusDrive = capacityText(.operation.size)
            .setStatus(.Resized)
        }

        .showPage(.List)
    }

    // Reports how a password or key-file change ended.
    mtd finishAccessChange(operationError: any?)
    {
        if operationError != null
        {
            let keyFiles = .operation.accessChange == .KeyFiles
            .showError(keyFiles ? appStrings().msg_KeyFilesFailed : appStrings().msg_PasswordFailed, operationError)
            .setStatus(keyFiles ? .KeyFilesStopped : .PasswordStopped)
        }
        else
        {
            .rememberAccessChange()
            if .operation.accessChange == .KeyFiles
            {
                .unlockKeyFiles = .operation.resultKeyFiles
                .list.card.setKeyFileCount(.unlockKeyFiles.count)
                .setStatus(.KeyFilesChanged)
            }
            else
            {
                .setStatus(.operation.removesPassword ? .PasswordRemoved : .PasswordChanged)
            }
        }
    }

    // Adds the drive the mount operation produced to the list, on the row of its vault.
    mtd rememberMountedDrive()
    {
        let known = .startupIndex(.operation.path)

        // The vault keeps the choices of its last mount, so the next one starts from them.
        .addVault(.operation.path)
        if let vault = .findVault(.operation.path)
        {
            vault.drive    = .operation.mount
            vault.readOnly = .operation.readOnly
        }

        with var entry: MountedDrive
        {
            .volume        = me.operation.volume
            .path          = me.operation.path
            .drive         = me.operation.mount
            .mountLabel    = me.operation.mountLabel
            .needsPassword = me.operation.usedProtection
            .readOnly      = me.operation.readOnly
            .protectHidden = me.operation.protectHidden
            .atStartup     = not me.privacyMode and known != Swag.U64.Max
        }

        if .operation.volume
        {
            let space = .operation.volume.space()
            entry.totalBytes     = space.total
            entry.availableBytes = space.available
        }

        // The letter is remembered as the one actually used, so a startup vault comes back on
        // the drive it was last seen on rather than on the one it was first marked with.
        if not .privacyMode and known != Swag.U64.Max
        {
            .startupVaults[known].drive         = .operation.mount
            .startupVaults[known].protectHidden = .operation.protectHidden
            .startupVaults[known].readOnly      = .operation.readOnly
        }

        .mountedDrives.drives.add(#move entry)
        .refreshVaults()
        catch g_App.saveState()
    }

    // Keeps the startup list truthful after any change to what opens the vault.
    mtd rememberAccessChange()
    {
        if .privacyMode do
            return
        let index = .startupIndex(.operation.path)
        if index != Swag.U64.Max
        {
            .startupVaults[index].needsPassword = not .operation.leavesUnprotected
            catch g_App.saveState()
        }
    }

    // Fills the drive picker with the destinations the active filesystem backend still has free.
    //
    // Mounting takes one and unmounting gives it back, so the list is said again after both:
    // a letter that is no longer free must not stay on offer.
    mtd fillDriveChoice()
    {
        let previous = .selectedMountPoint()
        .drive.clear()

        .mountDestinations = availableMountDestinations()
        for &destination in .mountDestinations do
            .drive.addItem(destination.label)

        if .drive.items.count and not .selectMountPoint(previous) do
            .drive.setSelectedIndex(0, notify: false)
    }

    // Selects `mountPoint` when that backend destination is still available.
    mtd selectMountPoint(mountPoint: string)->bool
    {
        for &destination, index in .mountDestinations where destination.id == mountPoint
        {
            .drive.setSelectedIndex(cast(u32, index), notify: false)
            return true
        }

        return false
    }

    // Lets the reader pick the container file `target` names, for creating it.
    mtd chooseContainer(target: *EditBox, create: bool)
    {
        // Privacy controls persistence, not the convenience of returning to the last folder
        // during this run. Serialization below remains the only path from this state to disk.
        with var options: FileDlgOptions
        {
            .state             = &me.fileDlgState
            .mode              = create ? .CreateFile : .SelectFile
            .title             = create ? appStrings().dlg_TitleCreate : appStrings().dlg_TitleOpen
            .confirmButtonText = create ? appStrings().dlg_BtnCreate : appStrings().dlg_BtnOpen
            .initialName       = create ? "volume" : ""
            .shortcuts.add({type: Env.SpecialDirectory.Desktop, name: appStrings().ui_Desktop})
            .shortcuts.add({type: Env.SpecialDirectory.UserDocuments, name: "Documents"})
        }

        let dialog = FileDlg.create(unwrap .surface, options)
        if dialog.doModal() == Dialog.BtnOk do
            target.setText(dialog.selectedPath())
    }

    // Returns the backend identifier of the destination the picker selects, or an empty string.
    mtd selectedMountPoint()->String
    {
        let index = .drive.selectedIndex
        return index < .mountDestinations.count ? .mountDestinations[index].id : ""
    }

    // Returns the host-facing name for a backend destination identifier.
    mtd mountPointLabel(mountPoint: string)->String
    {
        for &destination in .mountDestinations where destination.id == mountPoint do
            return destination.label
        return mountPoint
    }
}
