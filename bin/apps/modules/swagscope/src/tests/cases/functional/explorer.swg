#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

func fixture(name: string)->String => Path.combine(testSourceRoot(#curlocation), "datas", name)

internal func completeExplorer(host: *Testing.HeadlessHost, explorer: *Explorer)
{
    for 16
    {
        if not explorer.load.started do
            return
        explorer.load.task.wait()
        host.pump()
    }

    Swag.require(false, "exploration did not settle")
}

// Filesystem and ZIP locations expose the same immediate-child model, including implicit folders.
#test
{
    var listing = expect ExplorerListing.load(unwrap Path.directoryName(fixture("comprehensive.txt")))
    Swag.require(not listing.isArchive and listing.entries.count > 10)
    var found = false
    for &entry in listing.entries where entry.name == "comprehensive.txt"
    {
        found = true
        Swag.require(not entry.directory and entry.size > 0 and not entry.modified.isEmpty())
    }

    Swag.require(found)

    var archive = expect ExplorerListing.load(fixture("viewer.archive.zip"))
    Swag.require(archive.isArchive)
    let roots = archive.children("")
    Swag.require(roots.count == 2)
    let documents = archive.children("docs/")
    Swag.require(documents.count == 1 and documents[0].name == "readme.txt")
    Swag.require(documents[0].path == "docs/readme.txt" and documents[0].archiveIndex != Swag.U64.Max)
    for &entry in roots where entry.directory
    {
        let children = archive.children(entry.path)
        for &child in children do
            Swag.require(Utf8.startsWith(child.path, entry.path))
    }

    archive.archive.entries.clear()
    archive.archive.entries.add({path: "docs", isDirectory: true})
    archive.archive.entries.add({path: "docs/one.txt"})
    archive.archive.entries.add({path: "docs2/two.txt"})
    let explicitFolders = archive.children("")
    Swag.require(explicitFolders.count == 2 and explicitFolders[0].path == "docs/")
    Swag.require(archive.children(explicitFolders[0].path).count == 1)
}

// Opening a file directly stays simple; explicit exploration survives viewing and closing a file.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 640)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.queueFile(fixture("comprehensive.txt"))
    completeQueuedViewerFile(&host, window)
    Swag.require(not window.explorerActive and window.explorer == null)
    window.exploreFolder()
    Swag.require(window.explorerActive and window.explorer != null)
    Swag.require(window.focusedWindow() == null)
    let explorer = window.explorer
    explorer.setMode(.Details)
    completeExplorer(&host, explorer)
    Swag.require(explorer.isLocallyVisible() and explorer.shown.count > 0)
    Swag.require(explorer.tools.position.y >= explorer.address.position.bottom())
    window.showSearch()
    window.searchBox.setText(".txt")
    Swag.require(explorer.filter.text() == ".txt" and explorer.shown.count > 0)
    explorer.forceRefresh()
    completeExplorer(&host, explorer)
    Swag.require(explorer.filter.text() == ".txt" and window.searchBox.text() == ".txt")
    var selected = Swag.U64.Max
    for &entry, index in explorer.entries where entry.name == "comprehensive.txt" do
        selected = index
    Swag.require(selected != Swag.U64.Max)
    explorer.selected = selected
    explorer.activate(selected)
    completeQueuedViewerFile(&host, window)
    Swag.require(not explorer.isLocallyVisible() and window.currentView != null)
    window.setFilePanelVisible(true)
    Swag.require(not window.isExploring() and window.folderList.lineCount() == window.folderFiles.count)
    window.closeFile()
    host.pump()
    Swag.require(explorer.isLocallyVisible() and explorer.selected == selected and explorer.mode == .Details)
    Swag.require(explorer.filter.text() == ".txt")
    Swag.require(window.searchBox.text() == ".txt")
    window.hideSearch()
    Swag.require(explorer.filter.text() == ".txt" and explorer.shown.count > 0)
    Swag.require(explorer.queryButton.name.raw == ".txt")
    Swag.require(not explorer.kindMenu.showsFocusRing())
    window.closeFile()
    Swag.require(not window.explorerActive and window.home.isLocallyVisible())
}

// A click on a packaged book or comic opens its reader rather than the archive explorer.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 640)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openExplorer(unwrap Path.directoryName(fixture("viewer.epub")))
    let explorer = unwrap window.explorer
    completeExplorer(&host, explorer)
    Swag.require(not window.viewerCaptionButton.isLocallyVisible())

    const Cases: [2] string = ["viewer.epub", "viewer.cbz"]
    for name in Cases
    {
        var selected = Swag.U64.Max
        for &entry, index in explorer.entries where entry.name == name do
            selected = index
        Swag.require(selected != Swag.U64.Max)
        explorer.activate(selected)
        completeQueuedViewerFile(&host, window)
        Swag.require(not window.isExploring() and not explorer.isLocallyVisible())
        Swag.require(window.choices[window.activeChoiceIndex].key == (name == "viewer.epub" ? "epub" : "comic"))
        window.closeFile()
        host.pump()
        Swag.require(window.isExploring() and not window.viewerCaptionButton.isLocallyVisible())
    }
}

// The information sheet follows the reader from a folder to its file and back, then to another
// explored location without changing its visibility.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 640)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openExplorer(unwrap Path.directoryName(fixture("comprehensive.txt")))
    let explorer = unwrap window.explorer
    completeExplorer(&host, explorer)
    window.toggleInformation()
    Swag.require(window.infoSheet.isLocallyVisible())

    var exploredInformation: String
    for &entry, index in explorer.entries where entry.name == "comprehensive.txt"
    {
        explorer.selected = index
        window.infoSheet.clear()
        explorer.describeSelection(window.infoSheet, includeAction: false, includeTechnical: false, includeFile: false)
        exploredInformation = window.infoSheet.text()
        explorer.activate(index)
        break
    }

    completeQueuedViewerFile(&host, window)
    Swag.require(window.infoSheet.isLocallyVisible())
    Swag.require(Utf8.contains(window.infoSheet.text(), "comprehensive.txt"))
    Swag.require(explorer.describesFile(window.currentFile))
    Swag.require(Utf8.startsWith(window.infoSheet.text(), exploredInformation))
    window.closeFile(forExplorer: true)
    host.pump()
    Swag.require(window.isExploring())
    Swag.require(window.infoSheet.isLocallyVisible())
    Swag.require(Utf8.contains(window.infoSheet.text(), "comprehensive.txt"))

    window.openExplorer(fixture("viewer.archive.zip"))
    Swag.require(window.infoSheet.isLocallyVisible())
    completeExplorer(&host, explorer)
    Swag.require(window.isExploring())
    Swag.require(window.infoSheet.isLocallyVisible())
    Swag.require(Utf8.contains(window.infoSheet.text(), "viewer.archive.zip"))
    window.closeFile()
    Swag.require(window.home.isLocallyVisible() and not window.infoSheet.isLocallyVisible())
}

// The caption chooser returns from an archive's folder page to its original book or comic reader.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 640)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    const Cases: [2] string = ["viewer.epub", "viewer.cbz"]
    for name in Cases
    {
        if name == "viewer.cbz"
        {
            host.theme.setLight()
            host.notify(.ThemeChanged)
        }
        let file = fixture(name)
        let native = name == "viewer.epub" ? "epub" : "comic"
        window.openFile(file)
        completeQueuedViewerFile(&host, window)
        Swag.require(window.choices[window.activeChoiceIndex].key == native)
        Swag.require(window.viewerCaptionButton.isLocallyVisible())
        Swag.require(window.viewerCaptionButton.iconColor == Color{})

        var archiveChoice = Swag.U32.Max
        for choice, index in window.choices where choice.key == "archive" do
            archiveChoice = cast(u32, index)
        Swag.require(archiveChoice != Swag.U32.Max)
        window.selectViewer(archiveChoice)
        let explorer = unwrap window.explorer
        completeExplorer(&host, explorer)
        Swag.require(window.isExploring() and explorer.listing.isArchive)
        Swag.require(window.viewerCaptionButton.isLocallyVisible())
        Swag.require(window.viewerCaptionButton.iconColor == window.themeColors().caution)
        window.lens.open(appStrings().lens_ViewAs)
        Swag.require(lensHasEntry(window, window.index.plugins[window.index.choices(file)[0].pluginIndex].displayName()))
        window.lens.close()

        let menu = window.createViewerChoicesMenu()
        let choices = window.index.choices(file)
        Swag.require(menu.items.count == choices.count + 1)
        Swag.require(menu.items[0]!.id == "scope.viewer.choice.0")
        Swag.require(menu.items[1]!.separator and menu.items[2]!.id == "scope.viewer.choice.1")
        Swag.require(menu.items[0]!.name.raw == Format.toString(appStrings().ui_DefaultViewerChoice,
                                                                window.index.plugins[choices[0].pluginIndex].displayName()))
        menu.destroyNow()

        host.clickPopupMenuItemWhenShown("scope.viewer.choice.0")
        window.viewerCaptionButton.sigPressed.call(cast(*Button, window.viewerCaptionButton))
        completeQueuedViewerFile(&host, window)
        Swag.require(not window.isExploring() and window.choices[window.activeChoiceIndex].key == native)
        Swag.require(window.viewerCaptionButton.iconColor == Color{})
        for preference in window.preferences do
            Swag.require(preference.kind != native)
        window.closeFile()
        host.pump()
    }
    window.openExplorer(fixture("viewer.archive.zip"))
    completeExplorer(&host, unwrap window.explorer)
    Swag.require(window.viewerCaptionButton.isLocallyVisible() and window.viewerCaptionButton.iconColor == Color{})
}

// A later location wins even when the preceding enumeration has not returned yet.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 640)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openExplorer(unwrap Path.directoryName(fixture("comprehensive.txt")))
    let explorer = unwrap window.explorer
    explorer.setMode(.Names)
    explorer.navigate(fixture("viewer.archive.zip"))
    completeExplorer(&host, explorer)
    Swag.require(explorer.listing.isArchive and explorer.listing.path == (expect Path.absolute(fixture("viewer.archive.zip"))))
    explorer.goBack()
    completeExplorer(&host, explorer)
    Swag.require(not explorer.listing.isArchive)
}

// An archive is a page: its folders and members as quiet rows with their dates, "Extract All…" on
// the title's line, and the chosen member in the sheet with Open and "Extract…".
internal func archivePage(host: *Testing.HeadlessHost, light: bool)->*ViewerWindow
{
    host.setup(1280, 800)
    host.surface.updateFlags(SurfaceFlags.StandardWindow | SurfaceFlags.NoShadow)
    if light do
        host.theme.setLight()
    else do
        host.theme.setDark()
    host.notify(.ThemeChanged)

    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openExplorer(fixture("viewer.archive.zip"))
    let explorer = unwrap window.explorer
    explorer.setMode(.Details)
    completeExplorer(host, explorer)
    explorer.address.breadcrumb.clear()
    explorer.address.breadcrumb.addItem("Home")
    explorer.address.breadcrumb.addItem("viewer.archive.zip")
    explorer.address.refreshPath()
    window.applyLayout()
    return window
}

// Folder traversal uses the visible buttons and restores their enabled state in both directions.
#test
{
    var host: Testing.HeadlessHost
    let window   = archivePage(&host, light: false)
    let explorer = unwrap window.explorer
    let back     = &window.backCaptionButton.button
    let forward  = &window.forwardCaptionButton.button
    let up       = &window.upCaptionButton.button
    window.updateCommandState()
    Swag.require(back.position.right() <= forward.position.x)
    Swag.require(forward.position.right() <= up.position.x)
    Swag.require(not window.lensLauncher.captionButton.isLocallyVisible())
    Swag.require(window.informationCaptionButton.isLocallyVisible())
    Swag.require(window.informationCaptionButton.position.x > window.clientRect().width / 2)
    Swag.require(not back.isEnabled() and not forward.isEnabled())
    explorer.navigate(explorer.listing.path, "docs/")
    completeExplorer(&host, explorer)
    window.updateCommandState()
    Swag.require(back.isEnabled() and not forward.isEnabled())
    back.sigPressed.call(back)
    completeExplorer(&host, explorer)
    window.updateCommandState()
    Swag.require(explorer.folder.isEmpty(), "the caption Back button navigates to the prior folder")
    Swag.require(not back.isEnabled(), "Back is disabled at the first history entry")
    Swag.require(forward.isEnabled(), "Forward is enabled after going back")
    forward.sigPressed.call(forward)
    completeExplorer(&host, explorer)
    Swag.require(explorer.folder == "docs/")
    up.sigPressed.call(up)
    completeExplorer(&host, explorer)
    Swag.require(explorer.folder.isEmpty())
    explorer.address.beginEdit()
    Swag.require(back.isVisible() and explorer.address.edit.isLocallyVisible())
}

func completeExtraction(host: *Testing.HeadlessHost, explorer: *Explorer)
{
    for 16
    {
        if not explorer.extraction.started do
            return
        explorer.extraction.task.wait()
        host.pump()
    }

    Swag.require(false, "extraction did not settle")
}

// Extracting writes the members under the chosen folder, keeps a file already there, and says how
// it went in a toast; a chosen member lands without the folders above it, and no member's path
// leaves the chosen folder.
#test
{
    Swag.require(ArchiveExtraction.destination("C:/t", "", "../evil.txt").isEmpty())
    Swag.require(ArchiveExtraction.destination("C:/t", "", "a/../../evil.txt").isEmpty())
    if WINDOWS do
        Swag.require(ArchiveExtraction.destination("C:/t", "", ".. /evil.txt").isEmpty())
    Swag.require(ArchiveExtraction.destination("C:/t", "docs/", "docs/").isEmpty())
    Swag.require(ArchiveExtraction.destination("C:/t", "docs/", "docs/readme.txt") == Path.combine("C:/t", "readme.txt"))

    var host: Testing.HeadlessHost
    host.setup(960, 640)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openExplorer(fixture("viewer.archive.zip"))
    let explorer = unwrap window.explorer
    completeExplorer(&host, explorer)

    let target = Gui.Testing.tempFilePath("scope-extract-", "")
    defer discard catch Directory.delete(target, recurse: true)
    explorer.extractTo(target, all: true)
    completeExtraction(&host, explorer)
    Swag.require(explorer.extraction.error.isEmpty() and
                 explorer.extraction.written > 0 and
                 not explorer.extraction.kept)
    Swag.require(File.exists(Path.combine(target, "docs", "readme.txt")))
    Swag.require(explorer.toast!.isLocallyVisible() and explorer.toast.detail == target)
    let written = explorer.extraction.written

    explorer.extractTo(target, all: true)
    completeExtraction(&host, explorer)
    Swag.require(explorer.extraction.written == 0 and explorer.extraction.kept == written)

    let member = Gui.Testing.tempFilePath("scope-extract-member-", "")
    defer discard catch Directory.delete(member, recurse: true)
    explorer.navigate(explorer.listing.path, "docs/")
    completeExplorer(&host, explorer)
    for &entry, index in explorer.entries where entry.name == "readme.txt" do
        explorer.selected = index
    explorer.extractTo(member, all: false)
    completeExtraction(&host, explorer)
    Swag.require(explorer.extraction.written == 1 and File.exists(Path.combine(member, "readme.txt")))
}

// An archive member opens asynchronously with its logical name, then returns to its selected row.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 640)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openExplorer(fixture("viewer.archive.zip"))
    let explorer = unwrap window.explorer
    explorer.setMode(.Names)
    explorer.navigate(fixture("viewer.archive.zip"), "docs/")
    completeExplorer(&host, explorer)
    explorer.selected = 0
    explorer.activate(0)
    Swag.require(explorer.previews[0].started and explorer.previews[0].opening)

    // A second activation supersedes the extraction even if the first worker already finished.
    explorer.previews[0].task.wait()
    explorer.activate(0)
    for preview in explorer.previews do
        preview.task.wait()
    host.pump()
    for preview in explorer.previews where preview.started
    {
        preview.task.wait()
        host.pump()
    }

    completeQueuedViewerFile(&host, window)
    Swag.require(window.currentView != null and not explorer.isLocallyVisible())
    Swag.require(Utf8.endsWith(explorer.displayPath(window.currentFile), "docs/readme.txt"))
    Swag.require(Path.isValidPathName(explorer.logicalPath(window.currentFile)))
    Swag.require(Path.fileName(explorer.logicalPath(window.currentFile)) == "readme.txt")
    Swag.require(window.folderFiles.isEmpty())
    window.setFilePanelVisible(true)
    Swag.require(window.isArchivePreview() and window.folderList.lineCount() == 1)
    window.closeFile()
    host.pump()
    Swag.require(explorer.isLocallyVisible() and explorer.selected == 0)

    explorer.activate(0)
    window.closeFile()
    explorer.previews[0].task.wait()
    host.pump()
    Swag.require(not window.explorerActive and window.pendingFile.isEmpty() and window.currentView == null)
}

// Tile geometry remains bounded by the viewport even for a large folder, and survives mode changes.

// All palettes keep the gallery usable at minimum size, including French labels and the folder pane.
// Set SWAG_SCOPE_REVIEW to a directory inside the test sandbox to inspect the noncanonical palettes.
#test
{
    for palette in 3
    {
        var host: Testing.HeadlessHost
        host.setup(880, 420)
        defer discard catch host.app.setLanguage(ReferenceLanguage)
        registerAppStrings(&host.app.resources)
        switch palette
        {
        case 0: host.theme.setDark()
        case 1: host.theme.setDark()
        case 2: host.theme.setLight()
        }

        host.notify(.ThemeChanged)
        let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
        window.openExplorer(fixture("viewer.archive.zip"))
        let explorer = unwrap window.explorer
        explorer.setMode(.Names)
        completeExplorer(&host, explorer)
        explorer.entries.clear()
        explorer.entries.add({name: "Documents", directory: true, attempted: true})
        for name in ["qrcode.png", "title.png", "sample.cpp", "A document with a long descriptive filename.pdf"]
        {
            with var entry: ExplorerEntry
            {
                .name      = name
                .path      = name
                .attempted = true
            }

            if Utf8.endsWith(name, ".png")
            {
                let image = expect Image.load(fixture(name))
                entry.texture = host.app.renderer.addImage(&image)
            }

            explorer.entries.add(#move entry)
        }

        explorer.address.breadcrumb.clear()
        explorer.address.breadcrumb.addItem("Home")
        explorer.address.breadcrumb.addItem("Gallery")
        explorer.address.refreshPath()
        explorer.selected = 3
        explorer.setMode(.Medium)
        window.setFilePanelVisible(true)
        if palette == 2
        {
            discard expect host.app.setLanguage("fr")
            host.notify(.LanguageChanged)
            Swag.require(explorer.modeMenu.isLocallyVisible())
            Swag.require(window.folderLabel.text == appStrings().explore_Folders)
        }

        window.applyLayout()
        host.settleAnimations(window)
        Swag.require(explorer.grid.clientRect().height > 200)
        Swag.require(not window.searchBar.isLocallyVisible())
        explorer.revealFilter()
        Swag.require(window.searchBox.position.width > 100 and window.searchBox.hasFocus())

        // Filtering floats over the page; sort and view remain in the header, clear of it.
        let filterRect = window.searchBox.surfaceRect()
        let sortRect   = explorer.sortMenu.surfaceRect()
        let toolsRect  = explorer.tools.surfaceRect()
        Swag.require(filterRect.height == 36)
        Swag.require(filterRect.right() <= toolsRect.x or filterRect.bottom() <= toolsRect.y or filterRect.y >= toolsRect.bottom())
        Swag.require(explorer.modeMenu.surfaceRect().y == sortRect.y)
        host.moveMouse(explorer.grid.localToSurface(Math.Point{32, 32}))
        Swag.require(explorer.grid.hovered == 0)

        // Keep one publication pending to photograph its indicator without starting a decoder.
        explorer.refreshPreviewSettings()
        for &entry in explorer.entries do
            entry.attempted = true
        host.app.renderer.removeTexture(&explorer.entries[2].texture)
        explorer.previews[0].index      = 2
        explorer.previews[0].generation = explorer.generation
        explorer.previews[0].submit(func() {})
        var image = host.render(window)
        Swag.require(explorer.grid.spinners[0].isLocallyVisible())
        explorer.previews[0].wait()
        explorer.grid.invalidate()
        discard host.render(window)
        Swag.require(not explorer.grid.spinners[0].isLocallyVisible())
        let review = Env.variable("SWAG_SCOPE_REVIEW")
        if not review.isEmpty() do
            expect image.save(Path.combine(review, Format.toString("explorer-palette-%.png", palette)))
    }
}

// Returning to Explorer follows the current file, even when a previous location was retained.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 640)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openExplorer(fixture("viewer.archive.zip"))
    let explorer = unwrap window.explorer
    explorer.setMode(.Names)
    completeExplorer(&host, explorer)
    window.queueFile(fixture("comprehensive.txt"))
    completeQueuedViewerFile(&host, window)
    window.exploreFolder()
    completeExplorer(&host, explorer)
    Swag.require(window.isExploring() and not explorer.listing.isArchive)
    Swag.require(explorer.listing.path == (expect Path.absolute(unwrap Path.directoryName(fixture("comprehensive.txt")))))
    window.setFilePanelVisible(true)
    var folders: u64
    for &entry in explorer.entries where entry.directory do
        folders += 1
    Swag.require(window.folderList.lineCount() == folders)
}
