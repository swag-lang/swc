impl MainWindow
{
    mtd queueAutomaticMount(path: string)
    {
        // Keep an earlier file in the session list when a newer one takes the pending mount.
        if not .pendingMountPath.isEmpty() and .pendingMountPath != path do
            .addVault(.pendingMountPath)

        .pendingMountPath = path
        if not .automaticMountTimer do
            .automaticMountTimer = .addTimer(40'ms)
    }

    // Tries empty access for an explicitly opened file. A selected vault can already have
    // access in its controls, which still belongs to the person's next manual mount.
    mtd openForAutomaticMount(path: string)
    {
        .fillDriveChoice()
        .openVault(path)
        .checkEmptyAccess(path)
    }

    private mtd checkEmptyAccess(path: string)
    {
        if .operation.kind != .None or not .pendingMountPath.isEmpty() or .chosenLockedPath() != path or not .canMount() do
            return

        let startup = .startupIndex(path)
        if startup != Swag.U64.Max and
           .startupVaults[startup].protectHidden and
           not .readOnly.isChecked()
        {
            .protectHiddenOnMount = true
            .refreshVaults()
        }

        if not .mountPassword.isEmpty() or not .unlockKeyFiles.isEmpty() or .protectHiddenOnMount do
            return

        // Checking for empty access is part of opening the file. Driver setup begins only
        // once the container has opened successfully.
        .operation.path = path
        .beginOperation(.CheckEmptyAccess)
    }

    // Continues opening the selected vault after its background access check.
    mtd finishEmptyAccessCheck(error: any?)
    {
        let active = not .resident.isHidden() and not .resident.batch and not .surface!.isDisabled and .page == .List
        let selected = .chosenLockedPath()
        let manual = active and selected.count != 0 and .manualMountPath == selected and
                     (.pendingMountPath.isEmpty() or .pendingMountPath == selected)
        let current = active and selected.count != 0 and .operation.path == selected and .pendingMountPath.isEmpty()

        .operation.forgetRequest()
        .manualMountPath.clear()
        for row in .list.rows do
            row.unmount.enable(true)
        .refreshActions()

        defer
        {
            if .operation.kind == .None and .pendingMountPath.isEmpty() and not .resident.batch and .startupQueue.count and
               (.startupWaiting.isEmpty() or .startupWaiting != .chosenPath or .isMounted(.startupWaiting)) do
                .pumpStartupQueue()
        }

        if manual
        {
            if .pendingMountPath == selected
            {
                .pendingMountPath.clear()
                .stopTimer(&.automaticMountTimer)
            }

            .mountContainer()
        }
        elif not .pendingMountPath.isEmpty() and not .automaticMountTimer
        {
            let path = #move .pendingMountPath
            if active and path == selected do
                .checkEmptyAccess(path)
        }
        elif current
        {
            if error == null
            {
                if .mountPassword.isEmpty() and .unlockKeyFiles.isEmpty() and not .protectHiddenOnMount do
                    .mountContainer()
            }
            else
            {
                if error is Error as volumeError where volumeError.kind == .PasswordOrDamaged do
                    return
                .finishMount(error)
            }
        }
    }

    // Returns the startup entry for `path`, or `Swag.U64.Max` when there is none.
    mtd startupIndex(path: string)->u64
    {
        for &one, index in .startupVaults where one.path == path do
            return index
        return Swag.U64.Max
    }

    // Marks the mounted vault at `path` to be mounted again the next time Swag Vault starts, or
    // takes the mark off.
    //
    // A drive that is unmounted keeps its mark: the list is what Swag Vault mounts at its next
    // start, not what it happens to be showing now.
    mtd toggleStartup(path: string)
    {
        let drive = .mountedDrives.find(path)
        if .privacyMode or not drive do
            return

        drive.atStartup = not drive.atStartup
        let known = .startupIndex(drive.path)
        if known != Swag.U64.Max do
            .startupVaults.removeAtOrdered(known)
        if drive.atStartup do
            .startupVaults.add(StartupVault{drive.path, drive.drive, drive.needsPassword, drive.readOnly, drive.protectHidden})

        .refreshVaults()
        catch g_App.saveState()
    }

    // Mounts the next container marked for startup; a protected one unfolds in the list for its
    // access instead.
    //
    // One at a time: a mount is a job, and the operation that finishes is what calls this
    // again, so the drives come up in order instead of all at once on one worker. An unfolded
    // vault holds the queue until it is mounted, or until the reader leaves it, which skips it. A
    // protected vault never takes the list from a reader who has chosen another one: it is skipped.
    mtd pumpStartupQueue()
    {
        .startupWaiting.clear()

        // Background startup never displays a credential prompt. Protected entries remain
        // locked in the ordinary list and can be opened when the user returns to the window.
        let hidden = .resident.isHidden()
        while .startupQueue.count
        {
            let entry = .startupQueue[0]
            .startupQueue.removeAtOrdered(0)

            if entry.drive.isEmpty() or not File.exists(entry.path) or .isMounted(entry.path) do
                continue

            if entry.needsPassword or .needsDriverChoice()
            {
                if hidden do
                    continue
                if not .chosenPath.isEmpty() do
                    continue
                .unfoldStartupVault(entry)
                return
            }

            .operation.access.clear()
            .operation.protectHidden = entry.protectHidden and not entry.readOnly
            .operation.hiddenAccess.clear()
            if hidden and .operation.protectHidden do
                continue
            if .operation.protectHidden and not .askHiddenProtection()
            {
                .operation.access.clear()
                .operation.protectHidden = false
                continue
            }

            .startMount(entry.path, entry.drive, true, entry.readOnly)
            return
        }
    }

    // Unfolds one protected startup vault in the list, on the drive, the read-only choice and the
    // hidden protection it was marked with, and waits for its access.
    //
    // Leaving it is an answer: a vault whose access material is not at hand simply does not come
    // up, and the mark it carries is left alone for the next start.
    mtd unfoldStartupVault(entry: StartupVault)
    {
        .openVault(entry.path)
        .readOnly.setState(entry.readOnly ? .Checked : .Unchecked)
        discard .selectMountPoint(entry.drive)
        .protectHiddenOnMount = entry.protectHidden and not entry.readOnly
        .startupWaiting       = entry.path
        .refreshVaults()
    }

    // Goes on with the startup queue once the reader has left the startup vault unfolded for its
    // access without mounting it.
    mtd skipStartupVault()
    {
        if .startupWaiting.isEmpty() or .chosenPath == .startupWaiting or .operation.kind != .None do
            return
        .pumpStartupQueue()
    }
}
