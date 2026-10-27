#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

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
    let source = Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas", "comprehensive.md")
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
    Swag.assert(explorer.generation == generation and explorer.cached.count == 1)
    Swag.assert(explorer.entries[0].attempted and explorer.entries[0].texture.isValid())
    Swag.assert(explorer.previewSettings == originalSettings)
    Swag.assert(originalKey == (expect ThumbnailCache.key(source, settings: explorer.previewSettings)))
    Swag.assert(ThumbnailSettings.capture(window) == explorer.previewSettings)

    window.preferences.add(ViewerPreference{"markdown", "text"})
    explorer.refreshPreviewSettings()
    let transferred = expect ThumbnailSettings.decode(explorer.previewSettings)
    Swag.assert(not transferred.usesDefaultViewer("markdown"))
    Swag.assert(explorer.generation == generation + 1 and explorer.cached.isEmpty())
    Swag.assert(not explorer.entries[0].attempted and not explorer.entries[0].texture.isValid())
    Swag.assert(originalKey != (expect ThumbnailCache.key(source, settings: explorer.previewSettings)))
}
