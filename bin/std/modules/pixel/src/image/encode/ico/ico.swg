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
    mtd impl encode(result: *ConcatBuffer, image: Image, _: any?) fail
    {
        try appendAll(result, Swag.makeSlice(&image, 1))
    }
}

// Encodes an icon holding every image, in the order given.
//
// An icon is picked by size at display time, so a favicon carrying 16, 32, and 48 pixel
// entries stays sharp in a tab, a bookmark, and a shortcut alike. Each image is written as a
// 32-bit BGRA entry whose alpha channel carries transparency. Every input image must use
// `RGB8`, `BGR8`, `RGBA8`, or `BGRA8`.
//
// ## Example
//
// ```swag
// let sizes: [3] Image = [mark16, mark32, mark48]
// try Ico.save("favicon.ico", sizes)
// ```
public func encodeAll(images: const [..] Image)->ConcatBuffer fail
{
    var result: #returntype
    try appendAll(&result, images)
    return result
}

private func appendAll(result: *ConcatBuffer, images: const [..] Image) fail
{
    if images.count == 0
    {
        fail InvalidFormatError{"an icon needs at least one image"}
    }

    if images.count > 0xFFFF
    {
        fail UnsupportedFormatError{"an icon holds at most 65535 images"}
    }

    let directoryBytes = cast(u64, #sizeof(IconDir)) + images.count * #sizeof(IconDirEntry)
    var bytes = directoryBytes
    for &image in images
    {
        if image.width <= 0 or
           image.height <= 0 or
           not image.isValid() or
           image.pixels.count != image.byteCount
        {
            fail InvalidFormatError{"invalid image"}
        }

        if image.width > 256 or image.height > 256
        {
            fail UnsupportedFormatError{"icon dimensions must be <= 256"}
        }

        if image.pixelFormat != .RGB8 and
           image.pixelFormat != .BGR8 and
           image.pixelFormat != .RGBA8 and
           image.pixelFormat != .BGRA8
        {
            fail UnsupportedFormatError{"ICO encoding only supports RGB8, BGR8, RGBA8, and BGRA8 images"}
        }
    }

    // All offsets are relative to this icon's header.
    let output  = result.reserveInPlace(bytes)
    let entries = cast([*] IconDirEntry, output + #sizeof(IconDir))

    // ICONDIR
    var dir: IconDir
    dir.reserved = 0
    dir.type     = 1
    dir.count    = cast(u16, images.count)
    cast([*] IconDir, output)[0] = dir

    var offset = directoryBytes
    var index  = 0_u64
    for &image in images
    {
        let dibBytes = dibSizeOf(image)

        with var entry: IconDirEntry
        {
            .width       = cast(u8, (image.width == 256 ? 0 : image.width))
            .height      = cast(u8, (image.height == 256 ? 0 : image.height))
            .colorCount  = 0
            .reserved    = 0
            .planes      = 1
            .bitCount    = 32
            .bytesInRes  = cast(u32, dibBytes)
            .imageOffset = cast(u32, offset)
        }

        entries[index] = entry
        let destination = output + offset
        writeDib(destination, image)

        offset += dibBytes
        index  += 1
    }
}

// Writes an icon file holding every image, in the order given.
//
// Every input image must use `RGB8`, `BGR8`, `RGBA8`, or `BGRA8`.
public func save(fileName: string, images: const [..] Image) fail
{
    let buffer = try encodeAll(images)
    discard try File.writeAllBytes(fileName, buffer)
}

// Total size of the DIB written for one image.
private func dibSizeOf(image: Image)->u64
{
    let xorStride = cast(u64, image.width) * 4
    let andStride = rowStride32(cast(u64, image.width))
    return cast(u64, #sizeof(DibHeader)) + xorStride * cast(u64, image.height) + andStride * cast(u64, image.height)
}

// Expands a packed RGB or BGR image to opaque BGRA.
private func expandIconPixels(source: const [*] u8, destination: [*] u8, count: u64, swapRedBlue: bool)
{
    const Keep = cast(Math.Simd.U8x16, [0_u8, 1, 2, 128, 3, 4, 5, 128, 6, 7, 8, 128, 9, 10, 11, 128])
    const Swap = cast(Math.Simd.U8x16, [2_u8, 1, 0, 128, 5, 4, 3, 128, 8, 7, 6, 128, 11, 10, 9, 128])
    let shuffle = swapRedBlue ? Swap : Keep
    let alpha   = cast #bit(Math.Simd.U8x16, Math.Simd.splat(0xFF000000_u32))
    var index   = 0_u64

    // Four output pixels use 12 source bytes, but the load reads a full vector.
    while count - index >= 6
    {
        let colors = Math.Simd.load(source + index * 3)
        let packed = Math.Simd.shuffle(colors, shuffle) | alpha
        Math.Simd.store(destination + index * 4, packed)
        index += 4
    }

    let blue = swapRedBlue ? 2 : 0
    let red  = 2 - blue
    for i in index until count
    {
        let input  = source + i * 3
        let output = destination + i * 4
        output[0] = input[blue]
        output[1] = input[1]
        output[2] = input[red]
        output[3] = 255
    }
}

private func writeDib(destination: [*] u8, image: Image)
{
    let count    = cast(u64, image.width) * image.height
    let xorBytes = count * 4
    let andBytes = rowStride32(cast(u64, image.width)) * image.height

    // The DIB's height includes the AND mask.
    var dib: DibHeader
    dib.size      = #sizeof(DibHeader)
    dib.width     = image.width
    dib.height    = image.height * 2
    dib.planes    = 1
    dib.bitCount  = 32
    dib.sizeImage = cast(u32, xorBytes)
    cast([*] DibHeader, destination)[0] = dib

    // The image already stores tightly packed bottom-up rows.
    let pixels = destination + #sizeof(DibHeader)
    let source = image.pixels.storage()
    if image.alphaMode == .Premultiplied
    {
        PackedPixel.writeStraightAlpha8(source, pixels, count, image.pixelFormat == .RGBA8)
    }
    else
    {
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
                result.addNative(255_u8)
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
                result.addNative(255_u8)
                psrc += 3
            }

        default:
            break
        }
    }

    // AND (transparency) mask, fully opaque
    for andBytes
    {
        result.addNative(0_u8)
    }
}
