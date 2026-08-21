#global namespace PackedPixel

using Core

private const ReverseBgr24 = cast(Math.Simd.U8x16) [13'u8, 14, 15, 10, 11, 12, 7, 8, 9, 4, 5, 6, 128, 128, 128, 128]
private const ReverseBgra32 = cast(Math.Simd.U8x16) [12'u8, 13, 14, 15, 8, 9, 10, 11, 4, 5, 6, 7, 0, 1, 2, 3]
private const RepeatBgr24 = cast(Math.Simd.U8x16) [0'u8, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 128, 128, 128, 128]

func fillBgr24Row(pixel: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    let packed  = cast(u32) pixel[0] | (cast(u32) pixel[1] << 8) | (cast(u32) pixel[2] << 16)
    let pattern = Math.Simd.shuffle(cast #bit(Math.Simd.U8x16) Math.Simd.splat(packed), RepeatBgr24)
    var x       = 0'u64
    while pixelCount - x >= 4
    {
        Image.storeLow12(destination + x * 3, pattern)
        x += 4
    }

    while x < pixelCount
    {
        let dstPixel = destination + x * 3
        dstPixel[0] = pixel[0]
        dstPixel[1] = pixel[1]
        dstPixel[2] = pixel[2]
        x           += 1
    }
}

func fillBgra32Row(pixel: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    let pattern = Math.Simd.splat(pixel[as u32])
    var x       = 0'u64
    while pixelCount - x >= 4
    {
        Math.Simd.store(cast([*] u32) destination + x, pattern)
        x += 4
    }

    while x < pixelCount
    {
        (cast([*] u32) destination)[x] = pixel[as u32]
        x += 1
    }
}

func reverseBgr24Row(source: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    var x = 0'u64
    while pixelCount - x >= 6
    {
        let srcBlock = source + (pixelCount - x - 4) * 3
        let pixels   = Math.Simd.load(srcBlock - 4)
        Image.storeLow12(destination + x * 3, Math.Simd.shuffle(pixels, ReverseBgr24))
        x += 4
    }

    while x < pixelCount
    {
        let srcPixel = source + (pixelCount - x - 1) * 3
        let dstPixel = destination + x * 3
        dstPixel[0] = srcPixel[0]
        dstPixel[1] = srcPixel[1]
        dstPixel[2] = srcPixel[2]
        x           += 1
    }
}

func reverseBgra32Row(source: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    var x = 0'u64
    while pixelCount - x >= 4
    {
        let srcBlock = source + (pixelCount - x - 4) * 4
        Math.Simd.store(destination + x * 4, Math.Simd.shuffle(Math.Simd.load(srcBlock), ReverseBgra32))
        x += 4
    }

    while x < pixelCount
    {
        (cast([*] u32) destination)[x] = (cast(const [*] u32) source)[pixelCount - x - 1]
        x += 1
    }
}
