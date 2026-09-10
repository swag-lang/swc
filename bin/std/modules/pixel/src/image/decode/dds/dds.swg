//! Format: DirectDraw Surface decoder.
//! Supported: Mip levels, array layers, cube faces, and volume slices of legacy or DX10 DDS files; RGB/luminance integer pixels,
//!            RGBA 8/16-bit and half/full-float DXGI pixels, and BC1 through BC5 compression.
//! Not supported: Signed blocks, BC6H, BC7, or palette data.
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

internal struct Decoder
{
    bytes:  const [..] u8?
    frames: Array'ImageFrameInfo
}

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
    if not mask do
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

impl Decoder
{
    mtd decodeSurface(buffer: const [..] u8, options: DecodeOptions, selected: u32 = 0, collect = false)->Image fail
    {
        if buffer.count < HeaderSize or readU32(buffer.buffer) != Magic do
            fail InvalidFormatError{"DDS signature or header is truncated"}
        if readU32(buffer.buffer + 4) != 124 or readU32(buffer.buffer + 76) != 32 do
            fail InvalidFormatError{"DDS header sizes are invalid"}

        var height = readU32(buffer.buffer + 12)
        var width  = readU32(buffer.buffer + 16)
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
        let caps2     = readU32(buffer.buffer + 112)
        var layers    = 1'u32
        var faces:            Array'u32
        var depth     = (caps2 & 0x200000) ? readU32(buffer.buffer + 24) : 1'u32
        if caps2 & 0x200
        {
            for face in 6'u32 where caps2 & (0x400'u32 << face) do
                faces.add(face)
            if not faces.count do
                fail InvalidFormatError{"DDS cubemap declares no faces"}
        }
        else do
            faces.add(0)

        if pfFlags & FourCcFlag
        {
            if fourCc == 0x30315844     // DX10
            {
                if buffer.count < 148 do
                    fail InvalidFormatError{"DDS DX10 header is truncated"}
                let dxgi      = readU32(buffer.buffer + 128)
                let dimension = readU32(buffer.buffer + 132)
                let arraySize = readU32(buffer.buffer + 140)
                if dimension < 2 or dimension > 4 or arraySize == 0 do
                    fail InvalidFormatError{"DDS texture dimension or array size is invalid"}
                layers = arraySize
                depth  = dimension == 4 ? readU32(buffer.buffer + 24) : 1
                if dimension == 4 and arraySize != 1 do
                    fail InvalidFormatError{"DDS volume texture cannot be an array"}
                if dimension == 2 and height != 1 do
                    fail InvalidFormatError{"DDS one-dimensional texture has multiple rows"}
                faces.clear()
                if readU32(buffer.buffer + 136) & 4
                {
                    if dimension != 3 or width != height do
                        fail InvalidFormatError{"DDS cubemap dimensions are invalid"}
                    for face in 6'u32 do
                        faces.add(face)
                }
                else do
                    faces.add(0)
                if not dxgiFormat(dxgi, &format, &blocks) do
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
        if not depth or (depth > 1 and faces.count != 1) do
            fail InvalidFormatError{"DDS volume depth is invalid"}
        let levels = Math.max(readU32(buffer.buffer + 28), 1'u32)
        if levels > 32 do
            fail InvalidFormatError{"DDS mip count exceeds its dimensions"}
        options.checkFrameCount(cast(u64) layers * faces.count * levels)
        let baseWidth  = width
        let baseHeight = height
        var cursor     = offset
        var current    = 0'u64
        var selectedPitch:  u64
        var selectedLength: u64
        if collect do
            .frames.clear()
        for layer in layers
        {
            for face in faces
            {
                for level in levels
                {
                    let frameWidth  = Math.max(baseWidth >> level, 1'u32)
                    let frameHeight = Math.max(baseHeight >> level, 1'u32)
                    let slices      = Math.max(depth >> level, 1'u32)
                    options.checkFrameCount(current + slices)
                    options.checkImage(cast(s32) frameWidth, cast(s32) frameHeight, format)
                    let rowBytes      = directCopy ? cast(u64) frameWidth * format.bitsPerPixel() / 8 : (cast(u64) frameWidth * bits + 7) / 8
                    let declaredPitch = level == 0 ? cast(u64) readU32(buffer.buffer + 20) : 0
                    let pitch         = Math.max(rowBytes, declaredPitch)
                    let length        = blocks != .None ? cast(u64) ((frameWidth + 3) / 4) * ((frameHeight + 3) / 4) * TextureBlocks.blockBytes(blocks) : pitch * frameHeight
                    for slice in slices
                    {
                        if cursor > buffer.count or length > buffer.count - cursor do
                            fail InvalidFormatError{"DDS texture subresource is truncated"}
                        if current == selected
                        {
                            width          = frameWidth
                            height         = frameHeight
                            offset         = cursor
                            selectedPitch  = pitch
                            selectedLength = length
                        }

                        if collect
                        {
                            let frame: ImageFrameInfo = {kind: .Texture, width: cast(s32) frameWidth, height: cast(s32) frameHeight, pixelFormat: format, layer: layer, face: face, level: level, depthSlice: slice}
                            .frames.add(frame)
                        }

                        cursor  += length
                        current += 1
                    }
                }
            }
        }

        if selected >= current do
            fail InvalidFormatError{"DDS image index is out of range"}
        var result: retval
        result.init(cast(s32) width, cast(s32) height, format, alphaMode)
        if not options.decodePixels do
            return result
        result.allocPixels()

        if blocks != .None
        {
            try TextureBlocks.decode(&result, buffer[offset until offset + selectedLength], blocks)
        }
        elif directCopy
        {
            try copyRows(&result, buffer, offset, selectedPitch, forceOpaqueAlpha)
        }
        else
        {
            try decodeMasked(&result, buffer, offset, selectedPitch, bits, redMask, greenMask, blueMask, alphaMask, (pfFlags & LumaFlag) != 0)
        }

        return result
    }
}

impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => {"DDS - DirectDraw Surface", ".dds"}
    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail => .decodeSurface(buffer, options)
}

impl IImageSetDecoder for Decoder
{
    mtd impl open(buffer: const [..] u8, options: DecodeOptions)->ImageSetInfo fail
    {
        .bytes = buffer
        var probeOptions = options
        probeOptions.decodePixels = false
        discard .decodeSurface(buffer, probeOptions, collect: true)
        var result: retval
        result.frames = .frames
        return result
    }

    mtd impl readFrame(index: u32, options: DecodeOptions)->Image fail => .decodeSurface(.bytes!, options, index)
}
