#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// The asynchronous cache uses the native renderer after parsing, preserving transparency
// and supersampling while a DPI change made during parsing selects the final raster size.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    const Source = "<svg width='120' height='60'><rect x='4' y='4' width='80' height='40' fill='#285078'/><rect x='40' y='20' width='70' height='30' fill='#E06030' opacity='.5'/></svg>"
    let fileName = Testing.tempFilePath("markdown-image-gpu-", ".svg")
    discard expect File.writeAllText(fileName, Source)
    defer discard catch File.delete(fileName)
    var window  = expect Env.createWindow({identifier: "markdown-image-test", title: "Markdown image test", width: 240, height: 120})
    var backend:  RenderOgl
    let renderer: IRenderer = &backend
    var context = expect renderer.createContext(window.nativeRenderHandle(), 240, 120)
    defer renderer.deleteContext(&context)
    renderer.setCurrentContext(context)
    renderer.init()

    var cache: HtmlImageCache
    cache.asynchronous = true
    let pending = cache.texture(renderer, fileName.toString(), 120, 60)
    Swag.assert(pending == null and not cache.parsing.isEmpty())
    cache.parsing[0].task.wait()
    Swag.assert(not cache.entries[0].image.isValid())
    let ready = cache.texture(renderer, fileName.toString(), 240, 120)
    Swag.assert(ready != null and cache.entries[0].image.width == 240)
    let drawing  = expect Svg.Drawing.parse(Source)
    let expected = drawing.rasterize(240, 120)

    // The two backends round supersampled translucent colors within two channel levels.
    Pixel.Testing.assertImagesNear(&expected, &cache.entries[0].image, "markdownview.images.ogl", {maxChannelDelta: 2})
}
