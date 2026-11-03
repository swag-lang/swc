#global internal

using Core, Pixel, Gui

private const ThumbnailMaxSize: u32 = 320

// One reusable renderer, owned and called by one Explorer background operation at a time.
struct ThumbnailService
{
    registry: ViewerPluginRegistry
    renderer: ThumbnailRenderer
    ready:    bool
}

impl ThumbnailService
{
    mtd render(path: string, settings: string = "")->Image fail
    {
        if not .ready
        {
            .registry = createViewerPluginRegistry()
            .renderer = try ThumbnailRenderer.create()
            .ready    = true
        }

        var options = try ThumbnailSettings.decode(settings)
        var image   = try renderThumbnail(&.registry, &.renderer, &options, path)
        let largest = Math.max(image.width, image.height)
        if largest > ThumbnailMaxSize
        {
            let scale = cast(f32, ThumbnailMaxSize) / cast(f32, largest)
            image.resize(Math.max(1, cast(s32, cast(f32, image.width) * scale)),
                         Math.max(1, cast(s32, cast(f32, image.height) * scale)),
                         .Bilinear)
        }

        return image
    }
}

// Uses a plugin decoder when it has one, otherwise renders a bounded source sample.
func renderThumbnail(registry: const *ViewerPluginRegistry,
                     renderer: *ThumbnailRenderer,
                     settings: *ThumbnailSettings,
                     path: string)->Image fail
{
    var pluginIndex: u64
    let knownPlugin = registry.namePlugin(path, &pluginIndex)
    if knownPlugin and
       registry.plugins[pluginIndex].thumbnail and
       settings.usesDefaultViewer(registry.plugins[pluginIndex].key)
    {
        return try registry.plugins[pluginIndex].thumbnail!(path, ThumbnailMaxSize)
    }

    let viewerName = knownPlugin ? registry.plugins[pluginIndex].staticName : "File"
    let textual    = knownPlugin and registry.plugins[pluginIndex].textual
    return try renderer.render(path, viewerName, textual)
}
