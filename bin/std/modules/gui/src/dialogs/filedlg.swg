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
        showLocationsPane              = true           // Whether to show the places row above the path field.
        showDrives                     = true           // Whether the places include mounted drives under More Places.
        mode:              FileDlgMode = SelectFile     // Accepted selection kind.
        filters:           Array'{ name: string, extensions: string }     // Named extension filters; empty means all files.
        shortcuts:         Array'{ type: Core.Env.SpecialDirectory, name: string }     // Locations prioritized on the row; built-in user folders not listed here stay under More Places.
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

    // Asks for a new folder in the folder the box shows, creates it, and puts its name in the name field.
    mtd onNewFolder()
    {
        let name = FileDlg.askNewFolderName(unwrap .surface, .browser.currentFolder, .browser.displayPath())
        if name.isEmpty() do
            return

        if not .browser.createFolder(name)
        {
            MessageDlg.error(.surface, strings().fileDlg_ErrFolderCreate)
            return
        }

        .browser.setFileName(name)
    }
}

impl FileDlg
{
    // Asks before a save replaces the file at `path`, in a box over `from`, and returns whether
    // the reader chose to replace it.
    //
    // The title names the file, a mono line gives its size and date when it can be read, and the
    // action is destructive. The file box asks this itself when a save names a file that exists;
    // an application that writes a file by other means asks the same question through this.
    func askReplace(from: *Surface, path: string)->bool
    {
        // A file that cannot be read leaves an empty description, and the question stands without it.
        var detail: String
        let info = catch File.info(path)
        if info.size do
            detail = Format.toString(strings().fileDlg_ReplaceDetail, Format.byteSize(info.size), info.lastWriteTime.toString(.DateTimeIsoHm))

        let box = createReplaceBox(from, Path.fileName(path) orelse path, detail)
        return box.doModal() == Dialog.BtnYes
    }

    // Builds the question [[Gui.FileDlg.askReplace]] asks about the file `name`, with `detail` as
    // its mono line, without running it.
    internal func createReplaceBox(from: *Surface, name, detail: string)->*MessageDlg
    {
        var options: MessageDlgOptions
        let title = Format.toString(strings().fileDlg_ReplaceTitle, name)
        options.title  = title.toString()
        options.detail = detail

        // The answer finishes the box at its bottom right, as in every other box.
        let box = MessageDlg.create(from, strings().fileDlg_ReplaceText, options)
        box.addButton(strings().dlg_Cancel, Dialog.BtnCancel)
        box.addButton(strings().fileDlg_BtnReplace, Dialog.BtnYes, true).setForm(.Destructive)
        box.adaptSizeToMessage()
        return box
    }

    // Asks for the name of a new folder inside `folder`, in a box over `from`, and returns it; an
    // empty name when the reader cancels.
    //
    // `place` says where the folder goes the way the reader reads it — the file box passes its
    // breadcrumb. The box refuses an empty name, a name a folder cannot have and a folder that
    // already exists, and creates nothing: the caller does, once it has the name.
    func askNewFolderName(from: *Surface, folder, place: string)->String
    {
        let box  = createNewFolderBox(from, place)
        let dlg  = box.dlg
        let edit = box.edit

        // The box answers before this call returns, so the closure may borrow `folder`.
        dlg.validateResult = func|dlg, folder, edit|(_, btnid)
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

            let path = Path.combine(folder, folderName.toString())
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
            return {}

        var result = String.from(edit.text())
        result.trim()
        return result
    }

    // Builds the form [[Gui.FileDlg.askNewFolderName]] asks with, the folder going to `place`,
    // its proposed name chosen, without running it.
    internal func createNewFolderBox(from: *Surface, place: string)->{ dlg: *FormDlg, edit: *EditBox }
    {
        var options: FormDlgOptions
        options.title = strings().fileDlg_NewFolderTitle
        options.width = cast(s32, MessageDlg.MinMessageWidth)

        options.confirmButtonText = strings().fileDlg_BtnCreate

        // The box fits what it holds, so the line saying where the folder goes is never cut.
        let dlg      = FormDlg.create(from, options)
        let location = Format.toString(strings().fileDlg_NewFolderWhere, place)
        let edit     = dlg.form.addTextField(strings().fileDlg_NewFolderField, strings().fileDlg_NewFolderDefault, placeholder: strings().fileDlg_NewFolderHint, help: location.toString())
        dlg.form.computeLayout()
        dlg.adaptSizeToForm()
        edit.selectAll()
        edit.setFocus()
        return {dlg, edit}
    }

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
                if dlg.options.mode == .CreateFile and
                   File.exists(selName) and
                   not FileDlg.askReplace(unwrap dlg.surface, selName.toString()) do
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
