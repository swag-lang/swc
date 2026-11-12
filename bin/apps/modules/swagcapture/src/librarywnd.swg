using Threading, Time

// Air between two quiet menus of the title row.
const LibButtonGap = 12.0

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

    // The folder each tab opens, in the order of the tabs.
    tabFolders:   Array'String
    updatingTabs: bool

    // The folders the lens offered last, which its rows open.
    lensFolders: Array'String

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
            let file = String.from(videoCopy.source)
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
            copy.source = Capture.mediaPathOf(file, .Video)
            copy.target = Library.uniqueName(.exportFolder, name)
            .videoCopyJob = copy
            copy.task.submit(func|copy|()
            {
                catch exportOriginalVideo(copy.source, copy.target) as copy.error
            }, .taskNotifier(&copy.task))
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

        .viewBtn.setText(appStrings().ui_BarView)
        .filterBtn.setText(appStrings().ui_BarFilter)
        .folderBtn.setText(appStrings().ui_BarFolders)
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
            else do
                .hintLine.addHint(Input.formatKeyShortcut(.Control, .Space), texts.hint_Space)
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
