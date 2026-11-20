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
    mtd render(path: string)->Image fail
    {
        if not .ready
        {
            .registry = createViewerPluginRegistry()
            .ready    = true
        }

        var image   = try renderThumbnail(&.registry, &.renderer, path)
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
                     path: string)->Image fail
{
    var pluginIndex: u64
    let knownPlugin = registry.namePlugin(path, &pluginIndex)
    if knownPlugin and registry.plugins[pluginIndex].thumbnail
    {
        let image = try registry.plugins[pluginIndex].thumbnail!(path, ThumbnailMaxSize)
        if image.isValid() do
            return image
    }

    let viewerName = knownPlugin ? registry.plugins[pluginIndex].staticName : "File"
    let textual    = knownPlugin and registry.plugins[pluginIndex].textual
    if not renderer.bodyFont do
        renderer[] = try ThumbnailRenderer.create()
    return try renderer.render(path, viewerName, textual)
}
