impl MainWindow
{
    // Puts the spinner in the place of the notice's dot while an operation runs, and takes it back
    // when the operation ends. A spinner is the honest report for work whose remaining time is
    // unknown; creation and growth have their own page, which says how far they are.
    mtd showBusy(busy: bool)
    {
        .list.notice.setBusy(busy)
        .refreshStatus()
    }

    // Reports the outcome of the latest step on the notice line under the title of the list.
    mtd setStatus(message: StatusMessage)
    {
        .statusMessage = message
        if not .statusHeadline.isEmpty() and .statusTone() != .Stopped
        {
            .statusHeadline = {}
            .statusDetail   = {}
        }

        .refreshStatus()
    }

    // Writes the current status message on the notice line in the active language.
    //
    // A window that is ready has nothing to report, so the line is not there: it appears with the
    // first step that leaves something to say, and stays while work runs.
    mtd refreshStatus()
    {
        let notice = .list.notice
        let failed = not .statusHeadline.isEmpty()
        let detail = .statusDetail.text()
        if failed do
            notice.set(.statusHeadline.text(), detail, .Stopped)
        elif .statusMessage == .Ready and not detail.isEmpty() do
            notice.set(detail, "", .Idle)
        else do
            notice.set(.statusText(), detail, .statusTone())
        notice.show(failed or .statusMessage != .Ready or not detail.isEmpty() or notice.busy.isLocallyVisible())
        .list.arrange()
    }

    // Returns the emphasis the current status message carries.
    mtd statusTone()->StatusTone
    {
        switch #complete .statusMessage
        {
        case .ReadingKeyFile, .Randomizing, .StopRequested, .StartingDriver,
             .InstallingDriver, .Unmounting, .Mounted, .MountedReadOnly, .MountedProtected,
             .Resizing, .Camouflaging, .ChangingPassword, .ChangingKeyFiles:
            return .Active

        case .CreateStopped, .MountStopped, .DriverInstallStopped, .ResizeStopped,
             .PasswordStopped, .KeyFilesStopped, .AutoUnmountStopped,
             .AutoUnmountBusy, .UnmountStopped, .UnmountSyncStopped:
            return .Stopped

        case .Ready, .CreateCanceled, .HiddenCreateCanceled, .Created,
             .DriverInstalled, .Unmounted, .ResizeCanceled, .Resized, .Camouflaged,
             .AutoUnmounted, .PasswordChanged, .PasswordRemoved, .KeyFilesChanged:
            return .Idle
        }
    }

    // Returns the current status message in the active language.
    mtd statusText()->String
    {
        let texts = appStrings()
        switch #complete .statusMessage
        {
        case .Ready:
            return texts.msg_Ready

        case .ReadingKeyFile:
            return texts.ui_ReadingKeyFile

        case .Randomizing:
            return Format.toString(texts.msg_Randomizing, .statusProgress)

        case .StopRequested:
            return texts.msg_StopRequested

        case .HiddenCreateCanceled:
            return texts.msg_HiddenCreateCanceled

        case .CreateCanceled:
            return texts.msg_CreateCanceled

        case .StartingDriver:
            return texts.msg_StartingDriver

        case .InstallingDriver:
            return texts.msg_InstallingDriver

        case .DriverInstalled:
            return texts.msg_DriverInstalled

        case .DriverInstallStopped:
            return texts.msg_WinFspInstallStopped

        case .Unmounting:
            return texts.msg_Unmounting

        case .CreateStopped:
            return texts.msg_CreateStopped

        case .Created:
            return texts.msg_Created

        case .MountStopped:
            return texts.msg_MountStopped

        case .Mounted:
            return Format.toString(texts.msg_Mounted, .statusDrive)

        case .MountedProtected:
            return Format.toString(texts.msg_MountedProtected, .statusDrive)

        case .MountedReadOnly:
            return Format.toString(texts.msg_MountedReadOnly, .statusDrive)

        case .Unmounted:
            return texts.msg_Unmounted

        case .Resizing:
            return Format.toString(texts.msg_Resizing, .statusProgress)

        case .Camouflaging:
            return Format.toString(texts.msg_Camouflaging, .statusProgress)

        case .ResizeCanceled:
            return texts.msg_ResizeCanceled

        case .ResizeStopped:
            return texts.msg_ResizeStopped

        case .Resized:
            return Format.toString(texts.msg_Resized, capacityText(.statusCapacity))

        case .Camouflaged:
            return texts.msg_Camouflaged

        case .AutoUnmounted:
            return texts.msg_AutoUnmounted

        case .AutoUnmountStopped:
            return texts.msg_AutoUnmountStopped

        case .AutoUnmountBusy:
            if .statusDrive == "1" do
                return texts.msg_AutoUnmountBusyOne
            return Format.toString(texts.msg_AutoUnmountBusy, .statusDrive)

        case .UnmountStopped:
            if .statusDrive == "1" do
                return texts.msg_UnmountStoppedOne
            return Format.toString(texts.msg_UnmountStopped, .statusDrive)

        case .UnmountSyncStopped:
            return texts.msg_UnmountSyncStopped

        case .ChangingPassword:
            return texts.msg_ChangingPassword

        case .PasswordChanged:
            return texts.msg_PasswordChanged

        case .PasswordRemoved:
            return texts.msg_PasswordRemoved

        case .PasswordStopped:
            return texts.msg_PasswordStopped

        case .ChangingKeyFiles:
            return texts.msg_ChangingKeyFiles

        case .KeyFilesChanged:
            return texts.msg_KeyFilesChanged

        case .KeyFilesStopped:
            return texts.msg_KeyFilesStopped
        }
    }

    // Opens an error box and keeps its summary and cause on the notice line.
    mtd showError(key: const *string, err: any? = null, shortTitle = false, number = 0'u64)
    {
        .statusHeadline = {key, number}
        let failure = describeFailure(err)
        .statusDetail = {failure: {present: failure.present, kind: failure.kind}}

        let message = .statusHeadline.text()
        let reason  = failure.reason()
        let code    = failure.codeText()
        .refreshStatus()
        if .resident.isHidden()
        {
            .resident.notify(message)
            return
        }

        if shortTitle
        {
            MessageDlg.error(unwrap .surface, reason, options: {title: message, detail: code})
            return
        }

        let body = reason.isEmpty() ? String.from(message) : Format.toString("%\n\n%", message, reason)
        MessageDlg.error(unwrap .surface, body, options: {detail: code})
    }
}
