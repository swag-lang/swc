//! Format: Windows Bitmap (BMP) encoder component.
//! Supported: Uncompressed 24- and 32-bit RGB/BGR source images with four-byte row alignment.
//! Not supported: Paletted, RLE, bitfield, and embedded-compression output.
//! Role: This file owns container header emission, validation, encoder registration, and top-level pixel dispatch.
//
#global namespace Bmp

using Core, Core.Errors

// Configures the BMP container around the encoded pixels.
public struct EncodeOptions
{
    // Includes the BMP file header by default. Disable it for a packed DIB, such as CF_DIB.
    public fileHeader = true
}

// Encodes 24-bit or 32-bit uncompressed Windows BMP images.
internal struct Encoder {}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"BMP - Windows Bitmap", ".bmp"}

    mtd impl encode(result: *ConcatBuffer, image: Image, options: any?) fail
    {
        var userOptions: EncodeOptions
        if options.buffer != null
        {
            if Swag.kindOf(options) != EncodeOptions do
                fail BadParameterError{"BMP encoder options must be Bmp.EncodeOptions"}
            userOptions = cast(const *EncodeOptions, unwrap options.buffer)[]
        }

        if image.width <= 0 or image.height <= 0 or not image.pixels.buffer do
            fail InvalidFormatError{"invalid image"}
        if image.pixelFormat != .BGR8 and
           image.pixelFormat != .BGRA8 and
           image.pixelFormat != .RGB8 and
           image.pixelFormat != .RGBA8 do
            fail UnsupportedFormatError{"BMP encoding accepts only 8-bit RGB and BGR pixels"}
        if image.width > Swag.S32.Max / image.bytesPerPixel or image.height > Swag.S32.Max / image.width do
            fail UnsupportedFormatError{"image is too big"}

        let rowBytes  = cast(u64, image.width) * image.bytesPerPixel
        let stride    = rowStride(image.width, image.bitsPerPixel)
        let imageSize = stride * cast(u64, image.height)
        let fileSize  = (userOptions.fileHeader ? cast(u64, #sizeof(FileHeader)) : 0) + #sizeof(Header) + imageSize
        if fileSize > Swag.U32.Max do
            fail UnsupportedFormatError{"image is too big"}

        result.grow(fileSize)

        if userOptions.fileHeader
        {
            with var fileHeader: FileHeader
            {
                .bfType    = 0x4D42
                .bfSize    = cast(u32, fileSize)
                .bfOffBits = #sizeof(FileHeader) + #sizeof(Header)
            }

            result.addStruct(fileHeader)
        }

        with var header: Header
        {
            .biSize        = #sizeof(Header)
            .biWidth       = image.width
            .biHeight      = image.height
            .biPlanes      = 1
            .biBitCount    = image.bitsPerPixel
            .biCompression = BI_RGB
            .biSizeImage   = cast(u32, imageSize)
        }

        result.addStruct(header)

        let target  = result.reserveInPlace(imageSize)
        let source  = image.pixels.storage()
        let padding = stride - rowBytes
        if not padding and (image.pixelFormat == .BGR8 or image.pixelFormat == .BGRA8)
        {
            Memory.copy(target, source, imageSize)
            return
        }

        for y in image.height
        {
            let src = source + cast(u64, y) * rowBytes
            let dst = target + cast(u64, y) * stride
            switch image.pixelFormat
            {
            case .RGB8:         PackedPixel.swapRedBlue24Row(src, dst, image.width)
            case .RGBA8:        PackedPixel.swapRedBlue32Row(src, dst, image.width)
            case .BGR8, .BGRA8: Memory.copy(dst, src, rowBytes)
            default:            unreachable
            }

            if padding do
                Memory.set(dst + rowBytes, 0, padding)
        }
    }
}
