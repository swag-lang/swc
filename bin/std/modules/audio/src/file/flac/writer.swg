//! Format: Native FLAC PCM16 streaming writer.
//! Supported: One to eight channels, variable-block frames, constant, verbatim, and fixed subframes of orders one through four.
//! Role: This file writes bounded PCM blocks and keeps every flushed file prefix playable.
//
#global namespace Flac
#global export

using Core, Core.Errors

private const WriterMinBlockFrames = 16_u16
private const WriterBlockFrames    = 4_096_u32
private const WriterMaxSamples     = (1_u64 << 36) - 1
private const WriterPrologueBytes  = 58_u64

private const WriterMaxPartitionOrder = 4_u32
private const WriterMaxPartitions     = 1_u32 << WriterMaxPartitionOrder

private struct WriterRicePartition
{
    bits:      u64
    parameter: u32
}

private struct WriterFixedStats
{
    total:         [2] u32
    partitionSums: [2, WriterMaxPartitions] u32
}

private struct WriterRicePlan
{
    bits:       u64
    partitions: [WriterMaxPartitions] WriterRicePartition
}

private enum WriterStereoMode
{
    Independent
    Duplicated
    Constant
}

// Writes signed PCM16 frames to a native FLAC file without retaining the recording.
//
// The writer buffers at most 4096 sample frames and one encoded frame. A flush completes a
// partial frame, updates STREAMINFO (including its PCM MD5), and makes the prefix playable.
// Frames with duplicated stereo use mid/side coding.
// Input samples are interleaved and owned by the caller. Each channel chooses constant,
// fixed prediction of orders one to four with partitioned Rice coding, or verbatim coding.
// Shared trailing zero bits let a channel use a narrower width.
#[Swag.NoCopy]
struct Writer
{
    private
    {
        sink:          ByteSink
        pending:       Array!{s16}
        frame:         Array!{u8}
        residuals:     Array!{u32}
        checksum:      Hash.Md5
        bitBuffer:     u64
        bufferedBits:  u32
        frameCount:    u64
        writtenFrames: u64
        sampleRate:    u32
        channels:      u16
        minBlock:      u16
        maxBlock:      u16
        minFrameBytes: u32
        maxFrameBytes: u32
        isEnded:       bool
    }
}

impl Writer
{
    // Creates a native PCM16 FLAC file, replacing any file at `fileName`.
    //
    // `channels` must be between one and eight and `sampleRate` must fit FLAC's 20-bit field.
    // A newly created file has no audio frame; add samples and flush or end it to make it playable.
    func create(fileName: string, channels: u16, sampleRate: u32)->Writer fail
    {
        if not channels or channels > 8 or not sampleRate or sampleRate > 0xFFFFF
        {
            fail BadParameterError{"FLAC writer needs one to eight channels and a representable sample rate"}
        }

        with var result: #returntype
        {
            .sink       = try ByteSink.createFile(fileName, .Read)
            .channels   = channels
            .sampleRate = sampleRate
            .checksum.reset()
        }

        try result.writePrologue()
        try result.sink.flush()
        return result
    }

    // Continues a stopped file after its last flushed sample frame.
    //
    // The writer's APPLICATION checkpoint marks the complete prefix. Its frames and PCM MD5
    // are validated with bounded buffers before any trailing bytes are removed. A partial or
    // unflushed tail is discarded. Resuming scans and decodes the committed prefix once so the
    // streaming checksum can continue; an I/O failure after truncation may leave that prefix.
    func resume(fileName: string)->Writer fail
    {
        var source       = try ByteSource.openFile(fileName)
        let originalSize = source.size()
        if originalSize < WriterPrologueBytes
        {
            fail InvalidFormatError{"FLAC resume header is truncated"}
        }

        var header: [WriterPrologueBytes] u8
        try source.readExact(Swag.makeSlice(&header[0], header.count))
        let prologue = Swag.makeSlice(&header[0], header.count)
        if Memory.compare(prologue.buffer, "fLaC".buffer, 4) != 0 or
           prologue[4] != 0 or
           prologue[5] != 0 or
           prologue[6] != 0 or
           prologue[7] != 34 or
           prologue[42] != 0x82 or
           prologue[43] != 0 or
           prologue[44] != 0 or
           prologue[45] != 12 or
           Memory.compare(prologue.buffer + 46, "SWAG".buffer, 4) != 0
        {
            fail InvalidFormatError{"FLAC resume needs this writer's metadata checkpoint"}
        }

        var codec: Codec
        try codec.readStreamInfo(prologue[until 42])
        if codec.info.bitsPerSample != 16 or
           codec.info.maxBlockSize > WriterBlockFrames or
           codec.info.channels > 8 or
           not codec.info.sampleRate
        {
            fail UnsupportedFormatError{"FLAC resume needs a PCM16 recording from this writer"}
        }

        let channelCount = codec.info.channels
        let sampleRateHz = codec.info.sampleRate
        let declared     = codec.info.totalSamples
        let frameLimit   = cast(u64, WriterBlockFrames) * channelCount * 2 + 64
        var expectedDigest: [16] u8
        Memory.copy(&expectedDigest[0], prologue.buffer + 26, 16)
        try source.seek(50)
        let committedEnd = try source.readBigEndian!{u64}()
        if committedEnd < WriterPrologueBytes or
           committedEnd > originalSize or
           (declared == 0 and committedEnd != WriterPrologueBytes)
        {
            fail InvalidFormatError{"FLAC resume checkpoint is outside the committed prefix"}
        }

        let decoder: IPacketCodec = &codec
        try decoder.initialize(prologue[until 42], sampleRateHz, channelCount)
        var pcm: Array!{u8}
        pcm.resize(cast(u64, WriterBlockFrames) * channelCount * 2)
        var checksum: Hash.Md5
        checksum.reset()
        var frames        = 0_u64
        var offset        = WriterPrologueBytes
        var minBlock      = Swag.U16.Max
        var maxBlock      = 0_u16
        var minFrameBytes = Swag.U32.Max
        var maxFrameBytes = 0_u32
        while offset < committedEnd
        {
            let next   = try findFrameEnd(&source, offset, committedEnd, frameLimit)
            let length = next - offset
            if length < 10 or length > frameLimit
            {
                fail InvalidFormatError{"FLAC resume frame size is outside the writer's limit"}
            }

            try source.seek(offset)
            let packet  = (try source.peek(length))[until length]
            let trailer = (cast(u16, packet[length - 2]) << 8) | packet[length - 1]
            if frameCrc16(packet[until length - 2]) != trailer or readSampleNumber(packet) != frames
            {
                fail InvalidFormatError{"FLAC resume frame checksum or sample position differs"}
            }

            let block = try packetFrameCount(packet)
            if block > WriterBlockFrames or block > WriterMaxSamples - frames
            {
                fail InvalidFormatError{"FLAC resume frame count exceeds the writer's limit"}
            }

            let decoded = try decoder.decodePacket(pcm.storage(), pcm.count, packet)
            if decoded != cast(u64, block) * channelCount * 2
            {
                fail InvalidFormatError{"FLAC resume frame decoded an unexpected sample count"}
            }

            if Core.BIG_ENDIAN
            {
                let samples = cast(const [*] s16, pcm.storage())
                for index in decoded / 2
                {
                    var little = Math.nativeToLittleEndian(samples[index])
                    checksum.update(Swag.makeSlice(cast(const [*] u8, &little), 2))
                }
            }
            else
            {
                checksum.update(pcm.toSlice()[until decoded])
            }

            frames        += block
            minBlock      = cast(u16, Math.min(cast(u32, minBlock), block))
            maxBlock      = cast(u16, Math.max(cast(u32, maxBlock), block))
            minFrameBytes = Math.min(minFrameBytes, cast(u32, length))
            maxFrameBytes = Math.max(maxFrameBytes, cast(u32, length))
            offset        = next
        }

        if frames != declared
        {
            fail InvalidFormatError{"FLAC resume sample count differs from STREAMINFO"}
        }

        if frames
        {
            let minimumFrame = (cast(u32, header[12]) << 16) | (cast(u32, header[13]) << 8) | header[14]
            let maximumFrame = (cast(u32, header[15]) << 16) | (cast(u32, header[16]) << 8) | header[17]

            // Older writers recorded short committed blocks directly in STREAMINFO.
            let exactBounds      = codec.info.minBlockSize == minBlock and codec.info.maxBlockSize == maxBlock
            let normalizedBounds = codec.info.minBlockSize == Math.max(minBlock, WriterMinBlockFrames) and
                                   codec.info.maxBlockSize == Math.max(maxBlock, WriterMinBlockFrames)
            if (not exactBounds and not normalizedBounds) or
               minimumFrame != minFrameBytes or
               maximumFrame != maxFrameBytes
            {
                fail InvalidFormatError{"FLAC resume frame bounds differ from STREAMINFO"}
            }
        }

        var finalHash    = checksum
        let actualDigest = finalHash.finalize()
        if frames and Memory.compare(&actualDigest[0], &expectedDigest[0], 16) != 0
        {
            fail InvalidFormatError{"FLAC resume PCM checksum differs from STREAMINFO"}
        }

        source.close()

        scope
        {
            var file = try File.open(fileName, .Open, .ReadWrite, .Zero)
            if try file.size() != originalSize
            {
                fail InvalidFormatError{"FLAC file changed during resume"}
            }

            try file.resize(committedEnd)
            file.close()
        }

        var result: #returntype
        result.sink          = try ByteSink.openAppendFile(fileName, .Read)
        result.checksum      = checksum
        result.sampleRate    = sampleRateHz
        result.channels      = cast(u16, channelCount)
        result.frameCount    = frames
        result.writtenFrames = frames
        result.minBlock      = frames ? minBlock : 0
        result.maxBlock      = maxBlock
        result.minFrameBytes = frames ? minFrameBytes : 0
        result.maxFrameBytes = maxFrameBytes
        return result
    }

    // Returns the submitted sample-frame count, including a partial buffered block.
    mtd const sampleFrameCount()->u64 => .frameCount

    // Returns the accepted file byte count, excluding a partial unencoded block.
    mtd const writtenByteCount()->u64 => .sink.position()

    // Adds complete interleaved PCM16 sample frames.
    //
    // Input is copied or encoded before returning. The 36-bit FLAC sample count is checked
    // before appending; a malformed input leaves the file and writer state unchanged.
    mtd addFrames(samples: const [..] s16) fail
    {
        if .isEnded
        {
            fail BadParameterError{"cannot append to an ended FLAC writer"}
        }

        if samples.count % .channels
        {
            fail BadParameterError{"FLAC samples must contain complete interleaved frames"}
        }

        let added = samples.count / .channels
        if added > WriterMaxSamples - .frameCount
        {
            fail OverflowError{"FLAC sample count exceeds its 36-bit limit"}
        }

        if not added
        {
            return
        }

        if Core.BIG_ENDIAN
        {
            for sample in samples
            {
                var little = Math.nativeToLittleEndian(sample)
                .checksum.update(Swag.makeSlice(cast(const [*] u8, &little), 2))
            }
        }
        else
        {
            .checksum.update(Swag.makeSlice(cast(const [*] u8, samples.buffer), samples.count * 2))
        }

        var offset = 0_u64
        while offset < samples.count
        {
            let room = cast(u64, WriterBlockFrames) * .channels - .pending.count
            let take = Math.min(room, samples.count - offset)
            .pending.add(samples[offset until offset + take])
            offset += take
            if .pending.count == cast(u64, WriterBlockFrames) * .channels
            {
                try .writeFrame()
                .pending.clear()
            }
        }

        .frameCount += added
    }

    // Completes a partial frame and updates a playable file prefix.
    //
    // The current sample count and PCM checksum are written into STREAMINFO. A subsequent
    // `addFrames` starts a new independent frame and can therefore resume after this prefix.
    mtd flush() fail
    {
        if .isEnded
        {
            fail BadParameterError{"cannot flush an ended FLAC writer"}
        }

        if .pending.count
        {
            try .writeFrame()
            .pending.clear()
        }

        try .patchStreamInfo()
        try .sink.flush()
    }

    // Finishes the file and closes its sink; repeated calls do nothing.
    mtd end() fail
    {
        if .isEnded
        {
            return
        }

        try .flush()
        try .sink.close()
        .isEnded = true
    }
}

private impl Writer
{
    func readSampleNumber(packet: const [..] u8)->u64
    {
        let lead = packet[4]
        if lead == 0xFF
        {
            return Swag.U64.Max
        }

        var width = 1_u32
        if lead == 0xFE
        {
            width = 7
        }
        else if lead >= 0xFC
        {
            width = 6
        }
        else if lead >= 0xF8
        {
            width = 5
        }
        else if lead >= 0xF0
        {
            width = 4
        }
        else if lead >= 0xE0
        {
            width = 3
        }
        else if lead >= 0xC0
        {
            width = 2
        }
        else if lead >= 0x80
        {
            return Swag.U64.Max
        }

        if width == 1
        {
            return lead
        }

        if packet.count < 4 + width
        {
            return Swag.U64.Max
        }

        var result = cast(u64, lead & (0x7F >> width))
        for index in 1 until width
        {
            let next = packet[4 + index]
            if next & 0xC0 != 0x80
            {
                return Swag.U64.Max
            }

            result = (result << 6) | (next & 0x3F)
        }

        return result
    }

    mtd writePrologue() fail
    {
        try .sink.writeText("fLaC")
        try .sink.writeByte(0)     // STREAMINFO precedes the writer's checkpoint block.
        try .sink.writeByte(0)
        try .sink.writeByte(0)
        try .sink.writeByte(34)
        try .sink.writeBigEndian(WriterMinBlockFrames)
        try .sink.writeBigEndian(cast(u16, WriterBlockFrames))
        for 6
        {
            try .sink.writeByte(0)
        }

        let description = (cast(u64, .sampleRate) << 44) |
                          (cast(u64, .channels - 1) << 41) |
                          (15_u64 << 36)
        try .sink.writeBigEndian(description)
        for 16
        {
            try .sink.writeByte(0)
        }

        try .sink.writeByte(0x82)     // APPLICATION is the last metadata block.
        try .sink.writeByte(0)
        try .sink.writeByte(0)
        try .sink.writeByte(12)
        try .sink.writeText("SWAG")
        try .sink.writeBigEndian(WriterPrologueBytes)
    }

    mtd patchStreamInfo() fail
    {
        var sizes: [10] u8

        // STREAMINFO requires block-size bounds of at least sixteen samples.
        // The frame headers retain the exact sizes of short flushes.
        let minimum = Math.max(.minBlock, WriterMinBlockFrames)
        let maximum = .maxBlock ? Math.max(.maxBlock, WriterMinBlockFrames) : cast(u16, WriterBlockFrames)
        sizes[0] = cast(u8, minimum >> 8)
        sizes[1] = cast(u8, minimum & 0xFF)
        sizes[2] = cast(u8, maximum >> 8)
        sizes[3] = cast(u8, maximum & 0xFF)
        sizes[4] = cast(u8, .minFrameBytes >> 16)
        sizes[5] = cast(u8, (.minFrameBytes >> 8) & 0xFF)
        sizes[6] = cast(u8, .minFrameBytes & 0xFF)
        sizes[7] = cast(u8, .maxFrameBytes >> 16)
        sizes[8] = cast(u8, (.maxFrameBytes >> 8) & 0xFF)
        sizes[9] = cast(u8, .maxFrameBytes & 0xFF)
        try .sink.patch(8, sizes)

        var description = Math.nativeToBigEndian((cast(u64, .sampleRate) << 44) |
                                                 (cast(u64, .channels - 1) << 41) |
                                                 (15_u64 << 36) | .writtenFrames)
        try .sink.patch(18, Swag.makeSlice(cast(const [*] u8, &description), 8))
        var hash   = .checksum
        let digest = hash.finalize()
        try .sink.patch(26, digest)
        var checkpoint = Math.nativeToBigEndian(.sink.position())
        try .sink.patch(50, Swag.makeSlice(cast(const [*] u8, &checkpoint), 8))
    }

    mtd writeFrame() fail
    {
        let count = cast(u32, .pending.count / .channels)
        Swag.assert(count and count <= WriterBlockFrames)
        .frame.clear()
        .bitBuffer    = 0
        .bufferedBits = 0

        let stereo     = .channels == 2 ? stereoMode(.pending.storage(), count) : WriterStereoMode.Independent
        let assignment = stereo == .Duplicated ? 10_u16 : .channels - 1
        .writeByte(0xFF)
        .writeByte(0xF9)     // Variable-block stream, with an absolute sample number.
        .writeByte(0x70)     // Explicit 16-bit block size, sample rate from STREAMINFO.
        .writeByte(cast(u8, assignment << 4))
        .writeSampleNumber(.writtenFrames)
        .writeByte(cast(u8, (count - 1) >> 8))
        .writeByte(cast(u8, (count - 1) & 0xFF))
        let headerChecksum = crc8(.frame.toSlice())
        .writeByte(headerChecksum)

        switch stereo
        {
        case .Duplicated:

            // Equal channels have the original signal as their mid channel and a zero side.
            .writeChannel(0, count)
            .writeBits(0, 8)
            .writeBits(0, 17)

        case .Constant:
            let sample = cast #bit(u16, .pending[0])
            for 2
            {
                .writeBits(0, 8)
                .writeBits(sample, 16)
            }

        default:
            for channel in .channels
            {
                .writeChannel(cast(u64, channel), count)
            }
        }

        .alignByte()
        let checksum = frameCrc16(.frame.toSlice())
        .writeByte(cast(u8, checksum >> 8))
        .writeByte(cast(u8, checksum & 0xFF))

        let bytes = cast(u32, .frame.count)
        try .sink.write(.frame.toSlice())
        .writtenFrames += count
        .minBlock      = .minBlock ? cast(u16, Math.min(.minBlock, count)) : cast(u16, count)
        .maxBlock      = cast(u16, Math.max(.maxBlock, count))
        .minFrameBytes = .minFrameBytes ? Math.min(.minFrameBytes, bytes) : bytes
        .maxFrameBytes = Math.max(.maxFrameBytes, bytes)
    }

    // Stereo frames with two copies of a varying signal need to code that signal once.
    func stereoMode(samples: const [*] s16, count: u32)->WriterStereoMode
    {
        let firstSample = samples[0]
        let finalPair   = (count - 1) * 2
        if firstSample != samples[1] or samples[finalPair] != samples[finalPair + 1]
        {
            return .Independent
        }

        let bits      = cast(u32, cast #bit(u16, firstSample))
        let reference = Math.Simd.splat(bits * 0x1_0001)
        let low       = Math.Simd.splat(0xFFFF_u32)
        let pairs     = cast(const [*] u32, samples)
        var variation = Math.Simd.splat(0_u32)
        var index     = 0_u32
        while count - index >= 4
        {
            let stereo = Math.Simd.load(pairs + index)
            if Math.Simd.bitmask((stereo & low) == (stereo >> 16)) != 0b1111
            {
                return .Independent
            }

            variation |= stereo ^ reference
            index     += 4
        }

        var varied = Math.Simd.bitwiseOr(variation) != 0
        for tail in index until count
        {
            let value = samples[tail * 2]
            if value != samples[tail * 2 + 1]
            {
                return .Independent
            }

            varied = varied or value != firstSample
        }

        return varied ? .Duplicated : .Constant
    }

    mtd writeSampleNumber(number: u64)
    {
        var width = 1_u32
        if number >= 0x800
        {
            width = 3
        }
        else if number >= 0x80
        {
            width = 2
        }

        if number >= 0x1_0000
        {
            width = 4
        }

        if number >= 0x20_0000
        {
            width = 5
        }

        if number >= 0x400_0000
        {
            width = 6
        }

        if number >= 0x8000_0000
        {
            width = 7
        }

        if width == 1
        {
            .writeByte(cast(u8, number))
            return
        }

        let marker = cast(u8, (0xFF_u32 << (8 - width)) & 0xFF)
        .writeByte(marker | cast(u8, number >> (6 * (width - 1))))
        for index in 1 until width
        {
            let shift = 6 * (width - index - 1)
            .writeByte(0x80 | cast(u8, (number >> shift) & 0x3F))
        }
    }

    mtd writeChannel(channel: u64, count: u32)
    {
        let samples = .pending.storage() + channel
        let stride  = cast(u64, .channels)
        let first   = cast(s32, samples[0])
        var changed = 1_u32
        while changed < count and samples[cast(u64, changed) * stride] == first
        {
            changed += 1
        }

        if changed == count
        {
            .writeBits(0, 8)
            .writeBits(cast #bit(u16, cast(s16, first)), 16)
            return
        }

        // Most full-depth channels contain an odd sample near an endpoint.
        var used = cast #bit(u16, samples[0]) |
                   cast #bit(u16, samples[cast(u64, changed) * stride]) |
                   cast #bit(u16, samples[cast(u64, count - 1) * stride])
        if not (used & 1)
        {
            let last = samples + cast(u64, count - 1) * stride
            var next = samples + cast(u64, changed) * stride
            while next < last
            {
                next += stride
                used |= cast #bit(u16, next[0])
                if used & 1
                {
                    break
                }
            }

            let wasted = cast(u32, Swag.trailingZeros(used))
            if wasted
            {
                .writeTrimmedChannel(samples, stride, count, wasted)
                return
            }
        }

        .writePredictedChannel!{false}(.pending.storage(), channel, stride, count, 0)
    }

    #[Swag.NoInline]
    mtd writeTrimmedChannel(samples: const [*] s16, stride: u64, count, wasted: u32)
    {
        var plane: [WriterBlockFrames] s16
        var cursor = samples
        for frame in count
        {
            plane[frame] = cursor[0] >> wasted
            cursor       += stride
        }

        .writePredictedChannel!{true}(cast(const [*] s16, &plane[0]), 0, 1, count, wasted)
    }

    #[Swag.Inline]
    mtd(Trimmed: bool) writeSubframeHeader(kind, wasted: u32)
    {
        #static if Trimmed
        {
            .writeBits(kind | 1, 8)
            .writeBits(1, wasted)
        }
        else
        {
            discard wasted
            .writeBits(kind, 8)
        }
    }

    mtd(Trimmed: bool) writePredictedChannel(input: const [*] s16, channel, stride: u64, count, wasted: u32)
    {
        let samples = input + channel
        let depth   = Trimmed ? 16 - wasted : 16_u32
        let header  = Trimmed ? 14_u64 + wasted : 14_u64
        .residuals.growResize(3 * count)
        let residual1      = .residuals.storage()
        let residual2      = residual1 + count
        let depthBudget    = count >= 64 ? 31 - cast(u32, Swag.leadingZeros(count >> 3)) : 0
        let availableOrder = count >= 64 ? Math.min(WriterMaxPartitionOrder, depthBudget, cast(u32, Swag.trailingZeros(count))) : 0
        var sums           = fillFixedPairs(input, channel, stride, count, availableOrder, residual1, residual2)

        let verbatimBits    = cast(u64, count) * depth + 8 + wasted
        let firstResiduals  = Swag.makeSlice(residual1, count - 1)
        let secondResiduals = Swag.makeSlice(residual2, count - 2)
        var order           = 1_u32
        var chosen          = firstResiduals
        var bestBits        = verbatimBits
        var bestRice        = 15_u32
        var plannedOrder    = 0_u32
        var partitionPlan: WriterRicePlan
        let estimateNeeded  = availableOrder or count >= 256
        let firstEstimate   = estimateNeeded ? estimatePartitions(&sums.partitionSums[0, 0], count, 1, availableOrder, header + depth) : verbatimBits
        let secondEstimate  = estimateNeeded ? estimatePartitions(&sums.partitionSums[1, 0], count, 2, availableOrder, header + 2 * depth) : verbatimBits
        let estimatedBase   = Math.min(firstEstimate, secondEstimate)
        let pilotDepth      = Math.min(availableOrder, 3_u32)
        if estimatedBase < verbatimBits and (count >> pilotDepth) >= 256
        {
            let predictor = chooseHigherOrder(secondResiduals, count, pilotDepth, estimatedBase, header, depth)
            if predictor
            {
                let destination = residual2 + count
                let higher      = Swag.makeSlice(destination, count - predictor)
                let parts       = predictor == 3 ? fillHigherOrder!{3}(secondResiduals, count, availableOrder, destination) :
                                  fillHigherOrder!{4}(secondResiduals, count, availableOrder, destination)
                if availableOrder
                {
                    let plan = planRicePartitions(higher, &parts[0], count, predictor, availableOrder, bestBits, header + depth * predictor)
                    if plan.bits < bestBits
                    {
                        bestBits      = plan.bits
                        order         = predictor
                        chosen        = higher
                        plannedOrder  = availableOrder
                        partitionPlan = plan
                    }
                }

                var foldedSum = 0_u32
                for part in 1_u32 << availableOrder
                {
                    foldedSum += parts[part]
                }

                let overhead = header + 4 + depth * predictor
                if minimumRiceCost(foldedSum, count - predictor) + overhead < bestBits
                {
                    let plan = selectRice(higher, foldedSum, overhead, bestBits)
                    if plan.rice < 15
                    {
                        bestBits     = plan.bits
                        bestRice     = plan.rice
                        order        = predictor
                        chosen       = higher
                        plannedOrder = 0
                    }
                }
            }
        }

        if availableOrder and estimatedBase < verbatimBits
        {
            let predictor = firstEstimate <= secondEstimate ? 1_u32 : 2
            let residuals = predictor == 1 ? firstResiduals : secondResiduals
            let sumByPart = &sums.partitionSums[predictor - 1, 0]
            if bestBits == verbatimBits or minimumPartitionCost(sumByPart, count, predictor, availableOrder, header + depth * predictor) < bestBits
            {
                let plan = planRicePartitions(residuals, sumByPart, count, predictor, availableOrder, bestBits, header + depth * predictor)
                if plan.bits < bestBits
                {
                    bestBits      = plan.bits
                    order         = predictor
                    chosen        = residuals
                    plannedOrder  = availableOrder
                    partitionPlan = plan
                }
            }
        }

        if minimumRiceCost(sums.total[0], count - 1) + header + 4 + depth < bestBits
        {
            let plan = selectRice(firstResiduals, sums.total[0], header + 4 + depth, bestBits)
            if plan.rice < 15
            {
                bestBits     = plan.bits
                bestRice     = plan.rice
                order        = 1
                chosen       = firstResiduals
                plannedOrder = 0
            }
        }

        if count > 2 and minimumRiceCost(sums.total[1], count - 2) + header + 4 + 2 * depth < bestBits
        {
            let plan = selectRice(secondResiduals, sums.total[1], header + 4 + 2 * depth, bestBits)
            if plan.rice < 15
            {
                bestBits     = plan.bits
                bestRice     = plan.rice
                order        = 2
                chosen       = secondResiduals
                plannedOrder = 0
            }
        }

        if not plannedOrder and bestRice == 15
        {
            .writeSubframeHeader!{Trimmed}(0x02, wasted)
            #static if Trimmed
            {
                // Trimmed channels are passed in as contiguous sample planes.
                .writeNarrowVerbatim(samples, count, depth)
            }
            else
            {
                if not (.bufferedBits & 7)
                {
                    .alignByte()
                    let output = cast([*] u16, .frame.emplaceAddress(count * 2))
                    for index in count
                    {
                        let sample = cast #bit(u16, samples[cast(u64, index) * stride])
                        output[index] = Math.nativeToBigEndian(sample)
                    }
                }
                else
                {
                    for index in count
                    {
                        .writeBits(cast #bit(u16, samples[cast(u64, index) * stride]), depth)
                    }
                }
            }

            return
        }

        .writeSubframeHeader!{Trimmed}(0x10 + 2 * order, wasted)
        for warmup in order
        {
            .writeBits(cast #bit(u16, samples[cast(u64, warmup) * stride]), depth)
        }

        .writeBits(plannedOrder, 6)     // Rice method 0 and a four-bit partition order.
        if not plannedOrder
        {
            .writeBits(bestRice, 4)
            .writeRiceRun(chosen, bestRice, bestBits - (header + 4 + depth * order))
            return
        }

        let size  = count >> plannedOrder
        var start = 0_u32
        for part in 1_u32 << plannedOrder
        {
            let end  = (part + 1) * size - order
            let code = partitionPlan.partitions[part]
            .writeBits(code.parameter, 4)
            .writeRiceRun(chosen[start until end], code.parameter, code.bits)
            start = end
        }
    }

    // Fold both fixed predictors together. Mono and stereo use contiguous loads.
    // Other layouts copy one channel into a bounded sample plane first.
    func fillFixedPairs(input: const [*] s16, channel, stride: u64, count, partitionOrder: u32, first, second: [*] u32)->WriterFixedStats
    {
        var plane: [WriterBlockFrames] s16
        var inputBase    = input
        var inputStride  = stride
        var inputChannel = channel
        if stride > 2
        {
            var cursor  = input + channel
            let compact = cast([*] s16, &plane[0])
            for frame in count
            {
                compact[frame] = cursor[0]
                cursor         += stride
            }

            inputBase    = cast(const [*] s16, compact)
            inputStride  = 1
            inputChannel = 0
        }

        let source = inputBase + inputChannel

        // The second predictor starts after the same first difference as the first.
        let initial = cast(s32, source[inputStride]) - cast(s32, source[0])
        first[0] = foldDelta(initial)
        var result: WriterFixedStats
        var frame         = 2_u32
        var last          = Math.Simd.splat(source[inputStride])
        var delta         = Math.Simd.splat(initial)
        let partitionSize = count >> partitionOrder
        for part in 1_u32 << partitionOrder
        {
            let end     = (part + 1) * partitionSize
            var totals1 = Math.Simd.splat(0_u32)
            var totals2 = Math.Simd.splat(0_u32)
            while end - frame >= 8
            {
                let samples = inputBase + cast(u64, frame) * inputStride
                var current = Math.Simd.load(samples)
                if inputStride == 2
                {
                    let lower  = cast #bit(Math.Simd.U16x8, current)
                    let upper  = cast #bit(Math.Simd.U16x8, Math.Simd.load(samples + 8))
                    let column = inputChannel ? Math.Simd.deinterleaveOdd(lower, upper) : Math.Simd.deinterleaveEven(lower, upper)
                    current = cast #bit(Math.Simd.S16x8, column)
                }

                let predecessor = Swag.vecAlign(last, current, 14)
                let low1        = Math.Simd.widenLow(current) - Math.Simd.widenLow(predecessor)
                let high1       = Math.Simd.widenHigh(current) - Math.Simd.widenHigh(predecessor)
                let low2        = low1 - Swag.vecAlign(delta, low1, 12)
                let high2       = high1 - Swag.vecAlign(low1, high1, 12)
                let foldedLow1  = foldDeltaVector(low1)
                let foldedHigh1 = foldDeltaVector(high1)
                let foldedLow2  = foldDeltaVector(low2)
                let foldedHigh2 = foldDeltaVector(high2)
                Math.Simd.store(first + frame - 1, foldedLow1)
                Math.Simd.store(first + frame + 3, foldedHigh1)
                Math.Simd.store(second + frame - 2, foldedLow2)
                Math.Simd.store(second + frame + 2, foldedHigh2)
                totals1 += foldedLow1 + foldedHigh1
                totals2 += foldedLow2 + foldedHigh2
                last    = current
                delta   = high1
                frame   += 8
            }

            var sum1 = Math.Simd.sum(totals1)
            var sum2 = Math.Simd.sum(totals2)
            if not part
            {
                sum1 += first[0]
            }

            var previous      = cast(s32, source[cast(u64, (frame - 1)) * inputStride])
            var previousDelta = previous - cast(s32, source[cast(u64, (frame - 2)) * inputStride])
            for at in frame until end
            {
                let current = cast(s32, source[cast(u64, at) * inputStride])
                let delta   = current - previous
                let folded1 = foldDelta(delta)
                let folded2 = foldDelta(delta - previousDelta)
                first[at - 1]  = folded1
                second[at - 2] = folded2
                sum1           += folded1
                sum2           += folded2
                previous       = current
                previousDelta  = delta
            }

            if frame != end
            {
                last  = Math.Simd.splat(cast(s16, previous))
                delta = Math.Simd.splat(previousDelta)
                frame = end
            }

            result.partitionSums[0, part] = sum1
            result.partitionSums[1, part] = sum2
            result.total[0]               += sum1
            result.total[1]               += sum2
        }

        return result
    }

    #[Swag.Inline]
    func foldDeltaVector(value: Math.Simd.S32x4)->Math.Simd.U32x4
        => (cast #bit(Math.Simd.U32x4, value) << 1) ^ cast #bit(Math.Simd.U32x4, value >> 31)

    // Scores the exact size of a single Rice partition, including fixed warmup.
    func selectRice(residuals: const [..] u32, foldedSum: u32, overhead, limitBits: u64)->{bits: u64, rice: u32}
    {
        let count = cast(u32, residuals.count)
        let range = riceRange(foldedSum, count)
        var first = range.start
        while first < range.stop and overhead + riceLowerBound(foldedSum, count, first) >= limitBits
        {
            first += 1
        }

        if first == range.stop
        {
            return {limitBits, 15_u32}
        }

        // The other candidate quotients are right shifts of the same first quotient.
        var sums0 = Math.Simd.splat(0_u32)
        var sums1 = Math.Simd.splat(0_u32)
        var sums2 = Math.Simd.splat(0_u32)
        let bound = count & ~3_u32
        let data  = residuals.buffer
        var index = 0_u32
        while index < bound
        {
            let quotient = Math.Simd.load(data + index) >> first
            sums0 += quotient
            sums1 += quotient >> 1
            sums2 += quotient >> 2
            index += 4
        }

        var sums = [Math.Simd.sum(sums0), Math.Simd.sum(sums1), Math.Simd.sum(sums2)]
        for tail in index until count
        {
            let quotient = residuals[tail] >> first
            sums[0] += quotient
            sums[1] += quotient >> 1
            sums[2] += quotient >> 2
        }

        var bestBits = limitBits
        var bestRice = 15_u32
        for rice in first until range.stop
        {
            let bits = overhead + cast(u64, count) * (1 + rice) + sums[rice - first]
            if bits < bestBits
            {
                bestBits = bits
                bestRice = rice
            }
        }

        return {bestBits, bestRice}
    }

    #[Swag.Inline]
    func foldDelta(delta: s32)->u32 => (cast #bit(u32, delta) << 1) ^ cast #bit(u32, delta >> 31)

    func riceRange(foldedSum, count: u32)->{start: u32, stop: u32}
    {
        let mean  = foldedSum / count
        let b     = mean ? 31 - cast(u32, Swag.leadingZeros(mean)) : 0
        let start = b ? Math.min(b - 1, 14_u32) : 0
        return {start, Math.min(b + 2, 15_u32)}
    }

    // The exact sum of quotients is nonnegative. Rounding N terms can also lose at most N - 1.
    func riceLowerBound(foldedSum, count, parameter: u32)->u64
        => cast(u64, count) * parameter + Math.max(count, 1 + (foldedSum >> parameter))

    func minimumRiceCost(foldedSum, count: u32)->u64
    {
        let range = riceRange(foldedSum, count)
        var best  = Swag.U64.Max
        for rice in range.start until range.stop
        {
            best = Math.min(best, riceLowerBound(foldedSum, count, rice))
        }

        return best
    }

    // A lower bound allows a measured higher-order plan to skip the standard partition scan.
    func minimumPartitionCost(sums: const [*] u32, count, order, partitionOrder: u32, overhead: u64)->u64
    {
        let size = count >> partitionOrder
        var bits = overhead
        for part in 1_u32 << partitionOrder
        {
            bits += 4 + minimumRiceCost(sums[part], part ? size : size - order)
        }

        return bits
    }

    // The estimated size only decides which partitioned predictor to measure.
    func estimatePartitions(sums: const [*] u32, count, order, partitionOrder: u32, overhead: u64)->u64
    {
        let size = count >> partitionOrder
        var bits = overhead
        for part in 1_u32 << partitionOrder
        {
            let samples  = part ? size : size - order
            let mean     = sums[part] / samples
            let rice     = mean ? Math.min(14_u32, 31 - cast(u32, Swag.leadingZeros(mean))) : 0
            let quotient = (sums[part] >> rice)
            bits += 4 + cast(u64, samples) * (1 + rice) + (Math.max(quotient, samples / 2) - samples / 2)
        }

        return bits
    }

    func planRicePartitions(residuals: const [..] u32, sums: const [*] u32, count, order, partitionOrder: u32, limit, overhead: u64)->WriterRicePlan
    {
        var plan: WriterRicePlan
        plan.bits = overhead
        let size  = count >> partitionOrder
        let parts = 1_u32 << partitionOrder

        var start = 0_u32
        for part in parts
        {
            let end    = (part + 1) * size - order
            let choice = selectRice(residuals[start until end], sums[part], 4, limit - plan.bits)
            if choice.rice == 15
            {
                plan.bits = limit
                return plan
            }

            plan.bits += choice.bits
            plan.partitions[part] = WriterRicePartition{choice.bits - 4, choice.rice}
            start     = end
        }

        return plan
    }

    // Estimate the extra predictors from sampled differences and compare with the measured incumbent.
    func chooseHigherOrder(second: const [..] u32, count, partitionOrder: u32, incumbent, header: u64, depth: u32)->u32
    {
        let size  = count >> partitionOrder
        let parts = 1_u32 << partitionOrder
        var costs = [(header + depth * 3 + 4 * parts) << 8,
                     (header + depth * 4 + 4 * parts) << 8]
        for part in parts
        {
            let end     = (part + 1) * size
            var frame   = Math.max(4_u32, part * size)
            let length  = end - frame
            var sums: [2] u32
            var samples = 0_u32
            while frame < end
            {
                let current = unfoldDelta(second[frame - 2])
                let prev    = unfoldDelta(second[frame - 3])
                let earlier = unfoldDelta(second[frame - 4])
                sums[0] += foldDelta(current - prev)
                sums[1] += foldDelta(current - 2 * prev + earlier)
                samples += 1
                frame   += 61
            }

            for lane in 2
            {
                let mean     = sums[lane] / samples
                let rice     = mean ? Math.min(14_u32, 31 - cast(u32, Swag.leadingZeros(mean))) : 0
                let quotient = (mean << 8) >> rice
                let rate     = ((1 + rice) << 8) + Math.max(quotient, 128_u32) - 128
                costs[lane] += cast(u64, rate) * length
            }
        }

        let better = Math.min(costs[0], costs[1])
        if better + (cast(u64, count) * 64) >= incumbent << 8
        {
            return 0
        }

        return costs[0] <= costs[1] ? 3 : 4
    }

    #[Swag.Inline]
    func unfoldDelta(value: u32)->s32 => cast(s32, value >> 1) ^ -cast(s32, value & 1)

    #[Swag.Inline]
    func unfoldDeltaVector(value: Math.Simd.U32x4)->Math.Simd.S32x4
    {
        let sign = cast #bit(Math.Simd.S32x4, value & Math.Simd.splat(1_u32))
        return cast #bit(Math.Simd.S32x4, value >> 1) ^ (Math.Simd.splat(0_s32) - sign)
    }

    // Third and fourth differences are the first and second differences of order two.
    func(Order: u32) fillHigherOrder(second: const [..] u32, count, partitionOrder: u32, target: [*] u32)->[WriterMaxPartitions] u32
    {
        let size  = count >> partitionOrder
        let input = second.buffer
        var sums: [WriterMaxPartitions] u32
        var start = 0_u32
        for part in 1_u32 << partitionOrder
        {
            let end    = (part + 1) * size - Order
            var totals = Math.Simd.splat(0_u32)
            const EarlierSamples = Order - 2
            let olderValue = unfoldDelta(second[start])
            let newerValue = unfoldDelta(second[start + EarlierSamples - 1])
            var history    = cast(Math.Simd.S32x4, [olderValue, olderValue, olderValue, newerValue])
            while end - start >= 4
            {
                let current    = unfoldDeltaVector(Math.Simd.load(input + start + EarlierSamples))
                let previous   = Swag.vecAlign(history, current, 12)
                var difference = current - previous
                #static if Order == 4
                {
                    difference -= previous - Swag.vecAlign(history, current, 8)
                }

                history = current
                let folded = foldDeltaVector(difference)
                Math.Simd.store(target + start, folded)
                totals += folded
                start  += 4
            }

            var sum = Math.Simd.sum(totals)
            for at in start until end
            {
                let older      = unfoldDelta(second[at])
                let newer      = unfoldDelta(second[at + 1])
                var difference = newer - older
                #static if Order == 4
                {
                    difference = unfoldDelta(second[at + 2]) - newer - difference
                }

                let folded = foldDelta(difference)
                target[at] = folded
                sum        += folded
            }

            sums[part] = sum
            start      = end
        }

        return sums
    }

    // The exact Rice cost lets us allocate all complete output words once.
    mtd writeRiceRun(residuals: const [..] u32, parameter: u32, encodedBits: u64)
    {
        let wordCount = (encodedBits + .bufferedBits) >> 5
        let output    = cast([*] u32, .frame.emplaceAddress(cast(u32, (wordCount + 1) * 4)))
        output[wordCount] = 0
        let marker     = 1_u64 << parameter
        let mask       = marker - 1
        let suffixBits = 1 + parameter
        var queued     = .bitBuffer
        var buffered   = .bufferedBits
        var cursor     = 0_u64
        var index      = 0_u64
        while index < residuals.count
        {
            let value = residuals[index]
            let zeros = value >> parameter
            var width = zeros + suffixBits
            var bits  = marker | (cast(u64, value) & mask)
            index += 1
            if index < residuals.count
            {
                let next      = residuals[index]
                let nextWidth = (next >> parameter) + suffixBits
                if width + nextWidth <= 32
                {
                    bits  = (bits << nextWidth) | marker | (cast(u64, next) & mask)
                    width += nextWidth
                    index += 1
                }
            }

            if width > 32
            {
                let room = 32 - buffered
                if zeros >= room
                {
                    output[cursor] = Math.nativeToBigEndian(cast #wrap(u32, queued << room))
                    cursor         += 1
                    let remaining = zeros - room
                    let clear     = remaining >> 5
                    if clear
                    {
                        Memory.clear(output + cursor, cast(u64, clear) * 4)
                        cursor += clear
                    }

                    queued   = 0
                    buffered = remaining & 31
                }
                else
                {
                    queued   <<= zeros
                    buffered += zeros
                }

                width = suffixBits
            }

            queued = (queued << width) | bits
            let used = buffered + width
            buffered = used & 31

            // An incomplete word may be overwritten until it can be counted.
            output[cursor] = Math.nativeToBigEndian(cast #wrap(u32, queued >> buffered))
            cursor         += used >> 5
        }

        Swag.assert(cursor == wordCount)
        .frame.count  -= 4
        .bitBuffer    = queued
        .bufferedBits = buffered
    }

    mtd writeByte(value: u8)
    {
        Swag.assert(not .bufferedBits)
        .frame.add(value)
    }

    // Write pairs of narrow samples with one word reservation for the whole subframe.
    mtd writeNarrowVerbatim(samples: const [*] s16, count, depth: u32)
    {
        var index = .writeAlignedVerbatim(samples, count, depth)
        if index == count
        {
            return
        }

        let wordCount  = (.bufferedBits + (count - index) * depth) >> 5
        let wordOutput = cast([*] u32, .frame.emplaceAddress((wordCount + 1) * 4))
        wordOutput[wordCount] = 0
        let width    = depth * 2
        let mask     = (1_u64 << depth) - 1
        var queued   = .bitBuffer
        var buffered = .bufferedBits
        var cursor   = 0_u64
        while count - index >= 2
        {
            let first = cast(u64, cast #bit(u16, samples[index])) & mask
            let last  = cast(u64, cast #bit(u16, samples[index + 1])) & mask
            queued = (queued << width) | (first << depth) | last
            let used = buffered + width
            buffered = used & 31
            wordOutput[cursor] = Math.nativeToBigEndian(cast #wrap(u32, queued >> buffered))
            cursor   += used >> 5
            index    += 2
        }

        if index < count
        {
            let bits = cast(u64, cast #bit(u16, samples[index])) & mask
            queued = (queued << depth) | bits
            let used = buffered + depth
            buffered = used & 31
            wordOutput[cursor] = Math.nativeToBigEndian(cast #wrap(u32, queued >> buffered))
            cursor   += used >> 5
        }

        Swag.assert(cursor == wordCount)
        .frame.count  -= 4
        .bitBuffer    = queued
        .bufferedBits = buffered
    }

    mtd writeAlignedVerbatim(samples: const [*] s16, count, depth: u32)->u32
    {
        var index = 0_u32
        #static if not Core.BIG_ENDIAN
        {
            if depth == 8 and not (.bufferedBits & 7)
            {
                let groups = count / 16
                if groups
                {
                    .alignByte()
                    let byteOutput = cast([*] s8, .frame.emplaceAddress(groups * 16))
                    for group in groups
                    {
                        let input = samples + group * 16
                        Math.Simd.store(byteOutput + group * 16, Math.Simd.packSigned(Math.Simd.load(input), Math.Simd.load(input + 8)))
                    }

                    index = groups * 16
                }
            }
            else if depth == 12
            {
                if (.bufferedBits & 7) == 4
                {
                    .writeBits(cast #bit(u16, samples[0]), 12)
                    index = 1
                }

                let groups = (count - index) / 8
                if groups and not (.bufferedBits & 7)
                {
                    .alignByte()
                    index += .writeVerbatim12Vectors(samples + index, groups)
                }
            }
        }

        return index
    }

    // A pair of 12-bit samples occupies three bytes in the bitstream.
    mtd writeVerbatim12Vectors(samples: const [*] s16, groups: u32)->u32
    {
        const FirstWords  = cast(Math.Simd.U16x8, [0xFFFF_u16, 0, 0xFFFF, 0, 0xFFFF, 0, 0xFFFF, 0])
        const LastWords   = cast(Math.Simd.U16x8, [0_u16, 0x0FFF, 0, 0x0FFF, 0, 0x0FFF, 0, 0x0FFF])
        const MainBytes   = cast(Math.Simd.U8x16, [1_u8, 0, 2, 5, 4, 6, 9, 8, 10, 13, 12, 14, 0x80, 0x80, 0x80, 0x80])
        const LastNibbles = cast(Math.Simd.U8x16, [0x80_u8, 3, 0x80, 0x80, 7, 0x80, 0x80, 11, 0x80, 0x80, 15, 0x80, 0x80, 0x80, 0x80, 0x80])
        let output = .frame.emplaceAddress(groups * 12 + 4)
        for group in groups
        {
            let samples16 = cast #bit(Math.Simd.U16x8, Math.Simd.load(samples + group * 8))
            let words     = ((samples16 & FirstWords) << 4) | (samples16 & LastWords)
            let bytes     = cast #bit(Math.Simd.U8x16, words)
            let packed    = Math.Simd.shuffle(bytes, MainBytes) | Math.Simd.shuffle(bytes, LastNibbles)
            Math.Simd.store(output + group * 12, packed)
        }

        // The last vector writes four byte slots past its data.
        .frame.count -= 4
        return groups * 8
    }

    #[Swag.Inline]
    mtd writeBits(value: u32, count: u32)
    {
        let bits   = cast(u64, value) & ((1_u64 << count) - 1)
        let queued = (.bitBuffer << count) | bits
        var used   = .bufferedBits + count
        if used >= 32
        {
            used -= 32
            let word   = Math.nativeToBigEndian(cast #wrap(u32, queued >> used))
            let output = cast([*] u32, .frame.emplaceAddress(4))
            output[0] = word
        }

        .bitBuffer    = queued
        .bufferedBits = used
    }

    mtd alignByte()
    {
        let padding = (8 - (.bufferedBits & 7)) & 7
        let padded  = .bitBuffer << padding
        let bytes   = (.bufferedBits + padding) >> 3
        let output  = .frame.emplaceAddress(bytes)
        for index in bytes
        {
            output[index] = cast #wrap(u8, padded >> ((bytes - index - 1) * 8))
        }

        .bitBuffer    = 0
        .bufferedBits = 0
    }

    func crc8(bytes: const [..] u8)->u8
    {
        var checksum = 0_u8
        for byte in bytes
        {
            checksum ^= byte
            for 8
            {
                checksum = checksum & 0x80 ? cast(u8, ((cast(u32, checksum) << 1) ^ 7) & 0xFF) :
                           cast(u8, (cast(u32, checksum) << 1) & 0xFF)
            }
        }

        return checksum
    }
}
