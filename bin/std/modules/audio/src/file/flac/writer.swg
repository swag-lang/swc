//! Format: Native FLAC PCM16 streaming writer.
//! Supported: One to eight channels, independent variable-block frames, constant, verbatim, and first-order fixed subframes.
//! Role: This file writes bounded PCM blocks and keeps every flushed file prefix playable.
//
#global namespace Flac
#global export

using Core, Core.Errors

private const WriterBlockFrames = 4_096'u32
private const WriterMaxSamples = (1'u64 << 36) - 1
private const WriterPrologueBytes = 58'u64

// Writes signed PCM16 frames to a native FLAC file without retaining the recording.
//
// The writer buffers at most 4096 sample frames and one encoded frame. A flush completes a
// partial frame, updates STREAMINFO (including its PCM MD5), and makes the prefix playable.
// Input samples are interleaved and owned by the caller. Each channel chooses constant,
// first-order fixed/Rice, or verbatim coding for each block.
#[Swag.NoCopy]
struct Writer
{
    private
    {
        sink:          ByteSink
        pending:       Array's16
        frame:         Array'u8
        checksum:      Hash.Md5
        bitCount:      u64
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
        if not channels or channels > 8 or not sampleRate or sampleRate > 0xFFFFF do
            fail BadParameterError{"FLAC writer needs one to eight channels and a representable sample rate"}

        with var result: #returntype
        {
            .sink       = try ByteSink.createFile(fileName)
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
        var source = try ByteSource.openFile(fileName)
        let originalSize = source.size()
        if originalSize < WriterPrologueBytes do
            fail InvalidFormatError{"FLAC resume header is truncated"}
        var header: [WriterPrologueBytes] u8
        try source.readExact(Swag.makeSlice(&header[0], header.count))
        let prologue = Swag.makeSlice(&header[0], header.count)
        if Memory.compare(prologue.buffer, "fLaC".buffer, 4) != 0 or
           prologue[4] != 0 or prologue[5] != 0 or prologue[6] != 0 or prologue[7] != 34 or
           prologue[42] != 0x82 or prologue[43] != 0 or prologue[44] != 0 or prologue[45] != 12 or
           Memory.compare(prologue.buffer + 46, "SWAG".buffer, 4) != 0 do
            fail InvalidFormatError{"FLAC resume needs this writer's metadata checkpoint"}

        var codec: Codec
        try codec.readStreamInfo(prologue[until 42])
        if codec.info.bitsPerSample != 16 or codec.info.maxBlockSize > WriterBlockFrames or
           codec.info.channels > 8 or not codec.info.sampleRate do
            fail UnsupportedFormatError{"FLAC resume needs a PCM16 recording from this writer"}
        let channelCount = codec.info.channels
        let sampleRateHz = codec.info.sampleRate
        let declared = codec.info.totalSamples
        var expectedDigest: [16] u8
        Memory.copy(&expectedDigest[0], prologue.buffer + 26, 16)
        try source.seek(50)
        let committedEnd = try source.readBigEndian'u64()
        if committedEnd < WriterPrologueBytes or committedEnd > originalSize or
           (declared == 0 and committedEnd != WriterPrologueBytes) do
            fail InvalidFormatError{"FLAC resume checkpoint is outside the committed prefix"}

        let decoder: IPacketCodec = &codec
        try decoder.initialize(prologue[until 42], sampleRateHz, channelCount)
        var pcm: Array'u8
        pcm.resize(cast(u64, WriterBlockFrames) * channelCount * 2)
        var checksum: Hash.Md5
        checksum.reset()
        var frames = 0'u64
        var offset = WriterPrologueBytes
        var minBlock = Swag.U16.Max
        var maxBlock = 0'u16
        var minFrameBytes = Swag.U32.Max
        var maxFrameBytes = 0'u32
        while offset < committedEnd
        {
            let next = try findFrameEnd(&source, offset, committedEnd)
            let length = next - offset
            if length < 10 or length > WriterBlockFrames * channelCount * 2 + 64 do
                fail InvalidFormatError{"FLAC resume frame size is outside the writer's limit"}
            try source.seek(offset)
            let packet = (try source.peek(length))[until length]
            let trailer = (cast(u16, packet[length - 2]) << 8) | packet[length - 1]
            if frameCrc16(packet[until length - 2]) != trailer or readSampleNumber(packet) != frames do
                fail InvalidFormatError{"FLAC resume frame checksum or sample position differs"}
            let block = try packetFrameCount(packet)
            if block > WriterBlockFrames or block > WriterMaxSamples - frames do
                fail InvalidFormatError{"FLAC resume frame count exceeds the writer's limit"}
            let decoded = try decoder.decodePacket(pcm.storage(), pcm.count, packet)
            if decoded != cast(u64, block) * channelCount * 2 do
                fail InvalidFormatError{"FLAC resume frame decoded an unexpected sample count"}
            if Core.BIG_ENDIAN
            {
                let samples = cast(const [*] s16, pcm.storage())
                for index in decoded / 2
                {
                    var little = Math.nativeToLittleEndian(samples[index])
                    checksum.update(Swag.makeSlice(cast(const [*] u8, &little), 2))
                }
            }
            else do
                checksum.update(pcm.toSlice()[until decoded])
            frames += block
            minBlock = cast(u16, Math.min(cast(u32, minBlock), block))
            maxBlock = cast(u16, Math.max(cast(u32, maxBlock), block))
            minFrameBytes = Math.min(minFrameBytes, cast(u32, length))
            maxFrameBytes = Math.max(maxFrameBytes, cast(u32, length))
            offset = next
        }

        if frames != declared do
            fail InvalidFormatError{"FLAC resume sample count differs from STREAMINFO"}
        if frames
        {
            let minimumFrame = (cast(u32, header[12]) << 16) | (cast(u32, header[13]) << 8) | header[14]
            let maximumFrame = (cast(u32, header[15]) << 16) | (cast(u32, header[16]) << 8) | header[17]
            if codec.info.minBlockSize != minBlock or codec.info.maxBlockSize != maxBlock or
               minimumFrame != minFrameBytes or maximumFrame != maxFrameBytes do
                fail InvalidFormatError{"FLAC resume frame bounds differ from STREAMINFO"}
        }
        var finalHash = checksum
        let actualDigest = finalHash.finalize()
        if frames and Memory.compare(&actualDigest[0], &expectedDigest[0], 16) != 0 do
            fail InvalidFormatError{"FLAC resume PCM checksum differs from STREAMINFO"}
        source.close()

        scope
        {
            var file = try File.open(fileName, .Open, .ReadWrite, .Zero)
            if try file.size() != originalSize do
                fail InvalidFormatError{"FLAC file changed during resume"}
            try file.resize(committedEnd)
            file.close()
        }

        var result: #returntype
        result.sink          = try ByteSink.openAppendFile(fileName)
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
        if .isEnded do
            fail BadParameterError{"cannot append to an ended FLAC writer"}
        if samples.count % .channels do
            fail BadParameterError{"FLAC samples must contain complete interleaved frames"}
        let added = samples.count / .channels
        if added > WriterMaxSamples - .frameCount do
            fail OverflowError{"FLAC sample count exceeds its 36-bit limit"}
        if not added do
            return

        if Core.BIG_ENDIAN
        {
            for sample in samples
            {
                var little = Math.nativeToLittleEndian(sample)
                .checksum.update(Swag.makeSlice(cast(const [*] u8, &little), 2))
            }
        }
        else do
            .checksum.update(Swag.makeSlice(cast(const [*] u8, samples.buffer), samples.count * 2))

        var offset = 0'u64
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
        if .isEnded do
            fail BadParameterError{"cannot flush an ended FLAC writer"}
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
        if .isEnded do
            return
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
        var width = 1'u32
        if lead >= 0xFE do width = 7
        elif lead >= 0xFC do width = 6
        elif lead >= 0xF8 do width = 5
        elif lead >= 0xF0 do width = 4
        elif lead >= 0xE0 do width = 3
        elif lead >= 0xC0 do width = 2
        elif lead >= 0x80 do return Swag.U64.Max
        if width == 1 do
            return lead
        if packet.count < 4 + width do
            return Swag.U64.Max
        var result = cast(u64, lead & (0x7F >> width))
        for index in 1 until width
        {
            let next = packet[4 + index]
            if next & 0xC0 != 0x80 do
                return Swag.U64.Max
            result = (result << 6) | (next & 0x3F)
        }
        return result
    }

    mtd writePrologue() fail
    {
        try .sink.writeText("fLaC")
        try .sink.writeByte(0) // STREAMINFO precedes the writer's checkpoint block.
        try .sink.writeByte(0)
        try .sink.writeByte(0)
        try .sink.writeByte(34)
        try .sink.writeBigEndian(16'u16)
        try .sink.writeBigEndian(cast(u16, WriterBlockFrames))
        for 6 do
            try .sink.writeByte(0)
        let description = (cast(u64, .sampleRate) << 44) |
                          (cast(u64, .channels - 1) << 41) |
                          (15'u64 << 36)
        try .sink.writeBigEndian(description)
        for 16 do
            try .sink.writeByte(0)
        try .sink.writeByte(0x82) // APPLICATION is the last metadata block.
        try .sink.writeByte(0)
        try .sink.writeByte(0)
        try .sink.writeByte(12)
        try .sink.writeText("SWAG")
        try .sink.writeBigEndian(WriterPrologueBytes)
    }

    mtd patchStreamInfo() fail
    {
        var sizes: [10] u8
        let minimum = .minBlock ? .minBlock : 16'u16
        let maximum = .maxBlock ? .maxBlock : cast(u16, WriterBlockFrames)
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
                                                  (15'u64 << 36) | .writtenFrames)
        try .sink.patch(18, Swag.makeSlice(cast(const [*] u8, &description), 8))
        var hash = .checksum
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
        .bitCount = 0

        .writeByte(0xFF)
        .writeByte(0xF9) // Variable-block stream, with an absolute sample number.
        .writeByte(0x70) // Explicit 16-bit block size, sample rate from STREAMINFO.
        .writeByte(cast(u8, (.channels - 1) << 4))
        .writeSampleNumber(.writtenFrames)
        .writeByte(cast(u8, (count - 1) >> 8))
        .writeByte(cast(u8, (count - 1) & 0xFF))
        let headerChecksum = crc8(.frame.toSlice())
        .writeByte(headerChecksum)

        for channel in .channels do
            .writeChannel(cast(u64, channel), count)
        .alignByte()
        let checksum = frameCrc16(.frame.toSlice())
        .writeByte(cast(u8, checksum >> 8))
        .writeByte(cast(u8, checksum & 0xFF))

        let bytes = cast(u32, .frame.count)
        try .sink.write(.frame.toSlice())
        .writtenFrames += count
        .minBlock       = .minBlock ? cast(u16, Math.min(.minBlock, count)) : cast(u16, count)
        .maxBlock       = cast(u16, Math.max(.maxBlock, count))
        .minFrameBytes  = .minFrameBytes ? Math.min(.minFrameBytes, bytes) : bytes
        .maxFrameBytes  = Math.max(.maxFrameBytes, bytes)
    }

    mtd writeSampleNumber(number: u64)
    {
        var width = 1'u32
        if number >= 0x800 do width = 3
        elif number >= 0x80 do width = 2
        if number >= 0x1_0000 do width = 4
        if number >= 0x20_0000 do width = 5
        if number >= 0x400_0000 do width = 6
        if number >= 0x8000_0000 do width = 7
        if width == 1
        {
            .writeByte(cast(u8, number))
            return
        }
        let marker = cast(u8, (0xFF'u32 << (8 - width)) & 0xFF)
        .writeByte(marker | cast(u8, number >> (6 * (width - 1))))
        for index in 1 until width
        {
            let shift = 6 * (width - index - 1)
            .writeByte(0x80 | cast(u8, (number >> shift) & 0x3F))
        }
    }

    mtd writeChannel(channel: u64, count: u32)
    {
        let first = cast(s32, .pending[channel])
        var constant = true
        for index in 1 until count where .pending[cast(u64, index) * .channels + channel] != first do
            constant = false
        if constant
        {
            .writeBits(0, 8)
            .writeBits(cast #bit(u16, cast(s16, first)), 16)
            return
        }

        let verbatimBits = cast(u64, count) * 16 + 8
        var bestBits = verbatimBits
        var bestRice = 15'u32
        for rice in 15
        {
            var bits = 8'u64 + 16 + 6 + 4
            var previous = first
            for index in 1 until count
            {
                let current = cast(s32, .pending[cast(u64, index) * .channels + channel])
                let delta = current - previous
                let folded = delta < 0 ? cast(u32, -delta) * 2 - 1 : cast(u32, delta) * 2
                bits += (folded >> rice) + 1 + rice
                previous = current
            }
            if bits < bestBits
            {
                bestBits = bits
                bestRice = rice
            }
        }

        if bestRice == 15
        {
            .writeBits(0x02, 8)
            for index in count do
                .writeBits(cast #bit(u16, .pending[cast(u64, index) * .channels + channel]), 16)
            return
        }

        .writeBits(0x12, 8) // First-order fixed predictor.
        .writeBits(cast #bit(u16, cast(s16, first)), 16)
        .writeBits(0, 6) // Rice method 0 and one partition.
        .writeBits(bestRice, 4)
        var previous = first
        for index in 1 until count
        {
            let current = cast(s32, .pending[cast(u64, index) * .channels + channel])
            let delta = current - previous
            let folded = delta < 0 ? cast(u32, -delta) * 2 - 1 : cast(u32, delta) * 2
            .writeUnary(folded >> bestRice)
            .writeBits(folded, bestRice)
            previous = current
        }
    }

    mtd writeUnary(zeros: u32)
    {
        for zeros do
            .writeBits(0, 1)
        .writeBits(1, 1)
    }

    mtd writeByte(value: u8)
    {
        Swag.assert(not (.bitCount & 7))
        .frame.add(value)
        .bitCount += 8
    }

    mtd writeBits(value: u32, count: u32)
    {
        for index in count
        {
            if .bitCount == .frame.count * 8 do
                .frame.add(0'u8)
            let shift = count - index - 1
            .frame[.bitCount >> 3] |= cast(u8, ((value >> shift) & 1) << (7 - cast(u32, .bitCount & 7)))
            .bitCount += 1
        }
    }

    mtd alignByte()
    {
        if .bitCount & 7 do
            .bitCount = (.bitCount + 7) & ~7'u64
    }

    func crc8(bytes: const [..] u8)->u8
    {
        var checksum = 0'u8
        for byte in bytes
        {
            checksum ^= byte
            for 8 do
                checksum = checksum & 0x80 ? cast(u8, ((cast(u32, checksum) << 1) ^ 7) & 0xFF) :
                                            cast(u8, (cast(u32, checksum) << 1) & 0xFF)
        }
        return checksum
    }

}
