#global public

using Core, Core.Errors, Pixel

private struct Nv12Rgb
{
    red:   s32
    green: s32
    blue:  s32
}

#[Swag.Inline]
private func nv12Rgb(pixel: const [*] u8, redIndex, blueIndex: u64)->Nv12Rgb
    =>
{pixel[redIndex], pixel[1], pixel[blueIndex]}

#[Swag.Inline]
private func nv12Luma(color: Nv12Rgb)->u8
    => cast #wrap(u8, 16 + (11_966 * color.red + 40_254 * color.green + 4_064 * color.blue + 32_768) / 65_536)

#[Swag.Inline]
private func nv12Chroma(value: s32)->u8
{
    let rounded = value >= 0 ? (value + 131_072) / 262_144 : -((-value + 131_072) / 262_144)
    return cast #wrap(u8, Math.clamp(128 + rounded, 0, 255))
}

#[Swag.Inline]
private func nv12BgraLuma(pixel: const [*] u8)->u8
    => cast #wrap(u8, 16 + (11_966 * cast(s32, pixel[2]) + 40_254 * cast(s32, pixel[1]) + 4_064 * cast(s32, pixel[0]) + 32_768) / 65_536)

private const Nv12BlueBytes  = cast(Math.Simd.U8x16, [0'u8, 4, 8, 12, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128])
private const Nv12GreenBytes = cast(Math.Simd.U8x16, [1'u8, 5, 9, 13, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128])
private const Nv12RedBytes   = cast(Math.Simd.U8x16, [2'u8, 6, 10, 14, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128])

#[Swag.Inline]
private func nv12BgraLuma4(pixels: const [*] u8)->Math.Simd.U8x16
{
    let packed = Math.Simd.load(pixels)
    let blue   = cast #bit(Math.Simd.S32x4, Math.Simd.widenLow(Math.Simd.widenLow(Math.Simd.shuffle(packed, Nv12BlueBytes))))
    let green  = cast #bit(Math.Simd.S32x4, Math.Simd.widenLow(Math.Simd.widenLow(Math.Simd.shuffle(packed, Nv12GreenBytes))))
    let red    = cast #bit(Math.Simd.S32x4, Math.Simd.widenLow(Math.Simd.widenLow(Math.Simd.shuffle(packed, Nv12RedBytes))))
    let luma   = 16 + ((red * 11_966 + green * 40_254 + blue * 4_064 + 32_768) >> 16)
    return Math.Simd.packUnsigned(Math.Simd.packSigned(luma, Math.Simd.splat(0's32)), Math.Simd.splat(0's16))
}

#[Swag.Inline]
private func nv12BgraChroma(top, bottom: const [*] u8, uv: [*] u8)
{
    let red   = cast(s32, top[2]) + cast(s32, top[6]) + cast(s32, bottom[2]) + cast(s32, bottom[6])
    let green = cast(s32, top[1]) + cast(s32, top[5]) + cast(s32, bottom[1]) + cast(s32, bottom[5])
    let blue  = cast(s32, top[0]) + cast(s32, top[4]) + cast(s32, bottom[0]) + cast(s32, bottom[4])
    uv[0] = nv12Chroma(-6_596 * red - 22_189 * green + 28_785 * blue)
    uv[1] = nv12Chroma(28_784 * red - 26_145 * green - 2_639 * blue)
}

// One pair of luma rows and its chroma row can be converted independently.
private func convertBgraNv12Band(source: const [*] u8, target: [*] u8, width, height, rowStride, lumaSize, blockY: u64)
{
    let topRow    = source + (height - 1 - blockY * 2) * rowStride
    let bottomRow = topRow - rowStride
    let topY      = target + blockY * 2 * width
    let bottomY   = topY + width
    let uvRow     = target + lumaSize + blockY * width
    for group in width / 4
    {
        let top    = topRow + group * 16
        let bottom = bottomRow + group * 16
        let x      = group * 4
        Math.Simd.storeLow4(topY + x, nv12BgraLuma4(top))
        Math.Simd.storeLow4(bottomY + x, nv12BgraLuma4(bottom))
        nv12BgraChroma(top, bottom, uvRow + x)
        nv12BgraChroma(top + 8, bottom + 8, uvRow + x + 2)
    }

    if width % 4
    {
        let top    = topRow + (width - 2) * 4
        let bottom = bottomRow + (width - 2) * 4
        topY[width - 2]    = nv12BgraLuma(top)
        topY[width - 1]    = nv12BgraLuma(top + 4)
        bottomY[width - 2] = nv12BgraLuma(bottom)
        bottomY[width - 1] = nv12BgraLuma(bottom + 4)
        nv12BgraChroma(top, bottom, uvRow + width - 2)
    }
}

// The screen readback path supplies BGRA8. Keep its channel positions constant in the hot loop.
private func convertBgraToNv12(source: const [*] u8, target: [*] u8, width, height, rowStride, lumaSize: u64)
{
    parallel for |source, target, width, height, rowStride, lumaSize| blockY in height / 2 do
        convertBgraNv12Band(source, target, width, height, rowStride, lumaSize, blockY)
}

// Owns one tightly packed NV12 picture for a video encoder.
//
// The first `width * height` bytes are top-down luma. The remainder is top-down interleaved
// Cb/Cr, with one pair for each two-by-two block. Rows use `width` bytes without padding.
// [[Video.Nv12Frame.convertFrom]] applies the BT.709 matrix and studio range (Y 16–235,
// chroma 16–240). Storage is reused when consecutive pictures have the same dimensions.
struct Nv12Frame
{
    public readonly
    {
        width:  s32          // Visible width; positive and even for a converted picture.
        height: s32          // Visible height; positive and even for a converted picture.
        bytes:  Array'u8     // Owned Y plane followed by interleaved Cb/Cr plane.
    }
}

impl Nv12Frame
{
    internal mtd copyPacked(width, height: s32, pixels: const [..] u8)
    {
        .width = width
        .height = height
        .bytes.clear()
        .bytes.add(pixels)
    }

    // Borrows the full-resolution luma plane until the next conversion or frame mutation.
    mtd const luma()->const [..] u8 => .bytes.toSlice()[until cast(u64, .width) * cast(u64, .height)]

    // Borrows the interleaved Cb/Cr plane until the next conversion or frame mutation.
    mtd const chroma()->const [..] u8 => .bytes.toSlice()[cast(u64, .width) * cast(u64, .height) until .bytes.count]

    // Converts a bottom-up packed image into top-down NV12 using the BT.709 studio range.
    //
    // Accepts RGB8, BGR8, RGBA8, and BGRA8; alpha is ignored. Width and height must be positive
    // and even. Invalid inputs leave the previous picture intact. Conversion keeps and reuses the
    // owned byte capacity when dimensions stay the same.
    mtd convertFrom(image: const *Image) fail
    {
        if image.width <= 0 or image.height <= 0 or image.width % 2 or image.height % 2 do
            fail BadParameterError{"NV12 conversion needs positive even image dimensions"}
        let format = image.pixelFormat
        if format != .RGB8 and format != .BGR8 and format != .RGBA8 and format != .BGRA8 do
            fail UnsupportedFormatError{"NV12 conversion needs packed 8-bit RGB pixels"}

        let width    = cast(u64, image.width)
        let height   = cast(u64, image.height)
        let lumaSize = width * height
        .bytes.resize(lumaSize + lumaSize / 2)
        .width  = image.width
        .height = image.height

        let source    = image.pixels.storage()
        let target    = .bytes.storage()
        let rowStride = cast(u64, image.rowStride)
        if format == .BGRA8
        {
            convertBgraToNv12(source, target, width, height, rowStride, lumaSize)
            return
        }
        let pixelSize = cast(u64, image.bytesPerPixel)
        let redIndex  = format == .BGR8 or format == .BGRA8 ? 2'u64 : 0'u64
        let blueIndex = 2 - redIndex
        for blockY in height / 2
        {
            let topRow    = source + (height - 1 - blockY * 2) * rowStride
            let bottomRow = topRow - rowStride
            for blockX in width / 2
            {
                let offset      = blockX * 2 * pixelSize
                let topLeft     = nv12Rgb(topRow + offset, redIndex, blueIndex)
                let topRight    = nv12Rgb(topRow + offset + pixelSize, redIndex, blueIndex)
                let bottomLeft  = nv12Rgb(bottomRow + offset, redIndex, blueIndex)
                let bottomRight = nv12Rgb(bottomRow + offset + pixelSize, redIndex, blueIndex)

                let y = blockY * 2 * width + blockX * 2
                target[y]             = nv12Luma(topLeft)
                target[y + 1]         = nv12Luma(topRight)
                target[y + width]     = nv12Luma(bottomLeft)
                target[y + width + 1] = nv12Luma(bottomRight)

                let red   = topLeft.red + topRight.red + bottomLeft.red + bottomRight.red
                let green = topLeft.green + topRight.green + bottomLeft.green + bottomRight.green
                let blue  = topLeft.blue + topRight.blue + bottomLeft.blue + bottomRight.blue
                let uv    = lumaSize + blockY * width + blockX * 2
                target[uv]     = nv12Chroma(-6_596 * red - 22_189 * green + 28_785 * blue)
                target[uv + 1] = nv12Chroma(28_784 * red - 26_145 * green - 2_639 * blue)
            }
        }
    }
}
