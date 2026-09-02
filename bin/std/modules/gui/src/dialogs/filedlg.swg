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
// give the dialog a memory across runs. Closing or destroying the dialog updates it.
struct FileDlgState
{
    public
    {
        surfacePosition:     Math.Rectangle     // Last dialog surface rectangle.
        currentFolder:       String             // Last browsed folder.
        recentFolders:       Array'String       // Recently accepted folders, most recent first.
        nameColumnWidth:     s32 = 220          // Last width of the name column.
        modifiedColumnWidth: s32 = 130          // Last width of the modified-time column.
        sizeColumnWidth:     s32 = 90           // Last width of the size column.
    }
}

// Configures a [[Gui.FileDlg]] or embedded [[Gui.FileBrowserCtrl]].
struct FileDlgOptions
{
    public
    {
        title:             string      = ""                                            // Surface title, or empty for a mode-specific title.
        confirmButtonText: string      = ""                                            // Confirmation button label, or empty for the localized OK.
        initialFolder:     string      = ""                                            // Initially browsed folder, when non-empty.
        initialName:       string      = ""                                            // Initial file-name editor contents.
        showLocationsPane              = true                                          // Whether to show shortcuts and drives.
        mode:              FileDlgMode = SelectFile                                    // Accepted selection kind.
        filters:           Array'{ name: string, extensions: string }                  // Named extension filters; empty means all files.
        shortcuts:         Array'{ type: Core.Env.SpecialDirectory, name: string }     // Locations shown in the shortcuts pane; empty uses common user folders.
        state:             #null *FileDlgState                                         // Optional borrowed state captured when the modal closes and on destruction.
    }
}

// Thin modal wrapper around the reusable 'FileBrowserCtrl' composite.
struct FileDlg
{
    public using dialog: Dialog     // Embedded dialog state.

    public readonly
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
        // The browser saves the folder and column widths in its own destruction event. At this
        // point its child tree may already be gone, so only the dialog-owned rectangle is read.
        let state = .options.state
        if state do
            state.surfacePosition = .surface!.position
    }
}

private impl FileDlg
{
    mtd saveState()
    {
        .browser.saveState()

        // The browser saves the folder and column widths; the dialog owns the position.
        let state = .options.state
        if state do
            state.surfacePosition = .surface!.position
    }

    mtd onNewFolder()
    {
        var options: FormDlgOptions
        options.title  = strings().fileDlg_NewFolderTitle
        options.width  = 440
        options.height = 220

        let dlg  = FormDlg.create(me .surface!, options)
        let edit = dlg.form.addTextField(strings().fileDlg_NewFolderField, strings().fileDlg_NewFolderDefault, placeholder: strings().fileDlg_NewFolderHint)
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
                MessageDlg.error(dlg.surface!, strings().fileDlg_ErrFolderName)
                edit.selectAll()
                edit.setFocus()
                return false
            }

            let path = Path.combine(browser.currentFolder, folderName.toString())
            if Directory.exists(path)
            {
                MessageDlg.error(dlg.surface!, strings().fileDlg_ErrFolderExists)
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
            MessageDlg.error(.surface!, strings().fileDlg_ErrFolderCreate)
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

            if opt.title.count do
                .setTitle(opt.title)
            else
            {
                switch #complete opt.mode
                {
                case .CreateFile:   .setTitle(strings().fileDlg_TitleSaveFile)
                case .SelectFile:   .setTitle(strings().fileDlg_TitleSelectFile)
                case .SelectFiles:  .setTitle(strings().fileDlg_TitleSelectFiles)
                case .SelectFolder: .setTitle(strings().fileDlg_TitleSelectFolder)
                }
            }
        }

        var confirmText = opt.confirmButtonText
        if !confirmText.count
        {
            switch #complete opt.mode
            {
            case .CreateFile:               confirmText = strings().fileDlg_BtnSave
            case .SelectFile, .SelectFiles: confirmText = strings().fileDlg_BtnOpen
            case .SelectFolder:             confirmText = strings().fileDlg_TitleSelectFolder
            }
        }

        dlg.addButton(confirmText, Dialog.BtnOk, true)
        dlg.addButton(strings().dlg_Cancel, Dialog.BtnCancel)

        // Host the reusable browser composite. It carries its own grounds and its own edge
        // paddings, so the body it sits in keeps none of the dialog inset around it.
        with dlg.browser = FileBrowserCtrl.create(dlg.createContentView(inset: false), opt)
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
                    let res = MessageDlg.confirm(dlg.surface!, strings().fileDlg_ReplaceTitle, strings().fileDlg_ReplaceText)
                    if res != Dialog.BtnYes do
                        return false
                }

                dlg.browser.noteAccepted()
            }

            // Capture while every child is still alive. A modal backend may release its native
            // tree as soon as the result exits the loop, before control returns to the caller.
            dlg.saveState()
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
