//! Format: Portable Network Graphics (PNG) encoder component.
//! Supported: 8-bit grayscale and RGB/BGR images with optional alpha, PNG filters, Deflate compression, and optional Adam7 interlacing.
//! Not supported: APNG animation, palette generation, and non-8-bit output.
//! Role: This file owns PNG encoder filter selection.
//
// @LICENCE: BSD-2-Clause
// @ORIGIN: libspng, https://github.com/randy408/libspng
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#libspng

#global namespace Png

using Core, Core.Errors

// Scores one filtered byte: the closer to zero it encodes, the cheaper Deflate stores it.
//
// PNG writes the residual as a byte, so the score is read off that wrapped value and is never
// negative. Scoring the signed difference instead lets a noisy row cancel itself out and score
// as well as a flat one, which is how a bad filter gets chosen.
#[Swag.Inline]
func residualScore(value: u8)->s32 => 128 - Math.abs(cast(s32) value - 128)

// Folds the scores of sixteen filtered bytes into a running total.
//
// '128 - |b - 128|' is 'min(b, -b)' in byte arithmetic, so the whole score stays in eight-bit
// lanes and the two widened halves add without leaving 's16'. Keeping the total packed is what
// matters: reducing to a scalar on every step would put a horizontal add, and the scalar
// dependency behind it, on the loop's critical path.
#[Swag.Inline]
func accumulateResidual(total: Math.Simd.S32x4, residual: Math.Simd.U8x16, ones: Math.Simd.S16x8)->Math.Simd.S32x4
{
    let score  = Math.min(residual, Math.Simd.splat(0'u8) - residual)
    let halves = cast #bit(Math.Simd.S16x8) Math.Simd.widenLow(score) + cast #bit(Math.Simd.S16x8) Math.Simd.widenHigh(score)
    return total + Math.Simd.mulAddPairs(halves, ones)
}

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

// Scores the None filter, or the Up filter when 'up' is set.
//
// Both read their predictor straight out of memory, which is what lets one loop serve them.
func filterSumIndependent(source, previous: const [*] u8, count: u64, up: bool)->s32
{
    let ones   = Math.Simd.splat(1's16)
    var total  = Math.Simd.splat(0's32)
    var offset = 0'u64
    if up
    {
        while count - offset >= 16
        {
            total  = accumulateResidual(total, Math.Simd.load(source + offset) - Math.Simd.load(previous + offset), ones)
            offset += 16
        }
    }
    else
    {
        while count - offset >= 16
        {
            total  = accumulateResidual(total, Math.Simd.load(source + offset), ones)
            offset += 16
        }
    }

    var sum = Math.Simd.sum(total)
    while offset < count
    {
        var residual = source[offset]
        if up do
            residual = cast #bit(u8) (residual - #wrap previous[offset])
        sum    += residualScore(residual)
        offset += 1
    }

    return sum
}

func filterSumSub(source: const [*] u8, count, bytesPerPixel: u64)->s32
{
    let prefix = Math.min(count, bytesPerPixel)
    var sum    = 0's32
    for i in prefix do
        sum += residualScore(source[i])

    if count > prefix do
        sum += filterSumIndependent(source + prefix, source + prefix - bytesPerPixel, count - prefix, true)
    return sum
}

// Averages the left and up bytes downward, the way the PNG predictor defines it.
//
// 'average' rounds up, so the carry has to come back out; both operands are bytes, so the
// correction is exactly the low bit of their difference.
#[Swag.Inline]
func averagePredictor(left, up: Math.Simd.U8x16)->Math.Simd.U8x16 => Math.Simd.average(left, up) - ((left ^ up) & 1'u8)

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
            let average = averagePredictor(Math.Simd.load(source + index - bytesPerPixel), Math.Simd.load(previous + index))
            Math.Simd.store(destination + index, Math.Simd.load(source + index) - average)
        }

        offset += BatchBytes
    }

    while count - offset >= VectorBytes
    {
        let average = averagePredictor(Math.Simd.load(source + offset - bytesPerPixel), Math.Simd.load(previous + offset))
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
    let ones   = Math.Simd.splat(1's16)
    let prefix = Math.min(count, bytesPerPixel)
    var sum    = 0's32
    for i in prefix
    {
        let average = cast(u8) (cast(u16) previous[i] / 2)
        sum += residualScore(cast #bit(u8) (source[i] - #wrap average))
    }

    var total  = Math.Simd.splat(0's32)
    var offset = prefix
    while count - offset >= 16
    {
        let average = averagePredictor(Math.Simd.load(source + offset - bytesPerPixel), Math.Simd.load(previous + offset))
        total  = accumulateResidual(total, Math.Simd.load(source + offset) - average, ones)
        offset += 16
    }

    sum += Math.Simd.sum(total)
    while offset < count
    {
        let average = cast(u8) ((cast(u16) source[offset - bytesPerPixel] + previous[offset]) / 2)
        sum    += residualScore(cast #bit(u8) (source[offset] - #wrap average))
        offset += 1
    }

    return sum
}

func paethScalar(a, b, c: s32)->s32
{
    let p  = cast(s16) (a + b - c)
    let pa = Math.abs(cast(s16) (p - a))
    let pb = Math.abs(cast(s16) (p - b))
    let pc = Math.abs(cast(s16) (p - c))

    if pa <= pb and pa <= pc do
        return a
    if pb <= pc do
        return b
    return c
}

#[Swag.Inline]
func paethPacked(a, b, c: Math.Simd.S16x8)->Math.Simd.S16x8
{
    let p     = a + b - c
    let pa    = Math.abs(p - a)
    let pb    = Math.abs(p - b)
    let pc    = Math.abs(p - c)
    let bestB = Math.Simd.select(pb <= pc, b, c)
    return Math.Simd.select((pa <= pb) & (pa <= pc), a, bestB)
}

// Computes the Paeth predictor of sixteen bytes, in byte lanes.
//
// The comparisons need sixteen-bit lanes, but the predictor is always one of the three
// neighbouring bytes, so narrowing the two halves back is exact and never saturates.
#[Swag.Inline]
func paethPredictorBytes(left, up, upLeft: Math.Simd.U8x16)->Math.Simd.U8x16
{
    let lowPredictor = paethPacked(cast #bit(Math.Simd.S16x8) Math.Simd.widenLow(left),
                                   cast #bit(Math.Simd.S16x8) Math.Simd.widenLow(up),
                                   cast #bit(Math.Simd.S16x8) Math.Simd.widenLow(upLeft))
    let highPredictor = paethPacked(cast #bit(Math.Simd.S16x8) Math.Simd.widenHigh(left),
                                    cast #bit(Math.Simd.S16x8) Math.Simd.widenHigh(up),
                                    cast #bit(Math.Simd.S16x8) Math.Simd.widenHigh(upLeft))
    return Math.Simd.packUnsigned(lowPredictor, highPredictor)
}

func filterPaethRow(source, previous: const [*] u8, destination: [*] u8, count, bytesPerPixel: u64)
{
    var offset = 0'u64
    while offset < bytesPerPixel and offset < count
    {
        destination[offset] = cast #bit(u8) (source[offset] - #wrap previous[offset])
        offset              += 1
    }

    while count - offset >= 16
    {
        let predictor = paethPredictorBytes(Math.Simd.load(source + offset - bytesPerPixel), Math.Simd.load(previous + offset), Math.Simd.load(previous + offset - bytesPerPixel))
        Math.Simd.store(destination + offset, Math.Simd.load(source + offset) - predictor)
        offset += 16
    }

    while offset < count
    {
        let predictor = paethScalar(source[offset - bytesPerPixel], previous[offset], previous[offset - bytesPerPixel])
        destination[offset] = cast #bit(u8) (source[offset] - #wrap predictor)
        offset              += 1
    }
}

func filterSumPaeth(source, previous: const [*] u8, count, bytesPerPixel: u64)->s32
{
    let ones   = Math.Simd.splat(1's16)
    let prefix = Math.min(count, bytesPerPixel)
    var sum    = 0's32
    for i in prefix do
        sum += residualScore(cast #bit(u8) (source[i] - #wrap previous[i]))

    var total  = Math.Simd.splat(0's32)
    var offset = prefix
    while count - offset >= 16
    {
        let predictor = paethPredictorBytes(Math.Simd.load(source + offset - bytesPerPixel), Math.Simd.load(previous + offset), Math.Simd.load(previous + offset - bytesPerPixel))
        total  = accumulateResidual(total, Math.Simd.load(source + offset) - predictor, ones)
        offset += 16
    }

    sum += Math.Simd.sum(total)
    while offset < count
    {
        let predictor = paethScalar(source[offset - bytesPerPixel], previous[offset], previous[offset - bytesPerPixel])
        sum    += residualScore(cast #bit(u8) (source[offset] - #wrap cast(u8) predictor))
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

        var bestFilter = 0
        var bestScore  = Swag.S32.Max
        for i in 5
        {
            let flag = 1 << (i + 3)
            if !(chl & flag) do
                continue

            let score = .filterSum(size, cast(Filter) i)
            if score < bestScore
            {
                bestScore  = score
                bestFilter = i
            }
        }

        return cast() bestFilter
    }

    mtd filterSum(size: u32, filter: Filter)->s32
    {
        // A row this wide could overflow the running total, so refuse it instead of scoring it.
        if size > Swag.S32.Max / 128 do
            return Swag.S32.Max

        let scanline     = .scanline!
        let prevScanline = .prevScanline!
        switch #complete filter
        {
        case .None:    return filterSumIndependent(scanline, prevScanline, size, false)
        case .Sub:     return filterSumSub(scanline, size, .bytesPerPixel)
        case .Up:      return filterSumIndependent(scanline, prevScanline, size, true)
        case .Average: return filterSumAverage(scanline, prevScanline, size, .bytesPerPixel)
        case .Paeth:   return filterSumPaeth(scanline, prevScanline, size, .bytesPerPixel)
        }
    }

    mtd filterScanline(filtered: [*] u8, size: u32, filter: Filter)
    {
        let scanline     = .scanline!
        let prevScanline = .prevScanline!
        switch filter
        {
        case .None:    break
        case .Sub:     filterSubRow(scanline, filtered, size, .bytesPerPixel)
        case .Up:      filterUpRow(scanline, prevScanline, filtered, size)
        case .Average: filterAverageRow(scanline, prevScanline, filtered, size, .bytesPerPixel)
        case .Paeth:   filterPaethRow(scanline, prevScanline, filtered, size, .bytesPerPixel)
        }
    }
}
