#global public

using Core, File, Directory

// A reusable file-browsing composite control: a shortcut/drive tree, a file
// list, a path combo and a name/type row. It is a plain window that can be
// embedded anywhere (a dialog, a side panel, a tab...) independently of FileDlg.
// FileDlg is just a thin modal wrapper around this control.
//
// Reuses the public option types declared by FileDlg (FileDlgOptions/Mode/State)
// so existing callers keep working; the dialog-only fields (title, btnOkName)
// are simply ignored here.
struct FileBrowserCtrl
{
    using wnd: Wnd

    treeCtrl:     #null *ListCtrl
    treePathStr:  Array'String
    listCtrl:     #late *ListCtrl
    comboPath:    #late *ComboBox
    comboPathStr: Array'String
    editFile:     #late *EditBox
    comboType:    #late *ComboBox
    options:      FileDlgOptions

    curFolder: String
    curList:   Array'FileInfo

    // A file/folder was activated (double-click or Enter on a non-directory).
    sigAccept: SigArray'func||(*FileBrowserCtrl)

    // The current folder changed.
    sigFolderChanged: SigArray'func||(*FileBrowserCtrl)

    // The user requested the creation of a new folder (host shows the prompt).
    sigNewFolder: SigArray'func||(*FileBrowserCtrl)
}

impl IWnd for FileBrowserCtrl
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        if .options.state
        {
            with me.options.state
            {
                .curFolder           = me.curFolder
                .columnWidthName     = cast() me.listCtrl.header.getItemWidthByCol(0)
                .columnWidthModified = cast() me.listCtrl.header.getItemWidthByCol(1)
            }
        }
    }
}

private impl FileBrowserCtrl
{
    mtd folderUp()
    {
        if .comboPathStr.count > 1 do
            .setCurFolder(.comboPathStr[1].toString())
    }

    mtd fillComboPath()
    {
        .comboPath.clear()
        .comboPathStr.clear()

        let all = Tokenize.split(.curFolder.toString(), '/''rune)
        for #reverse i in @countof(all)
        {
            var str: String
            for j in i + 1
            {
                str += all[j]
                str += '/''u8
            }

            .comboPathStr.add(str)

            let one  = all[i]
            var icon = .getApp().getDirectoryIcon(one)
            icon.color = Pixel.Argb.White
            .comboPath.addItem(one, icon: icon)
        }

        .comboPath.selectItem(0)
    }

    mtd fillFileListFolders()
    {
        var l = .treeCtrl.createLine("Shortcuts")
        l.separator = true

        for v in .options.shortcuts
        {
            let c    = Env.getSpecialDirectory(v.type)
            var icon = .getApp().getSpecialDirectoryIcon(v.type, true)
            icon.color       = Pixel.Argb.White
            l                = .treeCtrl.createLine(v.name, icon)
            l.userData0      = cast(#null *void) .treePathStr.count
            l.leftTextMargin = 10
            .treePathStr.add(c)
        }

        l           = .treeCtrl.createLine("Drives")
        l.separator = true

        let volumes = catch Directory.getDrives()
        for &v in volumes
        {
            v.removeBack()
            var icon = .getApp().getDirectoryIcon(v, true)
            icon.color       = Pixel.Argb.White
            l                = .treeCtrl.createLine(v.toString(), icon)
            l.userData0      = cast(#null *void) .treePathStr.count
            l.leftTextMargin = 10
            .treePathStr.add(v)
        }

        .treeCtrl.sigSelChanged += func|fileBrowser = me|(list)
        {
            var line = list.getSelectedLine()
            if !line do
                return
            var idx = cast(u64) line.userData0
            fileBrowser.setCurFolder(fileBrowser.treePathStr[idx].toString())
        }
    }

    mtd createFileList(view: *Wnd)
    {
        with me.listCtrl = ListCtrl.createMultiColumns(view)
        {
            .selectionMode   = me.options.mode == .SelectMultiFiles ? .Multi : .Single
            .dockStyle       = .Center
            .margin.z        = 10
            .listFlags       |= .HotTrack
            .backgroundStyle = .View

            // NOTE: both branches are kept explicitly f32. A runtime conditional
            // whose unified result is integer, fed to an f32 parameter, is currently
            // mis-lowered to a bit-reinterpret (see reference_conditional_int_to_float_miscompile).
            .addColumn("Name", me.options.state ? cast(f32) me.options.state.columnWidthName : 200.0)
            .addColumn("Modified", me.options.state ? cast(f32) me.options.state.columnWidthModified : 150.0)
            .header.form = .Transparent
            .header.style.addStyleSheetColors("headerItem_Separator $lighterMedium")
            .scrollWnd.style.addStyleSheetColors("scrollBar_Bk $view_Bk")
            .sigKeyPressed += func|fileBrowser = me|(list, evt)
            {
                switch evt.key
                {
                case Back:
                    fileBrowser.folderUp()

                case Enter:
                    let l = list.getFocusLine()
                    if !l do
                        break
                    let fi = cast(#null const *FileInfo) l.userData0
                    if fi.isDirectory()
                    {
                        fileBrowser.setCurFolder(fi.fullname)
                    }
                    elif fileBrowser.options.mode != .SelectFolder
                    {
                        fileBrowser.sigAccept.call(fileBrowser)
                        list.setFocus()
                    }
                }
            }
            .sigLeftDoubleClick += func|fileBrowser = me|(list, pt)
            {
                var l = list.getSelectedLine()
                if !l do
                    return
                var fi = cast(#null const *FileInfo) l.userData0
                if fi.isDirectory()
                {
                    fileBrowser.setCurFolder(fi.fullname)
                }
                elif fileBrowser.options.mode != .SelectFolder
                {
                    fileBrowser.sigAccept.call(fileBrowser)
                    list.setFocus()
                }
            }
            .sigSelChanged += func|fileBrowser = me|(list)
            {
                var sel  = list.getSelectedLines()
                var txt: String
                for l in sel
                {
                    let fi = cast(#null const *FileInfo) l.userData0
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
                    txt     += Path.getFileName(fi.fullname)
                }

                if !txt.isEmpty() do
                    fileBrowser.editFile.setText(txt)
            }
            .sigSort = func(l1, l2, col, down)
            {
                if l1 == null or l2 == null do
                    return 0

                var fi1 = cast(#null *FileInfo) l1.userData0
                var fi2 = cast(#null *FileInfo) l2.userData0
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
    // Creates the file browser composite inside 'parent'.
    func create(parent: *Wnd, opt: FileDlgOptions = {}, position: Math.Rectangle = {})->*FileBrowserCtrl
    {
        let fileBrowser = Wnd.create'FileBrowserCtrl(parent, "", position)
        fileBrowser.options         = opt
        fileBrowser.backgroundStyle = .Window

        // Panes
        ////////////////////////
        if opt.drivePane
        {
            with fileBrowser.treeCtrl = ListCtrl.createSimple(fileBrowser, {0, 0, 170})
            {
                .dockStyle       = .Left
                .listFlags       |= .HotTrack
                .lineHeight      = 28
                .leftTextMargin  = 8
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
                .sigPressed += func|fileBrowser|(btn) { fileBrowser.sigNewFolder.call(fileBrowser) }
            }
        }

        with fileBrowser.comboPath = ComboBox.create(viewTop)
        {
            .dockStyle  = .Center
            .sigChanged += func|fileBrowser|(combo, idx) { fileBrowser.setCurFolder(fileBrowser.comboPathStr[idx]) }
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
                for f, idx in opt.filters do
                    .addItem(f.name, userData0: cast(#null *void) idx)
            .selectItem(0)
            .sigChanged += func|fileBrowser|(c, idx) { fileBrowser.fillFileList() }
        }

        let nameLbl0 = opt.mode == .SelectFolder ? "Folder Name" : "File Name"
        let label0   = Label.create(viewBottom, nameLbl0, {5, 10, 80, fileBrowser.editFile.position.height})
        label0.horzAlignmentText = .Right
        label0.vertAlignmentText = .Center
        let label1 = Label.create(viewBottom, "Type", {5, 45, 80, fileBrowser.comboType.position.height})
        label1.horzAlignmentText = .Right
        label1.vertAlignmentText = .Center

        with fileBrowser
        {
            if opt.openFolder do
                .setCurFolder(opt.openFolder)
            elif opt.state and !opt.state.curFolder.isEmpty() do
                .setCurFolder(opt.state.curFolder)
            .listCtrl.sort(0)
            .editFile.setText(opt.editName)
            if opt.mode == .CreateFile
            {
                .editFile.selectAll()
                .editFile.setFocus()
            }
            else do
                .listCtrl.setFocus()
        }

        // Default to the first shortcut/drive when nothing else selected a folder.
        if fileBrowser.curFolder.isEmpty() and fileBrowser.treeCtrl do
            fileBrowser.treeCtrl.selectLine(0)

        return fileBrowser
    }

    // Navigate to the given folder.
    mtd setCurFolder(folder: string)
    {
        if !@countof(folder) or !Directory.exists(notnull folder) do
            return

        .curFolder = folder
        Path.normalize(&.curFolder)

        if .curFolder.back() == '/' do
            .curFolder.removeBack()

        .fillFileList()
        .fillComboPath()
        .sigFolderChanged.call(me)
    }

    // Refresh the file list of the current folder.
    mtd refresh()
    {
        .fillFileList()
    }

    // Fill the file list from the current folder, applying the active filter.
    mtd fillFileList()
    {
        .listCtrl.clear()

        with var options: EnumerationOptions
        {
            .skipAttributes  = .Hidden
            .wantFiles       = me.options.mode != .SelectFolder
            .wantDirectories = true
            .recurse         = false
        }

        .curList = catch Directory.enumerate(.curFolder, options)

        // SelectFolder mode has no file filters (it lists folders only): avoid
        // indexing the empty 'filters' array.
        var filterExtensions: #null string
        if me.options.mode != .SelectFolder and .options.filters.count
        {
            let item        = .comboType.getSelectedItem()
            let filterIndex = cast(u64) item.userData0
            if filterIndex < .options.filters.count do
                filterExtensions = .options.filters[filterIndex].extensions
        }

        let tokens = Tokenize.split(filterExtensions orelse "", ';''rune)

        for &fi in .curList
        {
            let fname = notnull Path.getFileName(fi.fullname)

            // Filter
            var show = true
            if !fi.isDirectory() and @countof(filterExtensions)
            {
                show = false
                for t in tokens
                {
                    if Path.isExtension(fname, t)
                    {
                        show = true
                        break
                    }
                }
            }

            if !show do
                continue

            // Content
            var icon = .getApp().getFileDirectoryIcon(fname, fi.isDirectory())
            icon.color = Pixel.Argb.White
            let line = .listCtrl.createLine(fname, icon)
            line.userData0 = fi
            line.setItem(1, fi.lastWriteTime.toString(.DateTimeIso))
        }

        .listCtrl.computeLayout()
        .listCtrl.sort()
    }

    // Create a folder inside the current folder; returns true on success.
    mtd createFolder(name: string)->bool
    {
        let path = Path.combine(.curFolder, name)
        catch Directory.create(path)
        if @err != null do
            return false
        .fillFileList()
        return true
    }

    // Get the first selection (full path)
    mtd getSelectedName()->String
    {
        let sel = .getSelectedNames()
        if sel.count == 0 do
            return String.from("")
        return sel.front()
    }

    // Get all selections (full paths)
    mtd getSelectedNames()->Array'String
    {
        var result: retval

        // SelectFolder mode has no filters: do not index the empty 'filters' array.
        var filterExtensions: #null string
        if me.options.mode != .SelectFolder and .options.filters.count
        {
            let item        = .comboType.getSelectedItem()
            let filterIndex = cast(u64) item.userData0
            if filterIndex < .options.filters.count do
                filterExtensions = .options.filters[filterIndex].extensions
        }

        let tokens = Tokenize.split(.editFile.text, ';''rune)
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
            var val = Path.combine(.curFolder, t1.toString())

            // Append extension if not done by the user
            if .options.mode != .SelectFolder and @countof(filterExtensions) and !Path.isExtension(val, notnull filterExtensions)
            {
                let exts = Tokenize.split(notnull filterExtensions, ';''rune)
                val += exts[0]
            }

            result.add(val)
        }

        return result
    }
}
