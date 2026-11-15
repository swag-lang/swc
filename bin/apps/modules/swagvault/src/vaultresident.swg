using Core, Gui, Pixel

// Non-sensitive preferences; existing installations keep the ordinary close behavior.
struct ResidentSettings
{
    enabled:          bool
    startWithSession: bool
    showReminder:     bool = true
}

// Owns the notification-area lifecycle and a serial batch of ordinary unmounts.
struct VaultResident
{
    late window:         *MainWindow
    settings:            ResidentSettings
    running:             bool
    activationRequested: bool
    icon:                Image
    tip:                 String
    notice:              *TrayNotice?
    menu:                *ResidentMenu?
    batch:               bool
    quitting:            bool
    failed:              bool
    failureDetail:       String
    pending:             Array'String
}

impl VaultResident
{
    mtd start()
    {
        .running = true
        .icon    = expect Image.decode(".png", AppIcon)
        .refreshTray()
        if Env.hasArgument("--hide") and
           not .activationRequested and
           .settings.enabled and
           .window.surface!.hasTrayIcon() do
            .remind()
        else do
            .showWindow()
    }

    mtd isHidden()->bool => .running and .window.surface!.isHidden

    mtd activate()
    {
        .activationRequested = true
        if .running do
            .showWindow()
    }

    mtd showWindow()
    {
        .notice?.close()
        let surface = unwrap .window.surface
        if surface.isMinimized do
            surface.showNormal()
        else do
            surface.show()
        surface.bringToFront()
    }

    // Failure to register the icon always leaves a visible route back to the mounts.
    mtd refreshTray()
    {
        if not .running do
            return
        let surface = unwrap .window.surface
        if not .settings.enabled
        {
            surface.removeTrayIcon()
            return
        }

        let count   = .window.mountedDrives.drives.count
        let texts   = appStrings()
        let nextTip = count == 1 ? String.from(texts.msg_ResidentTipOne) : Format.toString(texts.msg_ResidentTip, count)
        if .tip != nextTip or not surface.hasTrayIcon()
        {
            surface.setTrayIcon(.icon, nextTip)
            .tip = nextTip
        }

        if not surface.hasTrayIcon() and surface.isHidden
        {
            .showWindow()
            .window.statusDetail = appStrings().msg_TrayUnavailable
            .window.refreshStatus()
        }
    }

    mtd hideWindow()
    {
        .refreshTray()
        if not .window.surface!.hasTrayIcon()
        {
            .showWindow()
            .window.showError(appStrings().msg_TrayUnavailable)
            return
        }

        .window.forgetAccess()
        .window.createPassword.clear()
        .window.confirmPassword.clear()
        .window.createKeyFiles.clear()
        .window.createPage.setKeyFileCount(0)
        .window.lens.close()
        catch g_App.saveState()
        .window.surface.hide()
        .remind()
    }

    mtd remind()
    {
        if not .settings.showReminder do
            return
        .notify(appStrings().msg_ResidentText, reminder: true)
    }

    mtd notify(message: string, reminder = false)
    {
        if not .running do
            return
        .notice?.close()
        let texts  = appStrings()
        let notice = TrayNotice.open(unwrap .window.surface, texts.msg_ResidentTitle, message, reminder ? texts.ui_ResidentReminder : null)
        if not notice
        {
            .showWindow()
            return
        }

        .notice = notice
        notice.sigDismissed += func|resident = me|(dismissed)
        {
            if resident.notice == dismissed do
                resident.notice = null
        }

        notice.sigOptionChanged += func|resident = me|(_, checked)
        {
            resident.settings.showReminder = not checked
            catch g_App.saveState()
        }
    }

    mtd applySettings()
    {
        .window.optionsPage.resident.toggle.setChecked(.settings.enabled)
        .window.optionsPage.startup.toggle.setChecked(.settings.startWithSession)
        .window.optionsPage.startup.toggle.enable(.settings.enabled)
        .refreshTray()
    }

    mtd setEnabled(enabled: bool)
    {
        if not enabled and .settings.startWithSession
        {
            if not Env.setSessionStartup(ApplicationId, ProductName, false)
            {
                .applySettings()
                .window.showError(appStrings().msg_StartupFailed)
                return
            }

            .settings.startWithSession = false
        }

        .settings.enabled = enabled
        if not enabled and .isHidden() do
            .showWindow()
        .applySettings()
        catch g_App.saveState()
    }

    mtd setSessionStartup(enabled: bool)
    {
        if enabled and not .settings.enabled do
            return
        if not Env.setSessionStartup(ApplicationId, ProductName, enabled, ["--hide"])
        {
            .applySettings()
            .window.showError(appStrings().msg_StartupFailed)
            return
        }

        .settings.startWithSession = enabled
        .applySettings()
        catch g_App.saveState()
    }

    // Never exit while a mount, an operation or an unreviewed synchronization failure remains.
    mtd unmountAll(quit: bool)
    {
        if .window.operation.kind != .None or .batch
        {
            .showWindow()
            .window.showError(appStrings().msg_FinishOperation)
            return
        }

        .window.startupQueue.clear()
        .pending.clear()
        for &drive in .window.mountedDrives.drives do
            .pending.add(drive.path)
        .batch    = true
        .quitting = quit
        .failed   = false
        .failureDetail.clear()
        .continueUnmount()
    }

    mtd continueUnmount()
    {
        if not .batch do
            return
        while .pending.count
        {
            let path = .pending[0]
            .pending.removeAtOrdered(0)
            if not .window.isMounted(path) do
                continue
            .window.unmountVault(path)
            return
        }

        .batch = false
        let count = .window.mountedDrives.drives.count
        if .failed or count
        {
            .quitting = false
            .window.statusDetail = .failureDetail
            .window.statusDrive  = Format.toString("%", count)
            .window.setStatus(count ? .UnmountStopped : .UnmountSyncStopped)
            if .isHidden() do
                .notify(.window.statusText())
            return
        }

        if .quitting
        {
            .quitting = false
            catch g_App.saveState()
            .window.surface!.destroy()
        }
    }

    mtd stop()
    {
        .running = false
        .menu?.close()
        .notice?.close()
        .window.surface?.removeTrayIcon()
    }
}
