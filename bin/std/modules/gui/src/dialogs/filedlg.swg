#global public

using Core, File, Directory

// Selects what a file dialog accepts.
enum FileDlgMode
{
    CreateFile       // Accepts a destination file path, including a new file.
    SelectFile       // Accepts one existing file.
    SelectFiles      // Accepts multiple existing files.
    SelectFolder     // Accepts one existing folder.
}

// Stores reusable file-dialog placement and browsing state between invocations.
struct FileDlgState
{
    surfacePosition:     Math.Rectangle     // Last dialog surface rectangle.
    currentFolder:       String             // Last browsed folder.
    nameColumnWidth:     s32 = 200          // Last width of the name column.
    modifiedColumnWidth: s32 = 150          // Last width of the modified-time column.
}

// Configures a [[Gui.FileDlg]] or embedded [[Gui.FileBrowserCtrl]].
struct FileDlgOptions
{
    title:             string      = ""                                            // Surface title, or empty for a mode-specific title.
    confirmButtonText: string      = ""                                            // Confirmation button label, or empty for "OK".
    initialFolder:     string      = ""                                            // Initially browsed folder, when non-empty.
    initialName:       string      = ""                                            // Initial file-name editor contents.
    showLocationsPane              = true                                          // Whether to show shortcuts and drives.
    mode:              FileDlgMode = SelectFile                                    // Accepted selection kind.
    filters:           Array'{ name: string, extensions: string }                  // Named extension filters; empty means all files.
    shortcuts:         Array'{ type: Core.Env.SpecialDirectory, name: string }     // Locations shown in the shortcuts pane; empty uses common user folders.
    state:             #null *FileDlgState                                         // Optional borrowed state updated on destruction.
}

// Thin modal wrapper around the reusable 'FileBrowserCtrl' composite.
struct FileDlg
{
    using dialog: Dialog     // Embedded dialog state.
    readonly
    {
        #[Swag.Late]
        browser: *FileBrowserCtrl     // Embedded browser control.
        options: FileDlgOptions       // Effective dialog options.
    }
}

impl IWnd for FileDlg
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        // The browser saves the folder/column widths; the dialog owns the position.
        let state = .options.state
        if state do
            state.surfacePosition = (notnull .surface).position
    }
}

private impl FileDlg
{
    mtd onNewFolder()
    {
        var options: FormDlgOptions
        options.title  = "New Folder"
        options.width  = 440
        options.height = 220
        options.fields.add({id: "name", label: "FOLDER NAME", initialText: "New Folder",
                            placeholder: "Folder name"})
        let dlg  = FormDlg.create(notnull me.surface, #move options)
        let edit = notnull dlg.textField("name")
        edit.selectAll()
        edit.setFocus()

        dlg.validateResult = func|dlg, browser = me.browser, edit|(fdlg, btnid)
        {
            discard fdlg
            if btnid != Dialog.BtnOk do
                return true

            var folderName: String
            folderName = edit.text()
            folderName.trim()
            if folderName.isEmpty()
            {
                edit.selectAll()
                edit.setFocus()
                return false
            }

            if !Path.isValidFileName(folderName)
            {
                MessageDlg.error(notnull dlg.surface, "The folder name is not valid.")
                edit.selectAll()
                edit.setFocus()
                return false
            }

            let path = Path.combine(browser.currentFolder, folderName.toString())
            if Directory.exists(path)
            {
                MessageDlg.error(notnull dlg.surface, "A folder with this name already exists.")
                edit.selectAll()
                edit.setFocus()
                return false
            }

            return true
        }

        if dlg.doModal() != Dialog.BtnOk do
            return

        if !.browser.createFolder(edit.text())
        {
            MessageDlg.error(notnull .surface, "The folder could not be created.")
            return
        }

        .browser.setFileName(edit.text())
    }
}

impl FileDlg
{
    // Creates the file dialog (own OS surface), hosting a FileBrowserCtrl.
    #[Swag.Discardable]
    func create(from: *Surface, opt: FileDlgOptions = {})->*FileDlg
    {
        Debug.assert(from != null)
        let dlg = Wnd.create'FileDlg()
        dlg.options = opt

        with let srf = dlg.createSurface(from, 100, 100, 700, 500)
        {
            .updateFlags(add: .Resizable)
            .minSize = {400, 400}

            if @countof(opt.title) do
                .setTitle(opt.title)
            else
            {
                switch #complete opt.mode
                {
                case .CreateFile:   .setTitle("Create File")
                case .SelectFile:   .setTitle("Select File")
                case .SelectFiles:  .setTitle("Select Files")
                case .SelectFolder: .setTitle("Select Folder")
                }
            }
        }

        dlg.addButton(@countof(opt.confirmButtonText) ? opt.confirmButtonText : "OK",
                      Dialog.BtnOk,
                      true)
        dlg.addButton("Cancel", Dialog.BtnCancel)
        dlg.backgroundStyle = .Window
        srf.updateFlags(remove: .CloseButton)

        // Host the reusable browser composite.
        with dlg.browser = FileBrowserCtrl.create(srf.view(), opt)
        {
            .dockStyle             = .Center
            .sigAccepted           += func|fileDlg = dlg|(b) { fileDlg.closeWithResult(Dialog.BtnOk) }
            .sigNewFolderRequested += func|fileDlg = dlg|(b) { fileDlg.onNewFolder() }
        }

        dlg.validateResult = func|dlg|(bdlg, id)
        {
            if id == Dialog.BtnOk
            {
                if !dlg.browser.hasValidSelection()
                {
                    dlg.browser.editFile.selectAll()
                    dlg.browser.editFile.setFocus()
                    return false
                }

                let selName = dlg.browser.selectedPath()
                if dlg.options.mode == .CreateFile and File.exists(selName)
                {
                    let res = MessageDlg.confirm(notnull dlg.surface, "This file already exists.", "Do you want to replace it?")
                    return res == Dialog.BtnYes
                }
            }

            return true
        }

        dlg.applyLayout()

        // Restore the saved surface position if any.
        if opt.state and !opt.state.surfacePosition.isEmpty() do
            srf.setPosition(opt.state.surfacePosition)
        else do
            srf.center(from)

        return dlg
    }

    // Returns the first selected full path, or an empty string when no valid selection exists.
    mtd selectedPath()->String
    {
        return .browser.selectedPath()
    }

    // Returns all selected full paths in display order.
    mtd selectedPaths()->Array'String
    {
        return .browser.selectedPaths()
    }
}
