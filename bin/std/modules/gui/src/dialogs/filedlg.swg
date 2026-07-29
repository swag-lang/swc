#global public

using Core, File, Directory

// Selects file dlg mode.
enum FileDlgMode
{
    CreateFile // Selects create file mode.
    SelectOneFile // Selects select one file mode.
    SelectMultiFiles // Selects select multi files mode.
    SelectFolder // Selects select folder mode.
}

// Represents file dlg state.
struct FileDlgState
{
    position:            Math.Rectangle // Position associated with this value.
    curFolder:           String // Cur folder associated with this value.
    folderHistory:       Array'String // Folder history associated with this value.
    columnWidthName:     s32 = 200 // Column width name associated with this value.
    columnWidthModified: s32 = 150 // Column width modified associated with this value.
}

// Represents file dlg options.
struct FileDlgOptions
{
    title:      string      = "" // Title associated with this value.
    btnOkName:  string      = "" // Btn ok name associated with this value.
    openFolder: string      = "" // Open folder associated with this value.
    editName:   string      = "" // Edit name associated with this value.
    drivePane               = true // Drive pane associated with this value.
    mode:       FileDlgMode = SelectOneFile // Mode associated with this value.
    filters:    Array'{ name: string, extensions: string } // Filters associated with this value.
    shortcuts:  Array'{ type: Core.Env.SpecialDirectory, name: string } // Shortcuts associated with this value.
    state:      #null *FileDlgState // State associated with this value.
}

// Thin modal wrapper around the reusable 'FileBrowserCtrl' composite.
struct FileDlg
{
    using dialog: Dialog // Embedded dialog state.
    #[Swag.Late]
    browser:    *FileBrowserCtrl // Browser associated with this value.
    dlgOptions: FileDlgOptions // Dlg options associated with this value.
}

impl IWnd for FileDlg
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        // The browser saves the folder/column widths; the dialog owns the position.
        let state = .dlgOptions.state
        if state do
            state.position = (notnull .surface).position
    }
}

private impl FileDlg
{
    mtd onNewFolder()
    {
        let folderName: String = "New Folder"

        with let dlg = EditDlg.createSingleLine(notnull me.surface)
        {
            let edit = notnull .edit
            edit.setText(folderName)
            edit.selectAll()
            edit.setNote("Folder name")
            let srf = notnull .surface
            srf.setTitle("Folder Name")
            srf.center(notnull me.surface)
        }

        dlg.sigPressedButton = func|dlg, browser = me.browser|(fdlg, btnid)
        {
            if btnid != Dialog.BtnOk do
                return true

            let dedit      = notnull dlg.edit
            var folderName = dedit.text
            folderName.trim()
            if folderName.isEmpty()
            {
                dedit.selectAll()
                dedit.setFocus()
                return false
            }

            if !Path.isValidFileName(folderName)
            {
                MessageDlg.error(notnull dlg.surface, "Invalid folder name")
                dedit.selectAll()
                dedit.setFocus()
                return false
            }

            let path = Path.combine(browser.curFolder, folderName.toString())
            if Directory.exists(path)
            {
                MessageDlg.error(notnull dlg.surface, "Folder already exists")
                dedit.selectAll()
                dedit.setFocus()
                return false
            }

            return true
        }

        if dlg.doModal() != Dialog.BtnOk do
            return

        if !.browser.createFolder((notnull dlg.edit).text.toString()) do
            MessageDlg.error(notnull .surface, "Cannot create folder")
    }
}

impl FileDlg
{
    // Creates the file dialog (own OS surface), hosting a FileBrowserCtrl.
    func create(from: *Surface, opt: FileDlgOptions = {})->*FileDlg
    {
        let dlg = Wnd.create'FileDlg()
        dlg.fromSurface = from
        dlg.dlgOptions  = opt

        with let srf = dlg.createSurface(from, 100, 100, 700, 500)
        {
            .setSurfaceFlags(add: .Sizeable)
            .minSize = {400, 400}

            if opt.title do
                .setTitle(opt.title)
            else
            {
                switch #complete opt.mode
                {
                case .CreateFile:       .setTitle("Create File")
                case .SelectOneFile:    .setTitle("Select File")
                case .SelectMultiFiles: .setTitle("Select Files")
                case .SelectFolder:     .setTitle("Select Folder")
                }
            }
        }

        dlg.addButton(opt.btnOkName orelse "Ok", Dialog.BtnOk, true)
        dlg.addButton("Cancel", Dialog.BtnCancel)
        dlg.backgroundStyle = .Window
        srf.setSurfaceFlags(remove: .CloseBtn)

        // Host the reusable browser composite.
        with dlg.browser = FileBrowserCtrl.create(srf.getView(), opt)
        {
            .dockStyle    = .Center
            .sigAccept    += func|fileDlg = dlg|(b) { fileDlg.validateId(Dialog.BtnOk) }
            .sigNewFolder += func|fileDlg = dlg|(b) { fileDlg.onNewFolder() }
        }

        dlg.sigPressedButton = func|dlg|(bdlg, id)
        {
            if id == Dialog.BtnOk
            {
                let selName = dlg.browser.getSelectedName()
                if selName == null
                {
                    dlg.browser.editFile.selectAll()
                    dlg.browser.editFile.setFocus()
                    return false
                }

                if dlg.dlgOptions.mode == .CreateFile and File.exists(selName)
                {
                    let res = MessageDlg.confirm(notnull dlg.surface, "This file already exists.", "Do you want to replace it ?")
                    return res == Dialog.BtnYes
                }
            }

            return true
        }

        dlg.applyLayout()

        // Restore the saved surface position if any.
        if opt.state and !opt.state.position.isEmpty() do
            srf.setPosition(opt.state.position)
        else do
            srf.center(from)

        return dlg
    }

    // Get the first selection (full path)
    mtd getSelectedName()->String
    {
        return .browser.getSelectedName()
    }

    // Get all selections (full paths)
    mtd getSelectedNames()->Array'String
    {
        return .browser.getSelectedNames()
    }
}
