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
    data:    const [*] u8
    bitSize: u64
    bitPos:  u64
    overrun: bool
}

private impl BitReader
{
    func create(data: const [*] u8, size: u64)->BitReader => {data, size * 8}

    mtd read(count: u32)->u32
    {
        var value: u32
        for count
        {
            value <<= 1
            if .bitPos >= .bitSize do
                .overrun = true
            else
            {
                let byteIndex = .bitPos >> 3
                let bitIndex  = 7 - (.bitPos & 7)
                value |= (cast(u32) .data[byteIndex] >> cast(u32) bitIndex) & 1
            }

            .bitPos += 1
        }

        return value
    }

    mtd readSigned(count: u32)->s32
    {
        let raw = .read(count)
        if !count do
            return 0
        let sign = 1'u32 << (count - 1)
        if raw & sign do
            return cast #bit (s32) (raw | (~0'u32 << count))
        return cast(s32) raw
    }

    mtd skip(count: u64)
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

private func inverseFft(real, imaginary: [*] f64, size: s32)
{
    var bits = 0's32
    while (1 << bits) < size do
        bits += 1
    for index in cast(u64) size
    {
        var source = cast(u32) index
        var reversed: u32
        for bits
        {
            reversed = (reversed << 1) | (source & 1)
            source   >>= 1
        }

        if reversed > index
        {
            let savedReal = real[index]
            let savedImag = imaginary[index]
            real[index]         = real[reversed]
            imaginary[index]    = imaginary[reversed]
            real[reversed]      = savedReal
            imaginary[reversed] = savedImag
        }
    }

    var half = 1's32
    while half < size
    {
        let step     = half * 2
        let angle    = Math.ConstF64.Pi / cast(f64) half
        let stepReal = Math.cos(angle)
        let stepImag = Math.sin(angle)
        var base     = 0's32
        while base < size
        {
            var twiddleReal = 1'f64
            var twiddleImag: f64
            for offset in cast(u64) half
            {
                let left        = cast(u64) base + offset
                let right       = left + cast(u64) half
                let productReal = twiddleReal * real[right] - twiddleImag * imaginary[right]
                let productImag = twiddleReal * imaginary[right] + twiddleImag * real[right]
                let leftReal    = real[left]
                let leftImag    = imaginary[left]
                real[right]      = leftReal - productReal
                imaginary[right] = leftImag - productImag
                real[left]       = leftReal + productReal
                imaginary[left]  = leftImag + productImag
                let nextReal = twiddleReal * stepReal - twiddleImag * stepImag
                twiddleImag = twiddleReal * stepImag + twiddleImag * stepReal
                twiddleReal = nextReal
            }

            base += step
        }

        half = step
    }
}

private func imdctLong(coefficients: const [*] f64, output: [*] f64)
{
    var real, imaginary: [128] f64
    for k in 128
    {
        let a = coefficients[255 - 2 * k]
        let b = coefficients[2 * k]
        real[k]      = a * g_LongCos[k] - b * g_LongSin[k]
        imaginary[k] = b * g_LongCos[k] + a * g_LongSin[k]
    }

    inverseFft(&real, &imaginary, 128)

    var postReal, postImaginary: [128] f64
    for index in 128
    {
        postReal[index]      = real[index] * g_LongCos[index] - imaginary[index] * g_LongSin[index]
        postImaginary[index] = imaginary[index] * g_LongCos[index] + real[index] * g_LongSin[index]
    }

    for index in 64
    {
        output[2 * index]       = -postImaginary[64 + index]
        output[2 * index + 1]   = postReal[63 - index]
        output[128 + 2 * index] = -postReal[index]
        output[129 + 2 * index] = postImaginary[127 - index]
        output[256 + 2 * index] = -postReal[64 + index]
        output[257 + 2 * index] = postImaginary[63 - index]
        output[384 + 2 * index] = postImaginary[index]
        output[385 + 2 * index] = -postReal[127 - index]
    }
}

private func imdctShort(coefficients: const [*] f64, output: [*] f64)
{
    var realA, imagA, realB, imagB: [64] f64
    for k in 64
    {
        let a1 = coefficients[2 * (127 - 2 * k)]
        let b1 = coefficients[4 * k]
        let a2 = coefficients[2 * (128 - 2 * k - 1) + 1]
        let b2 = coefficients[4 * k + 2]
        realA[k] = a1 * g_ShortCos[k] - b1 * g_ShortSin[k]
        imagA[k] = b1 * g_ShortCos[k] + a1 * g_ShortSin[k]
        realB[k] = a2 * g_ShortCos[k] - b2 * g_ShortSin[k]
        imagB[k] = b2 * g_ShortCos[k] + a2 * g_ShortSin[k]
    }

    inverseFft(&realA, &imagA, 64)
    inverseFft(&realB, &imagB, 64)
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

private impl Imdct
{
    mtd reset() => Memory.set(&.delay, 0, #sizeof(.delay))

    mtd process(coefficients: const [*] f64, shortBlocks: bool, output: [*] f64)
    {
        var time: [512] f64
        if shortBlocks do
            imdctShort(coefficients, &time)
        else do
            imdctLong(coefficients, &time)
        for index in 256
        {
            time[index]       *= WINDOW[index]
            time[511 - index] *= WINDOW[index]
            output[index]     = 2.0 * (time[index] + .delay[index])
            .delay[index]     = time[256 + index]
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

private func bitAllocation(fscod: u32, start, end: s32, exponents: const [*] s32, fastGain, slowGain, fastDecay, slowDecay, dbKnee, floor, snrOffset, fastLeak, slowLeak: s32, delta: #null const *DeltaAllocation, result: [*] s32)
{
    var currentFastLeak = fastLeak
    var currentSlowLeak = slowLeak
    let bandStart       = MASKTAB[start]
    let bandEnd         = MASKTAB[end - 1] + 1
    var psd: [256] s32
    var bandPsd, excitation, mask: [50] s32
    var bin             = start
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
    if !bandStart
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

    if delta and (delta!.mode == 0 or delta!.mode == 1)
    {
        band = 0
        for segment in cast(u64) delta!.count
        {
            band += cast(s32) delta!.offset[segment]
            let code   = cast(s32) delta!.value[segment]
            let amount = (code >= 4 ? code - 3 : code - 4) << 7
            for deltaBand in cast(u64) delta!.length[segment]
            {
                discard deltaBand
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
            let address = Math.min(63, Math.max(0, (psd[source] - masked) >> 5))
            result[source - start] = BAPTAB[address]
            source                 += 1
        }

        band += 1
    }
}

private struct MantissaReader
{
    reader: *BitReader
    bap1:   [3] f64
    bap2:   [3] f64
    bap4:   [2] f64
    bap1At: u32 = 3
    bap2At: u32 = 3
    bap4At: u32 = 2
}

private impl MantissaReader
{
    func create(reader: *BitReader)->MantissaReader => {reader}

    mtd get(bap: s32)->f64
    {
        switch bap
        {
        case 0:
            return 0

        case 1:
            if .bap1At >= 3
            {
                let code = .reader.read(5)
                .bap1[0] = code < 27 ? (cast(f64) (code / 9) - 1.0) * (2.0 / 3.0) : 0
                .bap1[1] = code < 27 ? (cast(f64) ((code / 3) % 3) - 1.0) * (2.0 / 3.0) : 0
                .bap1[2] = code < 27 ? (cast(f64) (code % 3) - 1.0) * (2.0 / 3.0) : 0
                .bap1At  = 0
            }

            let result = .bap1[.bap1At]
            .bap1At += 1
            return result

        case 2:
            if .bap2At >= 3
            {
                let code = .reader.read(7)
                .bap2[0] = code < 125 ? (cast(f64) (code / 25) - 2.0) * (2.0 / 5.0) : 0
                .bap2[1] = code < 125 ? (cast(f64) ((code / 5) % 5) - 2.0) * (2.0 / 5.0) : 0
                .bap2[2] = code < 125 ? (cast(f64) (code % 5) - 2.0) * (2.0 / 5.0) : 0
                .bap2At  = 0
            }

            let result = .bap2[.bap2At]
            .bap2At += 1
            return result

        case 3:
            let code = .reader.read(3)
            return code < 7 ? (cast(f64) code - 3.0) * (2.0 / 7.0) : 0

        case 4:
            if .bap4At >= 2
            {
                let code = .reader.read(7)
                .bap4[0] = code < 121 ? (cast(f64) (code / 11) - 5.0) * (2.0 / 11.0) : 0
                .bap4[1] = code < 121 ? (cast(f64) (code % 11) - 5.0) * (2.0 / 11.0) : 0
                .bap4At  = 0
            }

            let result = .bap4[.bap4At]
            .bap4At += 1
            return result

        case 5:
            let code = .reader.read(4)
            return code < 15 ? (cast(f64) code - 7.0) * (2.0 / 15.0) : 0

        case 6, 7, 8, 9, 10, 11, 12, 13:
            return cast(f64) .reader.readSigned(cast(u32) bap - 1) / cast(f64) (1 << (bap - 2))

        case 14:
            return cast(f64) .reader.readSigned(14) / 8192.0

        case 15:
            return cast(f64) .reader.readSigned(16) / 32768.0

        default:
            return 0
        }
    }
}

private func initializeDolbyCore()
{
    for index in 128
    {
        let angle = 2.0 * Math.ConstF64.Pi * (8.0 * cast(f64) index + 1.0) / (8.0 * 512.0)
        g_LongCos[index] = -Math.cos(angle)
        g_LongSin[index] = -Math.sin(angle)
    }

    for index in 64
    {
        let angle = 2.0 * Math.ConstF64.Pi * (8.0 * cast(f64) index + 1.0) / (4.0 * 512.0)
        g_ShortCos[index] = -Math.cos(angle)
        g_ShortSin[index] = -Math.sin(angle)
    }
}
