//! Format: Khronos Texture 2 encoder.
//! Supported: One uncompressed 2D level in every packed PixelFormat integer or float layout.
//! Not supported: Supercompression, block compression, mipmap generation, arrays, or cubemaps.
//! Role: This file writes a Vulkan-format KTX2 texture and its matching basic DFD.
//
#global namespace Ktx2

using Core, Core.Errors

internal struct Encoder {}

#[Swag.Inline]
private func writeU64(target: [*] u32, value: u64)
{
    target[0] = cast #wrap(u32, value)
    target[1] = cast(u32, (value >> 32))
}

func formatInfo(format: PixelFormat, vk: *u32, typeSize: *u32, channelIds: *[4] u8, floating: *bool)
{
    switch #complete format
    {
    case .Gray8:
        vk[] = 9

    case .GrayAlpha8:
        vk[] = 16
        channelIds[][1] = 15

    case .Gray16:
        vk[]       = 70
        typeSize[] = 2

    case .GrayAlpha16:
        vk[]            = 77
        typeSize[]      = 2
        channelIds[][1] = 15

    case .GrayF16:
        vk[]       = 76
        typeSize[] = 2
        floating[] = true

    case .GrayAlphaF16:
        vk[]            = 83
        typeSize[]      = 2
        floating[]      = true
        channelIds[][1] = 15

    case .GrayF32:
        vk[]       = 100
        typeSize[] = 4
        floating[] = true

    case .GrayAlphaF32:
        vk[]            = 103
        typeSize[]      = 4
        floating[]      = true
        channelIds[][1] = 15

    case .RGB8:
        vk[] = 23

    case .BGR8:
        vk[]         = 30
        channelIds[] = [2, 1, 0, 15]

    case .RGBA8:
        vk[] = 37
        channelIds[][3] = 15

    case .BGRA8:
        vk[]         = 44
        channelIds[] = [2, 1, 0, 15]

    case .RGB16:
        vk[]       = 84
        typeSize[] = 2

    case .RGBA16:
        vk[]            = 91
        typeSize[]      = 2
        channelIds[][3] = 15

    case .RGBF16:
        vk[]       = 90
        typeSize[] = 2
        floating[] = true

    case .RGBAF16:
        vk[]            = 97
        typeSize[]      = 2
        floating[]      = true
        channelIds[][3] = 15

    case .RGBF32:
        vk[]       = 106
        typeSize[] = 4
        floating[] = true

    case .RGBAF32:
        vk[]            = 109
        typeSize[]      = 4
        floating[]      = true
        channelIds[][3] = 15

    case .Yuv420, .Yuv444:
        unreachable
    }
}

func writeDfd(target: [*] u32, image: Image, typeSize: u32, channelIds: *[4] u8, floating: bool)
{
    let channels  = cast(u32, image.pixelFormat.channels())
    let blockSize = 24_u32 + channels * 16
    target[0] = blockSize + 4
    target[2] = (blockSize << 16) | 2     // KDF version 2.
    // RGBSDA model, BT.709 primaries and linear transfer.
    target[3] = 0x0001_0101 | (image.alphaMode == .Premultiplied ? 0x0100_0000 : 0)
    target[5] = image.bytesPerPixel

    let bits       = typeSize * 8
    let floatLower = typeSize == 2 ? 0xBC00_u32 : 0xBF800000_u32
    let floatUpper = typeSize == 2 ? 0x3C00_u32 : 0x3F800000_u32
    let lower      = floating ? floatLower : 0
    let upper      = floating ? floatUpper : ((1_u32 << bits) - 1)
    for channel in channels
    {
        let sample      = target + 7 + channel * 4
        let channelType = channelIds[][channel] | (floating ? 0x80 : 0)
        sample[0] = channel * bits | ((bits - 1) << 16) | (cast(u32, channelType) << 24)
        sample[2] = lower
        sample[3] = upper
    }
}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"KTX2 - Khronos Texture", ".ktx2"}

    mtd impl encode(result: *ConcatBuffer, image: Image, _: any?) fail
    {
        if not image.isValid() or not image.pixelFormat.isPacked()
        {
            fail InvalidFormatError{"invalid packed image"}
        }

        var vk:         u32
        var typeSize = 1_u32
        var channelIds: [4] u8 = [0, 1, 2, 3]
        var floating:   bool
        formatInfo(image.pixelFormat, &vk, &typeSize, &channelIds, &floating)
        let dfdLength  = 28_u64 + cast(u64, image.pixelFormat.channels()) * 16
        let dfdOffset  = HeaderSize + 24
        let alignment  = cast(u64, try Math.lcm(4, image.bytesPerPixel))
        let dataOffset = (dfdOffset + dfdLength + alignment - 1) / alignment * alignment

        result.grow(dataOffset + image.byteCount)
        let header = cast([*] u32, result.reserveInPlace(dataOffset))
        Memory.clear(header, dataOffset)
        Memory.copy(header, Identifier.buffer, Identifier.count)
        header[3]  = vk
        header[4]  = typeSize
        header[5]  = cast(u32, image.width)
        header[6]  = cast(u32, image.height)
        header[9]  = 1     // One face.
        header[10] = 1     // One level.
        header[12] = cast(u32, dfdOffset)
        header[13] = cast(u32, dfdLength)

        let level = header + HeaderSize / 4
        writeU64(level, dataOffset)
        writeU64(level + 2, image.byteCount)
        writeU64(level + 4, image.byteCount)
        writeDfd(header + dfdOffset / 4, image, typeSize, &channelIds, floating)

        #static if Core.BIG_ENDIAN
        {
            // The identifier is already stored as literal bytes.
            for index in 3 until dataOffset / 4
            {
                header[index] = Swag.byteSwap(header[index])
            }
        }

        let target = result.reserveInPlace(image.byteCount)
        let pixels = image.pixels.storage()
        let stride = cast(u64, image.rowStride)
        for y in image.height
        {
            let storageY = image.height - y - 1
            Memory.copy(target + cast(u64, y) * stride, pixels + cast(u64, storageY) * stride, stride)
        }
    }
}
