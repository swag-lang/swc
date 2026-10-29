#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

func fixture(name: string)->String => Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas", name)

func completeExplorer(host: *Testing.HeadlessHost, explorer: *Explorer)
{
    for 16
    {
        if not explorer.load.started do
            return
        explorer.load.task.wait()
        host.pump()
    }

    Swag.assert(false, "exploration did not settle")
}

// Filesystem and ZIP locations expose the same immediate-child model, including implicit folders.
#test
{
    var listing = expect ExplorerListing.load(unwrap Path.directoryName(fixture("comprehensive.txt")))
    Swag.assert(not listing.isArchive and listing.entries.count > 10)
    var found = false
    for &entry in listing.entries where entry.name == "comprehensive.txt"
    {
        found = true
        Swag.assert(not entry.directory and entry.size > 0 and not entry.modified.isEmpty())
    }

    Swag.assert(found)

    var archive = expect ExplorerListing.load(fixture("viewer.archive.zip"))
    Swag.assert(archive.isArchive)
    let roots = archive.children("")
    Swag.assert(roots.count == 2)
    let documents = archive.children("docs/")
    Swag.assert(documents.count == 1 and documents[0].name == "readme.txt")
    Swag.assert(documents[0].path == "docs/readme.txt" and documents[0].archiveIndex != Swag.U64.Max)
    for &entry in roots where entry.directory
    {
        let children = archive.children(entry.path)
        for &child in children do
            Swag.assert(Utf8.startsWith(child.path, entry.path))
    }

    archive.archive.entries.clear()
    archive.archive.entries.add({path: "docs", isDirectory: true})
    archive.archive.entries.add({path: "docs/one.txt"})
    archive.archive.entries.add({path: "docs2/two.txt"})
    let explicitFolders = archive.children("")
    Swag.assert(explicitFolders.count == 2 and explicitFolders[0].path == "docs/")
    Swag.assert(archive.children(explicitFolders[0].path).count == 1)
}

// Opening a file directly stays simple; explicit exploration survives viewing and closing a file.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 640)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.queueFile(fixture("comprehensive.txt"))
    completeQueuedViewerFile(&host, window)
    Swag.assert(not window.explorerActive and window.explorer == null)
    window.exploreFolder()
    Swag.assert(window.explorerActive and window.explorer != null)
    let explorer = window.explorer
    explorer.setMode(.Details)
    completeExplorer(&host, explorer)
    Swag.assert(explorer.isLocallyVisible() and explorer.shown.count > 0)
    var selected = Swag.U64.Max
    for &entry, index in explorer.entries where entry.name == "comprehensive.txt" do
        selected = index
    Swag.assert(selected != Swag.U64.Max)
    explorer.selected = selected
    explorer.activate(selected)
    completeQueuedViewerFile(&host, window)
    Swag.assert(not explorer.isLocallyVisible() and window.currentView != null)
    window.setFilePanelVisible(true)
    Swag.assert(not window.isExploring() and window.folderList.lineCount() == window.folderFiles.count)
    window.closeFile()
    host.pump()
    Swag.assert(explorer.isLocallyVisible() and explorer.selected == selected and explorer.mode == .Details)
    window.closeFile()
    Swag.assert(not window.explorerActive and window.home.isLocallyVisible())
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
    Swag.assert(explorer.listing.isArchive and explorer.listing.path == (expect Path.absolute(fixture("viewer.archive.zip"))))
    explorer.goBack()
    completeExplorer(&host, explorer)
    Swag.assert(not explorer.listing.isArchive)
}

// An archive is a page: its folders and members as quiet rows with their dates, "Extract All…" on
// the title's line, and the chosen member in the sheet with Open and "Extract…".
func archivePage(host: *Testing.HeadlessHost, light: bool)->*ViewerWindow
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

#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        let window   = archivePage(&host, light)
        let explorer = unwrap window.explorer
        Swag.assert(explorer.extractAll.isLocallyVisible() and explorer.extractAll.name.raw == appStrings().cmd_ExtractAll)
        for &entry in explorer.entries do
            Swag.assert(entry.directory and entry.modified.length == 16)

        // The chosen member, its picture not asked for so the page holds still.
        explorer.navigate(explorer.listing.path, "docs/")
        completeExplorer(&host, explorer)
        explorer.address.breadcrumb.clear()
        explorer.address.breadcrumb.addItem("viewer.archive.zip")
        explorer.address.refreshPath()
        for &entry in explorer.entries do
            entry.attempted = true
        explorer.selected = 0
        explorer.fill()
        explorer.showInformation()
        let sheet = window.infoSheet.text()
        Swag.assert(Utf8.contains(sheet, appStrings().cmd_OpenChosen) and Utf8.contains(sheet, appStrings().cmd_Extract))
        Swag.assert(Utf8.contains(sheet, "CRC-32"))
        window.applyLayout()
        host.settleAnimations(window)
        var image = host.render(window)
        Pixel.Testing.assertImageGolden(&image, light ? "explorer.archive.paper" : "explorer.archive")
    }
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

    Swag.assert(false, "extraction did not settle")
}

// Extracting writes the members under the chosen folder, keeps a file already there, and says how
// it went in a toast; a chosen member lands without the folders above it, and no member's path
// leaves the chosen folder.
#test
{
    Swag.assert(ArchiveExtraction.destination("C:/t", "", "../evil.txt").isEmpty())
    Swag.assert(ArchiveExtraction.destination("C:/t", "", "a/../../evil.txt").isEmpty())
    Swag.assert(ArchiveExtraction.destination("C:/t", "docs/", "docs/").isEmpty())
    Swag.assert(ArchiveExtraction.destination("C:/t", "docs/", "docs/readme.txt") == Path.combine("C:/t", "readme.txt"))

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
    Swag.assert(explorer.extraction.error.isEmpty() and explorer.extraction.written > 0 and not explorer.extraction.kept)
    Swag.assert(File.exists(Path.combine(target, "docs", "readme.txt")))
    Swag.assert(explorer.toast!.isLocallyVisible() and explorer.toast.detail == target)
    let written = explorer.extraction.written

    explorer.extractTo(target, all: true)
    completeExtraction(&host, explorer)
    Swag.assert(explorer.extraction.written == 0 and explorer.extraction.kept == written)

    let member = Gui.Testing.tempFilePath("scope-extract-member-", "")
    defer discard catch Directory.delete(member, recurse: true)
    explorer.navigate(explorer.listing.path, "docs/")
    completeExplorer(&host, explorer)
    for &entry, index in explorer.entries where entry.name == "readme.txt" do
        explorer.selected = index
    explorer.extractTo(member, all: false)
    completeExtraction(&host, explorer)
    Swag.assert(explorer.extraction.written == 1 and File.exists(Path.combine(member, "readme.txt")))
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
    Swag.assert(explorer.previews[0].started and explorer.previews[0].opening)

    // A second activation supersedes the extraction even if the first worker already finished.
    explorer.previews[0].task.wait()
    explorer.activate(0)
    for &preview in explorer.previews do
        preview.task.wait()
    host.pump()
    for &preview in explorer.previews where preview.started
    {
        preview.task.wait()
        host.pump()
    }

    completeQueuedViewerFile(&host, window)
    Swag.assert(window.currentView != null and not explorer.isLocallyVisible())
    Swag.assert(Utf8.endsWith(explorer.displayPath(window.currentFile), "docs/readme.txt"))
    Swag.assert(window.folderFiles.isEmpty())
    window.setFilePanelVisible(true)
    Swag.assert(window.isArchivePreview() and window.folderList.lineCount() == 1)
    window.closeFile()
    host.pump()
    Swag.assert(explorer.isLocallyVisible() and explorer.selected == 0)

    explorer.activate(0)
    window.closeFile()
    explorer.previews[0].task.wait()
    host.pump()
    Swag.assert(not window.explorerActive and window.pendingFile.isEmpty() and window.currentView == null)
}

// Tile geometry remains bounded by the viewport even for a large folder, and survives mode changes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 640)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let explorer = Explorer.create(window.documentPanel, window)
    explorer.setMode(.Names)
    for index in 20_000
    {
        with var entry: ExplorerEntry
        {
            .name      = Format.toString("File %.txt", index)
            .attempted = true
        }

        explorer.entries.add(#move entry)
    }

    explorer.fill()
    explorer.selected = 1234
    explorer.setMode(.Small)
    window.applyLayout()
    let visible = explorer.grid.visibleRange()
    Swag.assert(visible.end - visible.first < 100 and explorer.shown.count == 20_000)
    explorer.setMode(.Details)
    Swag.assert(explorer.selected == 1234 and explorer.list.focusIndex == 1234)
    explorer.filter.setText("File 1234.txt")
    Swag.assert(explorer.shown.count == 1 and explorer.shown[0] == 1234)
}

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
            Swag.assert(explorer.modeMenu.name.raw == appStrings().mode_Thumbnails)
            Swag.assert(window.folderLabel.text == appStrings().explore_Folders)
        }

        window.applyLayout()
        host.settleAnimations(window)
        Swag.assert(explorer.grid.clientRect().height > 200)
        Swag.assert(not explorer.filter.isLocallyVisible())
        explorer.revealFilter()
        Swag.assert(explorer.filter.position.width > 100 and explorer.filter.hasFocus())
        // The filter takes a line of its own under the title, which keeps its room.
        let filterRect = explorer.filter.surfaceRect()
        let modesRect  = explorer.modeMenu.surfaceRect()
        Swag.assert(filterRect.y >= explorer.title.surfaceRect().bottom() and filterRect.height == Explorer.ToolHeight)
        Swag.assert(modesRect.height <= 36)
        host.moveMouse(explorer.grid.localToSurface(Math.Point{32, 32}))
        Swag.assert(explorer.grid.hovered == 0)

        // Keep one publication pending to photograph its indicator without starting a decoder.
        host.app.renderer.removeTexture(&explorer.entries[2].texture)
        explorer.previews[0].index      = 2
        explorer.previews[0].generation = explorer.generation
        explorer.previews[0].submit(func() {})
        var image = host.render(window)
        Swag.assert(explorer.grid.spinners[0].isLocallyVisible())
        explorer.previews[0].wait()
        explorer.grid.invalidate()
        discard host.render(window)
        Swag.assert(not explorer.grid.spinners[0].isLocallyVisible())
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
    Swag.assert(window.isExploring() and not explorer.listing.isArchive)
    Swag.assert(explorer.listing.path == (expect Path.absolute(unwrap Path.directoryName(fixture("comprehensive.txt")))))
    window.setFilePanelVisible(true)
    var folders: u64
    for &entry in explorer.entries where entry.directory do
        folders += 1
    Swag.assert(window.folderList.lineCount() == folders)
}
