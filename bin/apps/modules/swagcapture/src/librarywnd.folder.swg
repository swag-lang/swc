impl LibraryWnd
{
    // Names the page after the folder it now shows, and chooses that folder's tab.
    mtd updateFolderMode()
    {
        .updateTitle()
        .updateFolderTabs()
        .applyLayout()
    }

    // Opens an ordinary folder for browsing, or makes it the persistent root where new
    // captures are stored. Images already present are indexed as read-only image items.
    mtd chooseFolder(makeLibrary: bool)
    {
        let initialFolder = makeLibrary ? Library.getFolder() : .currentFolder()
        var options: FileDlgOptions
        options.mode          = .SelectFolder
        options.state         = &.main.libraryFolderDlgState
        options.initialFolder = initialFolder
        options.title         = makeLibrary ? appStrings().dlg_TitleChooseLibrary : appStrings().dlg_TitleBrowseFolder

        let dialog = FileDlg.create(unwrap .main.surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return

        let folder = dialog.selectedPath()
        if makeLibrary do
            .setLibraryFolder(folder)
        else do
            .navigateFolder(folder)
    }

    // Makes `folder` the persistent library root, the default folder when it is empty, and
    // shows it from its top level. The choice is kept only when the folder can be used.
    mtd setLibraryFolder(folder: String)
    {
        discard catch g_Library.setFolder(folder)
        {
            MessageDlg.error(unwrap .main.surface, appStrings().msg_FailedOpenLibrary, Swag.err)
            return
        }

        .main.libraryFolder = folder
        .curFolder.clear()
        .trashMode = false
        .view.filterYear, .view.filterMonth, .view.filterDay = 0
        .filledOnce = false
        .fill()
        .updateFolderMode()
        .main.saveAppState()
    }

    // Shows the folder menu under `btn`: open, browse, or choose the library folder, and the
    // recycle bin.
    mtd showFolderMenu(btn: *IconButton)
    {
        with let menu = MenuCtrl.createPopup(me, owner: me)
        {
            .addItem(appStrings().act_OpenLibraryFolder, "capture.library.root")
            .addSeparator()
            .addItem(appStrings().act_BrowseFolder, "capture.library.browse")
            .addItem(appStrings().act_ChooseLibraryFolder, "capture.library.choose")
            .addItem(appStrings().act_UseDefaultLibrary, "capture.library.default")
            .addSeparator()
            .addItem(ActionLibTrash.Toggle)
            .addItem(ActionLibTrash.Empty)
        }

        let result = menu.doModal(btn, autoDestroy: true)
        if not result do
            return
        switch result
        {
        case "capture.library.root":    .navigateFolder(Library.getFolder())
        case "capture.library.browse":  .chooseFolder(false)
        case "capture.library.choose":  .chooseFolder(true)
        case "capture.library.default": .setLibraryFolder("")
        }
    }

    // Switches between the normal library and the recycle bin: both are just folders, so
    // this is a folder navigation to the Swag Capture folder or its recycle bin.
    mtd setTrashMode(trash: bool)
    {
        .navigateFolder(trash ? Library.getTrashFolder() : Library.getFolder())
    }

    // Returns the real on-disk folder the library is showing: the Swag Capture folder by
    // default, its recycle bin, or any folder navigated to from a tab or the lens.
    mtd currentFolder()->String
    {
        if .curFolder.isEmpty() do
            return Library.getFolder()
        return .curFolder
    }

    // Navigates the library to a folder chosen from its tabs or from the lens. The Swag Capture
    // folder keeps its full features (date filters, delete-to-trash); the recycle bin and any
    // other folder are simply browsed by listing supported items.
    mtd navigateFolder(path: String)
    {
        if .currentFolder() == path do
            return

        .curFolder = path
        .trashMode = Library.getTrashFolder() == path
        catch .view.fill()
        .updateFolderMode()
        .invalidate()
    }
}
