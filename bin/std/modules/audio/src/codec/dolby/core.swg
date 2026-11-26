//! Format: Shared AC-3/E-AC-3 decoder support.
//! Supported: Common bit reading, channel layouts, exponents, bit allocation, transforms, windows, dither, and normative tables used by both Dolby packet decoders.
//! Not supported: This directory does not select or decode a complete packet format by itself.
//! Role: This file owns shared Dolby bit allocation, exponents, transforms, channel mapping, and PCM output.
//
#global namespace Dolby

using Core, Core.Errors, Core.Math

private const MaxChannels              = 6
private const MaxFullBandwidthChannels = 5
private const SamplesPerBlock          = 256
private const BlocksPerAc3Frame        = 6

private func dolbySpeakerMask(acmod: u32, lfe: bool)->u32
{
    var mask: u32
    switch acmod
    {
    case 0, 2:
        mask = 0x0003     // Dual mono or stereo.

    case 1:
        mask = 0x0004     // Center.

    case 3:
        mask = 0x0007     // Left, center, right.

    case 4:
        mask = 0x0103     // Left, right, back center.

    case 5:
        mask = 0x0107     // Left, center, right, back center.

    case 6:
        mask = 0x0603     // Left, right, side left, side right.

    case 7:
        mask = 0x0607     // Left, center, right, side left, side right.
    }

    return mask | (lfe ? 0x0008 : 0)
}

// Maps AC-3 bit-stream channel order to ascending WAVE speaker-mask order.
private func dolbySourceChannel(destination, acmod, nfchans: u32, lfeon: bool)->u32
{
    switch acmod
    {
    case 3, 5, 7:
        if destination == 0 do
            return 0
        if destination == 1 do
            return 2
        if destination == 2 do
            return 1
        if lfeon and destination == 3 do
            return nfchans
        if destination >= (lfeon ? 4 : 3) do
            return destination - (lfeon ? 1 : 0)

    case 4:
        if lfeon and destination == 2 do
            return nfchans
        if lfeon and destination == 3 do
            return 2

    case 6:
        if lfeon and destination == 2 do
            return nfchans
        if lfeon and destination >= 3 do
            return destination - 1
    }

    return destination
}

private struct BitReader
{
    data:     const [*] u8
    bitSize:  u64
    bitPos:   u64
    overrun:  bool
    cache:    u64
    cacheEnd: u64
}

private impl BitReader
{
    internal func create(data: const [*] u8, size: u64)->BitReader => BitReader{data, size * 8}

    // Dolby fields are at most 32 bits and never seek backwards.
    #[Swag.Inline]
    internal mtd read(count: u32)->u32
    {
        if not count do
            return 0

        let start = .bitPos
        let end   = start + count
        .bitPos = end
        if end <= .cacheEnd
        {
            let offset = cast(u32, 64 - (.cacheEnd - start))
            return cast(u32, ((.cache << offset) >> (64 - count)))
        }

        return .refillAndRead(count, start)
    }

    mtd refillAndRead(count: u32, start: u64)->u32
    {
        let byteStart = start >> 3
        let cacheEnd  = (byteStart + 8) * 8
        if cacheEnd <= .bitSize
        {
            .cache    = Math.bigEndianToNative(cast(const [*] u64, .data + byteStart)[0])
            .cacheEnd = cacheEnd
            return cast(u32, ((.cache << cast(u32, (start & 7))) >> (64 - count)))
        }

        // Read the tail without loading a full word past the end of the packet.
        if start >= .bitSize
        {
            .overrun = true
            return 0
        }

        var pos       = start
        let end       = pos + count
        let available = Math.min(end, .bitSize)
        var value: u32
        while pos < available
        {
            let byteBits = 8 - cast(u32, pos & 7)
            let take     = Math.min(cast(u32, available - pos), byteBits)
            let bits     = cast(u32, .data[pos >> 3]) >> (byteBits - take)
            value = (value << take) | (bits & ((1'u32 << take) - 1))
            pos   += take
        }

        if end > .bitSize
        {
            .overrun = true
            value    <<= cast(u32, end - pos)
        }

        return value
    }

    #[Swag.Inline]
    mtd readSigned(count: u32)->s32
    {
        let raw = .read(count)
        if not count do
            return 0
        let shift = 32 - count
        return cast #bit(s32, (raw << shift)) >> shift
    }

    internal mtd skip(count: u64)
    {
        .bitPos += count
        if .bitPos > .bitSize do
            .overrun = true
    }
}

private struct Imdct
{
    delay: [SamplesPerBlock] f64
}

private var g_LongCos:  [128] f64
private var g_LongSin:  [128] f64
private var g_ShortCos: [64] f64
private var g_ShortSin: [64] f64

// The 64- and 128-point transforms share all FFT stages up through length 64.
private var g_FftReverse:     [128] u8
private var g_FftTwiddleReal: [128] f64
private var g_FftTwiddleImag: [128] f64

// The two supported transform sizes have fixed butterfly strides.
#[Swag.Inline]
private func(Size: u64, Half: u64) inverseFftStage(real, imaginary: [*] f64)
{
    const Width = Half * 2
    for group in Size / Width
    {
        let base = group * Width
        for pair in Half / 2
        {
            let offset      = pair * 2
            let left        = base + offset
            let right       = left + Half
            let twiddleReal = Simd.load(&g_FftTwiddleReal[Half + offset])
            let twiddleImag = Simd.load(&g_FftTwiddleImag[Half + offset])
            let rightReal   = Simd.load(real + right)
            let rightImag   = Simd.load(imaginary + right)
            let productReal = twiddleReal * rightReal - twiddleImag * rightImag
            let productImag = twiddleReal * rightImag + twiddleImag * rightReal
            let leftReal    = Simd.load(real + left)
            let leftImag    = Simd.load(imaginary + left)
            Simd.store(real + right, leftReal - productReal)
            Simd.store(imaginary + right, leftImag - productImag)
            Simd.store(real + left, leftReal + productReal)
            Simd.store(imaginary + left, leftImag + productImag)
        }
    }
}

private func(Size: u64, FirstStageDone: bool = false) inverseFft(real, imaginary: [*] f64)
{
    #static if not FirstStageDone
    {
        // The first stage has a unit twiddle and one butterfly per block.
        for pair in Size / 2
        {
            let left      = pair * 2
            let right     = left + 1
            let leftReal  = real[left]
            let leftImag  = imaginary[left]
            let rightReal = real[right]
            let rightImag = imaginary[right]
            real[left]       = leftReal + rightReal
            imaginary[left]  = leftImag + rightImag
            real[right]      = leftReal - rightReal
            imaginary[right] = leftImag - rightImag
        }
    }

    inverseFftStage'(Size, 2)(real, imaginary)
    inverseFftStage'(Size, 4)(real, imaginary)
    inverseFftStage'(Size, 8)(real, imaginary)
    inverseFftStage'(Size, 16)(real, imaginary)
    inverseFftStage'(Size, 32)(real, imaginary)
    if Size == 128 do
        inverseFftStage'(Size, 64)(real, imaginary)
}

#[Swag.Inline]
private func writeSynthesisSample(output: [*] s16, offset: u64, value, window, previous: f64)
{
    let scaled = (2.0 * (value * window + previous)) * 32767.0
    output[offset] = cast(s16, Math.clamp(scaled, -32768.0, 32767.0))
}

private func imdctLong(coefficients: const [*] f64, output: [*] s16, stride: u32, delay: [*] f64)
{
    var real, imaginary: [128] f64
    for k in 64
    {
        // The high bit of the coefficient index becomes the low bit in FFT order.
        // Build the first butterfly directly while the two rotated inputs are live.
        let j     = k + 64
        let a0    = coefficients[255 - 2 * k]
        let b0    = coefficients[2 * k]
        let a1    = coefficients[255 - 2 * j]
        let b1    = coefficients[2 * j]
        let r0    = a0 * g_LongCos[k] - b0 * g_LongSin[k]
        let i0    = b0 * g_LongCos[k] + a0 * g_LongSin[k]
        let r1    = a1 * g_LongCos[j] - b1 * g_LongSin[j]
        let i1    = b1 * g_LongCos[j] + a1 * g_LongSin[j]
        let index = g_FftReverse[k]
        real[index]          = r0 + r1
        real[index + 1]      = r0 - r1
        imaginary[index]     = i0 + i1
        imaginary[index + 1] = i0 - i1
    }

    inverseFft'(128, true)(&real, &imaginary)

    for index in 64
    {
        let upperIndex = index + 64
        let lowReal    = real[index] * g_LongCos[index] - imaginary[index] * g_LongSin[index]
        let lowImag    = imaginary[index] * g_LongCos[index] + real[index] * g_LongSin[index]
        let highReal   = real[upperIndex] * g_LongCos[upperIndex] - imaginary[upperIndex] * g_LongSin[upperIndex]
        let highImag   = imaginary[upperIndex] * g_LongCos[upperIndex] + real[upperIndex] * g_LongSin[upperIndex]

        let lowEven  = 2 * index
        let lowOdd   = 127 - lowEven
        let highEven = 128 + lowEven
        let highOdd  = 128 + lowOdd
        writeSynthesisSample(output, lowEven * stride, -highImag, WINDOW[lowEven], delay[lowEven])
        writeSynthesisSample(output, lowOdd * stride, lowReal, WINDOW[lowOdd], delay[lowOdd])
        writeSynthesisSample(output, highEven * stride, -lowReal, WINDOW[highEven], delay[highEven])
        writeSynthesisSample(output, highOdd * stride, highImag, WINDOW[highOdd], delay[highOdd])

        // Save the first half directly and the second with the mirrored window.
        delay[lowEven]  = -highReal
        delay[lowOdd]   = lowImag
        delay[highEven] = lowImag * WINDOW[lowOdd]
        delay[highOdd]  = -highReal * WINDOW[lowEven]
    }
}

private func imdctShort(coefficients: const [*] f64, output: [*] f64)
{
    var realA, imagA, realB, imagB: [64] f64
    for k in 64
    {
        let a1    = coefficients[2 * (127 - 2 * k)]
        let b1    = coefficients[4 * k]
        let a2    = coefficients[2 * (128 - 2 * k - 1) + 1]
        let b2    = coefficients[4 * k + 2]
        let index = g_FftReverse[k] >> 1
        realA[index] = a1 * g_ShortCos[k] - b1 * g_ShortSin[k]
        imagA[index] = b1 * g_ShortCos[k] + a1 * g_ShortSin[k]
        realB[index] = a2 * g_ShortCos[k] - b2 * g_ShortSin[k]
        imagB[index] = b2 * g_ShortCos[k] + a2 * g_ShortSin[k]
    }

    inverseFft'64(&realA, &imagA)
    inverseFft'64(&realB, &imagB)
    var postRealA, postImagA, postRealB, postImagB: [64] f64
    for index in 64
    {
        postRealA[index] = realA[index] * g_ShortCos[index] - imagA[index] * g_ShortSin[index]
        postImagA[index] = imagA[index] * g_ShortCos[index] + realA[index] * g_ShortSin[index]
        postRealB[index] = realB[index] * g_ShortCos[index] - imagB[index] * g_ShortSin[index]
        postImagB[index] = imagB[index] * g_ShortCos[index] + realB[index] * g_ShortSin[index]
    }

    for index in 64
    {
        output[2 * index]       = -postImagA[index]
        output[2 * index + 1]   = postRealA[63 - index]
        output[128 + 2 * index] = -postRealA[index]
        output[129 + 2 * index] = postImagA[63 - index]
        output[256 + 2 * index] = -postRealB[index]
        output[257 + 2 * index] = postImagB[63 - index]
        output[384 + 2 * index] = postImagB[index]
        output[385 + 2 * index] = -postRealB[63 - index]
    }
}

// The long stereo kernel keeps its overlap in PCM channel order.
// Stereo, dual mono, and mono with LFE already have that order in the bitstream.
private struct StereoImdct
{
    delay:  [2 * SamplesPerBlock] f32
    active: bool
}

private struct StereoSpectrum
{
    real, imaginary: [256] f32
}

private var g_StereoCos, g_StereoSin: [256] f32
private var g_StereoTwiddleReal, g_StereoTwiddleImag: [256] f32
private var g_StereoWindow: [512] f32

#[Swag.Inline]
private func(Half: u64) fftStereoStage(fft: *StereoSpectrum)
{
    const Width = 2 * Half
    for group in 128 / Width
    {
        let base = group * Width * 2
        for row in Half / 2
        {
            let offset      = row * 4
            let left        = base + offset
            let right       = left + 2 * Half
            let r           = Simd.load(&fft.real[right])
            let i           = Simd.load(&fft.imaginary[right])
            let c           = Simd.load(&g_StereoTwiddleReal[2 * Half + offset])
            let w           = Simd.load(&g_StereoTwiddleImag[2 * Half + offset])
            let productReal = r * c - i * w
            let productImag = i * c + r * w
            let leftReal    = Simd.load(&fft.real[left])
            let leftImag    = Simd.load(&fft.imaginary[left])
            Simd.store(&fft.real[left], leftReal + productReal)
            Simd.store(&fft.imaginary[left], leftImag + productImag)
            Simd.store(&fft.real[right], leftReal - productReal)
            Simd.store(&fft.imaginary[right], leftImag - productImag)
        }
    }
}

private func prepareStereoSpectrum(fft: *StereoSpectrum, coefficients: const *[MaxChannels, SamplesPerBlock] f64)
{
    for k in 128
    {
        let hi     = 255 - 2 * k
        let lo     = 2 * k
        let a      = cast(f32, coefficients[][0, hi])
        let b      = cast(f32, coefficients[][0, lo])
        let c      = cast(f32, coefficients[][1, hi])
        let d      = cast(f32, coefficients[][1, lo])
        let index  = 2 * cast(u32, g_FftReverse[k])
        let cosine = g_StereoCos[lo]
        let sine   = g_StereoSin[lo]
        fft.real[index]          = a * cosine - b * sine
        fft.imaginary[index]     = b * cosine + a * sine
        fft.real[index + 1]      = c * cosine - d * sine
        fft.imaginary[index + 1] = d * cosine + c * sine
    }

    // Each vector holds one complex component for two bins in both channels.
    const DuplicateFirst   = cast(Simd.U32x4, [0'u32, 1, 0, 1])
    const DuplicateLast    = cast(Simd.U32x4, [2'u32, 3, 2, 3])
    const SumAndDifference = cast(Simd.F32x4, [1.0'f32, 1, -1, -1])
    for group in 64
    {
        let index = 4 * group
        let r     = Simd.load(&fft.real[index])
        let i     = Simd.load(&fft.imaginary[index])
        let r0    = Simd.permute(r, DuplicateFirst)
        let i0    = Simd.permute(i, DuplicateFirst)
        let r1    = Simd.permute(r, DuplicateLast)
        let i1    = Simd.permute(i, DuplicateLast)
        Simd.store(&fft.real[index], r0 + r1 * SumAndDifference)
        Simd.store(&fft.imaginary[index], i0 + i1 * SumAndDifference)
    }

    fftStereoStage'2(fft)
    fftStereoStage'4(fft)
    fftStereoStage'8(fft)
    fftStereoStage'16(fft)
    fftStereoStage'32(fft)
    fftStereoStage'64(fft)

    for group in 64
    {
        let index = group * 4
        let r     = Simd.load(&fft.real[index])
        let i     = Simd.load(&fft.imaginary[index])
        let c     = Simd.load(&g_StereoCos[index])
        let w     = Simd.load(&g_StereoSin[index])
        Simd.store(&fft.real[index], r * c - i * w)
        Simd.store(&fft.imaginary[index], i * c + r * w)
    }
}

#[Swag.Inline]
private func(Upper: bool) writeStereoHalf(fft: const *StereoSpectrum, delay: [*] f32, destination: [*] s16)
{
    // Reverse the time samples and keep the two channel lanes in order.
    const ReverseFrames = cast(Simd.U32x4, [2'u32, 3, 0, 1])
    const MixFirst      = cast(Simd.U32x4, [0'u32, 1, 4, 5])
    const MixLast       = cast(Simd.U32x4, [2'u32, 3, 6, 7])
    const Gain          = cast(Simd.F32x4, [65_534.0'f32, 65_534.0, 65_534.0, 65_534.0])
    const High          = cast(Simd.F32x4, [32_767.0'f32, 32_767.0, 32_767.0, 32_767.0])
    const Low           = cast(Simd.F32x4, [-32_768.0'f32, -32_768.0, -32_768.0, -32_768.0])
    for group in 32
    {
        let bin    = 4 * group
        let mirror = 124 - bin
        var offset = 2 * bin
        var even, odd, futureEven, futureOdd: Simd.F32x4
        if Upper
        {
            offset     += 256
            even       = -Simd.load(&fft.real[bin])
            odd        = Simd.permute(Simd.load(&fft.imaginary[128 + mirror]), ReverseFrames)
            futureEven = Simd.load(&fft.imaginary[bin])
            futureOdd  = -Simd.permute(Simd.load(&fft.real[128 + mirror]), ReverseFrames)
        }
        else
        {
            even       = -Simd.load(&fft.imaginary[128 + bin])
            odd        = Simd.permute(Simd.load(&fft.real[mirror]), ReverseFrames)
            futureEven = -Simd.load(&fft.real[128 + bin])
            futureOdd  = Simd.permute(Simd.load(&fft.imaginary[mirror]), ReverseFrames)
        }

        let a       = Simd.permute2(even, odd, MixFirst)
        let b       = Simd.permute2(even, odd, MixLast)
        let sampleA = (a * Simd.load(&g_StereoWindow[offset]) + Simd.load(delay + offset)) * Gain
        let sampleB = (b * Simd.load(&g_StereoWindow[offset + 4]) + Simd.load(delay + offset + 4)) * Gain
        let pcmA    = Simd.truncateToS32(Swag.min(Swag.max(sampleA, Low), High))
        let pcmB    = Simd.truncateToS32(Swag.min(Swag.max(sampleB, Low), High))
        Simd.store(destination + offset, Simd.packSigned(pcmA, pcmB))

        var nextA = Simd.permute2(futureEven, futureOdd, MixFirst)
        var nextB = Simd.permute2(futureEven, futureOdd, MixLast)
        if Upper
        {
            nextA *= Simd.permute(Simd.load(&g_StereoWindow[508 - offset]), ReverseFrames)
            nextB *= Simd.permute(Simd.load(&g_StereoWindow[504 - offset]), ReverseFrames)
        }

        Simd.store(delay + offset, nextA)
        Simd.store(delay + offset + 4, nextB)
    }
}

impl StereoImdct
{
    // Hand the previous block's delay back to the scalar path on a window switch.
    mtd restore(states: *[MaxChannels] Imdct)
    {
        if not .active do
            return
        for index in SamplesPerBlock
        {
            states[][0].delay[index] = cast(f64, .delay[2 * index])
            states[][1].delay[index] = cast(f64, .delay[2 * index + 1])
        }

        .active = false
    }

    mtd process(states: *[MaxChannels] Imdct, coefficients: const *[MaxChannels, SamplesPerBlock] f64, output: [*] s16)
    {
        if not .active
        {
            for index in SamplesPerBlock
            {
                .delay[2 * index]     = cast(f32, states[][0].delay[index])
                .delay[2 * index + 1] = cast(f32, states[][1].delay[index])
            }

            .active = true
        }

        var fft: StereoSpectrum
        prepareStereoSpectrum(&fft, coefficients)
        writeStereoHalf'false(&fft, &.delay[0], output)
        writeStereoHalf'true(&fft, &.delay[0], output)
    }
}

impl Imdct
{
    mtd reset() => Memory.set(&.delay, 0, #sizeof(.delay))

    // Write the channel at its interleaved stride after applying the synthesis window.
    mtd process(coefficients: const [*] f64, shortBlocks: bool, output: [*] s16, stride: u32)
    {
        if not shortBlocks
        {
            imdctLong(coefficients, output, stride, &.delay[0])
            return
        }

        var time: [512] f64
        imdctShort(coefficients, &time)
        for index in 256
        {
            time[index]       *= WINDOW[index]
            time[511 - index] *= WINDOW[index]
            let sample = (2.0 * (time[index] + .delay[index])) * 32767.0
            output[index * stride] = cast(s16, Math.clamp(sample, -32768.0, 32767.0))
            .delay[index] = time[256 + index]
        }
    }
}

private struct DeltaAllocation
{
    mode:   u32
    count:  u32
    offset: [8] u32
    length: [8] u32
    value:  [8] u32
}

private func logarithmicAdd(a, b: s32)->s32
{
    let difference = a - b
    let address    = Math.min(Math.abs(difference) >> 1, 255)
    return difference >= 0 ? a + LATAB[address] : b + LATAB[address]
}

private func lowCompensation(value, first, second, bin: s32)->s32
{
    if bin < 7
    {
        if first + 256 == second do
            return 384
        if first > second do
            return Math.max(0, value - 64)
        return value
    }

    if bin < 20
    {
        if first + 256 == second do
            return 320
        if first > second do
            return Math.max(0, value - 64)
        return value
    }

    return Math.max(0, value - 128)
}

private func bitAllocation(fscod: u32, start, end: s32, exponents: const [*] s32, fastGain, slowGain, fastDecay, slowDecay, dbKnee, floor, snrOffset, fastLeak, slowLeak: s32, delta: const *DeltaAllocation?, result: [*] s32) fail
{
    if start < 0 or end <= start or end > 253 do
        fail InvalidFormatError{"Dolby bit-allocation range is invalid"}

    var currentFastLeak = fastLeak
    var currentSlowLeak = slowLeak
    let bandStart       = MASKTAB[start]
    let bandEnd         = MASKTAB[end - 1] + 1
    var psd: [256] s32
    var bandPsd, excitation, mask: [50] s32
    if bandStart < 0 or bandEnd <= bandStart or bandEnd > mask.count do
        fail InvalidFormatError{"Dolby bit-allocation bands exceed the core limit"}

    var bin = start
    while bin < end
    {
        psd[bin] = 3072 - (exponents[bin - start] << 7)
        bin      += 1
    }

    var source = start
    var band   = bandStart
    while band < bandEnd
    {
        let last = Math.min(BNDTAB[band] + BNDSZ[band], end)
        bandPsd[band] = psd[source]
        source        += 1
        while source < last
        {
            bandPsd[band] = logarithmicAdd(bandPsd[band], psd[source])
            source        += 1
        }

        band += 1
    }

    var begin   = bandStart
    var lowComp = 0's32
    if not bandStart
    {
        lowComp       = lowCompensation(lowComp, bandPsd[0], bandPsd[1], 0)
        excitation[0] = bandPsd[0] - fastGain - lowComp
        lowComp       = lowCompensation(lowComp, bandPsd[1], bandPsd[2], 1)
        excitation[1] = bandPsd[1] - fastGain - lowComp
        begin         = 7
        var current = 2's32
        while current < 7
        {
            if bandEnd != 7 or current != 6 do
                lowComp = lowCompensation(lowComp, bandPsd[current], bandPsd[current + 1], current)
            currentFastLeak     = bandPsd[current] - fastGain
            currentSlowLeak     = bandPsd[current] - slowGain
            excitation[current] = currentFastLeak - lowComp
            if (bandEnd != 7 or current != 6) and bandPsd[current] <= bandPsd[current + 1]
            {
                begin = current + 1
                break
            }

            current += 1
        }

        current = begin
        while current < Math.min(bandEnd, 22)
        {
            if bandEnd != 7 or current != 6 do
                lowComp = lowCompensation(lowComp, bandPsd[current], bandPsd[current + 1], current)
            currentFastLeak     = Math.max(currentFastLeak - fastDecay, bandPsd[current] - fastGain)
            currentSlowLeak     = Math.max(currentSlowLeak - slowDecay, bandPsd[current] - slowGain)
            excitation[current] = Math.max(currentFastLeak - lowComp, currentSlowLeak)
            current             += 1
        }

        begin = 22
    }

    var current = begin
    while current < bandEnd
    {
        currentFastLeak     = Math.max(currentFastLeak - fastDecay, bandPsd[current] - fastGain)
        currentSlowLeak     = Math.max(currentSlowLeak - slowDecay, bandPsd[current] - slowGain)
        excitation[current] = Math.max(currentFastLeak, currentSlowLeak)
        current             += 1
    }

    current = bandStart
    while current < bandEnd
    {
        if bandPsd[current] < dbKnee do
            excitation[current] += (dbKnee - bandPsd[current]) >> 2
        mask[current] = Math.max(excitation[current], HTH[fscod, current])
        current       += 1
    }

    if delta and (delta.mode == 0 or delta.mode == 1)
    {
        if delta.count > delta.offset.count do
            fail InvalidFormatError{"Dolby delta allocation has too many segments"}

        band = 0
        for segment in cast(u64, delta.count)
        {
            band += cast(s32, delta.offset[segment])
            let segmentEnd = band + cast(s32, delta.length[segment])
            if band < 0 or segmentEnd > bandEnd or segmentEnd > mask.count do
                fail InvalidFormatError{"Dolby delta allocation segment exceeds the channel bands"}

            let code   = cast(s32, delta.value[segment])
            let amount = (code >= 4 ? code - 3 : code - 4) << 7
            for cast(u64, delta.length[segment])
            {
                mask[band] += amount
                band       += 1
            }
        }
    }

    source = start
    band   = bandStart
    while source < end
    {
        let last   = Math.min(BNDTAB[band] + BNDSZ[band], end)
        var masked = mask[band] - snrOffset - floor
        if masked < 0 do
            masked = 0
        masked = (masked & 0x1FE0) + floor
        while source < last
        {
            let address = Math.clamp((psd[source] - masked) >> 5, 0, 63)
            result[source - start] = BAPTAB[address]
            source += 1
        }

        band += 1
    }
}

// Dolby mantissa exponents are small integers, so their powers of two are exact.
internal func mantissaScale(exponent: s32)->f64 => cast #bit (f64, cast(u64, (1023 - exponent)) << 52)

// Shift out one signed digit at a time. The trailing 1 marks the empty group.
// Reserved codes retain the full group length with zero-valued digits.
private func(Bits: u32, Levels: u32, Digits: u32) packedMantissaCodes()->[1 << Bits] u32
{
    var result: [1 << Bits] u32
    var validCodes = 1'u32
    for Digits do
        validCodes *= Levels

    for code in result.count
    {
        var packed = 1'u32 << (8 * Digits)
        if code < validCodes
        {
            var remaining = cast(u32, code)
            for digit in Digits
            {
                let centered = cast(s32, remaining % Levels) - cast(s32, Levels / 2)
                packed    |= cast(u32, cast #wrap(u8, centered)) << (8 * (Digits - 1 - digit))
                remaining /= Levels
            }
        }

        result[code] = packed
    }

    return result
}

private const Bap1Packed = #run packedMantissaCodes'(5, 3, 3)()
private const Bap2Packed = #run packedMantissaCodes'(7, 5, 3)()
private const Bap4Packed = #run packedMantissaCodes'(7, 11, 2)()

private struct MantissaReader
{
    reader: *BitReader
    bap1:   u32 = 1
    bap2:   u32 = 1
    bap4:   u32 = 1
}

impl MantissaReader
{
    func create(reader: *BitReader)->MantissaReader => MantissaReader{reader}

    #[Swag.Inline]
    mtd readPacked(bits: u32, packed: *u32, table: const [*] u32)->s32
    {
        if packed[] == 1 do
            packed[] = table[.reader.read(bits)]
        let value = cast(s32, cast #wrap(s8, packed[]))
        packed[] >>= 8
        return value
    }

    #[Swag.Inline]
    mtd getScaled(bap, exponent: s32)->f64
    {
        if bap >= 6
        {
            const Width: [16] u32 = [0, 0, 0, 0, 0, 0, 5, 6, 7, 8, 9, 10, 11, 12, 14, 16]
            let width = Width[bap]
            let raw   = .reader.readSigned(width)
            return cast(f64, raw) * mantissaScale(exponent + cast(s32, width) - 1)
        }

        return .getGrouped(bap) * mantissaScale(exponent)
    }

    #[Swag.Inline]
    mtd getGrouped(bap: s32)->f64
    {
        switch bap
        {
        case 0:
            return 0

        case 1:
            return cast(f64, .readPacked(5, &.bap1, &Bap1Packed[0])) * (2.0 / 3.0)

        case 2:
            return cast(f64, .readPacked(7, &.bap2, &Bap2Packed[0])) * (2.0 / 5.0)

        case 3:
            let code = .reader.read(3)
            return code < 7 ? (cast(f64, code) - 3.0) * (2.0 / 7.0) : 0

        case 4:
            return cast(f64, .readPacked(7, &.bap4, &Bap4Packed[0])) * (2.0 / 11.0)

        case 5:
            let code = .reader.read(4)
            return code < 15 ? (cast(f64, code) - 7.0) * (2.0 / 15.0) : 0

        default:
            return 0
        }
    }
}

private func initializeDolbyCore()
{
    for index in g_FftReverse.count do
        g_FftReverse[index] = Math.reverse(cast(u8, index)) >> 1

    var half = 1'u64
    while half < g_FftTwiddleReal.count
    {
        let angle    = Math.ConstF64.Pi / cast(f64, half)
        let stepReal = Math.cos(angle)
        let stepImag = Math.sin(angle)
        var real     = 1'f64
        var imag     = 0'f64
        for offset in half
        {
            g_FftTwiddleReal[half + offset] = real
            g_FftTwiddleImag[half + offset] = imag
            let nextReal = real * stepReal - imag * stepImag
            imag = real * stepImag + imag * stepReal
            real = nextReal
        }

        half *= 2
    }

    for index in 128
    {
        let angle = 2.0 * Math.ConstF64.Pi * (8.0 * cast(f64, index) + 1.0) / (8.0 * 512.0)
        g_LongCos[index] = -Math.cos(angle)
        g_LongSin[index] = -Math.sin(angle)
    }

    for index in 256
    {
        let bin = index / 2
        g_StereoCos[index]         = cast(f32, g_LongCos[bin])
        g_StereoSin[index]         = cast(f32, g_LongSin[bin])
        g_StereoTwiddleReal[index] = cast(f32, g_FftTwiddleReal[bin])
        g_StereoTwiddleImag[index] = cast(f32, g_FftTwiddleImag[bin])
    }

    for index in 512 do
        g_StereoWindow[index] = cast(f32, WINDOW[index / 2])

    for index in 64
    {
        let angle = 2.0 * Math.ConstF64.Pi * (8.0 * cast(f64, index) + 1.0) / (4.0 * 512.0)
        g_ShortCos[index] = -Math.cos(angle)
        g_ShortSin[index] = -Math.sin(angle)
    }
}
