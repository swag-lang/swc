using Threading, Time

// Air between two quiet menus of the title row.
const LibButtonGap = 12.0

// The page of the library: a title over its folders as tabs and its tags as chips, the quiet menus
// and the search beside the title, the captures under them on the window ground.
const LibraryPageMargin  = 72.0       // Air between the page and the side edges of the window.
const LibraryTitleSize   = 48'u32     // Size of the page title.
const LibraryTitleRow    = 72.0       // Height of the row of the title, the menus and the search.
const LibraryTabsRow     = 40.0       // Height of the row of the folder tabs and the tag chips.
const LibraryHeaderGap   = 24.0       // Air between the header and the first row of captures.
const LibraryTopGap      = 16.0       // Air between the strip and the title.
const LibrarySearchWidth = 280.0      // Width of the search field.
const LibrarySearchMin   = 160.0      // Width the search field keeps when the title needs room.
const LibraryMaxChips    = 6          // Tags offered as chips; the filter sheet offers every tag.

// The size of library thumbnails.
enum PreviewSize
{
    Small
    Medium
    Big
}

// The order of the library.
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

// Which kinds of entries the library shows. The application state stores the choice by value
// (std.core.038), so a new kind goes last whatever its place in the menu.
enum LibraryContentFilter
{
    All
    Captures
    ScreenCaptures
    ImportedCaptures
    Images
    Animations     // Captures with a length.
}

// One date the library can be narrowed to: a year, a month of a year, or a day of a month, with
// how many captures it holds. A zero month or day covers the whole year or month.
struct LibraryDateFilter
{
    year, month, day: u64
    count: u64
}

// One entry of a sidebar group: its name, the executable it stands for when it groups by
// application, and how many entries match it.
struct LibraryNamedFilter
{
    name:       String
    executable: String
    count:      u64
}

impl LibraryNamedFilter
{
    // Returns whether both entries name the same filter with the same count. Names compare
    // without case, the way the side bar groups them.
    mtd const opEquals(other: LibraryNamedFilter)->bool => .count == other.count and
                                                           Utf8.compare(.name.toSlice(), other.name.toSlice(), .Latin1NoCase) == 0 and
                                                           .executable == other.executable
}

// Uses a normalized name as a case-insensitive lookup key and retains its output index.
struct LibraryNamedFilterKey
{
    name:  String
    index: u64
}

impl LibraryNamedFilterKey
{
    mtd const opEquals(other: LibraryNamedFilterKey)->bool => .name == other.name
}

impl Hash.IHash32 for LibraryNamedFilterKey
{
    mtd const impl compute()->u32 => Hash.hash32(.name)
}

// What a folder tab last counted in its folder, with the time the folder was last written and the
// revision of the library index then: either one moving says the count may have changed.
struct LibraryFolderCount
{
    folder:   String
    written:  DateTime
    revision: u64
    count:    u64
}

// The library page: its title, folder tabs and tag chips, the quiet menus and the search, the
// thumbnail grid, and the hint line naming what the lens offers here.
struct LibraryWnd
{
    using wnd: Wnd

    late
    {
        main:        *MainWnd
        view:        *LibraryView
        header:      *Wnd
        titleLabel:  *Label
        folderTabs:  *Tab
        tagChips:    *StackLayoutCtrl
        captureHost: *ScrollWnd
        commandBar:  *StackLayoutCtrl
        viewBtn:     *IconButton
        filterBtn:   *IconButton
        folderBtn:   *IconButton
        searchEdit:  *EditBox
        hintLine:    *HintLine
    }

    // The first capture, offered where an empty library says it holds none.
    emptyCapture: *PushButton?

    // The folder each tab opens, in the order of the tabs, and what the tabs of the sub-folders
    // counted last.
    tabFolders:   Array'String
    folderCounts: Array'LibraryFolderCount
    updatingTabs: bool

    // The folders the lens offered last, which its rows open.
    lensFolders: Array'String

    // The applications and the tags the lens offered last, which its rows narrow the page to.
    lensNames: Array'String

    // The applications and the tags the filter sheet offers, which its choices narrow the page to.
    applicationChoices: Array'String
    tagChoices:         Array'String

    // The dates the captures were taken on, newest first, offered by the lens.
    dateFilters: Array'LibraryDateFilter

    previewSize: PreviewSize

    searchText: String
    trashMode:  bool
    curFolder:  String

    sidebarApplications: Array'LibraryNamedFilter
    sidebarTags:         Array'LibraryNamedFilter

    invertSort:               bool
    sortMethod:               SortMethod
    contentFilter:            LibraryContentFilter
    favoritesOnly:            bool
    minimumRating:            u8
    applicationFilter:        String
    tagFilter:                String
    filledRevision:           u64
    filledOnce:               bool
    deleteObserverRegistered: bool
    showUpToDateLinkedImage:  bool = true
    showLinkedImage:          bool = true
    showUnSavedLinkedImage:   bool = true
    showUnLinkedImage:        bool = true
    showRatingOverlay:        bool = true
    showLinkOverlay:          bool = true

    exportFiles:  Array'String
    exportFolder: String
    exportIndex:  u64
    exportJob:    *CaptureLoadJob?
    videoCopyJob: *CaptureVideoCopyJob?
    exportTimer:  *Gui.Timer?
    exporting:    bool
}

impl IWnd for LibraryWnd
{
    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        let videoCopy = .videoCopyJob
        if videoCopy and evt.task == &videoCopy.task
        {
            .videoCopyJob = null
            let file   = String.from(videoCopy.source)
            let failed = not videoCopy.error.isEmpty()
            Memory.delete(videoCopy)
            if failed
            {
                .main.reportFailure(appStrings().msg_FailedExportCaptures, file)
                .finishExport()
            }
            else
            {
                .exportIndex += 1
                .startNextExport()
            }

            return
        }

        let job = .exportJob
        if not job or evt.task != &job.task
        {
            evt.accepted = false
            return
        }

        .exportJob = null
        let capture = job.capture
        let file    = job.file
        Memory.delete(job)
        if not capture
        {
            .main.reportFailure(appStrings().msg_FailedExportCaptures, file)
            .finishExport()
            return
        }

        defer Memory.delete(capture)
        if capture.canCopyOriginalVideo()
        {
            let name = Format.toString("%.mp4", Path.fileNameWithoutExtension(file) orelse "capture")
            let copy = Memory.new'CaptureVideoCopyJob()
            copy.source   = Capture.mediaPathOf(file, .Video)
            copy.target   = Library.uniqueName(.exportFolder, name)
            .videoCopyJob = copy
            copy.task.submit(func|copy|()
            {
                catch exportOriginalVideo(copy.source, copy.target) as copy.error
            },
                             .taskNotifier(&copy.task))
            return
        }

        catch .exportLoadedCapture(capture, file, .exportFolder)
        {
            .main.reportFailure(appStrings().msg_FailedExportCaptures, file)
            .finishExport()
            return
        }

        .exportIndex += 1
        .startNextExport()
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .exportTimer
        {
            .wnd.IWnd.onTimerEvent(evt)
            return
        }

        .stopTimer(&.exportTimer)
        .startNextExport()
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .stopTimer(&.exportTimer)
        if .videoCopyJob
        {
            let job = .videoCopyJob
            .videoCopyJob = null
            job.task.cancel()
            job.task.wait()
            Memory.delete(job)
        }

        if .exportJob
        {
            let job = .exportJob
            .exportJob = null
            job.task.cancel()
            job.task.wait()
            if job.capture do
                Memory.delete(job.capture)
            Memory.delete(job)
        }
    }

    // The page keeps its side margins, and its header keeps clear of the strip the window glyph,
    // the title, the window buttons and the task controls float in, or of the band those controls
    // take without a strip.
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .padding = {LibraryPageMargin - LibraryCellRing, .stripInset() + TaskStrip.bandHeight(me), LibraryPageMargin - LibraryCellRing, 0}
        .fitTitleRow()
    }

    // The three drop-down buttons and the search placeholder take their wording once, when
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
    // Whether a filter on what a capture holds is active: favorites, rating, application, or tag.
    mtd const filtersMetadata()->bool => .favoritesOnly or .minimumRating or not .applicationFilter.isEmpty() or not .tagFilter.isEmpty()

    mtd applyLanguage()
    {
        if .viewBtn == null do
            return

        .viewBtn.setQuietText(appStrings().ui_BarView)
        .filterBtn.setQuietText(appStrings().ui_BarFilter)
        .folderBtn.setQuietText(appStrings().ui_BarFolders)
        .folderBtn.toolTip = appStrings().tip_LibraryFolders
        .searchEdit.setPlaceholder(appStrings().ui_Search)
        .fillHintLine()
        .commandBar.computeLayout()
        .updateTitle()
        .updateFolderTabs()
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

    mtd getCapture()->*Capture?
    {
        if .view.focusItem < .view.items.count do
            return .view.items[.view.focusItem].capture
        return null
    }

    mtd requestClose()
    {
        .view.stopLoading()
    }

    mtd const hasSelected()->bool => not .view.selModel.isEmpty()

    // Fills the library from the index, once per index revision, and hooks the delete notification
    // the first time.
    mtd fill()
    {
        if not g_Library.loaded do
            g_Library.fill()
        .main.startVideoRecovery()

        if .filledOnce and .filledRevision == g_Library.revision do
            return
        .filledOnce = true

        if not .deleteObserverRegistered
        {
            g_Library.onDeleteFile += func|libWnd = me|(file)
            {
                libWnd.view.removeFile(file)
                libWnd.filledRevision = g_Library.revision
                libWnd.view.filter()
                libWnd.refreshAutomaticFilters(force: true)
                catch libWnd.view.startLoading()
            }

            .deleteObserverRegistered = true
        }

        // The folder tabs count what the page lists, so the sidebar follows the fill.
        catch .view.fill()
        .sidebarApplications.clear()
        .sidebarTags.clear()
        .rebuildSidebar()
        .filledRevision = g_Library.revision
    }

    // Registers the command families of the library and its keyboard navigation.
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

        // The keys the hint line teaches: Enter opens, Delete deletes, 0 to 5 rate, / searches.
        .registerKeyShortcut(.None, .Return, ActionLibSel.Open)
        .registerKeyShortcut(.None, .Delete, ActionLibSel.Delete)
        .registerKeyShortcut(.None, .Oem2, ActionLibSel.Search)
        .registerKeyShortcut(.None, .Divide, ActionLibSel.Search)
        .registerKeyShortcut(.None, .D0, ActionLibSel.Rate0)
        .registerKeyShortcut(.None, .D1, ActionLibSel.Rate1)
        .registerKeyShortcut(.None, .D2, ActionLibSel.Rate2)
        .registerKeyShortcut(.None, .D3, ActionLibSel.Rate3)
        .registerKeyShortcut(.None, .D4, ActionLibSel.Rate4)
        .registerKeyShortcut(.None, .D5, ActionLibSel.Rate5)
    }

    // Teaches the keys of the page on its hint line: open, delete, rename, rate and search the
    // chosen captures, then Ctrl Space, which opens the lens. An empty page has none of those to
    // act on: it keeps the lens, and the ways in that it offers.
    mtd fillHintLine()
    {
        let texts = appStrings()
        .hintLine.clearHints()
        if .view != null and .view.items.isEmpty()
        {
            if not .view.allItems.isEmpty()
            {
                .hintLine.addHint(Input.formatKeyShortcut(.None, .Oem2), texts.hint_Filter)
                .hintLine.addHint(Input.formatKeyShortcut(.Control, .Space), texts.hint_EmptySearchSpace)
            }
            else
            {
                .hintLine.addHint(Input.formatKeyShortcut(.Control, .Space), texts.hint_Space)
            }

            return
        }

        .hintLine.addHint(strings().key_Enter, texts.hint_Open)
        .hintLine.addHint(Input.formatKeyShortcut(.None, .Delete), texts.hint_Delete)
        .hintLine.addHint(Input.formatKeyShortcut(.None, .F2), texts.hint_Rename)
        .hintLine.addHint(texts.key_Ratings, texts.hint_Rate)
        .hintLine.addHint(Input.formatKeyShortcut(.None, .Oem2), texts.hint_Filter)
        .hintLine.addHint(Input.formatKeyShortcut(.Control, .Space), texts.hint_LibrarySpace)
    }

    // Update the live text filter and rebuild the visible set.
    mtd setSearch(text: String)
    {
        .searchText = text
        .view.filter()
        .invalidate()
    }

    // Shows the first capture where the page is the empty library, and nowhere else: an empty
    // recycle bin or an empty folder being browsed is not a place to capture into. The hint line
    // follows, since an empty page has no capture to open, delete or rate.
    mtd updateEmptyState()
    {
        if .hintLine != null do
            .fillHintLine()
        let button = .emptyCapture
        if not button do
            return

        let shown = .view.allItems.isEmpty() and not .trashMode and .currentFolder() == Library.getFolder()
        button.show(shown)
        if not shown do
            return

        // Under the sentence that says the library is empty, against the same edge, a line of
        // air below it.
        let metrics = .themeMetrics()
        let width   = Math.max(button.itf.measureContent({}).x, metrics.btnPush_Width)
        let client  = .view.paddedClientRect()
        button.setPosition(Math.Rectangle{client.x, client.y + 2 * metrics.fileTile_NameHeight + 12, width, metrics.btnPush_Height})
    }

    // Builds the library page: the header over the thumbnail grid, on the ground of the window.
    func create(parent: *MainWnd)->*LibraryWnd
    {
        with let result = Wnd.create'LibraryWnd(parent, "capture.librarywnd")
        {
            .main            = parent
            .dockStyle       = .Center
            .backgroundStyle = .Window
            .registerActions()
        }

        result.createHeader()
        result.createCaptureGrid()
        with result.emptyCapture = PushButton.create(result.view, "", id: ActionCapture.Area, form: .Strong)
        {
            .owner = parent
            .hide()
        }

        result.createSpinner()
        result.setPreviewSize(.Small)
        result.setSortMethod(result.sortMethod)
        result.updateTitle()
        return result
    }
}

// How the page is built and laid out: its header, its grid, its title, its tabs and its chips.
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
            .updateFlags(.Ellipsis)
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
            .margin.w        = me.themeMetrics().hintLine_Bottom + me.themeMetrics().hintLine_Height
        }

        with .view = Wnd.create'LibraryView(me.captureHost)
        {
            .libWnd      = me
            .padding     = LibraryCellRing
            .scrollWnd   = me.captureHost
            .mainWnd     = me.main
            .focusPolicy = .Tab
            .wndFlags    |= .NoFocusRing
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
        .fitTitleRow()
    }

    // Keeps the whole title of the page before the whole width of the search: a narrow window or
    // a longer translation takes room from the search, down to its minimum, and only past that
    // does the title end with an ellipsis rather than run under the menus.
    mtd fitTitleRow()
    {
        if .titleLabel == null or .searchEdit == null or .commandBar == null do
            return

        let row   = .clientRect().width - .padding.x - .padding.z - 2 * LibraryCellRing
        let menus = .commandBar.itf.measureContent({}).x
        let title = Math.ceil(Painter.measureString(.titleLabel.text(), unwrap .titleLabel.font().regular).width)
        let width = Math.clamp(row - menus - title, LibrarySearchMin, LibrarySearchWidth)
        if .searchEdit.position.width != width do
            .searchEdit.resize(width, .searchEdit.position.height)
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

        // Counting a folder lists it and asks the decoders about every file, so a count is kept
        // until the folder is written to or the library changes.
        var counts: Array'LibraryFolderCount
        let dirs = catch Directory.enumerateDirectories(root)
        for d in dirs
        {
            let isTrash = d.fullName == Library.getTrashFolder()
            var count   = Swag.U64.Max
            for cached in .folderCounts
            {
                if cached.folder == d.fullName and
                   cached.written == d.lastWriteTime and
                   cached.revision == g_Library.revision
                {
                    count = cached.count
                    break
                }
            }

            if count == Swag.U64.Max
            {
                if isTrash do
                    count = (catch Library.enumerateTrash()).count
                else do
                    count = (catch Library.enumerateSupportedFiles(d.fullName)).count
            }

            counts.add({d.fullName, d.lastWriteTime, g_Library.revision, count})
            let name = isTrash ? appStrings().act_RecycleBin : (Path.fileName(d.fullName) orelse d.fullName.toString())
            .folderTabs.addItem(name)
            .folderTabs.setItemCount(cast(u32, .folderTabs.items.count - 1), Format.toString("%", count))
            .tabFolders.add(d.fullName)
        }

        .folderCounts = #move counts

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

// Which folder the page shows: the library, its recycle bin, or a folder browsed to.
impl LibraryWnd
{
    // Returns the folder glyph of a command, in the ink of its row: the theme gives a folder
    // Arc, the mark of a place to go in a listing, and a command that acts on a folder is not one.
    mtd commandFolderIcon()->Icon
    {
        var result = .theme().icon(.Folder)
        result.color = Argb.Zero
        return result
    }

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
        .trashMode  = false
        .view.filterYear, .view.filterMonth, .view.filterDay = 0
        .filledOnce = false
        .fill()
        .updateFolderMode()
        .main.saveAppState()
    }

    // Shows the folder menu under `btn`: back to the library, another folder to browse, the folder
    // the library keeps its captures in, and the emptying of the recycle bin, whose tab is on
    // the page already.
    mtd showFolderMenu(btn: *IconButton)
    {
        let folderIcon = .commandFolderIcon()
        with let menu  = MenuCtrl.createPopup(me, owner: me)
        {
            .addItem(appStrings().act_OpenLibraryFolder, "capture.library.root", icon: folderIcon)
            .addSeparator()
            .addItem(appStrings().act_BrowseFolder, "capture.library.browse", icon: .theme().icon(.ExploreFolder))
            .addItem(appStrings().act_ChooseLibraryFolder, "capture.library.choose", icon: folderIcon)
            .addItem(appStrings().act_UseDefaultLibrary, "capture.library.default", icon: .theme().icon(.Undo))
            .addSeparator()
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

// What the page does with the chosen captures: delete, restore, walk, tag, rate, move, export.
impl LibraryWnd
{
    // Moves the selected captures to the recycle bin. The names are snapshotted first:
    // g_Library.removeFile() fires onDeleteFile, whose handler removes entries from
    // .view.items, and deleting from the list being iterated would skip entries and
    // desync the selection.
    mtd removeSelected()
    {
        var failed: bool
        for name in .selectedFiles()
        {
            if not g_Library.removeFile(name.toString()) do
                failed = true
        }

        if failed do
            MessageDlg.error(unwrap .main.surface, appStrings().msg_FailedMoveCaptures)
    }

    // Returns owned copies of the selected, visible file names, so a caller can act on them
    // while refilling the grid moves the items they came from.
    mtd selectedFiles()->Array'String
    {
        var result: #returntype
        for it, i in .view.items where not it.filtered
        {
            if .view.selModel.isSelected(cast(i)) do
                result.add(it.fi.fullName)
        }

        return result
    }

    // Brings the selected captures back from the recycle bin into the library, and says when
    // some of them stayed there.
    mtd restoreSelected()
    {
        var failed = false
        for name in .selectedFiles()
        {
            let dst = Library.restoreFile(name)
            if dst.isEmpty() do
                failed = true
            else do
                g_Library.addFile(dst)
        }

        catch .view.fill()
        .updateFolderTabs()
        .invalidate()
        if failed do
            MessageDlg.error(unwrap .main.surface, appStrings().msg_FailedRestoreCaptures)
    }

    // Erases the selected captures from the recycle bin for good, and says when some of them
    // could not be erased.
    mtd deleteForeverSelected()
    {
        var failed = false
        for name in .selectedFiles()
        {
            catch Capture.deleteFiles(name[]) do
                failed = true
        }

        catch .view.fill()
        .updateFolderTabs()
        .invalidate()
        if failed do
            MessageDlg.error(unwrap .main.surface, appStrings().msg_FailedDeleteCaptures)
    }

    mtd moveSelHome()
    {
        if not .view.items.isEmpty() do
            .focusCell(0)
    }

    mtd moveSelEnd()
    {
        if not .view.items.isEmpty() do
            .focusCell(cast(u32, .view.items.count) - 1)
    }

    // The arrows walk the grid from the focused cell. Without one, the first arrow starts the walk
    // on the first cell, so the keyboard reaches the grid before anything was clicked.
    mtd moveSelLeft()
    {
        if .startWalk() do
            return
        if .view.focusItem > 0 do
            .focusCell(.view.focusItem - 1)
    }

    mtd moveSelRight()
    {
        if .startWalk() do
            return
        if .view.focusItem + 1 < .view.items.count do
            .focusCell(.view.focusItem + 1)
    }

    mtd moveSelTop()
    {
        if .startWalk() do
            return
        let n = .view.numImagesPerLine()
        if .view.focusItem >= n do
            .focusCell(.view.focusItem - n)
    }

    // A shorter last row has no cell under the focused one: Down lands on its last cell, as the
    // nearest one below.
    mtd moveSelBottom()
    {
        if .startWalk() do
            return
        let n    = .view.numImagesPerLine()
        let last = cast(u32, .view.items.count) - 1
        if .view.focusItem + n <= last do
            .focusCell(.view.focusItem + n)
        elif .view.focusItem / n < last / n do
            .focusCell(last)
    }

    // Focuses the first cell when none is focused, and returns whether it did; an empty grid or
    // a focus beyond it (for a moment, while the grid is rebuilt) leaves nothing to walk.
    private mtd startWalk()->bool
    {
        if .view.items.isEmpty() do
            return true
        if .view.focusItem < .view.items.count do
            return false
        .focusCell(0)
        return true
    }

    private mtd focusCell(index: u32)
    {
        .view.setFocusItem(index)
        .view.scrollToFocus()
    }

    mtd selectedCaptureFiles()->Array'String
    {
        var result: #returntype
        for item, i in .view.items where item.kind == .Capture and .view.selModel.isSelected(cast(i)) do
            result.add(item.fi.fullName)
        return result
    }

    mtd refreshPreviewMetadata(file: String, tags: const *Array'String? = null, favorite: const *bool? = null, rating: const *u8? = null)
    {
        .view.mutexLoaded.lock()
        defer .view.mutexLoaded.unlock()
        for item in .view.allItems where item!.capture and item.fi.fullName == file
        {
            if tags do
                item.capture!.tags = tags[]
            if favorite do
                item.capture!.favorite = favorite[]
            if rating do
                item.capture!.rating = rating[]
        }

        let active = .main.editWnd.getCapture()
        if active and active.file == file
        {
            if tags do
                active.tags = tags[]
            if favorite do
                active.favorite = favorite[]
            if rating do
                active.rating = rating[]
        }

        g_DirtyList = true
        .view.invalidate()
    }

    // Queues a metadata edit in the file-writer lane, then updates the visible preview.
    mtd updateMetadata(file: String, tags: const *Array'String? = null, favorite: const *bool? = null, rating: const *u8? = null)
    {
        .main.queueCaptureMetadata(file, tags: tags, favorite: favorite, rating: rating)
        .refreshPreviewMetadata(file, tags, favorite, rating)
    }

    // Asks for the tags of the selected captures and writes them to every one. A single capture
    // starts from its own tags.
    mtd editSelectedTags()
    {
        let files = .selectedCaptureFiles()
        if files.isEmpty() do
            return

        var text: String
        if files.count == 1
        {
            for item in .view.items where item.capture and item.fi.fullName == files[0]
            {
                for tag in item.capture.tags
                {
                    if not text.isEmpty() do
                        text += ", "
                    text += tag[]
                }
            }
        }

        var options: EditDlgOptions
        options.title   = appStrings().dlg_TitleEditTags
        options.message = appStrings().ui_CommaSeparatedTags
        options.text    = text
        let dialog = EditDlg.createSingleLine(unwrap .main.surface, options)
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
            if not exists do
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
            if item.capture and .view.selModel.isSelected(cast(i)) and not item.capture.favorite do
                favorite = true
        }

        for file in files do
            .updateMetadata(file, favorite: &favorite)
    }

    mtd rateSelected(value: u8)
    {
        for file in .selectedCaptureFiles() do
            .updateMetadata(file, rating: &value)
    }

    mtd exportCapture(file: String, folder: String) fail
    {
        // The exported media must include edits a background save is still writing.
        .main.flushCaptureSave(file)

        let capture = try Capture.load(file)
        defer Memory.delete(capture)

        try .exportLoadedCapture(capture, file, folder)
    }

    private mtd exportLoadedCapture(capture: *Capture, file: String, folder: String) fail
    {
        var name = String.from(Path.fileNameWithoutExtension(file) orelse "capture")
        capture.editView = .main.editWnd.editView
        switch capture.media
        {
        case .Video:
            name += ".mp4"
            try capture.exportVideo(Library.uniqueName(folder, name))

        case .Animation:
            name += ".gif"
            try capture.exportAnimation(Library.uniqueName(folder, name))

        case .Picture:
            name += ".png"
            var image = capture.toImage()
            try image.save(Library.uniqueName(folder, name))
        }
    }

    // Moves the chosen captures to a folder the user picks: they leave the page, and the library
    // when the folder is outside it.
    mtd moveSelected()
    {
        let files = .selectedFiles()
        if files.isEmpty() do
            return

        let initialFolder = .currentFolder()
        var options: FileDlgOptions
        options.mode              = .SelectFolder
        options.state             = &.main.exportFolderDlgState
        options.initialFolder     = initialFolder
        options.title             = appStrings().dlg_TitleMoveCaptures
        options.confirmButtonText = appStrings().dlg_BtnMove
        let dialog = FileDlg.create(unwrap .main.surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return

        let folder = dialog.selectedPath()
        if folder == initialFolder do
            return

        Cursor.activateWait()
        var failed = false
        for name in files where g_Library.moveTo(name, folder).isEmpty() do
            failed = true

        catch .view.fill()
        .invalidate()
        if failed do
            MessageDlg.error(.main.surface, appStrings().msg_FailedMoveCaptures)
    }

    // Asks for a folder and writes each selected capture in its media format.
    mtd exportSelected()
    {
        if .exporting
        {
            .main.reportProgress(appStrings().msg_ExportingCaptures)
            return
        }

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
        let dialog = FileDlg.create(unwrap .main.surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return

        .beginExport(files, dialog.selectedPath())
    }

    // Starts one ordered export from an owned selection and destination.
    mtd beginExport(files: Array'String, folder: String)
    {
        if .exporting or files.isEmpty() do
            return
        .exportFiles  = files
        .exportFolder = folder
        .exportIndex  = 0
        .exporting    = true
        .main.reportProgress(appStrings().msg_ExportingCaptures)
        .startNextExport()
    }

    private mtd startNextExport()
    {
        if not .exporting or .exportJob or .videoCopyJob do
            return
        if .exportIndex >= .exportFiles.count
        {
            .finishExport(completed: true)
            return
        }

        let file   = .exportFiles[.exportIndex]
        let failed = g_CaptureSaves.collect()
        if not failed.isEmpty() do
            .main.reportFailure(Format.toString(appStrings().msg_FailedSaveCapture, failed))
        if g_CaptureSaves.writing(file)
        {
            if not .exportTimer do
                .exportTimer = .addTimer(16'ms)
            return
        }

        let job = Memory.new'CaptureLoadJob()
        job.file   = file
        .exportJob = job
        job.task.submit(func|job|()
        {
            catch { job.capture = try Capture.load(job.file) } as job.error
        },
                        .taskNotifier(&job.task))
    }

    private mtd finishExport(completed = false)
    {
        .stopTimer(&.exportTimer)
        .exportFiles.clear()
        .exportFolder.clear()
        .exportIndex = 0
        .exporting   = false
        if completed do
            .main.confirm(appStrings().msg_ExportedCaptures)
    }
}

// What the page can be narrowed to, and how the lens and the option sheets offer it.
impl LibraryWnd
{
    // Counts the loaded captures per source application and per tag, in one pass over the
    // library, for the sidebar groups. Both lists are sorted by name.
    mtd collectNamedFilters()->{applications: Array'LibraryNamedFilter, tags: Array'LibraryNamedFilter}
    {
        // Counts one more capture under `name`, combining case variants through the lookup key.
        func count(entries: *Array'LibraryNamedFilter,
                   index: *HashSet'LibraryNamedFilterKey,
                   name: string,
                   executable: string)
        {
            let key   = LibraryNamedFilterKey{String.toLower(name), entries.count}
            let found = index[].add(#move key)
            if found.key.index < entries.count
            {
                let entry = &entries[found.key.index]
                entry.count += 1
                if entry.executable.isEmpty() and executable.count != 0 do
                    entry.executable = executable
                return
            }

            entries.add(LibraryNamedFilter{name, executable, 1})
        }

        var result: #returntype
        var applications: HashSet'LibraryNamedFilterKey
        var tags:         HashSet'LibraryNamedFilterKey
        for item in .view.allItems
        {
            .view.mutexLoaded.lock()
            let capture = item!.capture
            .view.mutexLoaded.unlock()
            if not capture do
                continue

            if not capture.sourceApplication.isEmpty() do
                count(&result.applications,
                      &applications,
                      capture.sourceApplication,
                      capture.sourceExecutable)
            for tag in capture.tags do
                count(&result.tags, &tags, tag[], "")
        }

        result.applications.sort(func(a, b) => Utf8.compare(a.name.toSlice(), b.name.toSlice(), .Latin1NoCase))
        result.tags.sort(func(a, b) => Utf8.compare(a.name.toSlice(), b.name.toSlice(), .Latin1NoCase))
        return result
    }

    // Returns the words of a date filter: the year, the month and its year, or the day, its
    // month and its year.
    func dateFilterLabel(filter: LibraryDateFilter)->String
    {
        if filter.month == 0 do
            return Format.toString("%", filter.year)
        let month = DateTime.monthName(cast(u8, filter.month))
        if filter.day == 0 do
            return Format.toString("% %", month, filter.year)
        return Format.toString("% % %", filter.day, month, filter.year)
    }

    // Rebuilds what the library can be narrowed to: the dates its captures were taken on, newest
    // first, for the lens; the tags, as chips; the folders, as tabs.
    mtd rebuildSidebar()
    {
        .dateFilters.clear()
        g_Library.files.sort(func(a, b) => b.lastWriteTime <=> a.lastWriteTime)

        var year, month, day = Swag.U64.Max
        var yearIdx, monthIdx, dayIdx: u64
        for fi in g_Library.files
        {
            let t = fi.lastWriteTime
            if t.year != year
            {
                month   = Swag.U64.Max
                day     = Swag.U64.Max
                yearIdx = .dateFilters.count
                .dateFilters.add(LibraryDateFilter{year: t.year})
            }

            if t.month != month
            {
                day      = Swag.U64.Max
                monthIdx = .dateFilters.count
                .dateFilters.add(LibraryDateFilter{year: t.year, month: t.month})
            }

            if t.day != day
            {
                dayIdx = .dateFilters.count
                .dateFilters.add(LibraryDateFilter{year: t.year, month: t.month, day: t.day})
            }

            year                         = t.year
            month                        = t.month
            day                          = t.day
            .dateFilters[yearIdx].count  += 1
            .dateFilters[monthIdx].count += 1
            .dateFilters[dayIdx].count   += 1
        }

        .updateTagChips()
        .updateFolderTabs()
    }

    // Counts the applications and the tags of the loaded captures again, which change as the
    // previews stream in. Only the tag chips show them: the dates and the folder tabs follow the
    // files, not what they hold, and listing the folders reads every one of them from disk, so
    // they are rebuilt only when `force` says the files changed.
    //
    // A list is replaced only when it changed: the tag chips borrow the names of the tags.
    mtd refreshAutomaticFilters(force = false)
    {
        var filters = .collectNamedFilters()
        if not Slice.equals(.sidebarApplications.toSlice(), filters.applications.toSlice()) do
            .sidebarApplications = #move filters.applications

        let tagsChanged = not Slice.equals(.sidebarTags.toSlice(), filters.tags.toSlice())
        if tagsChanged do
            .sidebarTags = #move filters.tags

        if force do
            .rebuildSidebar()
        elif tagsChanged do
            .updateTagChips()
    }

    // Narrows the library to the captures of a date, or shows every date with a zero year.
    mtd applyDateFilter(filter: LibraryDateFilter)
    {
        .view.filterYear  = filter.year
        .view.filterMonth = filter.month
        .view.filterDay   = filter.day
        .view.filter()
    }

    // Answers the lens on the library page: its commands, the folders to open, the dates, the
    // applications and the tags to narrow it to.
    mtd describeLens(results: *Lens.Results)
    {
        let texts = appStrings()
        let query = results.query.toString()

        // The commands of the page: those of the selection, how it is shown, what it filters and
        // which folder it reads. They route through the page, where the library registers them.
        .describeCommands(results, query, texts.act_Library, SelectionIds)
        .describeActions(results, query)
        .describeCommands(results, query, texts.ui_BarView, ThumbnailSizeIds)
        .describeCommands(results, query, texts.ui_BarView, SortIds)
        .describeCommands(results, query, texts.ui_BarView, OverlayIds)
        .describeCommands(results, query, texts.ui_BarFilter, ContentFilterIds)
        .describeCommands(results, query, texts.ui_BarFilter, [ActionLibFilter.FavoritesOnly])
        .describeCommands(results, query, texts.ui_BarFilter, RatingFilterIds)
        .describeCommands(results, query, texts.ui_BarFilter, LinkFilterIds)
        .describeCommands(results, query, texts.ui_BarFilter, [ActionLibFilter.Reset])
        .describeFolderCommands(results, query)
        .describeFolders(results, query)
        .describeDates(results, query)
        .lensNames.clear()
        .describeNamed(results, query, texts.act_Application, &.sidebarApplications, application: true)
        .describeNamed(results, query, texts.act_Tags, &.sidebarTags, application: false)
    }

    // Answers the lens at rest on the library page: what can be done with the chosen captures —
    // open, export, tags, favourite, move, delete — and their rating, then what the page shows.
    // Every other command of the page is one word away.
    mtd describeLensRest(results: *Lens.Results)
    {
        let texts  = appStrings()
        let chosen = .selectedFiles()
        if .trashMode
        {
            .describeCommands(results, "", texts.lens_Selection, [ActionLibTrash.Restore, ActionLibTrash.DeleteForever])
        }
        elif not chosen.isEmpty() and .view.focusItem < .view.items.count
        {
            let family  = texts.lens_Selection
            let focused = .view.items[.view.focusItem]
            .describeItemActions(results, "", family, focused)
            describeAction(results, "", family, texts.act_MoveSelected, .commandFolderIcon(), func|libWnd = me|() { libWnd.moveSelected() })
            .describeCommands(results, "", family, [ActionFile.DeleteCapture])

            // The rating is one choice among six, with each value drawn as its familiar star score.
            if focused.kind != .Image
            {
                let rating = results.addSection(texts.act_Rating)
                rating.inline = true
                let current = focused.capture ? focused.capture.rating : 0
                for value in 6
                {
                    let stars = cast(u8, value)
                    .addRatingEntry(rating, stars).checked = stars == current
                }
            }
        }

        // Then what the page shows, one row of segments.
        let filter = results.addSection(texts.ui_BarFilter)
        filter.inline = true
        for id in ContentFilterIds
        {
            let state      = .sendComputeCommandStateEvent(id)
            with let entry = filter.addEntry(state.name)
            {
                .checked = state.updatedFields.has(.Checked) and state.checked
                .run     = func|libWnd = me, id|() { libWnd.sendCommandEvent(id) }
            }
        }
    }

    // Returns the section of `results` labelled `label`, adding it the first time.
    func sectionOf(results: *Lens.Results, label: string)->*Lens.Section
    {
        for section in results.sections where section!.label == label do
            return section
        return results.addSection(label)
    }

    // Adds the commands of `ids` the query names, with their wording and state, under `family`.
    mtd describeCommands(results: *Lens.Results, query: string, family: string, ids: const [..] WndId)
    {
        for id in ids
        {
            let state = .sendComputeCommandStateEvent(id)
            if state.updatedFields.has(.Hidden) and state.hidden do
                continue
            if state.name.isEmpty() or not Lens.match(query, state.name).matched do
                continue

            with let entry = sectionOf(results, family).addEntry(state.name)
            {
                .disabled = state.updatedFields.has(.Disabled) and state.disabled
                .critical = state.updatedFields.has(.RenderingHint) and state.renderingHint.has(.Critical)
                .run      = func|libWnd = me, id|() { libWnd.sendCommandEvent(id) }
                if state.updatedFields.has(.Shortcut)
                {
                    .detail     = state.shortcut
                    .monoDetail = true
                }

                if state.updatedFields.has(.Checked) and state.checked do
                    .detail = LensCheck
                if state.updatedFields.has(.Icon) do
                    .glyph = state.icon
            }
        }
    }

    // Adds one action the query names under `family`, with its glyph and optional key.
    func describeAction(results: *Lens.Results, query: string, family: string, title: string, glyph: Icon, action: func||(), shortcut: string = "")
    {
        if not Lens.match(query, title).matched do
            return
        with let entry = sectionOf(results, family).addEntry(title)
        {
            .glyph      = glyph
            .detail     = shortcut
            .monoDetail = true
            .run        = action
        }
    }

    // Adds the actions on the selected captures the query names: open, export, tags, favorite
    // and rating, as the context menu of a capture offers them.
    mtd describeActions(results: *Lens.Results, query: string)
    {
        if .trashMode or .view.focusItem >= .view.items.count do
            return

        let family  = appStrings().act_Library
        let focused = .view.items[.view.focusItem]
        .describeItemActions(results, query, family, focused)
        if focused.kind == .Image do
            return

        for rating in 6 do
            discard .addRatingEntry(sectionOf(results, family), cast(u8, rating))
    }

    // Adds what can be done with the focused cell and the selection, as far as the query names it,
    // under `family`: open, then locate an image, or export, tag and favour the captures.
    mtd describeItemActions(results: *Lens.Results, query: string, family: string, focused: *LibraryItem)
    {
        let texts = appStrings()
        describeAction(results,
                       query,
                       family,
                       texts.act_OpenSelected,
                       .theme().icon(.OpenFile),
                       func|libWnd = me, focused|() { libWnd.view.openItem(focused) },
                       Input.formatKeyShortcut(.None, .Return))
        if focused.kind == .Image
        {
            describeAction(results,
                           query,
                           family,
                           texts.act_LocateImage,
                           .theme().icon(.OpenExternal),
                           func|focused|() { discard Env.showInFileExplorer(focused.fi.fullName) })
            return
        }

        describeAction(results, query, family, texts.act_ExportSelected, .theme().icon(.Export), func|libWnd = me|() { libWnd.exportSelected() })
        describeAction(results, query, family, texts.act_EditTags, .theme().icon(.Edit), func|libWnd = me|() { libWnd.editSelectedTags() })
        describeAction(results, query, family, texts.act_FavoriteCapture, .theme().icon(.Star), func|libWnd = me|() { libWnd.toggleSelectedFavorite() })
    }

    // Adds the rating `stars` to `section`: its star score, its key, and the rating of the
    // selection it sets.
    mtd addRatingEntry(section: *Lens.Section, stars: u8)->*Lens.Entry
    {
        with let entry = section.addEntry(ratingLabel(stars))
        {
            if stars != 0
            {
                .paintWidth = stars * (RatingStarSize + RatingStarGap) - RatingStarGap
                .paint      = func|libWnd = me, stars|(painter, rect) { libWnd.paintRatingStars(painter, rect, stars) }
            }

            .detail     = Input.formatKeyShortcut(.None, ratingKey(stars))
            .monoDetail = true
            .run        = func|libWnd = me, stars|() { libWnd.rateSelected(stars) }
        }

        return entry
    }

    // Adds the commands of the folder menu the query names.
    mtd describeFolderCommands(results: *Lens.Results, query: string)
    {
        let texts  = appStrings()
        let family = texts.ui_BarFolders
        describeAction(results, query, family, texts.act_OpenLibraryFolder, .commandFolderIcon(), func|libWnd = me|() { libWnd.navigateFolder(Library.getFolder()) })
        describeAction(results, query, family, texts.act_BrowseFolder, .theme().icon(.ExploreFolder), func|libWnd = me|() { libWnd.chooseFolder(false) })
        describeAction(results, query, family, texts.act_ChooseLibraryFolder, .commandFolderIcon(), func|libWnd = me|() { libWnd.chooseFolder(true) })
        describeAction(results, query, family, texts.act_UseDefaultLibrary, .theme().icon(.Undo), func|libWnd = me|() { libWnd.setLibraryFolder("") })
        .describeCommands(results, query, family, FolderIds)
    }

    // Adds the folders the query names: the library, its sub-folders and those of the folder
    // shown, the recycle bin among them.
    mtd describeFolders(results: *Lens.Results, query: string)
    {
        // The paths live on the page until the lens asks again, so a row chosen after the lens
        // closed still names its folder.
        .lensFolders.clear()
        .lensFolders.add(Library.getFolder())
        for folder in .tabFolders where not .lensFolders.contains(folder[]) do
            .lensFolders.add(folder[])
        let dirs = catch Directory.enumerateDirectories(.currentFolder())
        for d in dirs where not .lensFolders.contains(d.fullName) do
            .lensFolders.add(d.fullName)

        for entryFolder, index in .lensFolders
        {
            let folder       = entryFolder[]
            var name: String = Path.fileName(folder) orelse folder.toString()
            if folder == Library.getFolder() do
                name = appStrings().act_Library
            elif folder == Library.getTrashFolder() do
                name = appStrings().act_RecycleBin
            if not Lens.match(query, name).matched do
                continue

            with let entry = sectionOf(results, appStrings().ui_BarFolders).addEntry(name)
            {
                .glyph = me.theme().icon(.Folder)
                .run   = func|libWnd = me, index|()
                {
                    let path: String = libWnd.lensFolders[index]
                    libWnd.navigateFolder(path)
                }

                if folder == me.currentFolder() do
                    .detail = LensCheck
            }
        }
    }

    // Adds the dates the query names; choosing one narrows the library to it.
    mtd describeDates(results: *Lens.Results, query: string)
    {
        let family = appStrings().lens_Dates
        let all    = appStrings().ui_AllCaptures
        if Lens.match(query, all).matched or Lens.match(query, family).matched
        {
            with let entry = sectionOf(results, family).addEntry(all)
            {
                .glyph = me.main.icon(.Calendar)
                .run   = func|libWnd = me|() { libWnd.applyDateFilter({}) }
                if me.view.filterYear == 0 do
                    .detail = LensCheck
            }
        }

        for filter in .dateFilters
        {
            let label = dateFilterLabel(filter)
            if not Lens.match(query, label).matched do
                continue
            with let entry = sectionOf(results, family).addEntry(label)
            {
                .lead = Format.toString("%", filter.count)
                .run  = func|libWnd = me, filter|() { libWnd.applyDateFilter(filter) }
                if filter.year == me.view.filterYear and
                   filter.month == me.view.filterMonth and
                   filter.day == me.view.filterDay do
                    .detail = LensCheck
            }
        }
    }

    // Adds the applications or the tags the query names; choosing one narrows the library to it.
    //
    // A row runs after a load may have replaced the sidebar lists, so it keeps its name in
    // `lensNames`, which lives until the lens asks again, and finds it there by index.
    mtd describeNamed(results: *Lens.Results, query: string, family: string, values: *Array'LibraryNamedFilter, application: bool)
    {
        for value in values[]
        {
            let name = value.name.toString()
            if not Lens.match(query, name).matched and not Lens.match(query, family).matched do
                continue

            let index = .lensNames.count
            .lensNames.add(value.name)
            with let entry = sectionOf(results, family).addEntry(name)
            {
                .lead = Format.toString("%", value.count)
                if application do
                    .run = func|libWnd = me, index|() { libWnd.setApplicationFilter(String.from(libWnd.lensNames[index])) }
                else do
                    .run = func|libWnd = me, index|() { libWnd.setTagFilter(String.from(libWnd.lensNames[index])) }
                let active = application ? me.applicationFilter.toString() : me.tagFilter.toString()
                if Utf8.compare(value.name.toSlice(), active, .Latin1NoCase) == 0 do
                    .detail = LensCheck
            }
        }
    }

    // Returns the names of the applications, or of the tags, the loaded captures hold now. The
    // sidebar lists are brought up to date first; the filter sheet keeps a copy, since its
    // choices run after a load may have replaced them.
    mtd currentFilterNames(applications: bool)->Array'String
    {
        .refreshAutomaticFilters()
        let names = applications ? &.sidebarApplications : &.sidebarTags
        var result: #returntype
        for value in names[] do
            result.add(value.name)
        return result
    }

    // Shows how the library is presented under `btn`: thumbnail size, order, and the marks painted
    // over each thumbnail.
    mtd showViewOptions(btn: *IconButton)
    {
        let sheet = OptionSheet.View.create(me, func|libWnd = me|(page) { libWnd.describeViewOptions(page) }, owner: me)
        sheet.doModal(btn, autoDestroy: true)
    }

    mtd describeViewOptions(page: *OptionSheet.Page)
    {
        page.addCommandLink(appStrings().ui_ThumbnailSize, ThumbnailSizeIds, me, .main.icon(.ViewMedium))
        page.addCommandLink(appStrings().ui_SortBy, SortIds, me, .theme().icon(.Sort))
        page.addCommand(ActionLibSort.Invert, me)
        page.addHeading(appStrings().ui_Overlays)
        page.addCommand(ActionLibView.Ratings, me)
        page.addCommand(ActionLibView.LinkMarkers, me)
    }

    // Shows the filters under `btn`: the content kinds, the favorites, one page per application,
    // tag and rating, the link states, and the reset.
    mtd showFilterOptions(btn: *IconButton)
    {
        let sheet = OptionSheet.View.create(me, func|libWnd = me|(page) { libWnd.describeFilterOptions(page) }, owner: me)
        sheet.doModal(btn, autoDestroy: true)
    }

    mtd describeFilterOptions(page: *OptionSheet.Page)
    {
        let texts = appStrings()
        page.addCommandLink(texts.ui_FilterContent, ContentFilterIds, me, .theme().icon(.Filter))
        page.addCommand(ActionLibFilter.FavoritesOnly, me)

        let application = .applicationFilter.isEmpty() ? texts.act_AllApplications : .applicationFilter.toString()
        page.addLink(texts.act_Application,
                     application,
                     func|libWnd = me|(choices)
                     {
                         choices.addChoice(appStrings().act_AllApplications, libWnd.applicationFilter.isEmpty(), func|libWnd|() { libWnd.setApplicationFilter("") })
                         libWnd.applicationChoices = libWnd.currentFilterNames(applications: true)
                         for one, index in libWnd.applicationChoices
                         {
                             let on = Utf8.compare(one.toSlice(), libWnd.applicationFilter, .Latin1NoCase) == 0
                             choices.addChoice(one.toString(), on, func|libWnd, index|() { libWnd.setApplicationFilter(String.from(libWnd.applicationChoices[index])) })
                         }
                     },
                     icon: .theme().icon(.OpenExternal))

        let tag = .tagFilter.isEmpty() ? texts.act_AllTags : .tagFilter.toString()
        page.addLink(texts.act_Tags,
                     tag,
                     func|libWnd = me|(choices)
                     {
                         choices.addChoice(appStrings().act_AllTags, libWnd.tagFilter.isEmpty(), func|libWnd|() { libWnd.setTagFilter("") })
                         libWnd.tagChoices = libWnd.currentFilterNames(applications: false)
                         for one, index in libWnd.tagChoices
                         {
                             let on = Utf8.compare(one.toSlice(), libWnd.tagFilter, .Latin1NoCase) == 0
                             choices.addChoice(one.toString(), on, func|libWnd, index|() { libWnd.setTagFilter(String.from(libWnd.tagChoices[index])) })
                         }
                     },
                     icon: .theme().icon(.Edit))

        page.addCommandLink(texts.ui_FilterRating, RatingFilterIds, me, .theme().icon(.Star))
        page.addLink(texts.ui_FilterLinks,
                     "",
                     func|libWnd = me|(links)
                     {
                         for id in LinkFilterIds do
                             links.addCommand(id, libWnd)
                     },
                     icon: .theme().icon(.Link))

        page.addCommand(ActionLibFilter.Reset, me)
    }

    // Shows only the captures of the application `name`, or every capture when it is empty.
    mtd setApplicationFilter(name: string)
    {
        .applicationFilter = name
        .view.filter()
    }

    // Shows only the captures tagged `name`, or every capture when it is empty.
    mtd setTagFilter(name: string)
    {
        .tagFilter = name
        .view.filter()
        .updateTagChips()
    }

    // Paints a rating as the number of familiar filled stars represented by its choice.
    mtd paintRatingStars(painter: *Painter, rect: Math.Rectangle, rating: u8)
    {
        let size  = RatingStarSize
        let color = .themeColors().arc
        let star  = .theme().icon(.StarFilled, size)
        let y     = Math.round(rect.vertCenter() - size * 0.5)
        for i in rating do
            star.paint(painter, rect.x + i * (size + RatingStarGap), y, color)
    }
}

// The library's 0 to 5 rating shortcuts, in the same order as `ratingLabel`.
func ratingKey(rating: u8)->Input.Key
{
    switch rating
    {
    case 0:  return .D0
    case 1:  return .D1
    case 2:  return .D2
    case 3:  return .D3
    case 4:  return .D4
    default: return .D5
    }
}

const RatingStarSize = 13'f32
const RatingStarGap  = 2'f32

// The commands each group of the library options offers, in the order a page lists them. A page
// borrows its identifiers, which these constants keep alive for as long as the program runs.
const ThumbnailSizeIds = [ActionRecentSize.LibSmall, ActionRecentSize.LibMedium, ActionRecentSize.LibBig]
const SortIds          = [ActionLibSort.Recent, ActionLibSort.Modified, ActionLibSort.Name, ActionLibSort.Application, ActionLibSort.WindowTitle, ActionLibSort.Dimensions, ActionLibSort.FileSize, ActionLibSort.Similar]
const ContentFilterIds = [ActionLibFilter.AllItems, ActionLibFilter.Captures, ActionLibFilter.Animations, ActionLibFilter.ScreenCaptures, ActionLibFilter.ImportedCaptures, ActionLibFilter.Images]
const RatingFilterIds  = [ActionLibFilter.RatingAny, ActionLibFilter.Rating1, ActionLibFilter.Rating2, ActionLibFilter.Rating3, ActionLibFilter.Rating4, ActionLibFilter.Rating5]
const LinkFilterIds    = [ActionLibFilter.UpToDateLinkedImage, ActionLibFilter.UnSavedLinkedImage, ActionLibFilter.LinkedImage, ActionLibFilter.UnLinkedImage]
const OverlayIds       = [ActionLibSort.Invert, ActionLibView.Ratings, ActionLibView.LinkMarkers]
const FolderIds        = [ActionLibTrash.Toggle, ActionLibTrash.Empty]
const SelectionIds     = [ActionFile.CopyImage, ActionFile.RenameCapture, ActionFile.DeleteCapture, ActionFile.CaptureFileLocation, ActionFile.LinkedFileLocation, ActionFile.FileDetails, ActionLibTrash.Restore, ActionLibTrash.DeleteForever]

// The mark of the choice in force, at the end of its row of the lens.
const LensCheck = "✓"
