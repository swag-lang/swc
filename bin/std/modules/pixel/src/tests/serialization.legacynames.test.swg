#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Mirrors the field names 'Pixel.Image' was written under before they were spelled out.
// Only the names matter here: TagBin keys a field by the CRC of its name, so a stream
// produced from this struct is byte-compatible with an image saved by an older build.
struct LegacyImage
{
    pixels:    Array'u8
    metaDatas: Array'LegacyImageMetaData
    size:      u64
    width:     s32
    height:    s32
    width8:    s32
    pf:        PixelFormat
    bpp:       u8
    bpp8:      u8
}

struct LegacyImageMetaData
{
    sig:   u32
    tag:   Array'u8
    value: Array'u8
}

func makeLegacyImage()->LegacyImage
{
    var result: retval
    result.width  = 3
    result.height = 2
    result.width8 = 3 * 4
    result.pf     = .BGRA8
    result.bpp    = 32
    result.bpp8   = 4
    result.size   = cast(u64) (result.width8 * result.height)

    // A recognizable ramp, so a stride or format mistake shows up as wrong bytes rather
    // than as a plausible-looking image.
    for i in result.size do
        result.pixels.add(cast(u8) (i * 7))

    var meta: LegacyImageMetaData
    meta.sig = 0xCAFE
    meta.tag.add(cast(u8) 1)
    meta.value.add(cast(u8) 2)
    result.metaDatas.add(meta)
    return result
}

// An image saved under the previous field names still decodes. Renaming a serialized field
// without a 'Serialization.Alias' silently drops its value: the geometry survives because
// 'width' and 'height' kept their names, while stride, format and depth come back zero and
// the picture decodes to noise. That is what happened to every stored capture.
#test
{
    let legacy = makeLegacyImage()

    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    var buffer:  ConcatBuffer
    expect encoder.writeAll(&buffer, legacy)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'Image(buffer.toString().toSlice())!
    defer Memory.delete(decoded)

    Swag.assert(decoded.width == 3)
    Swag.assert(decoded.height == 2)
    Swag.assert(decoded.rowStride == 12)
    Swag.assert(decoded.pixelFormat == PixelFormat.BGRA8)
    Swag.assert(decoded.bitsPerPixel == 32)
    Swag.assert(decoded.bytesPerPixel == 4)
    Swag.assert(decoded.byteCount == 24)
    Swag.assert(decoded.isValid())

    for i in decoded.byteCount do
        Swag.assert(decoded.pixels.buffer![i] == cast(u8) (i * 7))

    Swag.assert(decoded.metadata.count == 1)
    Swag.assert(decoded.metadata[0].signature == 0xCAFE)
    Swag.assert(decoded.metadata[0].tag.count == 1)
    Swag.assert(decoded.metadata[0].value.count == 1)
}
