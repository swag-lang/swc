#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Library actions can be exercised against an empty headless library window:
// sorting/filtering and command states do not require scanning the user's files.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)

    discard f.setupLibraryWnd()
    let libWnd = cast(*Wnd) f.main.libWnd

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
    @assert(evt.name == "Smaller First")
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
    var f: CaptmeHeadlessFixture
    f.setup()
    let lib = f.setupLibraryWnd()
    let view = lib.view
    let wnd = cast(*Wnd) lib

    let old = captmeTestAddLibraryItem(view, "old.captme", 10, 1)
    let big = captmeTestAddLibraryItem(view, "big-linked.captme", 30, 3, "big.png")
    let dirty = captmeTestAddLibraryItem(view, "dirty-linked.captme", 20, 2, "dirty.png", linkedUpToDate: false)

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
