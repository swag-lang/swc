#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, File

// Library actions can be exercised against an empty headless library window:
// sorting/filtering and command states do not require scanning the user's files.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)

    discard f.setupLibraryWnd()
    let libWnd = cast(*Wnd) notnull f.main.libWnd

    var sizeEvt = Testing.commandState(ActionRecentSize.LibBig)
    @assert(Testing.actionUpdate'ActionRecentSize(f.main, ActionRecentSize.LibBig, &sizeEvt))
    @assert(!sizeEvt.checked)
    f.main.sendCommandEvent(ActionRecentSize.LibBig)
    @assert(f.main.libWnd.previewSize == .Big)
    @assert(Testing.actionExecute'ActionRecentSize(f.main, ActionRecentSize.LibMedium))
    @assert(f.main.libWnd.previewSize == .Medium)
    @assert(Testing.actionExecute'ActionRecentSize(f.main, ActionRecentSize.LibSmall))
    @assert(f.main.libWnd.previewSize == .Small)

    with f.main.recentBar = Wnd.create'Wnd(f.main, {0, 0, 0, 128})
    {
        .dockStyle = .Bottom
    }

    @assert(Testing.actionExecute'ActionRecentSize(f.main, ActionRecentSize.RecentSmall))
    @assert(f.main.bottomSize == .Small)
    @assert(Testing.actionExecute'ActionRecentSize(f.main, ActionRecentSize.RecentMedium))
    @assert(f.main.bottomSize == .Medium)
    @assert(Testing.actionExecute'ActionRecentSize(f.main, ActionRecentSize.RecentBig))
    @assert(f.main.bottomSize == .Big)

    var evt = Testing.commandState(ActionLibSort.Recent)
    @assert(Testing.actionUpdate'ActionLibSort(libWnd, ActionLibSort.Recent, &evt))
    @assert(evt.checked)

    libWnd.sendCommandEvent(ActionLibSort.FileSize)
    @assert(f.main.libWnd.sortMethod == .FileSize)

    evt = Testing.commandState(ActionLibSort.Invert)
    @assert(Testing.actionUpdate'ActionLibSort(libWnd, ActionLibSort.Invert, &evt))
    @assert(!evt.name.isEmpty())
    @assert(!evt.disabled)

    libWnd.sendCommandEvent(ActionLibSort.Invert)
    @assert(f.main.libWnd.invertSort)

    libWnd.sendCommandEvent(ActionLibSort.Similar)
    evt = Testing.commandState(ActionLibSort.Invert)
    @assert(Testing.actionUpdate'ActionLibSort(libWnd, ActionLibSort.Invert, &evt))
    @assert(evt.disabled)

    evt = Testing.commandState(ActionLibFilter.LinkedImage)
    @assert(Testing.actionUpdate'ActionLibFilter(libWnd, ActionLibFilter.LinkedImage, &evt))
    @assert(evt.checked)
    libWnd.sendCommandEvent(ActionLibFilter.LinkedImage)
    @assert(!f.main.libWnd.showLinkedImage)

    evt = Testing.commandState(ActionLibSel.Right)
    @assert(Testing.actionUpdate'ActionLibSel(libWnd, ActionLibSel.Right, &evt))
    @assert(evt.disabled)

    f.main.libWnd.view.focusItem = 0
    evt = Testing.commandState(ActionLibSel.Right)
    @assert(Testing.actionUpdate'ActionLibSel(libWnd, ActionLibSel.Right, &evt))
    @assert(!evt.disabled)

    f.shutdown()
}

// Library view filtering, sorting and keyboard-style movement operate entirely
// on in-memory items; no filesystem scan or preview loading is required.
#test
{
    var f: HeadlessFixture
    f.setup()
    let lib = f.setupLibraryWnd()
    let view = notnull lib.view
    let wnd = cast(*Wnd) lib

    let old = testAddLibraryItem(view, "old.captme", 10, 1)
    let big = testAddLibraryItem(view, "big-linked.captme", 30, 3, "big.png")
    let dirty = testAddLibraryItem(view, "dirty-linked.captme", 20, 2, "dirty.png", linkedUpToDate: false)

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
    lib.showLinkedImage = false
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

    f.shutdown()
}

// Deleting a multi-selection removes every selected capture, even though the
// onDeleteFile handler removes items from view.items as each file goes away
// (regression: iterating the list while it was mutated used to skip entries).
#test
{
    var f: HeadlessFixture
    f.setup()

    catch Library.init()
    @assert(@err == null)
    g_Library.files.clear()
    g_Library.loaded = true
    g_Library.onDeleteFile.arr.clear()

    let lib  = f.setupLibraryWnd()
    let view = notnull lib.view

    // Mirror the handler LibraryWnd.fill() installs: drop the matching view item.
    g_Library.onDeleteFile += func|libWnd = lib|(file)
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

    // Three real capture files, registered in the library and the view.
    var paths: Array'String
    for idx in 3
    {
        let capture = Memory.new'Capture()
        capture.width, capture.widthOrg = 8
        capture.height, capture.heightOrg = 6
        capture.backImg = Testing.indexedImage(8, 6)
        let path = testTempCapturePath()
        capture.file    = path
        capture.changed = true
        catch capture.save()
        @assert(@err == null)
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
            discard catch File.delete(Path.combine(Library.getTrashFolder(), Path.getFileName(p)))
        }
        g_Library.files.clear()
        g_Library.onDeleteFile.arr.clear()
    }

    @assert(view.items.count == 3)
    @assert(g_Library.files.count == 3)

    for idx in view.items.count do
        view.selModel.select(cast() idx, true)

    lib.removeSelected()

    // Every selection is gone from the view, the library, and its original location,
    // but soft-delete keeps a recoverable copy in the recycle bin.
    @assert(view.items.count == 0)
    @assert(g_Library.files.count == 0)
    for p in paths
    {
        @assert(!File.exists(p))
        @assert(File.exists(Path.combine(Library.getTrashFolder(), Path.getFileName(p))))
    }

    f.shutdown()
}

// The library search box matches captures by title, linked image path or file name,
// case-insensitively; unrelated captures are filtered out of the visible set. Clearing
// the search restores the full list.
#test
{
    var f: HeadlessFixture
    f.setup()
    let lib  = f.setupLibraryWnd()
    let view = notnull lib.view

    discard testAddLibraryItem(view, "alpha.captme", 10, 1, title: "Login screen")
    discard testAddLibraryItem(view, "beta.captme", 10, 2, "report.png", title: "Sales chart")
    discard testAddLibraryItem(view, "gamma.captme", 10, 3, title: "Login error")

    lib.setSearch("login")
    @assert(view.items.count == 2)

    lib.setSearch("REPORT")
    @assert(view.items.count == 1)
    @assert(view.items[0].fi.fullname == "beta.captme")

    lib.setSearch("gamma")
    @assert(view.items.count == 1)
    @assert(view.items[0].fi.fullname == "gamma.captme")

    lib.setSearch("nomatch")
    @assert(view.items.count == 0)

    lib.setSearch("")
    @assert(view.items.count == 3)

    f.shutdown()
}

// Filling the date sidebar from a fresh (empty) list must open the year/month/day
// group lines correctly: the group trackers start null and the FIRST file already
// flushes/opens groups, so an uninitialized tracker would be read before any
// assignment (this crashed in release when showing the library view).
#test
{
    var f: HeadlessFixture
    f.setup()

    f.main.libWnd = LibraryWnd.create(f.main)
    let libWnd = notnull f.main.libWnd

    let oldLibraryLoaded = g_Library.loaded
    defer
    {
        g_Library.files.clear()
        g_Library.loaded = oldLibraryLoaded
    }

    g_Library.loaded = true
    g_Library.files.clear()

    var fi: File.FileInfo
    fi.fullname               = "libfill_a.captme"
    fi.lastWriteTime.year     = 2024
    fi.lastWriteTime.month    = 5
    fi.lastWriteTime.day      = 11
    g_Library.files.add(fi)
    fi.fullname               = "libfill_b.captme"
    fi.lastWriteTime.day      = 10
    g_Library.files.add(fi)
    fi.fullname               = "libfill_c.captme"
    fi.lastWriteTime.year     = 2023
    fi.lastWriteTime.month    = 1
    fi.lastWriteTime.day      = 2
    g_Library.files.add(fi)

    @assert(libWnd.listCtrl.getLineCount() == 0)
    libWnd.fill()

    // Root lines only: "All Captures" + the 2024 and 2023 year groups (months and
    // days are children of their year/month lines).
    @assert(libWnd.listCtrl.getLineCount() == 3)
    @assert(libWnd.view.items.count == 3)

    // A second fill with lines already present must keep the sidebar as is.
    libWnd.fill()
    @assert(libWnd.listCtrl.getLineCount() == 3)

    libWnd.view.thread.safeForceEnd()
    libWnd.view.thread.wait()

    f.shutdown()
}
