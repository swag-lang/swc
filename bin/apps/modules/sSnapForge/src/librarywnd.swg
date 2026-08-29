using Threading, Time

// The date column. It is wider than the editor's tool column on purpose: the tool column carries
// one word per row and this one carries a sentence — "All Items" is two words in English and
// three in French, and a column sized to the English clipped the French in the very first row.
const SideBarWidth = 280.0
const LibBarHeight = 32.0
const LibGlyphSize = 16.0
const LibButtonGap = 12.0

// The count column of the date list, and what the rows spend before their name: the expander lane
// the tree reserves on every row, plus the padding of the list. The name column takes what those
// two leave, so widening the bar widens the only column that carries wording.
const LibCountWidth = 56.0
const LibRowIndent  = 28.0

enum PreviewSize
{
    Small
    Medium
    Big
}

enum SortMethod
{
    Recent
    Modified
    Name
    Application
    WindowTitle
    Dimensions
    FileSize
    Similar
}

enum LibraryContentFilter
{
    All
    Captures
    ScreenCaptures
    ImportedCaptures
    Images
}

enum LibrarySidebarFilter
{
    Date
    Application
    Tag
}

struct LibraryNamedFilter
{
    name:       String
    executable: String
    count:      u64
}

struct LibraryWnd
{
    using wnd: Wnd

    #[Swag.Late]
    {
        main:       *MainWnd
        view:       *LibraryView
        sideBar:    *Wnd
        listCtrl:   *ListCtrl
        commandBar: *StackLayoutCtrl
        viewBtn:    *IconButton
        sortBtn:    *IconButton
        filterBtn:  *IconButton
        folderBtn:  *IconButton
        searchEdit: *EditBox
        breadcrumb: *BreadcrumbCtrl
    }

    previewSize: PreviewSize

    searchText: String
    trashMode:  bool
    curFolder:  String

    // Backing storage for the breadcrumb drop-down entry ids (folder paths). Menu items
    // keep the id as a non-owning slice, so the strings must outlive the popup's modal loop.
    menuPaths:  Array'String
    menuValues: Array'String

    sidebarApplications: Array'LibraryNamedFilter
    sidebarTags:         Array'LibraryNamedFilter
    updatingSidebar:     bool

    invertSort:               bool
    sortMethod:               SortMethod
    contentFilter:            LibraryContentFilter
    favoritesOnly:            bool
    minimumRating:            u8
    applicationFilter:        String
    tagFilter:                String
    filledRevision:           u64
    deleteObserverRegistered: bool
    showUpToDateLinkedImage:  bool = true
    showLinkedImage:          bool = true
    showUnSavedLinkedImage:   bool = true
    showUnLinkedImage:        bool = true
    showRatingOverlay:        bool = true
    showLinkOverlay:          bool = true
}

impl IWnd for LibraryWnd
{
    // The four drop-down buttons and the search placeholder take their wording once, when
    // they are built, so they cannot follow a language change on their own. Every control
    // driven by a command already refreshes itself through the command state.
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .applyLanguage()
    }
}

impl LibraryWnd
{
    mtd applyLanguage()
    {
        if !@isset(.viewBtn) do
            return

        .viewBtn.setText(appStrings().ui_BarView)
        .sortBtn.setText(appStrings().ui_BarSort)
        .filterBtn.setText(appStrings().ui_BarFilter)
        .folderBtn.setText(appStrings().ui_BarFolders)
        .folderBtn.toolTip = appStrings().tip_LibraryFolders
        .searchEdit.setPlaceholder(appStrings().ui_Search)
        .commandBar.computeLayout()
    }

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
            discard catch File.delete(name[])

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

    mtd collectNamedFilters(applications: bool)->Array'LibraryNamedFilter
    {
        var result: retval
        for item in .view.allItems
        {
            .view.mutexLoaded.lock()
            let capture = item!.capture
            .view.mutexLoaded.unlock()
            if !capture do
                continue

            if applications
            {
                if capture.sourceApplication.isEmpty() do
                    continue

                var found = false
                for &entry in result where Utf8.compare(entry.name.toSlice(), capture.sourceApplication, .Latin1NoCase) == 0
                {
                    entry.count += 1
                    if entry.executable.isEmpty() and !capture.sourceExecutable.isEmpty() do
                        entry.executable = capture.sourceExecutable
                    found = true
                }

                if !found do
                    result.add({capture.sourceApplication, capture.sourceExecutable, 1})
                continue
            }

            for tag in capture.tags
            {
                var found = false
                for &entry in result where Utf8.compare(entry.name.toSlice(), tag[], .Latin1NoCase) == 0
                {
                    entry.count += 1
                    found       = true
                }

                if !found do
                    result.add({tag[], "", 1})
            }
        }

        result.sort(func(a, b) { return Utf8.compare(a.name.toSlice(), b.name.toSlice(), .Latin1NoCase) })
        return result
    }

    mtd const namedFiltersEqual(a, b: const [..] LibraryNamedFilter)->bool
    {
        if @countof(a) != @countof(b) do
            return false
        for value, i in a
        {
            if value.count != b[i].count or
               Utf8.compare(value.name.toSlice(), b[i].name.toSlice(), .Latin1NoCase) != 0 or
               value.executable != b[i].executable
            {
                return false
            }
        }

        return true
    }

    mtd addNamedFilterGroup(name: string, kind: LibrarySidebarFilter, values: *Array'LibraryNamedFilter)
    {
        if values.isEmpty() do
            return

        let root = .listCtrl.createLine(name, .theme().icon(.Filter, LibGlyphSize))
        root.userData0 = cast() Swag.U64.Max
        root.userData3 = cast() cast(u64) kind
        let rootCount = root.setItem(1, Format.toString("% ", values.count))
        rootCount.horzAlign = .Right

        for value, i in values[]
        {
            var icon: Icon
            if kind == .Application and !value.executable.isEmpty()
            {
                icon       = .app().fileIcon(value.executable)
                icon.color = Argb.White
            }

            let line = .listCtrl.createLine(value.name, icon, parentLine: root)
            line.userData0 = cast() i
            line.userData3 = cast() cast(u64) kind
            let count = line.setItem(1, Format.toString("% ", value.count))
            count.horzAlign = .Right
        }

        .listCtrl.expand(root)
    }

    // Gives the wording column exactly the horizontal room left by the fixed count column,
    // header separators and compact vertical bar. Deriving that room from the laid-out view is
    // what prevents a fixed-width rail from manufacturing a horizontal scroll bar.
    mtd layoutSidebarColumns()
    {
        if !@isset(.listCtrl) do
            return
        let available = .listCtrl.listView.paddedClientRect().width
        if available <= 0 do
            return

        let nameColumn = 0'u32
        let others     = .listCtrl.header.contentWidth() - .listCtrl.header.itemWidthForColumn(nameColumn)
        .listCtrl.setColumnWidth(nameColumn, Math.max(80, available - others))
        .listCtrl.computeLayout()
    }

    mtd selectActiveSidebarLine()
    {
        var wantedKind = LibrarySidebarFilter.Date
        if !.applicationFilter.isEmpty() do
            wantedKind = .Application
        elif !.tagFilter.isEmpty() do
            wantedKind = .Tag

        for i in .listCtrl.lineCount()
        {
            let line = .listCtrl.lineAt(cast(u32) i)!
            let kind = cast(LibrarySidebarFilter) cast(u64) line.userData3
            if kind != wantedKind do
                continue

            var matches = false
            switch kind
            {
            case .Date:
                matches = cast(u64) line.userData0 == .view.filterYear and cast(u64) line.userData1 == .view.filterMonth and cast(u64) line.userData2 == .view.filterDay

            case .Application:
                let idx = cast(u64) line.userData0
                matches = idx < .sidebarApplications.count and Utf8.compare(.sidebarApplications[idx].name.toSlice(), .applicationFilter, .Latin1NoCase) == 0

            case .Tag:
                let idx = cast(u64) line.userData0
                matches = idx < .sidebarTags.count and Utf8.compare(.sidebarTags[idx].name.toSlice(), .tagFilter, .Latin1NoCase) == 0
            }

            if matches
            {
                .listCtrl.selectLine(cast(u32) i)
                return
            }
        }
    }

    mtd rebuildSidebar()
    {
        .updatingSidebar = true
        defer .updatingSidebar = false
        .listCtrl.clear()

        let line = .listCtrl.createLine(appStrings().ui_AllCaptures, .main.icon(.Archive, LibGlyphSize))
        var item = line.setItem(1, Format.toString("% ", g_Library.files.count))
        item.horzAlign = .Right

        g_Library.files.sort(func(a, b) { return b.lastWriteTime <=> a.lastWriteTime })

        var lastDateTime:    DateTime
        var hasLastDateTime: bool
        var lastLine:        #null *ListLine
        var lastLineYear:    #null *ListLine
        var lastLineMonth:   #null *ListLine
        var lastLineDay:     #null *ListLine

        let icon1 = .main.icon(.Calendar, LibGlyphSize)
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
            if !hasLastDateTime or fi.lastWriteTime.year != lastDateTime.year
            {
                fillLastYear()
                lastLine           = .listCtrl.createLine(Format.toString("%", fi.lastWriteTime.year), icon1)
                lastLine.userData0 = cast() cast(u64) fi.lastWriteTime.year
                lastLineYear       = lastLine
            }

            if !hasLastDateTime or fi.lastWriteTime.month != lastDateTime.month
            {
                fillLastMonth()
                lastLine           = .listCtrl.createLine(Format.toString("%", DateTime.monthName(fi.lastWriteTime.month)), icon1, lastLineYear)
                lastLine.userData0 = cast() cast(u64) fi.lastWriteTime.year
                lastLine.userData1 = cast() cast(u64) fi.lastWriteTime.month
                lastLineMonth      = lastLine
            }

            if !hasLastDateTime or fi.lastWriteTime.day != lastDateTime.day
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

        .addNamedFilterGroup(appStrings().act_Application, .Application, &.sidebarApplications)
        .addNamedFilterGroup(appStrings().act_Tags, .Tag, &.sidebarTags)
        .selectActiveSidebarLine()
        .layoutSidebarColumns()
    }

    mtd refreshAutomaticFilters(force = false)
    {
        if !@isset(.listCtrl) do
            return

        let applications = .collectNamedFilters(true)
        let tags         = .collectNamedFilters(false)
        if !force and .namedFiltersEqual(.sidebarApplications.toSlice(), applications.toSlice()) and .namedFiltersEqual(.sidebarTags.toSlice(), tags.toSlice()) do
            return

        .sidebarApplications = applications
        .sidebarTags         = tags
        .rebuildSidebar()
    }

    mtd fill()
    {
        if !g_Library.loaded do
            g_Library.fill()

        if .listCtrl.lineCount() and .filledRevision == g_Library.revision do
            return

        if !.deleteObserverRegistered
        {
            g_Library.onDeleteFile += func|libWnd = me|(file)
            {
                // The loader owns a temporary pointer list. Join it before deleting the
                // corresponding ArrayPtr element, then resume any pending previews.
                libWnd.view.stopLoading()

                for item, i in libWnd.view.items
                {
                    if item.fi.fullname == file
                    {
                        libWnd.view.selModel.unselect(cast() i)
                        libWnd.view.items.removeAtOrdered(i)
                        break
                    }
                }

                for item, i in libWnd.view.allItems
                {
                    if item!.fi.fullname != file do
                        continue
                    libWnd.view.allItems.deleteAt(i)
                    break
                }

                libWnd.filledRevision = g_Library.revision
                libWnd.view.filter()
                libWnd.refreshAutomaticFilters(force: true)
                catch libWnd.view.startLoading()
            }

            .deleteObserverRegistered = true
        }

        .sidebarApplications.clear()
        .sidebarTags.clear()
        .rebuildSidebar()
        catch .view.fill()
        .filledRevision = g_Library.revision
    }

    mtd registerActions()
    {
        .registerAction'ActionLibSort()
        .registerAction'ActionLibFilter()
        .registerAction'ActionLibSel()
        .registerAction'ActionLibTrash()
        .registerAction'ActionLibView()

        .registerKeyShortcut(.None, .Left, ActionLibSel.Left)
        .registerKeyShortcut(.None, .Right, ActionLibSel.Right)
        .registerKeyShortcut(.None, .Up, ActionLibSel.Up)
        .registerKeyShortcut(.None, .Down, ActionLibSel.Down)
        .registerKeyShortcut(.None, .Home, ActionLibSel.Home)
        .registerKeyShortcut(.None, .End, ActionLibSel.End)

        .registerKeyShortcut(.Control, .C, ActionFile.CopyImage)
        .registerKeyShortcut(.None, .F2, ActionFile.RenameCapture)
    }

    // Update the live text filter and rebuild the visible set.
    mtd setSearch(text: String)
    {
        .searchText = text
        .view.filter()
        .invalidate()
    }

    mtd applySidebarFilter(line: *ListLine)
    {
        if .updatingSidebar do
            return

        .view.filterYear, .view.filterMonth, .view.filterDay = 0
        .applicationFilter.clear()
        .tagFilter.clear()

        let kind = cast(LibrarySidebarFilter) cast(u64) line.userData3
        switch kind
        {
        case .Date:
            .view.filterYear  = cast(u64) line.userData0
            .view.filterMonth = cast(u64) line.userData1
            .view.filterDay   = cast(u64) line.userData2

        case .Application:
            let idx = cast(u64) line.userData0
            if idx < .sidebarApplications.count do
                .applicationFilter = .sidebarApplications[idx].name

        case .Tag:
            let idx = cast(u64) line.userData0
            if idx < .sidebarTags.count do
                .tagFilter = .sidebarTags[idx].name
        }

        .view.filter()
    }

    mtd updateFolderMode()
    {
        if !@isset(.sideBar) do
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
        if makeLibrary
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
            return
        }

        .navigateFolder(folder)
    }

    mtd useDefaultFolder()
    {
        discard catch g_Library.setFolder("") as err
        if err != null
        {
            MessageDlg.error(.main.surface!, appStrings().msg_FailedOpenLibrary, err)
            return
        }

        .main.libraryFolder.clear()
        .curFolder.clear()
        .trashMode = false
        .view.filterYear, .view.filterMonth, .view.filterDay = 0
        .listCtrl.clear()
        .fill()
        .updateFolderMode()
        .updateBreadcrumb()
        .main.saveAppState()
    }

    mtd showFolderMenu(btn: *IconButton)
    {
        with let menu = MenuCtrl.createPopup(me, owner: me)
        {
            .addItem(appStrings().act_OpenLibraryFolder, "sSnapForge.library.root")
            .addSeparator()
            .addItem(appStrings().act_BrowseFolder, "sSnapForge.library.browse")
            .addItem(appStrings().act_ChooseLibraryFolder, "sSnapForge.library.choose")
            .addItem(appStrings().act_UseDefaultLibrary, "sSnapForge.library.default")
            .addSeparator()
            .addItem(ActionLibTrash.Toggle)
            .addItem(ActionLibTrash.Empty)
        }

        let result = menu.doModal(btn, autoDestroy: true)
        if !result do
            return
        switch result!
        {
        case "sSnapForge.library.root":    .navigateFolder(Library.getFolder())
        case "sSnapForge.library.browse":  .chooseFolder(false)
        case "sSnapForge.library.choose":  .chooseFolder(true)
        case "sSnapForge.library.default": .useDefaultFolder()
        }
    }

    mtd uniqueFilterValues(applications: bool)->Array'String
    {
        var result: retval
        for value in .collectNamedFilters(applications) do
            result.add(value.name)
        return result
    }

    mtd applyDynamicFilter(result: #null WndId)
    {
        if !result do
            return
        let id = result!
        if Utf8.startsWith(id, "sSnapForge.library.app:")
        {
            .applicationFilter = String.from(id[@countof("sSnapForge.library.app:") until @countof(id)])
            .view.filter()
        }
        elif Utf8.startsWith(id, "sSnapForge.library.tag:")
        {
            .tagFilter = String.from(id[@countof("sSnapForge.library.tag:") until @countof(id)])
            .view.filter()
        }
    }

    mtd showFilterMenu(btn: *IconButton)
    {
        let applications = .uniqueFilterValues(true)
        let tags         = .uniqueFilterValues(false)

        .menuValues.clear()
        .menuValues.reserve(2 * (applications.count + tags.count) + 2)

        with let menu = MenuCtrl.createPopup(me, owner: me)
        {
            .addItem(ActionLibFilter.Reset)
            .addSeparator()
            .addItems([ActionLibFilter.AllItems, ActionLibFilter.Captures, ActionLibFilter.ScreenCaptures, ActionLibFilter.ImportedCaptures, ActionLibFilter.Images])
            .addSeparator()
            .addItem(ActionLibFilter.FavoritesOnly)
            .addItems([ActionLibFilter.RatingAny, ActionLibFilter.Rating1, ActionLibFilter.Rating2, ActionLibFilter.Rating3, ActionLibFilter.Rating4, ActionLibFilter.Rating5])

            with let apps = MenuCtrl.createPopup(menu, owner: me)
            {
                me.menuValues.add("sSnapForge.library.app:")
                .addItem(appStrings().act_AllApplications, me.menuValues.back(), checked: me.applicationFilter.isEmpty())
                for application in applications
                {
                    me.menuValues.add(Format.toString("sSnapForge.library.app:%", application[]))
                    .addItem(application[], me.menuValues.back(), checked: Utf8.compare(application.toSlice(), me.applicationFilter, .Latin1NoCase) == 0)
                }

                menu.addPopup(appStrings().act_Application, apps)
            }

            with let tagMenu = MenuCtrl.createPopup(menu, owner: me)
            {
                me.menuValues.add("sSnapForge.library.tag:")
                .addItem(appStrings().act_AllTags, me.menuValues.back(), checked: me.tagFilter.isEmpty())
                for tag in tags
                {
                    me.menuValues.add(Format.toString("sSnapForge.library.tag:%", tag[]))
                    .addItem(tag[], me.menuValues.back(), checked: Utf8.compare(tag.toSlice(), me.tagFilter, .Latin1NoCase) == 0)
                }

                menu.addPopup(appStrings().act_Tags, tagMenu)
            }

            .addSeparator()
            .addItem(ActionLibFilter.UpToDateLinkedImage)
            .addItem(ActionLibFilter.UnSavedLinkedImage)
            .addItem(ActionLibFilter.LinkedImage)
            .addItem(ActionLibFilter.UnLinkedImage)
        }

        .applyDynamicFilter(menu.doModal(btn, autoDestroy: true))
    }

    mtd selectedCaptureFiles()->Array'String
    {
        var result: retval
        for item, i in .view.items where item.kind == .Capture and .view.selModel.isSelected(cast() i) do
            result.add(item.fi.fullname)
        return result
    }

    mtd refreshPreviewMetadata(file: String, capture: *Capture)
    {
        .view.mutexLoaded.lock()
        defer .view.mutexLoaded.unlock()
        for item in .view.allItems where item!.capture and item!.fi.fullname == file
        {
            item!.capture!.tags     = capture.tags
            item!.capture!.favorite = capture.favorite
            item!.capture!.rating   = capture.rating
        }

        g_DirtyList = true
        .view.invalidate()
    }

    mtd updateMetadata(file: String, tags: #null const *Array'String = null, favorite: #null const *bool = null, rating: #null const *u8 = null)
    {
        let loaded: #null *Capture = catch Capture.load(file) as err
        if err != null
        {
            MessageDlg.error(.main.surface!, appStrings().msg_FailedSaveMetadata, err)
            return
        }

        let capture = loaded!
        defer Memory.delete(capture)
        if tags do
            capture.tags = tags[]
        if favorite do
            capture.favorite = favorite[]
        if rating do
            capture.rating = rating[]
        capture.changed = true
        discard catch capture.save() as saveErr
        if saveErr != null
        {
            MessageDlg.error(.main.surface!, appStrings().msg_FailedSaveMetadata, saveErr)
            return
        }

        .refreshPreviewMetadata(file, capture)
    }

    mtd editSelectedTags()
    {
        let files = .selectedCaptureFiles()
        if files.isEmpty() do
            return

        var text: String
        if files.count == 1
        {
            for item in .view.items where item.capture and item.fi.fullname == files[0]
            {
                for tag in item.capture!.tags
                {
                    if !text.isEmpty() do
                        text += ", "
                    text += tag[]
                }
            }
        }

        var options: EditDlgOptions
        options.title   = appStrings().dlg_TitleEditTags
        options.message = appStrings().ui_CommaSeparatedTags
        options.text    = text
        let dialog = EditDlg.createSingleLine(.main.surface!, options)
        if dialog.doModal() != Dialog.BtnOk do
            return

        var tags: Array'String
        for part in Tokenize.split(dialog.text(), ','u8, removeEmpty: true)
        {
            var tag = String.from(part)
            tag.trim()
            if tag.isEmpty() do
                continue
            var exists = false
            for own in tags where Utf8.compare(own.toSlice(), tag, .Latin1NoCase) == 0 do
                exists = true
            if !exists do
                tags.add(#move tag)
        }

        for file in files do
            .updateMetadata(file, tags: &tags)
    }

    mtd toggleSelectedFavorite()
    {
        let files    = .selectedCaptureFiles()
        var favorite = false
        for item, i in .view.items
        {
            if item.capture and .view.selModel.isSelected(cast() i) and !item.capture!.favorite do
                favorite = true
        }

        for file in files do
            .updateMetadata(file, favorite: &favorite)
    }

    mtd rateSelected(value: u8)
    {
        let files = .selectedCaptureFiles()
        for file in files do
            .updateMetadata(file, rating: &value)
    }

    mtd exportCapture(file: String, folder: String) fail
    {
        let capture = (try Capture.load(file))!
        defer Memory.delete(capture)

        capture.editView = .main.editWnd.editView
        var image = capture.toImage()
        var name  = String.from(Path.fileNameWithoutExtension(file) orelse "capture")
        name += ".png"
        let destination = Library.uniqueName(folder, name)
        try image.save(destination)
    }

    mtd exportSelected()
    {
        let files = .selectedCaptureFiles()
        if files.isEmpty() do
            return

        let initialFolder = .currentFolder()
        var options: FileDlgOptions
        options.mode              = .SelectFolder
        options.state             = &.main.exportFolderDlgState
        options.initialFolder     = initialFolder
        options.title             = appStrings().dlg_TitleExportCaptures
        options.confirmButtonText = appStrings().dlg_BtnExport
        let dialog = FileDlg.create(.main.surface!, options)
        if dialog.doModal() != Dialog.BtnOk do
            return

        Cursor.activateWait()
        for file in files
        {
            discard catch .exportCapture(file, dialog.selectedPath()) as err
            if err != null
            {
                MessageDlg.error(.main.surface!, appStrings().msg_FailedExportCaptures, err)
                return
            }
        }
    }

    // Switch between the normal library and the recycle bin: both are just folders, so
    // this is a folder navigation to the sSnapForge folder or its recycle bin.
    mtd setTrashMode(trash: bool)
    {
        .navigateFolder(trash ? Library.getTrashFolder() : Library.getFolder())
    }

    // The real on-disk folder the library is currently showing (the sSnapForge folder by
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
        if !@isset(.breadcrumb) do
            return
        .breadcrumb.clear()

        let trashFolder = Library.getTrashFolder()

        // Collect each ancestor's full path, leaf first, by walking up the directory chain.
        // Keep 'folder' bound to a local so the slice 'p' (and every getDirectoryName slice
        // derived from it) stays backed by live memory for the whole walk.
        //
        // The walk stops at the library folder instead of climbing to the drive: this bar
        // navigates captures, and a reader has no use for the three directories that happen
        // to sit above them on this machine.
        let folder  = .currentFolder()
        let libRoot = Library.getFolder()
        var fulls: Array'String
        var p       = folder.toString()
        while @countof(p) != 0
        {
            fulls.add(String.from(p))
            if p == libRoot.toString() do
                break
            let parent = Path.directoryName(p)
            if parent == null or @countof(parent) == 0 or parent == p do
                break
            p = parent
        }

        // Add levels root-first.
        for idx in fulls.count.reversed()
        {
            let fp = fulls[idx].toString()
            var nm = Path.fileName(fp) orelse ""
            if @countof(nm) == 0 do
                nm = fp

            // At the row size of the chart, like every other glyph of this window. A breadcrumb
            // draws the icon it is handed at the size it is handed, and the theme default is the
            // 24 of a command bar — which next to a path reads as a button that lost its button.
            let isTrash = trashFolder == fp
            let icon    = isTrash ? .theme().icon(.Remove, LibGlyphSize) : .theme().icon(.OpenFile, LibGlyphSize)
            .breadcrumb.addItem(nm, icon, tag: fp)
        }
    }

    // Fill a level's drop-down with the real sub-directories of that level's folder.
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
            .menuPaths.add(String.from(d.fullname))

        for d, i in dirs
        {
            let name = Path.fileName(d.fullname) orelse d.fullname.toString()
            menu.addItem(name, .menuPaths[i].toString(), checked: d.fullname == currentChild)
        }
    }

    // Navigate the library to a folder chosen from the breadcrumb (its body or a chevron
    // entry). The sSnapForge folder keeps its full features (date sidebar, delete-to-trash);
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

    func create(parent: *MainWnd)->*LibraryWnd
    {
        with let res = Wnd.create'LibraryWnd(parent, "sSnapForge.librarywnd")
        {
            .main            = parent
            .dockStyle       = .Center
            .backgroundStyle = .View
            .registerActions()
        }

        // One rule holds both modes of the window: what can be picked stands on the left,
        // what is picked is shown on the right. The editor puts its tools on the left and
        // the selected form on the right; the library puts its dates on the left and the
        // captures themselves fill the rest. The date list used to sit on the right, so
        // switching modes swapped the meaning of the same edge.
        with res.sideBar = Wnd.create'Wnd(res, {0, 0, SideBarWidth, 0})
        {
            .dockStyle = .Left
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

        with let list = ListCtrl.createMultiColumns(res.sideBar)
        {
            .addColumn("name", SideBarWidth - LibCountWidth - LibRowIndent)
            .addColumn("count", LibCountWidth)
            .listView.style.addStyleSheetColors("listItem_SelectedBk $listItem_FocusSelectedBk")
            .setLineHeight(30)
            .updateFlags(.PreserveSelectionOnEmptyClick)
            .scrollWnd.updateFlags(.CompactBars | .AlwaysShowVertical | .TransparentBars)
            .header.hide()
            .backgroundStyle = .Window
            .updateFlags(.ReserveExpandMargin)
            .dockStyle           = .Center
            .sigSelectionChanged += func|res|(list)
            {
                let sel = list.selectedLine()
                if !sel do
                    return
                res.applySidebarFilter(sel)
            }
        }

        res.listCtrl = list

        // Folder path bar: shows the real library folder and lets the user walk it
        // (its sub-folders, incl. the recycle bin, are reachable from the chevrons).
        with res.breadcrumb = BreadcrumbCtrl.create(res, {0, 0, 0, LibBarHeight})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Window
            .sigItemPressed  += func|res|(bc, idx) { res.navigateFolder(bc.items[idx].tag.toString()) }
            .sigFillMenu     += func|res|(bc, idx, menu) { res.fillBreadcrumbMenu(bc, idx, menu) }
            .sigMenuSelected += func|res|(bc, idx, id) { res.navigateFolder(id) }
        }

        // Top bar
        with res.commandBar = StackLayoutCtrl.create(res, .Left, {0, 0, 0, LibBarHeight})
        {
            .dockStyle       = .Top
            .spacing         = LibButtonGap
            .padding         = {8, 4, 8, 4}
            .backgroundStyle = .Window
        }

        // View: thumbnail size and optional information painted over thumbnails share
        // one menu, because both control presentation rather than library contents.
        with res.viewBtn = IconButton.create(res.commandBar, res.main.icon(.ViewMedium, LibGlyphSize), {0, 0, 0, LibBarHeight})
        {
            .preferredSize.x = 0
            .setText(appStrings().ui_BarView)
            .updateFlags(.CenterContent)
            .setTextPosition(.Right)
            .setArrowPosition(.RightDownward)
            .sigPressed += func|res|(btn)
            {
                with var menu = MenuCtrl.createPopup(res)
                {
                    menu.updateFlags(.HideShortcuts)
                    .addItem(ActionRecentSize.LibSmall)
                    .addItem(ActionRecentSize.LibMedium)
                    .addItem(ActionRecentSize.LibBig)
                    .addSeparator()

                    .addItem(ActionLibView.Ratings)
                    .addItem(ActionLibView.LinkMarkers)
                }

                discard menu.doModal(cast(*IconButton) btn, autoDestroy: true)
            }
        }

        // Sort
        with res.sortBtn = IconButton.create(res.commandBar, res.theme().icon(.Sort, LibGlyphSize), {0, 0, 0, LibBarHeight})
        {
            .preferredSize.x = 0
            .setText(appStrings().ui_BarSort)
            .updateFlags(.CenterContent)
            .setTextPosition(.Right)
            .setArrowPosition(.RightDownward)
            .sigPressed += func|res|(btn)
            {
                with var menu = MenuCtrl.createPopup(res)
                {
                    menu.updateFlags(.HideShortcuts)
                    .addItem(ActionLibSort.Recent)
                    .addItem(ActionLibSort.Modified)
                    .addItem(ActionLibSort.Name)
                    .addItem(ActionLibSort.Application)
                    .addItem(ActionLibSort.WindowTitle)
                    .addItem(ActionLibSort.Dimensions)
                    .addItem(ActionLibSort.FileSize)
                    .addItem(ActionLibSort.Similar)
                    .addSeparator()
                    .addItem(ActionLibSort.Invert)
                }

                discard menu.doModal(cast(*IconButton) btn, autoDestroy: true)
            }
        }

        // Filter
        with res.filterBtn = IconButton.create(res.commandBar, res.theme().icon(.Filter, LibGlyphSize), {0, 0, 0, LibBarHeight})
        {
            .preferredSize.x = 0
            .setText(appStrings().ui_BarFilter)
            .updateFlags(.CenterContent)
            .setTextPosition(.Right)
            .setArrowPosition(.RightDownward)
            .sigPressed += func|res|(btn)
            {
                res.showFilterMenu(cast(*IconButton) btn)
            }
        }

        // Library roots and ordinary image folders are explicit choices, named like every
        // neighbouring command instead of leaving one unexplained glyph in the sentence.
        with res.folderBtn = IconButton.create(res.commandBar, res.theme().icon(.OpenFile, LibGlyphSize), {0, 0, 0, LibBarHeight})
        {
            .preferredSize.x = 0
            .setText(appStrings().ui_BarFolders)
            .updateFlags(.CenterContent)
            .setTextPosition(.Right)
            .setArrowPosition(.RightDownward)
            .toolTip    = appStrings().tip_LibraryFolders
            .sigPressed += func|res|(btn) { res.showFolderMenu(cast(*IconButton) btn) }
        }

        // Loading state stays with the commands it updates, before the flexible gap, so it
        // appears without moving the search field away from the right edge.
        view.imgSpin = Spinner.create(res.commandBar, {0, 0, LibGlyphSize, LibGlyphSize})
        view.imgSpin.hide()

        let spacer = Wnd.create'Wnd(res.commandBar)
        spacer.layoutSpec.policyX = .Expand

        // Live search
        with res.searchEdit = EditBox.create(res.commandBar, "", {0, 0, 220, LibBarHeight}, flags: .ClearButton | .ReleaseFocusOnEnterOrEscape)
        {
            .setForm(.Rectangle)
            .setPlaceholder(appStrings().ui_Search)
            .sigTextChanged += func|res|(ed) { res.setSearch(ed.text()) }
        }

        res.setPreviewSize(.Small)
        res.setSortMethod(res.sortMethod)
        res.updateBreadcrumb()
        return res
    }
}
