//! Format: GPU block-compression reconstruction shared by texture containers.
//! Supported: BC1, BC2, BC3, BC4 unsigned, and BC5 unsigned blocks.
//! Not supported: Signed BC4/BC5, BC6H, BC7, ETC, ASTC, or encoder-side compression.
//! Role: This file turns independently stored 4x4 GPU blocks into displayable RGBA pixels.
//
#global namespace TextureBlocks

using Core, Core.Errors, Core.Math

internal enum Format
{
    None
    BC1
    BC2
    BC3
    BC4
    BC5
}

internal func blockBytes(format: Format)->u64
{
    switch #complete format
    {
    case .None:            unreachable
    case .BC1, .BC4:       return 8
    case .BC2, .BC3, .BC5: return 16
    }
}

#[Swag.Inline]
func readEndpoint(source: const [*] u8)->u16
{
    let value = cast(const *u16, source)[]
    return Core.BIG_ENDIAN ? Swag.byteSwap(value) : value
}

#[Swag.Inline]
func expandRgb565(value: u16)->u32
{
    let red   = cast(u32, value >> 11)
    let green = cast(u32, ((value >> 5) & 63))
    let blue  = cast(u32, (value & 31))
    return 0xFF000000 | (red << 3) | (red >> 2) |
           (green << 10) | ((green >> 4) << 8) |
           (blue << 19) | ((blue >> 2) << 16)
}

#[Swag.Inline]
func loadColorIndices(source: const [*] u8)->u32
{
    let indices = cast(const *u32, source)[]
    return Core.BIG_ENDIAN ? Swag.byteSwap(indices) : indices
}

#[Swag.Inline]
func colorPalette(result: *[4] u32, source: const [*] u8, forceFourColors: bool)
{
    let endpointA = readEndpoint(source)
    let endpointB = readEndpoint(source + 2)
    let a         = expandRgb565(endpointA)
    let b         = expandRgb565(endpointB)
    result[][0] = a
    result[][1] = b
    if forceFourColors or endpointA > endpointB
    {
        let first  = Simd.splat(a)
        let second = Simd.splat(b)
        let zero   = Simd.splat(0'u8)
        let ab     = cast #bit(Simd.U8x16, Simd.interleaveLow(first, second))
        let ba     = cast #bit(Simd.U8x16, Simd.interleaveLow(second, first))
        let words  = cast #bit(Simd.U16x8, Simd.interleaveLow(ab, zero))
        let other  = cast #bit(Simd.U16x8, Simd.interleaveLow(ba, zero))
        let sums   = words + words + other

        // The high product divides both RGB sums by three exactly through 765.
        let values       = cast #bit(Simd.S16x8, Simd.mulHigh(sums, Simd.splat(21846'u16)))
        let interpolated = cast #bit(Simd.U32x4, Simd.packUnsigned(values, values))
        result[][2] = interpolated[0]
        result[][3] = interpolated[1]
    }
    else
    {
        result[][2] = (a & b) + (((a ^ b) & 0xFEFEFEFE'u32) >> 1)
        result[][3] = 0
    }
}

#[Swag.Inline]
func alphaPalette(result: *[8] u8, source: const [*] u8)
{
    result[][0] = source[0]
    result[][1] = source[1]
    if result[][0] > result[][1]
    {
        for i in rangeTo(1, 6)
        {
            result[][i + 1] = cast(u8, ((cast(u16, result[][0]) * (7 - i) + cast(u16, result[][1]) * i) / 7))
        }
    }
    else
    {
        for i in rangeTo(1, 4)
        {
            result[][i + 1] = cast(u8, ((cast(u16, result[][0]) * (5 - i) + cast(u16, result[][1]) * i) / 5))
        }

        result[][6] = 0
        result[][7] = 255
    }
}

#[Swag.Inline]
func loadAlphaBits(source: const [*] u8)->u64
{
    var bits = 0_u64
    for i in 6
    {
        bits |= cast(u64, source[2 + i]) << (i * 8)
    }

    return cast(u8, ((bits >> (pixel * 3)) & 7))
}

// Map the four two-bit color indices in each encoded row to RGBA byte offsets.
#[Swag.ConstExpr]
func bc1RowShuffles()->[256] Simd.U8x16
{
    if x >= image.width or sourceY >= image.height
    {
        return
    }

    let targetY = sourceTopDown ? image.height - sourceY - 1 : sourceY
    let target  = image.pixels.storage() + cast(u64, targetY) * image.rowStride + cast(u64, x) * 4
    target[0] = color.r
    target[1] = color.g
    target[2] = color.b
    target[3] = color.a
}

internal func decode(image: *Image, source: const [..] u8, format: Format, sourceTopDown = true) fail
{
    let columns  = (cast(u64, image.width) + 3) / 4
    let rows     = (cast(u64, image.height) + 3) / 4
    let oneBlock = blockBytes(format)
    if columns > Swag.U64.Max / rows or columns * rows > source.count / oneBlock
    {
        fail InvalidFormatError{"block-compressed texture data is truncated"}
    }

    var offset = 0_u64
    for blockY in rows
    {
        for blockX in columns
        {
            let block      = source.buffer + offset
            var colors: [4] Color
            var alpha:  [8] u8
            var red:    [8] u8
            var green:  [8] u8
            var colorBlock = block
            if format == .BC2
            {
                colorBlock += 8
            }
            else if format == .BC3
            {
                alphaPalette(&alpha, block)
                colorBlock += 8
            }
            else if format == .BC4
            {
                alphaPalette(&red, block)
            }
            else if format == .BC5
            {
                alphaPalette(&red, block)
                alphaPalette(&green, block + 8)
            }

            var indices = 0_u32
            if format == .BC1 or format == .BC2 or format == .BC3
            {
                let color0 = readU16(colorBlock)
                let color1 = readU16(colorBlock + 2)
                colorPalette(&colors, color0, color1, format != .BC1)
                indices = readU32(colorBlock + 4)
            }

            for pixel in 16_u32
            {
                let x = cast(s32, (blockX * 4 + pixel % 4))
                let y = cast(s32, (blockY * 4 + pixel / 4))
                var color: Color
                if format == .BC4
                {
                    let value = red[alphaIndex(block, pixel)]
                    color = Color.fromRgb(value, value, value)
                }
                else if format == .BC5
                {
                    color = Color.fromRgb(red[alphaIndex(block, pixel)], green[alphaIndex(block + 8, pixel)], 0)
                }
                else
                {
                    color = colors[(indices >> (pixel * 2)) & 3]
                    if format == .BC2
                    {
                        color.a = cast(u8, (((readU16(block + cast(u64, (pixel / 4)) * 2) >> ((pixel & 3) * 4)) & 15) * 17))
                    }
                    else if format == .BC3
                    {
                        color.a = alpha[alphaIndex(block, pixel)]
                    }
                }

                storePixel(image, x, y, color, sourceTopDown)
            }

            offset += oneBlock
        }
    }
}
