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
        .refreshStatus()
    }

    // Writes the current status message on the notice line in the active language.
    //
    // A window that is ready has nothing to report, so the line is not there: it appears with the
    // first step that leaves something to say, and stays while work runs.
    mtd refreshStatus()
    {
        let notice = .list.notice
        notice.set(.statusText(), .statusTone())
        let shown = .statusMessage != .Ready or notice.busy.isLocallyVisible()
        if notice.isLocallyVisible() != shown
        {
            notice.show(shown)
            .list.arrange()
        }
    }

    // Returns the emphasis the current status message carries.
    mtd statusTone()->StatusTone
    {
        switch #complete .statusMessage
        {
        case .Randomizing, .StopRequested, .StartingDriver, .Unmounting, .Mounted, .MountedReadOnly,
             .MountedProtected, .Resizing, .Camouflaging, .ChangingPassword, .ChangingKeyFiles:
            return .Active

        case .CreateStopped, .MountStopped, .ResizeStopped,
             .PasswordStopped, .KeyFilesStopped, .AutoUnmountStopped:
            return .Stopped

        case .Ready, .CreateCanceled, .HiddenCreateCanceled, .Created,
             .Unmounted, .ResizeCanceled, .Resized, .Camouflaged, .AutoUnmounted,
             .PasswordChanged, .PasswordRemoved, .KeyFilesChanged:
            return .Idle
        }
    }

    // Returns the current status message in the active language.
    mtd statusText()->String
    {
        let texts = appStrings()
        switch #complete .statusMessage
        {
        case .Ready:                return texts.msg_Ready
        case .Randomizing:          return Format.toString(texts.msg_Randomizing, .statusProgress)
        case .StopRequested:        return texts.msg_StopRequested
        case .HiddenCreateCanceled: return texts.msg_HiddenCreateCanceled
        case .CreateCanceled:       return texts.msg_CreateCanceled
        case .StartingDriver:       return texts.msg_StartingDriver
        case .Unmounting:           return texts.msg_Unmounting
        case .CreateStopped:        return texts.msg_CreateStopped
        case .Created:              return texts.msg_Created
        case .MountStopped:         return texts.msg_MountStopped
        case .Mounted:              return Format.toString(texts.msg_Mounted, .statusDrive)
        case .MountedProtected:     return Format.toString(texts.msg_MountedProtected, .statusDrive)
        case .MountedReadOnly:      return Format.toString(texts.msg_MountedReadOnly, .statusDrive)
        case .Unmounted:            return texts.msg_Unmounted
        case .Resizing:             return Format.toString(texts.msg_Resizing, .statusProgress)
        case .Camouflaging:         return Format.toString(texts.msg_Camouflaging, .statusProgress)
        case .ResizeCanceled:       return texts.msg_ResizeCanceled
        case .ResizeStopped:        return texts.msg_ResizeStopped
        case .Resized:              return Format.toString(texts.msg_Resized, .statusDrive)
        case .Camouflaged:          return texts.msg_Camouflaged
        case .AutoUnmounted:        return texts.msg_AutoUnmounted
        case .AutoUnmountStopped:   return texts.msg_AutoUnmountStopped
        case .ChangingPassword:     return texts.msg_ChangingPassword
        case .PasswordChanged:      return texts.msg_PasswordChanged
        case .PasswordRemoved:      return texts.msg_PasswordRemoved
        case .PasswordStopped:      return texts.msg_PasswordStopped
        case .ChangingKeyFiles:     return texts.msg_ChangingPassword
        case .KeyFilesChanged:      return texts.msg_KeyFilesChanged
        case .KeyFilesStopped:      return texts.msg_KeyFilesStopped
        }
    }

    // Opens an error box saying `message`, followed by the sentence for `err` when there is one.
    mtd showError(message: string, err: any? = null)
    {
        if err == null do
            MessageDlg.error(unwrap .surface, message)
        else do
            MessageDlg.error(unwrap .surface, Format.toString("%\n\n%", message, caughtMessage(err)))
    }
}
