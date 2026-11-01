#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

struct RetiringTestView
{
    using wnd: Wnd
    retired:   bool
}

func lensEntryOnFirstPage(window: *ViewerWindow, title: string)->bool
{
    let metrics    = window.lens.themeMetrics()
    let bounds     = window.lens.clientRect()
    let inset      = metrics.floating_Inset
    let top        = Math.max(Math.round(bounds.height * metrics.lens_TopRatio), window.stripInset() + inset)
    let fixed      = metrics.lens_InputHeight + metrics.lens_FooterHeight + 2 * metrics.separator_HairlineSize
    let room       = Math.max(Math.min(bounds.height * metrics.lens_MaxHeightRatio, bounds.height - inset - top), fixed)
    let listHeight = room - fixed
    for row in window.lens.rows where row.entry < row.section.entries.count
    {
        let entry = &row.section.entries[row.entry]
        if entry.title == title do
            return row.top + row.height <= listHeight
    }

    return false
}

func completeLensExplorer(host: *Testing.HeadlessHost, explorer: *Explorer)
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

// A golden can look plausibly rounded at fit-to-window scale while a square child has actually
// repainted its corner. Pin the document panel's own antialiased transition as well as its image.
func assertViewerPanelCorner(image: const *Image, panel: *Wnd)
{
    let rect    = panel.surfaceRect()
    let radius  = cast(s32, panel.themeRects().panel_Bk.radius)
    let outside = panel.parent!.themeColors().toolBar_Bk.argb
    let inside  = panel.themeColors().view_Bk.argb
    let left    = cast(s32, rect.x)
    let top     = cast(s32, rect.y)

    // A theme that grounds the panel and the bar around it alike leaves no corner to see.
    if outside == inside do
        return

    Swag.assert(image.pixelColor(left, top).argb == outside)
    Swag.assert(image.pixelColor(left + radius, top + radius).argb == inside)

    var antialiasedCorner: bool
    for y in 0 until radius
    {
        for x in 0 until radius
        {
            let pixel = image.pixelColor(left + x, top + y).argb
            if pixel != outside and pixel != inside do
                antialiasedCorner = true
        }
    }

    Swag.assert(antialiasedCorner)
}

// Pins the file panel: two named sections share the left edge, the row naming the open file is
// the selected one, and the document keeps the rest of the surface.
#[Swag.TestTag("golden")]
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory, "scope_panel_golden")
    discard catch Directory.delete(folder, recurse: true)
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)

    let names: [4] string = ["changelog.md", "notes.txt", "report-with-a-name-too-long-for-the-fixed-history-panel.txt", "sample.json"]
    for one in names do
        discard expect File.writeAllBytes(Path.combine(folder, one), "a readable line\n")

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    shipFrame(&host)

    var index = createViewerPluginRegistry()

    with let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    {
        .resize(960, 680)
        .openFile(Path.combine(folder, "notes.txt"))
    }

    completeQueuedViewerFile(&host, window)
    completeViewerStatistics(&host, window)
    window.toggleFilePanel()
    window.setPlayMode(.Folder)
    window.openFile(Path.combine(folder, "report-with-a-name-too-long-for-the-fixed-history-panel.txt"), remember: false)
    completeQueuedViewerFile(&host, window)
    completeViewerStatistics(&host, window)
    window.applyLayout()
    host.settleAnimations(window, 4)

    Swag.assert(window.folderList.lineCount() == 4)
    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "panel")
    Testing.assertContentFits(window)
}

// The application About box presents supported content as one compact capability line instead of
// a scrolling extension inventory.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 700)
    shipFrame(&host)

    let appIcon = expect Image.decode(".png", AppIcon)
    host.app.setAppIcon(appIcon)
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    let dialog = window.createAboutDialog({year: 2026, month: 9, day: 1}, version: "1.2.3")
    dialog.applyLayout()

    let surface = unwrap dialog.surface
    var image   = host.renderSurface(surface)
    Pixel.Testing.assertImageGolden(&image, "about")
    surface.destroy()
}

// The framework owns one centered, themed presentation for every viewer decoder reason.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 420)

    let view = ViewerErrorView.create(&host.root, "PNG chunk CRC does not match its payload")
    view.dockStyle = .Center
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    Swag.assert(view.iconLabel.icon.isValid())
    Swag.assert(view.iconLabel.iconColor == view.themeColors().critical)
    Swag.assert(view.summaryLabel.text() == appStrings().ui_ViewerError)
    Swag.assert(view.reasonLabel.text() == "PNG chunk CRC does not match its payload")
    Swag.assert(Math.abs(view.iconLabel.position.center().x - view.position.center().x) <= 1)
    Testing.assertContentFits(view)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "error")
}

// Progressive content keeps streaming without covering useful output. A viewer asks for the
// shared wait presentation separately when it has nothing useful to show yet.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 560)
    shipFrame(&host)

    let fileName = writeTempFile("html", "<p>ready</p>")
    defer discard catch File.delete(fileName)

    var index = createViewerPluginRegistry()

    with let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    {
        .currentFile = fileName
        .choices.add(ViewerPluginChoice{pluginIndex: 0, key: "html"})
        .choices.add(ViewerPluginChoice{pluginIndex: 1, key: "code"})
        .instances.resize(2)
    }

    let loading = Wnd.create'RetiringTestView(window.documentPanel)
    window.instances[0].view      = loading
    window.instances[0].details   = "streamed"
    window.instances[0].isLoading = func()->bool
    {
        return true
    }

    window.instances[0].retire = func|loading|()->bool
    {
        loading.retired = true
        return true
    }

    window.currentView       = loading
    window.activeChoiceIndex = 0
    loading.setPosition({17, 83, 611, 391})

    reportViewerLoadingChanged(loading)
    Swag.assert(not window.loadingOverlay.isLocallyVisible() and window.loadingTimer != null)

    // The mark waits before it appears: a wait that has just begun shows nothing, and the one
    // that has lasted the delay shows the mark, faded in over the preserved document.
    window.instances[0].needsLoadingOverlay = func()->bool => true
    reportViewerLoadingChanged(loading)
    Swag.assert(not window.loadingOverlay.isLocallyVisible() and
                window.loadingWantedSince != 0 and
                window.loadingTimer != null)
    expireViewerLoadingDelay(window)
    Swag.assert(window.loadingOverlay.isLocallyVisible() and window.loadingShownSince != 0)
    host.app.animator.finishAll()
    Swag.assert(window.loadingOverlay.position == loading.position)
    Swag.assert(window.loadingOverlay.backgroundStyle == .Transparent)
    Swag.assert(window.loadingOverlay.wndFlags.has(.Disabled))
    Swag.assert(window.documentPanel.children.back() == window.loadingOverlay)
    Swag.assert(window.loadingOverlay.spinner.position.width == ViewerLoadingOverlay.SpinnerSize and window.loadingOverlay.spinner.position.height == ViewerLoadingOverlay.SpinnerSize)
    let spinnerCenter = window.loadingOverlay.spinner.position.center()
    let overlayCenter = window.loadingOverlay.clientRect().center()
    Swag.assert(Math.abs(spinnerCenter.x - overlayCenter.x) <= 0.5 and Math.abs(spinnerCenter.y - overlayCenter.y) <= 0.5)
    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "loading")

    // A newly selected progressive viewer loads behind the preceding document. The activity
    // mark belongs over that preserved document until the replacement can publish its first frame.
    let outgoing = Wnd.create'Wnd(window)
    outgoing.setPosition({23, 71, 577, 363})
    window.outgoingView = outgoing
    window.currentView  = outgoing
    reportViewerLoadingChanged(loading)
    Swag.assert(window.loadingOverlay.isLocallyVisible() and window.loadingOverlay.position == outgoing.position)
    window.outgoingView = null
    window.currentView  = loading
    outgoing.destroy()

    // A wait that ends right after the mark appeared does not take it away in the same frame:
    // the mark lingers for its minimum time, watched by the poll timer, then goes.
    // Start this short-wait scenario after the snapshot: rendering has no wall-clock bound.
    window.loadingShownSince = Time.monotonicMicroseconds()
    window.instances[0].needsLoadingOverlay = null
    reportViewerLoadingChanged(loading)
    Swag.assert(window.loadingOverlay.isLocallyVisible() and
                window.loadingWantedSince == 0 and
                window.loadingTimer != null)
    expireViewerLoadingLinger(window)
    Swag.assert(not window.loadingOverlay.isLocallyVisible() and window.loadingTimer != null)
    Swag.assert(window.activateChoice(1))
    Swag.assert(loading.retired and loading.isPendingDestroy)
    Swag.assert(window.instances[0].view == null)
    Swag.assert(window.currentView != null and window.currentView != loading)
    Swag.assert(window.instances[1].view == window.currentView)
    Swag.assert(not window.loadingOverlay.isLocallyVisible() and window.loadingTimer == null)
}

// Pins the shipped empty surface of a first launch: the mark, the invitation to drop a file and
// the faint hint teaching the door, with no history yet and no format-specific controls.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    shipFrame(&host)
    host.app.setAppIcon(expect Image.decode(".png", AppIcon))

    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    host.theme.setDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    window.applyLayout()
    host.settleAnimations(window, 4)

    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "surface")
}

// Pins the open-document composition in Encre and Papier: the document and its faint readings,
// nothing above it but the strip, and the find bar floating at its top while a query runs.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    shipFrame(&host)

    host.theme.setDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    var index = createViewerPluginRegistry()

    with let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    {
        .resize(960, 680)
        .openFile(viewerFixturePath())
    }

    completeQueuedViewerFile(&host, window)
    completeViewerStatistics(&host, window)
    window.applyLayout()
    host.settleAnimations(window, 4)

    Swag.assert(not window.sendComputeCommandStateEvent(ViewerCommands.OpenDefault).hidden)
    Swag.assert(window.readingLine.isLocallyVisible() and not window.home.isLocallyVisible())
    Swag.assert(not window.hintLine.isLocallyVisible())
    Swag.assert(window.currentView!.parent == window.documentPanel)
    Swag.assert(window.currentCommands!.parent == window.viewerBar and not window.viewerBar.isLocallyVisible())
    Swag.assert(window.currentCommands.backgroundStyle == .Transparent)
    Swag.assert(window.searchBox.isEnabled() and not window.searchBar.isLocallyVisible())
    var dark = host.render(window)
    assertViewerPanelCorner(&dark, window.documentPanel)
    Pixel.Testing.assertImageGolden(&dark, "viewer.dark")

    window.showSearch()
    window.searchBox.setText("verification marker")
    completeViewerSearch(&host, window)
    discard host.render(window)
    host.fireTimers()
    var searchDark = host.render(window)
    Pixel.Testing.assertImageGolden(&searchDark, "search.dark")
    window.searchBox.setText("")
    window.hideSearch()

    window.applyTheme(cast(u32, AppearanceTheme.Light))
    host.notify(.ThemeChanged)
    host.settleAnimations(window, 4)
    var light = host.render(window)
    assertViewerPanelCorner(&light, window.documentPanel)
    Pixel.Testing.assertImageGolden(&light, "viewer.light")

    window.showSearch()
    window.searchBox.setText("verification marker")
    completeViewerSearch(&host, window)
    discard host.render(window)
    host.fireTimers()
    var searchLight = host.render(window)
    Pixel.Testing.assertImageGolden(&searchLight, "search.light")
}

// Opening the lens on a Markdown document keeps its basic actions and outline in the first viewport.
#[Swag.TestTag("golden")]
#test
{
    let fileName = Testing.tempFilePath("scope-lens-markdown-", ".md")
    discard expect File.writeAllBytes(fileName, "# Guide\n\n## Getting started\n")
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    shipFrame(&host)
    host.theme.setDark()
    host.notify(.ThemeChanged)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.resize(960, 680)
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    window.lens.open()
    host.finishAnimations()

    var fileSection: *Lens.Section?
    var viewSection: *Lens.Section?
    for section in window.lens.results.sections
    {
        if section
        {
            if section.label == appStrings().lens_File do
                fileSection = section
            elif section.label == appStrings().lens_View do
                viewSection = section
        }
    }

    let file    = unwrap fileSection
    let view    = unwrap viewSection
    let outline = window.currentSidePanelButton!.toolTip
    Swag.assert(window.lens.query() == "")
    Swag.assert(file.entries.count == 3)
    Swag.assert(file.entries[0].title == appStrings().cmd_Open)
    Swag.assert(file.entries[1].title == appStrings().cmd_Explore)
    Swag.assert(file.entries[2].title == appStrings().ui_CloseFile)
    Swag.assert(view.entries[0].title == outline)
    Swag.assert(lensEntryOnFirstPage(window, appStrings().cmd_Open))
    Swag.assert(lensEntryOnFirstPage(window, appStrings().cmd_Explore))
    Swag.assert(lensEntryOnFirstPage(window, appStrings().ui_CloseFile))
    Swag.assert(lensEntryOnFirstPage(window, outline))
    Swag.assert(window.lens.results.sections[0]!.label == appStrings().lens_File)
    Swag.assert(window.lens.results.sections[1]!.label == appStrings().lens_View)
    Swag.assert(window.lens.chosenEntry()!.title == appStrings().cmd_Open)

    window.resize(800, 600)
    window.applyLayout()
    Swag.assert(lensEntryOnFirstPage(window, appStrings().cmd_Open))
    Swag.assert(lensEntryOnFirstPage(window, appStrings().cmd_Explore))
    Swag.assert(lensEntryOnFirstPage(window, appStrings().ui_CloseFile))
    Swag.assert(lensEntryOnFirstPage(window, outline))
    window.resize(960, 680)
    window.applyLayout()

    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "viewer.lens.markdown.encre")

    var paperHost: Testing.HeadlessHost
    paperHost.setup(960, 680)
    shipFrame(&paperHost)
    paperHost.theme.setLight()
    let paperWindow = ViewerWindow.create(&paperHost.surfaceWnd, createViewerPluginRegistry())
    paperWindow.resize(960, 680)
    paperWindow.openFile(fileName, remember: false)
    completeQueuedViewerFile(&paperHost, paperWindow)
    paperWindow.lens.open()
    paperHost.finishAnimations()
    var paper = paperHost.render(paperWindow)
    Pixel.Testing.assertImageGolden(&paper, "viewer.lens.markdown.paper")
}

// Entering folder exploration puts its common actions in the lens without a command query.
#[Swag.TestTag("golden")]
#test
{
    // Rounded lens edges include the blurred explorer underneath: give it a stable corpus.
    let root = Testing.tempFilePath("scope-lens-explorer-", "")
    let fixtureFolder = Path.combine(root, "Library")
    expect Directory.create(fixtureFolder, recurse: true)
    defer discard catch Directory.delete(root, recurse: true)
    let fileName = Path.combine(fixtureFolder, "Guide.md")
    discard expect File.writeAllBytes(fileName, "# Guide\n")

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    shipFrame(&host)
    host.theme.setDark()
    host.notify(.ThemeChanged)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.resize(960, 680)
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    window.exploreFolder()
    let explorer = unwrap window.explorer
    completeLensExplorer(&host, explorer)
    Swag.assert(explorer.entries.count == 1)
    var selected = Swag.U64.Max
    for &entry, index in explorer.entries where entry.name == Path.fileName(fileName) do
        selected = index
    Swag.assert(selected != Swag.U64.Max)
    explorer.selected = selected
    window.lens.open()
    host.finishAnimations()

    var folderSection: *Lens.Section?
    var fileSection:   *Lens.Section?
    for section in window.lens.results.sections where section and section.label == appStrings().lens_Folder do
        folderSection = section
    for section in window.lens.results.sections where section and section.label == appStrings().lens_File do
        fileSection = section
    let folder = unwrap folderSection
    let file   = unwrap fileSection
    Swag.assert(window.lens.query() == "")
    Swag.assert(lensHasEntry(window, appStrings().explore_Up))
    Swag.assert(lensHasEntry(window, appStrings().explore_Refresh))
    Swag.assert(lensHasEntry(window, appStrings().cmd_EditLocation))
    Swag.assert(lensHasEntry(window, appStrings().cmd_OpenChosen))
    Swag.assert(lensEntryOnFirstPage(window, appStrings().explore_Up))
    Swag.assert(lensEntryOnFirstPage(window, appStrings().explore_Refresh))
    Swag.assert(lensEntryOnFirstPage(window, appStrings().cmd_EditLocation))
    Swag.assert(lensEntryOnFirstPage(window, appStrings().cmd_OpenChosen))
    Swag.assert(window.lens.results.sections[0]!.label == appStrings().lens_Folder)
    Swag.assert(file.entries.count == 2 and file.entries[0].title == appStrings().cmd_Open)
    Swag.assert(file.entries[1].title == appStrings().ui_CloseFile)
    Swag.assert(folder.entries.count >= 4)

    var image = host.render(window)
    image.crop(window.lens.body())
    Pixel.Testing.assertImageGolden(&image, "viewer.lens.explorer.encre")

    var paperHost: Testing.HeadlessHost
    paperHost.setup(960, 680)
    shipFrame(&paperHost)
    paperHost.theme.setLight()
    paperHost.notify(.ThemeChanged)
    let paperWindow = ViewerWindow.create(&paperHost.surfaceWnd, createViewerPluginRegistry())
    paperWindow.resize(960, 680)
    paperWindow.openFile(fileName, remember: false)
    completeQueuedViewerFile(&paperHost, paperWindow)
    paperWindow.exploreFolder()
    let paperExplorer = unwrap paperWindow.explorer
    completeLensExplorer(&paperHost, paperExplorer)
    paperHost.notify(.ThemeChanged)
    selected = Swag.U64.Max
    for &entry, index in paperExplorer.entries where entry.name == Path.fileName(fileName) do
        selected = index
    Swag.assert(selected != Swag.U64.Max)
    paperExplorer.selected = selected
    paperWindow.lens.open()
    Swag.assert(paperWindow.isExploring())
    Swag.assert(paperWindow.lens.results.sections[0]!.label == appStrings().lens_Folder)
    Swag.assert(lensHasEntry(paperWindow, appStrings().explore_Up))
    Swag.assert(lensEntryOnFirstPage(paperWindow, appStrings().explore_Up))
    paperHost.finishAnimations()
    var paper = paperHost.render(paperWindow)
    paper.crop(paperWindow.lens.body())
    Pixel.Testing.assertImageGolden(&paper, "viewer.lens.explorer.paper")
}
