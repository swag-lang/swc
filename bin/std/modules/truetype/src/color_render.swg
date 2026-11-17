using Swag, Core

func compositeColorGlyphPixel(dst: [*] u8, color: u32, coverage: u8)
{
    let sourceAlpha = (((color >> 24) & 255) * cast(u32, coverage) + 127) / 255
    if not sourceAlpha do
        return

    let destinationAlpha = cast(u32, dst[3])
    let outputAlpha      = sourceAlpha + (destinationAlpha * (255 - sourceAlpha) + 127) / 255
    let sourceRed        = (color >> 16) & 255
    let sourceGreen      = (color >> 8) & 255
    let sourceBlue       = color & 255

    let red = ((sourceRed * sourceAlpha +
                (cast(u32, dst[0]) * destinationAlpha * (255 - sourceAlpha) + 127) / 255) + outputAlpha / 2) / outputAlpha
    let green = ((sourceGreen * sourceAlpha +
                  (cast(u32, dst[1]) * destinationAlpha * (255 - sourceAlpha) + 127) / 255) + outputAlpha / 2) / outputAlpha
    let blue = ((sourceBlue * sourceAlpha +
                 (cast(u32, dst[2]) * destinationAlpha * (255 - sourceAlpha) + 127) / 255) + outputAlpha / 2) / outputAlpha

    dst[0] = cast(u8, red)
    dst[1] = cast(u8, green)
    dst[2] = cast(u8, blue)
    dst[3] = cast(u8, outputAlpha)
}

func renderColorGlyph(face: *Face, baseGlyph: u32, paletteIndex: u16, foregroundArgb: u32) fail
{
    let faceData = try getFaceImpl(face)
    let layers   = try readColorGlyphLayers(faceData, baseGlyph, paletteIndex)
    if layers.isEmpty() do
        try fault(0x12)

    // First find the union of the positioned layer bitmaps. The existing rasterizer
    // owns one reusable grayscale buffer, so the second pass renders directly into
    // the separate color destination without retaining per-layer copies.
    var hasBounds = false
    var left      = 0
    var right     = 0
    var top       = 0
    var bottom    = 0
    for layer in layers
    {
        try loadGlyphInternal(face, layer.glyphIndex)
        try renderCurrentOutline(&face.glyph)
        let bitmap = face.glyph.bitmap
        if not bitmap.width or not bitmap.rows do
            continue

        let layerLeft   = face.glyph.bitmapLeft
        let layerRight  = layerLeft + cast(s32, bitmap.width)
        let layerTop    = face.glyph.bitmapTop
        let layerBottom = layerTop - cast(s32, bitmap.rows)
        if not hasBounds
        {
            left      = layerLeft
            right     = layerRight
            top       = layerTop
            bottom    = layerBottom
            hasBounds = true
        }
        else
        {
            left   = Math.min(left, layerLeft)
            right  = Math.max(right, layerRight)
            top    = Math.max(top, layerTop)
            bottom = Math.min(bottom, layerBottom)
        }
    }

    try loadGlyphInternal(face, baseGlyph)
    if not hasBounds
    {
        face.glyph.setBitmap(0, 0, 0, null, .ColorRgba, 0, 0)
        return
    }

    let width = cast(u32, right - left)
    let rows  = cast(u32, top - bottom)
    if width > cast(u32, Swag.S32.Max / 4) do
        try fault(0x0A)
    if cast(u64, width) * rows > Swag.U64.Max / 4 do
        try fault(0x0A)

    let byteCount = cast(u64, width) * rows * 4
    faceData.colorBitmapPixels.resize(byteCount)
    let output = faceData.colorBitmapPixels.storage()
    Memory.clear(output, byteCount)

    for layer in layers
    {
        try loadGlyphInternal(face, layer.glyphIndex)
        try renderCurrentOutline(&face.glyph)
        let bitmap = face.glyph.bitmap
        if not bitmap.width or not bitmap.rows do
            continue

        let color   = layer.hasColor ? layer.argb : foregroundArgb
        let offsetX = cast(u32, face.glyph.bitmapLeft - left)
        let offsetY = cast(u32, top - face.glyph.bitmapTop)
        for row in bitmap.rows
        {
            let coverage = try bitmap.row(row)
            let dstRow   = (cast(u64, offsetY + row) * width + offsetX) * 4
            for column in bitmap.width do
                compositeColorGlyphPixel(output + dstRow + cast(u64, column) * 4, color, coverage[column])
        }
    }

    // Leave the base glyph's outline, index, and metrics active while publishing the
    // composite bitmap from its separate face-owned buffer.
    try loadGlyphInternal(face, baseGlyph)
    face.glyph.setBitmap(rows, width, cast(s32, width * 4), output, .ColorRgba, left, top)
}
