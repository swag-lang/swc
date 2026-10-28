impl MainWindow
{
    // Applies privacy without firing the switch's save callback.
    mtd applyPrivacyControl()
    {
        .privacyModeControl.setChecked(.privacyMode)
        .refreshHint()
        .refreshVaults()
    }

    // Removes every persisted or pending path while retaining appearance and
    // automatic-unmount preferences. The vaults that are mounted, or being unlocked, stay on
    // the list for as long as that lasts.
    mtd clearPrivateState()
    {
        .fileDlgState = {}
        .startupVaults.clear()
        .startupQueue.clear()
        for &one in .mountedDrives.drives do
            one.atStartup = false
        .pruneVaults()
        .refreshVaults()
    }

    // Applies the privacy switch: turning it on forgets the remembered containers and drives,
    // turning it off lets the list and the startup drives be remembered.
    mtd readPrivacyControl()
    {
        .privacyMode = .privacyModeControl.isChecked()
        if .privacyMode do
            .clearPrivateState()
        .refreshHint()
        .refreshVaults()
        catch g_App.saveState()
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
        .idleTimeout.setSelectedIndex(.idleIndexFor(.autoUnmount.idleMinutes), notify: false)
        .idleTimeout.enable(.autoUnmount.onIdle)
    }

    // Reads one complete policy snapshot and persists it immediately.
    mtd readAutoUnmountControls()
    {
        .autoUnmount.onSessionLock = .unmountOnLock.isChecked()
        .autoUnmount.onSuspend     = .unmountOnSuspend.isChecked()
        .autoUnmount.onIdle        = .unmountOnIdle.isChecked()
        .autoUnmount.idleMinutes   = .idleMinutesAt(.idleTimeout.selectedIndex)
        .idleTimeout.enable(.autoUnmount.onIdle)
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

    // Closes protected mounts synchronously. Lock and suspend notifications cannot leave cleanup
    // queued behind the event that is taking the session away.
    mtd handleAutoUnmount(cause: AutoUnmountCause)
    {
        if .shuttingDown or not .autoUnmountEnabled(cause) do
            return

        .securityEpoch += 1
        .startupQueue.clear()
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
        var index     = .mountedDrives.drives.count
        while index
        {
            index -= 1
            let entry = &.mountedDrives.drives[index]
            if not entry.needsPassword do
                continue
            unmounted = true

            let mounted = entry.volume
            entry.volume = null
            if mounted
            {
                discard catch mounted.close() { synchronizationStopped = true }
                Memory.delete(mounted)
            }

            .mountedDrives.drives.removeAtOrdered(index)
        }

        if not interruptedMount and not unmounted do
            return

        .pruneVaults()
        .refreshVaults()
        .fillDriveChoice()
        .setStatus(synchronizationStopped ? .AutoUnmountStopped : .AutoUnmounted)
    }
}
