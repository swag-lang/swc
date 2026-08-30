//! Format: DirectDraw Surface decoder.
//! Supported: First 2D surface of legacy or DX10 DDS files; RGB/luminance integer pixels,
//!            RGBA 8/16-bit and half/full-float DXGI pixels, and BC1 through BC5 compression.
//! Not supported: Volume slices, cubemap selection, signed blocks, BC6H, BC7, or palette data.
//! Role: This file validates DDS headers and exposes their base texture as a Pixel image.
//
#global namespace Dds

using Core, Core.Errors

const Magic      = 0x20534444'u32
const HeaderSize = 128'u64
const FourCcFlag = 0x00000004'u32
const RgbFlag    = 0x00000040'u32
const AlphaFlag  = 0x00000001'u32
const LumaFlag   = 0x00020000'u32

internal struct Decoder {}

#[Swag.Inline]
func readU32(source: const [*] u8)->u32 => source[as u32]

func blockFormat(fourCc: u32)->TextureBlocks.Format
{
    switch fourCc
    {
    case 0x31545844:
        return .BC1     // DXT1

    case 0x32545844, 0x33545844:
        return .BC2     // DXT2, DXT3

    case 0x34545844, 0x35545844:
        return .BC3     // DXT4, DXT5

    case 0x31495441, 0x55344342:
        return .BC4     // ATI1, BC4U

    case 0x32495441, 0x55354342:
        return .BC5     // ATI2, BC5U
    }

    return .None
}

func dxgiFormat(dxgi: u32, pixelFormat: *PixelFormat, blocks: *TextureBlocks.Format)->bool
{
    switch dxgi
    {
    case 2:      pixelFormat[] = .RGBAF32
    case 10:     pixelFormat[] = .RGBAF16
    case 11:     pixelFormat[] = .RGBA16
    case 16:     pixelFormat[] = .GrayAlphaF32
    case 34:     pixelFormat[] = .GrayAlphaF16
    case 35:     pixelFormat[] = .GrayAlpha16
    case 28, 29: pixelFormat[] = .RGBA8
    case 41:     pixelFormat[] = .GrayF32
    case 49:     pixelFormat[] = .GrayAlpha8
    case 54:     pixelFormat[] = .GrayF16
    case 56:     pixelFormat[] = .Gray16
    case 61:     pixelFormat[] = .Gray8
    case 71, 72: blocks[] = .BC1
    case 74, 75: blocks[] = .BC2
    case 77, 78: blocks[] = .BC3
    case 80:     blocks[] = .BC4
    case 83:     blocks[] = .BC5
    case 87, 91: pixelFormat[] = .BGRA8
    case 88, 93: pixelFormat[] = .BGRA8
    default:     return false
    }

    return true
}

#[Swag.Inline]
func maskToByte(value, mask: u32, fallback: u8)->u8
{
    if !mask do
        return fallback
    let shift  = Math.trailingZeros(mask)
    let bits   = Math.countOnes(mask)
    let limit  = bits == 32 ? Swag.U32.Max : (1'u32 << bits) - 1
    let sample = cast(u64) ((value & mask) >> shift)
    return cast(u8) ((sample * 255 + limit / 2) / limit)
}

func decodeMasked(image: *Image, buffer: const [..] u8, offset: u64, pitch: u64, bits: u32, redMask, greenMask, blueMask, alphaMask: u32, luminance: bool) fail
{
    let pixelBytes = cast(u64) (bits + 7) / 8
    let rowBytes   = cast(u64) image.width * pixelBytes
    if pitch < rowBytes or cast(u64) image.height > (buffer.count - offset) / pitch do
        fail InvalidFormatError{"DDS pixel rows are truncated"}

    for y in image.height
    {
        let source  = buffer.buffer + offset + cast(u64) y * pitch
        let targetY = image.height - y - 1
        var target  = image.pixels.buffer! + cast(u64) targetY * image.rowStride
        for x in image.width
        {
            var value = 0'u32
            for byte in pixelBytes do
                value |= cast(u32) source[cast(u64) x * pixelBytes + byte] << (byte * 8)
            if luminance
            {
                target[0] = maskToByte(value, redMask, 0)
                if image.pixelFormat == .GrayAlpha8 do
                    target[1] = maskToByte(value, alphaMask, 255)
            }
            else
            {
                target[0] = maskToByte(value, redMask, 0)
                target[1] = maskToByte(value, greenMask, 0)
                target[2] = maskToByte(value, blueMask, 0)
                target[3] = maskToByte(value, alphaMask, 255)
            }

            target += image.bytesPerPixel
        }
    }
}

func copyRows(image: *Image, buffer: const [..] u8, offset, pitch: u64, forceOpaqueAlpha: bool) fail
{
    let rowBytes = cast(u64) image.rowStride
    if pitch < rowBytes or cast(u64) image.height > (buffer.count - offset) / pitch do
        fail InvalidFormatError{"DDS pixel rows are truncated"}
    for y in image.height
    {
        let targetY = image.height - y - 1
        let target  = image.pixels.buffer! + cast(u64) targetY * image.rowStride
        Memory.copy(target, buffer.buffer + offset + cast(u64) y * pitch, rowBytes)
        if forceOpaqueAlpha
        {
            for x in image.width do
                target[cast(u64) x * 4 + 3] = 255
        }
    }
}

internal impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => {"DDS - DirectDraw Surface", ".dds"}

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        if buffer.count < HeaderSize or readU32(buffer.buffer) != Magic do
            fail InvalidFormatError{"DDS signature or header is truncated"}
        if readU32(buffer.buffer + 4) != 124 or readU32(buffer.buffer + 76) != 32 do
            fail InvalidFormatError{"DDS header sizes are invalid"}

        let height = readU32(buffer.buffer + 12)
        let width  = readU32(buffer.buffer + 16)
        if width == 0 or height == 0 or width > cast(u32) Swag.S32.Max or height > cast(u32) Swag.S32.Max do
            fail UnsupportedFormatError{"DDS dimensions exceed the image limits"}

        let pfFlags   = readU32(buffer.buffer + 80)
        let fourCc    = readU32(buffer.buffer + 84)
        let bits      = readU32(buffer.buffer + 88)
        let redMask   = readU32(buffer.buffer + 92)
        let greenMask = readU32(buffer.buffer + 96)
        let blueMask  = readU32(buffer.buffer + 100)
        let alphaMask = readU32(buffer.buffer + 104)
        var offset    = HeaderSize
        var format    = PixelFormat.RGBA8
        var blocks:           TextureBlocks.Format
        var directCopy:       bool
        var forceOpaqueAlpha: bool
        var alphaMode = AlphaMode.Straight

        if pfFlags & FourCcFlag
        {
            if fourCc == 0x30315844     // DX10
            {
                if buffer.count < 148 do
                    fail InvalidFormatError{"DDS DX10 header is truncated"}
                let dxgi      = readU32(buffer.buffer + 128)
                let dimension = readU32(buffer.buffer + 132)
                let arraySize = readU32(buffer.buffer + 140)
                if dimension != 3 or arraySize == 0 do
                    fail UnsupportedFormatError{"DDS resource is not a 2D texture"}
                if !dxgiFormat(dxgi, &format, &blocks) do
                    fail UnsupportedFormatError{"DDS DXGI pixel format is not supported"}
                let mode = readU32(buffer.buffer + 144) & 7
                if mode == 2 do
                    alphaMode = .Premultiplied
                forceOpaqueAlpha = dxgi == 88 or dxgi == 93
                directCopy       = blocks == .None
                offset           = 148
            }
            else
            {
                blocks = blockFormat(fourCc)
                if blocks == .None do
                    fail UnsupportedFormatError{"DDS FourCC pixel format is not supported"}
                if fourCc == 0x32545844 or fourCc == 0x34545844 do
                    alphaMode = .Premultiplied
            }
        }
        elif pfFlags & LumaFlag
        {
            if bits != 8 and bits != 16 do
                fail UnsupportedFormatError{"DDS luminance depth is not supported"}
            format = alphaMask ? .GrayAlpha8 : .Gray8
        }
        elif pfFlags & RgbFlag
        {
            if bits != 8 and bits != 16 and bits != 24 and bits != 32 do
                fail UnsupportedFormatError{"DDS RGB depth is not supported"}
            format = .RGBA8
        }
        else do
            fail UnsupportedFormatError{"DDS pixel format is not RGB, luminance, or block compressed"}

        if blocks != .None do
            format = .RGBA8
        var result: retval
        result.init(cast(s32) width, cast(s32) height, format, alphaMode)
        if !options.decodePixels do
            return result
        result.allocPixels()

        if blocks != .None
        {
            try TextureBlocks.decode(&result, buffer[offset to], blocks)
        }
        elif directCopy
        {
            let rowBytes      = cast(u64) result.rowStride
            let declaredPitch = cast(u64) readU32(buffer.buffer + 20)
            let pitch         = declaredPitch >= rowBytes ? declaredPitch : rowBytes
            try copyRows(&result, buffer, offset, pitch, forceOpaqueAlpha)
        }
        else
        {
            let rowBytes      = (cast(u64) width * bits + 7) / 8
            let declaredPitch = cast(u64) readU32(buffer.buffer + 20)
            let pitch         = declaredPitch >= rowBytes ? declaredPitch : rowBytes
            try decodeMasked(&result, buffer, offset, pitch, bits, redMask, greenMask, blueMask, alphaMask, (pfFlags & LumaFlag) != 0)
        }

        return result
    }
}
