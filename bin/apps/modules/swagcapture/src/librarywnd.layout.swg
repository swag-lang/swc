// The page of the library: a title over its folders as tabs and its tags as chips, the quiet menus
// and the search beside the title, the captures under them on the window ground.
const LibraryPageMargin  = 72.0       // Air between the page and the side edges of the window.
const LibraryTitleSize   = 48'u32     // Size of the page title.
const LibraryTitleRow    = 72.0       // Height of the row of the title, the menus and the search.
const LibraryTabsRow     = 40.0       // Height of the row of the folder tabs and the tag chips.
const LibraryHeaderGap   = 24.0       // Air between the header and the first row of captures.
const LibraryTopGap      = 16.0       // Air between the strip and the title.
const LibrarySearchWidth = 280.0      // Width of the search field.
const LibraryMaxChips    = 6          // Tags offered as chips; the filter sheet offers every tag.

impl LibraryWnd
{
    // The header of the page: the title row and the row of tabs and chips.
    mtd createHeader()
    {
        let metrics = .themeMetrics()
        let theme   = .theme()

        // The header stands on the page's edges; the grid under it reaches the ring's width past
        // them, so the thumbnails, not their rings, line up with the title.
        with .header = Wnd.create'Wnd(me, {0, 0, 0, LibraryTopGap + LibraryTitleRow + LibraryTabsRow + LibraryHeaderGap})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
            .padding.y       = LibraryTopGap
            .padding.w       = LibraryHeaderGap
            .margin.x        = LibraryCellRing
            .margin.z        = LibraryCellRing
        }

        with let titleRow = Wnd.create'Wnd(.header, {0, 0, 0, LibraryTitleRow})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
        }

        // The search stands against the trailing edge, centred on the line of the title.
        let fieldHeight = metrics.editBox_Height
        with .searchEdit = EditBox.create(titleRow, "", {0, 0, LibrarySearchWidth, fieldHeight}, flags: .ClearButton | .ReleaseFocusOnEnterOrEscape)
        {
            .dockStyle = .Right
            .margin.y  = Math.round((LibraryTitleRow - fieldHeight) * 0.5)
            .margin.w  = .margin.y
            .setPlaceholder(appStrings().ui_Search)
            .sigTextChanged += func|libWnd = me|(ed) { libWnd.setSearch(ed.text()) }
        }

        .createCommandBar(titleRow)

        var titleFont = theme.createDefaultFontFamily(LibraryTitleSize)
        titleFont.regular = titleFont.bold
        with .titleLabel = Label.create(titleRow, "", {})
        {
            .dockStyle = .Center
            .style.setFont(titleFont)
            .setTextAlignment(.Left, .Center)
        }

        with let tabsRow = Wnd.create'Wnd(.header, {0, 0, 0, LibraryTabsRow})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
        }

        // The chips stand centred on the line of the tabs: the row keeps the same air above and
        // under them, or they stretch down to its foot.
        let chipHeight = metrics.quiet_Height - 4
        with .tagChips = StackLayoutCtrl.create(tabsRow, .Left, {})
        {
            .dockStyle    = .Right
            .fitToContent = true
            .spacing      = metrics.iconBar_ButtonGap
            .padding.y    = Math.round((LibraryTabsRow - chipHeight) * 0.5)
            .padding.w    = .padding.y
        }

        // The folders are words on the page, with no rule under them: the underline of the one
        // open is the only line of the row.
        with .folderTabs = Tab.create(tabsRow, {})
        {
            .setForms(.Transparent, .Flat, .None)
            .dockStyle = .Center
            .sigSelectionChanged += func|libWnd = me|(_) { libWnd.openFolderTab() }
        }

        .hintLine = HintLine.create(me)
        .fillHintLine()
    }

    // The captures themselves, on the ground of the window.
    mtd createCaptureGrid()
    {
        with .captureHost = Wnd.create'ScrollWnd(me)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
        }

        with .view = Wnd.create'LibraryView(me.captureHost)
        {
            .libWnd    = me
            .padding   = LibraryCellRing
            .scrollWnd = me.captureHost
            .mainWnd   = me.main
        }

        .captureHost.setView(.view)
    }

    // One quiet menu of the title row: its word and the arrow that says a menu opens.
    mtd createMenuButton(parent: *Wnd, text: string)->*IconButton
    {
        let button = IconButton.createQuiet(parent)
        button.setQuietText(text)
        return button
    }

    // The quiet menus of the page: how it is shown, what it filters, which folder it reads.
    mtd createCommandBar(parent: *Wnd)
    {
        // The menus stand centred on the line of the title, as the search does: the same air above
        // and under them, or they stretch to the foot of the row and their words sink.
        let metrics = .themeMetrics()
        let air     = Math.round((LibraryTitleRow - metrics.quiet_Height) * 0.5)
        with .commandBar = StackLayoutCtrl.create(parent, .Left, {})
        {
            .dockStyle       = .Right
            .fitToContent    = true
            .spacing         = LibButtonGap
            .padding         = {0, air, LibButtonGap, air}
            .backgroundStyle = .Transparent
        }

        // How the library is shown — thumbnail size, order, and what is painted over each
        // thumbnail — is one sheet, because none of it changes what the library holds.
        .viewBtn = .createMenuButton(.commandBar, appStrings().ui_BarView)
        .viewBtn.sigPressed += func|libWnd = me|(btn) { libWnd.showViewOptions(btn) }

        .filterBtn = .createMenuButton(.commandBar, appStrings().ui_BarFilter)
        .filterBtn.sigPressed += func|libWnd = me|(btn) { libWnd.showFilterOptions(btn) }

        .folderBtn            = .createMenuButton(.commandBar, appStrings().ui_BarFolders)
        .folderBtn.toolTip    = appStrings().tip_LibraryFolders
        .folderBtn.sigPressed += func|libWnd = me|(btn) { libWnd.showFolderMenu(btn) }
    }

    // The loading state of the previews stays with the menus it updates; hidden, it takes no room.
    mtd createSpinner()
    {
        let iconSize = themeRowIconSize(.themeMetrics())
        .view.imgSpin = Spinner.create(.commandBar, Math.Rectangle{0, 0, iconSize, iconSize})
        .view.imgSpin.hide()
    }

    // Names the page after the folder it shows: the library, its recycle bin, or a browsed folder.
    mtd updateTitle()
    {
        if .titleLabel == null do
            return

        let folder = .currentFolder()
        if folder == Library.getFolder() do
            .titleLabel.setText(appStrings().act_Library)
        elif .trashMode do
            .titleLabel.setText(appStrings().act_RecycleBin)
        else do
            .titleLabel.setText(Path.fileName(folder) orelse folder.toString())
    }

    // Lists the folders of the library as tabs, with the count of what each one holds: the whole
    // library first, then its sub-folders, the recycle bin among them.
    mtd updateFolderTabs()
    {
        if .folderTabs == null do
            return

        .updatingTabs = true
        defer .updatingTabs = false
        .folderTabs.clear()
        .tabFolders.clear()

        // The library tab counts what the page lists when it shows the library, and the index
        // of the library otherwise.
        let root      = Library.getFolder()
        let rootCount = .currentFolder() == root ? .view.allItems.count : g_Library.files.count

        // A tab names its folder and counts its captures, the count in mono.
        .folderTabs.addItem(appStrings().ui_AllCaptures)
        .folderTabs.setItemCount(0, Format.toString("%", rootCount))
        .tabFolders.add(root)

        let dirs = catch Directory.enumerateDirectories(root)
        for d in dirs
        {
            let isTrash = d.fullName == Library.getTrashFolder()
            var count   = 0'u64
            if isTrash do
                count = (catch Library.enumerateTrash()).count
            else do
                count = (catch Library.enumerateSupportedFiles(d.fullName)).count
            let name = isTrash ? appStrings().act_RecycleBin : (Path.fileName(d.fullName) orelse d.fullName.toString())
            .folderTabs.addItem(name)
            .folderTabs.setItemCount(cast(u32, .folderTabs.items.count - 1), Format.toString("%", count))
            .tabFolders.add(d.fullName)
        }

        let current = .currentFolder()
        for folder, i in .tabFolders where folder[] == current
        {
            .folderTabs.setSelectedIndex(cast(u32, i))
            break
        }
    }

    // Opens the folder of the tab the reader chose.
    mtd openFolderTab()
    {
        if .updatingTabs do
            return

        // A copy: opening the folder lists the tabs again, which replaces the paths.
        let index = .folderTabs.selectedIndex
        if index < .tabFolders.count
        {
            let folder: String = .tabFolders[index]
            .navigateFolder(folder)
        }
    }

    // Offers the most used tags as chips; the chip of the tag in force is chosen.
    mtd updateTagChips()
    {
        if .tagChips == null do
            return

        for chip in .tagChips.children do
            chip.destroy()

        let metrics = .themeMetrics()
        for tag, i in .sidebarTags
        {
            if i == LibraryMaxChips do
                break

            let name = tag.name.toString()

            // A chip is a tag in mono on the raised ground; the one in force takes the Arc ground.
            with let chip = IconButton.create(.tagChips, {}, {0, 0, 0, metrics.quiet_Height - 4}, flags: .Toggle)
            {
                .preferredSize.x = 0
                .setText(name)
                .style.setFont(me.theme().res.fontDefaultFs)
                .style.addStyleSheetColors("btnIcon_Bk $raised")
                .updateFlags(.CenterContent)
                .setForm(.RoundedRectangle)
                .setCheckIndicator(.Full)
                .setChecked(Utf8.compare(tag.name.toSlice(), me.tagFilter, .Latin1NoCase) == 0)
                .sigPressed += func|libWnd = me, name|(_)
                {
                    let chosen = Utf8.compare(libWnd.tagFilter.toSlice(), name, .Latin1NoCase) == 0
                    libWnd.setTagFilter(chosen ? "" : name)
                }
            }
        }

        .tagChips.computeLayout()
        .applyLayout()
    }
}
