using Threading, Time

// The date column. It is wider than the editor's tool column on purpose: the tool column carries
// one word per row and this one carries a sentence — "All Items" is two words in English and
// three in French, and a column sized to the English would clip the French in the very first row.
const SideBarWidth = 280.0
const LibButtonGap = 12.0

// The count column of the date list, and what the rows spend before their name: the expander lane
// the tree reserves on every row, plus the padding of the list. The name column takes what those
// two leave, so widening the bar widens the only column that carries wording.
const LibCountWidth = 56.0
const LibRowIndent  = 28.0

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

// Which kinds of entries the library shows.
enum LibraryContentFilter
{
    All
    Captures
    ScreenCaptures
    ImportedCaptures
    Images
}

// The groups the library sidebar filters by.
enum LibrarySidebarFilter
{
    Date
    Application
    Tag
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

// The library page: the sidebar, the command bar, the thumbnail grid, and the search and
// folder they act on.
struct LibraryWnd
{
    using wnd: Wnd

    late
    {
        main:        *MainWnd
        view:        *LibraryView
        sideBar:     *Wnd
        barPanel:    *Wnd
        captureHost: *ScrollWnd
        listCtrl:    *ListCtrl
        commandBar:  *StackLayoutCtrl
        viewBtn:     *IconButton
        sortBtn:     *IconButton
        filterBtn:   *IconButton
        folderBtn:   *IconButton
        searchEdit:  *EditBox
        breadcrumb:  *BreadcrumbCtrl
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
    // Whether a filter on what a capture holds is active: favorites, rating, application, or tag.
    mtd const filtersMetadata()->bool => .favoritesOnly or .minimumRating or not .applicationFilter.isEmpty() or not .tagFilter.isEmpty()

    mtd applyLanguage()
    {
        if .viewBtn == null do
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

    mtd getCapture()->*Capture?
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

    mtd const hasSelected()->bool => not .view.selModel.isEmpty()

    // Fills the library from the index, once per index revision, and hooks the delete notification
    // the first time.
    mtd fill()
    {
        if not g_Library.loaded do
            g_Library.fill()

        if .listCtrl.lineCount() and .filledRevision == g_Library.revision do
            return

        if not .deleteObserverRegistered
        {
            g_Library.onDeleteFile += func|libWnd = me|(file)
            {
                // The loader owns a temporary pointer list. Join it before deleting the
                // corresponding ArrayPtr element, then resume any pending previews.
                libWnd.view.stopLoading()

                for item, i in libWnd.view.items
                {
                    if item.fi.fullName == file
                    {
                        libWnd.view.selModel.unselect(cast(i))
                        libWnd.view.items.removeAtOrdered(i)
                        break
                    }
                }

                for item, i in libWnd.view.allItems where item!.fi.fullName == file
                {
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
    }

    // Update the live text filter and rebuild the visible set.
    mtd setSearch(text: String)
    {
        .searchText = text
        .view.filter()
        .invalidate()
    }

    // Builds the library window: the sidebar and the item grid under the breadcrumb and the search
    // bar.
    func create(parent: *MainWnd)->*LibraryWnd
    {
        let metrics = parent.themeMetrics()

        with let result = Wnd.create'LibraryWnd(parent, "capture.librarywnd")
        {
            .main            = parent
            .dockStyle       = .Center
            .backgroundStyle = .ToolBar
            .padding         = {metrics.panel_GutterSize, metrics.panel_GutterSize, metrics.panel_GutterSize, metrics.panel_GutterSize}
            .registerActions()
        }

        // One rule holds both modes of the window: what can be picked stands on the left,
        // what is picked is shown on the right. The editor puts its tools on the left and
        // the selected form on the right; the library puts its dates on the left and the
        // captures themselves fill the rest. A date list on the right would swap the meaning
        // of the same edge when switching modes.
        with result.sideBar = Wnd.create'Wnd(result, {0, 0, SideBarWidth, 0})
        {
            .dockStyle       = .Left
            .backgroundStyle = .Panel
            .margin.z        = metrics.panel_GutterSize
            .padding         = {0, 8, 0, 8}
        }

        // The path and command rows are chrome and the captures are content. One panel holding
        // both would make the recessed capture ground read as a square dropped inside a larger
        // box, so each role stands on its own panel, parted by the same gutter that already
        // separates the rail from this column.
        with result.barPanel = Wnd.create'Wnd(result, {0, 0, 0, 2 * themeActionButtonSize(metrics)})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Panel
            .margin.w        = metrics.panel_GutterSize
        }

        result.createCaptureGrid()
        result.createDateList()
        result.createBreadcrumb()
        result.createCommandBar()

        result.setPreviewSize(.Small)
        result.setSortMethod(result.sortMethod)
        result.updateBreadcrumb()
        return result
    }
}
