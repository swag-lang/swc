//! Format: Windows Bitmap (BMP) encoder component.
//! Supported: Uncompressed 24- and 32-bit RGB/BGR source images with four-byte row alignment.
//! Not supported: Paletted, RLE, bitfield, and embedded-compression output.
//! Role: This file owns container header emission, validation, encoder registration, and top-level pixel dispatch.
//
#global namespace Bmp

using Core, Core.Errors

// Encodes 24-bit or 32-bit uncompressed Windows BMP images.
internal struct Encoder {}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"BMP - Windows Bitmap", ".bmp"}

    mtd impl encode(result: *ConcatBuffer, image: Image, options: any?) fail
    {
        if image.width <= 0 or image.height <= 0 or !image.pixels.buffer do
            fail InvalidFormatError{"invalid image"}
        if image.width > Swag.S32.Max / image.bytesPerPixel or image.height > Swag.S32.Max / image.width do
            fail UnsupportedFormatError{"image is too big"}

        let rowBytes  = cast(u64) image.width * image.bytesPerPixel
        let stride    = rowStride(image.width, image.bitsPerPixel)
        let imageSize = stride * cast(u64) image.height
        let fileSize  = cast(u64) #sizeof(FileHeader) + #sizeof(Header) + imageSize
        if fileSize > Swag.U32.Max do
            fail UnsupportedFormatError{"image is too big"}

        var fileHeader: FileHeader
        fileHeader.bfType    = 0x4D42
        fileHeader.bfSize    = cast(u32) fileSize
        fileHeader.bfOffBits = #sizeof(FileHeader) + #sizeof(Header)
        result.addStruct(fileHeader)

        var header: Header
        header.biSize        = #sizeof(Header)
        header.biWidth       = image.width
        header.biHeight      = image.height
        header.biPlanes      = 1
        header.biBitCount    = image.bitsPerPixel
        header.biCompression = BI_RGB
        header.biSizeImage   = cast(u32) imageSize
        result.addStruct(header)

        if image.pixelFormat == .RGB8 or image.pixelFormat == .RGBA8
        {
            var converted: Array'u8
            converted.resize(imageSize)
            let src = image.pixels.buffer!
            for y in image.height
            {
                let srcRow = src + cast(u64) y * rowBytes
                let dstRow = converted.buffer! + cast(u64) y * stride
                if image.pixelFormat == .RGB8 do
                    PackedPixel.swapRedBlue24Row(srcRow, dstRow, image.width)
                else do
                    PackedPixel.swapRedBlue32Row(srcRow, dstRow, image.width)

                let padding = stride - rowBytes
                if padding do
                    Memory.set(dstRow + rowBytes, 0, padding)
            }

            result.addBytes(converted.toSlice())
            return
        }

        var psrc = image.pixels.buffer
        for image.height
        {
            switch image.pixelFormat
            {
            case .BGR8, .BGRA8:
                result.addBytes(Swag.makeSlice(psrc, rowBytes))
                psrc += rowBytes
            }

            let padding = stride - rowBytes
            if padding
            {
                for padding do
                    result.addNative(0'u8)
            }
        }
    }
}
