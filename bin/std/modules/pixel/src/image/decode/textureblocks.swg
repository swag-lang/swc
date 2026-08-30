//! Format: GPU block-compression reconstruction shared by texture containers.
//! Supported: BC1, BC2, BC3, BC4 unsigned, and BC5 unsigned blocks.
//! Not supported: Signed BC4/BC5, BC6H, BC7, ETC, ASTC, or encoder-side compression.
//! Role: This file turns independently stored 4x4 GPU blocks into displayable RGBA pixels.
//
#global namespace TextureBlocks

using Core, Core.Errors

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
    case .None:
        Debug.assert(false)
        return 0

    case .BC1, .BC4:
        return 8

    case .BC2, .BC3, .BC5:
        return 16
    }
}

#[Swag.Inline]
func readU16(source: const [*] u8)->u16
{
    return cast(u16) source[0] | (cast(u16) source[1] << 8)
}

#[Swag.Inline]
func readU32(source: const [*] u8)->u32
{
    return cast(u32) source[0] |
           (cast(u32) source[1] << 8) |
           (cast(u32) source[2] << 16) |
           (cast(u32) source[3] << 24)
}

#[Swag.Inline]
func expand5(value: u16)->u8 => cast(u8) ((value << 3) | (value >> 2))

#[Swag.Inline]
func expand6(value: u16)->u8 => cast(u8) ((value << 2) | (value >> 4))

func colorPalette(result: *[4] Color, color0, color1: u16, forceFourColors: bool)
{
    result[][0] = Color.fromRgb(expand5((color0 >> 11) & 31), expand6((color0 >> 5) & 63), expand5(color0 & 31))
    result[][1] = Color.fromRgb(expand5((color1 >> 11) & 31), expand6((color1 >> 5) & 63), expand5(color1 & 31))
    if color0 > color1 or forceFourColors
    {
        result[][2] = Color.fromRgb(cast(u8) ((cast(u16) result[][0].r * 2 + result[][1].r) / 3),
                                    cast(u8) ((cast(u16) result[][0].g * 2 + result[][1].g) / 3),
                                    cast(u8) ((cast(u16) result[][0].b * 2 + result[][1].b) / 3))
        result[][3] = Color.fromRgb(cast(u8) ((cast(u16) result[][0].r + cast(u16) result[][1].r * 2) / 3),
                                    cast(u8) ((cast(u16) result[][0].g + cast(u16) result[][1].g * 2) / 3),
                                    cast(u8) ((cast(u16) result[][0].b + cast(u16) result[][1].b * 2) / 3))
    }
    else
    {
        result[][2] = Color.fromRgb(cast(u8) ((cast(u16) result[][0].r + result[][1].r) / 2),
                                    cast(u8) ((cast(u16) result[][0].g + result[][1].g) / 2),
                                    cast(u8) ((cast(u16) result[][0].b + result[][1].b) / 2))
        result[][3] = Color.fromArgb(0, 0, 0, 0)
    }
}

func alphaPalette(result: *[8] u8, source: const [*] u8)
{
    result[][0] = source[0]
    result[][1] = source[1]
    if result[][0] > result[][1]
    {
        for i in rangeTo(1, 6) do
            result[][i + 1] = cast(u8) ((cast(u16) result[][0] * (7 - i) + cast(u16) result[][1] * i) / 7)
    }
    else
    {
        for i in rangeTo(1, 4) do
            result[][i + 1] = cast(u8) ((cast(u16) result[][0] * (5 - i) + cast(u16) result[][1] * i) / 5)
        result[][6] = 0
        result[][7] = 255
    }
}

#[Swag.Inline]
func alphaIndex(source: const [*] u8, pixel: u32)->u8
{
    var bits = 0'u64
    for i in 6 do
        bits |= cast(u64) source[2 + i] << (i * 8)
    return cast(u8) ((bits >> (pixel * 3)) & 7)
}

func storePixel(image: *Image, x, sourceY: s32, color: Color, sourceTopDown: bool)
{
    if x >= image.width or sourceY >= image.height do
        return
    let targetY = sourceTopDown ? image.height - sourceY - 1 : sourceY
    let target  = image.pixels.buffer! + cast(u64) targetY * image.rowStride + cast(u64) x * 4
    target[0] = color.r
    target[1] = color.g
    target[2] = color.b
    target[3] = color.a
}

internal func decode(image: *Image, source: const [..] u8, format: Format, sourceTopDown = true) fail
{
    let columns  = cast(u64) (image.width + 3) / 4
    let rows     = cast(u64) (image.height + 3) / 4
    let oneBlock = blockBytes(format)
    if columns > Swag.U64.Max / rows or columns * rows > source.count / oneBlock do
        fail InvalidFormatError{"block-compressed texture data is truncated"}

    var offset = 0'u64
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
            if format == .BC2 do
                colorBlock += 8
            elif format == .BC3
            {
                alphaPalette(&alpha, block)
                colorBlock += 8
            }
            elif format == .BC4 do
                alphaPalette(&red, block)
            elif format == .BC5
            {
                alphaPalette(&red, block)
                alphaPalette(&green, block + 8)
            }

            var indices = 0'u32
            if format == .BC1 or format == .BC2 or format == .BC3
            {
                let color0 = readU16(colorBlock)
                let color1 = readU16(colorBlock + 2)
                colorPalette(&colors, color0, color1, format != .BC1)
                indices = readU32(colorBlock + 4)
            }

            for pixel in 16'u32
            {
                let x = cast(s32) (blockX * 4 + pixel % 4)
                let y = cast(s32) (blockY * 4 + pixel / 4)
                var color: Color
                if format == .BC4
                {
                    let value = red[alphaIndex(block, pixel)]
                    color = Color.fromRgb(value, value, value)
                }
                elif format == .BC5
                {
                    color = Color.fromRgb(red[alphaIndex(block, pixel)], green[alphaIndex(block + 8, pixel)], 0)
                }
                else
                {
                    color = colors[(indices >> (pixel * 2)) & 3]
                    if format == .BC2 do
                        color.a = cast(u8) (((readU16(block + cast(u64) (pixel / 4) * 2) >> ((pixel & 3) * 4)) & 15) * 17)
                    elif format == .BC3 do
                        color.a = alpha[alphaIndex(block, pixel)]
                }

                storePixel(image, x, y, color, sourceTopDown)
            }

            offset += oneBlock
        }
    }
}
