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
//
// Keep one instance per dialog role and pass it through [[Gui.FileDlgOptions.state]] so
// every invocation reopens where the previous one ended. The struct serializes cleanly,
// so an application can persist it inside its [[Gui.SerializeStateEvent]] handler and
// give the dialog a memory across runs.
struct FileDlgState
{
    surfacePosition:     Math.Rectangle     // Last dialog surface rectangle.
    currentFolder:       String             // Last browsed folder.
    recentFolders:       Array'String       // Recently accepted folders, most recent first.
    nameColumnWidth:     s32 = 220          // Last width of the name column.
    modifiedColumnWidth: s32 = 130          // Last width of the modified-time column.
    sizeColumnWidth:     s32 = 90           // Last width of the size column.
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
            state.surfacePosition = .surface!.position
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

        let dlg  = FormDlg.create(notnull me.surface, options)
        let edit = dlg.form.addTextField("FOLDER NAME", "New Folder", placeholder: "Folder name")
        dlg.form.computeLayout()
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
    //
    // Without [[Gui.FileDlgOptions.title]] and [[Gui.FileDlgOptions.confirmButtonText]],
    // the surface title and the confirmation label follow the dialog mode ("Open",
    // "Save", "Select Folder"). Confirming while the name editor targets an existing
    // folder navigates into it instead of accepting.
    #[Swag.Discardable]
    func create(from: *Surface, opt: FileDlgOptions = {})->*FileDlg
    {
        Debug.assert(from != null)
        let dlg = Wnd.create'FileDlg()
        dlg.options = opt

        with let srf = dlg.createSurface(from, 100, 100, 720, 520)
        {
            .updateFlags(add: .Resizable)
            .minSize = {540, 420}

            if @countof(opt.title) do
                .setTitle(opt.title)
            else
            {
                switch #complete opt.mode
                {
                case .CreateFile:   .setTitle("Save File")
                case .SelectFile:   .setTitle("Select File")
                case .SelectFiles:  .setTitle("Select Files")
                case .SelectFolder: .setTitle("Select Folder")
                }
            }
        }

        var confirmText = opt.confirmButtonText
        if !@countof(confirmText)
        {
            switch #complete opt.mode
            {
            case .CreateFile:               confirmText = "Save"
            case .SelectFile, .SelectFiles: confirmText = "Open"
            case .SelectFolder:             confirmText = "Select Folder"
            }
        }

        dlg.addButton(confirmText, Dialog.BtnOk, true)
        dlg.addButton("Cancel", Dialog.BtnCancel)
        dlg.backgroundStyle = .Window

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
                // A name that designates an existing folder navigates instead of accepting,
                // so a pasted or typed path browses like in the platform dialogs.
                if dlg.options.mode != .SelectFolder
                {
                    let target = dlg.browser.typedFolderTarget()
                    if !target.isEmpty()
                    {
                        dlg.browser.setCurrentFolder(target.toString())
                        dlg.browser.setFileName(dlg.options.mode == .CreateFile ? dlg.options.initialName : "")
                        return false
                    }
                }

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
                    if res != Dialog.BtnYes do
                        return false
                }

                dlg.browser.noteAccepted()
            }

            return true
        }

        dlg.applyLayout()

        // Restore the saved surface placement, then make sure it still lands on a
        // visible screen area: a stale rectangle must never open the dialog off-screen.
        if opt.state and !opt.state.surfacePosition.isEmpty()
        {
            var pos = opt.state.surfacePosition
            pos.width  = Math.max(pos.width, srf.minSize.x)
            pos.height = Math.max(pos.height, srf.minSize.y)
            srf.setPosition(pos)
            srf.constrainPositionToScreen(topLeft: true, margin: 10)
        }
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
