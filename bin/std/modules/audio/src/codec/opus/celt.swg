//! Format: Opus CELT layer decoder.
//! Supported: The 48 kHz mode of RFC 6716 clause 4.3: coarse and fine energy, transient and time-frequency decisions, dynamic allocation, pyramid vector quantization with spreading and folding, intensity and dual stereo, anti-collapse, the overlapped MDCT with its short-block form, the pitch post-filter, and de-emphasis, for mono or stereo streams on mono or stereo outputs.
//! Not supported: Packet-loss concealment, custom modes, and the decoder-side filters a lost frame would need.
//! Role: This file owns CELT frame syntax, band reconstruction, the inverse transform, and the time-domain filters.
//
#global namespace Opus

using Core, Core.Errors, Core.Math

internal const CeltBandCount = 21'u32
internal const CeltOverlap = 120'u32
internal const CeltShortSize = 120'u32
internal const CeltFrameMax = 960'u32
private const CeltMaxLM = 3'u32
private const CeltAllocVectors = 11'u32
private const CeltPreemphasis = 0.85000610'f32
private const CeltDecodeBuffer = 2048'u32
private const CeltMdctSize = 1920'u32
private const CeltFftMax = 480'u32
private const MaxFineBits = 8's32
private const FineOffset = 21's32
private const QThetaOffset = 4's32
private const QThetaOffsetTwoPhase = 16's32
private const AllocSteps = 6'u32
private const LogMaxPseudo = 6'u32
private const CombMinPeriod = 15's32
private const CombMaxPeriod = 1024'u32
private const SpreadNone = 0'u32
private const SpreadAggressive = 3'u32
private const LaplaceMinP = 1'u32
private const LaplaceNMin = 16'u32
private const NoiseFloor = -28.0'f32

private const TrimIcdf: [11] u8 = [126, 124, 119, 109, 87, 41, 19, 9, 4, 2, 0]
private const SpreadIcdf: [4] u8 = [25, 23, 2, 0]
private const TapsetIcdf: [3] u8 = [2, 1, 0]
private const SmallEnergyIcdf: [3] u8 = [2, 1, 0]
private const PredCoef: [4] f32 = [29440.0 / 32768.0, 26112.0 / 32768.0, 21248.0 / 32768.0, 16384.0 / 32768.0]
private const BetaCoef: [4] f32 = [30147.0 / 32768.0, 22282.0 / 32768.0, 12124.0 / 32768.0, 6554.0 / 32768.0]
private const BetaIntra = 4915.0'f32 / 32768.0'f32
private const CombGains: [3, 3] f32 = [[0.3066406250, 0.2170410156, 0.1296386719], [0.4638671875, 0.2680664062, 0.0], [0.7998046875, 0.1000976562, 0.0]]
private const SpreadFactor: [3] s32 = [15, 10, 5]
private const Exp2Table8: [8] s32 = [16384, 17866, 19483, 21247, 23170, 25267, 27554, 30048]
private const BitInterleave: [16] u32 = [0, 1, 1, 1, 2, 3, 3, 3, 2, 3, 3, 3, 2, 3, 3, 3]
private const BitDeinterleave: [16] u32 = [0x00, 0x03, 0x0C, 0x0F, 0x30, 0x33, 0x3C, 0x3F, 0xC0, 0xC3, 0xCC, 0xCF, 0xF0, 0xF3, 0xFC, 0xFF]

private func celtExp2(x: f32)->f32 => cast(f32) Math.exp(0.6931471805599453 * cast(f64) x)
private func celtLog2(x: f32)->f32 => cast(f32) (1.4426950408889634 * Math.log(cast(f64) x))
private func celtRsqrt(x: f32)->f32 => cast(f32) (1.0 / Math.sqrt(cast(f64) x))

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
    let lc = cast(s32) ilog(cast(u32) icos)
    let ls = cast(s32) ilog(cast(u32) isin)
    let c  = icos << cast(u32) (15 - lc)
    let s  = isin << cast(u32) (15 - ls)
    return (ls - lc) * (1 << 11) + fracMul16(s, fracMul16(s, -2597) + 7932) - fracMul16(c, fracMul16(c, -2597) + 7932)
}

private func isqrt32(value: u32)->u32
{
    var g      = 0'u32
    var bshift = cast(s32) (ilog(value) - 1) >> 1
    var b      = 1'u32 << cast(u32) bshift
    var v      = value
    while bshift >= 0
    {
        let t = ((g << 1) + b) << cast(u32) bshift
        if t <= v
        {
            g += b
            v -= t
        }

        b      >>= 1
        bshift -= 1
    }

    return g
}

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
        fl = fs
        fs = laplaceFreq1(fs, decay) + LaplaceMinP
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
            value += cast(s32) di
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

// One complex FFT of a fixed composite length, evaluated by decimation in time over its factors.
private struct CeltFft
{
    n:       u32
    cosine:  Array'f32
    sine:    Array'f32
}

private impl CeltFft
{
    func create(n: u32)->CeltFft
    {
        var result: retval
        result.n = n
        result.cosine.resize(n)
        result.sine.resize(n)
        for k in n
        {
            let angle = -2.0 * Math.ConstF64.Pi * cast(f64) k / cast(f64) n
            result.cosine[k] = cast(f32) Math.cos(angle)
            result.sine[k]   = cast(f32) Math.sin(angle)
        }

        return result
    }

    // Writes the transform of the `count` interleaved complex points read from `input` with
    // `stride` points between them into `output`, in natural order.
    mtd transform(output: [*] f32, input: const [*] f32, stride, count, twiddleStride: u32)
    {
        if count == 1
        {
            output[0] = input[0]
            output[1] = input[1]
            return
        }

        var radix = 5'u32
        if count % 2 == 0 do
            radix = 2
        elif count % 3 == 0 do
            radix = 3
        elif count % 5 != 0 do
            radix = count
        let m = count / radix
        for r in radix do
            .transform(output + 2 * r * m, input + 2 * r * stride, stride * radix, m, twiddleStride * radix)

        var re: [8] f32
        var im: [8] f32
        var outRe: [8] f32
        var outIm: [8] f32
        for k in m
        {
            for r in radix
            {
                re[r] = output[2 * (r * m + k)]
                im[r] = output[2 * (r * m + k) + 1]
            }

            for q in radix
            {
                var sumRe = 0.0'f32
                var sumIm = 0.0'f32
                for r in radix
                {
                    let index = (cast(u64) twiddleStride * cast(u64) (k + q * m) * cast(u64) r) % .n
                    let c     = .cosine[index]
                    let s     = .sine[index]
                    sumRe += re[r] * c - im[r] * s
                    sumIm += re[r] * s + im[r] * c
                }

                outRe[q] = sumRe
                outIm[q] = sumIm
            }

            for q in radix
            {
                output[2 * (k + q * m)]     = outRe[q]
                output[2 * (k + q * m) + 1] = outIm[q]
            }
        }
    }
}

// The inverse MDCT of the 48 kHz mode at its four block sizes, mirrored for time-domain aliasing
// cancellation exactly as the reference decoder lays it out.
private struct CeltMdct
{
    trig:   [4] Array'f32
    fft:    [4] CeltFft
    input:  Array'f32
    output: Array'f32
}

private impl CeltMdct
{
    func create()->CeltMdct
    {
        var result: retval
        var n = CeltMdctSize
        for shift in 4
        {
            let half = n / 2
            result.trig[shift].resize(half)
            for i in half do
                result.trig[shift][i] = cast(f32) Math.cos(2.0 * Math.ConstF64.Pi * (cast(f64) i + 0.125) / cast(f64) n)
            result.fft[shift] = CeltFft.create(n / 4)
            n /= 2
        }

        result.input.resize(2 * CeltFftMax)
        result.output.resize(2 * CeltFftMax)
        return result
    }

    // Reconstructs one block from `spectrum`, read with `stride` between coefficients, into
    // `out`, whose first half overlap holds the tail the previous block left there.
    mtd backward(spectrum: const [*] f32, stride: u32, out: [*] f32, shift: u32)
    {
        let n  = CeltMdctSize >> shift
        let n2 = n / 2
        let n4 = n / 4
        let t  = .trig[shift].buffer!
        let fftIn  = .input.buffer!
        let fftOut = .output.buffer!

        for i in n4
        {
            let x1 = spectrum[2 * stride * i]
            let x2 = spectrum[stride * (n2 - 1 - 2 * i)]
            fftIn[2 * i]     = x1 * t[i] - x2 * t[n4 + i]
            fftIn[2 * i + 1] = x2 * t[i] + x1 * t[n4 + i]
        }

        .fft[shift].transform(fftOut, fftIn, 1, n4, 1)
        let yp = out + CeltOverlap / 2
        Memory.copy(yp, fftOut, cast(u64) n2 * #sizeof(f32))

        var a = 0'u32
        var b = n2 - 2
        for i in (n4 + 1) / 2
        {
            let re  = yp[a + 1]
            let im  = yp[a]
            let yr  = re * t[i] + im * t[n4 + i]
            let yi  = re * t[n4 + i] - im * t[i]
            let re2 = yp[b + 1]
            let im2 = yp[b]
            yp[a]     = yr
            yp[b + 1] = yi
            let t0 = t[n4 - i - 1]
            let t1 = t[n2 - i - 1]
            yp[b]     = re2 * t0 + im2 * t1
            yp[a + 1] = re2 * t1 - im2 * t0
            a += 2
            b -= 2
        }

        var lowIndex  = 0'u32
        var highIndex = CeltOverlap - 1
        for i in CeltOverlap / 2
        {
            let x1 = out[highIndex]
            let x2 = out[lowIndex]
            out[lowIndex]  = CeltWindow[highIndex] * x2 - CeltWindow[lowIndex] * x1
            out[highIndex] = CeltWindow[lowIndex] * x2 + CeltWindow[highIndex] * x1
            lowIndex  += 1
            highIndex -= 1
        }
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
    band:          u32
    intensity:     u32
    spread:        u32
    tfChange:      s32
    remainingBits: s32
    seed:          u32
    disableInv:    bool
    avoidSplitNoise: bool
    lm:            u32
}

// Decodes CELT frames of the 48 kHz mode, carrying the overlap, energy, and post-filter state
// between them.
internal struct CeltDecoder
{
    channels:       u32          // Output channels.
    streamChannels: u32          // Channels coded in the frame.
    startBand:      u32
    endBand:        u32
    disableInv:     bool
    rng:            u32
    postfilterPeriod:     s32
    postfilterPeriodOld:  s32
    postfilterGain:       f32
    postfilterGainOld:    f32
    postfilterTapset:     u32
    postfilterTapsetOld:  u32
    preemphasisMemory:    [2] f32
    decodeMemory:         [2] Array'f32     // CeltDecodeBuffer + CeltOverlap samples per channel.
    oldBandE:             [2 * CeltBandCount] f32
    oldLogE:              [2 * CeltBandCount] f32
    oldLogE2:             [2 * CeltBandCount] f32
    backgroundLogE:       [2 * CeltBandCount] f32
    mdct:                 CeltMdct
    spectrum:             Array'f32     // Normalised MDCT coefficients of both channels.
    frequency:            Array'f32     // Denormalised coefficients of one channel.
    norm:                 Array'f32     // Folding source for both channels.
    scratch:              Array'f32     // Lowband copy while a band is recombined.
    pulses:               Array's32
}

internal impl CeltDecoder
{
    func create(channels: u32)->CeltDecoder
    {
        var result: retval
        result.channels       = channels
        result.streamChannels = channels
        result.endBand        = CeltBandCount
        result.disableInv     = channels == 1
        for c in 2 do
            result.decodeMemory[c].resize(CeltDecodeBuffer + CeltOverlap)
        result.mdct = CeltMdct.create()
        result.spectrum.resize(2 * CeltFrameMax)
        result.frequency.resize(CeltFrameMax)
        result.norm.resize(2 * 8 * 78)
        result.scratch.resize(8 * 22)
        result.pulses.resize(CeltFrameMax)
        result.reset()
        return result
    }

    mtd reset()
    {
        .rng                 = 0
        .postfilterPeriod    = 0
        .postfilterPeriodOld = 0
        .postfilterGain      = 0
        .postfilterGainOld   = 0
        .postfilterTapset    = 0
        .postfilterTapsetOld = 0
        .preemphasisMemory[0] = 0
        .preemphasisMemory[1] = 0
        for c in 2 do
            Memory.set(.decodeMemory[c].buffer!, 0, .decodeMemory[c].count * #sizeof(f32))
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
        let budget = cast(s32) dec.storage * 8
        var prev:  [2] f32
        let model = intra ? 1'u32 : 0
        for i in .startBand until .endBand
        {
            for c in .streamChannels
            {
                var qi: s32
                let tell = dec.tell()
                if budget - tell >= 15
                {
                    let pi = 2 * Math.min(i, 20)
                    qi = laplaceDecode(dec, cast(u32) CeltEnergyProbabilities[lm, model, pi] << 7, cast(u32) CeltEnergyProbabilities[lm, model, pi + 1] << 6)
                }
                elif budget - tell >= 2
                {
                    let raw = cast(s32) dec.decodeIcdf(SmallEnergyIcdf, 2)
                    qi = (raw >> 1) ^ -(raw & 1)
                }
                elif budget - tell >= 1 do
                    qi = dec.decodeBit(1) ? -1 : 0
                else do
                    qi = -1

                let q     = cast(f32) qi
                let index = i + c * CeltBandCount
                .oldBandE[index] = Math.max(-9.0'f32, .oldBandE[index])
                let tmp = coef * .oldBandE[index] + prev[c] + q
                .oldBandE[index] = tmp
                prev[c]          = prev[c] + q - beta * q
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
                let q2     = cast(f32) dec.decodeBits(cast(u32) fineQuant[i])
                let offset = (q2 + 0.5) * cast(f32) (1 << cast(u32) (14 - fineQuant[i])) * (1.0 / 16384.0) - 0.5
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
                if left < cast(s32) .streamChannels do
                    break
                if fineQuant[i] >= MaxFineBits or finePriority[i] != cast(s32) priority do
                    continue
                for c in .streamChannels
                {
                    let q2     = cast(f32) dec.decodeBits(1)
                    let offset = (q2 - 0.5) * cast(f32) (1 << cast(u32) (14 - fineQuant[i] - 1)) * (1.0 / 16384.0)
                    .oldBandE[i + c * CeltBandCount] += offset
                    left -= 1
                }
            }
        }
    }

    mtd tfDecode(isTransient: bool, tfRes: [*] s32, lm: u32, dec: *RangeDecoder)
    {
        var budget = cast(s32) dec.storage * 8
        var tell   = dec.tell()
        var logp   = isTransient ? 2'u32 : 4
        let reserve = lm > 0 and tell + cast(s32) logp + 1 <= budget
        if reserve do
            budget -= 1
        var changed = 0's32
        var current = 0's32
        for i in .startBand until .endBand
        {
            if tell + cast(s32) logp <= budget
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
        if reserve and CeltTfSelectTable[lm, row + cast(u32) changed] != CeltTfSelectTable[lm, row + 2 + cast(u32) changed] do
            select = dec.decodeBit(1) ? 1 : 0
        for i in .startBand until .endBand do
            tfRes[i] = cast(s32) CeltTfSelectTable[lm, row + 2 * cast(u32) select + cast(u32) tfRes[i]]
    }

    // Bit allocation, clause 4.3.3: interpolates between the static allocation rows that bracket
    // the budget and decides which bands are skipped or coded with intensity or dual stereo.
    mtd computeAllocation(offsets, cap: const [*] s32, allocTrim: s32, intensity: *u32, dualStereo: *bool, totalBits: s32, balance: *s32, pulses, ebits, finePriority: [*] s32, lm: u32, dec: *RangeDecoder)->u32
    {
        let C     = cast(s32) .streamChannels
        let start = .startBand
        let end   = .endBand
        var total = Math.max(totalBits, 0)
        var skipStart = start
        let skipRsv   = total >= 1's32 << BitRes ? 1's32 << BitRes : 0
        total -= skipRsv
        var intensityRsv  = 0's32
        var dualStereoRsv = 0's32
        if C == 2
        {
            intensityRsv = cast(s32) CeltLog2FracTable[end - start]
            if intensityRsv > total do
                intensityRsv = 0
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
            let width = cast(s32) (CeltBands[j + 1] - CeltBands[j])
            thresh[j]     = Math.max(C << BitRes, ((3 * width) << lm << BitRes) >> 4)
            trimOffset[j] = (C * width * (allocTrim - 5 - cast(s32) lm) * cast(s32) (end - j - 1) * (1 << (lm + BitRes))) >> 6
            if (width << lm) == 1 do
                trimOffset[j] -= C << BitRes
        }

        var lo = 1's32
        var hi = cast(s32) CeltAllocVectors - 1
        while lo <= hi
        {
            var done = false
            var psum = 0's32
            let mid  = (lo + hi) >> 1
            var j    = end
            while j > start
            {
                j -= 1
                let width = cast(s32) (CeltBands[j + 1] - CeltBands[j])
                var bitsj = ((C * width * cast(s32) CeltBandAllocation[cast(u32) mid, j]) << lm) >> 2
                if bitsj > 0 do
                    bitsj = Math.max(0's32, bitsj + trimOffset[j])
                bitsj += offsets[j]
                if bitsj >= thresh[j] or done
                {
                    done = true
                    psum += Math.min(bitsj, cap[j])
                }
                elif bitsj >= C << BitRes do
                    psum += C << BitRes
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
            let width  = cast(s32) (CeltBands[j + 1] - CeltBands[j])
            var bits1j = ((C * width * cast(s32) CeltBandAllocation[cast(u32) lo, j]) << lm) >> 2
            var bits2j = hi >= cast(s32) CeltAllocVectors ? cap[j] : ((C * width * cast(s32) CeltBandAllocation[cast(u32) hi, j]) << lm) >> 2
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
        let logM       = cast(s32) lm << BitRes
        var ilo = 0's32
        var ihi = 1's32 << AllocSteps
        var psum: s32
        for AllocSteps
        {
            let mid  = (ilo + ihi) >> 1
            psum = 0
            var done = false
            var j = end
            while j > start
            {
                j -= 1
                let tmp = bits1[j] + ((mid * bits2[j]) >> AllocSteps)
                if tmp >= thresh[j] or done
                {
                    done = true
                    psum += Math.min(tmp, cap[j])
                }
                elif tmp >= allocFloor do
                    psum += allocFloor
            }

            if psum > total do
                ihi = mid
            else do
                ilo = mid
        }

        psum = 0
        var done = false
        var j = end
        while j > start
        {
            j -= 1
            var tmp = bits1[j] + ((ilo * bits2[j]) >> AllocSteps)
            if tmp < thresh[j] and !done do
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
            let span     = cast(s32) (CeltBands[codedBands] - CeltBands[start])
            let percoeff = left / span
            left -= span * percoeff
            let rem       = Math.max(left - cast(s32) (CeltBands[j] - CeltBands[start]), 0)
            let bandWidth = cast(s32) (CeltBands[codedBands] - CeltBands[j])
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
                intensityRsv = cast(s32) CeltLog2FracTable[j - start]
            psum += intensityRsv
            if bandBits >= allocFloor
            {
                psum      += allocFloor
                pulses[j] = allocFloor
            }
            else do
                pulses[j] = 0
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
        let span     = cast(s32) (CeltBands[codedBands] - CeltBands[start])
        let percoeff = left / span
        left -= span * percoeff
        for k in start until codedBands do
            pulses[k] += percoeff * cast(s32) (CeltBands[k + 1] - CeltBands[k])
        for k in start until codedBands
        {
            let tmp = Math.min(left, cast(s32) (CeltBands[k + 1] - CeltBands[k]))
            pulses[k] += tmp
            left      -= tmp
        }

        var bal = 0's32
        for k in start until codedBands
        {
            let n0  = cast(s32) (CeltBands[k + 1] - CeltBands[k])
            let n   = n0 << lm
            let bit = pulses[k] + bal
            var excess: s32
            if n > 1
            {
                excess    = Math.max(bit - cap[k], 0)
                pulses[k] = bit - excess
                let den    = C * n + ((C == 2 and n > 2 and !dualStereo[] and k < intensity[]) ? 1 : 0)
                let nclogn = den * (cast(s32) CeltLogN[k] + logM)
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
                let extraFine = Math.min(excess >> (cast(u32) (stereo ? 1 : 0) + BitRes), MaxFineBits - ebits[k])
                ebits[k] += extraFine
                let extraBits = (extraFine * C) << BitRes
                finePriority[k] = extraBits >= excess - bal ? 1 : 0
                excess          -= extraBits
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

    mtd const bits2pulses(band: u32, lm: s32, bits: s32)->s32
    {
        let base = cast(u32) CeltCacheIndex[cast(u32) (lm + 1) * CeltBandCount + band]
        var lo   = 0's32
        var hi   = cast(s32) CeltCacheBits[base]
        let want = bits - 1
        for LogMaxPseudo
        {
            let mid = (lo + hi + 1) >> 1
            if cast(s32) CeltCacheBits[base + cast(u32) mid] >= want do
                hi = mid
            else do
                lo = mid
        }

        let below = lo == 0 ? -1 : cast(s32) CeltCacheBits[base + cast(u32) lo]
        return want - below <= cast(s32) CeltCacheBits[base + cast(u32) hi] - want ? lo : hi
    }

    mtd const pulses2bits(band: u32, lm: s32, pulses: s32)->s32
    {
        if !pulses do
            return 0
        let base = cast(u32) CeltCacheIndex[cast(u32) (lm + 1) * CeltBandCount + band]
        return cast(s32) CeltCacheBits[base + cast(u32) pulses] + 1
    }

    // Decodes the pulse vector of one band as the `index`-th combination of `k` pulses over `n`
    // positions, and returns the squared norm of the vector.
    mtd decodePulses(target: [*] s32, n, k: u32, dec: *RangeDecoder)->f32
    {
        var u: [160] u32
        let len = k + 2
        u[0] = 0
        u[1] = 1
        for j in 2'u32 until len do
            u[j] = (j << 1) - 1
        for 2'u32 until n
        {
            // Next row of the recurrence u[i][j] = u[i-1][j] + u[i][j-1] + u[i-1][j-1].
            var ui0 = 1'u32
            for j in 1'u32 until k + 1
            {
                let ui1 = u[1 + j] + u[j] + ui0
                u[j]    = ui0
                ui0     = ui1
            }

            u[k + 1] = ui0
        }

        var index = dec.decodeUint(u[k] + u[k + 1])
        var yy    = 0.0'f32
        var kk    = k
        for j in n
        {
            var p = u[kk + 1]
            let negative = index >= p
            if negative do
                index -= p
            var yj = cast(s32) kk
            p = u[kk]
            while p > index
            {
                kk -= 1
                p  = u[kk]
            }

            index -= p
            yj    -= cast(s32) kk
            var value = yj
            if negative do
                value = -yj
            target[j] = value
            yy += cast(f32) (value * value)

            // Previous row of the recurrence.
            var ui0 = 0'u32
            for i in 1'u32 until kk + 2
            {
                let ui1 = u[i] - u[i - 1] - ui0
                u[i - 1] = ui0
                ui0      = ui1
            }

            u[kk + 1] = ui0
        }

        return yy
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
            x[i]          = c * x1 + ms * x2
            i += 1
        }

        if len >= 2 * stride + 1
        {
            var j = len - 2 * stride - 1
            while true
            {
                let x1 = x[j]
                let x2 = x[j + stride]
                x[j + stride] = c * x2 + s * x1
                x[j]          = c * x1 + ms * x2
                if j == 0 do
                    break
                j -= 1
            }
        }
    }

    mtd expRotation(x: [*] f32, len: u32, stride, k, spread: u32)
    {
        if 2 * k >= len or spread == SpreadNone do
            return
        let factor = SpreadFactor[spread - 1]
        let gain   = cast(f32) len / cast(f32) (cast(s32) len + factor * cast(s32) k)
        let theta  = 0.5 * gain * gain
        let c      = cast(f32) Math.cos(0.5 * Math.ConstF64.Pi * cast(f64) theta)
        let s      = cast(f32) Math.cos(0.5 * Math.ConstF64.Pi * cast(f64) (1.0 - theta))
        var stride2 = 0'u32
        if len >= 8 * stride
        {
            stride2 = 1
            while (stride2 * stride2 + stride2) * stride + (stride >> 2) < len do
                stride2 += 1
        }

        let part = len / stride
        for i in stride
        {
            if stride2 do
                .expRotation1(x + i * part, part, stride2, s, c)
            .expRotation1(x + i * part, part, 1, c, s)
        }
    }

    mtd algUnquant(x: [*] f32, n, k: u32, spread, b: u32, dec: *RangeDecoder, gain: f32)->u32
    {
        var iy: [176] s32
        let ryy = .decodePulses(&iy[0], n, k, dec)
        let g   = celtRsqrt(ryy) * gain
        for i in n do
            x[i] = g * cast(f32) iy[i]
        .expRotation(x, n, b, k, spread)

        if b <= 1 do
            return 1
        let n0 = n / b
        var mask = 0'u32
        for i in b
        {
            var anyPulses = false
            for j in n0 where iy[i * n0 + j] do
                anyPulses = true
            if anyPulses do
                mask |= 1'u32 << i
        }

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
        var tmp: [1024] f32
        let n = n0 * stride
        if hadamard
        {
            let base = stride - 2
            for i in stride
            {
                for j in n0 do
                    tmp[cast(u32) CeltOrderyTable[base + i] * n0 + j] = x[j * stride + i]
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

        for i in n do
            x[i] = tmp[i]
    }

    mtd interleaveHadamard(x: [*] f32, n0, stride: u32, hadamard: bool)
    {
        var tmp: [1024] f32
        let n = n0 * stride
        if hadamard
        {
            let base = stride - 2
            for i in stride
            {
                for j in n0 do
                    tmp[j * stride + i] = x[cast(u32) CeltOrderyTable[base + i] * n0 + j]
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

        for i in n do
            x[i] = tmp[i]
    }

    mtd computeTheta(ctx: *BandContext, sctx: *SplitContext, n: u32, b: *s32, bBlocks, b0: u32, lm: s32, stereo: bool, fill: *u32, dec: *RangeDecoder)
    {
        let i        = ctx.band
        let pulseCap = cast(s32) CeltLogN[i] + lm * (1's32 << BitRes)
        let offset   = (pulseCap >> 1) - cast(s32) (stereo and n == 2 ? QThetaOffsetTwoPhase : QThetaOffset)
        var qn       = computeQn(cast(s32) n, b[], offset, pulseCap, stereo)
        if stereo and i >= ctx.intensity do
            qn = 1
        let tell   = cast(s32) dec.tellFrac()
        var itheta = 0's32
        var inv    = false
        if qn != 1
        {
            if stereo and n > 2
            {
                let p0 = 3's32
                let x0 = qn / 2
                let ft = cast(u32) (p0 * (x0 + 1) + x0)
                let fs = cast(s32) dec.decode(ft)
                var x: s32
                if fs < (x0 + 1) * p0 do
                    x = fs / p0
                else do
                    x = x0 + 1 + (fs - (x0 + 1) * p0)
                let low  = x <= x0 ? p0 * x : (x - 1 - x0) + (x0 + 1) * p0
                let high = x <= x0 ? p0 * (x + 1) : (x - x0) + (x0 + 1) * p0
                dec.update(cast(u32) low, cast(u32) high, ft)
                itheta = x
            }
            elif b0 > 1 or stereo do
                itheta = cast(s32) dec.decodeUint(cast(u32) qn + 1)
            else
            {
                let half = qn >> 1
                let ft   = cast(u32) ((half + 1) * (half + 1))
                let fm   = cast(s32) dec.decode(ft)
                var fl:  s32
                var fs:  s32
                if fm < (half * (half + 1) >> 1)
                {
                    itheta = (cast(s32) isqrt32(8 * cast(u32) fm + 1) - 1) >> 1
                    fs     = itheta + 1
                    fl     = itheta * (itheta + 1) >> 1
                }
                else
                {
                    itheta = (2 * (qn + 1) - cast(s32) isqrt32(8 * cast(u32) (cast(s32) ft - fm - 1) + 1)) >> 1
                    fs     = qn + 1 - itheta
                    fl     = cast(s32) ft - ((qn + 1 - itheta) * (qn + 2 - itheta) >> 1)
                }

                dec.update(cast(u32) fl, cast(u32) (fl + fs), ft)
            }

            itheta = itheta * 16384 / qn
        }
        elif stereo
        {
            if b[] > 2's32 << BitRes and ctx.remainingBits > 2's32 << BitRes do
                inv = dec.decodeBit(2)
            if ctx.disableInv do
                inv = false
            itheta = 0
        }

        let qalloc = cast(s32) dec.tellFrac() - tell
        b[] -= qalloc
        var imid, iside, delta: s32
        if itheta == 0
        {
            imid  = 32767
            iside = 0
            fill[] &= (1'u32 << bBlocks) - 1
            delta = -16384
        }
        elif itheta == 16384
        {
            imid  = 0
            iside = 32767
            fill[] &= ((1'u32 << bBlocks) - 1) << bBlocks
            delta = 16384
        }
        else
        {
            imid  = bitexactCos(itheta)
            iside = bitexactCos(16384 - itheta)
            delta = fracMul16((cast(s32) n - 1) << 7, bitexactLog2Tan(iside, imid))
        }

        sctx.inv    = inv
        sctx.imid   = imid
        sctx.iside  = iside
        sctx.delta  = delta
        sctx.itheta = itheta
        sctx.qalloc = qalloc
    }

    mtd quantBandN1(ctx: *BandContext, x: [*] f32, y: #null [*] f32, lowbandOut: #null [*] f32, dec: *RangeDecoder)->u32
    {
        var target = x
        for c in (y ? 2'u32 : 1)
        {
            var sign = false
            if ctx.remainingBits >= 1's32 << BitRes
            {
                sign = dec.decodeBits(1) != 0
                ctx.remainingBits -= 1's32 << BitRes
            }

            target[0] = sign ? -1.0'f32 : 1.0
            if y do
                target = y!
        }

        if lowbandOut do
            lowbandOut![0] = x[0]
        return 1
    }

    mtd quantPartition(ctx: *BandContext, x: [*] f32, n: u32, bBits: s32, b: u32, lowband: #null [*] f32, lm: s32, gain: f32, fill: u32, dec: *RangeDecoder)->u32
    {
        let i     = ctx.band
        var cm    = 0'u32
        let base  = cast(u32) CeltCacheIndex[cast(u32) (lm + 1) * CeltBandCount + i]
        let limit = cast(s32) CeltCacheBits[base + cast(u32) CeltCacheBits[base]] + 12
        if lm != -1 and bBits > limit and n > 2
        {
            var sctx: SplitContext
            let half  = n >> 1
            let y     = x + half
            let lmNew = lm - 1
            var fillNow = fill
            if b == 1 do
                fillNow = (fill & 1) | (fill << 1)
            let bNew = (b + 1) >> 1
            var bb   = bBits
            .computeTheta(ctx, &sctx, half, &bb, bNew, b, lmNew, false, &fillNow, dec)
            let mid  = (1.0 / 32768.0) * cast(f32) sctx.imid
            let side = (1.0 / 32768.0) * cast(f32) sctx.iside
            var delta = sctx.delta
            if b > 1 and (sctx.itheta & 0x3FFF)
            {
                if sctx.itheta > 8192 do
                    delta -= delta >> cast(u32) (4 - lmNew)
                else do
                    delta = Math.min(0's32, delta + ((cast(s32) half << BitRes) >> cast(u32) (5 - lmNew)))
            }

            var mbits = Math.max(0's32, Math.min(bb, (bb - delta) / 2))
            var sbits = bb - mbits
            ctx.remainingBits -= sctx.qalloc
            var nextLowband: #null [*] f32
            if lowband do
                nextLowband = lowband! + half
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

        var q        = .bits2pulses(i, lm, bBits)
        var currBits = .pulses2bits(i, lm, q)
        ctx.remainingBits -= currBits
        while ctx.remainingBits < 0 and q > 0
        {
            ctx.remainingBits += currBits
            q -= 1
            currBits = .pulses2bits(i, lm, q)
            ctx.remainingBits -= currBits
        }

        if q != 0
        {
            let k = q < 8 ? cast(u32) q : (8 + (cast(u32) q & 7)) << ((cast(u32) q >> 3) - 1)
            return .algUnquant(x, n, k, ctx.spread, b, dec, gain)
        }

        let cmMask   = (1'u32 << b) - 1
        let fillMask = fill & cmMask
        if !fillMask
        {
            for j in n do
                x[j] = 0
            return 0
        }

        if !lowband
        {
            for j in n
            {
                ctx.seed = lcgRand(ctx.seed)
                x[j]     = cast(f32) (cast #bit (s32) ctx.seed >> 20)
            }

            cm = cmMask
        }
        else
        {
            for j in n
            {
                ctx.seed = lcgRand(ctx.seed)
                let tmp = ctx.seed & 0x8000 ? 1.0 / 256.0 : -1.0 / 256.0
                x[j] = lowband![j] + cast(f32) tmp
            }

            cm = fillMask
        }

        .renormaliseVector(x, n, gain)
        return cm
    }

    mtd quantBand(ctx: *BandContext, x: [*] f32, n: u32, bBits: s32, b: u32, lowbandIn: #null [*] f32, lm: u32, lowbandOut: #null [*] f32, gain: f32, useScratch: bool, fillIn: u32, dec: *RangeDecoder)->u32
    {
        if n == 1 do
            return .quantBandN1(ctx, x, null, lowbandOut, dec)

        var lowband  = lowbandIn
        var fill     = fillIn
        let n0       = n
        var nb       = n / b
        var blocks   = b
        var timeDivide = 0'u32
        var recombine  = 0'u32
        let longBlocks = b == 1
        var tfChange   = ctx.tfChange
        if tfChange > 0 do
            recombine = cast(u32) tfChange

        if useScratch and lowband and (recombine or ((nb & 1) == 0 and tfChange < 0) or b > 1)
        {
            let scratch = .scratch.buffer!
            for j in n do
                scratch[j] = lowband![j]
            lowband = scratch
        }

        for k in recombine
        {
            if lowband do
                .haar1(lowband!, n >> k, 1'u32 << k)
            fill = BitInterleave[fill & 0xF] | (BitInterleave[fill >> 4] << 2)
        }

        blocks >>= recombine
        nb     <<= recombine
        while (nb & 1) == 0 and tfChange < 0
        {
            if lowband do
                .haar1(lowband!, nb, blocks)
            fill      |= fill << blocks
            blocks    <<= 1
            nb        >>= 1
            timeDivide += 1
            tfChange   += 1
        }

        let b0  = blocks
        let nb0 = nb
        if b0 > 1 and lowband do
            .deinterleaveHadamard(lowband!, nb >> recombine, b0 << recombine, longBlocks)

        var cm = .quantPartition(ctx, x, n, bBits, blocks, lowband, cast(s32) lm, gain, fill, dec)

        if b0 > 1 do
            .interleaveHadamard(x, nb >> recombine, b0 << recombine, longBlocks)
        nb     = nb0
        blocks = b0
        for timeDivide
        {
            blocks >>= 1
            nb     <<= 1
            cm |= cm >> blocks
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
            let scale = cast(f32) Math.sqrt(cast(f64) n0)
            for j in n0 do
                lowbandOut![j] = scale * x[j]
        }

        return cm & ((1'u32 << blocks) - 1)
    }

    mtd quantBandStereo(ctx: *BandContext, x, y: [*] f32, n: u32, bBits: s32, b: u32, lowband: #null [*] f32, lm: u32, lowbandOut: #null [*] f32, useScratch: bool, fillIn: u32, dec: *RangeDecoder)->u32
    {
        if n == 1 do
            return .quantBandN1(ctx, x, y, lowbandOut, dec)

        var sctx: SplitContext
        var fill = fillIn
        var bb   = bBits
        .computeTheta(ctx, &sctx, n, &bb, b, b, cast(s32) lm, true, &fill, dec)
        let mid  = (1.0 / 32768.0) * cast(f32) sctx.imid
        let side = (1.0 / 32768.0) * cast(f32) sctx.iside
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
            let x2 = swap ? y : x
            let y2 = swap ? x : y
            var sign = 1.0'f32
            if sbits and dec.decodeBits(1) do
                sign = -1.0
            cm = .quantBand(ctx, x2, n, mbits, b, lowband, lm, lowbandOut, 1.0, useScratch, fillIn, dec)
            y2[0] = -sign * x2[1]
            y2[1] = sign * x2[0]
            x[0] = mid * x[0]
            x[1] = mid * x[1]
            y[0] = side * y[0]
            y[1] = side * y[1]
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
    mtd quantAllBands(shortBlocks: bool, spread: u32, dualStereoIn: bool, intensity: u32, tfRes: const [*] s32, totalBits: s32, balanceIn: s32, dec: *RangeDecoder, lm: u32, codedBands: u32, collapseMasks: [*] u8)
    {
        let C          = .streamChannels
        let M          = 1'u32 << lm
        let B          = shortBlocks ? M : 1
        let normOffset = M * cast(u32) CeltBands[.startBand]
        let normSpan   = M * cast(u32) CeltBands[CeltBandCount - 1] - normOffset
        let norm       = .norm.buffer!
        let norm2      = norm + normSpan
        let spectrum   = .spectrum.buffer!
        let N          = M * CeltShortSize
        var dualStereo = dualStereoIn
        var balance    = balanceIn
        var lowbandOffset = 0'u32
        var updateLowband = true
        var ctx: BandContext
        ctx.intensity  = intensity
        ctx.spread     = spread
        ctx.seed       = .rng
        ctx.disableInv = .disableInv
        ctx.avoidSplitNoise = B > 1
        ctx.lm         = lm

        for i in .startBand until .endBand
        {
            ctx.band = i
            let last = i == .endBand - 1
            var x    = spectrum + M * cast(u32) CeltBands[i]
            var y: #null [*] f32
            if C == 2 do
                y = spectrum + N + M * cast(u32) CeltBands[i]
            let n    = M * cast(u32) (CeltBands[i + 1] - CeltBands[i])
            let tell = cast(s32) dec.tellFrac()
            if i != .startBand do
                balance -= tell
            let remainingBits = totalBits - tell - 1
            ctx.remainingBits = remainingBits
            var b = 0's32
            if i <= codedBands - 1
            {
                let currBalance = balance / cast(s32) Math.min(3'u32, codedBands - i)
                b = Math.max(0's32, Math.min(16383's32, Math.min(remainingBits + 1, .pulses[i] + currBalance)))
            }

            if (cast(s32) (M * cast(u32) CeltBands[i]) - cast(s32) n >= cast(s32) (M * cast(u32) CeltBands[.startBand]) or i == .startBand + 1) and (updateLowband or lowbandOffset == 0) do
                lowbandOffset = i
            if i == .startBand + 1
            {
                // Duplicate enough of the first band to fold the second one from it.
                let n1 = M * cast(u32) (CeltBands[.startBand + 1] - CeltBands[.startBand])
                let n2 = M * cast(u32) (CeltBands[.startBand + 2] - CeltBands[.startBand + 1])
                for j in n2 - n1
                {
                    norm[n1 + j] = norm[2 * n1 - n2 + j]
                    if dualStereo do
                        norm2[n1 + j] = norm2[2 * n1 - n2 + j]
                }
            }

            let tfChange = tfRes[i]
            ctx.tfChange = tfChange
            var useScratch = !last
            var effectiveLowband = Swag.U32.Max
            var xcm: u32
            var ycm: u32
            if lowbandOffset != 0 and (spread != SpreadAggressive or B > 1 or tfChange < 0)
            {
                let target = M * cast(u32) CeltBands[lowbandOffset]
                effectiveLowband = target >= normOffset + n ? target - normOffset - n : 0
                var foldStart = lowbandOffset
                while true
                {
                    foldStart -= 1
                    if M * cast(u32) CeltBands[foldStart] <= effectiveLowband + normOffset do
                        break
                }

                var foldEnd = lowbandOffset - 1
                while true
                {
                    foldEnd += 1
                    if !(foldEnd < i and M * cast(u32) CeltBands[foldEnd] < effectiveLowband + normOffset + n) do
                        break
                }

                while true
                {
                    foldEnd += 1
                    if M * cast(u32) CeltBands[foldEnd] >= effectiveLowband + normOffset + n do
                        break
                }
                xcm = 0
                ycm = 0
                for f in foldStart until foldEnd
                {
                    xcm |= cast(u32) collapseMasks[f * C]
                    ycm |= cast(u32) collapseMasks[f * C + C - 1]
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
                for j in M * cast(u32) CeltBands[i] - normOffset do
                    norm[j] = 0.5 * (norm[j] + norm2[j])
            }

            var lowband: #null [*] f32
            var lowband2: #null [*] f32
            if effectiveLowband != Swag.U32.Max
            {
                lowband  = norm + effectiveLowband
                lowband2 = norm2 + effectiveLowband
            }

            var lowbandOut: #null [*] f32
            var lowbandOut2: #null [*] f32
            if !last
            {
                lowbandOut  = norm + M * cast(u32) CeltBands[i] - normOffset
                lowbandOut2 = norm2 + M * cast(u32) CeltBands[i] - normOffset
            }

            if dualStereo
            {
                xcm = .quantBand(&ctx, x, n, b / 2, B, lowband, lm, lowbandOut, 1.0, useScratch, xcm, dec)
                ycm = .quantBand(&ctx, y!, n, b / 2, B, lowband2, lm, lowbandOut2, 1.0, useScratch, ycm, dec)
            }
            else
            {
                if y do
                    xcm = .quantBandStereo(&ctx, x, y!, n, b, B, lowband, lm, lowbandOut, useScratch, xcm | ycm, dec)
                else do
                    xcm = .quantBand(&ctx, x, n, b, B, lowband, lm, lowbandOut, 1.0, useScratch, xcm | ycm, dec)
                ycm = xcm
            }

            collapseMasks[i * C]         = cast(u8) xcm
            collapseMasks[i * C + C - 1] = cast(u8) ycm
            balance += .pulses[i] + tell
            updateLowband = b > cast(s32) (n << BitRes)
            ctx.avoidSplitNoise = false
        }

        .rng = ctx.seed
    }

    mtd antiCollapse(collapseMasks: const [*] u8, lm: u32, size: u32, seedIn: u32)
    {
        let C    = .streamChannels
        var seed = seedIn
        for i in .startBand until .endBand
        {
            let n0     = cast(u32) (CeltBands[i + 1] - CeltBands[i])
            let depth  = cast(u32) ((1 + .pulses[i]) / cast(s32) n0) >> lm
            let thresh = 0.5 * celtExp2(-0.125 * cast(f32) depth)
            let sqrt1  = celtRsqrt(cast(f32) (n0 << lm))
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
                let x = .spectrum.buffer! + c * size + (cast(u32) CeltBands[i] << lm)
                var renormalize = false
                for k in 1'u32 << lm
                {
                    if !(cast(u32) collapseMasks[i * C + c] & (1'u32 << k))
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

    mtd denormaliseBands(x: const [*] f32, bandLogE: const [*] f32, effEnd, M: u32, silence: bool)
    {
        let freq  = .frequency.buffer!
        let N     = M * CeltShortSize
        var bound = M * cast(u32) CeltBands[effEnd]
        var start = .startBand
        var end   = effEnd
        if silence
        {
            bound = 0
            start = 0
            end   = 0
        }

        for i in M * cast(u32) CeltBands[start] do
            freq[i] = 0
        for i in start until end
        {
            let lg = bandLogE[i] + CeltEnergyMeans[i]
            let g  = celtExp2(Math.min(32.0'f32, lg))
            for j in M * cast(u32) CeltBands[i] until M * cast(u32) CeltBands[i + 1] do
                freq[j] = x[j] * g
        }

        for i in bound until N do
            freq[i] = 0
    }

    mtd combFilter(y, x: [*] f32, t0In, t1In: s32, n: u32, g0, g1: f32, tapset0, tapset1: u32, overlap: u32)
    {
        if g0 == 0 and g1 == 0
        {
            if y != x
            {
                for i in n do
                    y[i] = x[i]
            }

            return
        }

        let t0  = cast(u32) Math.max(t0In, CombMinPeriod)
        let t1  = cast(u32) Math.max(t1In, CombMinPeriod)
        let g00 = g0 * CombGains[tapset0, 0]
        let g01 = g0 * CombGains[tapset0, 1]
        let g02 = g0 * CombGains[tapset0, 2]
        let g10 = g1 * CombGains[tapset1, 0]
        let g11 = g1 * CombGains[tapset1, 1]
        let g12 = g1 * CombGains[tapset1, 2]

        // The filters read up to two samples around each period back, which the decode buffer
        // keeps in front of the block being filtered.
        let past0 = x - (t0 + 2)
        let past1 = x - (t1 + 2)
        var x1 = past1[3]
        var x2 = past1[2]
        var x3 = past1[1]
        var x4 = past1[0]
        var fade = overlap
        if g0 == g1 and t0 == t1 and tapset0 == tapset1 do
            fade = 0
        var i = 0'u32
        while i < fade
        {
            let x0 = past1[i + 4]
            let f  = CeltWindow[i] * CeltWindow[i]
            y[i] = x[i] + (1.0 - f) * g00 * past0[i + 2] + (1.0 - f) * g01 * (past0[i + 3] + past0[i + 1]) + (1.0 - f) * g02 * (past0[i + 4] + past0[i]) + f * g10 * x2 + f * g11 * (x1 + x3) + f * g12 * (x0 + x4)
            x4 = x3
            x3 = x2
            x2 = x1
            x1 = x0
            i  += 1
        }

        if g1 == 0
        {
            if y != x
            {
                for j in fade until n do
                    y[j] = x[j]
            }

            return
        }

        while i < n
        {
            let x0 = past1[i + 4]
            y[i] = x[i] + g10 * x2 + g11 * (x1 + x3) + g12 * (x0 + x4)
            x4 = x3
            x3 = x2
            x2 = x1
            x1 = x0
            i  += 1
        }
    }

    // Decodes one frame of `frameSize` samples through `dec`, which reads `data`, and writes the
    // de-emphasized output interleaved over the output channels.
    mtd decodeFrame(data: const [..] u8, dec: *RangeDecoder, frameSize: u32, pcm: [*] f32) fail
    {
        var lm = 0'u32
        while lm <= CeltMaxLM and (CeltShortSize << lm) != frameSize do
            lm += 1
        if lm > CeltMaxLM do
            fail InvalidFormatError{"Opus CELT frame size is not one the mode supports"}
        let M   = 1'u32 << lm
        let N   = M * CeltShortSize
        let C   = .streamChannels
        let CC  = .channels
        let len = cast(s32) @countof(data)
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
                postfilterPitch = cast(s32) ((16'u32 << octave) + dec.decodeBits(4 + octave)) - 1
                let qg = dec.decodeBits(3)
                if dec.tell() + 2 <= totalBits do
                    postfilterTapset = dec.decodeIcdf(TapsetIcdf, 2)
                postfilterGain = 0.09375 * cast(f32) (qg + 1)
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
            let width = cast(s32) (CeltBands[i + 1] - CeltBands[i]) << lm
            cap[i] = ((cast(s32) CeltCacheCaps[CeltBandCount * (2 * lm + C - 1) + i] + 64) * cast(s32) C * width) >> 2
        }

        var offsets: [CeltBandCount] s32
        var dynallocLogp = 6'u32
        totalBits <<= BitRes
        var tellFrac = cast(s32) dec.tellFrac()
        for i in .startBand until .endBand
        {
            let width  = cast(s32) C * cast(s32) (CeltBands[i + 1] - CeltBands[i]) << lm
            let quanta = Math.min(width << BitRes, Math.max(6's32 << BitRes, width))
            var loopLogp = dynallocLogp
            var boost    = 0's32
            while tellFrac + (cast(s32) loopLogp << BitRes) < totalBits and boost < cap[i]
            {
                let flag = dec.decodeBit(loopLogp)
                tellFrac = cast(s32) dec.tellFrac()
                if !flag do
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
            allocTrim = cast(s32) dec.decodeIcdf(TrimIcdf, 7)

        var bits = ((len * 8) << BitRes) - cast(s32) dec.tellFrac() - 1
        var antiCollapseRsv = 0's32
        if isTransient and lm >= 2 and bits >= (cast(s32) (lm + 2) << BitRes) do
            antiCollapseRsv = 1's32 << BitRes
        bits -= antiCollapseRsv

        var intensity  = 0'u32
        var dualStereo = false
        var balance    = 0's32
        var fineQuant:    [CeltBandCount] s32
        var finePriority: [CeltBandCount] s32
        let pulses     = .pulses.buffer!
        let codedBands = .computeAllocation(&offsets[0], &cap[0], allocTrim, &intensity, &dualStereo, bits, &balance, pulses, &fineQuant[0], &finePriority[0], lm, dec)
        .unquantFineEnergy(&fineQuant[0], dec)

        for c in CC
        {
            let memory = .decodeMemory[c].buffer!
            for j in CeltDecodeBuffer - N + CeltOverlap do
                memory[j] = memory[j + N]
        }

        var collapseMasks: [2 * CeltBandCount] u8
        .quantAllBands(shortBlocks, spread, dualStereo, intensity, &tfRes[0], len * (8's32 << BitRes) - antiCollapseRsv, balance, dec, lm, codedBands, &collapseMasks[0])

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

        // Synthesis: denormalise each channel, run the inverse transforms into the decode buffer.
        let blocks    = shortBlocks ? M : 1
        let blockSize = shortBlocks ? CeltShortSize : N
        let shift     = shortBlocks ? CeltMaxLM : CeltMaxLM - lm
        let spectrum  = .spectrum.buffer!
        for c in CC
        {
            let outSyn = .decodeMemory[c].buffer! + CeltDecodeBuffer - N
            var source = spectrum + Math.min(c, C - 1) * N
            var energy = &.oldBandE[Math.min(c, C - 1) * CeltBandCount]
            if CC == 1 and C == 2
            {
                // Downmix a stereo stream to mono.
                .denormaliseBands(spectrum, &.oldBandE[0], effEnd, M, silence)
                var mono: Array'f32
                mono.add(.frequency.toSlice())
                .denormaliseBands(spectrum + N, &.oldBandE[CeltBandCount], effEnd, M, silence)
                let freq = .frequency.buffer!
                for i in N do
                    freq[i] = 0.5 * (mono[i] + freq[i])
            }
            else do
                .denormaliseBands(source, energy, effEnd, M, silence)

            let freq = .frequency.buffer!
            for b in blocks do
                .mdct.backward(freq + b, blocks, outSyn + blockSize * b, shift)
        }

        for c in CC
        {
            let outSyn = .decodeMemory[c].buffer! + CeltDecodeBuffer - N
            .postfilterPeriod    = Math.max(.postfilterPeriod, CombMinPeriod)
            .postfilterPeriodOld = Math.max(.postfilterPeriodOld, CombMinPeriod)
            .combFilter(outSyn, outSyn, .postfilterPeriodOld, .postfilterPeriod, CeltShortSize, .postfilterGainOld, .postfilterGain, .postfilterTapsetOld, .postfilterTapset, CeltOverlap)
            if lm != 0 do
                .combFilter(outSyn + CeltShortSize, outSyn + CeltShortSize, .postfilterPeriod, postfilterPitch, N - CeltShortSize, .postfilterGain, postfilterGain, .postfilterTapset, postfilterTapset, CeltOverlap)
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

        if !isTransient
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

        let increase = cast(f32) Math.min(160'u32, M) * 0.001'f32
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

        // De-emphasis, and the output scale of one unit per full-scale sample.
        for c in CC
        {
            let outSyn = .decodeMemory[c].buffer! + CeltDecodeBuffer - N
            var m      = .preemphasisMemory[c]
            for j in N
            {
                let tmp = outSyn[j] + 1e-30'f32 + m
                m = CeltPreemphasis * tmp
                pcm[j * CC + c] = tmp * (1.0 / 32768.0)
            }

            .preemphasisMemory[c] = m
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
    var qn = Exp2Table8[cast(u32) (qb & 7)] >> cast(u32) (14 - (qb >> BitRes))
    qn = (qn + 1) >> 1 << 1
    return qn
}
