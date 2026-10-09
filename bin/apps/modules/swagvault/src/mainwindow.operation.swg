impl MainWindow
{
    // Starts `kind` on the worker and polls it until `finishOperation` takes the result.
    mtd beginOperation(kind: OperationKind)
    {
        Swag.assert(.operation.kind == .None)
        .operation.kind = kind
        .showOperation()
        .operation.error.reset()
        .operation.timer = .addTimer(50'ms)

        // Arming the tracker before the task starts is what clears the cancellation a previous
        // operation left behind.
        .operation.progress.begin(0)
        .showBusy(true)

        .operation.task.submit(func|window = me|() { window.runOperation() })
    }

    // Checks the create form, then creates the container in the background.
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
        .operation.access.setInputs(.createPassword.bytes(), .createKeyFiles.paths.toSlice())
        .createPassword.clear()
        .confirmPassword.clear()
        .statusProgress = 0
        .setStatus(.Randomizing)
        .beginOperation(.Create)
    }

    // The open card identifies the outer container; this form owns only the new hidden access.
    mtd createHiddenContainer()
    {
        if not .canChangeVault() do
            return

        with var options: FormDlgOptions
        {
            .title = appStrings().ui_CreateHidden
            .confirmButtonText = appStrings().ui_CreateVault
            .width = 520
        }

        let dialog = FormDlg.create(.surface!, options)
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

        .operation.path          = .mountPath.text()
        .operation.size          = size.bytes
        .operation.createHidden  = true
        .operation.protectHidden = false
        .operation.access.setInputs(.mountPassword.bytes(), .mountKeyFiles.paths.toSlice())
        .operation.resultKeyFiles = fields.keyFiles.paths
        .mountPassword.clear()
        .statusProgress = 0
        .setStatus(.Randomizing)
        .showTab(0)
        .beginOperation(.Create)
    }

    // Asks for the access of the hidden volume the outer drive must not write over.
    mtd askHiddenProtection()->bool
    {
        with var options: FormDlgOptions
        {
            .title = appStrings().ui_ProtectHidden
            .confirmButtonText = appStrings().ui_MountDrive
            .width = 520
        }

        let dialog = FormDlg.create(.surface!, options)
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
        .createButton.enable(false)
        .resizeButton.enable(false)
        .setStatus(.StopRequested)
    }

    // Checks the mount form, then mounts the container in the background.
    mtd mountContainer()
    {
        let path = .mountPath.text()
        if path.count == 0
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
        .operation.protectHidden = .protectHidden.isChecked() and not .readOnly.isChecked()
        .protectHidden.setState(.Unchecked)
        if .operation.protectHidden and not .askHiddenProtection() do
            return
        .operation.access.setInputs(.mountPassword.bytes(), .mountKeyFiles.paths.toSlice())
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

    // Detaches the selected drive from the list and unmounts it in the background.
    mtd unmountSelectedDrive()
    {
        if .operation.kind != .None do
            return
        let index = .mountedDrives.selectedIndex()
        if index == Swag.U64.Max do
            return

        .operation.path       = .mountedDrives.drives[index].path
        .operation.mount      = .mountedDrives.drives[index].drive
        .operation.mountLabel = .mountedDrives.drives[index].mountLabel
        .operation.volume     = .mountedDrives.detach(index)
        .setStatus(.Unmounting)
        .beginOperation(.Unmount)
    }

    // Whether the open card names a container that can be changed now, saying why when it cannot.
    //
    // A mounted container is in use by Windows: changing its geometry or its key slots under the
    // driver would corrupt what the drive is reading.
    mtd canChangeVault()->bool
    {
        if .operation.kind != .None or not .canModifyVault() do
            return false
        if .isMounted(.mountPath.text())
        {
            .showError(appStrings().msg_UnmountFirst)
            return false
        }

        return true
    }

    // Changes only the password. Current access and the retained key-file set come from the open
    // card, so the box contains the new password and its confirmation alone.
    mtd changeVaultPassword()
    {
        if not .canChangeVault() do
            return

        with var options: FormDlgOptions
        {
            .title  = appStrings().dlg_TitlePassword
            .confirmButtonText = appStrings().dlg_BtnApply
            .width  = 520
            .height = 300
        }

        let dialog = FormDlg.create(.surface!, options)
        let fields = buildPasswordChangeForm(dialog)
        if dialog.doModal() != Dialog.BtnOk do
            return

        if not Core.Crypto.constantTimeEqual(fields.replacement.bytes(), fields.confirm.bytes())
        {
            .showError(appStrings().msg_PasswordMismatch)
            return
        }

        .operation.path = .mountPath.text()
        .operation.access.setInputs(.mountPassword.bytes(), .mountKeyFiles.paths.toSlice())
        .operation.replacement.setInputs(fields.replacement.bytes(), .mountKeyFiles.paths.toSlice())
        .mountPassword.clear()
        .operation.accessChange      = .Password
        .operation.leavesUnprotected = not .operation.replacement.isProtected()
        .operation.removesPassword   = fields.replacement.isEmpty()
        .setStatus(.ChangingPassword)
        .beginOperation(.ChangeAccess)
    }

    // Changes only the ordered key-file set. The box starts from the files already stated on the
    // open card, and current access is verified before the replacement slot is published.
    mtd changeVaultKeyFiles()
    {
        if not .canChangeVault() do
            return

        with var options: FormDlgOptions
        {
            .title = appStrings().dlg_TitleChangeKeyFiles
            .confirmButtonText = appStrings().dlg_BtnApply
        }

        let dialog = FormDlg.create(.surface!, options)
        let files  = buildKeyFileChangeForm(dialog, .mountKeyFiles.paths.toSlice())
        if dialog.doModal() != Dialog.BtnOk or files.samePaths(.mountKeyFiles.paths.toSlice()) do
            return

        .operation.path = .mountPath.text()
        .operation.access.setInputs(.mountPassword.bytes(), .mountKeyFiles.paths.toSlice())
        .operation.replacement.setInputs(.mountPassword.bytes(), files.paths.toSlice())
        files.copyPaths(&.operation.resultKeyFiles)
        .mountPassword.clear()
        .operation.accessChange      = .KeyFiles
        .operation.leavesUnprotected = not .operation.replacement.isProtected()
        .setStatus(.ChangingKeyFiles)
        .beginOperation(.ChangeAccess)
    }

    // Asks only for another capacity, then resizes with the access stated on the open card.
    mtd resizeVault()
    {
        if not .canChangeVault() do
            return

        let path = .mountPath.text()
        if not File.exists(path)
        {
            .showError(appStrings().msg_ChooseExisting)
            return
        }

        with var options: FormDlgOptions
        {
            .title  = appStrings().dlg_TitleResize
            .confirmButtonText = appStrings().dlg_BtnApply
            .width  = 520
            .height = 240
        }

        let dialog = FormDlg.create(.surface!, options)
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
        .operation.access.setInputs(.mountPassword.bytes(), .mountKeyFiles.paths.toSlice())
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
            hiddenCredential = catch .operation.hiddenAccess.derive() as hiddenError
            if hiddenError != null
            {
                .operation.error.capture(hiddenError)
                .operation.access.clear()
                return
            }
        }

        var current: VaultCredential
        if .operation.kind != .None and .operation.kind != .Unmount
        {
            current = catch .operation.access.derive() as accessError
            if accessError != null
            {
                .operation.error.capture(accessError)
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
                                                       .operation.outerReserve) as createError
                .operation.error.capture(createError)
                if createError == null do
                    volume.close()
            }
            else
            {
                var volume = catch Volume.create(.operation.path,
                                                 current.toSlice(),
                                                 .operation.size,
                                                 &.operation.progress) as createError
                .operation.error.capture(createError)
                if createError == null do
                    volume.close()
            }

        case .Mount:
            let mounted = Memory.new'MountedVault()
            discard catch mounted.open(.operation.path,
                                       current.toSlice(),
                                       .operation.mount,
                                       .operation.readOnly,
                                       hiddenCredential.toSlice()) as mountError
            .operation.error.capture(mountError)
            if mountError != null
            {
                Memory.delete(mounted)
                .operation.volume = null
            }
            else
            {
                .operation.volume = mounted
            }

        case .Unmount:
            let mounted = .operation.volume
            if mounted
            {
                discard catch mounted.close() as unmountError
                .operation.error.capture(unmountError)
                Memory.delete(mounted)
                .operation.volume = null
            }

        case .Resize:
            var volume = catch Volume.open(.operation.path, current.toSlice()) as openError
            .operation.error.capture(openError)
            if openError == null
            {
                if .operation.camouflageOnly
                {
                    discard catch volume.reapplyCamouflage(&.operation.progress) as resizeError
                    .operation.error.capture(resizeError)
                }
                else
                {
                    discard catch volume.resize(.operation.size, &.operation.progress) as resizeError
                    .operation.error.capture(resizeError)
                }

                volume.close()
            }

        case .ChangeAccess:
            var replacement = catch .operation.replacement.derive() as deriveError
            .operation.error.capture(deriveError)
            if deriveError != null do
                break

            var volume = catch Volume.open(.operation.path, current.toSlice()) as openError
            .operation.error.capture(openError)
            if openError == null
            {
                discard catch volume.changePassword(current.toSlice(), replacement.toSlice()) as changeError
                .operation.error.capture(changeError)
                volume.close()
            }
        }

        .operation.access.clear()
        .operation.replacement.clear()
        .operation.hiddenAccess.clear()
    }

    // Refreshes the status line of the operation that is still running.
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
        .statusProgress = cast(s32, .operation.progress.ratio() * 100)
        if .operation.kind == .Create do
            .setStatus(.Randomizing)
        elif .operation.camouflageOnly do
            .setStatus(.Camouflaging)
        else do
            .setStatus(.Resizing)
    }

    // Waits for the worker, then hands the outcome to the finish step of the operation kind.
    mtd finishOperation()
    {
        .operation.task.wait()
        catch .operation.error.raise() as operationError
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

        if .startupQueue.count do
            .pumpStartupQueue()
    }

    // Reports how a creation ended, and on success points the mount tab at the new container.
    mtd finishCreate(operationError: any?)
    {
        if isCanceledError(operationError)
        {
            // A creation the user stopped is an outcome, not a failure, so it reports on
            // the status line and never opens a dialog.
            .setStatus(.operation.createHidden ? .HiddenCreateCanceled : .CreateCanceled)
        }
        elif operationError != null
        {
            .showError(appStrings().msg_CreateFailed, operationError)
            .setStatus(.CreateStopped)
        }
        else
        {
            .setStatus(.Created)
            .mountPath.setText(.operation.path)
            if .operation.createHidden
            {
                .mountKeyFiles.setPaths(.operation.resultKeyFiles.toSlice())
                .protectHidden.setState(.Unchecked)
                .showTab(1)
            }
            else
            {
                .mountKeyFiles.setPaths(.createKeyFiles.paths.toSlice())
            }
        }
    }

    // Reports how a mount ended. A mount that finished after a security event is closed at once.
    mtd finishMount(operationError: any?)
    {
        if operationError != null
        {
            // A startup mount reports on the status line alone: a box per vault would meet
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
                discard catch mounted.close() as closeError
                if closeError != null do
                    .setStatus(.AutoUnmountStopped)
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
    }

    // Reports an unmount; a drive that could not flush is still gone.
    mtd finishUnmount(operationError: any?)
    {
        if operationError != null do
            .showError(appStrings().msg_UnmountSyncStopped, operationError)
        .setStatus(.Unmounted)
        .fillDriveChoice()
    }

    // Reports how a resize or a camouflage refresh ended.
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
                .mountKeyFiles.setPaths(.operation.resultKeyFiles.toSlice())
                .setStatus(.KeyFilesChanged)
            }
            else
            {
                .setStatus(.operation.removesPassword ? .PasswordRemoved : .PasswordChanged)
            }
        }
    }

    // Adds the drive the mount operation produced to the band.
    mtd rememberMountedDrive()
    {
        let known = .startupIndex(.operation.path)
        if not .privacyMode
        {
            .mountSettings.path     = .operation.path
            .mountSettings.drive    = .operation.mount
            .mountSettings.readOnly = .operation.readOnly
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
        .mountedDrives.refresh()
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
}
