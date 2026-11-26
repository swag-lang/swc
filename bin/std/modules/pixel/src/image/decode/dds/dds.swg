//! Format: DirectDraw Surface decoder.
//! Supported: Mip levels, array layers, cube faces, and volume slices of legacy or DX10 DDS files; RGB/luminance integer pixels,
//!            RGBA 8/16-bit and half/full-float DXGI pixels, and BC1 through BC5 compression.
//! Not supported: Signed blocks, BC6H, BC7, or palette data.
//! Role: This file validates DDS headers and exposes their base texture as a Pixel image.
//
#global namespace Dds

using Core, Core.Errors

const Magic      = 0x20534444_u32
const HeaderSize = 128_u64
const FourCcFlag = 0x00000004_u32
const RgbFlag    = 0x00000040_u32
const AlphaFlag  = 0x00000001_u32
const LumaFlag   = 0x00020000_u32

internal struct Decoder
{
    bytes:  const [..] u8?
    frames: Array!{ImageFrameInfo}
}

#[Swag.Inline]
func readU32(source: const [*] u8)->u32 => cast(const *u32, source)[]

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

private struct MaskField
{
    if not mask
    {
        return fallback
    }

    let shift  = Math.trailingZeros(mask)
    let bits   = Math.countOnes(mask)
    let limit  = bits == 32 ? Swag.U32.Max : (1_u32 << bits) - 1
    let sample = cast(u64, ((value & mask) >> shift))
    return cast(u8, ((sample * 255 + limit / 2) / limit))
}

private func prepareField(mask: u32, fallback: u8)->MaskField
{
    if not mask {
        return {0, 0, 1, fallback}
    }
    let shift = Math.trailingZeros(mask)
    let bits  = Math.countOnes(mask)
    let limit = bits == 32 ? Swag.U32.Max : (1_u32 << bits) - 1
    return {mask, shift, limit, fallback}
}

#[Swag.Inline]
private func maskToByte(value: u32, field: MaskField)->u8
{
    if not field.mask {
        return field.fallback
    }
    let sample = cast(u64, ((value & field.mask) >> field.shift))
    return cast(u8, ((sample * 255 + field.limit / 2) / field.limit))
}

private func isByteField(field: MaskField, bits: u32)->bool
{
    return not field.mask or (field.shift % 8 == 0 and field.shift < bits and field.mask == (255_u32 << field.shift))
}

private func decodeByteFieldsRow(source: const [*] u8, target: [*] u8, width, pixelBytes: u64, fields: const *[4] MaskField, order, fallback: Math.Simd.U8x16)
{
    using Math.Simd
    let rowBytes = width * pixelBytes
    var x        = 0_u64
    var offset   = 0_u64
    while width - x >= 4 and rowBytes - offset >= 16
    {
        store(target + x * 4, shuffle(load(source + offset), order) | fallback)
        x      += 4
        offset += 4 * pixelBytes
    }

    while x < width
    {
        for channel in 4
        {
            let field = fields[][channel]
            target[x * 4 + channel] = field.mask ? source[offset + field.shift / 8] : field.fallback
        }

        x      += 1
        offset += pixelBytes
    }
}

#[Swag.Inline]
private func scaleTenBit(samples: Math.Simd.U32x4)->Math.Simd.U32x4
{
    // Division by 1023 with round-to-nearest over the full ten-bit range.
    let biased = samples * 255_u32 + 512_u32
    return (biased + (biased >> 10)) >> 10
}

private func decodeRgb10Row(source: const [*] u8, target: [*] u8, width: u64, fields: const *[4] MaskField, hasAlpha: bool)
{
    using Math.Simd
    let input  = cast(const [*] u32, source)
    let output = cast([*] u32, target)
    let opaque = splat(0xFF00_0000_u32)
    var x      = 0_u64
    while width - x >= 4
    {
        let word  = load(input + x)
        let red   = scaleTenBit((word >> 20) & 1023_u32)
        let green = scaleTenBit((word >> 10) & 1023_u32)
        let blue  = scaleTenBit(word & 1023_u32)
        let alpha = hasAlpha ? (((word >> 30) * 85_u32) << 24) : opaque
        store(output + x, red | (green << 8) | (blue << 16) | alpha)
        x += 4
    }

    for i in x until width
    {
        let word = input[i]
        for channel in 4 {
            target[i * 4 + channel] = maskToByte(word, fields[][channel])
        }
    }
}

func decodeMasked(image: *Image, buffer: const [..] u8, offset, pitch: u64, bits: u32, redMask, greenMask, blueMask, alphaMask: u32, luminance: bool) fail
{
    let width      = cast(u64, image.width)
    let pixelBytes = cast(u64, (bits + 7)) / 8
    let rowBytes   = cast(u64, image.width) * pixelBytes
    if pitch!{rowBytes or cast(u64, image.height)}(buffer.count - offset) / pitch
    {
        fail InvalidFormatError{"DDS pixel rows are truncated"}
    }

    let fields: [4] MaskField = [prepareField(redMask, 0), prepareField(greenMask, 0), prepareField(blueMask, 0), prepareField(alphaMask, 255)]
    let rgb565 = not luminance and
                 bits == 16 and
                 redMask == 0xF800 and
                 greenMask == 0x07E0 and
                 blueMask == 0x1F and
                 not alphaMask
    let rgb10 = not luminance and
                bits == 32 and
                redMask == 0x3FF0_0000 and
                greenMask == 0x000F_FC00 and
                blueMask == 0x3FF and
                (not alphaMask or alphaMask == 0xC000_0000)
    let copyLuminance = luminance and
                        redMask == 255 and
                        ((bits == 8 and not alphaMask) or (bits == 16 and alphaMask == 0xFF00))
    var byteFields = not luminance
    for field in fields {
        byteFields = byteFields and isByteField(field, bits)

    }
    var orderBytes:    [16] u8
    var fallbackBytes: [16] u8
    if byteFields
    {
        for lane in 4
        {
            for channel in 4
            {
                let field = fields[channel]
                let index = lane * 4 + channel
                orderBytes[index]    = field.mask ? cast(u8, (lane * pixelBytes + field.shift / 8)) : 0x80
                fallbackBytes[index] = field.mask ? 0 : field.fallback
            }
        }
    }

    let order    = cast(Math.Simd.U8x16, orderBytes)
    let fallback = cast(Math.Simd.U8x16, fallbackBytes)
    for y in image.height
    {
        var source  = buffer.buffer + offset + cast(u64, y) * pitch
        let targetY = image.height - y - 1
        var target  = image.pixels.storage() + cast(u64, targetY) * image.rowStride
        if copyLuminance
        {
            Memory.copy(target, source, rowBytes)
            continue
        }

        if rgb565
        {
            PackedPixel.decodeRgb565ToRgbaRow(source, target, width)
            continue
        }

        if rgb10
        {
            decodeRgb10Row(source, target, width, &fields, alphaMask != 0)
            continue
        }

        if byteFields
        {
            decodeByteFieldsRow(source, target, width, pixelBytes, &fields, order, fallback)
            continue
        }

        for width
        {
            var value = 0_u32
            for byte in pixelBytes
            {
                value |= cast(u32, source[cast(u64, x) * pixelBytes + byte]) << (byte * 8)
            }

            if luminance
            {
                target[0] = maskToByte(value, redMask, 0)
                if image.pixelFormat == .GrayAlpha8
                {
                    target[1] = maskToByte(value, alphaMask, 255)
                }
            }
            else
            {
                target[1] = maskToByte(value, fields[1])
                target[2] = maskToByte(value, fields[2])
                target[3] = maskToByte(value, fields[3])
            }

            source += pixelBytes
            target += image.bytesPerPixel
        }
    }
}

func copyRows(image: *Image, buffer: const [..] u8, offset, pitch: u64, forceOpaqueAlpha: bool) fail
{
    let rowBytes = cast(u64, image.rowStride)
    if pitch!{rowBytes or cast(u64, image.height)}(buffer.count - offset) / pitch
    {
        fail InvalidFormatError{"DDS pixel rows are truncated"}
    }

    for y in image.height
    {
        let targetY = image.height - y - 1
        let target  = image.pixels.storage() + cast(u64, targetY) * image.rowStride
        Memory.copy(target, buffer.buffer + offset + cast(u64, y) * pitch, rowBytes)
        if forceOpaqueAlpha
        {
            for x in image.width
            {
                target[cast(u64, x) * 4 + 3] = 255
            }
        }
    }
}

impl Decoder
{
    mtd decodeSurface(buffer: const [..] u8, options: DecodeOptions, selected: u32 = 0, collect = false)->Image fail
    {
        if buffer.count < HeaderSize or readU32(buffer.buffer) != Magic
        {
            fail InvalidFormatError{"DDS signature or header is truncated"}
        }

        if readU32(buffer.buffer + 4) != 124 or readU32(buffer.buffer + 76) != 32
        {
            fail InvalidFormatError{"DDS header sizes are invalid"}
        }

        var height = readU32(buffer.buffer + 12)
        var width  = readU32(buffer.buffer + 16)
        if width == 0 or
           height == 0 or
           width > cast(u32, Swag.S32.Max) or
           height > cast(u32, Swag.S32.Max)
        {
            fail UnsupportedFormatError{"DDS dimensions exceed the image limits"}
        }

        let pfFlags   = readU32(buffer.buffer + 80)
        let fourCc    = readU32(buffer.buffer + 84)
        let bits      = readU32(buffer.buffer + 88)
        let redMask   = readU32(buffer.buffer + 92)
        let greenMask = readU32(buffer.buffer + 96)
        let blueMask  = readU32(buffer.buffer + 100)
        var alphaMask = readU32(buffer.buffer + 104)
        if (pfFlags & AlphaFlag) == 0
        {
            alphaMask = 0
        }

        var offset    = HeaderSize
        var format    = PixelFormat.RGBA8
        var blocks:           TextureBlocks.Format
        var directCopy:       bool
        var forceOpaqueAlpha: bool
        var alphaMode = AlphaMode.Straight
        let caps2     = readU32(buffer.buffer + 112)
        var layers    = 1_u32
        var faces:            Array!{u32}
        var depth     = (caps2 & 0x200000) ? readU32(buffer.buffer + 24) : 1_u32
        if caps2 & 0x200
        {
            for face in 6_u32 where caps2 & (0x400_u32 << face)
            {
                faces.add(face)
            }

            if not faces.count
            {
                fail InvalidFormatError{"DDS cubemap declares no faces"}
            }
        }
        else
        {
            faces.add(0)
        }

        if pfFlags & FourCcFlag
        {
            if fourCc == 0x30315844     // DX10
            {
                if buffer.count < 148
                {
                    fail InvalidFormatError{"DDS DX10 header is truncated"}
                }

                let dxgi      = readU32(buffer.buffer + 128)
                let dimension = readU32(buffer.buffer + 132)
                let arraySize = readU32(buffer.buffer + 140)
                if dimension < 2 or dimension > 4 or arraySize == 0
                {
                    fail InvalidFormatError{"DDS texture dimension or array size is invalid"}
                }

                layers = arraySize
                depth  = dimension == 4 ? readU32(buffer.buffer + 24) : 1
                if dimension == 4 and arraySize != 1
                {
                    fail InvalidFormatError{"DDS volume texture cannot be an array"}
                }

                if dimension == 2 and height != 1
                {
                    fail InvalidFormatError{"DDS one-dimensional texture has multiple rows"}
                }

                faces.clear()
                if readU32(buffer.buffer + 136) & 4
                {
                    if dimension != 3 or width != height
                    {
                        fail InvalidFormatError{"DDS cubemap dimensions are invalid"}
                    }

                    for face in 6_u32
                    {
                        faces.add(face)
                    }
                }
                else
                {
                    faces.add(0)
                }

                if not dxgiFormat(dxgi, &format, &blocks)
                {
                    fail UnsupportedFormatError{"DDS DXGI pixel format is not supported"}
                }

                let mode = readU32(buffer.buffer + 144) & 7
                if mode == 2
                {
                    alphaMode = .Premultiplied
                }

                forceOpaqueAlpha = dxgi == 88 or dxgi == 93
                directCopy       = blocks == .None
                offset           = 148
            }
            else
            {
                blocks = blockFormat(fourCc)
                if blocks == .None
                {
                    fail UnsupportedFormatError{"DDS FourCC pixel format is not supported"}
                }

                if fourCc == 0x32545844 or fourCc == 0x34545844
                {
                    alphaMode = .Premultiplied
                }
            }
        }
        else if pfFlags & LumaFlag
        {
            if bits != 8 and bits != 16
            {
                fail UnsupportedFormatError{"DDS luminance depth is not supported"}
            }

            format = alphaMask ? .GrayAlpha8 : .Gray8
        }
        else if pfFlags & RgbFlag
        {
            if bits != 8 and bits != 16 and bits != 24 and bits != 32
            {
                fail UnsupportedFormatError{"DDS RGB depth is not supported"}
            }

            format = .RGBA8
        }
        else
        {
            fail UnsupportedFormatError{"DDS pixel format is not RGB, luminance, or block compressed"}
        }

        if blocks != .None
        {
            format = .RGBA8
        }

        if not depth or (depth > 1 and faces.count != 1)
        {
            fail InvalidFormatError{"DDS volume depth is invalid"}
        }

        let levels = Math.max(readU32(buffer.buffer + 28), 1_u32)
        if levels > 32
        {
            fail InvalidFormatError{"DDS mip count exceeds its dimensions"}
        }

        try options.checkFrameCount(cast(u64, layers) * faces.count * levels)
        let baseWidth  = width
        let baseHeight = height
        var cursor     = offset
        var current    = 0_u64
        var selectedPitch:  u64
        var selectedLength: u64
        if collect
        {
            .frames.clear()
        }

        for layer in layers
        {
            for face in faces
            {
                for level in levels
                {
                    let frameWidth  = Math.max(baseWidth >> level, 1_u32)
                    let frameHeight = Math.max(baseHeight >> level, 1_u32)
                    let slices      = Math.max(depth >> level, 1_u32)
                    try options.checkFrameCount(current + slices)
                    try options.checkImage(cast(s32, frameWidth), cast(s32, frameHeight), format)
                    let rowBytes      = directCopy ? cast(u64, frameWidth) * format.bitsPerPixel() / 8 : (cast(u64, frameWidth) * bits + 7) / 8
                    let declaredPitch = level == 0 ? cast(u64, readU32(buffer.buffer + 20)) : 0
                    let pitch         = Math.max(rowBytes, declaredPitch)
                    let length        = blocks != .None ? cast(u64, ((frameWidth + 3) / 4)) * ((frameHeight + 3) / 4) * TextureBlocks.blockBytes(blocks) : pitch * frameHeight
                    for slice in slices
                    {
                        if cursor > buffer.count or length > buffer.count - cursor
                        {
                            fail InvalidFormatError{"DDS texture subresource is truncated"}
                        }

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
                            let frame: ImageFrameInfo = ImageFrameInfo{kind: .Texture, width: cast(s32, frameWidth), height: cast(s32, frameHeight), pixelFormat: format, layer: layer, face: face, level: level, depthSlice: slice}
                            .frames.add(frame)
                        }

                        cursor  += length
                        current += 1
                    }
                }
            }
        }

        if selected >= current
        {
            fail InvalidFormatError{"DDS image index is out of range"}
        }

        var result: #returntype
        result.init(cast(s32, width), cast(s32, height), format, alphaMode)
        if not options.decodePixels
        {
            return result
        }

        result.allocPixels()

        if blocks != .None
        {
            try TextureBlocks.decode(&result, buffer[offset until offset + selectedLength], blocks)
        }
        else if directCopy
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
    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail => try .decodeSurface(buffer, options)
}

impl IImageSetDecoder for Decoder
{
    mtd impl open(buffer: const [..] u8, options: DecodeOptions)->ImageSetInfo fail
    {
        .bytes = buffer
        var probeOptions = options
        probeOptions.decodePixels = false
        discard try .decodeSurface(buffer, probeOptions, collect: true)
        var result: #returntype
        result.frames = .frames
        return result
    }

    mtd impl readFrame(index: u32, options: DecodeOptions)->Image fail => try .decodeSurface(unwrap .bytes, options, index)
}
