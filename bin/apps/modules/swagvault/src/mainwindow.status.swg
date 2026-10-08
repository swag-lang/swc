impl MainWindow
{
    // Puts the spinner in the glyph's place while an operation runs, and takes it back when the
    // operation ends. A spinner is the honest report for work whose remaining time is unknown;
    // creation and growth additionally write their percentage onto the status line.
    mtd showBusy(busy: bool)
    {
        if .statusBusy.isLocallyVisible() == busy do
            return
        .statusIcon.show(not busy)
        .statusBusy.show(busy)
        .statusView.applyLayout()
    }

    // Reports the outcome of the latest step on the single status line.
    //
    // One glyph, three colors: the theme atlas has no monochrome success or failure glyph, and
    // borrowing a colored one would put a third hue on a two-color surface. The color alone
    // separates a line that is waiting from one that reports work, or one that stopped.
    mtd setStatus(message: StatusMessage)
    {
        .statusMessage = message
        .refreshStatus()
    }

    // Writes the current status message on the line in the active language.
    mtd refreshStatus()
    {
        let colors = .themeColors()

        var glyphColor, textColor: Color
        switch #complete .statusTone()
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

        var glyph = .theme().icon(ThemeIcons.About, themeActionIconSize(.themeMetrics()))
        glyph.color = glyphColor
        .statusIcon.setIcon(glyph)
        .status.setTextColor(textColor)
        .status.setText(.statusText())
    }

    // Returns the emphasis the current status message carries.
    mtd statusTone()->StatusTone
    {
        switch #complete .statusMessage
        {
        case .Randomizing,
             .StopRequested,
             .StartingDriver,
             .Unmounting,
             .Mounted,
             .MountedReadOnly,
             .MountedProtected,
             .Resizing,
             .Camouflaging,
             .ChangingPassword,
             .ChangingKeyFiles: return .Active

        case .CreateStopped, .MountStopped, .ResizeStopped, .PasswordStopped, .KeyFilesStopped, .AutoUnmountStopped: return .Stopped

        case .Ready,
             .CreateCanceled,
             .HiddenCreateCanceled,
             .Created,
             .Unmounted,
             .ResizeCanceled,
             .Resized,
             .Camouflaged,
             .AutoUnmounted,
             .PasswordChanged,
             .PasswordRemoved,
             .KeyFilesChanged: return .Idle
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
            MessageDlg.error(.surface!, message)
        else do
            MessageDlg.error(.surface!, Format.toString("%\n\n%", message, caughtMessage(err)))
    }
}
