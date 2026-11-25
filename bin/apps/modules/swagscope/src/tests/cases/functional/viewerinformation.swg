#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Audio

// Waits for the requested viewer and its optional artwork without depending on scheduler order.
internal func completeInformation(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    for 4_096
    {
        window.information.request()
        Swag.drainWork()
        host.pump()
        let source = window.information
        let viewer: Viewer.Embedded? = source.viewer
        if not source.preview.started and (not viewer or not viewer.isLoading())
        {
            window.refreshInformation()
            return
        }

        host.fireTimers()
        Threading.Thread.sleep(1'ms)
    }

    Swag.require(false, "information did not settle")
}

private func informationPages(window: *ViewerWindow)->Array'String
{
    var result: #returntype
    window.infoSheet.selectPage(0)
    result.add(window.infoSheet.text())
    if window.information.hasMediaSelection()
    {
        window.infoSheet.selectPage(1)
        result.add(window.infoSheet.text())
    }

    return result
}

// Explorer and a direct open use the corresponding viewer's complete information, page for page.
func assertInformationParity(name: string)
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    let file = scopeTestDataPath(name)
    var explored: Array'String
    scope
    {
        var host: Testing.HeadlessHost
        host.setup(960, 680)
        let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
        window.onlineMovies = false
        window.onlineMusic  = false
        let explorer = Explorer.create(window.documentPanel, window)
        window.explorer       = explorer
        window.explorerActive = true
        let info = expect File.info(file)
        explorer.listing.path = unwrap Path.directoryName(file)
        explorer.entries.add({name: name, path: file, size: info.size,
                              modified: info.lastWriteTime.toString(.DateTimeIsoHm)})
        explorer.fill()
        explorer.show()
        explorer.selected = 0
        window.toggleInformation()
        completeInformation(&host, window)
        window.refreshInformation()
        window.information.describe(window.infoSheet, includeAction: false)
        explored = informationPages(window)
        if name == "glint-aac-mjpeg.mp4"
        {
            Swag.require(explored.count == 2 and Utf8.contains(explored[1], "Frame rate"))
            Swag.require(Utf8.contains(explored[1], "Audio"))
            let panel = assume cast(*Viewers.Film.Panel, window.information.viewer!.currentView)
            Swag.require(not panel.playing and
                         not panel.autoPlayPending and
                         not panel.audioEngineAcquired and
                         panel.voice == null)
        }
    }

    scope
    {
        var host: Testing.HeadlessHost
        host.setup(960, 680)
        let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
        window.onlineMovies = false
        window.onlineMusic  = false
        window.openFile(file, remember: false)
        completeQueuedViewerFile(&host, window)
        window.toggleInformation()
        completeInformation(&host, window)
        let opened = informationPages(window)
        Swag.require(opened.count == explored.count, name)
        for page in opened.count do
            Swag.require(opened[page] == explored[page], Format.toString("%\nExplorer:\n%\nViewer:\n%", name, explored[page], opened[page]))
    }
}

#test { assertInformationParity("comprehensive.txt") }
#test { assertInformationParity("title.png") }
#test { assertInformationParity("pacman_beginning.wav") }
#test { assertInformationParity("viewer.mp3") }
#test { assertInformationParity("viewer.flac") }
#test { assertInformationParity("glint-aac-mjpeg.mp4") }

// A direct open uses cached online media without any Explorer, and exposes the online options.
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.onlineMovies = true
    window.onlineMusic  = true
    let file     = Path.combine(testSourceRoot(#curlocation), "datas", "glint-aac-mjpeg.mp4")
    let key      = expect ThumbnailCache.key(file, settings: ThumbnailSettings.capture(window))
    let previous = ThumbnailCache.read(key)
    defer
    {
        if previous.isValid() do
            expect ThumbnailCache.write(key, &previous)
        else do
            discard catch File.delete(key)
    }

    var artwork = Image.create(32, 48, .RGB8)
    let movie   = OnlineMovie{title: "Glint", overview: "A cached film synopsis"}
    movie.label(&artwork)
    expect ThumbnailCache.write(key, &artwork)
    window.openFile(file, remember: false)
    completeQueuedViewerFile(&host, window)
    window.toggleInformation()
    completeInformation(&host, window)
    Swag.require(window.explorer == null)
    Swag.require(Utf8.contains(window.infoSheet.text(), "A cached film synopsis"))
    window.infoSheet.selectPage(1)
    Swag.require(Utf8.contains(window.infoSheet.text(), "Frame rate"))
    Swag.require(not window.sendComputeCommandStateEvent(ViewerCommands.OnlineMovies).hidden)
    Swag.require(not window.sendComputeCommandStateEvent(ViewerCommands.OnlineMusic).hidden)
    Swag.require(window.runCommand(ViewerCommands.OnlineMovies))
    completeInformation(&host, window)
    window.infoSheet.selectPage(0)
    Swag.require(not window.onlineMovies and not Utf8.contains(window.infoSheet.text(), "A cached film synopsis"))
    window.closeInformation()
    Swag.require(not window.infoSheet.isLocallyVisible())
}

// The panel keeps the same height across content, pages, languages and palettes, centred in its viewport.
#test
{
    for language in [ReferenceLanguage, "fr"]
    {
        var host: Testing.HeadlessHost
        host.setup(960, 680, 1.5)
        registerAppStrings(&host.app.resources)
        discard expect host.app.setLanguage(language)
        defer discard catch host.app.setLanguage(ReferenceLanguage)
        let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
        window.onlineMovies = false
        window.openFile(Path.combine(testSourceRoot(#curlocation), "datas", "glint-aac-mjpeg.mp4"), remember: false)
        completeQueuedViewerFile(&host, window)
        window.concealViewerBar()
        window.toggleInformation()
        window.layoutFloatingParts()
        let sheet  = window.infoSheet
        let bounds = sheet.position
        let area   = window.documentArea()
        let inset  = window.themeMetrics().floating_Inset
        let top    = Math.max(area.y, window.stripInset())
        Swag.require(bounds.y == top + inset and bounds.bottom() + inset <= window.viewerBar.position.y)
        window.revealViewerBar()
        Swag.require(sheet.position == bounds and window.documentArea() == area)
        window.concealViewerBar()
        Swag.require(sheet.position == bounds)
        sheet.selectPage(1)
        Swag.require(sheet.position == bounds)
        for 40 do
            sheet.addText("A paragraph that makes the information scroll.")
        Swag.require(sheet.position == bounds)
        host.theme.setLight()
        host.notify(.ThemeChanged)
        window.applyLayout()
        Swag.require(sheet.position == bounds)
        let viewport = host.surface.position
        window.setFullScreen(true)
        host.surface.showNormalAt(viewport)
        window.applyLayout()
        window.revealViewerBar()
        window.layoutFloatingParts()
        Swag.require(sheet.position.y == window.documentArea().y + inset)
        Swag.require(sheet.position.bottom() + inset <= window.viewerBar.position.y)
        let fullScreenArea = window.documentArea()
        window.closeInformation()
        window.toggleInformation()
        Swag.require(window.documentArea() == fullScreenArea)
    }
}

// Archive members use the same corresponding viewer before and after foreground extraction.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.onlineMovies = false
    window.onlineMusic  = false
    window.openExplorer(Path.combine(testSourceRoot(#curlocation), "datas", "viewer.archive.zip"))
    let explorer = unwrap window.explorer
    completeExplorer(&host, explorer)
    explorer.navigate(explorer.listing.path, "docs/")
    completeExplorer(&host, explorer)
    explorer.selected = 0
    window.toggleInformation()
    completeInformation(&host, window)
    Swag.require(window.information.viewer != null,
                 Format.toString("Archive information: extracted=%, exists=%, attempted=%, failure=%, preview=%",
                                 window.information.extracted,
                                 File.exists(window.information.extracted),
                                 window.information.extractionAttempted,
                                 window.information.extractionFailure,
                                 window.information.preview.error))
    window.information.describe(window.infoSheet)
    let selected = informationPages(window)
    explorer.activate(0)
    for 256
    {
        Swag.drainWork()
        host.pump()
        if not window.currentFile.isEmpty() or not window.pendingFile.isEmpty() do
            break
        Threading.Thread.sleep(1'ms)
    }

    Swag.require(not window.currentFile.isEmpty() or not window.pendingFile.isEmpty())
    completeQueuedViewerFile(&host, window)
    completeInformation(&host, window)
    let opened = informationPages(window)
    Swag.require(selected.count == opened.count)
    for page in selected.count do
        Swag.require(selected[page] == opened[page], Format.toString("Explorer:\n%\nViewer:\n%", selected[page], opened[page]))
}

// Music opened directly retains the online album and the recording's own tag identity.
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.onlineMovies = false
    window.onlineMusic  = true
    let file     = scopeTestDataPath("viewer.mp3")
    let key      = expect ThumbnailCache.key(file, settings: ThumbnailSettings.capture(window))
    let previous = ThumbnailCache.read(key)
    defer
    {
        if previous.isValid() do
            expect ThumbnailCache.write(key, &previous)
        else do
            discard catch File.delete(key)
    }

    var artwork = Image.create(32, 32, .RGB8)
    let music   = OnlineMusic{title: "Discovery", firstReleaseDate: "2001-03-12"}
    let tags    = SoundTags{title: "One More Time", artist: "Daft Punk", albumArtist: "Album Artist"}
    music.label(&artwork, &tags)
    expect ThumbnailCache.write(key, &artwork)
    window.openFile(file, remember: false)
    completeQueuedViewerFile(&host, window)
    window.toggleInformation()
    completeInformation(&host, window)
    Swag.require(window.explorer == null and window.infoSheet.title == "One More Time")
    let media = window.infoSheet.text()
    Swag.require(Utf8.contains(media, "Discovery") and Utf8.contains(media, "Daft Punk"), media)
    Swag.require(Utf8.contains(media, "Album Artist") and Utf8.contains(media, "MusicBrainz"))
    window.infoSheet.selectPage(1)
    Swag.require(Utf8.contains(window.infoSheet.text(), "Sample rate"))
}

// File identity and decoded readings stay fresh even when Explorer still holds an older listing.
#test
{
    let folder = Testing.tempFilePath("scope-information-refresh-", "")
    expect Directory.create(folder)
    let file = Path.combine(folder, "notes.txt")
    defer discard catch Directory.delete(folder, recurse: true)
    discard expect File.writeAllText(file, "Before")
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openExplorer(folder)
    let explorer = unwrap window.explorer
    completeExplorer(&host, explorer)
    explorer.selected = 0
    window.toggleInformation()
    completeInformation(&host, window)
    let listedSize = explorer.entries[0].size
    discard expect File.writeAllText(file, "After\nTwo lines\n")
    window.refreshInformation()
    completeInformation(&host, window)
    Swag.require(explorer.entries[0].size == listedSize)
    Swag.require(window.information.entry.size == (expect File.info(file)).size)
    Swag.require(Utf8.contains(window.infoSheet.text(), "2 lines"))
}

private var g_ProbeDescriptions: u32
private var g_ProbeServices:     Viewer.HostServices

// A viewer that only counts how often the host has it describe the information sheet.
private func createProbeViewer(host: Viewer.Host)
{
    host.attachView(Wnd.create'Wnd(host.contentParent()))
    host.setDetails("Probe")
    host.setInformation(func||(_) { g_ProbeDescriptions += 1 })
    g_ProbeServices = host.services()
}

// A summary repeated as it stands leaves an open sheet alone. A new summary, or a viewer saying
// its contribution changed, has the sheet described again.
#test
{
    var registry = createViewerPluginRegistry()
    with var plugin: Viewer.Plugin
    {
        .key          = "probe"
        .staticName   = "Probe"
        .iconAtlas    = viewerIcons()
        .create       = &createProbeViewer
        .smokeFixture = "sample.probe"
        .addSelectors(".probe")
    }

    expect registry.register(#move plugin)
    let file = Testing.tempFilePath("scope-information-probe-", ".probe")
    defer discard catch File.delete(file)
    discard expect File.writeAllText(file, "probe")
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, #move registry)
    window.openFile(file, remember: false)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.choices[window.activeChoiceIndex].key == "probe")
    window.toggleInformation()
    Swag.require(window.infoSheet.isLocallyVisible() and g_ProbeDescriptions != 0)

    let view   = unwrap window.instances[window.activeChoiceIndex].view
    let opened = g_ProbeDescriptions
    g_ProbeServices.showDetails(view, "Probe")
    Swag.require(g_ProbeDescriptions == opened)
    g_ProbeServices.informationChanged(view)
    Swag.require(g_ProbeDescriptions > opened)
    let marked = g_ProbeDescriptions
    g_ProbeServices.showDetails(view, "Probe 2")
    Swag.require(g_ProbeDescriptions > marked)
}
