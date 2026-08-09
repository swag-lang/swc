#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, File

// Library actions can be exercised against an empty headless library window:
// sorting/filtering and command states do not require scanning the user's files.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    discard f.setupLibraryWnd()
    let libWnd = cast(*Wnd) f.main.libWnd!

    var sizeEvt = Gui.Testing.commandState(ActionRecentSize.LibBig)
    @assert(Gui.Testing.actionUpdate'ActionRecentSize(f.main, ActionRecentSize.LibBig, &sizeEvt))
    @assert(!sizeEvt.checked)
    f.main.sendCommandEvent(ActionRecentSize.LibBig)
    @assert(f.main.libWnd.previewSize == .Big)
    @assert(Gui.Testing.actionExecute'ActionRecentSize(f.main, ActionRecentSize.LibMedium))
    @assert(f.main.libWnd.previewSize == .Medium)
    @assert(Gui.Testing.actionExecute'ActionRecentSize(f.main, ActionRecentSize.LibSmall))
    @assert(f.main.libWnd.previewSize == .Small)

    with f.main.recentBar = Wnd.create'Wnd(f.main, {0, 0, 0, 128})
    {
        .dockStyle = .Bottom
    }

    @assert(Gui.Testing.actionExecute'ActionRecentSize(f.main, ActionRecentSize.RecentSmall))
    @assert(f.main.bottomSize == .Small)
    @assert(Gui.Testing.actionExecute'ActionRecentSize(f.main, ActionRecentSize.RecentMedium))
    @assert(f.main.bottomSize == .Medium)
    @assert(Gui.Testing.actionExecute'ActionRecentSize(f.main, ActionRecentSize.RecentBig))
    @assert(f.main.bottomSize == .Big)

    var evt = Gui.Testing.commandState(ActionLibSort.Recent)
    @assert(Gui.Testing.actionUpdate'ActionLibSort(libWnd, ActionLibSort.Recent, &evt))
    @assert(evt.checked)

    libWnd.sendCommandEvent(ActionLibSort.FileSize)
    @assert(f.main.libWnd.sortMethod == .FileSize)

    evt = Gui.Testing.commandState(ActionLibSort.Invert)
    @assert(Gui.Testing.actionUpdate'ActionLibSort(libWnd, ActionLibSort.Invert, &evt))
    @assert(!evt.name.isEmpty())
    @assert(!evt.disabled)

    libWnd.sendCommandEvent(ActionLibSort.Invert)
    @assert(f.main.libWnd.invertSort)

    libWnd.sendCommandEvent(ActionLibSort.Similar)
    evt = Gui.Testing.commandState(ActionLibSort.Invert)
    @assert(Gui.Testing.actionUpdate'ActionLibSort(libWnd, ActionLibSort.Invert, &evt))
    @assert(evt.disabled)

    evt = Gui.Testing.commandState(ActionLibFilter.LinkedImage)
    @assert(Gui.Testing.actionUpdate'ActionLibFilter(libWnd, ActionLibFilter.LinkedImage, &evt))
    @assert(evt.checked)
    libWnd.sendCommandEvent(ActionLibFilter.LinkedImage)
    @assert(!f.main.libWnd.showLinkedImage)

    f.main.libWnd.contentFilter     = .Images
    f.main.libWnd.favoritesOnly     = true
    f.main.libWnd.minimumRating     = 4
    f.main.libWnd.applicationFilter = "chrome"
    f.main.libWnd.tagFilter         = "docs"
    libWnd.sendCommandEvent(ActionLibFilter.Reset)
    @assert(f.main.libWnd.contentFilter == .All)
    @assert(!f.main.libWnd.favoritesOnly)
    @assert(f.main.libWnd.minimumRating == 0)
    @assert(f.main.libWnd.applicationFilter.isEmpty())
    @assert(f.main.libWnd.tagFilter.isEmpty())
    @assert(f.main.libWnd.showLinkedImage)

    evt = Gui.Testing.commandState(ActionLibSel.Right)
    @assert(Gui.Testing.actionUpdate'ActionLibSel(libWnd, ActionLibSel.Right, &evt))
    @assert(evt.disabled)

    f.main.libWnd.view.focusItem = 0
    evt = Gui.Testing.commandState(ActionLibSel.Right)
    @assert(Gui.Testing.actionUpdate'ActionLibSel(libWnd, ActionLibSel.Right, &evt))
    @assert(!evt.disabled)
}

// Library view filtering, sorting and keyboard-style movement operate entirely
// on in-memory items; no filesystem scan or preview loading is required.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let lib  = f.setupLibraryWnd()
    let view = lib.view!
    let wnd  = cast(*Wnd) lib

    let old   = testAddLibraryItem(view, "old.scapture", 10, 1)
    let big   = testAddLibraryItem(view, "big-linked.scapture", 30, 3, "big.png")
    let dirty = testAddLibraryItem(view, "dirty-linked.scapture", 20, 2, "dirty.png", linkedUpToDate: false)

    view.filterDay = 2
    view.filter()
    @assert(view.items.count == 1)
    @assert(view.items[0] == dirty)
    view.filterDay = 0
    view.filter()

    lib.sortMethod = .FileSize
    lib.invertSort = false
    view.sort()
    @assert(view.items[0] == big)
    @assert(view.items[1] == dirty)
    @assert(view.items[2] == old)

    lib.invertSort = true
    view.sort()
    @assert(view.items[0] == old)
    @assert(view.items[1] == dirty)
    @assert(view.items[2] == big)

    lib.sortMethod = .Recent
    lib.invertSort = false
    view.sort()
    @assert(view.items[0] == big)
    @assert(view.items[1] == dirty)
    @assert(view.items[2] == old)

    lib.showUnSavedLinkedImage = false
    view.filter()
    @assert(view.items.count == 2)
    @assert(view.items.contains(old))
    @assert(view.items.contains(big))
    @assert(!view.items.contains(dirty))

    lib.showUnSavedLinkedImage = true
    lib.showLinkedImage        = false
    view.filter()
    @assert(view.items.count == 1)
    @assert(view.items[0] == old)

    lib.showLinkedImage = true
    view.filter()
    view.sort()

    wnd.sendCommandEvent(ActionLibFilter.UpToDateLinkedImage)
    @assert(!lib.showUpToDateLinkedImage)
    @assert(view.items.count == 2)
    @assert(view.items.contains(old))
    @assert(!view.items.contains(big))
    @assert(view.items.contains(dirty))

    wnd.sendCommandEvent(ActionLibFilter.UpToDateLinkedImage)
    wnd.sendCommandEvent(ActionLibFilter.UnSavedLinkedImage)
    @assert(!lib.showUnSavedLinkedImage)
    @assert(view.items.count == 2)
    @assert(view.items.contains(old))
    @assert(view.items.contains(big))
    @assert(!view.items.contains(dirty))

    wnd.sendCommandEvent(ActionLibFilter.UnSavedLinkedImage)
    wnd.sendCommandEvent(ActionLibFilter.UnLinkedImage)
    @assert(!lib.showUnLinkedImage)
    @assert(view.items.count == 2)
    @assert(!view.items.contains(old))
    @assert(view.items.contains(big))
    @assert(view.items.contains(dirty))

    wnd.sendCommandEvent(ActionLibFilter.UnLinkedImage)
    view.filter()
    view.sort()
    view.focusItem = 1
    wnd.sendCommandEvent(ActionLibSel.Home)
    @assert(view.focusItem == 0)
    @assert(view.selModel.isSelected(0))

    wnd.sendCommandEvent(ActionLibSel.Right)
    @assert(view.focusItem == 1)
    @assert(view.selModel.isSelected(1))
    @assert(!view.selModel.isSelected(0))

    wnd.sendCommandEvent(ActionLibSel.End)
    @assert(view.focusItem == 2)
    @assert(view.selModel.isSelected(2))

    wnd.sendCommandEvent(ActionLibSel.Left)
    @assert(view.focusItem == 1)

    lib.previewSize = .Medium
    view.setPosition({0, 0, 360, 420})
    view.focusItem = 0
    wnd.sendCommandEvent(ActionLibSel.Down)
    @assert(view.focusItem == 1)
    @assert(view.selModel.isSelected(1))

    wnd.sendCommandEvent(ActionLibSel.Up)
    @assert(view.focusItem == 0)
    @assert(view.selModel.isSelected(0))
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
    let view = lib.view!

    // Mirror the handler LibraryWnd.fill() installs: drop the matching view item.
    g_Library.onDeleteFile += func|libWnd = lib|(file)
    {
        for it, [i] in libWnd.view.items
        {
            if it.fi.fullname == file
            {
                libWnd.view.selModel.unselect(cast() i)
                libWnd.view.items.removeAtOrdered(i)
                break
            }
        }
    }

    // Three real capture files, registered in the library and the view.
    var paths: Array'String
    for [idx] in 3
    {
        let capture = Memory.new'Capture()
        capture.width, capture.widthOrg   = 8
        capture.height, capture.heightOrg = 6
        capture.backImg                   = Gui.Testing.indexedImage(8, 6)
        let path = testTempCapturePath()
        capture.file    = path
        capture.changed = true
        expect capture.save()
        @assert(File.exists(path))
        Memory.delete(capture)

        g_Library.addFile(path)
        discard testAddLibraryItem(view, path, size: 8, day: cast(u16) (idx + 1))
        paths.add(path)
    }

    defer
    {
        for p in paths
        {
            discard catch File.delete(p)
            discard catch File.delete(Path.combine(Library.getTrashFolder(), Path.fileName(p)))
        }

        g_Library.files.clear()
        g_Library.onDeleteFile.clear()
    }

    @assert(view.items.count == 3)
    @assert(g_Library.files.count == 3)

    for [idx] in view.items.count do
        view.selModel.select(cast() idx)

    lib.removeSelected()

    // Every selection is gone from the view, the library, and its original location,
    // but soft-delete keeps a recoverable copy in the recycle bin.
    @assert(view.items.count == 0)
    @assert(g_Library.files.count == 0)
    for p in paths
    {
        @assert(!File.exists(p))
        @assert(File.exists(Path.combine(Library.getTrashFolder(), Path.fileName(p))))
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
    let view = lib.view!

    discard testAddLibraryItem(view, "alpha.scapture", 10, 1, title: "Login screen")
    discard testAddLibraryItem(view, "beta.scapture", 10, 2, "report.png", title: "Sales chart")
    discard testAddLibraryItem(view, "gamma.scapture", 10, 3, title: "Login error")

    lib.setSearch("login")
    @assert(view.items.count == 2)

    lib.setSearch("REPORT")
    @assert(view.items.count == 1)
    @assert(view.items[0]!.fi.fullname == "beta.scapture")

    lib.setSearch("gamma")
    @assert(view.items.count == 1)
    @assert(view.items[0]!.fi.fullname == "gamma.scapture")

    lib.setSearch("nomatch")
    @assert(view.items.count == 0)

    lib.setSearch("")
    @assert(view.items.count == 3)
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
    let libWnd = f.main.libWnd!

    let oldLibraryLoaded = g_Library.loaded
    defer
    {
        g_Library.files.clear()
        g_Library.loaded = oldLibraryLoaded
    }

    g_Library.loaded = true
    g_Library.files.clear()

    var fi: File.FileInfo
    fi.fullname            = "libfill_a.scapture"
    fi.lastWriteTime.year  = 2024
    fi.lastWriteTime.month = 5
    fi.lastWriteTime.day   = 11
    g_Library.files.add(fi)
    fi.fullname          = "libfill_b.scapture"
    fi.lastWriteTime.day = 10
    g_Library.files.add(fi)
    fi.fullname            = "libfill_c.scapture"
    fi.lastWriteTime.year  = 2023
    fi.lastWriteTime.month = 1
    fi.lastWriteTime.day   = 2
    g_Library.files.add(fi)

    @assert(libWnd.listCtrl.lineCount() == 0)
    libWnd.fill()

    // Root lines only: "All Items" + the 2024 and 2023 year groups (months and
    // days are children of their year/month lines).
    @assert(libWnd.listCtrl.lineCount() == 3)
    @assert(libWnd.view.items.count == 3)

    // A second fill with lines already present must keep the sidebar as is.
    libWnd.fill()
    @assert(libWnd.listCtrl.lineCount() == 3)

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

    let chrome = testAddLibraryItem(view, "chrome.scapture", 30, 2, title: "Documentation")
    chrome.capture!.sourceKind        = .Screen
    chrome.capture!.sourceApplication = "chrome"
    chrome.capture!.sourceWindowTitle = "Swag language reference"
    chrome.capture!.tags.add("docs")
    chrome.capture!.favorite = true
    chrome.capture!.rating   = 5
    chrome.width             = 1920
    chrome.height            = 1080

    let slack = testAddLibraryItem(view, "slack.scapture", 20, 3, title: "Team")
    slack.capture!.sourceKind        = .Screen
    slack.capture!.sourceApplication = "slack"
    slack.capture!.sourceWindowTitle = "Engineering"
    slack.capture!.tags.add("work")
    slack.capture!.rating = 2
    slack.width           = 800
    slack.height          = 600

    let imported = testAddLibraryItem(view, "imported.scapture", 10, 1, "photo.png", title: "Photo")
    imported.capture!.sourceKind = .ImageFile
    imported.width               = 400
    imported.height              = 300

    let image = view.allItems.addNew()
    image.fi.fullname = "wallpaper.png"
    image.kind        = .Image
    image.loaded      = true
    image.width       = 2560
    image.height      = 1440
    view.items.add(image)

    lib.contentFilter = .ScreenCaptures
    view.filter()
    @assert(view.items.count == 2)
    @assert(view.items.contains(chrome))
    @assert(view.items.contains(slack))

    lib.contentFilter = .Images
    view.filter()
    @assert(view.items.count == 1)
    @assert(view.items[0] == image)

    lib.contentFilter     = .All
    lib.applicationFilter = "CHROME"
    view.filter()
    @assert(view.items.count == 1)
    @assert(view.items[0] == chrome)

    lib.applicationFilter.clear()
    lib.tagFilter = "DOCS"
    view.filter()
    @assert(view.items.count == 1)
    @assert(view.items[0] == chrome)

    lib.tagFilter.clear()
    lib.favoritesOnly = true
    view.filter()
    @assert(view.items.count == 1)
    @assert(view.items[0] == chrome)

    lib.favoritesOnly = false
    lib.minimumRating = 3
    view.filter()
    @assert(view.items.count == 1)
    @assert(view.items[0] == chrome)

    lib.minimumRating = 0
    lib.setSearch("language reference")
    @assert(view.items.count == 1)
    @assert(view.items[0] == chrome)
    lib.setSearch("")

    lib.sortMethod = .Application
    view.sort()
    @assert(view.items.back() == slack)

    lib.sortMethod = .Dimensions
    view.sort()
    @assert(view.items[0] == image)

    lib.sortMethod = .Name
    view.sort()
    @assert(view.items[0] == chrome)

    for item, [i] in view.items where item == slack do
        view.setFocusItem(cast(u32) i)
    lib.sortMethod = .Dimensions
    view.sort()
    @assert(view.focusItem < view.items.count)
    @assert(view.items[view.focusItem] == slack)
    @assert(view.selModel.isSelected(view.focusItem))
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

    let path = Gui.Testing.tempFilePath("scapture-library-image-", ".png")
    defer discard catch File.delete(path)
    var source = Gui.Testing.indexedImage(48, 32)
    expect source.save(path)

    let item = view.allItems.addNew()
    item.fi.fullname = path
    item.kind        = .Image
    view.items.add(item)
    view.loadOne(item)

    @assert(item.loaded)
    @assert(!item.capture)
    @assert(item.image.isValid())
    @assert(item.width == 48)
    @assert(item.height == 32)
    @assert(item.haar.size != 0)

    f.main.libraryMode = true
    view.focusItem     = 0
    var deleteState = Gui.Testing.commandState(ActionFile.DeleteCapture)
    @assert(Gui.Testing.actionUpdate'ActionFile(f.main, ActionFile.DeleteCapture, &deleteState))
    @assert(deleteState.disabled)
}

// The root is configurable, indexes captures and ordinary images together, and remains
// the destination used for newly created capture files.
#test
{
    testUseScratchLibrary()
    let root = Gui.Testing.tempFilePath("scapture-library-root-", "")
    expect Directory.create(root)

    let capturePath = Path.combine(root, "sample.scapture")
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
    Memory.delete(capture)

    var image = Gui.Testing.indexedImage(10, 7)
    expect image.save(imagePath)

    let previousRoot = Library.getFolder()
    discard catch g_Library.setFolder(capturePath) as invalidRootError
    @assert(invalidRootError != null)
    @assert(Library.getFolder() == previousRoot)

    expect g_Library.setFolder(root)
    g_Library.fill()
    @assert(Library.getFolder() == root)
    @assert(g_Library.files.count == 2)
    let generatedFile      = Library.newFileName()
    let generatedDirectory = Path.directoryName(generatedFile)
    @assert(generatedDirectory != null)
    @assert(Path.equals(generatedDirectory!, root))
}

// The library chrome keeps its two fixed edges under every mode transition: the date/filter
// rail returns after leaving the recycle bin, the search field stays against the right edge,
// and the fixed-width rail never creates horizontal scrolling.
#test
{
    var f: HeadlessFixture
    f.setup(width: 1100, height: 700)
    defer f.shutdown()

    g_Library.loaded = true
    g_Library.files.clear()
    f.main.libWnd = LibraryWnd.create(f.main)
    let lib = f.main.libWnd!
    lib.setPosition({0, 0, 1100, 700})
    lib.applyLayout()
    lib.layoutSidebarColumns()
    lib.listCtrl.computeLayout()
    lib.commandBar.computeLayout()

    @assert(@countof(lib.folderBtn.text()) != 0)
    @assert(lib.searchEdit.position.right() == lib.commandBar.paddedClientRect().right())
    @assert(lib.listCtrl.scrollWnd.scrollSize.x <= lib.listCtrl.listView.paddedClientRect().width)
    @assert(lib.commandBar.children.count == 7)
    @assert(lib.sortBtn.position.x - lib.previewSizeBtn.position.right() == LibButtonGap)
    @assert(lib.filterBtn.position.x - lib.sortBtn.position.right() == LibButtonGap)
    @assert(lib.folderBtn.position.x - lib.filterBtn.position.right() == LibButtonGap)

    @assert(lib.sideBar.isLocallyVisible())
    @assert(lib.view.scrollWnd.position.x == SideBarWidth)

    lib.setTrashMode(true)
    @assert(!lib.sideBar.isLocallyVisible())
    @assert(lib.view.scrollWnd.position.x == 0)

    lib.setTrashMode(false)
    @assert(lib.sideBar.isLocallyVisible())
    @assert(lib.view.scrollWnd.position.x == SideBarWidth)

    let chrome = testAddLibraryItem(lib.view, "chrome.scapture", 10, 1)
    chrome.capture!.sourceApplication = "Chrome"
    chrome.capture!.sourceExecutable  = Env.executablePath()
    chrome.capture!.tags.add("docs")
    let slack = testAddLibraryItem(lib.view, "slack.scapture", 10, 2)
    slack.capture!.sourceApplication = "Slack"
    slack.capture!.tags.add("work")
    lib.refreshAutomaticFilters()

    @assert(lib.sidebarApplications.count == 2)
    @assert(lib.sidebarApplications[0].name == "Chrome")
    @assert(lib.sidebarApplications[0].executable == Env.executablePath())
    @assert(lib.sidebarApplications[0].count == 1)
    @assert(lib.sidebarTags.count == 2)

    for [i] in lib.listCtrl.lineCount()
    {
        let line = lib.listCtrl.lineAt(cast(u32) i)!
        if cast(LibrarySidebarFilter) cast(u64) line.userData3 != .Application do
            continue
        let idx = cast(u64) line.userData0
        if idx < lib.sidebarApplications.count and lib.sidebarApplications[idx].name == "Chrome"
        {
            @assert(line.itemAt(0).icon.isValid())
            @assert(line.itemAt(0).icon.color == Argb.White)
            lib.listCtrl.selectLine(cast(u32) i)
        }
    }

    @assert(lib.applicationFilter == "Chrome")
    @assert(lib.view.items.count == 1)
    @assert(lib.view.items[0] == chrome)

    for [i] in lib.listCtrl.lineCount()
    {
        let line = lib.listCtrl.lineAt(cast(u32) i)!
        if cast(LibrarySidebarFilter) cast(u64) line.userData3 != .Tag do
            continue
        let idx = cast(u64) line.userData0
        if idx < lib.sidebarTags.count and lib.sidebarTags[idx].name == "work" do
            lib.listCtrl.selectLine(cast(u32) i)
    }

    @assert(lib.applicationFilter.isEmpty())
    @assert(lib.tagFilter == "work")
    @assert(lib.view.items.count == 1)
    @assert(lib.view.items[0] == slack)
}
