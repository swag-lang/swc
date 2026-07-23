using Threading, Time

enum PreviewSize
{
    Small
    Medium
    Big
}

enum SortMethod
{
    Recent
    FileSize
    Similar
}

struct LibraryWnd
{
    using wnd:                   Wnd

    main:                        #late *MainWnd
    view:                        #late *LibraryView
    listCtrl:                    #late *ListCtrl
    editZoomBar:                 #late *Wnd
    zoomBtn:                     #late *IconButton
    sortBtn:                     #late *IconButton
    filterBtn:                   #late *IconButton
    trashBtn:                    #late *IconButton
    searchEdit:                  #late *EditBox
    breadcrumb:                  #late *BreadcrumbCtrl
    previewSize:                 PreviewSize

    searchText: String
    trashMode:  bool
    curFolder:  String

    // Backing storage for the breadcrumb drop-down entry ids (folder paths). Menu items
    // keep the id as a non-owning slice, so the strings must outlive the popup's modal loop.
    menuPaths:                   Array'String

    invertSort:              bool
    sortMethod:              SortMethod
    showUpToDateLinkedImage: bool = true
    showLinkedImage:         bool = true
    showUnSavedLinkedImage:  bool = true
    showUnLinkedImage:       bool = true
}

impl LibraryWnd
{
    mtd setPreviewSize(size: PreviewSize)
    {
        .previewSize = size
        .invalidate()
    }

    mtd setSortMethod(method: SortMethod)
    {
        .sortMethod = method
        .view.sort()
        .invalidate()
    }

    mtd setSortOrder(invert: bool)
    {
        .invertSort = invert
        .view.sort()
        .invalidate()
    }

    mtd getCapture()->#null *Capture
    {
        if .view.focusItem < .view.items.count do
            return .view.items[.view.focusItem].capture
        return null
    }

    mtd requestClose()
    {
        if .view.thread.isValid()
        {
            .view.thread.safeForceEnd()
            .view.thread.wait()
        }
    }

    mtd const hasSelected()->bool
    {
        return !.view.selModel.isEmpty()
    }

    mtd removeSelected()
    {
        // g_Library.removeFile() fires onDeleteFile, whose handler removes entries
        // from .view.items. Snapshot the selected file names (owned copies) first so
        // we never delete from the list we are iterating, which would skip entries
        // and desync the selection/indices.
        var toRemove: Array'String
        for it, i in .view.items
        {
            if it.filtered do
                continue

            if .view.selModel.isSelected(cast() i) do
                toRemove.add(it.fi.fullname)
        }

        for name in toRemove do
            g_Library.removeFile(name)
    }

    // Snapshot the selected trash file names first (see removeSelected), then act on the
    // copies so refilling the grid mid-loop cannot desync indices.
    mtd selectedFiles()->Array'String
    {
        var res: retval
        for it, i in .view.items
        {
            if it.filtered do
                continue
            if .view.selModel.isSelected(cast() i) do
                res.add(it.fi.fullname)
        }
        return res
    }

    // Bring the selected captures back from the recycle bin into the library.
    mtd restoreSelected()
    {
        for name in .selectedFiles()
        {
            let dst = Library.restoreFile(name)
            if !dst.isEmpty() do
                g_Library.addFile(dst)
        }

        catch .view.fill()
        .invalidate()
    }

    // Erase the selected captures from the recycle bin for good.
    mtd deleteForeverSelected()
    {
        for name in .selectedFiles() do
            discard catch File.delete(name)

        catch .view.fill()
        .invalidate()
    }

    mtd moveSelHome()
    {
        if .view.items.isEmpty() do
            return
        .view.setFocusItem(0)
        .view.scrollToFocus()
    }

    mtd moveSelEnd()
    {
        if .view.items.isEmpty() do
            return
        .view.setFocusItem(cast(u32) .view.items.count - 1)
        .view.scrollToFocus()
    }

    mtd moveSelLeft()
    {
        if .view.items.isEmpty() do
            return
        if .view.focusItem == 0 or .view.focusItem == Swag.U32.Max do
            return
        .view.focusItem -= 1
        .view.setFocusItem(.view.focusItem)
        .view.scrollToFocus()
    }

    mtd moveSelRight()
    {
        if .view.items.isEmpty() do
            return
        if .view.focusItem == .view.items.count - 1 or .view.focusItem == Swag.U32.Max do
            return
        .view.focusItem += 1
        .view.setFocusItem(.view.focusItem)
        .view.scrollToFocus()
    }

    mtd moveSelTop()
    {
        if .view.items.isEmpty() do
            return
        let n = .view.numImagesPerLine()
        if .view.focusItem < n or .view.focusItem == Swag.U32.Max do
            return
        .view.focusItem -= n
        .view.setFocusItem(.view.focusItem)
        .view.scrollToFocus()
    }

    mtd moveSelBottom()
    {
        if .view.items.isEmpty() do
            return
        let n = .view.numImagesPerLine()
        // Use an addition instead of 'items.count - n' so an unsigned underflow
        // (when n > items.count) cannot make the guard pass and jump out of range.
        if .view.focusItem + n >= .view.items.count or .view.focusItem == Swag.U32.Max do
            return
        .view.focusItem += n
        .view.setFocusItem(.view.focusItem)
        .view.scrollToFocus()
    }

    mtd fill()
    {
        if !g_Library.loaded do
            g_Library.fill()

        if .listCtrl.getLineCount() do
            return
        g_Library.onDeleteFile += func|libWnd = me|(file)
        {
            for it, i in libWnd.view.items
            {
                if it.fi.fullname == file
                {
                    libWnd.view.selModel.select(cast() i, false)
                    libWnd.view.items.removeAtOrdered(i)
                    break
                }
            }
        }

        let line = .listCtrl.createLine("All Captures", Icon.from(&.main.icons24, 4))
        var item = line.setItem(1, Format.toString("% ", g_Library.files.count))
        item.horzAlign = .Right

        g_Library.files.sort(func(a, b)
        {
            return b.lastWriteTime <=> a.lastWriteTime
        })

        var lastDateTime:    DateTime
        var hasLastDateTime: bool
        var lastLine:        #null *ListLine
        var lastLineYear:    #null *ListLine
        var lastLineMonth:   #null *ListLine
        var lastLineDay:     #null *ListLine

        let icon1 = Icon.from(&.main.icons24, 3)

        var cptYear, cptMonth, cptDay = 0

        #[Swag.Mixin]
        func fillLastYear()
        {
            if lastLineYear
            {
                item           = lastLineYear.setItem(1, Format.toString("% ", cptYear))
                item.horzAlign = .Right
                cptYear        = 0
            }
        }

        #[Swag.Mixin]
        func fillLastMonth()
        {
            if lastLineMonth
            {
                item           = lastLineMonth.setItem(1, Format.toString("% ", cptMonth))
                item.horzAlign = .Right
                cptMonth       = 0
            }
        }

        #[Swag.Mixin]
        func fillLastDay()
        {
            if lastLineDay
            {
                item           = lastLineDay.setItem(1, Format.toString("% ", cptDay))
                item.horzAlign = .Right
                cptDay         = 0
            }
        }

        for fi in g_Library.files
        {
            if !hasLastDateTime or (fi.lastWriteTime.year != lastDateTime.year)
            {
                fillLastYear()
                lastLine           = .listCtrl.createLine(Format.toString("%", fi.lastWriteTime.year), icon1)
                lastLine.userData0 = cast() cast(u64) fi.lastWriteTime.year
                lastLineYear       = lastLine
            }

            if !hasLastDateTime or (fi.lastWriteTime.month != lastDateTime.month)
            {
                fillLastMonth()
                lastLine           = .listCtrl.createLine(Format.toString("%", DateTime.monthName(fi.lastWriteTime.month)), icon1, lastLineYear)
                lastLine.userData0 = cast() cast(u64) fi.lastWriteTime.year
                lastLine.userData1 = cast() cast(u64) fi.lastWriteTime.month
                lastLineMonth      = lastLine
            }

            if !hasLastDateTime or (fi.lastWriteTime.day != lastDateTime.day)
            {
                fillLastDay()
                lastLine           = .listCtrl.createLine(Format.toString("%, %", DateTime.dayOfWeekName(fi.lastWriteTime.dayOfWeek()), fi.lastWriteTime.day), icon1, lastLineMonth)
                lastLine.userData0 = cast() cast(u64) fi.lastWriteTime.year
                lastLine.userData1 = cast() cast(u64) fi.lastWriteTime.month
                lastLine.userData2 = cast() cast(u64) fi.lastWriteTime.day
                lastLineDay        = lastLine
            }

            lastDateTime              = fi.lastWriteTime
            hasLastDateTime           = true
            cptYear, cptMonth, cptDay += 1
        }

        fillLastYear()
        fillLastMonth()
        fillLastDay()

        .listCtrl.computeLayout()
        catch .view.fill()
    }

    mtd registerActions()
    {
        .registerAction'ActionLibSort()
        .registerAction'ActionLibFilter()
        .registerAction'ActionLibSel()
        .registerAction'ActionLibTrash()

        .registerKeyShortcut(.Zero, .Left, ActionLibSel.Left)
        .registerKeyShortcut(.Zero, .Right, ActionLibSel.Right)
        .registerKeyShortcut(.Zero, .Up, ActionLibSel.Up)
        .registerKeyShortcut(.Zero, .Down, ActionLibSel.Down)
        .registerKeyShortcut(.Zero, .Home, ActionLibSel.Home)
        .registerKeyShortcut(.Zero, .End, ActionLibSel.End)

        .registerKeyShortcut(.Control, .C, ActionFile.CopyImage)
        .registerKeyShortcut(.Zero, .F2, ActionFile.RenameCapture)
    }

    // Update the live text filter and rebuild the visible set.
    mtd setSearch(text: String)
    {
        .searchText = text
        .view.filter()
        .invalidate()
    }

    // Switch between the normal library and the recycle bin: both are just folders, so
    // this is a folder navigation to the captMe folder or its recycle bin.
    mtd setTrashMode(trash: bool)
    {
        .navigateFolder(trash ? Library.getTrashFolder() : Library.getFolder())
    }

    // The real on-disk folder the library is currently showing (the captMe folder by
    // default, its recycle bin, or any folder navigated to from the breadcrumb).
    mtd currentFolder()->String
    {
        if .curFolder.isEmpty() do
            return Library.getFolder()
        return .curFolder
    }

    // Rebuild the breadcrumb from the current folder path: one level per path component,
    // each carrying its full path in 'tag' so navigation can act on it.
    mtd updateBreadcrumb()
    {
        if !#isset(.breadcrumb) do
            return
        .breadcrumb.clear()

        let trashFolder = Library.getTrashFolder()

        // Collect each ancestor's full path, leaf first, by walking up the directory chain.
        // Keep 'folder' bound to a local so the slice 'p' (and every getDirectoryName slice
        // derived from it) stays backed by live memory for the whole walk.
        let folder = .currentFolder()
        var fulls: Array'String
        var p = folder.toString()
        while @countof(p) != 0
        {
            fulls.add(String.from(p))
            let parent = Path.getDirectoryName(p)
            if parent == null or @countof(parent) == 0 or parent == p do
                break
            p = parent
        }

        // Add levels root-first.
        for #reverse idx in fulls.count
        {
            let fp = fulls[idx].toString()
            var nm = Path.getFileName(fp) orelse ""
            if @countof(nm) == 0 do
                nm = fp
            let isTrash = trashFolder == fp
            let icon    = isTrash ? .getTheme().getIcon24(.Remove) : .getTheme().getIcon24(.OpenFile)
            .breadcrumb.addItem(nm, icon, tag: fp)
        }
    }

    // Fill a level's drop-down with the real sub-directories of that level's folder.
    mtd fillBreadcrumbMenu(bc: *BreadcrumbCtrl, index: u64, menu: *MenuCtrl)
    {
        if index >= bc.items.count do
            return
        let folder = bc.items[index].tag.toString()

        let dirs = catch Directory.enumerateDirectories(folder)
        if @err != null do
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
            .menuPaths.add(String.from(d.fullname))

        for d, i in dirs
        {
            let name = Path.getFileName(d.fullname) orelse d.fullname.toString()
            menu.addItem(name, .menuPaths[i].toString(), checked: d.fullname == currentChild)
        }
    }

    // Navigate the library to a folder chosen from the breadcrumb (its body or a chevron
    // entry). The captMe folder keeps its full features (date sidebar, delete-to-trash);
    // the recycle bin and any other folder are simply browsed by listing their captures.
    mtd navigateFolder(path: String)
    {
        if .currentFolder() == path do
            return

        .curFolder = path
        .trashMode = Library.getTrashFolder() == path
        catch .view.fill()
        .invalidate()
        .updateBreadcrumb()
    }

    func create(parent: *MainWnd)->*LibraryWnd
    {
        with let res = Wnd.create'LibraryWnd(parent, "captme.librarywnd")
        {
            .main            = parent
            .dockStyle       = .Center
            .backgroundStyle = .View
            .registerActions()
        }

        with let rightBar = Wnd.create'Wnd(res, {0, 0, 300, 0})
        {
            .dockStyle = .Right
        }

        with let scrollWnd = Wnd.create'ScrollWnd(res)
        {
            .dockStyle = .Center
        }

        with let view = Wnd.create'LibraryView(scrollWnd)
        {
            .libWnd    = res
            .padding   = 8
            .scrollWnd = scrollWnd
            .mainWnd   = parent
        }

        scrollWnd.setView(view)
        res.view = view

        // Top bar list
        with let barList = StackLayoutCtrl.create(rightBar, .HorzCenter, {0, 0, 300, 32})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Window
        }

        with let list = ListCtrl.createMultiColumns(rightBar)
        {
            .addColumn("name", 200)
            .addColumn("count", 70)
            .listView.style.addStyleSheetColors("listItem_SelectedBk $listItem_FocusSelectedBk")
            .lineHeight               = 30
            .listFlags                |= .NoMouseEmptySel
            .scrollWnd.scrollWndFlags |= .SmallBar | .ForceVertical | .TransparentBar
            .header.hide()
            .backgroundStyle = .Window
            .listFlags       |= .ForceMarginExpandMark
            .dockStyle       = .Center
            .sigSelChanged   += func|view|(list)
            {
                var sel = list.getSelectedLine()
                if !sel do
                    return
                view.filterYear  = cast(u64) sel.userData0
                view.filterMonth = cast(u64) sel.userData1
                view.filterDay   = cast(u64) sel.userData2
                catch view.fill()
            }
        }
        res.listCtrl = list

        // Folder path bar: shows the real library folder and lets the user walk it
        // (its sub-folders, incl. the recycle bin, are reachable from the chevrons).
        with res.breadcrumb = BreadcrumbCtrl.create(res, {0, 0, 0, 32})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Window
            .sigItemPressed  += func|res|(bc, idx)
            {
                res.navigateFolder(bc.items[idx].tag.toString())
            }
            .sigFillMenu = func|res|(bc, idx, menu)
            {
                res.fillBreadcrumbMenu(bc, idx, menu)
            }
            .sigMenuSelected += func|res|(bc, idx, id)
            {
                res.navigateFolder(id)
            }
        }

        // Top bar
        with res.editZoomBar = StackLayoutCtrl.create(res, .HorzCenter, {0, 0, 300, 32})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Window
        }

        with view.imgSpin = ImageRect.create(res, {4, 4, 24, 24})
        {
            .setMovie(dref notnull view.getTheme().res.spin)
            .hide()
        }

        // Image Size
        with res.zoomBtn = IconButton.create(res.editZoomBar, res.getTheme().getIcon24(.Search), {0, 0, 120, 32})
        {
            .name.set("Size")
            .iconBtnFlags.add(.Center)
            .textPos    = .Right
            .arrowPos   = .RightDown
            .sigPressed += func|res|(btn)
            {
                var pos = btn.getSurfaceRect()
                with var menu = MenuCtrl.createPopup(res)
                {
                    .menuCtrlFlags |= .NoKeyShortcuts
                    .addItem(ActionRecentSize.LibSmall)
                    .addItem(ActionRecentSize.LibMedium)
                    .addItem(ActionRecentSize.LibBig)
                }
                discard menu.doModal({pos.horzCenter(), pos.bottom()}, .AnchorTopCenter, autoDestroy: true)
            }
        }

        // Sort
        with res.sortBtn = IconButton.create(res.editZoomBar, res.getTheme().getIcon24(.Sort), {0, 0, 120, 32})
        {
            .name.set("Sort")
            .iconBtnFlags.add(.Center)
            .textPos    = .Right
            .arrowPos   = .RightDown
            .sigPressed += func|res|(btn)
            {
                var pos = btn.getSurfaceRect()
                with var menu = MenuCtrl.createPopup(res)
                {
                    .menuCtrlFlags |= .NoKeyShortcuts
                    .addItem(ActionLibSort.Recent)
                    .addItem(ActionLibSort.FileSize)
                    .addItem(ActionLibSort.Similar)
                    .addSeparator()
                    .addItem(ActionLibSort.Invert)
                }
                discard menu.doModal({pos.horzCenter(), pos.bottom()}, .AnchorTopCenter, autoDestroy: true)
            }
        }

        // Filter
        with res.filterBtn = IconButton.create(res.editZoomBar, res.getTheme().getIcon24(.Filter), {0, 0, 120, 32})
        {
            .name.set("Filter")
            .iconBtnFlags.add(.Center)
            .textPos    = .Right
            .arrowPos   = .RightDown
            .sigPressed += func|res|(btn)
            {
                var pos = btn.getSurfaceRect()
                with var menu = MenuCtrl.createPopup(res)
                {
                    .menuCtrlFlags |= .NoKeyShortcuts
                    .addItem(ActionLibFilter.UpToDateLinkedImage)
                    .addItem(ActionLibFilter.UnSavedLinkedImage)
                    .addSeparator()
                    .addItem(ActionLibFilter.LinkedImage)
                    .addItem(ActionLibFilter.UnLinkedImage)
                }
                discard menu.doModal({pos.horzCenter(), pos.bottom()}, .AnchorTopCenter, autoDestroy: true)
            }
        }

        // Recycle bin
        with res.trashBtn = IconButton.create(res.editZoomBar, res.getTheme().getIcon24(.Remove), {0, 0, 120, 32})
        {
            .name.set("Trash")
            .iconBtnFlags.add(.Center)
            .textPos    = .Right
            .arrowPos   = .RightDown
            .sigPressed += func|res|(btn)
            {
                var pos = btn.getSurfaceRect()
                with var menu = MenuCtrl.createPopup(res)
                {
                    .menuCtrlFlags |= .NoKeyShortcuts
                    .addItem(ActionLibTrash.Toggle)
                    .addSeparator()
                    .addItem(ActionLibTrash.Empty)
                }
                discard menu.doModal({pos.horzCenter(), pos.bottom()}, .AnchorTopCenter, autoDestroy: true)
            }
        }

        // Live search
        with res.searchEdit = EditBox.create(res.editZoomBar, "", {0, 0, 180, 32}, flags: .ClearButton | .AutoLoseFocus)
        {
            .setForm(.Round)
            .setNote("Search")
            .sigChanged += func|res|(ed)
            {
                res.setSearch(ed.getText())
            }
        }

        res.setPreviewSize(.Small)
        res.setSortMethod(res.sortMethod)
        res.updateBreadcrumb()
        return res
    }
}
