impl MainWindow
{
    // The portable preference only suppresses the choice; an installed driver takes priority.
    mtd needsDriverChoice()->bool
    {
        return SupportsWinFspInstall and
               not .preferPortableWinFsp and
               .mountedDrives.drives.isEmpty() and
               not hasInstalledWinFsp()
    }

    // Returns true when the caller should continue its ordinary mount now.
    mtd chooseDriverForMount(path: string)->bool
    {
        let texts  = appStrings()
        let dialog = MessageDlg.create(unwrap .surface, texts.msg_WinFspChoice, {title: texts.msg_WinFspMissing, mark: .Question})
        dialog.addButton(texts.dlg_BtnKeepPortable, Dialog.BtnNo)
        dialog.addButton(Gui.strings().dlg_Cancel, Dialog.BtnCancel)
        dialog.addButton(texts.cmd_InstallWinFsp, Dialog.BtnOk, true)
        switch dialog.doModal()
        {
        case Dialog.BtnNo:
            .preferPortableWinFsp = true
            catch g_App.saveState()
            return true

        case Dialog.BtnOk:
            .startDriverInstall(path)
        }

        return false
    }

    // A path asks to resume that vault's mount after the installer succeeds.
    mtd startDriverInstall(resumePath: string = "")
    {
        if not SupportsWinFspInstall or
           .operation.kind != .None or
           .resident.batch or
           not .mountedDrives.drives.isEmpty() do
            return
        .operation.path = resumePath
        .setStatus(.InstallingDriver)
        .beginOperation(.InstallDriver)
    }

    mtd finishDriverInstall(operationError: any?)
    {
        if operationError == null
        {
            .setStatus(.DriverInstalled)
        }
        elif isCanceledError(operationError)
        {
            .setStatus(.Ready)
        }
        else
        {
            .setStatus(.DriverInstallStopped)
            .showError(&appStrings().msg_WinFspInstallStopped, operationError)
        }
    }
}
