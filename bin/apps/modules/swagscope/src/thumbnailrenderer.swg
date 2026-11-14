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
    bodyFont:  *Font?
    titleFont: *Font?
}

impl ThumbnailRenderer
{
    func create()->ThumbnailRenderer fail
    {
        var face: *TypeFace?
        for name in ["Segoe UI", "Noto Sans", "DejaVu Sans", "Liberation Sans", "Arial"]
        {
            let family = FontFamily.findSystemFont(name)
            if family.name.isEmpty() do
                continue
            face = catch FontFamily.createTypeFace(family, .Regular)
            if face do
                break
        }
        if not face do
            fail Errors.InvalidFormatError{"a system font is unavailable"}

        // The renderer owns the font cache, so the fonts outlive the canvas moving in.
        var canvas = try ImageCanvas.create(ThumbnailWidth, ThumbnailHeight)
        let fonts  = canvas.painter.renderer().fontCache()
        let body   = fonts.createFont(face, 12, .Bitmap, false)
        let title  = fonts.createFont(face, 13, .Bitmap, true)
        return {canvas: #move canvas, bodyFont: body, titleFont: title}
    }

    // Renders a bounded text sample or neutral file facts into the same portrait page.
    mtd render(path, viewerName: string, textual: bool)->Image fail
    {
        let painter = &.canvas.painter
        .canvas.clear(Color.fromRgb(238, 239, 240))
        painter.fillRect({8, 8, 240, 304}, Color.fromRgb(255, 255, 255))
        painter.fillRect({8, 8, 240, 3}, Color.fromRgb(53, 122, 186))
        painter.drawString(18, 20, viewerName, unwrap .titleFont, Color.fromRgb(66, 72, 78))
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
                var format:  RichStringFormat
                format.font.regular  = unwrap .bodyFont
                format.palette       = [Color.fromRgb(52, 57, 62), Color.fromRgb(52, 57, 62), Color.fromRgb(52, 57, 62), Color.fromRgb(52, 57, 62)]
                format.colorUrl      = Color.fromRgb(36, 112, 176)
                format.colorHotUrl   = format.colorUrl
                format.lineGap       = 3
                format.minLineHeight = .bodyFont.height + 3
                format.maxLines      = ThumbnailTextLines
                format.flags         = .WordWrap | .Clip
                painter.drawRichString({18, 48, 220, 250}, &content, format)
            }
        }
        else
        {
            let info = try File.info(path)
            var name = String.from(Path.fileName(path) orelse path)
            name.replace('<', "‹")
            name.replace('>', "›")
            var content: RichString = Format.toString("%\n%", name, StrConv.toDisplaySize(info.size))
            var format:  RichStringFormat
            format.font.regular  = unwrap .bodyFont
            format.palette       = [Color.fromRgb(52, 57, 62), Color.fromRgb(52, 57, 62), Color.fromRgb(52, 57, 62), Color.fromRgb(52, 57, 62)]
            format.minLineHeight = .bodyFont.height + 3
            format.maxLines      = 5
            format.flags         = .WordWrap | .Clip
            painter.drawRichString({18, 50, 220, 120}, &content, format)
        }

        return try .canvas.toImage()
    }

    mtd readText(path: string)->String fail
    {
        var stream = try File.openReadLive(path)
        return try stream.readUtf8Chunk(ThumbnailSourceSize)
    }

}
