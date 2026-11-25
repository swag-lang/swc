impl MainWindow
{
    // Applies privacy without firing the switch's save callback.
    mtd applyPrivacyControl()
    {
        .privacyModeControl.setChecked(.privacyMode)
        .publishMountPrivacy()
        .refreshHint()
        .refreshVaults()
    }

    // Clears startup mount requests and their marks on the mounted drives.
    mtd clearStartupMounts()
    {
        .startupVaults.clear()
        .startupQueue.clear()
        .startupWaiting.clear()
        .stopTimer(&.startupTimer)
        for &one in .mountedDrives.drives do
            one.atStartup = false
    }

    // Applies the privacy switch and saves the resulting settings.
    mtd readPrivacyControl()
    {
        .privacyMode = .privacyModeControl.isChecked()
        .publishMountPrivacy()
        if .privacyMode do
            .clearStartupMounts()
        .refreshVaults()
        catch g_App.saveState()
    }

    // Both restored settings and interactive changes apply to every currently owned mount.
    mtd publishMountPrivacy()
    {
        for &drive in .mountedDrives.drives where drive.volume do
            drive.volume.setPrivateMode(.privacyMode)
    }

    // Returns the idle delay the picker entry at `index` offers, in minutes.
    mtd idleMinutesAt(index: u32)->u32 => index < IdleChoices.count ? IdleChoices[index] : IdleChoices[IdleDefaultIndex]

    // Returns the entry of the idle picker that offers `minutes`, or the default one.
    mtd idleIndexFor(minutes: u32)->u32
    {
        for choice, index in IdleChoices where choice == minutes do
            return cast(u32, index)
        return IdleDefaultIndex
    }

    // Applies persisted policy without firing the switches' save callbacks.
    mtd applyAutoUnmountControls()
    {
        .unmountOnLock.setChecked(.autoUnmount.onSessionLock)
        .unmountOnSuspend.setChecked(.autoUnmount.onSuspend)
        .unmountOnIdle.setChecked(.autoUnmount.onIdle)
        .optionsPage.setTimeout(.idleIndexFor(.autoUnmount.idleMinutes))
        .idleTimeout.setLinksEnabled(.autoUnmount.onIdle)
    }

    // Reads one complete policy snapshot and persists it immediately.
    mtd readAutoUnmountControls()
    {
        .autoUnmount.onSessionLock = .unmountOnLock.isChecked()
        .autoUnmount.onSuspend     = .unmountOnSuspend.isChecked()
        .autoUnmount.onIdle        = .unmountOnIdle.isChecked()
        .autoUnmount.idleMinutes   = .idleMinutesAt(.optionsPage.timeoutIndex)
        .idleTimeout.setLinksEnabled(.autoUnmount.onIdle)
        catch g_App.saveState()
    }

    // Whether the settings unmount the drives on `cause`.
    mtd autoUnmountEnabled(cause: AutoUnmountCause)->bool
    {
        switch #complete cause
        {
        case .SessionLock: return .autoUnmount.onSessionLock
        case .Suspend:     return .autoUnmount.onSuspend
        case .Idle:        return .autoUnmount.onIdle
        }
    }

    // Attempts ordinary unmounts synchronously. Lock and suspend cannot leave cleanup
    // queued behind the event that is taking the session away.
    mtd handleAutoUnmount(cause: AutoUnmountCause)
    {
        if .shuttingDown or not .autoUnmountEnabled(cause) do
            return

        .securityEpoch  += 1
        .autoRetryAfter = Time.monotonicMilliseconds() + 30_000
        .startupQueue.clear()
        if .operation.kind == .InstallDriver and not .operation.path.isEmpty() do
            .forgetAccess()
        if .operation.kind == .Unmount do
            .operation.task.wait()
        let interruptedMount = .operation.kind == .Mount and .operation.usedProtection

        // A protected mount already in flight belongs to the event too. Waiting here lets the
        // worker hand its handle back before the notification returns; `finishOperation` sees the
        // changed epoch and closes it instead of publishing a new drive after the lock or sleep.
        if interruptedMount
        {
            .operation.securityStopped = true
            .operation.task.wait()
            .finishOperation()
        }

        var synchronizationStopped = interruptedMount and .statusMessage == .AutoUnmountStopped
        var unmounted = false
        var remaining = 0'u64
        var index     = .mountedDrives.drives.count
        while index
        {
            index -= 1
            let entry = &.mountedDrives.drives[index]
            if not entry.needsPassword do
                continue

            // The unmount worker borrows this row. Its completion owns removal and reporting.
            if .operation.kind == .Unmount and entry.path == .operation.path
            {
                if entry.volume and entry.volume.handle do
                    remaining += 1
                continue
            }

            unmounted = true

            let mounted = entry.volume
            if mounted
            {
                discard catch mounted.close()
                {
                    synchronizationStopped = true
                    if not isBusyError(Swag.err) do
                        .statusDetail = {failure: describeFailure(Swag.err)}
                }

                if mounted.handle
                {
                    mounted.setPrivateMode(.privacyMode)
                    remaining += 1
                    continue
                }

                entry.volume = null
                Memory.delete(mounted)
            }

            .mountedDrives.drives.removeAtOrdered(index)
        }

        if not interruptedMount and not unmounted do
            return

        .pruneVaults()
        .refreshVaults()
        .fillDriveChoice()
        .statusDrive = Format.toString("%", remaining)
        if remaining do
            .setStatus(.AutoUnmountBusy)
        else do
            .setStatus(synchronizationStopped ? .AutoUnmountStopped : .AutoUnmounted)
        .resident.refreshTray()
        if .resident.isHidden() do
            .resident.notify(.statusText())
    }
}
