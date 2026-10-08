impl LibraryWnd
{
    mtd updateFolderMode()
    {
        if .sideBar == null do
            return
        if .currentFolder() == Library.getFolder() do
            .sideBar.show()
        else do
            .sideBar.hide()
        .applyLayout()
        .layoutSidebarColumns()
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

        let dialog = FileDlg.create(.main.surface!, options)
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
        discard catch g_Library.setFolder(folder) as err
        if err != null
        {
            MessageDlg.error(.main.surface!, appStrings().msg_FailedOpenLibrary, err)
            return
        }

        .main.libraryFolder = folder
        .curFolder.clear()
        .trashMode = false
        .view.filterYear, .view.filterMonth, .view.filterDay = 0
        .listCtrl.clear()
        .fill()
        .updateFolderMode()
        .updateBreadcrumb()
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
    // default, its recycle bin, or any folder navigated to from the breadcrumb.
    mtd currentFolder()->String
    {
        if .curFolder.isEmpty() do
            return Library.getFolder()
        return .curFolder
    }

    // Rebuilds the breadcrumb from the current folder path: one level per path component,
    // each carrying its full path in `tag` so navigation can act on it.
    mtd updateBreadcrumb()
    {
        if .breadcrumb == null do
            return
        .breadcrumb.clear()

        let trashFolder = Library.getTrashFolder()

        // Collect each ancestor's full path, leaf first, by walking up the directory chain.
        // Keep `folder` bound to a local so the slice `p` (and every getDirectoryName slice
        // derived from it) stays backed by live memory for the whole walk.
        //
        // The walk stops at the library folder instead of climbing to the drive: this bar
        // navigates captures, and a reader has no use for the three directories that happen
        // to sit above them on this machine.
        let folder  = .currentFolder()
        let libRoot = Library.getFolder()
        var fulls: Array'String
        var p       = folder.toString()
        while p.count != 0
        {
            fulls.add(p)
            if p == libRoot.toString() do
                break
            let parent = Path.directoryName(p)
            if parent == null or parent.count == 0 or parent == p do
                break
            p = parent
        }

        // Add levels root-first.
        for full in fulls.reversed()
        {
            let fp = full.toString()
            var nm = Path.fileName(fp) orelse ""
            if nm.count == 0 do
                nm = fp

            // At the row size of the chart, like every other glyph of this window. A breadcrumb
            // draws the icon it is handed at the size it is handed, and the theme default is the
            // 24 of a command bar — which next to a path reads as a button that lost its button.
            let isTrash = trashFolder == fp
            let icon    = isTrash ? .theme().icon(.Remove, themeRowIconSize(.themeMetrics())) : .theme().icon(.OpenFile, themeRowIconSize(.themeMetrics()))
            .breadcrumb.addItem(nm, icon, tag: fp)
        }
    }

    // Fills a level's drop-down with the real sub-directories of that level's folder.
    mtd fillBreadcrumbMenu(bc: *BreadcrumbCtrl, index: u64, menu: *MenuCtrl)
    {
        if index >= bc.items.count do
            return
        let folder = bc.items[index].tag.toString()

        let dirs = catch Directory.enumerateDirectories(folder) as err
        if err != null do
            return

        // Mark the child that is currently on the path (the level shown to the right).
        var currentChild: String
        if index + 1 < bc.items.count do
            currentChild = bc.items[index + 1].tag.toString()

        // Own the paths (reserved so no reallocation moves them) and hand the menu slices
        // into them; the menu keeps ids as non-owning slices used after this returns.
        .menuPaths.clear()
        .menuPaths.reserve(dirs.count)
        for d in dirs do
            .menuPaths.add(d.fullName)

        for d, i in dirs
        {
            let name = Path.fileName(d.fullName) orelse d.fullName.toString()
            menu.addItem(name, .menuPaths[i], checked: d.fullName == currentChild)
        }
    }

    // Navigates the library to a folder chosen from the breadcrumb (its body or a chevron
    // entry). The Swag Capture folder keeps its full features (date sidebar, delete-to-trash);
    // the recycle bin and any other folder are simply browsed by listing supported items.
    mtd navigateFolder(path: String)
    {
        if .currentFolder() == path do
            return

        .curFolder = path
        .trashMode = Library.getTrashFolder() == path
        catch .view.fill()
        .updateFolderMode()
        .invalidate()
        .updateBreadcrumb()
    }
}
