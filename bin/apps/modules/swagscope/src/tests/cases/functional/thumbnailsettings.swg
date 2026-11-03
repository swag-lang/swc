#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Refresh retries unchanged files instead of reusing a failed or stale preview identity.
#test
{
    var host: Testing.HeadlessHost
    host.setup(880, 560)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let explorer = Explorer.create(window.documentPanel, window)
    explorer.setMode(.Names)
    let source = Path.combine(testSourceRoot(#curlocation), "datas", "comprehensive.txt")
    explorer.listing.path = unwrap Path.directoryName(source)
    explorer.refreshPreviewSettings()
    let original = expect ThumbnailCache.key(source, settings: explorer.previewSettings)
    explorer.forceRefresh()
    completeExplorer(&host, explorer)
    explorer.refreshPreviewSettings()
    let refreshed = expect ThumbnailCache.key(source, settings: explorer.previewSettings)
    Swag.require(refreshed != original)
    explorer.forceRefresh()
    completeExplorer(&host, explorer)
    explorer.refreshPreviewSettings()
    Swag.require((expect ThumbnailCache.key(source, settings: explorer.previewSettings)) != refreshed)
}

// Appearance changes leave previews intact; changing the selected viewer retires them.
#test
{
    let previousMarkdown = MarkdownText.g_ViewerSettings
    defer MarkdownText.g_ViewerSettings = previousMarkdown
    var host: Testing.HeadlessHost
    host.setup(880, 560)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let explorer = Explorer.create(window.documentPanel, window)
    explorer.setMode(.Names)
    let source = Path.combine(testSourceRoot(#curlocation), "datas", "comprehensive.md")
    MarkdownText.g_ViewerSettings = {themeIndex: 1, widthIndex: 2, zoomPercent: 125}
    explorer.refreshPreviewSettings()
    let originalSettings = String.from(explorer.previewSettings)
    let originalKey      = expect ThumbnailCache.key(source, settings: originalSettings)
    var image            = Image.create(8, 8, .RGB8)
    explorer.entries.add({name: "comprehensive.md", path: source, attempted: true,
                          texture: host.app.renderer.addImage(&image)})
    explorer.cached.add(0)
    let generation = explorer.generation
    MarkdownText.g_ViewerSettings.themeIndex = 5
    explorer.refreshPreviewSettings()
    Swag.require(explorer.generation == generation and explorer.cached.count == 1)
    Swag.require(explorer.entries[0].attempted and explorer.entries[0].texture.isValid())
    Swag.require(explorer.previewSettings == originalSettings)
    Swag.require(originalKey == (expect ThumbnailCache.key(source, settings: explorer.previewSettings)))
    Swag.require(ThumbnailSettings.capture(window) == explorer.previewSettings)

    window.preferences.add(ViewerPreference{"markdown", "text"})
    explorer.refreshPreviewSettings()
    let transferred = expect ThumbnailSettings.decode(explorer.previewSettings)
    Swag.require(not transferred.usesDefaultViewer("markdown"))
    Swag.require(explorer.generation == generation + 1 and explorer.cached.isEmpty())
    Swag.require(not explorer.entries[0].attempted and not explorer.entries[0].texture.isValid())
    Swag.require(originalKey != (expect ThumbnailCache.key(source, settings: explorer.previewSettings)))
}

// Both user corrections survive the same application-state save and restore as the real window.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    let path = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-choices-%.scc", Guid64.random()))
    defer catch File.delete(path)
    host.app.setStatePath(path)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let album  = ExplorerEntry{path: "C:/music/first.mp3", size: 20, creationStamp: 3, modifiedStamp: 4}
    let id     = "48140466-cff6-3222-bd55-63c27e43190d"
    setMusicChoice(&window.musicChoices, &album, id)
    expect host.app.saveState()
    window.musicChoices.clear()
    expect host.app.loadState()
    Swag.require(musicChoiceId(window.musicChoices.toSlice(), &album) == id)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    let window  = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let first   = ExplorerEntry{path: "C:/films/first.mkv", size: 10, creationStamp: 1, modifiedStamp: 2}
    let second  = ExplorerEntry{path: "C:/films/second.mkv", size: 20, creationStamp: 3, modifiedStamp: 4}
    let musicId = "48140466-cff6-3222-bd55-63c27e43190d"
    setMusicChoice(&window.musicChoices, &second, musicId)
    let musicSettings = expect ThumbnailSettings.decode(ThumbnailSettings.capture(window, &second))
    Swag.require(musicSettings.musicId == musicId)
    Swag.require((expect ThumbnailSettings.decode(ThumbnailSettings.capture(window, &first))).musicId.isEmpty())

    var file: File.FileInfo
    file.size = 10
    var selected = ThumbnailSettings{choiceSize: file.size, choiceCreationStamp: Hash.hash64(file.creationTime),
                                     choiceModifiedStamp: Hash.hash64(file.lastWriteTime)}
    Swag.require(selected.choiceMatches(&file))
    file.size += 1
    Swag.require(not selected.choiceMatches(&file))
}
