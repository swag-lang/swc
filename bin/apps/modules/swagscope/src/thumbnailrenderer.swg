#global internal

using Core, Pixel

private const ThumbnailWidth      = 256
private const ThumbnailHeight     = 320
private const ThumbnailSourceSize = 16 * 1024'u64
private const ThumbnailTextLines  = 18

// Produces a compact source preview without constructing a viewer or a window.
struct ThumbnailRenderer
{
    canvas:    ImageCanvas
    bodyFont:  *Font
    titleFont: *Font
}

impl ThumbnailRenderer
{
    func create()->ThumbnailRenderer fail
    {
        let family = FontFamily.findSystemFont("Segoe UI")
        if family.name.isEmpty() do
            fail Errors.InvalidFormatError{"a system font is unavailable"}

        let face = try FontFamily.createTypeFace(family, .Regular)
        if not face do
            fail Errors.InvalidFormatError{"a system font is unavailable"}

        var result: retval
        result.canvas = try ImageCanvas.create(ThumbnailWidth, ThumbnailHeight)
        let fonts = result.canvas.painter.renderer().fontCache()
        result.bodyFont  = fonts.createFont(face, 12, .Bitmap, false)
        result.titleFont = fonts.createFont(face, 13, .Bitmap, true)
        return result
    }

    // Renders a bounded text sample or a compact byte map into the same portrait page.
    mtd render(path, viewerName: string, textual: bool)->Image fail
    {
        let painter = &.canvas.painter
        .canvas.clear(Color.fromRgb(238, 239, 240))
        painter.fillRect({8, 8, 240, 304}, Color.fromRgb(255, 255, 255))
        painter.fillRect({8, 8, 240, 3}, Color.fromRgb(53, 122, 186))
        painter.drawString(18, 20, viewerName, .titleFont, Color.fromRgb(66, 72, 78))
        painter.fillRect({18, 38, 220, 1}, Color.fromRgb(224, 226, 228))

        if textual
        {
            var source = catch .readText(path)
            if source.count
            {
                // RichString uses angle brackets as its own small formatting language.
                source.replace('<', "‹")
                source.replace('>', "›")
                var content: RichString = #move source
                var format: RichStringFormat
                format.font.regular  = .bodyFont
                format.palette       = [Color.fromRgb(52, 57, 62), Color.fromRgb(52, 57, 62), Color.fromRgb(52, 57, 62), Color.fromRgb(52, 57, 62)]
                format.colorUrl      = Color.fromRgb(36, 112, 176)
                format.colorHotUrl   = format.colorUrl
                format.lineGap       = 3
                format.minLineHeight  = .bodyFont.height + 3
                format.maxLines       = ThumbnailTextLines
                format.flags          = .WordWrap | .Clip
                painter.drawRichString({18, 48, 220, 250}, &content, format)
            }
        }
        else
        {
            try .drawByteMap(path, painter)
        }

        return try .canvas.toImage()
    }

    mtd readText(path: string)->String fail
    {
        var stream = try File.openReadLive(path)
        return try stream.readUtf8Chunk(ThumbnailSourceSize)
    }

    private mtd drawByteMap(path: string, painter: *Painter) fail
    {
        var stream = try File.openReadLive(path)
        var bytes: Array'u8
        bytes.resize(32 * 64)
        let count = try stream.read(bytes.toSlice())
        bytes.resize(count)

        for byte, index in bytes
        {
            let value = cast(u32, byte)
            let x     = 18 + cast(f32, index % 32) * 6.8
            let y     = 50 + cast(f32, index / 32) * 3.8
            let color = Color.fromRgb(cast(u8, 24 + value / 8),
                                      cast(u8, 48 + value / 5),
                                      cast(u8, 78 + value / 3))
            painter.fillRect({x, y, 5.2, 2.8}, color)
        }
    }
}
