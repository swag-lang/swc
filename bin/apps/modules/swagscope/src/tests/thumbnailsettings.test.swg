#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Presentation changes produce a new key, survive worker transfer, and retire uploaded previews.
#test
{
    let previousMarkdown  = MarkdownText.g_ViewerSettings
    let previousMidi      = Midi.g_ViewerSettings
    let previousSubtitles = Film.g_SubtitleSettings
    defer MarkdownText.g_ViewerSettings = previousMarkdown
    defer Midi.g_ViewerSettings = previousMidi
    defer Film.g_SubtitleSettings = previousSubtitles
    var host: Testing.HeadlessHost
    host.setup(880, 560)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let explorer = Explorer.create(window.documentPanel, window)
    explorer.setMode(.Names)
    let source = Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas", "comprehensive.md")
    MarkdownText.g_ViewerSettings = {themeIndex: 1, widthIndex: 2, zoomPercent: 125}
    explorer.refreshPreviewSettings()
    let before = String.from(explorer.previewSettings)
    let oldKey = expect ThumbnailCache.key(source, settings: before)
    var image  = Image.create(8, 8, .RGB8)
    explorer.entries.add({name: "comprehensive.md", path: source, attempted: true,
                          texture: host.app.renderer.addImage(&image)})
    explorer.cached.add(0)
    let generation = explorer.generation
    explorer.previews[0].opening    = true
    explorer.previews[0].generation = generation
    explorer.previews[1].generation = generation
    MarkdownText.g_ViewerSettings.themeIndex = 5
    explorer.refreshPreviewSettings()
    Swag.assert(explorer.generation == generation + 1 and explorer.cached.isEmpty())
    Swag.assert(not explorer.entries[0].attempted and not explorer.entries[0].texture.isValid())
    Swag.assert(explorer.previews[0].generation == explorer.generation and
                explorer.previews[1].generation != explorer.generation)
    Swag.assert(oldKey != (expect ThumbnailCache.key(source, settings: explorer.previewSettings)))

    var transferred = expect ThumbnailSettings.decode(explorer.previewSettings)
    MarkdownText.g_ViewerSettings = {}
    transferred.apply(window)
    Swag.assert(MarkdownText.g_ViewerSettings.themeIndex == 5 and
                MarkdownText.g_ViewerSettings.widthIndex == 2 and
                MarkdownText.g_ViewerSettings.zoomPercent == 125)
    Swag.assert(ThumbnailSettings.capture(window) == explorer.previewSettings)
    let review = Env.variable("SWAG_SCOPE_REVIEW")
    if not review.isEmpty()
    {
        discard expect File.writeAllText(Path.combine(review, "thumbnail-markdown-before.settings"), before)
        discard expect File.writeAllText(Path.combine(review, "thumbnail-markdown-whitey.settings"), explorer.previewSettings)
    }

    explorer.refreshPreviewSettings()
    Swag.assert(explorer.generation == generation + 1)

    window.preferences.add({"markdown", "text"})
    explorer.refreshPreviewSettings()
    transferred = expect ThumbnailSettings.decode(explorer.previewSettings)
    Swag.assert(not transferred.usesDefaultViewer("markdown"))
    Swag.assert(explorer.generation == generation + 2)
}
