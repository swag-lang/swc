using Core, Pixel, Gui

// Small attention projections travel with cached pixels; choosing a crop needs no texture readback.
struct ThumbnailFraming
{
    horizontal: [32] u8
    vertical:   [32] u8
}

impl ThumbnailFraming
{
    private const HorizontalTag = "scope.thumbnail.attention.x"
    private const VerticalTag   = "scope.thumbnail.attention.y"

    func analyze(image: const *Image)->ThumbnailFraming
    {
        var columns, rows: [32] f32
        for y in 32
        {
            for x in 32
            {
                let px         = cast(s32, x) * (image.width - 1) / 31
                let py         = cast(s32, y) * (image.height - 1) / 31
                let color      = image.pixelColor(px, py)
                let right      = image.pixelColor(Math.min(px + Math.max(image.width / 64, 1), image.width - 1), py)
                let down       = image.pixelColor(px, Math.min(py + Math.max(image.height / 64, 1), image.height - 1))
                let light      = luma(color)
                let edge       = Math.abs(light - luma(right)) + Math.abs(light - luma(down))
                let saturation = cast(f32, Math.max(color.r, Math.max(color.g, color.b)) - Math.min(color.r, Math.min(color.g, color.b)))
                let skin       = color.r > 80 and
                                 color.g > 40 and
                                 color.b > 20 and
                                 color.r > color.g and
                                 color.r > color.b and
                                 saturation > 15
                let weight = light < 12 ? 0 : (edge + saturation * 0.25 + (skin ? 32 : 0)) * cast(f32, color.a) / 255
                columns[x] += weight
                rows[y]    += weight
            }
        }

        var columnMax: f32 = 1
        var rowMax:    f32 = 1
        for index in 32
        {
            columnMax = Math.max(columnMax, columns[index])
            rowMax    = Math.max(rowMax, rows[index])
        }

        var result: #returntype
        for index in 32
        {
            result.horizontal[index] = cast(u8, columns[index] * 255 / columnMax)
            result.vertical[index]   = cast(u8, rows[index] * 255 / rowMax)
        }

        return result
    }

    #[Swag.Inline]
    private func luma(color: Color)->f32 =>
        (cast(f32, color.r) * 77 + cast(f32, color.g) * 150 + cast(f32, color.b) * 29) / 256

    mtd const label(image: *Image)
    {
        for axis in 2
        {
            var record: ImageMetadata
            record.tag = axis == 0 ? HorizontalTag : VerticalTag
            var text: String
            for index in 32 do
                text += Format.toString("%{X02}", axis == 0 ? .horizontal[index] : .vertical[index])
            record.value = text.toString()
            image.metadata.add(#move record)
        }
    }

    func fromImage(image: const *Image)->ThumbnailFraming
    {
        func digit(value: u8)->u8 => value <= '9' ? value - '0'u8 : value - 'A'u8 + 10

        var result: #returntype
        for &record in image.metadata
        {
            let horizontal = record.isTag(cast(const [..] u8, HorizontalTag))
            if not horizontal and not record.isTag(cast(const [..] u8, VerticalTag)) do
                continue
            let text = cast(string, record.toSlice())
            if text.count != 64 do
                continue
            var valid = true
            for byte in text where not Latin1.isDigit(byte) and (byte < 'A' or byte > 'F') do
                valid = false
            if not valid do
                continue
            for index in 32
            {
                let weight = digit(text[index * 2]) * 16 + digit(text[index * 2 + 1])
                if horizontal do
                    result.horizontal[index] = weight
                else do
                    result.vertical[index] = weight
            }
        }

        return result
    }

    // Search each axis for the most informative cover window, with a small stability bias to centre.
    private func bestOffset(weights: const [..] u8, span: f32)->f32
    {
        var prefix: [33] f32
        for index in 32 do
            prefix[index + 1] = prefix[index] + cast(f32, weights[index])

        let integral = func|&prefix, weights|(position: f32)->f32
        {
            let index = cast(u64, position)
            if index >= 32 do
                return prefix[32]
            return prefix[index] + (position - cast(f32, index)) * cast(f32, weights[index])
        }

        let centre = (1 - span) * 0.5
        var best   = centre
        var score  = -Swag.F32.Max
        for step in 129
        {
            let offset    = cast(f32, step) * (1 - span) / 128
            let attention = integral((offset + span) * 32) - integral(offset * 32)
            let candidate = attention - prefix[32] * Math.abs(offset - centre) * 0.02
            if candidate > score
            {
                score = candidate
                best  = offset
            }
        }

        return prefix[32] > 0 ? best : centre
    }

    mtd const crop(width, height, aspect: f32)->Math.Rectangle
    {
        let sourceAspect = width / height
        if aspect < sourceAspect
        {
            let span = aspect / sourceAspect
            return {bestOffset(.horizontal, span) * width, 0, span * width, height}
        }

        let span = sourceAspect / aspect
        return {0, bestOffset(.vertical, span) * height, width, span * height}
    }

    mtd const paint(host: *Wnd, painter: *Painter, texture: Texture, tile: Math.Rectangle)
    {
        var brush = Brush.createTexture(texture)
        brush.uvMode = .FillSubRect
        brush.uvRect = .crop(cast(f32, texture.width), cast(f32, texture.height), tile.width / tile.height)
        let radius = host.themeMetrics().corner_Control
        painter.fillRoundRect(tile, radius, radius, brush)
    }
}
