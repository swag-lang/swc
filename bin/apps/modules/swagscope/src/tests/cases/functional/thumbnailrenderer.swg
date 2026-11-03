#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Gui.Testing, Viewers

private func thumbnailFixture(name: string)->String => Path.combine(testSourceRoot(#curlocation), "datas", name)

// The isolated worker renders subtitle content and can reuse that process for a video frame.
#test
{
    let file = Testing.tempFilePath("scope-subtitle-preview-", ".vtt")
    defer catch File.delete(file)
    discard expect File.writeAllText(file, "WEBVTT\n\n00:00.000 --> 00:01.000\nVisible subtitle words\n")
    var service: ThumbnailService
    var buffer:  ConcatBuffer
    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    expect encoder.writeAll(&buffer, ThumbnailSettings{localArtworkOnly: true})
    let subtitle = expect service.render(file, buffer.toString())
    Swag.require(subtitle.width == 256 and subtitle.height == 320)
    let video = expect service.render(thumbnailFixture("glint-aac-mjpeg.mp4"), buffer.toString())
    Swag.require(video.isValid())
}

// Both source paths render without creating a GUI application or a viewer window.
#test
{
    var renderer = expect ThumbnailRenderer.create()
    let markdown = expect renderer.render(thumbnailFixture("markdown.images.md"), "Markdown", true)
    Swag.require(markdown.width == 256 and markdown.height == 320)
    Swag.require(markdown.pixelColor(0, 0).argb == Color.fromRgb(238, 239, 240).argb)
    Swag.require(markdown.pixelColor(245, 310).argb == Color.fromRgb(255, 255, 255).argb)

    let binary = expect renderer.render(thumbnailFixture("viewer.pdf"), "PDF", false)
    Swag.require(binary.width == 256 and binary.height == 320)
    Swag.require(binary.pixelColor(18, 50).argb != Color.fromRgb(255, 255, 255).argb)

    let repeated = expect renderer.render(thumbnailFixture("markdown.images.md"), "Markdown", true)
    Swag.require(repeated.width == markdown.width and repeated.height == markdown.height)
    Swag.require(repeated.pixelColor(0, 0).argb == markdown.pixelColor(0, 0).argb)
}

// Plugin decoders and the shared source renderer both bypass viewer construction.
#test
{
    var renderer = expect ThumbnailRenderer.create()
    let registry = createViewerPluginRegistry()
    var settings: ThumbnailSettings

    let markdown = expect renderThumbnail(&registry, &renderer, &settings, thumbnailFixture("markdown.images.md"))
    Swag.require(markdown.width == 256 and markdown.height == 320)

    let pdf = expect renderThumbnail(&registry, &renderer, &settings, thumbnailFixture("viewer.pdf"))
    Swag.require(pdf.width == 256 and pdf.height == 320)

    let image = expect renderThumbnail(&registry, &renderer, &settings, thumbnailFixture("sample.svg"))
    Swag.require(image.isValid())

    let video = expect renderThumbnail(&registry, &renderer, &settings, thumbnailFixture("glint-aac-mjpeg.mp4"))
    Swag.require(video.isValid())
}

// Large text documents contribute only the bounded source prefix to a thumbnail.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-thumbnail-bounded-", ".md")
    defer discard catch File.delete(fileName)

    var source: String
    for 256 do
        source += "A repeated paragraph keeps the thumbnail input much larger than its preview budget.\n"
    discard expect File.writeAllText(fileName, source)

    var renderer = expect ThumbnailRenderer.create()
    let sample   = expect renderer.readText(fileName)
    Swag.require(source.count > 16 * 1024 and sample.count == 16 * 1024)
    let image = expect renderer.render(fileName, "Markdown", true)
    Swag.require(image.isValid())

    // The tail must not affect the result. Compare the same file truncated to its budget;
    // a wall-clock deadline here would fail when unrelated work delays the process.
    discard expect File.writeAllText(fileName, sample)
    let bounded = expect renderer.render(fileName, "Markdown", true)
    Swag.require(image.width == bounded.width and image.height == bounded.height)
    Swag.require(Slice.equals(image.pixels.toSlice(), bounded.pixels.toSlice()))
}
