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
        title:             string      = ""             // Surface title, or empty for a mode-specific title.
        confirmButtonText: string      = ""             // Confirmation button label, or empty for the localized OK.
        initialFolder:     string      = ""             // Initially browsed folder, when non-empty.
        initialName:       string      = ""             // Initial file-name editor contents.
        showLocationsPane              = true           // Whether to show the places, as text tabs over the path field.
        showDrives                     = true           // Whether the places include the mounted drives after the shortcuts.
        mode:              FileDlgMode = SelectFile     // Accepted selection kind.
        filters:           Array'{ name: string, extensions: string }     // Named extension filters; empty means all files.
        shortcuts:         Array'{ type: Core.Env.SpecialDirectory, name: string }     // Locations shown in the shortcuts pane; empty uses common user folders.
        state:             *FileDlgState?               // Optional borrowed state captured when the modal closes and on destruction.
    }
}

// Modal file dialog hosting the reusable [[Gui.FileBrowserCtrl]] composite.
struct FileDlg
{
    public using dialog: Dialog     // Embedded dialog state.

    public readonly
    {
        late browser: *FileBrowserCtrl     // Embedded browser control.
        options:      FileDlgOptions       // Effective dialog options.
    }
}

impl IWnd for FileDlg
{
    mtd impl onDestroyEvent(_: *DestroyEvent)
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

    // Names the choice in the primary action: the folder a folder box picks, how many files a multiple box opens.
    mtd nameChoice(confirmText: string)
    {
        var button: *PushButton?
        for btn in .buttons where btn.id == Dialog.BtnOk do
            button = btn
        if not button do
            return

        var text = String.from(confirmText)
        switch .options.mode
        {
        case .SelectFolder:
            let name = .browser.editFile.text()
            if name.count do
                text = Format.toString(strings().fileDlg_BtnChooseNamed, name)
        case .SelectFiles:
            let count = .browser.selectedPaths().count
            if count > 1 do
                text = Format.toString(strings().fileDlg_BtnOpenCount, count)
        }

        if button.text() == text.toString() do
            return
        button.setText(text.toString())
        button.fitWidthToLabel(button.position.width)
        .buttonBar.computeLayout()
        .applyLayout()
    }

    // Asks before a save replaces `path`: the title names the file, a mono line gives its size and date, and the action is destructive.
    mtd confirmReplace(path: string)->bool
    {
        // The options borrow their strings, so the strings live here for as long as the box.
        let title = Format.toString(strings().fileDlg_ReplaceTitle, Path.fileName(path) orelse path)
        // A file that cannot be read leaves an empty description, and the question stands without it.
        var detail: String
        let info = catch File.info(path)
        if info.size do
            detail = Format.toString(strings().fileDlg_ReplaceDetail, Format.byteSize(info.size), info.lastWriteTime.toString(.DateTimeIsoHm))

        var options: MessageDlgOptions
        options.title  = title.toString()
        options.detail = detail.toString()

        let box = MessageDlg.create(unwrap .surface, strings().fileDlg_ReplaceText, options)
        box.addButton(strings().fileDlg_BtnReplace, Dialog.BtnYes, true).setForm(.Destructive)
        box.addButton(strings().dlg_Cancel, Dialog.BtnCancel)
        box.adaptSizeToMessage()
        return box.doModal() == Dialog.BtnYes
    }

    mtd onNewFolder()
    {
        var options: FormDlgOptions
        options.title  = strings().fileDlg_NewFolderTitle
        options.width  = cast(s32, MessageDlg.MinMessageWidth)
        options.height = 220

        options.confirmButtonText = strings().fileDlg_BtnCreate

        let dlg   = FormDlg.create(unwrap .surface, options)
        let place = Format.toString(strings().fileDlg_NewFolderWhere, .browser.displayPath())
        let edit  = dlg.form.addTextField(strings().fileDlg_NewFolderField, strings().fileDlg_NewFolderDefault, placeholder: strings().fileDlg_NewFolderHint, help: place.toString())
        dlg.form.computeLayout()
        edit.selectAll()
        edit.setFocus()

        dlg.validateResult = func|dlg, browser = me.browser, edit|(_, btnid)
        {
            if btnid != Dialog.BtnOk do
                return true

            var folderName: String = edit.text()
            folderName.trim()
            if folderName.isEmpty()
            {
                edit.selectAll()
                edit.setFocus()
                return false
            }

            if not Path.isValidFileName(folderName)
            {
                MessageDlg.error(unwrap dlg.surface, strings().fileDlg_ErrFolderName)
                edit.selectAll()
                edit.setFocus()
                return false
            }

            let path = Path.combine(browser.currentFolder, folderName.toString())
            if Directory.exists(path)
            {
                MessageDlg.error(dlg.surface, strings().fileDlg_ErrFolderExists)
                edit.selectAll()
                edit.setFocus()
                return false
            }

            return true
        }

        if dlg.doModal() != Dialog.BtnOk do
            return

        if not .browser.createFolder(edit.text())
        {
            MessageDlg.error(.surface, strings().fileDlg_ErrFolderCreate)
            return
        }

        .browser.setFileName(edit.text())
    }
}

impl FileDlg
{
    // Creates a file dialog on its own surface, centered on `from` or placed where [[Gui.FileDlgOptions.state]] last left it.
    //
    // Without [[Gui.FileDlgOptions.title]] and [[Gui.FileDlgOptions.confirmButtonText]],
    // the surface title and the confirmation label follow the dialog mode ("Open",
    // "Save", "Select Folder"). Confirming while the name editor targets an existing
    // folder navigates into it instead of accepting, and saving over an existing file asks
    // first. Run it with [[Gui.Dialog.doModal]]; when the result is `Dialog.BtnOk`, read
    // [[Gui.FileDlg.selectedPath]] or [[Gui.FileDlg.selectedPaths]].
    #[Swag.Discardable]
    func create(from: *Surface, opt: FileDlgOptions = {})->*FileDlg
    {
        Swag.assert(from != null)
        let dlg = Wnd.create'FileDlg()
        dlg.options = opt

        let srf = dlg.createSurface(from, 100, 100, 720, 560, .Resizable)
        dlg.setMinSize(540, 420)
        if opt.title.count
        {
            dlg.setTitle(opt.title)
        }
        else
        {
            switch #complete opt.mode
            {
            case .CreateFile:   dlg.setTitle(strings().fileDlg_TitleSaveFile)
            case .SelectFile:   dlg.setTitle(strings().fileDlg_TitleSelectFile)
            case .SelectFiles:  dlg.setTitle(strings().fileDlg_TitleSelectFiles)
            case .SelectFolder: dlg.setTitle(strings().fileDlg_TitleSelectFolder)
            }
        }

        var confirmText = opt.confirmButtonText
        if not confirmText.count
        {
            switch #complete opt.mode
            {
            case .CreateFile:   confirmText = strings().fileDlg_BtnSave
            case .SelectFile, .SelectFiles: confirmText = strings().fileDlg_BtnOpen
            case .SelectFolder: confirmText = strings().fileDlg_TitleSelectFolder
            }
        }

        dlg.addButton(confirmText, Dialog.BtnOk, true)
        dlg.addButton(strings().dlg_Cancel, Dialog.BtnCancel)

        // Host the reusable browser composite in the body, inside the inset every box keeps.
        with dlg.browser = FileBrowserCtrl.create(dlg.createContentView(), opt)
        {
            .dockStyle   = .Center
            .sigAccepted += func|fileDlg = dlg|(_) { fileDlg.closeWithResult(Dialog.BtnOk) }
            .sigNewFolderRequested += func|fileDlg = dlg|(_) { fileDlg.onNewFolder() }
        }

        // The type filter and the line of what is chosen take the quiet bottom-left slot of the box,
        // and the primary action names the choice when there is one to name.
        dlg.setLeadingControl(dlg.browser.detachFoot())
        dlg.browser.sigChoiceChanged += func|dlg, confirmText|(_) { dlg.nameChoice(confirmText) }
        dlg.nameChoice(confirmText)

        dlg.validateResult = func|dlg|(_, id)
        {
            if id == Dialog.BtnOk
            {
                // A name that designates an existing folder navigates instead of accepting,
                // so a pasted or typed path browses like in the platform dialogs.
                if dlg.options.mode != .SelectFolder
                {
                    let target = dlg.browser.typedFolderTarget()
                    if not target.isEmpty()
                    {
                        dlg.browser.setCurrentFolder(target.toString())
                        dlg.browser.setFileName(dlg.options.mode == .CreateFile ? dlg.options.initialName : "")
                        return false
                    }
                }

                if not dlg.browser.hasValidSelection()
                {
                    dlg.browser.focusNameEntry()
                    return false
                }

                let selName = dlg.browser.selectedPath()
                if dlg.options.mode == .CreateFile and File.exists(selName) and not dlg.confirmReplace(selName.toString()) do
                    return false

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
        if opt.state and not opt.state.surfacePosition.isEmpty()
        {
            var pos = opt.state.surfacePosition
            pos.width  = Math.max(pos.width, srf.minSize.x)
            pos.height = Math.max(pos.height, srf.minSize.y)
            srf.setPosition(pos)
            srf.constrainPositionToScreen(topLeft: true, margin: 10)
        }
        else
        {
            srf.center(from)
        }

        return dlg
    }

    // Returns the first selected full path, or an empty string when no valid selection exists.
    mtd selectedPath()->String => .browser.selectedPath()

    // Returns all selected full paths in display order.
    mtd selectedPaths()->Array'String => .browser.selectedPaths()
}
