#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Gui.Testing, Viewers

private func thumbnailFixture(name: string)->String => Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas", name)

// Both source paths render without creating a GUI application or a viewer window.
#test
{
    var renderer = expect ThumbnailRenderer.create()
    let markdown = expect renderer.render(thumbnailFixture("markdown.images.md"), "Markdown", true)
    Swag.assert(markdown.width == 256 and markdown.height == 320)
    Swag.assert(markdown.pixelColor(0, 0).argb == Color.fromRgb(238, 239, 240).argb)
    Swag.assert(markdown.pixelColor(245, 310).argb == Color.fromRgb(255, 255, 255).argb)

    let binary = expect renderer.render(thumbnailFixture("viewer.pdf"), "PDF", false)
    Swag.assert(binary.width == 256 and binary.height == 320)
    Swag.assert(binary.pixelColor(18, 50).argb != Color.fromRgb(255, 255, 255).argb)

    let repeated = expect renderer.render(thumbnailFixture("markdown.images.md"), "Markdown", true)
    Swag.assert(repeated.width == markdown.width and repeated.height == markdown.height)
    Swag.assert(repeated.pixelColor(0, 0).argb == markdown.pixelColor(0, 0).argb)
}

// Plugin decoders and the shared source renderer both bypass viewer construction.
#test
{
    var renderer = expect ThumbnailRenderer.create()
    let registry = createViewerPluginRegistry()
    var settings: ThumbnailSettings

    let markdown = expect renderThumbnail(&registry, &renderer, &settings, thumbnailFixture("markdown.images.md"))
    Swag.assert(markdown.width == 256 and markdown.height == 320)

    let pdf = expect renderThumbnail(&registry, &renderer, &settings, thumbnailFixture("viewer.pdf"))
    Swag.assert(pdf.width == 256 and pdf.height == 320)

    let image = expect renderThumbnail(&registry, &renderer, &settings, thumbnailFixture("sample.svg"))
    Swag.assert(image.isValid())

    let video = expect renderThumbnail(&registry, &renderer, &settings, thumbnailFixture("glint-aac-mjpeg.mp4"))
    Swag.assert(video.isValid())
}

// Large text documents contribute only the bounded source prefix to a thumbnail.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-thumbnail-bounded-", ".md")
    defer discard catch File.delete(fileName)

    var source: String
    for 2048 do
        source += "A repeated paragraph keeps the thumbnail input much larger than its preview budget.\n"
    discard expect File.writeAllText(fileName, source)

    var renderer = expect ThumbnailRenderer.create()
    let sample   = expect renderer.readText(fileName)
    Swag.assert(source.count > 16 * 1024 and sample.count == 16 * 1024)
    let started = Time.monotonicMicroseconds()
    let image   = expect renderer.render(fileName, "Markdown", true)
    let elapsed = Time.monotonicMicroseconds() - started
    Swag.assert(image.isValid() and elapsed < 1_000_000)
}
