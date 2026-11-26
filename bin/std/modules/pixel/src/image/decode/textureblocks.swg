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
    case .None:            unreachable
    case .BC1, .BC4:       return 8
    case .BC2, .BC3, .BC5: return 16
    }
}

#[Swag.Inline]
func readU16(source: const [*] u8)->u16 => cast(u16, source[0]) | (cast(u16, source[1]) << 8)

#[Swag.Inline]
func readU32(source: const [*] u8)->u32
{
    return cast(u32, source[0]) |
           (cast(u32, source[1]) << 8) |
           (cast(u32, source[2]) << 16) |
           (cast(u32, source[3]) << 24)
}

#[Swag.Inline]
func expand5(value: u16)->u8 => cast(u8, ((value << 3) | (value >> 2)))

#[Swag.Inline]
func expand6(value: u16)->u8 => cast(u8, ((value << 2) | (value >> 4)))

func colorPalette(result: *[4] Color, color0, color1: u16, forceFourColors: bool)
{
    result[][0] = Color.fromRgb(expand5((color0 >> 11) & 31), expand6((color0 >> 5) & 63), expand5(color0 & 31))
    result[][1] = Color.fromRgb(expand5((color1 >> 11) & 31), expand6((color1 >> 5) & 63), expand5(color1 & 31))
    if color0 > color1 or forceFourColors
    {
        result[][2] = Color.fromRgb(cast(u8, ((cast(u16, result[][0].r) * 2 + result[][1].r) / 3)),
                                    cast(u8, ((cast(u16, result[][0].g) * 2 + result[][1].g) / 3)),
                                    cast(u8, ((cast(u16, result[][0].b) * 2 + result[][1].b) / 3)))
        result[][3] = Color.fromRgb(cast(u8, ((cast(u16, result[][0].r) + cast(u16, result[][1].r) * 2) / 3)),
                                    cast(u8, ((cast(u16, result[][0].g) + cast(u16, result[][1].g) * 2) / 3)),
                                    cast(u8, ((cast(u16, result[][0].b) + cast(u16, result[][1].b) * 2) / 3)))
    }
    else
    {
        result[][2] = Color.fromRgb(cast(u8, ((cast(u16, result[][0].r) + result[][1].r) / 2)),
                                    cast(u8, ((cast(u16, result[][0].g) + result[][1].g) / 2)),
                                    cast(u8, ((cast(u16, result[][0].b) + result[][1].b) / 2)))
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
            result[][i + 1] = cast(u8, ((cast(u16, result[][0]) * (7 - i) + cast(u16, result[][1]) * i) / 7))
    }
    else
    {
        for i in rangeTo(1, 4) do
            result[][i + 1] = cast(u8, ((cast(u16, result[][0]) * (5 - i) + cast(u16, result[][1]) * i) / 5))
        result[][6] = 0
        result[][7] = 255
    }
}

#[Swag.Inline]
func readAlphaIndices(source: const [*] u8)->u64 => cast(u64, readU32(source + 2)) | (cast(u64, readU16(source + 6)) << 32)

#[Swag.Inline]
func packRgba(color: Color)->u32
{
    return cast(u32, color.r) |
           (cast(u32, color.g) << 8) |
           (cast(u32, color.b) << 16) |
           (cast(u32, color.a) << 24)
}

func(FMT: Format) decodeBlocks(image: *Image, source: const [*] u8, columns, rows, oneBlock: u64, sourceTopDown: bool)
{
    let width  = cast(u64, image.width)
    let height = cast(u64, image.height)
    for blockY in rows
    {
        let firstY    = blockY * 4
        let countY    = Math.min(4'u64, height - firstY)
        let sourceRow = source + blockY * columns * oneBlock
        for blockX in columns
        {
            let firstX = blockX * 4
            let countX = Math.min(4'u64, width - firstX)
            let block  = sourceRow + blockX * oneBlock

            var colors:                      [4] u32
            var firstPalette, secondPalette: [8] u8
            var firstIndices, secondIndices: u64
            var colorIndices:                u32
            #static if FMT == .BC1 or FMT == .BC2 or FMT == .BC3
            {
                let colorBlock = FMT == .BC1 ? block : block + 8
                var palette: [4] Color
                colorPalette(&palette, readU16(colorBlock), readU16(colorBlock + 2), FMT != .BC1)
                for i in 4 do
                    colors[i] = packRgba(palette[i])
                colorIndices = readU32(colorBlock + 4)
            }

            #static if FMT == .BC2
            {
                firstIndices = cast(u64, readU32(block)) | (cast(u64, readU32(block + 4)) << 32)
            }
            elif FMT == .BC3 or FMT == .BC4 or FMT == .BC5
            {
                alphaPalette(&firstPalette, block)
                firstIndices = readAlphaIndices(block)
            }

            #static if FMT == .BC5
            {
                alphaPalette(&secondPalette, block + 8)
                secondIndices = readAlphaIndices(block + 8)
            }

            // Clip partial blocks once and write each visible row as packed RGBA words.
            for row in countY
            {
                let sourceY = firstY + row
                let targetY = sourceTopDown ? height - sourceY - 1 : sourceY
                let target  = cast([*] u32, image.pixels.storage() + targetY * image.rowStride) + firstX
                for column in countX
                {
                    let pixel = row * 4 + column
                    #static if FMT == .BC4
                    {
                        let value = cast(u32, firstPalette[(firstIndices >> (pixel * 3)) & 7])
                        target[column] = 0xFF000000 | (value * 0x010101)
                    }
                    elif FMT == .BC5
                    {
                        let red   = cast(u32, firstPalette[(firstIndices >> (pixel * 3)) & 7])
                        let green = cast(u32, secondPalette[(secondIndices >> (pixel * 3)) & 7])
                        target[column] = 0xFF000000 | red | (green << 8)
                    }
                    else
                    {
                        let rgb = colors[(colorIndices >> (pixel * 2)) & 3]
                        #static if FMT == .BC2
                        {
                            let alpha = cast(u32, ((firstIndices >> (pixel * 4)) & 15)) * 17
                            target[column] = (rgb & 0x00FFFFFF) | (alpha << 24)
                        }
                        elif FMT == .BC3
                        {
                            let alpha = cast(u32, firstPalette[(firstIndices >> (pixel * 3)) & 7])
                            target[column] = (rgb & 0x00FFFFFF) | (alpha << 24)
                        }
                        else
                        {
                            target[column] = rgb
                        }
                    }
                }
            }
        }
    }
}

internal func decode(image: *Image, source: const [..] u8, format: Format, sourceTopDown = true) fail
{
    let columns  = (cast(u64, image.width) + 3) / 4
    let rows     = (cast(u64, image.height) + 3) / 4
    let oneBlock = blockBytes(format)
    if columns > Swag.U64.Max / rows or columns * rows > source.count / oneBlock do
        fail InvalidFormatError{"block-compressed texture data is truncated"}

    switch #complete format
    {
    case .None: unreachable
    case .BC1:  decodeBlocks'(.BC1)(image, source.buffer, columns, rows, oneBlock, sourceTopDown)
    case .BC2:  decodeBlocks'(.BC2)(image, source.buffer, columns, rows, oneBlock, sourceTopDown)
    case .BC3:  decodeBlocks'(.BC3)(image, source.buffer, columns, rows, oneBlock, sourceTopDown)
    case .BC4:  decodeBlocks'(.BC4)(image, source.buffer, columns, rows, oneBlock, sourceTopDown)
    case .BC5:  decodeBlocks'(.BC5)(image, source.buffer, columns, rows, oneBlock, sourceTopDown)
    }
}
