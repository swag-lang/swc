//! Format: Opus CELT layer decoder.
//! Supported: The 48 kHz mode of RFC 6716 clause 4.3: coarse and fine energy, transient and time-frequency decisions, dynamic allocation, pyramid vector quantization with spreading and folding, intensity and dual stereo, anti-collapse, the overlapped MDCT with its short-block form, the pitch post-filter, and de-emphasis, for mono or stereo streams on mono or stereo outputs.
//! Not supported: Packet-loss concealment, custom modes, and the decoder-side filters a lost frame would need.
//! Role: This file owns CELT frame syntax, band reconstruction, the inverse transform, and the time-domain filters.
//
#global namespace Opus

using Core, Core.Errors, Core.Math

internal const CeltBandCount       = 21'u32
internal const CeltOverlap         = 120'u32
internal const CeltShortSize       = 120'u32
internal const CeltFrameMax        = 960'u32
private const CeltMaxLM            = 3'u32
private const CeltAllocVectors     = 11'u32
private const CeltPreemphasis      = 0.85000610'f32
private const CeltDecodeBuffer     = 2048'u32
private const CeltMdctSize         = 1920'u32
private const CeltFftMax           = 480'u32
private const MaxFineBits          = 8's32
private const FineOffset           = 21's32
private const QThetaOffset         = 4's32
private const QThetaOffsetTwoPhase = 16's32
private const AllocSteps           = 6'u32
private const LogMaxPseudo         = 6'u32
private const CombMinPeriod        = 15's32
private const CombMaxPeriod        = 1024'u32
private const SpreadNone           = 0'u32
private const SpreadAggressive     = 3'u32
private const LaplaceMinP          = 1'u32
private const LaplaceNMin          = 16'u32
private const NoiseFloor           = -28.0'f32

private const TrimIcdf:        [11] u8    = [126, 124, 119, 109, 87, 41, 19, 9, 4, 2, 0]
private const SpreadIcdf:      [4] u8     = [25, 23, 2, 0]
private const TapsetIcdf:      [3] u8     = [2, 1, 0]
private const SmallEnergyIcdf: [3] u8     = [2, 1, 0]
private const PredCoef:        [4] f32    = [29440.0 / 32768.0, 26112.0 / 32768.0, 21248.0 / 32768.0, 16384.0 / 32768.0]
private const BetaCoef:        [4] f32    = [30147.0 / 32768.0, 22282.0 / 32768.0, 12124.0 / 32768.0, 6554.0 / 32768.0]
private const BetaIntra = 4915.0'f32 / 32768.0'f32
private const CombGains:       [3, 3] f32 = [[0.3066406250, 0.2170410156, 0.1296386719], [0.4638671875, 0.2680664062, 0.0], [0.7998046875, 0.1000976562, 0.0]]
private const SpreadFactor:    [3] s32    = [15, 10, 5]
private const Exp2Table8:      [8] s32    = [16384, 17866, 19483, 21247, 23170, 25267, 27554, 30048]
private const BitInterleave:   [16] u32   = [0, 1, 1, 1, 2, 3, 3, 3, 2, 3, 3, 3, 2, 3, 3, 3]
private const BitDeinterleave: [16] u32   = [0x00, 0x03, 0x0C, 0x0F, 0x30, 0x33, 0x3C, 0x3F, 0xC0, 0xC3, 0xCC, 0xCF, 0xF0, 0xF3, 0xFC, 0xFF]

// The widest CELT band contains 22 bins in each of up to eight short blocks.
private const MaxPulseDimensions = 176'u32

private func pulseCount(pseudo: u32)->u32
    => pseudo < 8 ? pseudo : (8 + (pseudo & 7)) << ((pseudo >> 3) - 1)

// The bit-allocation cache bounds the pulse count for each starting band size.
private const PulseLimits: [MaxPulseDimensions + 1] u32 = #run
{
    var limits: [MaxPulseDimensions + 1] u32
    for base, i in CeltCacheIndex where base >= 0
    {
        let band       = i % CeltBandCount
        let dimensions = cast(u32, CeltBands[band + 1] - CeltBands[band]) << cast(u32, i / CeltBandCount) >> 1
        let maxPulses  = pulseCount(cast(u32, CeltCacheBits[cast(u32, base)]))
        limits[dimensions] = Math.max(limits[dimensions], maxPulses)
    }

    return limits
}

// A vector can only lose dimensions and pulses as it is reconstructed. Give
// each row room for every pulse count reachable from that dimension or above.
private const PulseLayout = #run
{
    var result: {offset: [MaxPulseDimensions + 1] u32, limit: [MaxPulseDimensions + 1] u32, count: u32}
    var maxPulses = 0'u32
    for i in PulseLimits.count
    {
        let dimensions = MaxPulseDimensions - cast(u32, i)
        maxPulses = Math.max(maxPulses, PulseLimits[dimensions])
        result.limit[dimensions] = maxPulses + 1     // Includes the sign threshold U(n,k+1).
    }

    for limit, dimensions in result.limit
    {
        result.offset[dimensions] = result.count
        result.count += limit + 1
    }

    return result
}

private const PulseArrangements: [PulseLayout.count] u32 = #run
{
    var table: [PulseLayout.count] u32
    table[0] = 1
    for n in 1 until PulseLayout.offset.count
    {
        let prior = PulseLayout.offset[n - 1]
        let base  = PulseLayout.offset[n]
        for k in 1 until PulseLayout.limit[n] + 1
        {
            let total = cast(u64, table[base + k - 1]) + table[prior + k] + table[prior + k - 1]
            table[base + k] = cast(u32, Math.min(total, cast(u64, Swag.U32.Max)))
        }
    }

    return table
}

#[Swag.Inline]
private func pulseArrangements(dimensions, pulses: u32)->u32
    => PulseArrangements[PulseLayout.offset[dimensions] + pulses]

// Complete, small codebooks for the four- and eight-bin tails.
// Each record packs five bits per signed coefficient and its squared norm.
private const PulseTailLimits: [9] u32 = [0, 0, 0, 0, 6, 0, 0, 0, 3]
private const PulseTailLayout = #run
{
    var result: {offset: [9, 7] u32, count: u32}

    // Zero is reserved for states that have no table.
    result.count = 1
    for limit, dimensions in PulseTailLimits where limit
    {
        for k in 2'u32 until limit + 1
        {
            result.offset[dimensions, k] = result.count
            result.count += pulseArrangements(cast(u32, dimensions), k) +
                            pulseArrangements(cast(u32, dimensions), k + 1)
        }
    }

    return result
}

private const PulseTails: [PulseTailLayout.count] u64 = #run
{
    var result: [PulseTailLayout.count] u64
    for limit, dimensions in PulseTailLimits where limit
    {
        for k in 2'u32 until limit + 1
        {
            let count = pulseArrangements(cast(u32, dimensions), k) + pulseArrangements(cast(u32, dimensions), k + 1)
            for rank in count
            {
                var index     = rank
                var remaining = k
                var code      = 0'u64
                var norm      = 0'u32
                for position in dimensions
                {
                    let n         = cast(u32, dimensions - position)
                    let threshold = pulseArrangements(n, remaining + 1)
                    let negative  = index >= threshold
                    if negative do
                        index -= threshold
                    let before = remaining
                    var offset = pulseArrangements(n, remaining)
                    while offset > index
                    {
                        remaining -= 1
                        offset    = pulseArrangements(n, remaining)
                    }

                    index -= offset
                    let value  = cast(s32, before - remaining)
                    let signed = negative ? -value : value
                    code |= cast(u64, signed + 16) << (5 * position)
                    norm += cast(u32, value * value)
                }

                result[PulseTailLayout.offset[dimensions, k] + rank] = code | (cast(u64, norm) << 40)
            }
        }
    }

    return result
}

#[Swag.Inline]
private func unpackPulseTail(code: u32)->Simd.F32x4
{
    const Place = cast(Simd.U32x4, [1'u32 << 27, 1'u32 << 22, 1'u32 << 17, 1'u32 << 12])

    // Place each biased integer into the mantissa of exactly 2^23, then remove both biases.
    let integers = (Simd.splat(code) * Place) >> 27
    return cast #bit(Simd.F32x4, (integers | 0x4B00_0000'u32)) - 8_388_624.0'f32
}

private const PulseChoiceRows = #run
{
    var result: {indices: [CeltCacheBits.count] u8, count: u32}
    var base = 0'u32
    while base < CeltCacheBits.count
    {
        result.indices[base] = cast(u8, result.count)
        result.count         += 1
        base                 += cast(u32, CeltCacheBits[base]) + 1
    }

    return result
}

// Map each possible requested eighth-bit budget to the nearest entry in its pulse cache.
private const PulseChoices: [PulseChoiceRows.count, 256] u8 = #run
{
    var choices: [PulseChoiceRows.count, 256] u8
    var base = 0'u32
    while base < CeltCacheBits.count
    {
        let row       = PulseChoiceRows.indices[base]
        let maxPseudo = cast(s32, CeltCacheBits[base])
        for budget in 256
        {
            let want = cast(s32, budget)
            var lo   = 0's32
            var hi   = maxPseudo
            for LogMaxPseudo
            {
                let mid = (lo + hi + 1) >> 1
                if cast(s32, CeltCacheBits[base + cast(u32, mid)]) >= want do
                    hi = mid
                else do
                    lo = mid
            }

            let below  = lo == 0 ? -1 : cast(s32, CeltCacheBits[base + cast(u32, lo)])
            let pseudo = want - below <= cast(s32, CeltCacheBits[base + cast(u32, hi)]) - want ? lo : hi
            choices[row, budget] = cast(u8, pseudo)
        }

        base += cast(u32, maxPseudo) + 1
    }

    return choices
}

// A rotation is used only when two times the pulse count is below the band dimension.
private const SpreadLayout = #run
{
    var result: {offset: [MaxPulseDimensions + 1] u32, limit: [MaxPulseDimensions + 1] u32, count: u32}
    for pulses, samples in PulseLimits where pulses do
        result.limit[samples] = Math.min(pulses, cast(u32, (samples - 1) / 2))

    for limit, samples in result.limit
    {
        result.offset[samples] = result.count
        result.count += limit
    }

    return result
}

private const SpreadRotations: [SpreadFactor.count, SpreadLayout.count, 2] f32 = #run
{
    var result: [SpreadFactor.count, SpreadLayout.count, 2] f32
    for limit, samples in SpreadLayout.limit
    {
        for k in 1 until limit + 1
        {
            let offset = SpreadLayout.offset[samples] + k - 1
            for factor, spread in SpreadFactor
            {
                let gain  = cast(f32, samples) / cast(f32, (cast(s32, samples) + factor * cast(s32, k)))
                let theta = 0.5 * gain * gain
                result[spread, offset, 0] = cast(f32, Math.cos(0.5 * Math.ConstF64.Pi * cast(f64, theta)))
                result[spread, offset, 1] = cast(f32, Math.cos(0.5 * Math.ConstF64.Pi * cast(f64, (1.0 - theta))))
            }
        }
    }

    return result
}

// The secondary rotation spans the smallest stride s with s*(s+1) at least the part width.
private const SpreadStride: [MaxPulseDimensions + 1] u8 = #run
{
    var result: [MaxPulseDimensions + 1] u8
    for part in 8 until result.count
    {
        var stride = 1'u32
        while stride * (stride + 1) < part do
            stride += 1
        result[part] = cast(u8, stride)
    }

    return result
}

private func celtExp2(x: f32)->f32  => cast(f32, Math.exp(0.6931471805599453 * cast(f64, x)))
private func celtLog2(x: f32)->f32  => cast(f32, (1.4426950408889634 * Math.log(cast(f64, x))))
private func celtRsqrt(x: f32)->f32 => cast(f32, (1.0 / Math.sqrt(cast(f64, x))))

#[Swag.Safety(.Overflow, false)]
private func lcgRand(seed: u32)->u32 => 1664525 * seed + 1013904223

// A cosine approximation shared with the encoder bit for bit, since it steers the allocation.
private func bitexactCos(x: s32)->s32
{
    let tmp = (4096 + x * x) >> 13
    var x2  = tmp
    x2 = (32767 - x2) + fracMul16(x2, -7651 + fracMul16(x2, 8277 + fracMul16(-626, x2)))
    return 1 + x2
}

private func fracMul16(a, b: s32)->s32 => (16384 + a * b) >> 15

private func bitexactLog2Tan(isin, icos: s32)->s32
{
    let lc = cast(s32, ilog(cast(u32, icos)))
    let ls = cast(s32, ilog(cast(u32, isin)))
    let c  = icos << cast(u32, (15 - lc))
    let s  = isin << cast(u32, (15 - ls))
    return (ls - lc) * (1 << 11) + fracMul16(s, fracMul16(s, -2597) + 7932) - fracMul16(c, fracMul16(c, -2597) + 7932)
}

private struct CodedTheta
{
    angle:  u16
    middle: u16
    side:   u16
    logTan: s16
}

// For qn = 2 * row, the preceding rows contain row * row - 1 coded angles.
private const CodedThetas: [129 * 129 - 1] CodedTheta = #run
{
    var table: [129 * 129 - 1] CodedTheta
    for row in 1's32 until 129
    {
        let base = row * row - 1
        let qn   = 2 * row
        for rank in 1 until qn
        {
            let angle  = rank * 16384 / qn
            let middle = bitexactCos(angle)
            let side   = bitexactCos(16384 - angle)
            table[base + rank] = {cast(u16, angle), cast(u16, middle), cast(u16, side), cast(s16, bitexactLog2Tan(side, middle))}
        }

        table[base + qn].angle = 16384
    }

    return table
}

// The f64 square root is precise enough to keep the integer floor for every u32.
private func isqrt32(value: u32)->u32 => cast(u32, Math.sqrt(cast(f64, value)))

private func laplaceFreq1(fs0, decay: u32)->u32
{
    let ft = 32768 - LaplaceMinP * (2 * LaplaceNMin) - fs0
    return (ft * (16384 - decay)) >> 15
}

private func laplaceDecode(dec: *RangeDecoder, fs0, decay: u32)->s32
{
    var value = 0's32
    var fl    = 0'u32
    var fs    = fs0
    let fm    = dec.decodeBinary(15)
    if fm >= fs
    {
        value += 1
        fl    = fs
        fs    = laplaceFreq1(fs, decay) + LaplaceMinP
        while fs > LaplaceMinP and fm >= fl + 2 * fs
        {
            fs    *= 2
            fl    += fs
            fs    = ((fs - 2 * LaplaceMinP) * decay) >> 15
            fs    += LaplaceMinP
            value += 1
        }

        if fs <= LaplaceMinP
        {
            let di = (fm - fl) >> 1
            value += cast(s32, di)
            fl    += 2 * di * LaplaceMinP
        }

        if fm < fl + fs do
            value = -value
        else do
            fl += fs
    }

    dec.update(fl, Math.min(fl + fs, 32768), 32768)
    return value
}

// The CELT FFT lengths are 15 times a power of two. Decimation in time puts all
// five-point butterflies first, then the three-point butterflies and the radix-two stages.
private struct CeltFft
{
    n:      u32
    cosine: Array'f32
    sine:   Array'f32
    order:  Array'u32
}

private impl CeltFft
{
    func create(n: u32)->CeltFft
    {
        var result: #returntype
        result.n = n
        result.cosine.resize(n)
        result.sine.resize(n)
        result.order.resize(n)

        let binarySize = n / 15
        for k in n
        {
            let angle = -2.0 * Math.ConstF64.Pi * cast(f64, k) / cast(f64, n)
            result.cosine[k] = cast(f32, Math.cos(angle))
            result.sine[k]   = cast(f32, Math.sin(angle))

            // Reverse the binary digits, then place the mixed-radix digits at the low end.
            var bits     = k % binarySize
            var reversed = 0'u32
            var width    = binarySize
            while width > 1
            {
                reversed = (reversed << 1) | (bits & 1)
                bits     >>= 1
                width    >>= 1
            }

            let mixed = k / binarySize
            result.order[k] = reversed * 15 + (mixed % 3) * 5 + mixed / 3
        }

        return result
    }

    // A packed point keeps its real and imaginary components in the first two lanes.
    // Multiplication by i exchanges the components and flips the new real component's sign.
    #[Swag.Inline]
    func quarterTurn(point: Simd.F32x4)->Simd.F32x4
    {
        const Swap = cast(Simd.U32x4, [1'u32, 0, 3, 2])
        const Sign = cast(Simd.U32x4, [0x8000_0000'u32, 0, 0x8000_0000, 0])
        let exchanged = Swag.vecShuffle(point, Swap)
        return cast #bit(Simd.F32x4, (cast #bit(Simd.U32x4, exchanged) ^ Sign))
    }

    #[Swag.Inline]
    func rotate(point: Simd.F32x4, cosine, sine: f32)->Simd.F32x4
        => point * cosine + quarterTurn(point) * sine

    // The input is already in the digit-reversed order stored in `.order`.
    mtd const transform(points: [*] Simd.F32x4)
    {
        const Cos72  = 0.30901699437494745'f32
        const Cos144 = -0.80901699437494734'f32
        const Sin72  = 0.95105651629515353'f32
        const Sin144 = 0.58778525229247324'f32
        const Sin120 = 0.86602540378443865'f32

        // Pair conjugate weights so the two outputs share each sum and difference.
        for group in .n / 5
        {
            let p      = points + group * 5
            let sum14  = p[1] + p[4]
            let sum23  = p[2] + p[3]
            let diff14 = p[1] - p[4]
            let diff23 = p[2] - p[3]
            let a      = p[0] + Cos72 * sum14 + Cos144 * sum23
            let b      = p[0] + Cos144 * sum14 + Cos72 * sum23
            let c      = Sin72 * diff14 + Sin144 * diff23
            let d      = Sin144 * diff14 - Sin72 * diff23
            let ci     = quarterTurn(c)
            let di     = quarterTurn(d)
            p[0] = p[0] + sum14 + sum23
            p[1] = a - ci
            p[2] = b - di
            p[3] = b + di
            p[4] = a + ci
        }

        // Rotate the three five-point transforms into their fifteen-point group.
        let cosine = .cosine.storage()
        let sine   = .sine.storage()
        let radixThreeGroups = .n / 15
        for group in radixThreeGroups
        {
            let p = points + group * 15
            for k in 5
            {
                let index = k * radixThreeGroups
                let b     = rotate(p[k + 5], cosine[index], sine[index])
                let c     = rotate(p[k + 10], cosine[2 * index], sine[2 * index])
                let sum   = b + c
                let mid   = p[k] - 0.5 * sum
                let diff  = b - c
                let cross = quarterTurn(diff) * Sin120
                p[k]      += sum
                p[k + 5]  = mid - cross
                p[k + 10] = mid + cross
            }
        }

        // The remaining stages double the transformed span at each step.
        var width  = 15'u32
        var groups = .n / 30
        while width < .n
        {
            for group in groups
            {
                let even = points + group * 2 * width
                let odd  = even + width
                for k in width
                {
                    let a     = even[k]
                    let index = k * groups
                    let b     = rotate(odd[k], cosine[index], sine[index])
                    even[k] = a + b
                    odd[k]  = a - b
                }
            }

            width  *= 2
            groups /= 2
        }
    }
}

// The inverse MDCT of the 48 kHz mode at its four block sizes, mirrored for time-domain aliasing
// cancellation exactly as the reference decoder lays it out.
private struct CeltMdct
{
    trig:    [4] Array'f32
    fft:     [4] CeltFft
    scratch: Array'Simd.F32x4
}

private impl CeltMdct
{
    func create()->CeltMdct
    {
        var result: #returntype
        var n = CeltMdctSize
        for shift in 4
        {
            let half = n / 2
            result.trig[shift].resize(half)
            for i in half do
                result.trig[shift][i] = cast(f32, Math.cos(2.0 * Math.ConstF64.Pi * (cast(f64, i) + 0.125) / cast(f64, n)))
            result.fft[shift] = CeltFft.create(n / 4)
            n /= 2
        }

        result.scratch.resize(CeltFftMax)
        return result
    }

    // Reconstructs one block into each output, whose first half overlap still holds the
    // previous block's tail. The second lane pair can carry a second channel through the FFT.
    mtd backward(spectrum: const [*] f32, stride: u32, out: [*] f32, shift: u32, right: const [*] f32? = null, rightOut: [*] f32? = null)
    {
        func overlap(output: [*] f32)
        {
            var lowIndex  = 0'u32
            var highIndex = CeltOverlap - 1
            for CeltOverlap / 2
            {
                let x1 = output[highIndex]
                let x2 = output[lowIndex]
                output[lowIndex]  = CeltWindow[highIndex] * x2 - CeltWindow[lowIndex] * x1
                output[highIndex] = CeltWindow[lowIndex] * x2 + CeltWindow[highIndex] * x1
                lowIndex          += 1
                highIndex         -= 1
            }
        }

        let n      = CeltMdctSize >> shift
        let n2     = n / 2
        let n4     = n / 4
        let t      = .trig[shift].storage()
        let fft    = &.fft[shift]
        let order  = fft.order.storage()
        let points = .scratch.storage()
        const Pair = cast(Simd.U32x4, [0'u32, 4, 0, 4])
        const Join = cast(Simd.U32x4, [0'u32, 1, 4, 5])
        if right and stride == 1
        {
            // A pair of neighboring points draws from two four-bin spans of each channel.
            const Heads  = cast(Simd.U32x4, [0'u32, 4, 2, 6])
            const Tails  = cast(Simd.U32x4, [3'u32, 7, 1, 5])
            const First  = cast(Simd.U32x4, [0'u32, 4, 1, 5])
            const Second = cast(Simd.U32x4, [2'u32, 6, 3, 7])
            for block in n4 / 2
            {
                let i    = 2 * block
                let head = 2 * i
                let tail = n2 - 4 - head
                let h    = Swag.vecShuffle2(Simd.load(spectrum + head), Simd.load(right + head), Heads)
                let t0   = Swag.vecShuffle2(Simd.load(spectrum + tail), Simd.load(right + tail), Tails)
                let even = Swag.vecShuffle2(h, t0, First)
                let odd  = Swag.vecShuffle2(h, t0, Second)
                points[order[i]]     = CeltFft.rotate(even, t[i], t[n4 + i])
                points[order[i + 1]] = CeltFft.rotate(odd, t[i + 1], t[n4 + i + 1])
            }
        }
        elif right
        {
            for i in n4
            {
                let head      = 2 * stride * i
                let tail      = stride * (n2 - 1 - 2 * i)
                let leftPair  = Swag.vecShuffle2(Simd.splat(spectrum[head]), Simd.splat(spectrum[tail]), Pair)
                let rightPair = Swag.vecShuffle2(Simd.splat(right[head]), Simd.splat(right[tail]), Pair)
                let point     = Swag.vecShuffle2(leftPair, rightPair, Join)
                points[order[i]] = CeltFft.rotate(point, t[i], t[n4 + i])
            }
        }
        else
        {
            for i in n4
            {
                let x1    = spectrum[2 * stride * i]
                let x2    = spectrum[stride * (n2 - 1 - 2 * i)]
                let point = Swag.vecShuffle2(Simd.splat(x1), Simd.splat(x2), Pair)
                points[order[i]] = CeltFft.rotate(point, t[i], t[n4 + i])
            }
        }

        fft.transform(points)
        let yp = out + CeltOverlap / 2
        if rightOut
        {
            let yr = rightOut + CeltOverlap / 2
            for i in n4
            {
                let point = CeltFft.rotate(points[i], t[n4 + i], -t[i])
                yp[2 * i]          = point[0]
                yp[n2 - 1 - 2 * i] = point[1]
                yr[2 * i]          = point[2]
                yr[n2 - 1 - 2 * i] = point[3]
            }

            overlap(rightOut)
        }
        else
        {
            for i in n4
            {
                let point = points[i]
                yp[2 * i] = point[1] * t[i] + point[0] * t[n4 + i]
                yp[n2 - 1 - 2 * i] = point[1] * t[n4 + i] - point[0] * t[i]
            }
        }

        overlap(out)
    }
}

// What one band's split decision resolved to.
private struct SplitContext
{
    inv:    bool
    imid:   s32
    iside:  s32
    delta:  s32
    itheta: s32
    qalloc: s32
}

// The per-frame state the band decoder threads through its recursion.
private struct BandContext
{
    band:            u32
    intensity:       u32
    spread:          u32
    tfChange:        s32
    remainingBits:   s32
    seed:            u32
    disableInv:      bool
    avoidSplitNoise: bool
    lm:              u32
}

// Decodes CELT frames of the 48 kHz mode, carrying the overlap, energy, and post-filter state
// between them.
internal struct CeltDecoder
{
    channels:            u32     // Output channels.
    streamChannels:      u32     // Channels coded in the frame.
    startBand:           u32
    endBand:             u32
    disableInv:          bool
    rng:                 u32
    postfilterPeriod:    s32
    postfilterPeriodOld: s32
    postfilterGain:      f32
    postfilterGainOld:   f32
    postfilterTapset:    u32
    postfilterTapsetOld: u32
    preemphasisMemory:   [2] f32
    decodeMemory:        [2] Array'f32     // CeltDecodeBuffer + CeltOverlap samples per channel.
    oldBandE:            [2 * CeltBandCount] f32
    oldLogE:             [2 * CeltBandCount] f32
    oldLogE2:            [2 * CeltBandCount] f32
    backgroundLogE:      [2 * CeltBandCount] f32
    mdct:                CeltMdct
    spectrum:            Array'f32     // Normalised MDCT coefficients of both channels.
    frequency:           Array'f32     // Denormalised coefficients of one channel.
    norm:                Array'f32     // Folding source for both channels.
    scratch:             Array'f32     // Lowband copy while a band is recombined.
    pulses:              Array's32
    hadamard:            [MaxPulseDimensions] f32
}

internal impl CeltDecoder
{
    func create(channels: u32)->CeltDecoder
    {
        var result: #returntype
        result.channels       = channels
        result.streamChannels = channels
        result.endBand        = CeltBandCount
        result.disableInv     = channels == 1
        for c in 2 do
            result.decodeMemory[c].resize(CeltDecodeBuffer + CeltOverlap)
        result.mdct = CeltMdct.create()
        result.spectrum.resize(2 * CeltFrameMax)
        result.frequency.resize(2 * CeltFrameMax)
        result.norm.resize(2 * 8 * 78)
        result.scratch.resize(8 * 22)
        result.pulses.resize(CeltFrameMax)
        result.reset()
        return result
    }

    mtd reset()
    {
        .rng = 0
        .postfilterPeriod     = 0
        .postfilterPeriodOld  = 0
        .postfilterGain       = 0
        .postfilterGainOld    = 0
        .postfilterTapset     = 0
        .postfilterTapsetOld  = 0
        .preemphasisMemory[0] = 0
        .preemphasisMemory[1] = 0
        for c in 2 do
            Memory.set(.decodeMemory[c].storage(), 0, .decodeMemory[c].count * #sizeof(f32))
        for i in 2 * CeltBandCount
        {
            .oldBandE[i]       = 0
            .oldLogE[i]        = NoiseFloor
            .oldLogE2[i]       = NoiseFloor
            .backgroundLogE[i] = 0
        }
    }

    mtd unquantCoarseEnergy(intra: bool, dec: *RangeDecoder, lm: u32)
    {
        let coef   = intra ? 0.0'f32 : PredCoef[lm]
        let beta   = intra ? BetaIntra : BetaCoef[lm]
        let budget = cast(s32, dec.storage) * 8
        var prev: [2] f32
        let model  = intra ? 1'u32 : 0
        for i in .startBand until .endBand
        {
            for c in .streamChannels
            {
                var qi: s32
                let tell = dec.tell()
                if budget - tell >= 15
                {
                    let pi = 2 * Math.min(i, 20)
                    qi = laplaceDecode(dec, cast(u32, CeltEnergyProbabilities[lm, model, pi]) << 7, cast(u32, CeltEnergyProbabilities[lm, model, pi + 1]) << 6)
                }
                elif budget - tell >= 2
                {
                    let raw = cast(s32, dec.decodeIcdf(SmallEnergyIcdf, 2))
                    qi = (raw >> 1) ^ -(raw & 1)
                }
                elif budget - tell >= 1
                {
                    qi = dec.decodeBit(1) ? -1 : 0
                }
                else
                {
                    qi = -1
                }

                let q     = cast(f32, qi)
                let index = i + c * CeltBandCount
                .oldBandE[index] = Math.max(-9.0'f32, .oldBandE[index])
                let tmp = coef * .oldBandE[index] + prev[c] + q
                .oldBandE[index] = tmp
                prev[c] = prev[c] + q - beta * q
            }
        }
    }

    mtd unquantFineEnergy(fineQuant: const [*] s32, dec: *RangeDecoder)
    {
        for i in .startBand until .endBand
        {
            if fineQuant[i] <= 0 do
                continue
            for c in .streamChannels
            {
                let q2     = cast(f32, dec.decodeBits(cast(u32, fineQuant[i])))
                let offset = (q2 + 0.5) * cast(f32, (1 << cast(u32, (14 - fineQuant[i])))) * (1.0 / 16384.0) - 0.5
                .oldBandE[i + c * CeltBandCount] += offset
            }
        }
    }

    mtd unquantEnergyFinalise(fineQuant, finePriority: const [*] s32, bitsLeft: s32, dec: *RangeDecoder)
    {
        var left = bitsLeft
        for priority in 2
        {
            for i in .startBand until .endBand
            {
                if left < cast(s32, .streamChannels) do
                    break
                if fineQuant[i] >= MaxFineBits or finePriority[i] != cast(s32, priority) do
                    continue
                for c in .streamChannels
                {
                    let q2     = cast(f32, dec.decodeBits(1))
                    let offset = (q2 - 0.5) * cast(f32, (1 << cast(u32, (14 - fineQuant[i] - 1)))) * (1.0 / 16384.0)
                    .oldBandE[i + c * CeltBandCount] += offset
                    left -= 1
                }
            }
        }
    }

    mtd tfDecode(isTransient: bool, tfRes: [*] s32, lm: u32, dec: *RangeDecoder)
    {
        var budget  = cast(s32, dec.storage) * 8
        var tell    = dec.tell()
        var logp    = isTransient ? 2'u32 : 4
        let reserve = lm > 0 and tell + cast(s32, logp) + 1 <= budget
        if reserve do
            budget -= 1
        var changed = 0's32
        var current = 0's32
        for i in .startBand until .endBand
        {
            if tell + cast(s32, logp) <= budget
            {
                current ^= dec.decodeBit(logp) ? 1 : 0
                tell    = dec.tell()
                changed |= current
            }

            tfRes[i] = current
            logp     = isTransient ? 4'u32 : 5
        }

        var select = 0's32
        let row    = isTransient ? 4'u32 : 0
        if reserve and CeltTfSelectTable[lm, row + cast(u32, changed)] != CeltTfSelectTable[lm, row + 2 + cast(u32, changed)] do
            select = dec.decodeBit(1) ? 1 : 0
        for i in .startBand until .endBand do
            tfRes[i] = cast(s32, CeltTfSelectTable[lm, row + 2 * cast(u32, select) + cast(u32, tfRes[i])])
    }

    // Bit allocation, clause 4.3.3: interpolates between the static allocation rows that bracket
    // the budget and decides which bands are skipped or coded with intensity or dual stereo.
    mtd computeAllocation(offsets,
                          cap: const [*] s32,
                          allocTrim: s32,
                          intensity: *u32,
                          dualStereo: *bool,
                          totalBits: s32,
                          balance: *s32,
                          pulses,
                          ebits,
                          finePriority: [*] s32,
                          lm: u32,
                          dec: *RangeDecoder)->u32
    {
        let C         = cast(s32, .streamChannels)
        let start     = .startBand
        let end       = .endBand
        var total     = Math.max(totalBits, 0)
        var skipStart = start
        let skipRsv   = total >= 1's32 << BitRes ? 1's32 << BitRes : 0
        total -= skipRsv
        var intensityRsv  = 0's32
        var dualStereoRsv = 0's32
        if C == 2
        {
            intensityRsv = cast(s32, CeltLog2FracTable[end - start])
            if intensityRsv > total
            {
                intensityRsv = 0
            }
            else
            {
                total         -= intensityRsv
                dualStereoRsv = total >= 1's32 << BitRes ? 1's32 << BitRes : 0
                total         -= dualStereoRsv
            }
        }

        var bits1:      [CeltBandCount] s32
        var bits2:      [CeltBandCount] s32
        var thresh:     [CeltBandCount] s32
        var trimOffset: [CeltBandCount] s32
        for j in start until end
        {
            let width = cast(s32, (CeltBands[j + 1] - CeltBands[j]))
            thresh[j]     = Math.max(C << BitRes, ((3 * width) << lm << BitRes) >> 4)
            trimOffset[j] = (C * width * (allocTrim - 5 - cast(s32, lm)) * cast(s32, (end - j - 1)) * (1 << (lm + BitRes))) >> 6
            if (width << lm) == 1 do
                trimOffset[j] -= C << BitRes
        }

        var lo = 1's32
        var hi = cast(s32, CeltAllocVectors) - 1
        while lo <= hi
        {
            var done = false
            var psum = 0's32
            let mid  = (lo + hi) >> 1
            var j    = end
            while j > start
            {
                j -= 1
                let width = cast(s32, (CeltBands[j + 1] - CeltBands[j]))
                var bitsj = ((C * width * cast(s32, CeltBandAllocation[cast(u32, mid), j])) << lm) >> 2
                if bitsj > 0 do
                    bitsj = Math.max(0's32, bitsj + trimOffset[j])
                bitsj += offsets[j]
                if bitsj >= thresh[j] or done
                {
                    done = true
                    psum += Math.min(bitsj, cap[j])
                }
                elif bitsj >= C << BitRes
                {
                    psum += C << BitRes
                }
            }

            if psum > total do
                hi = mid - 1
            else do
                lo = mid + 1
        }

        hi = lo
        lo -= 1
        for j in start until end
        {
            let width  = cast(s32, (CeltBands[j + 1] - CeltBands[j]))
            var bits1j = ((C * width * cast(s32, CeltBandAllocation[cast(u32, lo), j])) << lm) >> 2
            var bits2j = hi >= cast(s32, CeltAllocVectors) ? cap[j] : ((C * width * cast(s32, CeltBandAllocation[cast(u32, hi), j])) << lm) >> 2
            if bits1j > 0 do
                bits1j = Math.max(0's32, bits1j + trimOffset[j])
            if bits2j > 0 do
                bits2j = Math.max(0's32, bits2j + trimOffset[j])
            if lo > 0 do
                bits1j += offsets[j]
            bits2j += offsets[j]
            if offsets[j] > 0 do
                skipStart = j
            bits2j   = Math.max(0's32, bits2j - bits1j)
            bits1[j] = bits1j
            bits2[j] = bits2j
        }

        // Interpolate between the two rows, then hand bits from skipped bands down to the coded ones.
        let allocFloor = C << BitRes
        let stereo     = C > 1
        let logM       = cast(s32, lm) << BitRes
        var ilo        = 0's32
        var ihi        = 1's32 << AllocSteps
        var psum: s32
        for AllocSteps
        {
            let mid = (ilo + ihi) >> 1
            psum = 0
            var done = false
            var j    = end
            while j > start
            {
                j -= 1
                let tmp = bits1[j] + ((mid * bits2[j]) >> AllocSteps)
                if tmp >= thresh[j] or done
                {
                    done = true
                    psum += Math.min(tmp, cap[j])
                }
                elif tmp >= allocFloor
                {
                    psum += allocFloor
                }
            }

            if psum > total do
                ihi = mid
            else do
                ilo = mid
        }

        psum = 0
        var done = false
        var j    = end
        while j > start
        {
            j -= 1
            var tmp = bits1[j] + ((ilo * bits2[j]) >> AllocSteps)
            if tmp < thresh[j] and not done do
                tmp = tmp >= allocFloor ? allocFloor : 0
            else do
                done = true
            tmp       = Math.min(tmp, cap[j])
            pulses[j] = tmp
            psum      += tmp
        }

        var codedBands = end
        while true
        {
            j = codedBands - 1
            if j <= skipStart
            {
                total += skipRsv
                break
            }

            var left     = total - psum
            let span     = cast(s32, (CeltBands[codedBands] - CeltBands[start]))
            let percoeff = left / span
            left -= span * percoeff
            let rem       = Math.max(left - cast(s32, (CeltBands[j] - CeltBands[start])), 0)
            let bandWidth = cast(s32, (CeltBands[codedBands] - CeltBands[j]))
            var bandBits  = pulses[j] + percoeff * bandWidth + rem
            if bandBits >= Math.max(thresh[j], allocFloor + (1's32 << BitRes))
            {
                if dec.decodeBit(1) do
                    break
                psum     += 1's32 << BitRes
                bandBits -= 1's32 << BitRes
            }

            psum -= pulses[j] + intensityRsv
            if intensityRsv > 0 do
                intensityRsv = cast(s32, CeltLog2FracTable[j - start])
            psum += intensityRsv
            if bandBits >= allocFloor
            {
                psum      += allocFloor
                pulses[j] = allocFloor
            }
            else
            {
                pulses[j] = 0
            }

            codedBands -= 1
        }

        if intensityRsv > 0 do
            intensity[] = start + dec.decodeUint(codedBands + 1 - start)
        else do
            intensity[] = 0
        if intensity[] <= start
        {
            total         += dualStereoRsv
            dualStereoRsv = 0
        }

        dualStereo[] = dualStereoRsv > 0 ? dec.decodeBit(1) : false

        var left     = total - psum
        let span     = cast(s32, (CeltBands[codedBands] - CeltBands[start]))
        let percoeff = left / span
        left -= span * percoeff
        for k in start until codedBands do
            pulses[k] += percoeff * cast(s32, (CeltBands[k + 1] - CeltBands[k]))
        for k in start until codedBands
        {
            let tmp = Math.min(left, cast(s32, (CeltBands[k + 1] - CeltBands[k])))
            pulses[k] += tmp
            left      -= tmp
        }

        var bal = 0's32
        for k in start until codedBands
        {
            let n0  = cast(s32, (CeltBands[k + 1] - CeltBands[k]))
            let n   = n0 << lm
            let bit = pulses[k] + bal
            var excess: s32
            if n > 1
            {
                excess    = Math.max(bit - cap[k], 0)
                pulses[k] = bit - excess
                let den    = C * n + ((C == 2 and n > 2 and not dualStereo[] and k < intensity[]) ? 1 : 0)
                let nclogn = den * (cast(s32, CeltLogN[k]) + logM)
                var offset = (nclogn >> 1) - den * FineOffset
                if n == 2 do
                    offset += (den << BitRes) >> 2
                if pulses[k] + offset < (den * 2) << BitRes do
                    offset += nclogn >> 2
                elif pulses[k] + offset < (den * 3) << BitRes do
                    offset += nclogn >> 3
                ebits[k] = Math.max(0's32, pulses[k] + offset + (den << (BitRes - 1)))
                ebits[k] = (ebits[k] / den) >> BitRes
                if C * ebits[k] > (pulses[k] >> BitRes) do
                    ebits[k] = pulses[k] >> (stereo ? 1 : 0) >> BitRes
                ebits[k]        = Math.min(ebits[k], MaxFineBits)
                finePriority[k] = ebits[k] * (den << BitRes) >= pulses[k] + offset ? 1 : 0
                pulses[k]       -= (C * ebits[k]) << BitRes
            }
            else
            {
                excess          = Math.max(0's32, bit - (C << BitRes))
                pulses[k]       = bit - excess
                ebits[k]        = 0
                finePriority[k] = 1
            }

            if excess > 0
            {
                let extraFine = Math.min(excess >> (cast(u32, (stereo ? 1 : 0)) + BitRes), MaxFineBits - ebits[k])
                ebits[k] += extraFine
                let extraBits = (extraFine * C) << BitRes
                finePriority[k] = extraBits >= excess - bal ? 1 : 0
                excess -= extraBits
            }

            bal = excess
        }

        balance[] = bal
        for k in codedBands until end
        {
            ebits[k]        = pulses[k] >> (stereo ? 1 : 0) >> BitRes
            pulses[k]       = 0
            finePriority[k] = ebits[k] < 1 ? 1 : 0
        }

        return codedBands
    }

    mtd const bits2pulses(base: u32, bits: s32)->s32
        => cast(s32, PulseChoices[PulseChoiceRows.indices[base], Math.clamp(bits - 1, 0, 255)])

    mtd const pulses2bits(base: u32, pulses: s32)->s32
    {
        if not pulses do
            return 0
        return cast(s32, CeltCacheBits[base + cast(u32, pulses)]) + 1
    }

    // Reconstructs the signed pulse vector in the spectrum and returns its squared norm.
    mtd decodePulses(target: [*] f32, n, k: u32, dec: *RangeDecoder)->f32
    {
        var index     = dec.decodeUint(pulseArrangements(n, k) + pulseArrangements(n, k + 1))
        var remaining = k
        var norm      = 0'u32
        var position  = 0'u32

        // Stop as soon as the remaining codebook has a closed form.
        while remaining > 1 and position + 2 < n
        {
            let dimensions = n - position
            if dimensions <= 8 and remaining <= 6
            {
                let start = PulseTailLayout.offset[dimensions, remaining]
                if start
                {
                    let code = PulseTails[start + index]
                    Simd.store(target + position, unpackPulseTail(cast #wrap(u32, code)))
                    if dimensions == 8 do
                        Simd.store(target + position + 4, unpackPulseTail(cast(u32, code >> 20)))
                    return cast(f32, norm + cast(u32, code >> 40))
                }
            }

            let row       = cast(const [*] u32, &PulseArrangements[PulseLayout.offset[dimensions]])
            let threshold = row[remaining + 1]
            let negative  = cast #bit(u32, -cast(s32, index >= threshold))
            index -= threshold & negative

            let available = remaining
            var offset    = row[remaining]
            while offset > index
            {
                remaining -= 1
                offset    = row[remaining]
            }

            index -= offset
            let magnitude = available - remaining
            let value     = cast #bit(u32, cast(f32, magnitude)) | (negative & 0x8000_0000)
            target[position] = cast #bit(f32, value)
            norm             += magnitude * magnitude
            position         += 1
        }

        let tail       = target + position
        let dimensions = n - position
        if remaining <= 1
        {
            // Single pulses are indexed by increasing position when positive and by
            // decreasing position when negative. Zero pulses leave the entire tail empty.
            Memory.clear(tail, cast(u64, dimensions) * #sizeof(f32))
            if remaining
            {
                if index < dimensions do
                    tail[index] = 1
                else do
                    tail[2 * dimensions - 1 - index] = -1
            }

            return cast(f32, norm + remaining)
        }

        if dimensions == 1
        {
            let value = cast(f32, remaining)
            tail[0] = index ? -value : value
            return cast(f32, norm + remaining * remaining)
        }

        // U(2,k) = 2*k - 1 for k > 0, so the two-bin case recovers the second
        // magnitude and its sign directly from the index after the first sign.
        let threshold = 2 * remaining + 1
        let negative  = index >= threshold
        let code      = negative ? index - threshold : index
        let second    = (code + 1) >> 1
        let first     = cast(s32, remaining - second)
        tail[0] = cast(f32, negative ? -first : first)
        tail[1] = cast(f32, (code & 1) ? cast(s32, second) : -cast(s32, second))
        return cast(f32, norm + cast(u32, first * first) + second * second)
    }

    mtd expRotation1(x: [*] f32, len, stride: u32, c, s: f32)
    {
        let ms = -s
        var i  = 0'u32
        while i + stride < len
        {
            let x1 = x[i]
            let x2 = x[i + stride]
            x[i + stride] = c * x2 + s * x1
            x[i] = c * x1 + ms * x2
            i    += 1
        }

        if len >= 2 * stride + 1
        {
            var j = len - 2 * stride - 1
            while true
            {
                let x1 = x[j]
                let x2 = x[j + stride]
                x[j + stride] = c * x2 + s * x1
                x[j] = c * x1 + ms * x2
                if j == 0 do
                    break
                j -= 1
            }
        }
    }

    // Adjacent rotations pass one coefficient to the next pair in either direction.
    mtd expRotationAdjacent(x: [*] f32, len: u32, c, s: f32)
    {
        if len < 2 do
            return

        let ms      = -s
        var carried = x[0]
        for i in len - 1
        {
            let next = x[i + 1]
            x[i]    = c * carried + ms * next
            carried = c * next + s * carried
        }

        x[len - 1] = carried
        if len == 2 do
            return

        var i = len - 2
        carried = x[i]
        while i
        {
            let previous = x[i - 1]
            x[i]    = c * carried + s * previous
            carried = c * previous + ms * carried
            i       -= 1
        }

        x[0] = carried
    }

    // Each lane follows an independent stride-four chain through both passes.
    mtd expRotationStridedFour(x: [*] f32, len: u32, c, s: f32)
    {
        let last    = len - 4
        let ms      = -s
        var carried = Simd.load(x)
        for block in 1 until len / 4
        {
            let at   = x + 4 * block
            let next = Simd.load(at)
            Simd.store(at - 4, c * carried + ms * next)
            carried = c * next + s * carried
        }

        Simd.store(x + last, carried)

        var i = len - 8
        carried = Simd.load(x + i)
        while i
        {
            let previous = Simd.load(x + i - 4)
            Simd.store(x + i, c * carried + s * previous)
            carried = c * previous + ms * carried
            i       -= 4
        }

        Simd.store(x, carried)
    }

    // Expand the carry recurrence across four coefficients as a weighted prefix sum.
    mtd expRotationAdjacentPacked(x: [*] f32, len: u32, c, s: f32)
    {
        #[Swag.Inline]
        func scan(input, memory: Simd.F32x4, c, s: f32, powers: Simd.F32x4)->Simd.F32x4
        {
            const LeftOne = cast(Simd.U32x4, [4'u32, 0, 1, 2])
            const LeftTwo = cast(Simd.U32x4, [4'u32, 4, 0, 1])
            let zero   = Simd.splat(0.0'f32)
            let values = c * input
            let pair   = values + Swag.vecShuffle2(values, zero, LeftOne) * s
            return pair + Swag.vecShuffle2(pair, zero, LeftTwo) * (s * s) + memory * powers
        }

        const Last    = cast(Simd.U32x4, [3'u32, 3, 3, 3])
        const Link    = cast(Simd.U32x4, [0'u32, 4, 5, 6])
        const Reverse = cast(Simd.U32x4, [3'u32, 2, 1, 0])
        let s2        = s * s
        let s3        = s2 * s
        let s4        = s2 * s2
        let ms        = -s
        let forward   = cast(Simd.F32x4, [s, s2, s3, s4])
        let reverse   = cast(Simd.F32x4, [ms, s2, -s3, s4])
        let vectorEnd = (len - 1) & ~3'u32
        var carried   = Simd.splat(x[0])
        for block in vectorEnd / 4
        {
            let at     = x + 4 * block
            let next   = Simd.load(at + 1)
            let result = scan(next, carried, c, s, forward)
            let prior  = Swag.vecShuffle2(carried, result, Link)
            Simd.store(at, c * prior + ms * next)
            carried = Swag.vecShuffle(result, Last)
        }

        var scalar = carried[0]
        for i in vectorEnd until len - 1
        {
            let next = x[i + 1]
            x[i]   = c * scalar + ms * next
            scalar = c * next + s * scalar
        }

        x[len - 1] = scalar

        var i = len - 2
        carried = Simd.splat(x[i])
        while i >= 4
        {
            let previous = Swag.vecShuffle(Simd.load(x + i - 4), Reverse)
            let result   = scan(previous, carried, c, ms, reverse)
            let prior    = Swag.vecShuffle2(carried, result, Link)
            Simd.store(x + i - 3, Swag.vecShuffle(c * prior + s * previous, Reverse))
            carried = Swag.vecShuffle(result, Last)
            i       -= 4
        }

        scalar = carried[0]
        while i
        {
            let previous = x[i - 1]
            x[i]   = c * scalar + s * previous
            scalar = c * previous + ms * scalar
            i      -= 1
        }

        x[0] = scalar
    }

    mtd expRotation(x: [*] f32, len: u32, stride, k, spread: u32)
    {
        if 2 * k >= len or spread == SpreadNone do
            return
        let offset = SpreadLayout.offset[len] + k - 1
        let c      = SpreadRotations[spread - 1, offset, 0]
        let s      = SpreadRotations[spread - 1, offset, 1]

        // The transform block count is a power of two.
        let part    = len >> cast(u32, Swag.trailingZeros(stride))
        let stride2 = SpreadStride[part]
        for i in stride
        {
            let at = x + i * part
            if stride2 == 4 and (part & 3) == 0 do
                .expRotationStridedFour(at, part, s, c)
            elif stride2 do
                .expRotation1(at, part, cast(u32, stride2), s, c)
            if part >= 12 do
                .expRotationAdjacentPacked(at, part, c, s)
            else do
                .expRotationAdjacent(at, part, c, s)
        }
    }

    mtd algUnquant(x: [*] f32, n, k: u32, spread, b: u32, dec: *RangeDecoder, gain: f32)->u32
    {
        let energy = .decodePulses(x, n, k, dec)
        var mask   = 1'u32
        if b > 1
        {
            let blockSize = n / b
            mask = 0
            for i in b
            {
                let block = x + i * blockSize
                for j in blockSize where block[j] != 0
                {
                    mask |= 1'u32 << i
                    break
                }
            }
        }

        let scale     = celtRsqrt(energy) * gain
        let vectorEnd = n & ~3'u32
        for block in vectorEnd / 4
        {
            let part = x + 4 * block
            Simd.store(part, Simd.load(part) * scale)
        }

        for i in vectorEnd until n do
            x[i] *= scale
        .expRotation(x, n, b, k, spread)
        return mask
    }

    mtd renormaliseVector(x: [*] f32, n: u32, gain: f32)
    {
        var energy = 1e-15'f32
        for i in n do
            energy += x[i] * x[i]
        let g = celtRsqrt(energy) * gain
        for i in n do
            x[i] *= g
    }

    mtd haar1(x: [*] f32, n0, stride: u32)
    {
        let half = n0 >> 1
        for i in stride
        {
            for j in half
            {
                let a = 0.70710678'f32 * x[stride * 2 * j + i]
                let b = 0.70710678'f32 * x[stride * (2 * j + 1) + i]
                x[stride * 2 * j + i]       = a + b
                x[stride * (2 * j + 1) + i] = a - b
            }
        }
    }

    mtd deinterleaveHadamard(x: [*] f32, n0, stride: u32, hadamard: bool)
    {
        let tmp = cast([*] f32, &.hadamard[0])
        let n   = n0 * stride
        if hadamard
        {
            let base = stride - 2
            for i in stride
            {
                for j in n0 do
                    tmp[cast(u32, CeltOrderyTable[base + i]) * n0 + j] = x[j * stride + i]
            }
        }
        else
        {
            for i in stride
            {
                for j in n0 do
                    tmp[i * n0 + j] = x[j * stride + i]
            }
        }

        Memory.copy(x, tmp, cast(u64, n) * #sizeof(f32))
    }

    mtd interleaveHadamard(x: [*] f32, n0, stride: u32, hadamard: bool)
    {
        let tmp = cast([*] f32, &.hadamard[0])
        let n   = n0 * stride
        if hadamard
        {
            let base = stride - 2
            for i in stride
            {
                for j in n0 do
                    tmp[j * stride + i] = x[cast(u32, CeltOrderyTable[base + i]) * n0 + j]
            }
        }
        else
        {
            for i in stride
            {
                for j in n0 do
                    tmp[j * stride + i] = x[i * n0 + j]
            }
        }

        Memory.copy(x, tmp, cast(u64, n) * #sizeof(f32))
    }

    mtd computeTheta(ctx: *BandContext,
                     sctx: *SplitContext,
                     n: u32,
                     b: *s32,
                     bBlocks,
                     b0: u32,
                     lm: s32,
                     stereo: bool,
                     fill: *u32,
                     dec: *RangeDecoder)
    {
        let i        = ctx.band
        let pulseCap = cast(s32, CeltLogN[i]) + lm * (1's32 << BitRes)
        let offset   = (pulseCap >> 1) - cast(s32, (stereo and n == 2 ? QThetaOffsetTwoPhase : QThetaOffset))
        var qn       = computeQn(cast(s32, n), b[], offset, pulseCap, stereo)
        if stereo and i >= ctx.intensity do
            qn = 1
        let tell   = cast(s32, dec.tellFrac())
        var itheta = 0's32
        var inv    = false
        var th: CodedTheta
        if qn != 1
        {
            if stereo and n > 2
            {
                let p0 = 3's32
                let x0 = qn / 2
                let ft = cast(u32, (p0 * (x0 + 1) + x0))
                let fs = cast(s32, dec.decode(ft))
                var x: s32
                if fs < (x0 + 1) * p0 do
                    x = fs / p0
                else do
                    x = x0 + 1 + (fs - (x0 + 1) * p0)
                let low  = x <= x0 ? p0 * x : (x - 1 - x0) + (x0 + 1) * p0
                let high = x <= x0 ? p0 * (x + 1) : (x - x0) + (x0 + 1) * p0
                dec.update(cast(u32, low), cast(u32, high), ft)
                itheta = x
            }
            elif b0 > 1 or stereo
            {
                itheta = cast(s32, dec.decodeUint(cast(u32, qn) + 1))
            }
            else
            {
                let half = qn >> 1
                let ft   = cast(u32, ((half + 1) * (half + 1)))
                let fm   = cast(s32, dec.decode(ft))
                var fl: s32
                var fs: s32
                if fm < (half * (half + 1) >> 1)
                {
                    itheta = (cast(s32, isqrt32(8 * cast(u32, fm) + 1)) - 1) >> 1
                    fs     = itheta + 1
                    fl     = itheta * (itheta + 1) >> 1
                }
                else
                {
                    itheta = (2 * (qn + 1) - cast(s32, isqrt32(8 * cast(u32, (cast(s32, ft) - fm - 1)) + 1))) >> 1
                    fs     = qn + 1 - itheta
                    fl     = cast(s32, ft) - ((qn + 1 - itheta) * (qn + 2 - itheta) >> 1)
                }

                dec.update(cast(u32, fl), cast(u32, (fl + fs)), ft)
            }

            let row = qn >> 1
            th     = CodedThetas[row * row - 1 + itheta]
            itheta = cast(s32, th.angle)
        }
        elif stereo
        {
            if b[] > 2's32 << BitRes and ctx.remainingBits > 2's32 << BitRes do
                inv = dec.decodeBit(2)
            if ctx.disableInv do
                inv = false
            itheta = 0
        }

        let qalloc = cast(s32, dec.tellFrac()) - tell
        b[] -= qalloc
        var imid, iside, delta: s32
        if itheta == 0
        {
            imid   = 32767
            iside  = 0
            fill[] &= (1'u32 << bBlocks) - 1
            delta  = -16384
        }
        elif itheta == 16384
        {
            imid   = 0
            iside  = 32767
            fill[] &= ((1'u32 << bBlocks) - 1) << bBlocks
            delta  = 16384
        }
        else
        {
            imid  = cast(s32, th.middle)
            iside = cast(s32, th.side)
            delta = fracMul16((cast(s32, n) - 1) << 7, cast(s32, th.logTan))
        }

        sctx.inv    = inv
        sctx.imid   = imid
        sctx.iside  = iside
        sctx.delta  = delta
        sctx.itheta = itheta
        sctx.qalloc = qalloc
    }

    mtd quantBandN1(ctx: *BandContext, x: [*] f32, y: [*] f32?, lowbandOut: [*] f32?, dec: *RangeDecoder)->u32
    {
        var target = x
        for (y ? 2'u32 : 1)
        {
            var sign = false
            if ctx.remainingBits >= 1's32 << BitRes
            {
                sign = dec.decodeBits(1) != 0
                ctx.remainingBits -= 1's32 << BitRes
            }

            target[0] = sign ? -1.0'f32 : 1.0
            if y do
                target = y
        }

        if lowbandOut do
            lowbandOut[0] = x[0]
        return 1
    }

    mtd quantPartition(ctx: *BandContext,
                       x: [*] f32,
                       n: u32,
                       bBits: s32,
                       b: u32,
                       lowband: [*] f32?,
                       lm: s32,
                       gain: f32,
                       fill: u32,
                       dec: *RangeDecoder)->u32
    {
        let i     = ctx.band
        var cm    = 0'u32
        let base  = cast(u32, CeltCacheIndex[cast(u32, (lm + 1)) * CeltBandCount + i])
        let limit = cast(s32, CeltCacheBits[base + cast(u32, CeltCacheBits[base])]) + 12
        if lm != -1 and bBits > limit and n > 2
        {
            var sctx: SplitContext
            let half    = n >> 1
            let y       = x + half
            let lmNew   = lm - 1
            var fillNow = fill
            if b == 1 do
                fillNow = (fill & 1) | (fill << 1)
            let bNew = (b + 1) >> 1
            var bb   = bBits
            .computeTheta(ctx, &sctx, half, &bb, bNew, b, lmNew, false, &fillNow, dec)
            let mid   = (1.0 / 32768.0) * cast(f32, sctx.imid)
            let side  = (1.0 / 32768.0) * cast(f32, sctx.iside)
            var delta = sctx.delta
            if b > 1 and (sctx.itheta & 0x3FFF)
            {
                if sctx.itheta > 8192 do
                    delta -= delta >> cast(u32, (4 - lmNew))
                else do
                    delta = Math.min(0's32, delta + ((cast(s32, half) << BitRes) >> cast(u32, (5 - lmNew))))
            }

            var mbits = Math.max(0's32, Math.min(bb, (bb - delta) / 2))
            var sbits = bb - mbits
            ctx.remainingBits -= sctx.qalloc
            var nextLowband: [*] f32?
            if lowband do
                nextLowband = lowband + half
            var rebalance = ctx.remainingBits
            if mbits >= sbits
            {
                cm        = .quantPartition(ctx, x, half, mbits, bNew, lowband, lmNew, gain * mid, fillNow, dec)
                rebalance = mbits - (rebalance - ctx.remainingBits)
                if rebalance > 3's32 << BitRes and sctx.itheta != 0 do
                    sbits += rebalance - (3's32 << BitRes)
                cm |= .quantPartition(ctx, y, half, sbits, bNew, nextLowband, lmNew, gain * side, fillNow >> bNew, dec) << (b >> 1)
            }
            else
            {
                cm        = .quantPartition(ctx, y, half, sbits, bNew, nextLowband, lmNew, gain * side, fillNow >> bNew, dec) << (b >> 1)
                rebalance = sbits - (rebalance - ctx.remainingBits)
                if rebalance > 3's32 << BitRes and sctx.itheta != 16384 do
                    mbits += rebalance - (3's32 << BitRes)
                cm |= .quantPartition(ctx, x, half, mbits, bNew, lowband, lmNew, gain * mid, fillNow, dec)
            }

            return cm
        }

        var q        = .bits2pulses(base, bBits)
        var currBits = .pulses2bits(base, q)
        ctx.remainingBits -= currBits
        while ctx.remainingBits < 0 and q > 0
        {
            ctx.remainingBits += currBits
            q                 -= 1
            currBits          = .pulses2bits(base, q)
            ctx.remainingBits -= currBits
        }

        if q != 0
        {
            let k = pulseCount(cast(u32, q))
            return .algUnquant(x, n, k, ctx.spread, b, dec, gain)
        }

        let cmMask   = (1'u32 << b) - 1
        let fillMask = fill & cmMask
        if not fillMask
        {
            for j in n do
                x[j] = 0
            return 0
        }

        if not lowband
        {
            for j in n
            {
                ctx.seed = lcgRand(ctx.seed)
                x[j]     = cast(f32, (cast #bit (s32, ctx.seed) >> 20))
            }

            cm = cmMask
        }
        else
        {
            for j in n
            {
                ctx.seed = lcgRand(ctx.seed)
                let tmp = ctx.seed & 0x8000 ? 1.0 / 256.0 : -1.0 / 256.0
                x[j] = lowband[j] + cast(f32, tmp)
            }

            cm = fillMask
        }

        .renormaliseVector(x, n, gain)
        return cm
    }

    mtd quantBand(ctx: *BandContext,
                  x: [*] f32,
                  n: u32,
                  bBits: s32,
                  b: u32,
                  lowbandIn: [*] f32?,
                  lm: u32,
                  lowbandOut: [*] f32?,
                  gain: f32,
                  useScratch: bool,
                  fillIn: u32,
                  dec: *RangeDecoder)->u32
    {
        if n == 1 do
            return .quantBandN1(ctx, x, null, lowbandOut, dec)

        // One block with unchanged resolution needs no coefficient permutation.
        if b == 1 and not ctx.tfChange
        {
            let cm = .quantPartition(ctx, x, n, bBits, 1, lowbandIn, cast(s32, lm), gain, fillIn, dec)
            if lowbandOut
            {
                let scale = cast(f32, Math.sqrt(cast(f64, n)))
                for j in n do
                    lowbandOut[j] = scale * x[j]
            }

            return cm & 1
        }

        var lowband    = lowbandIn
        var fill       = fillIn
        let n0         = n
        var nb         = n / b
        var blocks     = b
        var timeDivide = 0'u32
        var recombine  = 0'u32
        let longBlocks = b == 1
        var tfChange   = ctx.tfChange
        if tfChange > 0 do
            recombine = cast(u32, tfChange)

        if useScratch and lowband and (recombine or ((nb & 1) == 0 and tfChange < 0) or b > 1)
        {
            let scratch = .scratch.storage()
            for j in n do
                scratch[j] = lowband[j]
            lowband = scratch
        }

        for k in recombine
        {
            if lowband do
                .haar1(lowband, n >> k, 1'u32 << k)
            fill = BitInterleave[fill & 0xF] | (BitInterleave[fill >> 4] << 2)
        }

        blocks >>= recombine
        nb     <<= recombine
        while (nb & 1) == 0 and tfChange < 0
        {
            if lowband do
                .haar1(lowband, nb, blocks)
            fill       |= fill << blocks
            blocks     <<= 1
            nb         >>= 1
            timeDivide += 1
            tfChange   += 1
        }

        let b0  = blocks
        let nb0 = nb
        if b0 > 1 and lowband do
            .deinterleaveHadamard(lowband, nb >> recombine, b0 << recombine, longBlocks)

        var cm = .quantPartition(ctx, x, n, bBits, blocks, lowband, cast(s32, lm), gain, fill, dec)

        if b0 > 1 do
            .interleaveHadamard(x, nb >> recombine, b0 << recombine, longBlocks)
        nb     = nb0
        blocks = b0
        for timeDivide
        {
            blocks >>= 1
            nb     <<= 1
            cm     |= cm >> blocks
            .haar1(x, nb, blocks)
        }

        for k in recombine
        {
            cm = BitDeinterleave[cm & 0xF]
            .haar1(x, n0 >> k, 1'u32 << k)
        }

        blocks <<= recombine
        if lowbandOut
        {
            let scale = cast(f32, Math.sqrt(cast(f64, n0)))
            for j in n0 do
                lowbandOut[j] = scale * x[j]
        }

        return cm & ((1'u32 << blocks) - 1)
    }

    mtd quantBandStereo(ctx: *BandContext,
                        x,
                        y: [*] f32,
                        n: u32,
                        bBits: s32,
                        b: u32,
                        lowband: [*] f32?,
                        lm: u32,
                        lowbandOut: [*] f32?,
                        useScratch: bool,
                        fillIn: u32,
                        dec: *RangeDecoder)->u32
    {
        if n == 1 do
            return .quantBandN1(ctx, x, y, lowbandOut, dec)

        var sctx: SplitContext
        var fill = fillIn
        var bb   = bBits
        .computeTheta(ctx, &sctx, n, &bb, b, b, cast(s32, lm), true, &fill, dec)
        let mid  = (1.0 / 32768.0) * cast(f32, sctx.imid)
        let side = (1.0 / 32768.0) * cast(f32, sctx.iside)
        var cm: u32
        if n == 2
        {
            var mbits = bb
            var sbits = 0's32
            if sctx.itheta != 0 and sctx.itheta != 16384 do
                sbits = 1's32 << BitRes
            mbits -= sbits
            let swap = sctx.itheta > 8192
            ctx.remainingBits -= sctx.qalloc + sbits
            let x2   = swap ? y : x
            let y2   = swap ? x : y
            var sign = 1.0'f32
            if sbits and dec.decodeBits(1) do
                sign = -1.0
            cm    = .quantBand(ctx, x2, n, mbits, b, lowband, lm, lowbandOut, 1.0, useScratch, fillIn, dec)
            y2[0] = -sign * x2[1]
            y2[1] = sign * x2[0]
            x[0]  = mid * x[0]
            x[1]  = mid * x[1]
            y[0]  = side * y[0]
            y[1]  = side * y[1]
            var tmp = x[0]
            x[0] = tmp - y[0]
            y[0] = tmp + y[0]
            tmp  = x[1]
            x[1] = tmp - y[1]
            y[1] = tmp + y[1]
        }
        else
        {
            var mbits = Math.max(0's32, Math.min(bb, (bb - sctx.delta) / 2))
            var sbits = bb - mbits
            ctx.remainingBits -= sctx.qalloc
            var rebalance = ctx.remainingBits
            if mbits >= sbits
            {
                cm        = .quantBand(ctx, x, n, mbits, b, lowband, lm, lowbandOut, 1.0, useScratch, fill, dec)
                rebalance = mbits - (rebalance - ctx.remainingBits)
                if rebalance > 3's32 << BitRes and sctx.itheta != 0 do
                    sbits += rebalance - (3's32 << BitRes)
                cm |= .quantBand(ctx, y, n, sbits, b, null, lm, null, side, false, fill >> b, dec)
            }
            else
            {
                cm        = .quantBand(ctx, y, n, sbits, b, null, lm, null, side, false, fill >> b, dec)
                rebalance = sbits - (rebalance - ctx.remainingBits)
                if rebalance > 3's32 << BitRes and sctx.itheta != 16384 do
                    mbits += rebalance - (3's32 << BitRes)
                cm |= .quantBand(ctx, x, n, mbits, b, lowband, lm, lowbandOut, 1.0, useScratch, fill, dec)
            }
        }

        if n != 2 do
            .stereoMerge(x, y, mid, n)
        if sctx.inv
        {
            for j in n do
                y[j] = -y[j]
        }

        return cm
    }

    mtd stereoMerge(x, y: [*] f32, mid: f32, n: u32)
    {
        var xp   = 0.0'f32
        var side = 0.0'f32
        for j in n
        {
            xp   += y[j] * x[j]
            side += y[j] * y[j]
        }

        xp *= mid
        let el = mid * mid + side - 2.0 * xp
        let er = mid * mid + side + 2.0 * xp
        if er < 6e-4'f32 or el < 6e-4'f32
        {
            for j in n do
                y[j] = x[j]
            return
        }

        let lgain = celtRsqrt(el)
        let rgain = celtRsqrt(er)
        for j in n
        {
            let l = mid * x[j]
            let r = y[j]
            x[j] = lgain * (l - r)
            y[j] = rgain * (l + r)
        }
    }

    // Decodes every band of the frame into the normalised spectrum, clause 4.3.4.
    mtd quantAllBands(shortBlocks: bool,
                      spread: u32,
                      dualStereoIn: bool,
                      intensity: u32,
                      tfRes: const [*] s32,
                      totalBits: s32,
                      balanceIn: s32,
                      dec: *RangeDecoder,
                      lm: u32,
                      codedBands: u32,
                      collapseMasks: [*] u8)
    {
        let C             = .streamChannels
        let M             = 1'u32 << lm
        let B             = shortBlocks ? M : 1
        let normOffset    = M * cast(u32, CeltBands[.startBand])
        let normSpan      = M * cast(u32, CeltBands[CeltBandCount - 1]) - normOffset
        let norm          = .norm.storage()
        let norm2         = norm + normSpan
        let spectrum      = .spectrum.storage()
        let N             = M * CeltShortSize
        var dualStereo    = dualStereoIn
        var balance       = balanceIn
        var lowbandOffset = 0'u32
        var updateLowband = true
        var ctx: BandContext
        ctx.intensity       = intensity
        ctx.spread          = spread
        ctx.seed            = .rng
        ctx.disableInv      = .disableInv
        ctx.avoidSplitNoise = B > 1
        ctx.lm              = lm

        for i in .startBand until .endBand
        {
            ctx.band = i
            let last = i == .endBand - 1
            var x    = spectrum + M * cast(u32, CeltBands[i])
            var y: [*] f32?
            if C == 2 do
                y = spectrum + N + M * cast(u32, CeltBands[i])
            let n    = M * cast(u32, (CeltBands[i + 1] - CeltBands[i]))
            let tell = cast(s32, dec.tellFrac())
            if i != .startBand do
                balance -= tell
            let remainingBits = totalBits - tell - 1
            ctx.remainingBits = remainingBits
            var b = 0's32
            if i <= codedBands - 1
            {
                let currBalance = balance / cast(s32, Math.min(3'u32, codedBands - i))
                b = Math.clamp(Math.min(remainingBits + 1, .pulses[i] + currBalance), 0's32, 16383's32)
            }

            if (cast(s32, (M * cast(u32, CeltBands[i]))) - cast(s32, n) >= cast(s32, (M * cast(u32, CeltBands[.startBand]))) or i == .startBand + 1) and (updateLowband or lowbandOffset == 0) do
                lowbandOffset = i
            if i == .startBand + 1
            {
                // Duplicate enough of the first band to fold the second one from it.
                let n1 = M * cast(u32, (CeltBands[.startBand + 1] - CeltBands[.startBand]))
                let n2 = M * cast(u32, (CeltBands[.startBand + 2] - CeltBands[.startBand + 1]))
                for j in n2 - n1
                {
                    norm[n1 + j] = norm[2 * n1 - n2 + j]
                    if dualStereo do
                        norm2[n1 + j] = norm2[2 * n1 - n2 + j]
                }
            }

            let tfChange = tfRes[i]
            ctx.tfChange = tfChange
            var useScratch       = not last
            var effectiveLowband = Swag.U32.Max
            var xcm: u32
            var ycm: u32
            if lowbandOffset != 0 and (spread != SpreadAggressive or B > 1 or tfChange < 0)
            {
                let target = M * cast(u32, CeltBands[lowbandOffset])
                effectiveLowband = target >= normOffset + n ? target - normOffset - n : 0
                var foldStart = lowbandOffset
                while true
                {
                    foldStart -= 1
                    if M * cast(u32, CeltBands[foldStart]) <= effectiveLowband + normOffset do
                        break
                }

                var foldEnd = lowbandOffset - 1
                while true
                {
                    foldEnd += 1
                    if not (foldEnd < i and M * cast(u32, CeltBands[foldEnd]) < effectiveLowband + normOffset + n) do
                        break
                }

                while true
                {
                    foldEnd += 1
                    if M * cast(u32, CeltBands[foldEnd]) >= effectiveLowband + normOffset + n do
                        break
                }

                xcm = 0
                ycm = 0
                for f in foldStart until foldEnd
                {
                    xcm |= cast(u32, collapseMasks[f * C])
                    ycm |= cast(u32, collapseMasks[f * C + C - 1])
                }
            }
            else
            {
                xcm = (1'u32 << B) - 1
                ycm = xcm
            }

            if dualStereo and i == intensity
            {
                dualStereo = false
                for j in M * cast(u32, CeltBands[i]) - normOffset do
                    norm[j] = 0.5 * (norm[j] + norm2[j])
            }

            var lowband:  [*] f32?
            var lowband2: [*] f32?
            if effectiveLowband != Swag.U32.Max
            {
                lowband  = norm + effectiveLowband
                lowband2 = norm2 + effectiveLowband
            }

            var lowbandOut:  [*] f32?
            var lowbandOut2: [*] f32?
            if not last
            {
                lowbandOut  = norm + M * cast(u32, CeltBands[i]) - normOffset
                lowbandOut2 = norm2 + M * cast(u32, CeltBands[i]) - normOffset
            }

            if dualStereo
            {
                xcm = .quantBand(&ctx, x, n, b / 2, B, lowband, lm, lowbandOut, 1.0, useScratch, xcm, dec)
                ycm = .quantBand(&ctx, unwrap y, n, b / 2, B, lowband2, lm, lowbandOut2, 1.0, useScratch, ycm, dec)
            }
            else
            {
                if y do
                    xcm = .quantBandStereo(&ctx, x, y, n, b, B, lowband, lm, lowbandOut, useScratch, xcm | ycm, dec)
                else do
                    xcm = .quantBand(&ctx, x, n, b, B, lowband, lm, lowbandOut, 1.0, useScratch, xcm | ycm, dec)
                ycm = xcm
            }

            collapseMasks[i * C]         = cast(u8, xcm)
            collapseMasks[i * C + C - 1] = cast(u8, ycm)
            balance                      += .pulses[i] + tell
            updateLowband                = b > cast(s32, (n << BitRes))
            ctx.avoidSplitNoise          = false
        }

        .rng = ctx.seed
    }

    mtd antiCollapse(collapseMasks: const [*] u8, lm: u32, size: u32, seedIn: u32)
    {
        let C    = .streamChannels
        var seed = seedIn
        for i in .startBand until .endBand
        {
            let n0     = cast(u32, (CeltBands[i + 1] - CeltBands[i]))
            let depth  = cast(u32, ((1 + .pulses[i]) / cast(s32, n0))) >> lm
            let thresh = 0.5 * celtExp2(-0.125 * cast(f32, depth))
            let sqrt1  = celtRsqrt(cast(f32, (n0 << lm)))
            for c in C
            {
                var prev1 = .oldLogE[c * CeltBandCount + i]
                var prev2 = .oldLogE2[c * CeltBandCount + i]
                if C == 1
                {
                    prev1 = Math.max(prev1, .oldLogE[CeltBandCount + i])
                    prev2 = Math.max(prev2, .oldLogE2[CeltBandCount + i])
                }

                let ediff = Math.max(0.0'f32, .oldBandE[c * CeltBandCount + i] - Math.min(prev1, prev2))
                var r     = 2.0 * celtExp2(-ediff)
                if lm == 3 do
                    r *= 1.41421356'f32
                r = Math.min(thresh, r) * sqrt1
                let x = .spectrum.storage() + c * size + (cast(u32, CeltBands[i]) << lm)
                var renormalize = false
                for k in 1'u32 << lm
                {
                    if not (cast(u32, collapseMasks[i * C + c]) & (1'u32 << k))
                    {
                        for j in n0
                        {
                            seed = lcgRand(seed)
                            x[(j << lm) + k] = seed & 0x8000 ? r : -r
                        }

                        renormalize = true
                    }
                }

                if renormalize do
                    .renormaliseVector(x, n0 << lm, 1.0)
            }
        }
    }

    mtd denormaliseBands(freq: [*] f32, x: const [*] f32, bandLogE: const [*] f32, effEnd, M: u32, silence: bool)
    {
        let N     = M * CeltShortSize
        var bound = M * cast(u32, CeltBands[effEnd])
        var start = .startBand
        var end   = effEnd
        if silence
        {
            bound = 0
            start = 0
            end   = 0
        }

        Memory.clear(freq, cast(u64, M * cast(u32, CeltBands[start])) * #sizeof(f32))
        for i in start until end
        {
            let lg     = bandLogE[i] + CeltEnergyMeans[i]
            let g      = celtExp2(Math.min(32.0'f32, lg))
            let lo     = M * cast(u32, CeltBands[i])
            let hi     = M * cast(u32, CeltBands[i + 1])
            let packed = (hi - lo) & ~3'u32
            for group in packed / 4
            {
                let j = lo + 4 * group
                Simd.store(freq + j, Simd.load(x + j) * g)
            }

            for j in lo + packed until hi do
                freq[j] = x[j] * g
        }

        Memory.clear(freq + bound, cast(u64, N - bound) * #sizeof(f32))
    }

    // Every call covers whole four-sample groups. The pitch taps precede the
    // group being overwritten because the lag is at least fifteen samples.
    mtd combFilter(samples: [*] f32, t0In, t1In: s32, n: u32, g0, g1: f32, tapset0, tapset1: u32, overlap: u32)
    {
        if g0 == 0 and g1 == 0 do
            return

        let t0  = cast(u32, Math.max(t0In, CombMinPeriod))
        let t1  = cast(u32, Math.max(t1In, CombMinPeriod))
        let g00 = g0 * CombGains[tapset0, 0]
        let g01 = g0 * CombGains[tapset0, 1]
        let g02 = g0 * CombGains[tapset0, 2]
        let g10 = g1 * CombGains[tapset1, 0]
        let g11 = g1 * CombGains[tapset1, 1]
        let g12 = g1 * CombGains[tapset1, 2]

        // The decode buffer retains the two extra taps on either side of the pitch lag.
        let past0  = samples - (t0 + 2)
        let past1  = samples - (t1 + 2)
        let fade   = g0 == g1 and t0 == t1 and tapset0 == tapset1 ? 0 : overlap
        let window = cast(const [*] f32, &CeltWindow[0])
        for block in fade / 4
        {
            let i      = 4 * block
            let w      = Simd.load(window + i)
            let f      = w * w
            let old    = Simd.splat(1.0'f32) - f
            let result = Simd.load(samples + i) +
                         old * g00 * Simd.load(past0 + i + 2) +
                         old * g01 * (Simd.load(past0 + i + 3) + Simd.load(past0 + i + 1)) +
                         old * g02 * (Simd.load(past0 + i + 4) + Simd.load(past0 + i)) +
                         f * g10 * Simd.load(past1 + i + 2) +
                         f * g11 * (Simd.load(past1 + i + 3) + Simd.load(past1 + i + 1)) +
                         f * g12 * (Simd.load(past1 + i + 4) + Simd.load(past1 + i))
            Simd.store(samples + i, result)
        }

        if g1 == 0 do
            return
        for block in fade / 4 until n / 4
        {
            let i      = 4 * block
            let result = Simd.load(samples + i) +
                         g10 * Simd.load(past1 + i + 2) +
                         g11 * (Simd.load(past1 + i + 3) + Simd.load(past1 + i + 1)) +
                         g12 * (Simd.load(past1 + i + 4) + Simd.load(past1 + i))
            Simd.store(samples + i, result)
        }
    }

    // A block's four de-emphasis steps form a weighted prefix sum. The next
    // block depends only on the final lane, so both channels can stay packed.
    mtd deemphasizePcm16(left, right: const [*] f32, count: u32, pcm: [*] s16)
    {
        #[Swag.Inline]
        func filter(input, memory: Simd.F32x4)->Simd.F32x4
        {
            const DecaySquared = CeltPreemphasis * CeltPreemphasis
            const Decay        = cast(Simd.F32x4, [1.0'f32, CeltPreemphasis, DecaySquared, DecaySquared * CeltPreemphasis])
            const PreviousOne  = cast(Simd.U32x4, [4'u32, 0, 1, 2])
            const PreviousTwo  = cast(Simd.U32x4, [4'u32, 4, 0, 1])
            let zero   = Simd.splat(0.0'f32)
            let values = input + 1e-30'f32
            let pairs  = values + Swag.vecShuffle2(values, zero, PreviousOne) * CeltPreemphasis
            return pairs + Swag.vecShuffle2(pairs, zero, PreviousTwo) * DecaySquared + memory * Decay
        }

        const Last       = cast(Simd.U32x4, [3'u32, 3, 3, 3])
        const Interleave = cast(Simd.U16x8, [0'u16, 4, 1, 5, 2, 6, 3, 7])
        var leftMemory = Simd.splat(.preemphasisMemory[0])
        if .channels == 2
        {
            var rightMemory = Simd.splat(.preemphasisMemory[1])
            for block in count / 4
            {
                let at = 4 * block
                let l  = filter(Simd.load(left + at), leftMemory)
                let r  = filter(Simd.load(right + at), rightMemory)
                leftMemory  = CeltPreemphasis * Swag.vecShuffle(l, Last)
                rightMemory = CeltPreemphasis * Swag.vecShuffle(r, Last)
                let packed = Simd.packSigned(roundOpusPcm16(l), roundOpusPcm16(r))
                Simd.store(pcm + 2 * at, Swag.vecShuffle(packed, Interleave))
            }

            .preemphasisMemory[1] = rightMemory[0]
        }
        else
        {
            for block in count / 8
            {
                let at   = 8 * block
                let low  = filter(Simd.load(left + at), leftMemory)
                let high = filter(Simd.load(left + at + 4), CeltPreemphasis * Swag.vecShuffle(low, Last))
                leftMemory = CeltPreemphasis * Swag.vecShuffle(high, Last)
                Simd.store(pcm + at, Simd.packSigned(roundOpusPcm16(low), roundOpusPcm16(high)))
            }
        }

        .preemphasisMemory[0] = leftMemory[0]
    }

    // Decodes one frame of `frameSize` samples through `dec`, which reads `data`, and writes the
    // de-emphasized output interleaved over the output channels. A CELT-only
    // frame without gain can write directly to the caller's PCM16 buffer.
    mtd decodeFrame(data: const [..] u8, dec: *RangeDecoder, frameSize: u32, pcm: [*] f32, direct: [*] s16? = null) fail
    {
        var lm = 0'u32
        while lm <= CeltMaxLM and (CeltShortSize << lm) != frameSize do
            lm += 1
        if lm > CeltMaxLM do
            fail InvalidFormatError{"Opus CELT frame size is not one the mode supports"}
        let M      = 1'u32 << lm
        let N      = M * CeltShortSize
        let C      = .streamChannels
        let CC     = .channels
        let len    = cast(s32, data.count)
        let effEnd = Math.min(.endBand, CeltBandCount)

        if C == 1
        {
            for i in CeltBandCount do
                .oldBandE[i] = Math.max(.oldBandE[i], .oldBandE[CeltBandCount + i])
        }

        var totalBits = len * 8
        var tell      = dec.tell()
        var silence   = false
        if tell >= totalBits do
            silence = true
        elif tell == 1 do
            silence = dec.decodeBit(15)
        if silence
        {
            tell = len * 8
            dec.bitsTotal += tell - dec.tell()
        }

        var postfilterGain   = 0.0'f32
        var postfilterPitch  = 0's32
        var postfilterTapset = 0'u32
        if .startBand == 0 and tell + 16 <= totalBits
        {
            if dec.decodeBit(1)
            {
                let octave = dec.decodeUint(6)
                postfilterPitch = cast(s32, ((16'u32 << octave) + dec.decodeBits(4 + octave))) - 1
                let qg = dec.decodeBits(3)
                if dec.tell() + 2 <= totalBits do
                    postfilterTapset = dec.decodeIcdf(TapsetIcdf, 2)
                postfilterGain = 0.09375 * cast(f32, (qg + 1))
            }

            tell = dec.tell()
        }

        var isTransient = false
        if lm > 0 and tell + 3 <= totalBits
        {
            isTransient = dec.decodeBit(3)
            tell        = dec.tell()
        }

        let shortBlocks = isTransient
        let intra       = tell + 3 <= totalBits ? dec.decodeBit(3) : false
        .unquantCoarseEnergy(intra, dec, lm)

        var tfRes: [CeltBandCount] s32
        .tfDecode(isTransient, &tfRes[0], lm, dec)
        tell = dec.tell()
        var spread = 2'u32
        if tell + 4 <= totalBits do
            spread = dec.decodeIcdf(SpreadIcdf, 5)

        var cap: [CeltBandCount] s32
        for i in CeltBandCount
        {
            let width = cast(s32, (CeltBands[i + 1] - CeltBands[i])) << lm
            cap[i] = ((cast(s32, CeltCacheCaps[CeltBandCount * (2 * lm + C - 1) + i]) + 64) * cast(s32, C) * width) >> 2
        }

        var offsets: [CeltBandCount] s32
        var dynallocLogp = 6'u32
        totalBits <<= BitRes
        var tellFrac = cast(s32, dec.tellFrac())
        for i in .startBand until .endBand
        {
            let width    = cast(s32, C) * cast(s32, (CeltBands[i + 1] - CeltBands[i])) << lm
            let quanta   = Math.min(width << BitRes, Math.max(6's32 << BitRes, width))
            var loopLogp = dynallocLogp
            var boost    = 0's32
            while tellFrac + (cast(s32, loopLogp) << BitRes) < totalBits and boost < cap[i]
            {
                let flag = dec.decodeBit(loopLogp)
                tellFrac = cast(s32, dec.tellFrac())
                if not flag do
                    break
                boost     += quanta
                totalBits -= quanta
                loopLogp  = 1
            }

            offsets[i] = boost
            if boost > 0 do
                dynallocLogp = Math.max(2'u32, dynallocLogp - 1)
        }

        var allocTrim = 5's32
        if tellFrac + (6's32 << BitRes) <= totalBits do
            allocTrim = cast(s32, dec.decodeIcdf(TrimIcdf, 7))

        var bits = ((len * 8) << BitRes) - cast(s32, dec.tellFrac()) - 1
        var antiCollapseRsv = 0's32
        if isTransient and lm >= 2 and bits >= (cast(s32, (lm + 2)) << BitRes) do
            antiCollapseRsv = 1's32 << BitRes
        bits -= antiCollapseRsv

        var intensity  = 0'u32
        var dualStereo = false
        var balance    = 0's32
        var fineQuant:    [CeltBandCount] s32
        var finePriority: [CeltBandCount] s32
        let pulses     = .pulses.storage()
        let codedBands = .computeAllocation(&offsets[0],
                                            &cap[0],
                                            allocTrim,
                                            &intensity,
                                            &dualStereo,
                                            bits,
                                            &balance,
                                            pulses,
                                            &fineQuant[0],
                                            &finePriority[0],
                                            lm,
                                            dec)
        .unquantFineEnergy(&fineQuant[0], dec)

        for c in CC
        {
            let memory = .decodeMemory[c].storage()
            Memory.copyOverlapping(memory, memory + N, cast(u64, CeltDecodeBuffer - N + CeltOverlap) * #sizeof(f32))
        }

        var collapseMasks: [2 * CeltBandCount] u8
        .quantAllBands(shortBlocks,
                       spread,
                       dualStereo,
                       intensity,
                       &tfRes[0],
                       len * (8's32 << BitRes) - antiCollapseRsv,
                       balance,
                       dec,
                       lm,
                       codedBands,
                       &collapseMasks[0])

        var antiCollapseOn = false
        if antiCollapseRsv > 0 do
            antiCollapseOn = dec.decodeBits(1) != 0
        .unquantEnergyFinalise(&fineQuant[0], &finePriority[0], len * 8 - dec.tell(), dec)
        if antiCollapseOn do
            .antiCollapse(&collapseMasks[0], lm, N, .rng)
        if silence
        {
            for i in C * CeltBandCount do
                .oldBandE[i] = NoiseFloor
        }

        // Denormalize the channel spectra before transforming their paired blocks.
        let blocks    = shortBlocks ? M : 1
        let blockSize = shortBlocks ? CeltShortSize : N
        let shift     = shortBlocks ? CeltMaxLM : CeltMaxLM - lm
        let spectrum  = .spectrum.storage()
        let left      = .frequency.storage()
        .denormaliseBands(left, spectrum, &.oldBandE[0], effEnd, M, silence)

        var right = left
        if C == 2
        {
            right = left + CeltFrameMax
            .denormaliseBands(right, spectrum + N, &.oldBandE[CeltBandCount], effEnd, M, silence)
            if CC == 1
            {
                for i in N do
                    left[i] = 0.5 * (left[i] + right[i])
            }
        }

        let leftOut = .decodeMemory[0].storage() + CeltDecodeBuffer - N
        if CC == 2
        {
            let rightOut = .decodeMemory[1].storage() + CeltDecodeBuffer - N
            for b in blocks
            {
                let offset = blockSize * b
                .mdct.backward(left + b, blocks, leftOut + offset, shift, right + b, rightOut + offset)
            }
        }
        else
        {
            for b in blocks do
                .mdct.backward(left + b, blocks, leftOut + blockSize * b, shift)
        }

        for c in CC
        {
            let outSyn = .decodeMemory[c].storage() + CeltDecodeBuffer - N
            .postfilterPeriod    = Math.max(.postfilterPeriod, CombMinPeriod)
            .postfilterPeriodOld = Math.max(.postfilterPeriodOld, CombMinPeriod)
            .combFilter(outSyn,
                        .postfilterPeriodOld,
                        .postfilterPeriod,
                        CeltShortSize,
                        .postfilterGainOld,
                        .postfilterGain,
                        .postfilterTapsetOld,
                        .postfilterTapset,
                        CeltOverlap)
            if lm != 0 do
                .combFilter(outSyn + CeltShortSize,
                            .postfilterPeriod,
                            postfilterPitch,
                            N - CeltShortSize,
                            .postfilterGain,
                            postfilterGain,
                            .postfilterTapset,
                            postfilterTapset,
                            CeltOverlap)
        }

        .postfilterPeriodOld = .postfilterPeriod
        .postfilterGainOld   = .postfilterGain
        .postfilterTapsetOld = .postfilterTapset
        .postfilterPeriod    = postfilterPitch
        .postfilterGain      = postfilterGain
        .postfilterTapset    = postfilterTapset
        if lm != 0
        {
            .postfilterPeriodOld = .postfilterPeriod
            .postfilterGainOld   = .postfilterGain
            .postfilterTapsetOld = .postfilterTapset
        }

        if C == 1
        {
            for i in CeltBandCount do
                .oldBandE[CeltBandCount + i] = .oldBandE[i]
        }

        if not isTransient
        {
            for i in 2 * CeltBandCount
            {
                .oldLogE2[i] = .oldLogE[i]
                .oldLogE[i]  = .oldBandE[i]
            }
        }
        else
        {
            for i in 2 * CeltBandCount do
                .oldLogE[i] = Math.min(.oldLogE[i], .oldBandE[i])
        }

        let increase = cast(f32, Math.min(160'u32, M)) * 0.001'f32
        for i in 2 * CeltBandCount do
            .backgroundLogE[i] = Math.min(.backgroundLogE[i] + increase, .oldBandE[i])
        for c in 2
        {
            for i in .startBand
            {
                .oldBandE[c * CeltBandCount + i] = 0
                .oldLogE[c * CeltBandCount + i]  = NoiseFloor
                .oldLogE2[c * CeltBandCount + i] = NoiseFloor
            }

            for i in .endBand until CeltBandCount
            {
                .oldBandE[c * CeltBandCount + i] = 0
                .oldLogE[c * CeltBandCount + i]  = NoiseFloor
                .oldLogE2[c * CeltBandCount + i] = NoiseFloor
            }
        }

        .rng = dec.range

        if direct
        {
            let rightOut = .decodeMemory[1].storage() + CeltDecodeBuffer - N
            .deemphasizePcm16(leftOut, rightOut, N, direct)
        }
        else
        {
            // The stereo recurrences are independent. Advance both while writing interleaved PCM.
            var leftMemory = .preemphasisMemory[0]
            if CC == 2
            {
                let right       = .decodeMemory[1].storage() + CeltDecodeBuffer - N
                var rightMemory = .preemphasisMemory[1]
                for j in N
                {
                    let l = leftOut[j] + 1e-30'f32 + leftMemory
                    let r = right[j] + 1e-30'f32 + rightMemory
                    leftMemory     = CeltPreemphasis * l
                    rightMemory    = CeltPreemphasis * r
                    pcm[2 * j]     = l * (1.0 / 32768.0)
                    pcm[2 * j + 1] = r * (1.0 / 32768.0)
                }

                .preemphasisMemory[1] = rightMemory
            }
            else
            {
                for j in N
                {
                    let sample = leftOut[j] + 1e-30'f32 + leftMemory
                    leftMemory = CeltPreemphasis * sample
                    pcm[j]     = sample * (1.0 / 32768.0)
                }
            }

            .preemphasisMemory[0] = leftMemory
        }

        if dec.tell() > 8 * len do
            fail InvalidFormatError{"Opus CELT frame reads past its end"}
    }
}

private func computeQn(n, b, offset, pulseCap: s32, stereo: bool)->s32
{
    var n2 = 2 * n - 1
    if stereo and n == 2 do
        n2 -= 1
    var qb = (b + n2 * offset) / n2
    qb = Math.min(b - pulseCap - (4's32 << BitRes), qb)
    qb = Math.min(8's32 << BitRes, qb)
    if qb < (1's32 << BitRes >> 1) do
        return 1
    var qn = Exp2Table8[cast(u32, (qb & 7))] >> cast(u32, (14 - (qb >> BitRes)))
    qn = (qn + 1) >> 1 << 1
    return qn
}
