//! Format: Windows icon (ICO) encoder component.
//! Supported: One or more images up to 256 by 256, stored as 32-bit BGRA DIB entries with alpha.
//! Not supported: CUR output, PNG-compressed entries, paletted entries, and dimensions above 256.
//! Role: This file owns container directory emission and embedded-image encoding.
//
#global namespace Ico

using Core, Core.Errors

// Encodes one image as a 32-bit Windows icon entry.
internal struct Encoder {}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"ICO - Windows Icon", ".ico"}

    // Encode a single image as a 32-bit BGRA DIB icon entry with an empty AND mask.
    // The alpha channel carries transparency; the AND mask is left fully opaque.
    mtd impl encode(result: *ConcatBuffer, image: Image, options: any?) fail
    {
        var single: [1] Image = [image]
        try appendAll(result, single)
    }
}

// Encodes an icon holding every image, in the order given.
//
// An icon is picked by size at display time, so a favicon carrying 16, 32, and 48 pixel
// entries stays sharp in a tab, a bookmark, and a shortcut alike. Each image is written as a
// 32-bit BGRA entry whose alpha channel carries transparency.
//
// ## Example
//
// ```swag
// let sizes: [3] Image = [mark16, mark32, mark48]
// try Ico.save("favicon.ico", sizes)
// ```
public func encodeAll(images: const [..] Image)->ConcatBuffer fail
{
    var result: retval
    try appendAll(&result, images)
    return result
}

private func appendAll(result: *ConcatBuffer, images: const [..] Image) fail
{
    if images.count == 0 do
        fail InvalidFormatError{"an icon needs at least one image"}
    if images.count > 0xFFFF do
        fail UnsupportedFormatError{"an icon holds at most 65535 images"}

    for &image in images
    {
        if image.width <= 0 or image.height <= 0 or !image.pixels.buffer do
            fail InvalidFormatError{"invalid image"}
        if image.width > 256 or image.height > 256 do
            fail UnsupportedFormatError{"icon dimensions must be <= 256"}
    }

    // ICONDIR
    var dir: IconDir
    dir.reserved = 0
    dir.type     = 1
    dir.count    = cast(u16) images.count
    result.addStruct(dir)

    // Every entry points at its own DIB, so the offsets are known before any pixel is written.
    var offset = cast(u32) (#sizeof(IconDir) + images.count * #sizeof(IconDirEntry))
    for &image in images
    {
        let dibBytes = dibSizeOf(image)

        var entry: IconDirEntry
        entry.width       = cast(u8) (image.width == 256 ? 0 : image.width)
        entry.height      = cast(u8) (image.height == 256 ? 0 : image.height)
        entry.colorCount  = 0
        entry.reserved    = 0
        entry.planes      = 1
        entry.bitCount    = 32
        entry.bytesInRes  = cast(u32) dibBytes
        entry.imageOffset = offset
        result.addStruct(entry)

        offset += cast(u32) dibBytes
    }

    for &image in images do
        appendDib(result, image)
}

// Writes an icon file holding every image, in the order given.
public func save(fileName: string, images: const [..] Image) fail
{
    let buffer = try encodeAll(images)
    discard try File.writeAllBytes(fileName, buffer)
}

// Total size of the DIB written for one image.
private func dibSizeOf(image: Image)->u64
{
    let xorStride = cast(u64) image.width * 4
    let andStride = (((cast(u64) image.width) + 31) / 32) * 4
    return cast(u64) #sizeof(DibHeader) + xorStride * cast(u64) image.height + andStride * cast(u64) image.height
}

private func appendDib(result: *ConcatBuffer, image: Image)
{
    let width  = image.width
    let height = image.height

    let xorStride = cast(u64) width * 4
    let andStride = (((cast(u64) width) + 31) / 32) * 4
    let xorBytes  = xorStride * cast(u64) height
    let andBytes  = andStride * cast(u64) height

    // BITMAPINFOHEADER (height is doubled to account for the AND mask)
    var dib: DibHeader
    dib.size      = #sizeof(DibHeader)
    dib.width     = width
    dib.height    = height * 2
    dib.planes    = 1
    dib.bitCount  = 32
    dib.sizeImage = cast(u32) xorBytes
    result.addStruct(dib)

    // XOR (color) data, bottom-up BGRA - matches the internal buffer convention
    for y in height
    {
        var psrc = image.pixels.buffer! + cast(u64) y * image.rowStride

        switch image.pixelFormat
        {
        case .BGRA8:
            result.addBytes(Swag.makeSlice(psrc, xorStride))

        case .BGR8:
            for width
            {
                result.addNative(psrc[0])
                result.addNative(psrc[1])
                result.addNative(psrc[2])
                result.addNative(255'u8)
                psrc += 3
            }

        case .RGBA8:
            for width
            {
                result.addNative(psrc[2])
                result.addNative(psrc[1])
                result.addNative(psrc[0])
                result.addNative(psrc[3])
                psrc += 4
            }

        case .RGB8:
            for width
            {
                result.addNative(psrc[2])
                result.addNative(psrc[1])
                result.addNative(psrc[0])
                result.addNative(255'u8)
                psrc += 3
            }
        }
    }

    // AND (transparency) mask, fully opaque
    for andBytes do
        result.addNative(0'u8)
}
