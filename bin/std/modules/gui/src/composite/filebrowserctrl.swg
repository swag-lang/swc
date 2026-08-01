#global public

using Core, File, Directory

// Embeds location navigation, a sortable file list, and name and type editors.
struct FileBrowserCtrl
{
    using wnd: Wnd     // Embedded wnd state.

    readonly
    {
        treeCtrl:      #null *ListCtrl      // Optional shortcuts and drives list.
        options:       FileDlgOptions       // Effective browsing and selection options.
        currentFolder: String               // Normalized folder currently displayed.

        #[Swag.Late]
        {
            listCtrl:  *ListCtrl       // Sortable file and folder list.
            comboPath: *ComboBox       // Current-folder and ancestor selector.
            editFile:  *EditBox        // File or folder name editor.
            comboType: *ComboBox       // Active file-type filter selector.
        }
    }

    sigAccepted:           SigArray'func||(*FileBrowserCtrl)     // Emitted when the current selection is activated.
    sigFolderChanged:      SigArray'func||(*FileBrowserCtrl)     // Emitted after [[Gui.FileBrowserCtrl.currentFolder]] changes.
    sigNewFolderRequested: SigArray'func||(*FileBrowserCtrl)     // Emitted when the user requests a new folder.

    internal
    {
        treePathStr:    Array'String       // Folder paths backing `treeCtrl` rows.
        comboPathStr:   Array'String       // Folder paths backing `comboPath` entries.
        currentEntries: Array'FileInfo     // Filesystem entries backing visible rows.
    }
}

impl IWnd for FileBrowserCtrl
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        if .options.state
        {
            let state = notnull me.options.state
            state.currentFolder       = me.currentFolder
            state.nameColumnWidth     = cast() me.listCtrl.header.itemWidthForColumn(0)
            state.modifiedColumnWidth = cast() me.listCtrl.header.itemWidthForColumn(1)
        }
    }
}

private impl FileBrowserCtrl
{
    mtd folderUp()
    {
        if .comboPathStr.count > 1 do
            .setCurrentFolder(.comboPathStr[1].toString())
    }

    mtd fillComboPath()
    {
        .comboPath.clear()
        .comboPathStr.clear()

        let all = Tokenize.split(.currentFolder.toString(), '/'rune)
        for #reverse [i] in @countof(all)
        {
            var str: String
            for [j] in i + 1
            {
                str += all[j]
                str += '/'u8
            }

            .comboPathStr.add(str)

            let one  = all[i]
            var icon = .app().directoryIcon(one)
            icon.color = Pixel.Argb.White
            .comboPath.addItem(one, icon: icon)
        }

        .comboPath.setSelectedIndex(0, notify: false)
    }

    mtd fillFileListFolders()
    {
        let treeCtrl = notnull .treeCtrl
        var l        = treeCtrl.createLine("Shortcuts")
        l.separator = true

        for v in .options.shortcuts
        {
            let c    = Env.getSpecialDirectory(v.type)
            var icon = .app().specialDirectoryIcon(v.type, true)
            icon.color       = Pixel.Argb.White
            l                = treeCtrl.createLine(v.name, icon)
            l.userData0      = cast(#null *void) .treePathStr.count
            l.leftTextMargin = 10
            .treePathStr.add(c)
        }

        l           = treeCtrl.createLine("Drives")
        l.separator = true

        let volumes = catch Directory.drives()
        for &v in volumes
        {
            v.removeBack()
            var icon = .app().directoryIcon(v, true)
            icon.color       = Pixel.Argb.White
            l                = treeCtrl.createLine(v.toString(), icon)
            l.userData0      = cast(#null *void) .treePathStr.count
            l.leftTextMargin = 10
            .treePathStr.add(v)
        }

        treeCtrl.sigSelectionChanged += func|fileBrowser = me|(list)
        {
            var line = list.selectedLine()
            if !line do
                return
            var idx = cast(u64) line.userData0
            fileBrowser.setCurrentFolder(fileBrowser.treePathStr[idx].toString())
        }
    }

    mtd createFileList(view: *Wnd)
    {
        with me.listCtrl = ListCtrl.createMultiColumns(view)
        {
            .setSelectionMode(me.options.mode == FileDlgMode.SelectFiles ? ListSelectionMode.Multi : ListSelectionMode.Single)
            .dockStyle       = .Center
            .margin.z        = 10
            .updateFlags(.HotTrack)
            .backgroundStyle = .View

            // NOTE: both branches are kept explicitly f32. A runtime conditional
            // whose unified result is integer, fed to an f32 parameter, is currently
            // mis-lowered to a bit-reinterpret (see reference_conditional_int_to_float_miscompile).
            .addColumn("Name", me.options.state ? cast(f32) me.options.state.nameColumnWidth : 200.0)
            .addColumn("Modified", me.options.state ? cast(f32) me.options.state.modifiedColumnWidth : 150.0)
            .header.form = .Transparent
            .header.style.addStyleSheetColors("headerItem_Separator $lighterMedium")
            .scrollWnd.style.addStyleSheetColors("scrollBar_Bk $view_Bk")
            .sigKeyPressed += func|fileBrowser = me|(list, evt)
            {
                switch evt.key
                {
                case .Back:
                    fileBrowser.folderUp()

                case .Enter:
                    let l = list.focusedLine()
                    if !l do
                        break
                    let fi = notnull cast(#null const *FileInfo) l.userData0
                    if fi.isDirectory()
                    {
                        fileBrowser.setCurrentFolder(fi.fullname)
                    }
                    elif fileBrowser.options.mode != .SelectFolder
                    {
                        fileBrowser.sigAccepted.call(fileBrowser)
                        list.setFocus()
                    }
                }
            }
            .sigLeftDoubleClicked += func|fileBrowser = me|(list, pt)
            {
                var l = list.selectedLine()
                if !l do
                    return
                var fi = notnull cast(#null const *FileInfo) l.userData0
                if fi.isDirectory()
                {
                    fileBrowser.setCurrentFolder(fi.fullname)
                }
                elif fileBrowser.options.mode != .SelectFolder
                {
                    fileBrowser.sigAccepted.call(fileBrowser)
                    list.setFocus()
                }
            }
            .sigSelectionChanged += func|fileBrowser = me|(list)
            {
                var sel = list.selectedLines()
                var txt: String
                for l in sel
                {
                    let fi = notnull cast(#null const *FileInfo) (notnull l).userData0
                    if fi.isDirectory()
                    {
                        if fileBrowser.options.mode != .SelectFolder do
                            continue
                    }
                    else
                    {
                        if .options.mode == .SelectFolder do
                            continue
                    }

                    if !txt.isEmpty() do
                        txt += ";"
                    txt     += Path.fileName(fi.fullname)
                }

                if !txt.isEmpty() do
                    fileBrowser.editFile.setText(txt)
            }
            .compareLines = func(l1, l2, col, down)
            {
                if !l1 or !l2 do
                    return 0

                var fi1 = notnull cast(#null *FileInfo) l1.userData0
                var fi2 = notnull cast(#null *FileInfo) l2.userData0
                if fi1.isDirectory() and !fi2.isDirectory() do
                    return -1
                if !fi1.isDirectory() and fi2.isDirectory() do
                    return 1
                switch col
                {
                case 0: return (fi1.fullname <=> fi2.fullname) * (down ? -1 : 1)
                case 1: return (fi1.lastWriteTime <=> fi2.lastWriteTime) * (down ? -1 : 1)
                }

                return 0
            }
        }
    }
}

impl FileBrowserCtrl
{
    // Creates an embedded file browser inside `parent`.
    #[Swag.Discardable]
    func create(parent: *Wnd, opt: FileDlgOptions = {}, position: Math.Rectangle = {})->*FileBrowserCtrl
    {
        Debug.assert(parent != null)
        let fileBrowser = Wnd.create'FileBrowserCtrl(parent, "", position)
        fileBrowser.options         = opt
        fileBrowser.backgroundStyle = .Window

        // Panes
        ////////////////////////
        if opt.showLocationsPane
        {
            with fileBrowser.treeCtrl = ListCtrl.createSimple(fileBrowser, {0, 0, 170})
            {
                .dockStyle       = .Left
                .updateFlags(.HotTrack)
                .setLineHeight(28)
                .setLeftTextMargin(8)
                .backgroundStyle = .Dialog
                .scrollWnd.style.addStyleSheetColors("scrollBar_Bk $view_Bk")
                fileBrowser.fillFileListFolders()
            }
        }

        fileBrowser.createFileList(fileBrowser)

        // Top
        ////////////////////////
        with let viewTop = Wnd.create'Wnd(fileBrowser, {0, 0, 0, 50})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Window
            .padding.x       = 10
            .padding.z       = 10
            .padding.y       = 8
            .padding.w       = 8
        }

        fileBrowser.applyLayout()

        if opt.mode == .CreateFile or opt.mode == .SelectFolder
        {
            let btn = PushButton.create(viewTop, "New Folder", {0, 0, 90})
            with btn
            {
                .dockStyle  = .Right
                .margin.x   = 10
                .sigPressed += func|fileBrowser|(btn) { fileBrowser.sigNewFolderRequested.call(fileBrowser) }
            }
        }

        with fileBrowser.comboPath = ComboBox.create(viewTop)
        {
            .dockStyle  = .Center
            .sigChanged += func|fileBrowser|(combo, idx) { fileBrowser.setCurrentFolder(fileBrowser.comboPathStr[idx]) }
        }

        // Bottom
        ////////////////////////
        let viewBottom = Wnd.create'Wnd(fileBrowser, {0, 0, 0, 90})
        viewBottom.dockStyle       = .Bottom
        viewBottom.backgroundStyle = .Window
        fileBrowser.applyLayout()

        with fileBrowser.editFile = EditBox.create(viewBottom, "", {105, 10, viewBottom.position.width - (105 + 15)})
        {
            .anchorStyle = .Width
        }

        with fileBrowser.comboType = ComboBox.create(viewBottom, {105, 45, viewBottom.position.width - (105 + 15)})
        {
            .anchorStyle = .Width
            if opt.mode == .SelectFolder do
                .addItem("Folders")
            else do
                for f, [idx] in opt.filters do
                    .addItem(f.name, userData0: cast(#null *void) idx)
            .setSelectedIndex(0)
            .sigChanged += func|fileBrowser|(c, idx) { fileBrowser.fillFileList() }
        }

        let nameLbl0 = opt.mode == .SelectFolder ? "Folder Name" : "File Name"
        let label0   = Label.create(viewBottom, nameLbl0, {5, 10, 80, fileBrowser.editFile.position.height})
        label0.setTextAlignment(.Right, .Center)
        let label1 = Label.create(viewBottom, "Type", {5, 45, 80, fileBrowser.comboType.position.height})
        label1.setTextAlignment(.Right, .Center)

        with fileBrowser
        {
            if opt.initialFolder do
                .setCurrentFolder(opt.initialFolder)
            elif opt.state and !opt.state.currentFolder.isEmpty() do
                .setCurrentFolder(opt.state.currentFolder)
            .listCtrl.sort(0)
            .editFile.setText(opt.initialName)
            if opt.mode == .CreateFile
            {
                .editFile.selectAll()
                .editFile.setFocus()
            }
            else do
                .listCtrl.setFocus()
        }

        // Default to the first shortcut/drive when nothing else selected a folder.
        if fileBrowser.currentFolder.isEmpty() and fileBrowser.treeCtrl do
            fileBrowser.treeCtrl.selectLine(0)

        return fileBrowser
    }

    // Navigates to `folder`; returns false when it does not name an existing directory.
    #[Swag.Discardable]
    mtd setCurrentFolder(folder: string)->bool
    {
        if !@countof(folder) or !Directory.exists(notnull folder) do
            return false

        var normalized = String.from(folder)
        Path.normalize(&normalized)

        if normalized.back() == '/' do
            normalized.removeBack()
        if .currentFolder == normalized do
            return true

        .currentFolder = #move normalized

        .fillFileList()
        .fillComboPath()
        .sigFolderChanged.call(me)
        return true
    }

    // Refresh the file list of the current folder.
    mtd refresh()
    {
        .fillFileList()
    }

    // Fills the file list from the current folder, applying the active filter.
    private mtd fillFileList()
    {
        .listCtrl.clear()

        with var options: EnumerationOptions
        {
            .skipAttributes  = .Hidden
            .wantFiles       = me.options.mode != .SelectFolder
            .wantDirectories = true
            .recurse         = false
        }

        .currentEntries = catch Directory.enumerate(.currentFolder, options)

        // SelectFolder mode has no file filters (it lists folders only): avoid
        // indexing the empty 'filters' array.
        var filterExtensions: #null string
        if me.options.mode != .SelectFolder and .options.filters.count
        {
            let item        = notnull .comboType.selectedItem()
            let filterIndex = cast(u64) item.userData0
            if filterIndex < .options.filters.count do
                filterExtensions = .options.filters[filterIndex].extensions
        }

        let tokens = Tokenize.split(filterExtensions orelse "", ';'rune)

        for &fi in .currentEntries
        {
            let fname = notnull Path.fileName(fi.fullname)

            // Filter
            var show = true
            if !fi.isDirectory() and @countof(filterExtensions)
            {
                show = false
                for t in tokens
                {
                    if Path.hasExtension(fname, t)
                    {
                        show = true
                        break
                    }
                }
            }

            if !show do
                continue

            // Content
            var icon = .app().fileOrDirectoryIcon(fname, fi.isDirectory())
            icon.color = Pixel.Argb.White
            let line = .listCtrl.createLine(fname, icon)
            line.userData0 = fi
            line.setItem(1, fi.lastWriteTime.toString(.DateTimeIso))
        }

        .listCtrl.computeLayout()
        .listCtrl.sort()
    }

    // Creates a folder inside [[Gui.FileBrowserCtrl.currentFolder]] and refreshes the list on success.
    mtd createFolder(name: string)->bool
    {
        if .currentFolder.isEmpty() or !Path.isValidFileName(name) do
            return false
        let path = Path.combine(.currentFolder, name)
        catch Directory.create(path) else do
            return false
        .fillFileList()
        return true
    }

    // Changes the contents of the file or folder name editor.
    mtd setFileName(name: #null string)
    {
        .editFile.setText(name)
    }

    // Returns the current contents of the file or folder name editor.
    mtd fileName()->string => .editFile.text()

    // Returns the first selected full path, or an empty string when selection is invalid.
    mtd selectedPath()->String
    {
        let sel = .selectedPaths()
        if sel.isEmpty() do
            return String.from("")
        return sel.front()
    }

    // Returns all selected full paths in display order.
    mtd selectedPaths()->Array'String
    {
        var result: retval

        // SelectFolder mode has no filters: do not index the empty 'filters' array.
        var filterExtensions: #null string
        if me.options.mode != .SelectFolder and .options.filters.count
        {
            let item        = notnull .comboType.selectedItem()
            let filterIndex = cast(u64) item.userData0
            if filterIndex < .options.filters.count do
                filterExtensions = .options.filters[filterIndex].extensions
        }

        let tokens = Tokenize.split(.editFile.text(), ';'rune)
        for t in tokens
        {
            // Be sure this is a valid file/folder name
            var t1 = String.from(t)
            t1.trim()
            if t1.isEmpty() do
                continue
            if .options.mode == .SelectFolder and !Path.isValidPathName(t1.toString()) do
                continue
            if .options.mode != .SelectFolder and !Path.isValidFileName(t1.toString()) do
                continue

            // Get the full name
            var val = Path.combine(.currentFolder, t1.toString())

            // Append extension if not done by the user
            if .options.mode != .SelectFolder and @countof(filterExtensions) and !Path.hasExtension(val, notnull filterExtensions)
            {
                let exts = Tokenize.split(notnull filterExtensions, ';'rune)
                val += exts[0]
            }

            result.add(val)
        }

        return result
    }
}
