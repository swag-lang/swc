#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, File

struct LibraryRejectAllocator {}

impl IAllocator for LibraryRejectAllocator
{
    mtd impl alloc(request: *AllocatorRequest) { request.address = null }
    mtd impl realloc(request: *AllocatorRequest) { request.address = null }
    mtd impl free(_: *AllocatorRequest) {}
}

// Library actions can be exercised against an empty headless library window:
// sorting/filtering and command states do not require scanning the user's files.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    discard f.setupLibraryWnd()
    let libWnd = cast(*Wnd, f.main.libWnd)

    var sizeEvt = Gui.Testing.commandState(ActionRecentSize.LibBig)
    Swag.assert(Gui.Testing.actionUpdate'ActionRecentSize(f.main, ActionRecentSize.LibBig, &sizeEvt))
    Swag.assert(not sizeEvt.checked)
    f.main.sendCommandEvent(ActionRecentSize.LibBig)
    Swag.assert(f.main.libWnd.previewSize == .Big)
    var actionExecuted = Gui.Testing.actionExecute'ActionRecentSize(f.main, ActionRecentSize.LibMedium)
    Swag.assert(actionExecuted)
    Swag.assert(f.main.libWnd.previewSize == .Medium)
    actionExecuted = Gui.Testing.actionExecute'ActionRecentSize(f.main, ActionRecentSize.LibSmall)
    Swag.assert(actionExecuted)
    Swag.assert(f.main.libWnd.previewSize == .Small)

    var overlayEvt = Gui.Testing.commandState(ActionLibView.Ratings)
    Swag.assert(Gui.Testing.actionUpdate'ActionLibView(libWnd, ActionLibView.Ratings, &overlayEvt))
    Swag.assert(overlayEvt.checked)
    actionExecuted = Gui.Testing.actionExecute'ActionLibView(libWnd, ActionLibView.Ratings)
    Swag.assert(actionExecuted)
    Swag.assert(not f.main.libWnd.showRatingOverlay)
    actionExecuted = Gui.Testing.actionExecute'ActionLibView(libWnd, ActionLibView.LinkMarkers)
    Swag.assert(actionExecuted)
    Swag.assert(not f.main.libWnd.showLinkOverlay)

    Swag.assert(ratingLabel(0) == appStrings().act_NoRating)
    Swag.assert(ratingLabel(3) == appStrings().act_Rating3)
    Swag.assert(ratingLabel(5) == appStrings().act_Rating5)

    with f.main.recentBar = Wnd.create'Wnd(f.main, {0, 0, 0, 128})
    {
        .dockStyle = .Bottom
    }

    actionExecuted = Gui.Testing.actionExecute'ActionRecentSize(f.main, ActionRecentSize.RecentSmall)
    Swag.assert(actionExecuted)
    Swag.assert(f.main.bottomSize == .Small)
    actionExecuted = Gui.Testing.actionExecute'ActionRecentSize(f.main, ActionRecentSize.RecentMedium)
    Swag.assert(actionExecuted)
    Swag.assert(f.main.bottomSize == .Medium)
    actionExecuted = Gui.Testing.actionExecute'ActionRecentSize(f.main, ActionRecentSize.RecentBig)
    Swag.assert(actionExecuted)
    Swag.assert(f.main.bottomSize == .Big)

    var evt = Gui.Testing.commandState(ActionLibSort.Recent)
    Swag.assert(Gui.Testing.actionUpdate'ActionLibSort(libWnd, ActionLibSort.Recent, &evt))
    Swag.assert(evt.checked)

    libWnd.sendCommandEvent(ActionLibSort.FileSize)
    Swag.assert(f.main.libWnd.sortMethod == .FileSize)

    evt = Gui.Testing.commandState(ActionLibSort.Invert)
    Swag.assert(Gui.Testing.actionUpdate'ActionLibSort(libWnd, ActionLibSort.Invert, &evt))
    Swag.assert(not evt.name.isEmpty())
    Swag.assert(not evt.disabled)

    libWnd.sendCommandEvent(ActionLibSort.Invert)
    Swag.assert(f.main.libWnd.invertSort)

    libWnd.sendCommandEvent(ActionLibSort.Similar)
    evt = Gui.Testing.commandState(ActionLibSort.Invert)
    Swag.assert(Gui.Testing.actionUpdate'ActionLibSort(libWnd, ActionLibSort.Invert, &evt))
    Swag.assert(evt.disabled)

    evt = Gui.Testing.commandState(ActionLibFilter.LinkedImage)
    Swag.assert(Gui.Testing.actionUpdate'ActionLibFilter(libWnd, ActionLibFilter.LinkedImage, &evt))
    Swag.assert(evt.checked)
    libWnd.sendCommandEvent(ActionLibFilter.LinkedImage)
    Swag.assert(not f.main.libWnd.showLinkedImage)

    f.main.libWnd.contentFilter     = .Images
    f.main.libWnd.favoritesOnly     = true
    f.main.libWnd.minimumRating     = 4
    f.main.libWnd.applicationFilter = "chrome"
    f.main.libWnd.tagFilter         = "docs"
    libWnd.sendCommandEvent(ActionLibFilter.Reset)
    Swag.assert(f.main.libWnd.contentFilter == .All)
    Swag.assert(not f.main.libWnd.favoritesOnly)
    Swag.assert(f.main.libWnd.minimumRating == 0)
    Swag.assert(f.main.libWnd.applicationFilter.isEmpty())
    Swag.assert(f.main.libWnd.tagFilter.isEmpty())
    Swag.assert(f.main.libWnd.showLinkedImage)

    evt = Gui.Testing.commandState(ActionLibSel.Right)
    Swag.assert(Gui.Testing.actionUpdate'ActionLibSel(libWnd, ActionLibSel.Right, &evt))
    Swag.assert(evt.disabled)

    f.main.libWnd.view.focusItem = 0
    evt = Gui.Testing.commandState(ActionLibSel.Right)
    Swag.assert(Gui.Testing.actionUpdate'ActionLibSel(libWnd, ActionLibSel.Right, &evt))
    Swag.assert(not evt.disabled)
}

// Library view filtering, sorting and keyboard-style movement operate entirely
// on in-memory items; no filesystem scan or preview loading is required.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let lib  = f.setupLibraryWnd()
    let view = lib.view
    let wnd  = cast(*Wnd, lib)

    let old   = testAddLibraryItem(view, "old.scc", 10, 1)
    let big   = testAddLibraryItem(view, "big-linked.scc", 30, 3, "big.png")
    let dirty = testAddLibraryItem(view, "dirty-linked.scc", 20, 2, "dirty.png", linkedUpToDate: false)

    view.filterDay = 2
    view.filter()
    Swag.assert(view.items.count == 1)
    Swag.assert(view.items[0] == dirty)
    view.filterDay = 0
    view.filter()

    lib.sortMethod = .FileSize
    lib.invertSort = false
    view.sort()
    Swag.assert(view.items[0] == big)
    Swag.assert(view.items[1] == dirty)
    Swag.assert(view.items[2] == old)

    lib.invertSort = true
    view.sort()
    Swag.assert(view.items[0] == old)
    Swag.assert(view.items[1] == dirty)
    Swag.assert(view.items[2] == big)

    lib.sortMethod = .Recent
    lib.invertSort = false
    view.sort()
    Swag.assert(view.items[0] == big)
    Swag.assert(view.items[1] == dirty)
    Swag.assert(view.items[2] == old)

    lib.showUnSavedLinkedImage = false
    view.filter()
    Swag.assert(view.items.count == 2)
    Swag.assert(view.items.contains(old))
    Swag.assert(view.items.contains(big))
    Swag.assert(not view.items.contains(dirty))

    lib.showUnSavedLinkedImage = true
    lib.showLinkedImage        = false
    view.filter()
    Swag.assert(view.items.count == 1)
    Swag.assert(view.items[0] == old)

    lib.showLinkedImage = true
    view.filter()
    view.sort()

    wnd.sendCommandEvent(ActionLibFilter.UpToDateLinkedImage)
    Swag.assert(not lib.showUpToDateLinkedImage)
    Swag.assert(view.items.count == 2)
    Swag.assert(view.items.contains(old))
    Swag.assert(not view.items.contains(big))
    Swag.assert(view.items.contains(dirty))

    wnd.sendCommandEvent(ActionLibFilter.UpToDateLinkedImage)
    wnd.sendCommandEvent(ActionLibFilter.UnSavedLinkedImage)
    Swag.assert(not lib.showUnSavedLinkedImage)
    Swag.assert(view.items.count == 2)
    Swag.assert(view.items.contains(old))
    Swag.assert(view.items.contains(big))
    Swag.assert(not view.items.contains(dirty))

    wnd.sendCommandEvent(ActionLibFilter.UnSavedLinkedImage)
    wnd.sendCommandEvent(ActionLibFilter.UnLinkedImage)
    Swag.assert(not lib.showUnLinkedImage)
    Swag.assert(view.items.count == 2)
    Swag.assert(not view.items.contains(old))
    Swag.assert(view.items.contains(big))
    Swag.assert(view.items.contains(dirty))

    wnd.sendCommandEvent(ActionLibFilter.UnLinkedImage)
    view.filter()
    view.sort()
    view.focusItem = 1
    wnd.sendCommandEvent(ActionLibSel.Home)
    Swag.assert(view.focusItem == 0)
    Swag.assert(view.selModel.isSelected(0))

    wnd.sendCommandEvent(ActionLibSel.Right)
    Swag.assert(view.focusItem == 1)
    Swag.assert(view.selModel.isSelected(1))
    Swag.assert(not view.selModel.isSelected(0))

    wnd.sendCommandEvent(ActionLibSel.End)
    Swag.assert(view.focusItem == 2)
    Swag.assert(view.selModel.isSelected(2))

    wnd.sendCommandEvent(ActionLibSel.Left)
    Swag.assert(view.focusItem == 1)

    lib.previewSize = .Medium
    view.setPosition({0, 0, 360, 420})
    view.focusItem = 0
    wnd.sendCommandEvent(ActionLibSel.Down)
    Swag.assert(view.focusItem == 1)
    Swag.assert(view.selModel.isSelected(1))

    wnd.sendCommandEvent(ActionLibSel.Up)
    Swag.assert(view.focusItem == 0)
    Swag.assert(view.selModel.isSelected(0))
}

// Deleting a multi-selection removes every selected capture, even though the
// onDeleteFile handler removes items from view.items as each file goes away
// (regression: iterating the list while it was mutated used to skip entries).
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    expect Library.init()
    g_Library.files.clear()
    g_Library.loaded = true
    g_Library.onDeleteFile.clear()

    let lib  = f.setupLibraryWnd()
    let view = lib.view

    // Mirror the handler LibraryWnd.fill() installs: drop the matching view item.
    g_Library.onDeleteFile += func|libWnd = lib|(file)
    {
        for it, i in libWnd.view.items
        {
            if it.fi.fullName == file
            {
                libWnd.view.selModel.unselect(cast(i))
                libWnd.view.items.removeAtOrdered(i)
                break
            }
        }
    }

    // Three real capture files, registered in the library and the view.
    var paths: Array'String
    for idx in 3
    {
        let capture = Memory.new'Capture()
        capture.width, capture.widthOrg   = 8
        capture.height, capture.heightOrg = 6
        capture.backImg = Gui.Testing.indexedImage(8, 6)
        let path = testTempCapturePath()
        capture.file    = path
        capture.changed = true
        expect capture.save()
        Swag.assert(File.exists(path))
        Memory.delete(capture)

        g_Library.addFile(path)
        discard testAddLibraryItem(view, path, size: 8, day: cast(u16, idx + 1))
        paths.add(path)
    }

    defer
    {
        for p in paths
        {
            discard catch File.delete(p[])
            discard catch File.delete(Path.combine(Library.getTrashFolder(), Path.fileName(p[])))
        }

        g_Library.files.clear()
        g_Library.onDeleteFile.clear()
    }

    Swag.assert(view.items.count == 3)
    Swag.assert(g_Library.files.count == 3)

    for idx in view.items.count do
        view.selModel.select(cast(idx))

    lib.removeSelected()

    // Every selection is gone from the view, the library, and its original location,
    // but soft-delete keeps a recoverable copy in the recycle bin.
    Swag.assert(view.items.count == 0)
    Swag.assert(g_Library.files.count == 0)
    for p in paths
    {
        Swag.assert(not File.exists(p[]))
        Swag.assert(File.exists(Path.combine(Library.getTrashFolder(), Path.fileName(p[]))))
    }
}

// The library search box matches captures by title, linked image path or file name,
// case-insensitively; unrelated captures are filtered out of the visible set. Clearing
// the search restores the full list.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let lib  = f.setupLibraryWnd()
    let view = lib.view

    discard testAddLibraryItem(view, "alpha.scc", 10, 1, title: "Login screen")
    discard testAddLibraryItem(view, "beta.scc", 10, 2, "report.png", title: "Sales chart")
    discard testAddLibraryItem(view, "gamma.scc", 10, 3, title: "Login error")

    lib.setSearch("login")
    Swag.assert(view.items.count == 2)

    lib.setSearch("REPORT")
    Swag.assert(view.items.count == 1)
    Swag.assert(view.items[0].fi.fullName == "beta.scc")

    lib.setSearch("gamma")
    Swag.assert(view.items.count == 1)
    Swag.assert(view.items[0].fi.fullName == "gamma.scc")

    lib.setSearch("nomatch")
    Swag.assert(view.items.count == 0)

    lib.setSearch("")
    Swag.assert(view.items.count == 3)
}

// Filling the date sidebar from a fresh (empty) list must open the year/month/day
// group lines correctly: the group trackers start null and the FIRST file already
// flushes/opens groups, so an uninitialized tracker would be read before any
// assignment (this crashed in release when showing the library view).
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.main.libWnd = LibraryWnd.create(f.main)
    let libWnd = f.main.libWnd

    let oldLibraryLoaded = g_Library.loaded
    defer
    {
        g_Library.files.clear()
        g_Library.loaded = oldLibraryLoaded
    }

    g_Library.loaded = true
    g_Library.files.clear()

    var fi: File.FileInfo
    fi.fullName = "libfill_a.scc"
    fi.lastWriteTime.year  = 2024
    fi.lastWriteTime.month = 5
    fi.lastWriteTime.day   = 11
    g_Library.files.add(fi)
    fi.fullName = "libfill_b.scc"
    fi.lastWriteTime.day = 10
    g_Library.files.add(fi)
    fi.fullName = "libfill_c.scc"
    fi.lastWriteTime.year  = 2023
    fi.lastWriteTime.month = 1
    fi.lastWriteTime.day   = 2
    g_Library.files.add(fi)

    Swag.assert(libWnd.dateFilters.isEmpty())
    libWnd.fill()

    // The dates the lens offers: each year, then its months, then their days, newest first,
    // each with the captures it holds.
    Swag.assert(libWnd.dateFilters.count == 7)
    Swag.assert(libWnd.dateFilters[0].year == 2024 and libWnd.dateFilters[0].month == 0 and libWnd.dateFilters[0].count == 2)
    Swag.assert(libWnd.dateFilters[1].month == 5 and libWnd.dateFilters[1].day == 0 and libWnd.dateFilters[1].count == 2)
    Swag.assert(libWnd.dateFilters[2].day == 11 and libWnd.dateFilters[2].count == 1)
    Swag.assert(libWnd.dateFilters[3].day == 10)
    Swag.assert(libWnd.dateFilters[4].year == 2023 and libWnd.dateFilters[4].count == 1)
    Swag.assert(libWnd.dateFilters[5].month == 1 and libWnd.dateFilters[6].day == 2)
    Swag.assert(libWnd.view.items.count == 3)

    // Narrowing to a date keeps its captures only.
    libWnd.applyDateFilter(libWnd.dateFilters[3])
    Swag.assert(libWnd.view.items.count == 1)
    libWnd.applyDateFilter({})
    Swag.assert(libWnd.view.items.count == 3)

    // A second fill of the same revision keeps the dates as they are.
    libWnd.fill()
    Swag.assert(libWnd.dateFilters.count == 7)

    libWnd.view.thread.safeForceEnd()
    libWnd.view.thread.wait()
}

// Source metadata, tags, favorites and ratings are first-class filters, and the sort
// families use the same metadata rather than falling back to file-system accidents.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let lib  = f.setupLibraryWnd()
    let view = lib.view

    let chrome = testAddLibraryItem(view, "chrome.scc", 30, 2, title: "Documentation")
    chrome.capture!.sourceKind       = .Screen
    chrome.capture.sourceApplication = "chrome"
    chrome.capture.sourceWindowTitle = "Swag language reference"
    chrome.capture.tags.add("docs")
    chrome.capture.favorite = true
    chrome.capture.rating   = 5
    chrome.width            = 1920
    chrome.height           = 1080

    let slack = testAddLibraryItem(view, "slack.scc", 20, 3, title: "Team")
    slack.capture!.sourceKind       = .Screen
    slack.capture.sourceApplication = "slack"
    slack.capture.sourceWindowTitle = "Engineering"
    slack.capture.tags.add("work")
    slack.capture.rating = 2
    slack.width          = 800
    slack.height         = 600

    let imported = testAddLibraryItem(view, "imported.scc", 10, 1, "photo.png", title: "Photo")
    imported.capture!.sourceKind = .ImageFile
    imported.width  = 400
    imported.height = 300

    with let image = view.allItems.addNew()
    {
        .fi.fullName = "wallpaper.png"
        .kind        = .Image
        .loaded      = true
        .width       = 2560
        .height      = 1440
    }

    view.items.add(image)

    lib.contentFilter = .ScreenCaptures
    view.filter()
    Swag.assert(view.items.count == 2)
    Swag.assert(view.items.contains(chrome))
    Swag.assert(view.items.contains(slack))

    lib.contentFilter = .Images
    view.filter()
    Swag.assert(view.items.count == 1)
    Swag.assert(view.items[0] == image)

    lib.contentFilter     = .All
    lib.applicationFilter = "CHROME"
    view.filter()
    Swag.assert(view.items.count == 1)
    Swag.assert(view.items[0] == chrome)

    lib.applicationFilter.clear()
    lib.tagFilter = "DOCS"
    view.filter()
    Swag.assert(view.items.count == 1)
    Swag.assert(view.items[0] == chrome)

    lib.tagFilter.clear()
    lib.favoritesOnly = true
    view.filter()
    Swag.assert(view.items.count == 1)
    Swag.assert(view.items[0] == chrome)

    lib.favoritesOnly = false
    lib.minimumRating = 3
    view.filter()
    Swag.assert(view.items.count == 1)
    Swag.assert(view.items[0] == chrome)

    lib.minimumRating = 0
    lib.setSearch("language reference")
    Swag.assert(view.items.count == 1)
    Swag.assert(view.items[0] == chrome)
    lib.setSearch("")

    lib.sortMethod = .Application
    view.sort()
    Swag.assert(view.items.back() == slack)

    lib.sortMethod = .Dimensions
    view.sort()
    Swag.assert(view.items[0] == image)

    lib.sortMethod = .Name
    view.sort()
    Swag.assert(view.items[0] == chrome)

    for item, i in view.items where item == slack do
        view.setFocusItem(cast(u32, i))
    lib.sortMethod = .Dimensions
    view.sort()
    Swag.assert(view.focusItem < view.items.count)
    Swag.assert(view.items[view.focusItem] == slack)
    Swag.assert(view.selModel.isSelected(view.focusItem))
}

// A regular image file is decoded into its own preview item. It never masquerades as a
// Capture until the user opens it in the editor.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let lib  = f.setupLibraryWnd()
    let view = lib.view

    let path = Gui.Testing.tempFilePath("capture-library-image-", ".png")
    defer discard catch File.delete(path)
    var source = Gui.Testing.indexedImage(48, 32)
    expect source.save(path)

    with let item = view.allItems.addNew()
    {
        .fi.fullName = path
        .kind        = .Image
    }

    view.items.add(item)
    view.loadOne(item)

    Swag.assert(item.loaded)
    Swag.assert(not item.capture)
    Swag.assert(item.image.isValid())
    Swag.assert(item.width == 48)
    Swag.assert(item.height == 32)
    Swag.assert(item.haar.size != 0)

    f.main.libraryMode = true
    view.focusItem     = 0
    var deleteState = Gui.Testing.commandState(ActionFile.DeleteCapture)
    Swag.assert(Gui.Testing.actionUpdate'ActionFile(f.main, ActionFile.DeleteCapture, &deleteState))
    Swag.assert(deleteState.disabled)
}

// The root is configurable, indexes captures and ordinary images together, and remains
// the destination used for newly created capture files.
#test
{
    testUseScratchLibrary()
    let root = Gui.Testing.tempFilePath("capture-library-root-", "")
    expect Directory.create(root)

    let capturePath = Path.combine(root, "sample.scc")
    let imagePath   = Path.combine(root, "sample.png")
    defer
    {
        discard catch File.delete(capturePath)
        discard catch File.delete(imagePath)
        discard catch Directory.delete(Path.combine(root, ".trash"))
        discard catch Directory.delete(root)
        discard catch g_Library.setFolder("")
    }

    let capture = Memory.new'Capture()
    capture.width, capture.widthOrg   = 8
    capture.height, capture.heightOrg = 6
    capture.backImg                   = Gui.Testing.indexedImage(8, 6)
    capture.file                      = capturePath
    capture.changed                   = true
    expect capture.save()
    Swag.assert(Capture.isFile(capturePath))

    // A listing classifies by name, so a folder of several hundred captures is not opened
    // once per row before the window can show anything.
    Swag.assert(Capture.isFileName(capturePath))
    Swag.assert(not Capture.isFileName(imagePath))
    Memory.delete(capture)

    var image = Gui.Testing.indexedImage(10, 7)
    expect image.save(imagePath)

    let previousRoot = Library.getFolder()
    var invalidRootErrorOutcome: Swag.Error
    discard catch g_Library.setFolder(capturePath) as invalidRootErrorOutcome
    let invalidRootError = invalidRootErrorOutcome.value()
    Swag.assert(invalidRootError != null)
    Swag.assert(Library.getFolder() == previousRoot)

    expect g_Library.setFolder(root)
    g_Library.fill()
    Swag.assert(Library.getFolder() == root)
    Swag.assert(g_Library.files.count == 2)
    let generatedFile      = Library.newFileName()
    let generatedDirectory = Path.directoryName(generatedFile)
    Swag.assert(generatedDirectory != null)
    Swag.assert(Path.equals(generatedDirectory, root))
    Swag.assert(Path.lowercaseExtension(generatedFile) == CaptureFileExtension)
}

// The library page keeps its header on every folder: the quiet menus and the search stand on the
// row of the title, the captures start under the tabs, and nothing boxes either.
#test
{
    var f: HeadlessFixture
    f.setup(width: 1100, height: 700)
    defer f.shutdown()

    g_Library.loaded = true
    g_Library.files.clear()
    f.main.libWnd = LibraryWnd.create(f.main)
    with let lib = f.main.libWnd
    {
        .setPosition({0, 0, 1100, 700})
        .applyLayout()
        .commandBar.computeLayout()
    }

    Swag.assert((lib.folderBtn.text()).count != 0)
    Swag.assert(lib.commandBar.children.count == 4)
    Swag.assert(lib.filterBtn.position.x - lib.viewBtn.position.right() == LibButtonGap)
    Swag.assert(lib.folderBtn.position.x - lib.filterBtn.position.right() == LibButtonGap)
    Swag.assert(lib.searchEdit.surfaceRect().right() == lib.surfaceRect().right() - LibraryPageMargin)
    Swag.assert(lib.captureHost.position.y >= lib.header.position.bottom())
    Swag.assert(lib.captureHost.backgroundStyle == .Transparent)

    lib.setTrashMode(true)
    Swag.assert(lib.header.isLocallyVisible() and lib.titleLabel.name == appStrings().act_RecycleBin)
    lib.setTrashMode(false)
    Swag.assert(lib.titleLabel.name == appStrings().act_Library)

    let chrome = testAddLibraryItem(lib.view, "chrome.scc", 10, 1)
    chrome.capture!.sourceApplication = "Chrome"
    chrome.capture.sourceExecutable   = Env.executablePath()
    chrome.capture.tags.add("docs")
    let slack = testAddLibraryItem(lib.view, "slack.scc", 10, 2)
    slack.capture!.sourceApplication = "Slack"
    slack.capture.tags.add("work")
    lib.refreshAutomaticFilters()

    Swag.assert(lib.sidebarApplications.count == 2)
    Swag.assert(lib.sidebarApplications[0].name == "Chrome")
    Swag.assert(lib.sidebarApplications[0].executable == Env.executablePath())
    Swag.assert(lib.sidebarApplications[0].count == 1)
    Swag.assert(lib.sidebarTags.count == 2)

    // Comparing unchanged filters only borrows their elements. A copied array would try to
    // allocate through its retained allocator and turn this no-op refresh into a panic.
    let applicationsAllocator = lib.sidebarApplications.allocator
    let tagsAllocator         = lib.sidebarTags.allocator
    var rejectAllocator: LibraryRejectAllocator
    let reject: IAllocator    = &rejectAllocator
    lib.sidebarApplications.allocator = reject
    lib.sidebarTags.allocator         = reject
    defer
    {
        lib.sidebarApplications.allocator = applicationsAllocator
        lib.sidebarTags.allocator         = tagsAllocator
    }

    lib.refreshAutomaticFilters()

    // The applications are lens entries; choosing one narrows the library to it.
    var results: Lens.Results
    lib.describeLens(&results)
    var chromeEntry: *Lens.Entry?
    for section in results.sections where section!.label == appStrings().act_Application
    {
        for &entry in section.entries where entry.title == "Chrome" do
            chromeEntry = entry
    }

    let chromeRun = unwrap (unwrap chromeEntry).run
    chromeRun()
    Swag.assert(lib.applicationFilter == "Chrome")
    Swag.assert(lib.view.items.count == 1)
    Swag.assert(lib.view.items[0] == chrome)

    // The tags are chips: choosing one narrows the library to it and leaves the application.
    lib.setApplicationFilter("")
    var workChip: *IconButton?
    for child in lib.tagChips.children
    {
        let chip = assume cast(*IconButton, child)
        if chip.text() == "work" do
            workChip = chip
    }

    f.gui.clickWnd(unwrap workChip)
    Swag.assert(lib.applicationFilter.isEmpty())
    Swag.assert(lib.tagFilter == "work")
    Swag.assert(lib.view.items.count == 1)
    Swag.assert(lib.view.items[0] == slack)
}

// At rest the lens offers what can be done with the chosen captures — open, export, tags,
// favourite, move, delete — and their rating as one row of segments, then what the page shows;
// with none chosen, what the page shows only.
#test
{
    var f: HeadlessFixture
    f.setup(width: 1100, height: 700)
    defer f.shutdown()
    testRegisterIoActions(f.main)

    g_Library.loaded = true
    g_Library.files.clear()
    f.main.libWnd = LibraryWnd.create(f.main)
    let lib = f.main.libWnd
    lib.setPosition({0, 0, 1100, 700})
    lib.applyLayout()
    f.main.libraryMode = true

    // The first capture is a real file, so rating it writes the file and reads it back.
    let path = testTempCapturePath()
    defer discard catch File.delete(path)
    let saved = Memory.new'Capture()
    saved.width, saved.widthOrg   = 8
    saved.height, saved.heightOrg = 6
    saved.backImg                 = Gui.Testing.indexedImage(8, 6)
    saved.file                    = path
    saved.rating                  = 3
    saved.changed                 = true
    expect saved.save()
    Memory.delete(saved)

    let first = testAddLibraryItem(lib.view, path, 10, 1)
    first.capture!.rating = 3
    discard testAddLibraryItem(lib.view, "second.scc", 10, 2)

    var none: Lens.Results
    lib.describeLensRest(&none)
    Swag.assert(none.sections.count == 1)
    let filter = unwrap none.sections[0]
    Swag.assert(filter.label == appStrings().ui_BarFilter and filter.inline)
    Swag.assert(filter.entries.count == ContentFilterIds.count)

    lib.view.selModel.select(0)
    lib.view.focusItem = 0
    var chosen: Lens.Results
    lib.describeLensRest(&chosen)
    Swag.assert(chosen.sections.count == 3)

    let texts   = appStrings()
    let actions = unwrap chosen.sections[0]
    Swag.assert(actions.label == texts.lens_Selection)
    let titles = [texts.act_OpenSelected, texts.act_ExportSelected, texts.act_EditTags, texts.act_FavoriteCapture, texts.act_MoveSelected, texts.act_Delete]
    Swag.assert(actions.entries.count == 6)
    for title, i in titles do
        Swag.assert(actions.entries[i].title == title)

    let rating = unwrap chosen.sections[1]
    Swag.assert(rating.label == texts.act_Rating and rating.inline and rating.entries.count == 6)
    for entry, i in rating.entries do
        Swag.assert(entry.checked == (i == 3))
    Swag.assert(chosen.sections[2]!.label == texts.ui_BarFilter)

    // Choosing a segment rates the chosen captures.
    let rate = unwrap rating.entries[5].run
    rate()
    Swag.assert(first.capture.rating == 5)
}

// A capture moved to a folder leaves the library for it, and comes back when moved to the library.
#test
{
    testUseScratchLibrary()
    let root = Gui.Testing.tempFilePath("capture-library-move-", "")
    expect Directory.create(root)
    let elsewhere = Gui.Testing.tempFilePath("capture-library-elsewhere-", "")
    expect Directory.create(elsewhere)
    defer
    {
        discard catch Directory.delete(Path.combine(root, ".trash"))
        discard catch Directory.delete(root)
        discard catch Directory.delete(elsewhere)
        discard catch g_Library.setFolder("")
    }

    let path    = Path.combine(root, "moved.scc")
    let capture = Memory.new'Capture()
    capture.width, capture.widthOrg   = 8
    capture.height, capture.heightOrg = 6
    capture.backImg                   = Gui.Testing.indexedImage(8, 6)
    capture.file                      = path
    capture.changed                   = true
    expect capture.save()
    Memory.delete(capture)

    expect g_Library.setFolder(root)
    g_Library.fill()
    Swag.assert(g_Library.files.count == 1)

    let away = g_Library.moveTo(path, elsewhere)
    Swag.assert(not away.isEmpty() and File.exists(away) and not File.exists(path))
    Swag.assert(g_Library.files.isEmpty())

    let back = g_Library.moveTo(away, Library.getFolder())
    Swag.assert(not back.isEmpty() and File.exists(back) and not File.exists(away))
    Swag.assert(g_Library.files.count == 1)
    discard catch File.delete(back)
}

// The library page teaches its keys on its hint line, Space last: Enter opens the chosen capture,
// Delete deletes it, F2 renames it, 0 to 5 rate it and / reaches the field filtering the grid.
#test
{
    var f: HeadlessFixture
    f.setup(width: 1100, height: 700)
    defer f.shutdown()

    g_Library.loaded = true
    g_Library.files.clear()
    f.main.libWnd = LibraryWnd.create(f.main)
    let lib = f.main.libWnd
    lib.setPosition({0, 0, 1100, 700})
    lib.applyLayout()

    let texts = appStrings()
    let hints = &lib.hintLine.hints
    Swag.assert(hints.count == 6)
    Swag.assert(hints[0].key == strings().key_Enter and hints[0].text == texts.hint_Open)
    Swag.assert(hints[1].key == "Del" and hints[2].key == "F2" and hints[2].text == texts.hint_Rename)
    Swag.assert(hints[3].key == texts.key_Ratings and hints[4].key == "/" and hints[4].text == texts.hint_Filter)
    Swag.assert(hints[5].key == strings().key_Space)

    Swag.assert(lib.keyShortcut(.None, .Return) == ActionLibSel.Open)
    Swag.assert(lib.keyShortcut(.None, .Delete) == ActionLibSel.Delete)
    Swag.assert(lib.keyShortcut(.None, .D3) == ActionLibSel.Rate3)
    Swag.assert(lib.keyShortcut(.None, .Oem2) == ActionLibSel.Search)

    // / reaches the filter field, where the next keys are typed.
    discard testAddLibraryItem(lib.view, "first.scc", 10, 1)
    lib.view.setFocus()
    f.gui.keyPress(.Oem2)
    Swag.assert(lib.searchEdit.hasFocus())
}
