/*
    :LICENCE
    This code is based on the libspng library by Randy (https://libspng.org/)
    The original code has been modified for Swag
    See LICENCE.md for the corresponding licence.
*/

#global namespace Png

using Core, Core.Errors

func filterUpRow(source, previous: const [*] u8, destination: [*] u8, count: u64)
{
    const VectorBytes = #sizeof(Math.Simd.U8x16)
    const BatchBytes  = 4 * VectorBytes
    var offset = 0'u64
    while count - offset >= BatchBytes
    {
        Math.Simd.store(destination + offset, Math.Simd.load(source + offset) - Math.Simd.load(previous + offset))
        Math.Simd.store(destination + offset + VectorBytes, Math.Simd.load(source + offset + VectorBytes) - Math.Simd.load(previous + offset + VectorBytes))
        Math.Simd.store(destination + offset + 2 * VectorBytes, Math.Simd.load(source + offset + 2 * VectorBytes) - Math.Simd.load(previous + offset + 2 * VectorBytes))
        Math.Simd.store(destination + offset + 3 * VectorBytes, Math.Simd.load(source + offset + 3 * VectorBytes) - Math.Simd.load(previous + offset + 3 * VectorBytes))
        offset += BatchBytes
    }

    while count - offset >= VectorBytes
    {
        Math.Simd.store(destination + offset, Math.Simd.load(source + offset) - Math.Simd.load(previous + offset))
        offset += VectorBytes
    }

    while offset < count
    {
        destination[offset] = cast #bit(u8) (source[offset] - #wrap previous[offset])
        offset              += 1
    }
}

func filterSubRow(source: const [*] u8, destination: [*] u8, count, bytesPerPixel: u64)
{
    const VectorBytes = #sizeof(Math.Simd.U8x16)
    const BatchBytes  = 4 * VectorBytes
    var offset = 0'u64
    while offset < bytesPerPixel and offset < count
    {
        destination[offset] = source[offset]
        offset              += 1
    }

    while count - offset >= BatchBytes
    {
        Math.Simd.store(destination + offset, Math.Simd.load(source + offset) - Math.Simd.load(source + offset - bytesPerPixel))
        Math.Simd.store(destination + offset + VectorBytes, Math.Simd.load(source + offset + VectorBytes) - Math.Simd.load(source + offset + VectorBytes - bytesPerPixel))
        Math.Simd.store(destination + offset + 2 * VectorBytes, Math.Simd.load(source + offset + 2 * VectorBytes) - Math.Simd.load(source + offset + 2 * VectorBytes - bytesPerPixel))
        Math.Simd.store(destination + offset + 3 * VectorBytes, Math.Simd.load(source + offset + 3 * VectorBytes) - Math.Simd.load(source + offset + 3 * VectorBytes - bytesPerPixel))
        offset += BatchBytes
    }

    while count - offset >= VectorBytes
    {
        Math.Simd.store(destination + offset, Math.Simd.load(source + offset) - Math.Simd.load(source + offset - bytesPerPixel))
        offset += VectorBytes
    }

    while offset < count
    {
        destination[offset] = cast #bit(u8) (source[offset] - #wrap source[offset - bytesPerPixel])
        offset              += 1
    }
}

func filterSumIndependent(source, previous: const [*] u8, count: u64, up: bool)->s32
{
    let bias   = Math.Simd.splat(128's16)
    let ones   = Math.Simd.splat(1's16)
    var sum    = 0's32
    var offset = 0'u64
    if up
    {
        while count - offset >= 16
        {
            let sourceBytes   = Math.Simd.load(source + offset)
            let previousBytes = Math.Simd.load(previous + offset)
            let lowValues     = cast #bit(Math.Simd.S16x8) Math.Simd.widenLow(sourceBytes) - cast #bit(Math.Simd.S16x8) Math.Simd.widenLow(previousBytes)
            let highValues    = cast #bit(Math.Simd.S16x8) Math.Simd.widenHigh(sourceBytes) - cast #bit(Math.Simd.S16x8) Math.Simd.widenHigh(previousBytes)
            let lowScores     = bias - Math.abs(lowValues - bias)
            let highScores    = bias - Math.abs(highValues - bias)
            sum    += Math.Simd.sum(Math.Simd.mulAddPairs(lowScores, ones))
            sum    += Math.Simd.sum(Math.Simd.mulAddPairs(highScores, ones))
            offset += 16
        }
    }
    else
    {
        while count - offset >= 16
        {
            let sourceBytes = Math.Simd.load(source + offset)
            let lowValues   = cast #bit(Math.Simd.S16x8) Math.Simd.widenLow(sourceBytes)
            let highValues  = cast #bit(Math.Simd.S16x8) Math.Simd.widenHigh(sourceBytes)
            let lowScores   = bias - Math.abs(lowValues - bias)
            let highScores  = bias - Math.abs(highValues - bias)
            sum    += Math.Simd.sum(Math.Simd.mulAddPairs(lowScores, ones))
            sum    += Math.Simd.sum(Math.Simd.mulAddPairs(highScores, ones))
            offset += 16
        }
    }

    while offset < count
    {
        var value = cast(s32) source[offset]
        if up do
            value -= previous[offset]
        sum    += 128 - Math.abs(value - 128)
        offset += 1
    }

    return sum
}

func filterSumSub(source: const [*] u8, count, bytesPerPixel: u64)->s32
{
    let prefix = Math.min(count, bytesPerPixel)
    var sum    = 0's32
    for i in prefix
    {
        let value = cast(s32) source[i]
        sum += 128 - Math.abs(value - 128)
    }

    if count > prefix do
        sum += filterSumIndependent(source + prefix, source + prefix - bytesPerPixel, count - prefix, true)
    return sum
}

func filterAverageRow(source, previous: const [*] u8, destination: [*] u8, count, bytesPerPixel: u64)
{
    const VectorBytes = #sizeof(Math.Simd.U8x16)
    const BatchBytes  = 4 * VectorBytes
    var offset = 0'u64
    while offset < bytesPerPixel and offset < count
    {
        let average = cast(u16) previous[offset] / 2
        destination[offset] = cast #bit(u8) (source[offset] - #wrap average)
        offset              += 1
    }

    while count - offset >= BatchBytes
    {
        for batch in 4
        {
            let index   = offset + batch * VectorBytes
            let left    = Math.Simd.load(source + index - bytesPerPixel)
            let up      = Math.Simd.load(previous + index)
            let average = Math.Simd.average(left, up) - ((left ^ up) & 1'u8)
            Math.Simd.store(destination + index, Math.Simd.load(source + index) - average)
        }

        offset += BatchBytes
    }

    while count - offset >= VectorBytes
    {
        let left    = Math.Simd.load(source + offset - bytesPerPixel)
        let up      = Math.Simd.load(previous + offset)
        let average = Math.Simd.average(left, up) - ((left ^ up) & 1'u8)
        Math.Simd.store(destination + offset, Math.Simd.load(source + offset) - average)
        offset += VectorBytes
    }

    while offset < count
    {
        let average = (cast(u16) source[offset - bytesPerPixel] + previous[offset]) / 2
        destination[offset] = cast #bit(u8) (source[offset] - #wrap average)
        offset              += 1
    }
}

func filterSumAverage(source, previous: const [*] u8, count, bytesPerPixel: u64)->s32
{
    let bias   = Math.Simd.splat(128's16)
    let ones   = Math.Simd.splat(1's16)
    let prefix = Math.min(count, bytesPerPixel)
    var sum    = 0's32
    for i in prefix
    {
        let average = cast(s32) previous[i] / 2
        let value   = cast(s32) source[i] - average
        sum += 128 - Math.abs(value - 128)
    }

    var offset = prefix
    while count - offset >= 16
    {
        let sourceBytes = Math.Simd.load(source + offset)
        let left        = Math.Simd.load(source + offset - bytesPerPixel)
        let up          = Math.Simd.load(previous + offset)
        let average     = Math.Simd.average(left, up) - ((left ^ up) & 1'u8)
        let lowValues   = cast #bit(Math.Simd.S16x8) Math.Simd.widenLow(sourceBytes) - cast #bit(Math.Simd.S16x8) Math.Simd.widenLow(average)
        let highValues  = cast #bit(Math.Simd.S16x8) Math.Simd.widenHigh(sourceBytes) - cast #bit(Math.Simd.S16x8) Math.Simd.widenHigh(average)
        let lowScores   = bias - Math.abs(lowValues - bias)
        let highScores  = bias - Math.abs(highValues - bias)
        sum    += Math.Simd.sum(Math.Simd.mulAddPairs(lowScores, ones))
        sum    += Math.Simd.sum(Math.Simd.mulAddPairs(highScores, ones))
        offset += 16
    }

    while offset < count
    {
        let average = (cast(s32) source[offset - bytesPerPixel] + previous[offset]) / 2
        let value   = cast(s32) source[offset] - average
        sum    += 128 - Math.abs(value - 128)
        offset += 1
    }

    return sum
}

impl Encoder
{
    mtd getBestFilter(size: u32)->Filter
    {
        if .encodeFlags.filterChoice == .Disabled do
            return .None

        let chl = cast(s32) .encodeFlags.filterChoice
        if !(chl & (chl - 1))
        {
            for i in 5
            {
                if chl == 1 << (i + 3) do
                    return cast() i
            }
        }

        var bestFilter   = 0
        var bestScore    = Swag.S32.Max
        var filterScores = [Swag.S32.Max, Swag.S32.Max, Swag.S32.Max, Swag.S32.Max, Swag.S32.Max]

        var sum: s32
        for i in 5
        {
            let flag = 1 << (i + 3)
            if !(chl & flag) do
                continue

            sum             = .filterSum(size, cast(Filter) i)
            filterScores[i] = Math.abs(sum)
            if filterScores[i] < bestScore
            {
                bestScore  = filterScores[i]
                bestFilter = i
            }
        }

        return cast() bestFilter
    }

    func paeth(a, b, c: s32)->s32
    {
        let p  = cast(s16) (a + b - c)
        let pa = Math.abs(cast(s16) (p - a))
        let pb = Math.abs(cast(s16) (p - b))
        let pc = Math.abs(cast(s16) (p - c))

        if pa <= pb and pa <= pc do
            return a
        elif pb <= pc do
            return b
        return c
    }

    mtd filterSum(size: u32, filter: Filter)->s32
    {
        if size > Swag.S32.Max / 128 do
            return Swag.S32.Max

        var sum:     s32
        var a, b, c: s32

        let scanline     = .scanline!
        let prevScanline = .prevScanline!
        if filter == .None do
            return filterSumIndependent(scanline, prevScanline, size, false)
        if filter == .Sub do
            return filterSumSub(scanline, size, .bytesPerPixel)
        if filter == .Up do
            return filterSumIndependent(scanline, prevScanline, size, true)
        if filter == .Average do
            return filterSumAverage(scanline, prevScanline, size, .bytesPerPixel)

        for i in size
        {
            if i >= .bytesPerPixel
            {
                a = scanline[i - .bytesPerPixel]
                b = prevScanline[i]
                c = prevScanline[i - .bytesPerPixel]
            }
            else
            {
                a = 0
                b = prevScanline[i]
                c = 0
            }

            var x = cast(s32) scanline[i]

            switch filter
            {
            case .None:
                break

            case .Sub:
                x = x - a

            case .Up:
                x = x - b

            case .Average:
                let avg = (a + b) / 2
                x = x - avg

            case .Paeth:
                x = x - paeth(a, b, c)
            }

            sum += 128 - Math.abs(x - 128)
        }

        return sum
    }

    mtd filterScanline(filtered: [*] u8, size: u32, filter: Filter)
    {
        let scanline     = .scanline!
        let prevScanline = .prevScanline!
        if filter == .Sub
        {
            filterSubRow(scanline, filtered, size, .bytesPerPixel)
            return
        }

        if filter == .Up
        {
            filterUpRow(scanline, prevScanline, filtered, size)
            return
        }

        if filter == .Average
        {
            filterAverageRow(scanline, prevScanline, filtered, size, .bytesPerPixel)
            return
        }

        for i in size
        {
            var a, b, c: s32
            if i >= .bytesPerPixel
            {
                a = scanline[i - .bytesPerPixel]
                b = prevScanline[i]
                c = prevScanline[i - .bytesPerPixel]
            }
            else
            {
                a = 0
                b = prevScanline[i]
                c = 0
            }

            var x = cast(s32) scanline[i]

            switch filter
            {
            case .Sub:
                x = x - a

            case .Up:
                unreachable

            case .Average:
                let avg = (a + b) / 2
                x = x - avg

            case .Paeth:
                x = x - paeth(a, b, c)
            }

            filtered[i] = cast #bit (u8) x
        }
    }
}
