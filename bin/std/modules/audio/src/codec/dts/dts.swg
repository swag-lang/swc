//! Format: DTS Coherent Acoustics Core packet decoder component.
//! Supported: 14- and 16-bit big- and little-endian core frames through 5.1 channels, including the backward-compatible core of DTS-HD access units, scalar quantization, ADPCM prediction, omission of high-frequency VQ bands, subframe transitions, both synthesis filters, and 64x or 128x LFE.
//! Not supported: High-frequency VQ reconstruction, joint intensity, and decoding DTS extension substreams.
//! Role: This file owns DTS Core frame syntax, subband reconstruction, channel mapping, and packet dispatch.
//
#global namespace Dts

using Core, Core.Errors, Core.Math

private const MaxChannels        = 6
private const MaxPrimaryChannels = 5
private const MaxSubbands        = 32
private const MaxSubbandSamples  = 128
private const HistorySamples     = 512
private const SamplesPerSubband  = 8

// Dequantized subband samples and the synthesis output use the 24-bit PCM scale of ETSI TS
// 102 114. The packet codec publishes 16-bit samples, so every output sample drops eight bits.
private const OutputScale = 1.0 / 256.0

private const ModeChannels:     [10] u32  = [1, 2, 2, 2, 2, 3, 3, 4, 4, 5]
private const SampleRates:      [16] u32  = [0, 8_000, 16_000, 32_000, 0, 0, 11_025, 22_050, 44_100, 0, 0, 12_000, 24_000, 48_000, 0, 0]
private const QuantLevels:      [8] u32   = [0, 3, 5, 7, 9, 13, 17, 25]
private const BlockCodeBits:    [8] u32   = [0, 7, 10, 12, 13, 15, 17, 19]
private const QuantSelectBits:  [10] u32  = [1, 2, 2, 2, 2, 3, 3, 3, 3, 3]
private const QuantGroupSize:   [10] u32  = [1, 3, 3, 3, 3, 7, 7, 7, 7, 7]
private const QuantAdjustments: [4] f64   = [1.0, 1.125, 1.25, 1.4375]
private const StepSizeLossy:    [27] f64  = [0, 6_710_886, 4_194_304, 3_355_443, 2_474_639, 2_097_152, 1_761_608, 1_426_063, 796_918, 461_373, 251_658, 146_801, 79_692, 46_137, 27_263, 16_777, 10_486, 5_872, 3_355, 1_887, 1_258, 713, 336, 168, 84, 42, 21]
private const StepSizeLossless: [27] f64  = [0, 4_194_304, 2_097_152, 1_384_120, 1_048_576, 696_254, 524_288, 348_127, 262_144, 131_072, 65_431, 33_026, 16_450, 8_208, 4_100, 2_049, 1_024, 512, 256, 128, 64, 32, 16, 8, 4, 2, 1]
private const ScaleFactors:     [128] f64 = [
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
    byteSize:          u64
    bytePosition:      u64
    buffer:            u64
    bitsBuffered:      u32
    littleEndianWords: bool
    packed14:          bool
    overrun:           bool
}

private impl BitReader
{
    func create(packet: const [..] u8)->BitReader fail
    {
        if packet.count < 4 do
            fail InvalidFormatError{"DTS packet header is truncated"}
        let bigEndian16    = packet[0] == 0x7F and packet[1] == 0xFE and packet[2] == 0x80 and packet[3] == 0x01
        let littleEndian16 = packet[0] == 0xFE and packet[1] == 0x7F and packet[2] == 0x01 and packet[3] == 0x80
        let bigEndian14    = packet[0] == 0x1F and packet[1] == 0xFF and packet[2] == 0xE8 and packet[3] == 0x00
        let littleEndian14 = packet[0] == 0xFF and packet[1] == 0x1F and packet[2] == 0x00 and packet[3] == 0xE8
        if not bigEndian16 and not littleEndian16 and not bigEndian14 and not littleEndian14 do
            fail InvalidFormatError{"DTS packet has no core sync word"}

        return {data: packet.buffer, byteSize: packet.count, littleEndianWords: littleEndian16 or littleEndian14, packed14: bigEndian14 or littleEndian14}
    }

    // Keep the next bits at the low end of the buffer, in stream order. Packed words contribute
    // only their low fourteen bits. Only an unpacked big-endian stream can end in a single byte.
    mtd refill(count: u32)
    {
        if not .packed14 and .byteSize - .bytePosition >= 4
        {
            var bytes: u32
            Memory.copy(&bytes, .data + .bytePosition, #sizeof(u32))
            let word = .littleEndianWords ? Math.rol(Math.littleEndianToNative(bytes), 16) : Math.bigEndianToNative(bytes)
            .buffer        = (.buffer << 32) | word
            .bitsBuffered += 32
            .bytePosition += 4
            return
        }

        let wordBits = .packed14 ? 14'u32 : 16
        let mask     = .packed14 ? 0x3FFF'u16 : 0xFFFF
        while .bitsBuffered < count and .byteSize - .bytePosition >= 2
        {
            let first  = .data[.bytePosition]
            let second = .data[.bytePosition + 1]
            let word   = .littleEndianWords ? Math.make16(second, first) : Math.make16(first, second)
            .buffer       = (.buffer << wordBits) | (word & mask)
            .bitsBuffered += wordBits
            .bytePosition += 2
        }

        if .bitsBuffered < count and
           .bytePosition < .byteSize and
           not .packed14 and
           not .littleEndianWords
        {
            .buffer       = (.buffer << 8) | .data[.bytePosition]
            .bitsBuffered += 8
            .bytePosition += 1
        }
    }

    // Reads at most 32 bits, padding a truncated field with zeros.
    #[Swag.Inline]
    mtd read(count: u32)->u32
    {
        if .bitsBuffered < count
        {
            .refill(count)
            if .bitsBuffered < count
            {
                .overrun = true
                let remaining = .bitsBuffered
                .bitsBuffered = 0
                let bits = .buffer & ((1'u64 << remaining) - 1)
                return cast(u32, (bits << (count - remaining)))
            }
        }

        .bitsBuffered -= count
        return cast(u32, ((.buffer >> .bitsBuffered) & ((1'u64 << count) - 1)))
    }

    mtd readSigned(count: u32)->s32
    {
        let raw = .read(count)
        if not count do
            return 0
        let sign = 1'u32 << (count - 1)
        if raw & sign do
            return cast #bit (s32, (raw | (~0'u32 << count)))
        return cast(s32, raw)
    }

    mtd readHuffman(root: u32)->s32 fail
    {
        var node = cast(s32, root)
        while node >= 0
        {
            let bit = .read(1)
            if .overrun do
                fail InvalidFormatError{"DTS Huffman code is truncated"}
            node = HuffmanNodes[node, bit]
        }

        return -1 - node
    }

    mtd readScale(selector: u32, index: *s32)->f64 fail
    {
        if selector < 5 do
            index[] += (try .readHuffman(ScaleBookRoots[selector])) - 64
        else do
            index[] = cast(s32, .read(selector + 1))
        let entries = selector == 6 ? 128 : 64
        if index[] < 0 or index[] >= entries do
            fail InvalidFormatError{"DTS scale-factor index exceeds its table"}
        if selector == 6 do
            return ScaleFactors[index[]]
        if index[] == 63 do
            return 0
        return ScaleFactors[index[] * 2]
    }

    mtd skip(count: u32)
    {
        discard .read(count)
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

    var result: #returntype
    result.crc = reader.read(1) != 0
    let blocks = reader.read(7) + 1
    if blocks < 8 or blocks > MaxSubbandSamples or blocks & 7 do
        fail InvalidFormatError{"DTS packet has an invalid sample-block count"}
    result.frames = blocks * 32
    let unpackedFrameBytes = reader.read(14) + 1
    result.frameBytes = reader.packed14 ? unpackedFrameBytes * 8 / 14 * 2 : unpackedFrameBytes
    result.mode       = reader.read(6)
    if result.mode >= ModeChannels.count do
        fail UnsupportedFormatError{"DTS packet uses an unsupported channel arrangement"}
    result.primaryChannels = ModeChannels[result.mode]
    let rateIndex = reader.read(4)
    result.sampleRate = SampleRates[rateIndex]
    if not result.sampleRate do
        fail InvalidFormatError{"DTS packet states a reserved sampling frequency"}
    result.bitRateIndex = reader.read(5)
    if result.bitRateIndex >= 25 and result.bitRateIndex != 29 and result.bitRateIndex != 31 do
        fail InvalidFormatError{"DTS packet states a reserved transmission rate"}

    reader.skip(9)
    result.syncSubsubframes = reader.read(1) != 0
    result.lfe = reader.read(2)
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
    return FrameInfo{header.frameBytes, header.sampleRate, header.channels, header.frames, speakerMask(header.mode, header.lfe)}
}

internal func packetFrameCount(packet: const [..] u8)->u32 fail => (try frameInfo(packet)).frames

private struct Codec
{
    using base: Audio.Codec

    sampleRate:        u32
    channels:          u32
    history:           [MaxPrimaryChannels, 2 * HistorySamples] f64
    historyStart:      [MaxPrimaryChannels] u32
    predictionHistory: [MaxPrimaryChannels, MaxSubbands, 4] f64
    lfeHistory:        [8] f64
}

private impl Codec
{
    mtd resetState()
    {
        Memory.set(&.history, 0, #sizeof(.history))
        Memory.clear(&.historyStart, #sizeof(.historyStart))
        Memory.set(&.predictionHistory, 0, #sizeof(.predictionHistory))
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
        let filter = header.perfectFilter ? BandFirPerfect : BandFirNonPerfect
        for channel in header.primaryChannels
        {
            let outputChannel = .sourceDestination(header.mode, channel, header.lfe)
            var historyStart  = .historyStart[channel]
            for sample in header.frames / 32
            {
                let bands = cast(const [*] f64, &subbands[][channel, 0, sample])
                var transformed: [32] f64
                synthesisDct(bands, MaxSubbandSamples, &transformed)

                // Mirror each block so the FIR can read a contiguous 512-sample window.
                historyStart = (historyStart + HistorySamples - 32) & (HistorySamples - 1)
                let history = cast([*] f64, &.history[channel, historyStart])
                for index in 16
                {
                    let first  = transformed[index] - transformed[31 - index]
                    let second = transformed[index] + transformed[31 - index]
                    history[index]                       = first
                    history[16 + index]                  = second
                    history[HistorySamples + index]      = first
                    history[HistorySamples + 16 + index] = second
                }

                for index in 16
                {
                    let reverse = 15 - index
                    var first, second: f64
                    for phase in 8
                    {
                        let tap = phase * 64
                        first  += history[index + tap] * filter[index + tap]
                        second += history[reverse + tap] * filter[16 + index + tap]
                    }

                    for phase in 8
                    {
                        let tap = 32 + phase * 64
                        first  += history[16 + index + tap] * filter[index + tap]
                        second += history[16 + reverse + tap] * filter[16 + index + tap]
                    }

                    destination[(sample * 32 + index) * header.channels + outputChannel]      = cast(s16, Math.clamp(Math.round(first * OutputScale), -32_768.0, 32_767.0))
                    destination[(sample * 32 + 16 + index) * header.channels + outputChannel] = cast(s16, Math.clamp(Math.round(second * OutputScale), -32_768.0, 32_767.0))
                }
            }

            .historyStart[channel] = historyStart
        }

        if header.sumDifference or header.mode == 3
        {
            for frame in header.frames
            {
                let left  = cast(s32, destination[frame * header.channels])
                let right = cast(s32, destination[frame * header.channels + 1])
                destination[frame * header.channels]     = cast(s16, Math.clamp(left + right, -32_768, 32_767))
                destination[frame * header.channels + 1] = cast(s16, Math.clamp(left - right, -32_768, 32_767))
            }
        }

        if header.surroundSumDiff and header.mode >= 8
        {
            let leftChannel  = header.lfe ? 3 : 2
            let rightChannel = leftChannel + 1
            for frame in header.frames
            {
                let left  = cast(s32, destination[frame * header.channels + leftChannel])
                let right = cast(s32, destination[frame * header.channels + rightChannel])
                destination[frame * header.channels + leftChannel]  = cast(s16, Math.clamp(left + right, -32_768, 32_767))
                destination[frame * header.channels + rightChannel] = cast(s16, Math.clamp(left - right, -32_768, 32_767))
            }
        }
    }

    mtd synthesizeLfe(destination: [*] s16, header: const *FrameHeader, samples: const [*] f64, sampleCount: u32)
    {
        if not header.lfe do
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
                    let source = cast(s32, sample) - cast(s32, tap)
                    let value  = source < 0 ? .lfeHistory[8 + source] : samples[source]
                    first  += coefficients[half * coefficientCount + tap] * value
                    second += coefficients[255 - half * coefficientCount - tap] * value
                }

                let frame = sample * factor
                destination[(frame + half) * header.channels + outputChannel] = cast(s16, Math.clamp(Math.round(first * OutputScale), -32_768.0, 32_767.0))
                destination[(frame + factor / 2 + half) * header.channels + outputChannel] = cast(s16, Math.clamp(Math.round(second * OutputScale), -32_768.0, 32_767.0))
            }
        }

        for index in 8
        {
            let source = cast(s32, sampleCount) - 8 + cast(s32, index)
            .lfeHistory[index] = source < 0 ? .lfeHistory[8 + source] : samples[source]
        }
    }

    mtd decodeFrame(destination: [*] s16, packet: const [..] u8)->FrameHeader fail
    {
        var reader = try BitReader.create(packet)
        var header = try parseFrameHeader(&reader)
        if header.frameBytes != packet.count do
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

        var quantAdjust: [MaxPrimaryChannels, 10] f64
        for book in 10
        {
            for channel in channels
            {
                if quantSelector[channel, book] < QuantGroupSize[book] do
                    quantAdjust[channel, book] = QuantAdjustments[reader.read(2)]
            }
        }

        if header.crc do
            reader.skip(16)

        var subbands:   [MaxPrimaryChannels, MaxSubbands, MaxSubbandSamples] f64
        var lfeSamples: [64] f64
        var subbandPosition, lfePosition: u32
        for header.subframes
        {
            let subsubframes = reader.read(2) + 1
            reader.skip(3)
            let subbandSamples = subsubframes * SamplesPerSubband
            if subbandPosition + subbandSamples > header.frames / 32 do
                fail InvalidFormatError{"DTS subframe sample table exceeds the frame"}

            var prediction:      [MaxPrimaryChannels, MaxSubbands] bool
            var predictionIndex: [MaxPrimaryChannels, MaxSubbands] u32
            for channel in channels
            {
                for band in subbandCount[channel] do
                    prediction[channel, band] = reader.read(1) != 0
            }

            for channel in channels
            {
                for band in subbandCount[channel] where prediction[channel, band] do
                    predictionIndex[channel, band] = reader.read(12)
            }

            var allocation: [MaxPrimaryChannels, MaxSubbands] u32
            for channel in channels
            {
                let selector = allocationSelector[channel]
                for band in Math.min(vqStart[channel], subbandCount[channel])
                {
                    if selector < 5 do
                        allocation[channel, band] = 1 + cast(u32, (try reader.readHuffman(AllocationBookRoots[selector])))
                    else do
                        allocation[channel, band] = reader.read(selector - 1)
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
                var scaleIndex: s32
                for band in subbandCount[channel]
                {
                    if band < vqStart[channel] and not allocation[channel, band] do
                        continue
                    scales[channel, band, 0] = try reader.readScale(scaleSelector[channel], &scaleIndex)
                    if transition[channel, band] do
                        scales[channel, band, 1] = try reader.readScale(scaleSelector[channel], &scaleIndex)
                }
            }

            for channel in channels where joint[channel]
            {
                fail UnsupportedFormatError{"DTS joint-intensity coding is not supported"}
            }

            if header.crc do
                reader.skip(16)

            // One ten-bit address names the complete vector for each high-frequency subband.
            // ETSI TS 102 114 permits a constrained decoder to omit those highest bands; consume
            // the addresses so the scalar bands still reconstruct instead of rejecting the frame.
            for channel in channels
            {
                for Math.min(vqStart[channel], subbandCount[channel]) until subbandCount[channel] do
                    discard reader.read(10)
            }

            if header.lfe
            {
                let count = 2 * header.lfe * subsubframes
                if lfePosition + count > lfeSamples.count do
                    fail InvalidFormatError{"DTS LFE sample table exceeds the frame"}
                for index in count do
                    lfeSamples[lfePosition + index] = cast(f64, reader.readSigned(8))
                let scaleIndex = reader.read(8)
                if scaleIndex >= ScaleFactors.count do
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
                        var adjustment = 1.0'f64
                        if not bits {}
                        elif bits <= 10 and quantSelector[channel, bits - 1] < QuantGroupSize[bits - 1]
                        {
                            let root = QuantBookRoots[bits - 1, quantSelector[channel, bits - 1]]
                            let bias = QuantBookBias[bits - 1]
                            for index in SamplesPerSubband do
                                audio[index] = (try reader.readHuffman(root)) - bias
                            adjustment = quantAdjust[channel, bits - 1]
                        }
                        elif bits <= 7
                        {
                            let levels = QuantLevels[bits]
                            let offset = cast(s32, ((levels - 1) / 2))
                            var first  = reader.read(BlockCodeBits[bits])
                            var second = reader.read(BlockCodeBits[bits])
                            for index in 4
                            {
                                audio[index]     = cast(s32, (first % levels)) - offset
                                first            /= levels
                                audio[4 + index] = cast(s32, (second % levels)) - offset
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
                        let adjustedScale = Math.min(Math.floor(scale * adjustment), 8_388_607.0)
                        let factor = step * adjustedScale / 4_194_304.0
                        for index in SamplesPerSubband do
                            subbands[channel, band, subbandPosition + subsubframe * SamplesPerSubband + index] = cast(f64, audio[index]) * factor
                    }
                }

                if (subsubframe == subsubframes - 1 or header.syncSubsubframes) and reader.read(16) != 0xFFFF do
                    fail InvalidFormatError{"DTS subsubframe sync word is invalid"}
            }

            // The four-tap predictor is applied after every scalar sample of this subframe has
            // been dequantized. A frame whose predictor-history switch is clear starts from zero;
            // otherwise its first four references come from the preceding frame.
            for channel in channels
            {
                for band in Math.min(vqStart[channel], subbandCount[channel]) where prediction[channel, band]
                {
                    let vector = predictionIndex[channel, band]
                    for offset in subbandSamples
                    {
                        let position = subbandPosition + offset
                        var predicted: f64
                        for tap in 4
                        {
                            let source = cast(s32, position) - 1 - cast(s32, tap)
                            var value  = 0.0'f64
                            if source < 0
                            {
                                if header.predictorHistory do
                                    value = .predictionHistory[channel, band, 4 + source]
                            }
                            else
                            {
                                value = subbands[channel, band, source]
                            }

                            predicted += value * cast(f64, AdpcmCoefficients[vector, tap])
                        }

                        subbands[channel, band, position] = Math.clamp(subbands[channel, band, position] + predicted / 8_192.0, -8_388_608.0, 8_388_607.0)
                    }
                }
            }

            subbandPosition += subbandSamples
        }

        if subbandPosition != header.frames / 32 do
            fail InvalidFormatError{"DTS subframes do not fill the declared frame"}
        if reader.overrun do
            fail InvalidFormatError{"DTS packet is truncated"}

        Memory.set(&.predictionHistory, 0, #sizeof(.predictionHistory))
        for channel in channels
        {
            for band in subbandCount[channel]
            {
                for sample in 4 do
                    .predictionHistory[channel, band, sample] = subbands[channel, band, subbandPosition - 4 + sample]
            }
        }

        .synthesize(destination, &header, &subbands)
        .synthesizeLfe(destination, &header, &lfeSamples, lfePosition)
        return header
    }
}

impl IPacketCodec for Codec
{
    mtd impl canDecode(encoding: SoundFileEncoding)->bool => encoding == .Dts

    mtd impl initialize(_: const [..] u8, sampleRateHz, channels: u32) fail
    {
        if not sampleRateHz or not channels or channels > MaxChannels do
            fail BadParameterError{"DTS audio needs one to six channels and a non-zero sample rate"}
        .sampleRate = sampleRateHz
        .channels   = channels
        .resetState()
    }

    mtd impl reset() => .resetState()

    mtd impl decodePacket(destination: [*] void, destinationSize: u64, packet: const [..] u8)->u64 fail
    {
        let info     = try frameInfo(packet)
        let required = cast(u64, info.frames) * .channels * #sizeof(s16)
        if info.frameBytes > packet.count do
            fail InvalidFormatError{"DTS packet size does not match its core-frame header"}
        if destinationSize < required do
            fail BadParameterError{"DTS destination buffer is too small"}

        // A DTS-HD access unit starts with a complete backward-compatible core. This decoder
        // consumes that core and leaves the extension substream to codecs that implement it.
        discard try .decodeFrame(cast([*] s16, destination), packet[0 until info.frameBytes])
        return required
    }
}

#init
{
    registerPacketCodec'Codec()
}
