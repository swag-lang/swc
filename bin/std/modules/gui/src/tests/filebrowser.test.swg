#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, File

// The file browser composite builds its sub-controls and resolves selections
// independently of any dialog/surface.
//
// The selection checks do not enumerate a real folder: they exercise name and filter
// resolution independently of the files present on the test machine.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 460)
    var opt: FileDlgOptions
    opt.mode = .SelectFile
    opt.showLocationsPane = false
    opt.filters.add({name: "Text", extensions: ".txt;.md"})

    let fb = FileBrowserCtrl.create(&host.root, opt, {0, 0, 600, 400})
    Swag.assert((fb.editFile != null))
    Swag.assert((fb.comboType != null))
    Swag.assert((fb.listCtrl != null))
    Swag.assert((fb.pathField != null))
    Swag.assert((fb.upButton != null))
    Swag.assert((fb.historyButton != null))
    Swag.assert((fb.newFolderButton != null))
    Swag.assert(fb.placesBar == null)
    Swag.assert(fb.comboType.items.count == 1)
    Swag.assert(fb.options.shortcuts.count == 3)
    Swag.assert(not fb.canGoBack())
    Swag.assert(not fb.canGoForward())

    // The file list is multi-column: the date and the size keep their default widths, and the
    // names take the room they leave.
    Swag.assert(fb.listCtrl.header.items.count == 3)
    Swag.assert(fb.listCtrl.header.itemWidthAt(0) > 220)
    Swag.assert(Math.abs(fb.listCtrl.header.itemWidthAt(1) - 130) < 0.5)
    Swag.assert(Math.abs(fb.listCtrl.header.itemWidthAt(2) - 90) < 0.5)

    // selectedPath combines the folder + typed name and appends the active
    // filter extension when missing.
    fb.setFileName("notes")
    Swag.assert(fb.fileName() == "notes")
    let name     = fb.selectedPath()
    let fileName = unwrap Path.fileName(name.toString())
    Swag.assert(fileName == "notes.txt")

    // A name that already carries the extension is kept as-is.
    fb.setFileName("report.txt")
    let name2     = fb.selectedPath()
    let fileName2 = unwrap Path.fileName(name2.toString())
    Swag.assert(fileName2 == "report.txt")

    // Every extension offered by one filter is accepted as-is, not only its first one.
    fb.setFileName("readme.md")
    let name3     = fb.selectedPath()
    let fileName3 = unwrap Path.fileName(name3.toString())
    Swag.assert(fileName3 == "readme.md")
    Swag.assert(not fb.setCurrentFolder("this-folder-does-not-exist"))
    Swag.assert(not fb.createFolder("bad/name"))
}

// SelectFolder mode offers a single "Folders" type entry.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 460)
    var opt: FileDlgOptions
    opt.mode = .SelectFolder
    opt.showLocationsPane = false
    opt.shortcuts.add({type: Env.SpecialDirectory.Desktop, name: "Workspace"})

    let fb = FileBrowserCtrl.create(&host.root, opt, {0, 0, 600, 400})
    Swag.assert(fb.comboType.items.count == 1)
    Swag.assert(fb.options.shortcuts.count == 1)
    Swag.assert((fb.editFile != null))

    // selectedPath must not index the (empty) filter list in SelectFolder mode.
    fb.setFileName("myfolder")
    let name     = fb.selectedPath()
    let fileName = unwrap Path.fileName(name.toString())
    Swag.assert(fileName == "myfolder")
}

// File-browser history drops its forward branch after a new navigation.
#test
{
    var history: NavigationHistory
    history.push("C:/one")
    history.push("C:/two")
    history.push("C:/three")
    Swag.assert(history.canGoBack())
    Swag.assert(not history.canGoForward())
    Swag.assert(history.goBack() == "C:/two")
    Swag.assert(history.goBack() == "C:/one")
    Swag.assert(history.canGoForward())
    Swag.assert(history.goForward() == "C:/two")

    history.push("C:/other")
    Swag.assert(history.entries.count == 3)
    Swag.assert(history.entries[2] == "C:/other")
    Swag.assert(not history.canGoForward())
}

// The reusable dialog state receives the column widths on destruction, and the
// recent-folder history keeps unique existing folders, most recent first.
#test
{
    var state = FileDlgState{nameColumnWidth: 333, modifiedColumnWidth: 155, sizeColumnWidth: 77}

    var host: Testing.HeadlessHost
    host.setup(640, 460)
    with var opt: FileDlgOptions
    {
        .mode  = .SelectFile
        .showLocationsPane = false
        .state = &state
        .filters.add({name: "Text", extensions: ".txt"})
    }

    let fb = FileBrowserCtrl.create(&host.root, opt, {0, 0, 600, 400})
    Swag.assert(Math.abs(fb.listCtrl.header.itemWidthAt(1) - 155) < 0.5)
    Swag.assert(Math.abs(fb.listCtrl.header.itemWidthAt(2) - 77) < 0.5)

    // Recording the same existing folder twice keeps one entry at the front.
    let temp = Env.getSpecialDirectory(.Temp)
    fb.recordRecentFolder(temp.toString())
    fb.recordRecentFolder(temp.toString())
    Swag.assert(state.recentFolders.count == 1)

    // A folder that does not exist is never recorded.
    fb.recordRecentFolder("Z:/this-folder-does-not-exist")
    Swag.assert(state.recentFolders.count == 1)

    // The real history trigger must join its menu to the button, just like an options menu.
    host.root.applyLayout()
    host.pump()
    var checked: bool
    host.app.sigFrame += func|host = &host, fb, checked = &checked|(_)
    {
        if checked[] do
            return
        let popup  = unwrap host.capturedPopupMenu()
        let anchor = fb.historyButton.surfaceRect()
        Swag.assert(popup.popupAnchorButton == fb.historyButton)
        Swag.assert(popup.popupBarItemSurfaceRect == anchor)
        Swag.assert(popup.surfaceRect().y + popup.getPopupBodyRect().y == anchor.bottom())
        Swag.assert(popup.items.count == 1)
        checked[] = true
        popup.setEndModal(null)
    }

    fb.historyButton.sigPressed.call(fb.historyButton)
    Swag.assert(checked)

    // The name editor targets a folder only when its content names an existing one.
    fb.setFileName(temp.toString())
    Swag.assert(not fb.typedFolderTarget().isEmpty())
    fb.setFileName("no-such-subfolder-anywhere")
    Swag.assert(fb.typedFolderTarget().isEmpty())
}

// Dialogs create the composite before assigning its Center dock. The fields
// must acquire a useful width once the parent performs its first layout.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 460)
    var opt: FileDlgOptions
    opt.mode = .CreateFile
    opt.showLocationsPane = false
    opt.filters.add({name: "Encrypted container", extensions: ".scv"})

    let fb = FileBrowserCtrl.create(&host.root, opt)
    fb.dockStyle = .Center
    host.root.applyLayout()
    fb.applyLayout()

    Swag.assert(fb.editFile.position.width > 300)

    // Under the list, the name of a save, then the type filter as wide as its longest name.
    let form    = unwrap fb.editFile.parent
    let typeRow = unwrap fb.comboType.parent
    Swag.assert(form.position.y >= fb.listCtrl.position.bottom())
    Swag.assert(typeRow.position.y >= form.position.bottom())
    Swag.assert(typeRow.position.bottom() <= fb.position.height)
    Swag.assert(fb.comboType.position.width > 0 and fb.comboType.position.width < 300)
}

// The path field filters the rows by the words typed after the path, browses to a typed path on
// Enter, and climbs to the parent on Backspace when nothing is typed.
#test
{
    let root = Path.combine(Env.getSpecialDirectory(.Temp).toString(), "swag-filebrowser-field")
    discard catch Directory.delete(root.toString(), recurse: true)
    let sub = Path.combine(root.toString(), "sub")
    expect Directory.create(sub.toString(), recurse: true)
    defer discard catch Directory.delete(root.toString(), recurse: true)
    discard expect File.writeAllText(Path.combine(root.toString(), "notes.md").toString(), "notes")
    discard expect File.writeAllText(Path.combine(root.toString(), "plan.txt").toString(), "plan")

    var host: Testing.HeadlessHost
    host.setup(640, 460)
    let fb = FileBrowserCtrl.create(&host.root, {mode: .SelectFile, showLocationsPane: false, initialFolder: root.toString()}, {0, 0, 600, 400})
    Swag.assert(fb.listCtrl.lines.count == 3)

    fb.pathField.setText("md")
    Swag.assert(fb.listCtrl.lines.count == 1)

    fb.pathField.setText("sub/")
    Swag.assert(fb.listCtrl.lines.count == 3)
    fb.pathField.sigSubmitted.call(fb.pathField)
    Swag.assert((Path.fileName(fb.currentFolder.toString()) orelse "") == "sub")
    Swag.assert(fb.pathField.text().count == 0)

    fb.pathField.setFocus()
    host.keyPress(.Back)
    Swag.assert(fb.listCtrl.lines.count == 3)
}

// Opening a file from another folder works through the modal box's path field, not only in an
// embedded browser. Enter changes the folder; choosing a row then returns that file's full path.
#test
{
    let root = Path.combine(Env.getSpecialDirectory(.Temp).toString(), "swag-filedlg-navigation")
    discard catch Directory.delete(root.toString(), recurse: true)
    let folder = Path.combine(root.toString(), "sub")
    expect Directory.create(folder.toString(), recurse: true)
    defer discard catch Directory.delete(root.toString(), recurse: true)
    discard expect File.writeAllText(Path.combine(folder.toString(), "notes.txt").toString(), "notes")

    var host: Testing.HeadlessHost
    host.setup(640, 460)
    let dlg = FileDlg.create(&host.surface, {mode: .SelectFile, showLocationsPane: false, initialFolder: root.toString()})

    var browsed: bool
    host.app.sigFrame += func|host = &host, dlg, folder = &folder, browsed = &browsed|(_)
    {
        if browsed[] do
            return

        dlg.browser.pathField.setText("sub/")
        dlg.browser.pathField.sigSubmitted.call(dlg.browser.pathField)
        Swag.assert(dlg.browser.currentFolder == folder[])
        Swag.assert(dlg.browser.listCtrl.lines.count == 1)
        dlg.browser.listCtrl.selectLine(0)
        let clicked = host.clickModalButton(Dialog.BtnOk)
        Swag.assert(clicked)
        browsed[] = true
    }

    Swag.assert(dlg.doModal() == Dialog.BtnOk)
    Swag.assert(browsed and dlg.selectedPath() == Path.combine(folder.toString(), "notes.txt"))
    host.pump()
}

// The places at the top of the modal file box are real navigation controls: clicking Documents
// leaves Desktop and updates the folder the dialog will open from.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 460)
    let dlg = FileDlg.create(&host.surface, {mode: .SelectFile, showDrives: false})
    var navigated: bool

    host.app.sigFrame += func|host = &host, dlg, navigated = &navigated|(_)
    {
        if navigated[] do
            return

        let places = unwrap dlg.browser.placesBar
        Swag.assert(places.stops.count >= 2)
        Swag.assert(places.currentIndex() == 0)
        let documentPlace = &places.stops[1]
        var point = places.surfaceRect().topLeft()
        point.x += documentPlace.rect.x + documentPlace.rect.width * 0.5
        point.y += documentPlace.rect.vertCenter()
        Swag.assert(not dlg.surface!.wnd.hitTestCaption(point))
        dlg.surface.surfaceToScreen(&point)
        host.click(point)

        var expected = Env.getSpecialDirectory(.UserDocuments)
        Path.normalize(&expected)
        if expected.back() == '/' and expected.length > Path.rootLength(expected.toString()) do
            expected.removeBack()
        Swag.assert(dlg.browser.currentFolder == expected and places.currentIndex() == 1)
        let clicked = host.clickModalButton(Dialog.BtnCancel)
        Swag.assert(clicked)
        navigated[] = true
    }

    Swag.assert(dlg.doModal() == Dialog.BtnCancel)
    Swag.assert(navigated)
    host.pump()
}

// The title of the modal file box is a native caption hit target, so the operating system can drag
// the floating sheet from it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 700)
    let dlg = FileDlg.create(&host.surface, {mode: .SelectFile, showLocationsPane: false})
    var checked: bool

    host.app.sigFrame += func|host = &host, dlg, checked = &checked|(_)
    {
        if checked[] do
            return

        let surface = unwrap dlg.surface
        var start = surface.wnd.view.surfaceRect().topLeft()
        start.x += dlg.themeMetrics().dialog_Padding + 100
        start.y += dlg.themeMetrics().dialog_Padding + 5
        Swag.assert(surface.wnd.hitTestCaption(start))
        let clicked = host.clickModalButton(Dialog.BtnCancel)
        Swag.assert(clicked)
        checked[] = true
    }

    Swag.assert(dlg.doModal() == Dialog.BtnCancel)
    Swag.assert(checked)
    host.pump()
}

// The line beside the type filter says what the box will answer with: the folder a folder box
// picks, the count and weight of what a multiple box opens, whose rows check as they are chosen.
#test
{
    let root = Path.combine(Env.getSpecialDirectory(.Temp).toString(), "swag-filebrowser-choice")
    discard catch Directory.delete(root.toString(), recurse: true)
    expect Directory.create(Path.combine(root.toString(), "design").toString(), recurse: true)
    defer discard catch Directory.delete(root.toString(), recurse: true)
    discard expect File.writeAllText(Path.combine(root.toString(), "a.md").toString(), "aaaa")
    discard expect File.writeAllText(Path.combine(root.toString(), "b.md").toString(), "bb")

    var host: Testing.HeadlessHost
    host.setup(640, 460)

    let folders = FileBrowserCtrl.create(&host.root, {mode: .SelectFolder, showLocationsPane: false, initialFolder: root.toString()}, {0, 0, 600, 400})
    Swag.assert(not folders.comboType.isLocallyVisible())
    Swag.assert(folders.selectedPath() == folders.currentFolder)
    folders.listCtrl.selectLine(0)
    Swag.assert(Utf8.endsWith(folders.choiceLabel.text(), " / design"))

    let files = FileBrowserCtrl.create(&host.root, {mode: .SelectFiles, showLocationsPane: false, initialFolder: root.toString()}, {0, 0, 600, 400})
    Swag.assert(files.choiceLabel.text().count == 0)
    files.listCtrl.selectLine(1)
    files.listCtrl.selectLine(2)
    Swag.assert(files.listCtrl.isLineChecked(1) and files.listCtrl.isLineChecked(2))
    Swag.assert(Utf8.startsWith(files.choiceLabel.text(), "2 "))

    // A checkbox unchecked lets its row go.
    files.listCtrl.setLineChecked(1, false)
    Swag.assert(files.selectedPaths().count == 1)
}
