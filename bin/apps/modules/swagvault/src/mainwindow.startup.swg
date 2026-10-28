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

    // Mounts the next container marked for startup, asking for its transient access when needed.
    //
    // One at a time: a mount is a job, and the operation that finishes is what calls this
    // again, so the drives come up in order instead of all at once on one worker.
    mtd pumpStartupQueue()
    {
        while .startupQueue.count
        {
            let entry = .startupQueue[0]
            .startupQueue.removeAtOrdered(0)

            if entry.drive.isEmpty() or not File.exists(entry.path) or .isMounted(entry.path) do
                continue

            .operation.access.clear()
            if entry.needsPassword and not .askStartupAccess(entry.path) do
                continue

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

    // Asks for the password and key files of one protected startup container.
    //
    // Skipping is an answer: a vault whose access material is not at hand simply does not come up,
    // and the mark it carries is left alone for the next start.
    mtd askStartupAccess(path: string)->bool
    {
        let title = Format.toString(appStrings().dlg_TitleUnlock, Path.fileName(path) orelse path)

        with var options: FormDlgOptions
        {
            .title = title
            .confirmButtonText = appStrings().ui_Mount
            .cancelButtonText  = appStrings().dlg_BtnSkip
        }

        let dialog   = FormDlg.create(unwrap .surface, options)
        let password = dialog.form.addPasswordField(appStrings().ui_Password, placeholder: appStrings().ui_ContainerPassword, help: path)
        let keyFiles = KeyFileField.create(dialog.form)
        discard dialog.form.addField(appStrings().ui_KeyFiles, keyFiles, help: appStrings().ui_KeyFilesHelp)
        VaultForm.finish(dialog.form)
        if dialog.doModal() != Dialog.BtnOk do
            return false

        .operation.access.setInputs(password.bytes(), keyFiles.paths.toSlice())
        return true
    }
}
