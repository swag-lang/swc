#global public

using Core, File, Directory

// Stores linear string locations for back and forward navigation.
//
// Pushing a location after moving backward discards the abandoned forward branch.
struct NavigationHistory
{
    readonly
    {
        entries: Array'String         // Locations in visit order.
        index = Swag.U64.Max          // Current entry index, or [[Swag.U64.Max]] when empty.
    }
}

impl NavigationHistory
{
    // Removes every location and resets the current position.
    mtd clear()
    {
        .entries.clear()
        .index = Swag.U64.Max
    }

    // Appends `path`, discarding any forward branch after the current position.
    mtd push(path: string)
    {
        if .index != Swag.U64.Max and .entries[.index] == path do
            return
        while .index != Swag.U64.Max and .entries.count > .index + 1 do
            .entries.removeBack()
        .entries.add(String.from(path))
        .index = .entries.count - 1
    }

    // Returns whether a location exists before the current one.
    mtd canGoBack()->bool => .index != Swag.U64.Max and .index > 0

    // Returns whether a location exists after the current one.
    mtd canGoForward()->bool => .index != Swag.U64.Max and .index + 1 < .entries.count

    // Moves backward and returns the new current location.
    //
    // The caller must first check [[Gui.NavigationHistory.canGoBack]].
    mtd goBack()->String
    {
        Debug.assert(.canGoBack(), "file-browser history has no previous folder")
        .index -= 1
        return .entries[.index]
    }

    // Moves forward and returns the new current location.
    //
    // The caller must first check [[Gui.NavigationHistory.canGoForward]].
    mtd goForward()->String
    {
        Debug.assert(.canGoForward(), "file-browser history has no next folder")
        .index += 1
        return .entries[.index]
    }
}

// Embeds location navigation, a sortable file list, and name and type editors.
struct FileBrowserCtrl
{
    using wnd: Wnd     // Embedded wnd state.

    readonly
    {
        treeCtrl:      #null *ListCtrl     // Optional shortcuts and drives list.
        options:       FileDlgOptions      // Effective browsing and selection options.
        currentFolder: String              // Normalized folder currently displayed.

        #[Swag.Late]
        {
            listCtrl:      *ListCtrl       // Sortable file and folder list.
            comboPath:     *ComboBox       // Current-folder and ancestor selector.
            editFile:      *EditBox        // File or folder name editor.
            comboType:     *ComboBox       // Active file-type filter selector.
            backButton:    *PushButton     // Navigates to the previous folder.
            forwardButton: *PushButton     // Navigates to the next folder.
            upButton:      *PushButton     // Navigates to the parent folder.
            refreshButton: *PushButton     // Reloads the current folder.
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
        history:        NavigationHistory // Folder-navigation history.
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
    mtd updateNavigationState()
    {
        .backButton.enable(.history.canGoBack())
        .forwardButton.enable(.history.canGoForward())
        let parent = Path.directoryName(.currentFolder.toString()) orelse ""
        .upButton.enable(@countof(parent) != 0 and parent != .currentFolder.toString())
    }

    mtd showFolder(folder: string)->bool
    {
        if !@countof(folder) or !Directory.exists(folder) do
            return false

        var normalized = String.from(folder)
        Path.normalize(&normalized)
        if normalized.back() == '/' and normalized.length > Path.rootLength(normalized.toString()) do
            normalized.removeBack()
        if .currentFolder == normalized do
            return true

        .currentFolder = #move normalized
        .fillFileList()
        .fillComboPath()
        .sigFolderChanged.call(me)
        return true
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
            icon.color = .themeColors().label_Text
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
            icon.color       = .themeColors().label_Text
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
            .dockStyle = .Center
            .margin.z  = 10
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
                    if evt.modifiers.equals(.None)
                    {
                        if !fileBrowser.goBack() do
                            discard fileBrowser.goUp()
                    }

                case .BrowserBack:
                    discard fileBrowser.goBack()

                case .BrowserForward:
                    discard fileBrowser.goForward()

                case .BrowserRefresh, .F5:
                    fileBrowser.refresh()

                case .Left:
                    if evt.modifiers.equals(.Alt) do
                        discard fileBrowser.goBack()

                case .Right:
                    if evt.modifiers.equals(.Alt) do
                        discard fileBrowser.goForward()

                case .Up:
                    if evt.modifiers.equals(.Alt) do
                        discard fileBrowser.goUp()

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
                    txt += Path.fileName(fi.fullname)
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

        if fileBrowser.options.shortcuts.isEmpty()
        {
            fileBrowser.options.shortcuts.add({Env.SpecialDirectory.Desktop, "Desktop"})
            fileBrowser.options.shortcuts.add({Env.SpecialDirectory.UserDocuments, "Documents"})
            fileBrowser.options.shortcuts.add({Env.SpecialDirectory.UserPictures, "Pictures"})
        }
        if fileBrowser.options.mode != .SelectFolder and fileBrowser.options.filters.isEmpty() do
            fileBrowser.options.filters.add({"All Files", ""})

        // Panes
        ////////////////////////
        if fileBrowser.options.showLocationsPane
        {
            with fileBrowser.treeCtrl = ListCtrl.createSimple(fileBrowser, {0, 0, 170})
            {
                .dockStyle = .Left
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

        with fileBrowser.backButton = PushButton.create(viewTop, "Back", {0, 0, 58})
        {
            .dockStyle  = .Left
            .margin.z   = 6
            .toolTip    = "Previous folder (Alt+Left)"
            .setIcon(fileBrowser.theme().icon24(ThemeIcons24.Undo, 16))
            .sigPressed += func|fileBrowser|(btn) { discard fileBrowser.goBack() }
        }

        with fileBrowser.forwardButton = PushButton.create(viewTop, "Forward", {0, 0, 72})
        {
            .dockStyle  = .Left
            .margin.z   = 6
            .toolTip    = "Next folder (Alt+Right)"
            .setIcon(fileBrowser.theme().icon24(ThemeIcons24.Redo, 16))
            .sigPressed += func|fileBrowser|(btn) { discard fileBrowser.goForward() }
        }

        with fileBrowser.upButton = PushButton.create(viewTop, "Up", {0, 0, 46})
        {
            .dockStyle  = .Left
            .margin.z   = 10
            .toolTip    = "Parent folder (Alt+Up)"
            .setIcon(fileBrowser.theme().icon24(ThemeIcons24.Expanded, 16))
            .sigPressed += func|fileBrowser|(btn) { discard fileBrowser.goUp() }
        }

        with fileBrowser.refreshButton = PushButton.create(viewTop, "Refresh", {0, 0, 72})
        {
            .dockStyle  = .Right
            .margin.x   = 6
            .toolTip    = "Refresh (F5)"
            .setIcon(fileBrowser.theme().icon24(ThemeIcons24.Update, 16))
            .sigPressed += func|fileBrowser|(btn) { fileBrowser.refresh() }
        }

        if fileBrowser.options.mode == .CreateFile or fileBrowser.options.mode == .SelectFolder
        {
            let btn = PushButton.create(viewTop, "New Folder", {0, 0, 90})
            with btn
            {
                .dockStyle  = .Right
                .margin.x   = 10
                .toolTip    = "Create a folder in the current location"
                .setIcon(fileBrowser.theme().icon24(ThemeIcons24.Plus, 16))
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
        var formOptions: FormLayoutOptions
        formOptions.labelPlacement = .Left
        formOptions.labelWidth     = 95
        formOptions.fieldHeight    = 30
        formOptions.rowSpacing     = 5
        let form = FormLayoutCtrl.create(fileBrowser, formOptions, {0, 0, 0, 90})
        form.dockStyle       = .Bottom
        form.backgroundStyle = .Window
        form.padding         = {0, 8, 15, 8}

        let nameLbl0 = fileBrowser.options.mode == .SelectFolder ? "Folder Name" : "File Name"
        fileBrowser.editFile = EditBox.create(form, "")
        discard form.addField(nameLbl0, fileBrowser.editFile)

        with fileBrowser.comboType = ComboBox.create(form)
        {
            if fileBrowser.options.mode == .SelectFolder do
                .addItem("Folders")
            else do
                for f, [idx] in fileBrowser.options.filters do
                    .addItem(f.name, userData0: cast(#null *void) idx)
            .setSelectedIndex(0)
            .sigChanged += func|fileBrowser|(c, idx) { fileBrowser.fillFileList() }
        }
        discard form.addField("Type", fileBrowser.comboType)

        with fileBrowser
        {
            if @countof(fileBrowser.options.initialFolder) do
                .setCurrentFolder(fileBrowser.options.initialFolder)
            elif fileBrowser.options.state and !fileBrowser.options.state.currentFolder.isEmpty() do
                .setCurrentFolder(fileBrowser.options.state.currentFolder)
            .listCtrl.sort(0)
            .editFile.setText(fileBrowser.options.initialName)
            if fileBrowser.options.mode == .CreateFile
            {
                .editFile.selectAll()
                .editFile.setFocus()
            }
            else do
                .listCtrl.setFocus()
        }

        // Default to the first real shortcut/drive when nothing else selected a folder.
        if fileBrowser.currentFolder.isEmpty() and fileBrowser.treeCtrl
        {
            let tree = notnull fileBrowser.treeCtrl
            for line, [idx] in tree.lines where line and !line.separator
            {
                tree.selectLine(cast(u32) idx)
                break
            }
        }

        fileBrowser.updateNavigationState()

        return fileBrowser
    }

    // Navigates to `folder`; returns false when it does not name an existing directory.
    #[Swag.Discardable]
    mtd setCurrentFolder(folder: string)->bool
    {
        if !.showFolder(folder) do
            return false
        .history.push(.currentFolder.toString())
        .updateNavigationState()
        return true
    }

    // Returns whether a previous folder is available in this browser session.
    mtd canGoBack()->bool => .history.canGoBack()

    // Returns whether a later folder is available in this browser session.
    mtd canGoForward()->bool => .history.canGoForward()

    // Navigates to the previous folder; returns false when history has no valid entry.
    #[Swag.Discardable]
    mtd goBack()->bool
    {
        if !.history.canGoBack() do
            return false
        let oldIndex = .history.index
        let folder   = .history.goBack()
        if !.showFolder(folder.toString())
        {
            .history.index = oldIndex
            .updateNavigationState()
            return false
        }
        .updateNavigationState()
        return true
    }

    // Navigates to the next folder; returns false when history has no valid entry.
    #[Swag.Discardable]
    mtd goForward()->bool
    {
        if !.history.canGoForward() do
            return false
        let oldIndex = .history.index
        let folder   = .history.goForward()
        if !.showFolder(folder.toString())
        {
            .history.index = oldIndex
            .updateNavigationState()
            return false
        }
        .updateNavigationState()
        return true
    }

    // Navigates to the parent folder; returns false at a root or when it is unavailable.
    #[Swag.Discardable]
    mtd goUp()->bool
    {
        let parent = Path.directoryName(.currentFolder.toString()) orelse ""
        if !@countof(parent) or parent == .currentFolder.toString() do
            return false
        return .setCurrentFolder(parent)
    }

    // Refresh the file list of the current folder.
    mtd refresh()
    {
        .fillFileList()
        .updateNavigationState()
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
            icon.color = .themeColors().label_Text
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

    // Returns whether the current selection satisfies the configured dialog mode.
    mtd hasValidSelection()->bool
    {
        let paths = .selectedPaths()
        if paths.isEmpty() do
            return false

        switch #complete .options.mode
        {
        case .CreateFile:
            return paths.count == 1 and Directory.exists(.currentFolder)

        case .SelectFile:
            return paths.count == 1 and File.exists(paths[0])

        case .SelectFiles:
            for path in paths where !File.exists(path) do
                return false
            return true

        case .SelectFolder:
            return paths.count == 1 and Directory.exists(paths[0])
        }
    }
}
