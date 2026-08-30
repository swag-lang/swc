//! Format: Khronos Texture 2 encoder.
//! Supported: One uncompressed 2D level in every packed PixelFormat integer or float layout.
//! Not supported: Supercompression, block compression, mipmap generation, arrays, or cubemaps.
//! Role: This file writes a Vulkan-format KTX2 texture and its matching basic DFD.
//
#global namespace Ktx2

using Core, Core.Errors

internal struct Encoder {}

#[Swag.Inline]
func writeU32(result: *ConcatBuffer, value: u32)
{
    result.addNative(cast(u8) (value & 0xFF))
    result.addNative(cast(u8) ((value >> 8) & 0xFF))
    result.addNative(cast(u8) ((value >> 16) & 0xFF))
    result.addNative(cast(u8) ((value >> 24) & 0xFF))
}

#[Swag.Inline]
func writeU64(result: *ConcatBuffer, value: u64)
{
    writeU32(result, cast(u32) (value & 0xFFFF_FFFF))
    writeU32(result, cast(u32) (value >> 32))
}

func formatInfo(format: PixelFormat, vk: *u32, typeSize: *u32, channelIds: *[4] u8, floating: *bool)
{
    switch #complete format
    {
    case .Gray8:
        vk[] = 9

    case .GrayAlpha8:
        vk[]            = 16
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
        vk[]            = 37
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

    case .Yuv420:
        Debug.assert(false)
    }
}

func writeDfd(result: *ConcatBuffer, image: Image, typeSize: u32, channelIds: *[4] u8, floating: bool)
{
    let channels  = cast(u32) image.pixelFormat.channels()
    let blockSize = 24'u32 + channels * 16
    writeU32(result, blockSize + 4)
    writeU32(result, 0)                         // Khronos vendor, basic descriptor type.
    writeU32(result, (blockSize << 16) | 2)     // KDF version 2.
    result.addNative(1'u8)                      // KHR_DF_MODEL_RGBSDA.
    result.addNative(1'u8)                      // BT.709/sRGB primaries.
    result.addNative(1'u8)                      // Linear transfer for UNORM/SFLOAT Vulkan formats.
    result.addNative(image.alphaMode == .Premultiplied ? 1'u8 : 0'u8)
    writeU32(result, 0)     // 1x1x1x1 texel block, stored as dimensions minus one.
    result.addNative(image.bytesPerPixel)
    for 7 do
        result.addNative(0'u8)

    let bits = typeSize * 8
    for channel in channels
    {
        let channelType = channelIds[][channel] | (floating ? 0x80 : 0)
        writeU32(result, channel * bits | ((bits - 1) << 16) | (cast(u32) channelType << 24))
        writeU32(result, 0)     // Sample positions.
        let floatLower = typeSize == 2 ? 0xBC00'u32 : 0xBF800000'u32
        let floatUpper = typeSize == 2 ? 0x3C00'u32 : 0x3F800000'u32
        writeU32(result, floating ? floatLower : 0)
        writeU32(result, floating ? floatUpper : ((1'u32 << bits) - 1))
    }
}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"KTX2 - Khronos Texture", ".ktx2"}

    mtd impl encode(result: *ConcatBuffer, image: Image, options: #null any) fail
    {
        discard options
        if !image.isValid() or !image.pixelFormat.isPacked() do
            fail InvalidFormatError{"invalid packed image"}

        var vk:         u32
        var typeSize           = 1'u32
        var channelIds: [4] u8 = [0, 1, 2, 3]
        var floating:   bool
        formatInfo(image.pixelFormat, &vk, &typeSize, &channelIds, &floating)
        let dfdLength  = 28'u64 + cast(u64) image.pixelFormat.channels() * 16
        let dfdOffset  = HeaderSize + 24
        let alignment  = cast(u64) Math.lcm(4, image.bytesPerPixel)
        let dataOffset = (dfdOffset + dfdLength + alignment - 1) / alignment * alignment

        result.addBytes(Identifier)
        writeU32(result, vk)
        writeU32(result, typeSize)
        writeU32(result, cast(u32) image.width)
        writeU32(result, cast(u32) image.height)
        writeU32(result, 0)
        writeU32(result, 0)
        writeU32(result, 1)
        writeU32(result, 1)
        writeU32(result, 0)
        writeU32(result, cast(u32) dfdOffset)
        writeU32(result, cast(u32) dfdLength)
        writeU32(result, 0)
        writeU32(result, 0)
        writeU64(result, 0)
        writeU64(result, 0)
        writeU64(result, dataOffset)
        writeU64(result, image.byteCount)
        writeU64(result, image.byteCount)
        writeDfd(result, image, typeSize, &channelIds, floating)
        while result.count() < dataOffset do
            result.addNative(0'u8)
        for y in image.height
        {
            let storageY = image.height - y - 1
            result.addBytes(Swag.makeSlice(image.pixels.buffer! + cast(u64) storageY * image.rowStride, cast(u64) image.rowStride))
        }
    }
}
