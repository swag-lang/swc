impl MainWindow
{
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
        while .startupQueue.count
        {
            let entry = .startupQueue[0]
            .startupQueue.removeAtOrdered(0)

            if entry.drive.isEmpty() or not File.exists(entry.path) or .isMounted(entry.path) do
                continue

            if entry.needsPassword
            {
                if not .chosenPath.isEmpty() do
                    continue
                .unfoldStartupVault(entry)
                return
            }

            .operation.access.clear()
            .operation.protectHidden = entry.protectHidden and not entry.readOnly
            .operation.hiddenAccess.clear()
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
