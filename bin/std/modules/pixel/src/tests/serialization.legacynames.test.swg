#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Uses different source field names with the same stable keys as 'Pixel.Image'. This
// simulates a source rename without adding a second accepted wire name.
#[Serialization.Schema("pixel.image")]
struct LegacyImage
{
    pixels:    Array'u8

    #[Serialization.Key("metadata")]
    metaDatas: Array'LegacyImageMetaData

    #[Serialization.Key("byteCount")]
    size:      u64
    width:     s32
    height:    s32

    #[Serialization.Key("rowStride")]
    width8:    s32

    #[Serialization.Key("pixelFormat")]
    pf:        PixelFormat

    #[Serialization.Key("bitsPerPixel")]
    bpp:       u8

    #[Serialization.Key("bytesPerPixel")]
    bpp8:      u8
}

struct LegacyImageMetaData
{
    #[Serialization.Key("signature")]
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

// Stable field keys preserve every image invariant across source-level field renames.
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
