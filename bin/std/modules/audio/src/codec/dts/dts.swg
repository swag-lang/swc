//! Format: DTS Coherent Acoustics Core packet decoder component.
//! Supported: 14- and 16-bit big- and little-endian core frames through 5.1 channels, scalar quantization, subframe transitions, both synthesis filters, and 64x or 128x LFE.
//! Not supported: Prediction, Huffman-coded side information or samples, high-frequency VQ, joint intensity, and DTS extension substreams.
//! Role: This file owns DTS Core frame syntax, subband reconstruction, channel mapping, and packet dispatch.
//
#global namespace Dts

using Core, Core.Errors, Core.Math

private const MaxChannels = 6
private const MaxPrimaryChannels = 5
private const MaxSubbands = 32
private const MaxSubbandSamples = 128
private const SamplesPerSubband = 8

private const ModeChannels: [10] u32 = [1, 2, 2, 2, 2, 3, 3, 4, 4, 5]
private const SampleRates: [16] u32 = [0, 8_000, 16_000, 32_000, 0, 0, 11_025, 22_050, 44_100, 0, 0, 12_000, 24_000, 48_000, 0, 0]
private const QuantLevels: [8] u32 = [0, 3, 5, 7, 9, 13, 17, 25]
private const BlockCodeBits: [8] u32 = [0, 7, 10, 12, 13, 15, 17, 19]
private const QuantSelectBits: [10] u32 = [1, 2, 2, 2, 2, 3, 3, 3, 3, 3]
private const QuantGroupSize: [10] u32 = [1, 3, 3, 3, 3, 7, 7, 7, 7, 7]
private const StepSizeLossy: [27] f64 = [0, 6_710_886, 4_194_304, 3_355_443, 2_474_639, 2_097_152, 1_761_608, 1_426_063, 796_918, 461_373, 251_658, 146_801, 79_692, 46_137, 27_263, 16_777, 10_486, 5_872, 3_355, 1_887, 1_258, 713, 336, 168, 84, 42, 21]
private const StepSizeLossless: [27] f64 = [0, 4_194_304, 2_097_152, 1_384_120, 1_048_576, 696_254, 524_288, 348_127, 262_144, 131_072, 65_431, 33_026, 16_450, 8_208, 4_100, 2_049, 1_024, 512, 256, 128, 64, 32, 16, 8, 4, 2, 1]
private const ScaleFactors: [128] f64 = [
    1, 1, 2, 2, 2, 2, 3, 3, 3, 4, 4, 5, 6, 7, 7, 8,
    10, 11, 12, 14, 16, 18, 20, 23, 26, 30, 34, 38, 44, 50, 56, 64,
    72, 82, 93, 106, 120, 136, 155, 176, 200, 226, 257, 292, 331, 376, 427, 484,
    550, 624, 708, 804, 912, 1_035, 1_175, 1_334, 1_514, 1_718, 1_950, 2_213, 2_512, 2_851, 3_236, 3_673,
    4_169, 4_732, 5_370, 6_095, 6_918, 7_852, 8_913, 10_116, 11_482, 13_032, 14_791, 16_788, 19_055, 21_627, 24_547, 27_861,
    31_623, 35_892, 40_738, 46_238, 52_481, 59_566, 67_608, 76_736, 87_096, 98_855, 112_202, 127_350, 144_544, 164_059, 186_209, 211_349,
    239_883, 272_270, 309_030, 350_752, 398_107, 451_856, 512_861, 582_103, 660_693, 749_894, 851_138, 966_051, 1_096_478, 1_244_515, 1_412_538, 1_603_245,
    1_819_701, 2_065_380, 2_344_229, 2_660_725, 3_019_952, 3_427_678, 3_890_451, 4_415_704, 5_011_872, 5_688_529, 6_456_542, 7_328_245, 8_317_638, 0, 0, 0]

private struct BitReader
{
    data:              const [*] u8
    bitSize:           u64
    bitPosition:       u64
    littleEndianWords: bool
    packed14:          bool
    overrun:           bool
}

private impl BitReader
{
    func create(packet: const [..] u8)->BitReader fail
    {
        if @countof(packet) < 4 do
            fail InvalidFormatError{"DTS packet header is truncated"}
        let bigEndian16    = packet[0] == 0x7F and packet[1] == 0xFE and packet[2] == 0x80 and packet[3] == 0x01
        let littleEndian16 = packet[0] == 0xFE and packet[1] == 0x7F and packet[2] == 0x01 and packet[3] == 0x80
        let bigEndian14    = packet[0] == 0x1F and packet[1] == 0xFF and packet[2] == 0xE8 and packet[3] == 0x00
        let littleEndian14 = packet[0] == 0xFF and packet[1] == 0x1F and packet[2] == 0x00 and packet[3] == 0xE8
        if !bigEndian16 and !littleEndian16 and !bigEndian14 and !littleEndian14 do
            fail InvalidFormatError{"DTS packet has no core sync word"}

        let packed14 = bigEndian14 or littleEndian14
        let bitSize  = packed14 ? (@countof(packet) / 2) * 14 : @countof(packet) * 8
        return {@dataof(packet), bitSize, 0, littleEndian16 or littleEndian14, packed14}
    }

    mtd read(count: u32)->u32
    {
        var result: u32
        for count
        {
            result <<= 1
            if .bitPosition >= .bitSize do
                .overrun = true
            else
            {
                if .packed14
                {
                    let wordIndex = .bitPosition / 14
                    let byteIndex = wordIndex * 2
                    let word      = .littleEndianWords ? cast(u32) .data[byteIndex] | (cast(u32) .data[byteIndex + 1] << 8) : (cast(u32) .data[byteIndex] << 8) | cast(u32) .data[byteIndex + 1]
                    result |= (word >> cast(u32) (13 - .bitPosition % 14)) & 1
                }
                else
                {
                    var byteIndex = .bitPosition >> 3
                    if .littleEndianWords do
                        byteIndex ^= 1
                    let bitIndex = 7 - (.bitPosition & 7)
                    result |= (cast(u32) .data[byteIndex] >> cast(u32) bitIndex) & 1
                }
            }

            .bitPosition += 1
        }

        return result
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
        .bitPosition += count
        if .bitPosition > .bitSize do
            .overrun = true
    }
}

internal struct FrameInfo
{
    frameBytes:  u64
    sampleRate:  u32
    channels:    u32
    frames:      u32
    speakerMask: u32
}

private struct FrameHeader
{
    frameBytes:       u32
    sampleRate:       u32
    frames:           u32
    mode:             u32
    channels:         u32
    primaryChannels:  u32
    bitRateIndex:     u32
    subframes:        u32
    lfe:              u32
    crc:              bool
    syncSubsubframes: bool
    predictorHistory: bool
    perfectFilter:    bool
    sumDifference:    bool
    surroundSumDiff:  bool
}

private func speakerMask(mode, lfe: u32)->u32
{
    const Masks: [10] u32 = [0x0004, 0x0003, 0x0003, 0x0003, 0x0003, 0x0007, 0x0103, 0x0107, 0x0033, 0x0037]
    return Masks[mode] | (lfe ? 0x0008 : 0)
}

private func parseFrameHeader(reader: *BitReader)->FrameHeader fail
{
    if reader.read(32) != 0x7FFE8001 do
        fail InvalidFormatError{"DTS packet has an invalid core sync word"}
    discard reader.read(1)
    if reader.read(5) != 31 do
        fail UnsupportedFormatError{"DTS packet uses a partial first sample block"}

    var result: retval
    result.crc = reader.read(1) != 0
    let blocks = reader.read(7) + 1
    if blocks < 8 or blocks > MaxSubbandSamples or blocks & 7 do
        fail InvalidFormatError{"DTS packet has an invalid sample-block count"}
    result.frames = blocks * 32
    let unpackedFrameBytes = reader.read(14) + 1
    result.frameBytes = reader.packed14 ? unpackedFrameBytes * 8 / 14 * 2 : unpackedFrameBytes
    result.mode       = reader.read(6)
    if result.mode >= @countof(ModeChannels) do
        fail UnsupportedFormatError{"DTS packet uses an unsupported channel arrangement"}
    result.primaryChannels = ModeChannels[result.mode]
    let rateIndex = reader.read(4)
    result.sampleRate = SampleRates[rateIndex]
    if !result.sampleRate do
        fail InvalidFormatError{"DTS packet states a reserved sampling frequency"}
    result.bitRateIndex = reader.read(5)
    if result.bitRateIndex >= 25 and result.bitRateIndex != 29 and result.bitRateIndex != 31 do
        fail InvalidFormatError{"DTS packet states a reserved transmission rate"}

    discard reader.read(1)
    discard reader.read(1)
    discard reader.read(1)
    discard reader.read(1)
    discard reader.read(1)
    discard reader.read(3)
    discard reader.read(1)
    result.syncSubsubframes = reader.read(1) != 0
    result.lfe              = reader.read(2)
    if result.lfe == 3 do
        fail InvalidFormatError{"DTS packet states a reserved LFE mode"}
    result.channels         = result.primaryChannels + (result.lfe ? 1 : 0)
    result.predictorHistory = reader.read(1) != 0
    if result.crc do
        reader.skip(16)
    result.perfectFilter = reader.read(1) != 0
    reader.skip(6)
    let resolution = reader.read(3)
    if resolution == 4 or resolution == 7 do
        fail InvalidFormatError{"DTS packet states a reserved PCM resolution"}
    result.sumDifference   = reader.read(1) != 0
    result.surroundSumDiff = reader.read(1) != 0
    reader.skip(4)
    if reader.overrun do
        fail InvalidFormatError{"DTS packet header is truncated"}
    return result
}

internal func frameInfo(packet: const [..] u8)->FrameInfo fail
{
    var reader = try BitReader.create(packet)
    let header = try parseFrameHeader(&reader)
    return {header.frameBytes, header.sampleRate, header.channels, header.frames, speakerMask(header.mode, header.lfe)}
}

internal func packetFrameCount(packet: const [..] u8)->u32 fail => (try frameInfo(packet)).frames

private struct Codec
{
    using base: Audio.Codec

    sampleRate: u32
    channels:   u32
    history:    [MaxPrimaryChannels, 512] f64
    lfeHistory: [8] f64
}

private impl Codec
{
    mtd resetState()
    {
        Memory.set(&.history, 0, #sizeof(.history))
        Memory.set(&.lfeHistory, 0, #sizeof(.lfeHistory))
    }

    mtd decodeTransition(reader: *BitReader, selector: u32)->u32 fail
    {
        if selector == 3 do
            return reader.read(2)
        var code: u32
        for length in 1'u32 until 4
        {
            code = (code << 1) | reader.read(1)
            if selector == 0
            {
                if length == 1 and code == 0 do
                    return 0
                if length == 2 and code == 2 do
                    return 1
                if length == 3 and code >= 6 do
                    return code - 4
            }
            elif selector == 1
            {
                if length == 1 and code == 0 do
                    return 3
                if length == 2 and code == 2 do
                    return 0
                if length == 3 and code >= 6 do
                    return code - 5
            }
            else
            {
                if length == 1 and code == 0 do
                    return 2
                if length == 2 and code == 2 do
                    return 3
                if length == 3 and code >= 6 do
                    return code - 6
            }
        }

        fail InvalidFormatError{"DTS transition-mode code is invalid"}
    }

    mtd sourceDestination(mode, source, lfe: u32)->u32
    {
        if mode == 5 or mode == 7 or mode == 9
        {
            if source == 0 do
                return 2
            if source == 1 do
                return 0
            if source == 2 do
                return 1
            return source + (lfe ? 1 : 0)
        }

        if (mode == 6 or mode == 8) and source >= 2 do
            return source + (lfe ? 1 : 0)
        return source
    }

    mtd lfeDestination(header: const *FrameHeader)->u32
    {
        if header.mode <= 4 do
            return header.primaryChannels
        if header.mode == 5 do
            return 3
        if header.mode == 6 do
            return 2
        if header.mode == 7 do
            return 3
        if header.mode == 8 do
            return 2
        return 3
    }

    mtd synthesize(destination: [*] s16, header: const *FrameHeader, subbands: *[MaxPrimaryChannels, MaxSubbands, MaxSubbandSamples] f64)
    {
        for channel in header.primaryChannels
        {
            let outputChannel = .sourceDestination(header.mode, channel, header.lfe)
            for sample in header.frames / 32
            {
                var transformed: [32] f64
                for output in 32
                {
                    var sum: f64
                    for band in 32
                    {
                        let angle = Math.ConstF64.Pi * (cast(f64) band + 0.5) * (cast(f64) output + 0.5) / 32.0
                        sum += subbands[][channel, band, sample] * Math.cos(angle)
                    }

                    transformed[output] = sum * 0.25
                }

                for index in 16
                {
                    .history[channel, index]      = transformed[index] - transformed[31 - index]
                    .history[channel, 16 + index] = transformed[index] + transformed[31 - index]
                }

                let filter = header.perfectFilter ? BandFirPerfect : BandFirNonPerfect
                for index in 16
                {
                    let reverse = 15 - index
                    var first, second: f64
                    var tap     = 0'u64
                    while tap < 512
                    {
                        first  += .history[channel, index + tap] * filter[index + tap]
                        second += .history[channel, reverse + tap] * filter[16 + index + tap]
                        tap    += 64
                    }

                    tap = 32
                    while tap < 512
                    {
                        first  += .history[channel, 16 + index + tap] * filter[index + tap]
                        second += .history[channel, 16 + reverse + tap] * filter[16 + index + tap]
                        tap    += 64
                    }

                    destination[(sample * 32 + index) * header.channels + outputChannel]      = cast(s16) Math.clamp(Math.round(first), -32_768.0, 32_767.0)
                    destination[(sample * 32 + 16 + index) * header.channels + outputChannel] = cast(s16) Math.clamp(Math.round(second), -32_768.0, 32_767.0)
                }

                var index = 512'u64
                while index > 32
                {
                    index -= 1
                    .history[channel, index] = .history[channel, index - 32]
                }
            }
        }

        if header.sumDifference or header.mode == 3
        {
            for frame in header.frames
            {
                let left  = cast(s32) destination[frame * header.channels]
                let right = cast(s32) destination[frame * header.channels + 1]
                destination[frame * header.channels]     = cast(s16) Math.clamp(left + right, -32_768, 32_767)
                destination[frame * header.channels + 1] = cast(s16) Math.clamp(left - right, -32_768, 32_767)
            }
        }

        if header.surroundSumDiff and header.mode >= 8
        {
            let leftChannel  = header.lfe ? 3 : 2
            let rightChannel = leftChannel + 1
            for frame in header.frames
            {
                let left  = cast(s32) destination[frame * header.channels + leftChannel]
                let right = cast(s32) destination[frame * header.channels + rightChannel]
                destination[frame * header.channels + leftChannel]  = cast(s16) Math.clamp(left + right, -32_768, 32_767)
                destination[frame * header.channels + rightChannel] = cast(s16) Math.clamp(left - right, -32_768, 32_767)
            }
        }
    }

    mtd synthesizeLfe(destination: [*] s16, header: const *FrameHeader, samples: const [*] f64, sampleCount: u32)
    {
        if !header.lfe do
            return
        let factor           = header.lfe == 1 ? 128'u32 : 64
        let coefficients     = header.lfe == 1 ? LfeFir128 : LfeFir64
        let coefficientCount = header.lfe == 1 ? 4'u32 : 8
        let outputChannel    = .lfeDestination(header)
        for sample in sampleCount
        {
            for half in factor / 2
            {
                var first, second: f64
                for tap in coefficientCount
                {
                    let source = cast(s32) sample - cast(s32) tap
                    let value  = source < 0 ? .lfeHistory[8 + source] : samples[source]
                    first  += coefficients[half * coefficientCount + tap] * value
                    second += coefficients[255 - half * coefficientCount - tap] * value
                }

                let frame = sample * factor
                destination[(frame + half) * header.channels + outputChannel]              = cast(s16) Math.clamp(Math.round(first), -32_768.0, 32_767.0)
                destination[(frame + factor / 2 + half) * header.channels + outputChannel] = cast(s16) Math.clamp(Math.round(second), -32_768.0, 32_767.0)
            }
        }

        for index in 8
        {
            let source = cast(s32) sampleCount - 8 + cast(s32) index
            .lfeHistory[index] = source < 0 ? .lfeHistory[8 + source] : samples[source]
        }
    }

    mtd decodeFrame(destination: [*] s16, packet: const [..] u8)->FrameHeader fail
    {
        var reader = try BitReader.create(packet)
        var header = try parseFrameHeader(&reader)
        if header.frameBytes != @countof(packet) do
            fail InvalidFormatError{"DTS packet size does not match its core-frame header"}
        if header.sampleRate != .sampleRate or header.channels != .channels do
            fail InvalidFormatError{"DTS packet shape differs from its container track"}

        header.subframes = reader.read(4) + 1
        let channels = reader.read(3) + 1
        if channels != header.primaryChannels do
            fail InvalidFormatError{"DTS primary-channel count differs from its channel arrangement"}

        var subbandCount:       [MaxPrimaryChannels] u32
        var vqStart:            [MaxPrimaryChannels] u32
        var joint:              [MaxPrimaryChannels] u32
        var transitionSelector: [MaxPrimaryChannels] u32
        var scaleSelector:      [MaxPrimaryChannels] u32
        var allocationSelector: [MaxPrimaryChannels] u32
        var quantSelector:      [MaxPrimaryChannels, 10] u32
        for channel in channels
        {
            subbandCount[channel] = reader.read(5) + 2
            if subbandCount[channel] > MaxSubbands do
                fail InvalidFormatError{"DTS subband count exceeds the core limit"}
        }

        for channel in channels do
            vqStart[channel] = reader.read(5) + 1
        for channel in channels do
            joint[channel] = reader.read(3)
        for channel in channels do
            transitionSelector[channel] = reader.read(2)
        for channel in channels
        {
            scaleSelector[channel] = reader.read(3)
            if scaleSelector[channel] == 7 do
                fail InvalidFormatError{"DTS packet states a reserved scale-factor codebook"}
        }

        for channel in channels
        {
            allocationSelector[channel] = reader.read(3)
            if allocationSelector[channel] == 7 do
                fail InvalidFormatError{"DTS packet states a reserved bit-allocation codebook"}
        }

        for book in 10
        {
            for channel in channels do
                quantSelector[channel, book] = reader.read(QuantSelectBits[book])
        }

        for book in 10
        {
            for channel in channels
            {
                if quantSelector[channel, book] < QuantGroupSize[book] do
                    discard reader.read(2)
            }
        }

        if header.crc do
            reader.skip(16)

        var subbands:   [MaxPrimaryChannels, MaxSubbands, MaxSubbandSamples] f64
        var lfeSamples: [64] f64
        var subbandPosition, lfePosition: u32
        for subframe in header.subframes
        {
            discard subframe
            let subsubframes = reader.read(2) + 1
            reader.skip(3)
            let subbandSamples = subsubframes * SamplesPerSubband
            if subbandPosition + subbandSamples > header.frames / 32 do
                fail InvalidFormatError{"DTS subframe sample table exceeds the frame"}

            var prediction: [MaxPrimaryChannels, MaxSubbands] bool
            for channel in channels
            {
                for band in subbandCount[channel] do
                    prediction[channel, band] = reader.read(1) != 0
            }

            for channel in channels
            {
                for band in subbandCount[channel] where prediction[channel, band]
                {
                    discard reader.read(12)
                    fail UnsupportedFormatError{"DTS prediction is not supported"}
                }
            }

            var allocation: [MaxPrimaryChannels, MaxSubbands] u32
            for channel in channels
            {
                if allocationSelector[channel] < 5 do
                    fail UnsupportedFormatError{"DTS Huffman-coded bit allocation is not supported"}
                let bitCount = allocationSelector[channel] - 1
                for band in Math.min(vqStart[channel], subbandCount[channel])
                {
                    allocation[channel, band] = reader.read(bitCount)
                    if allocation[channel, band] >= 27 do
                        fail InvalidFormatError{"DTS bit allocation exceeds the core limit"}
                }
            }

            var transition: [MaxPrimaryChannels, MaxSubbands] u32
            if subsubframes > 1
            {
                for channel in channels
                {
                    for band in Math.min(vqStart[channel], subbandCount[channel]) where allocation[channel, band]
                    {
                        transition[channel, band] = try .decodeTransition(&reader, transitionSelector[channel])
                    }
                }
            }

            var scales: [MaxPrimaryChannels, MaxSubbands, 2] f64
            for channel in channels
            {
                if scaleSelector[channel] < 5 do
                    fail UnsupportedFormatError{"DTS Huffman-coded scale factors are not supported"}
                let bitCount = scaleSelector[channel] + 1
                for band in subbandCount[channel]
                {
                    if band < vqStart[channel] and !allocation[channel, band] do
                        continue
                    let scaleIndex = reader.read(bitCount)
                    if scaleIndex >= @countof(ScaleFactors) do
                        fail InvalidFormatError{"DTS scale-factor index exceeds its table"}
                    scales[channel, band, 0] = ScaleFactors[scaleIndex]
                    if transition[channel, band]
                    {
                        let second = reader.read(bitCount)
                        if second >= @countof(ScaleFactors) do
                            fail InvalidFormatError{"DTS scale-factor index exceeds its table"}
                        scales[channel, band, 1] = ScaleFactors[second]
                    }
                }
            }

            for channel in channels where joint[channel]
            {
                discard channel
                fail UnsupportedFormatError{"DTS joint-intensity coding is not supported"}
            }

            if header.crc do
                reader.skip(16)
            for channel in channels where vqStart[channel] < subbandCount[channel]
            {
                discard channel
                fail UnsupportedFormatError{"DTS high-frequency vector quantization is not supported"}
            }

            if header.lfe
            {
                let count = 2 * header.lfe * subsubframes
                if lfePosition + count > @countof(lfeSamples) do
                    fail InvalidFormatError{"DTS LFE sample table exceeds the frame"}
                for index in count do
                    lfeSamples[lfePosition + index] = cast(f64) reader.readSigned(8)
                let scaleIndex = reader.read(8)
                if scaleIndex >= @countof(ScaleFactors) do
                    fail InvalidFormatError{"DTS LFE scale-factor index exceeds its table"}
                let scale = ScaleFactors[scaleIndex] * 0.035
                for index in count do
                    lfeSamples[lfePosition + index] *= scale
                lfePosition += count
            }

            for subsubframe in subsubframes
            {
                for channel in channels
                {
                    for band in Math.min(vqStart[channel], subbandCount[channel])
                    {
                        let bits = allocation[channel, band]
                        var audio: [SamplesPerSubband] s32
                        if !bits {}
                        elif bits <= 10 and quantSelector[channel, bits - 1] < QuantGroupSize[bits - 1]
                        {
                            fail UnsupportedFormatError{"DTS Huffman-coded audio samples are not supported"}
                        }
                        elif bits <= 7
                        {
                            let levels = QuantLevels[bits]
                            let offset = cast(s32) ((levels - 1) / 2)
                            var first  = reader.read(BlockCodeBits[bits])
                            var second = reader.read(BlockCodeBits[bits])
                            for index in 4
                            {
                                audio[index]     = cast(s32) (first % levels) - offset
                                first            /= levels
                                audio[4 + index] = cast(s32) (second % levels) - offset
                                second           /= levels
                            }

                            if first or second do
                                fail InvalidFormatError{"DTS block code exceeds its quantization levels"}
                        }
                        else
                        {
                            for index in SamplesPerSubband do
                                audio[index] = reader.readSigned(bits - 3)
                        }

                        let scale  = transition[channel, band] and subsubframe >= transition[channel, band] ? scales[channel, band, 1] : scales[channel, band, 0]
                        let step   = header.bitRateIndex == 31 ? StepSizeLossless[bits] : StepSizeLossy[bits]
                        let factor = step * scale / 4_194_304.0
                        for index in SamplesPerSubband do
                            subbands[channel, band, subbandPosition + subsubframe * SamplesPerSubband + index] = cast(f64) audio[index] * factor
                    }
                }

                if (subsubframe == subsubframes - 1 or header.syncSubsubframes) and reader.read(16) != 0xFFFF do
                    fail InvalidFormatError{"DTS subsubframe sync word is invalid"}
            }

            subbandPosition += subbandSamples
        }

        if subbandPosition != header.frames / 32 do
            fail InvalidFormatError{"DTS subframes do not fill the declared frame"}
        if reader.overrun do
            fail InvalidFormatError{"DTS packet is truncated"}
        .synthesize(destination, &header, &subbands)
        .synthesizeLfe(destination, &header, &lfeSamples, lfePosition)
        return header
    }
}

impl IPacketCodec for Codec
{
    mtd impl canDecode(encoding: SoundFileEncoding)->bool => encoding == .Dts

    mtd impl initialize(config: const [..] u8, sampleRateHz, channels: u32) fail
    {
        discard config
        if !sampleRateHz or !channels or channels > MaxChannels do
            fail BadParameterError{"DTS audio needs one to six channels and a non-zero sample rate"}
        .sampleRate = sampleRateHz
        .channels   = channels
        .resetState()
    }

    mtd impl reset() => .resetState()

    mtd impl decodePacket(destination: [*] void, destinationSize: u64, packet: const [..] u8)->u64 fail
    {
        let info     = try frameInfo(packet)
        let required = cast(u64) info.frames * .channels * #sizeof(s16)
        if destinationSize < required do
            fail BadParameterError{"DTS destination buffer is too small"}
        discard try .decodeFrame(cast([*] s16) destination, packet)
        return required
    }
}

#init
{
    registerPacketCodec'Codec()
}
