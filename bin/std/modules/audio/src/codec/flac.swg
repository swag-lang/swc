#global namespace Flac

using Core, Core.Errors

// The format reserves four bits for the partition order, so a block never splits further.
private const MaxPartitionOrder = 15'u32

// A linear predictor reads at most thirty-two previous samples, which also bounds the warmup.
private const MaxLpcOrder = 32'u32

// FLAC carries at most eight channels, and the escape codes that mean "raw bits" are the
// largest value each Rice parameter field can hold.
private const MaxChannels = 8'u32
private const RiceEscape = 15'u32
private const Rice2Escape = 31'u32

// Sample rates the frame header names by index rather than by value.
private const CodedRates: [16] u32 = [0, 88200, 176400, 192000, 8000, 16000, 22050, 24000, 32000, 44100, 48000, 96000, 0, 0, 0, 0]

// Sample widths the frame header names by index; the two zeros are "take it from the stream
// information" and a reserved code the parser rejects.
private const CodedDepths: [8] u32 = [0, 8, 12, 0, 16, 20, 24, 32]

// Reads the bits of a FLAC frame, most significant bit first.
//
// Reading past the end returns zeros and records the overrun rather than failing on the spot,
// so the residual loops carry no failure path; the decoder checks [[overran]] once per frame.
private struct BitReader
{
    data:    #null const [*] u8
    size:    u64
    bitPos:  u64
    overran: bool
}

private impl BitReader
{
    func create(payload: const [..] u8)->BitReader => {@dataof(payload), @countof(payload), 0, false}

    mtd const bitsLeft()->u64 => .bitPos >= .size * 8 ? 0 : .size * 8 - .bitPos

    // Reads `count` bits as an unsigned value. `count` is at most 32.
    mtd read(count: u32)->u32
    {
        if !count do
            return 0
        if .bitPos + count > .size * 8
        {
            .overran = true
            .bitPos  = .size * 8
            return 0
        }

        var result = 0'u32
        var need   = count
        while need
        {
            let bitOffset = cast(u32) (.bitPos & 7)
            let available = 8 - bitOffset
            let take      = Math.min(available, need)
            let value     = (cast(u32) .data![.bitPos >> 3] >> (available - take)) & ((1'u32 << take) - 1)
            result  = (result << take) | value
            .bitPos += take
            need    -= take
        }

        return result
    }

    // Reads `count` bits as a two's-complement value. `count` is at most 32.
    mtd readSigned(count: u32)->s32
    {
        let value = .read(count)
        if count == 32 do
            return cast(s32) value

        // A negative value is `value - 2^count`. Subtracting the sign bit twice reaches it without
        // ever leaving the range of either type: the usual `(value ^ sign) - sign` is one unsigned
        // subtraction below zero, which is a fault here rather than a wrap.
        let sign = 1'u32 << (count - 1)
        if !(value & sign) do
            return cast(s32) value
        return cast(s32) (value - sign) - cast(s32) sign
    }

    // Counts the zero bits before the next set bit, and consumes that set bit.
    //
    // This is the quotient of every Rice code in the stream, so it skips whole zero bytes
    // instead of walking bits.
    mtd unary()->u32
    {
        var zeros = 0'u32
        while .bitPos < .size * 8
        {
            let bitOffset = cast(u32) (.bitPos & 7)
            let masked    = cast(u32) .data![.bitPos >> 3] & (0xFF'u32 >> bitOffset)
            if masked
            {
                let highest = 31 - cast(u32) @bitcountlz(masked)
                let found   = 7 - highest
                zeros   += found - bitOffset
                .bitPos += cast(u64) (found - bitOffset) + 1
                return zeros
            }

            zeros   += 8 - bitOffset
            .bitPos += 8 - bitOffset
        }

        .overran = true
        return zeros
    }

    // Advances to the next byte boundary.
    mtd alignByte()
    {
        .bitPos = (.bitPos + 7) & ~7'u64
    }
}

// The stream-wide properties a FLAC frame header may omit.
//
// A frame is allowed to name its own sample rate and sample width, but it is also allowed to
// say "the one the stream declared", which is why the decoder keeps these even though the
// container already reported them.
private struct StreamInfo
{
    minBlockSize:  u32
    maxBlockSize:  u32
    sampleRate:    u32
    channels:      u32
    bitsPerSample: u32
    totalSamples:  u64
}

// Everything one frame header says about the block that follows it.
private struct FrameHeader
{
    blockSize:         u32
    sampleRate:        u32
    channelAssignment: u32
    channels:          u32
    bitsPerSample:     u32
}

// Decodes the FLAC frames a container indexes, one complete frame per call.
//
// Every frame is independently decodable, so the codec keeps no state between calls beyond the
// per-channel scratch it reuses. Output is interleaved 16-bit PCM: a stream wider than that is
// reduced on the way out, which is what the mixer accepts.
// Size of the stream information block, clause 8.2.
private const StreamInfoSize = 34'u64

private struct Codec
{
    // Every registered codec starts with the registry's own header: a voice destroys one through
    // this, reading back the concrete type and the allocator the instance was made with.
    using base: Audio.Codec

    info:     StreamInfo
    channels: [MaxChannels] Array's32
    residual: Array's32
    capacity: u32
}

private impl Codec
{
    // Reads the "fLaC" marker and the stream information block a container carries.
    mtd readStreamInfo(config: const [..] u8) fail
    {
        if @countof(config) < 4 do
            fail InvalidFormatError{"FLAC stream information is truncated"}

        // A container may hand over the whole metadata prologue, or the stream information
        // block alone. Both spellings are in use, so the marker is optional.
        var offset = 0'u64
        if config[0] == 'f' and config[1] == 'L' and config[2] == 'a' and config[3] == 'C' do
            offset = 4

        if @countof(config) < offset + 4 do
            fail InvalidFormatError{"FLAC stream information is truncated"}

        // A metadata block header may precede the payload: skip its type and length. Its type
        // alone does not identify it — a stream information block whose smallest block is under
        // 256 samples starts with a zero byte too — so the length it states has to agree.
        let headerLength = (cast(u64) config[offset + 1] << 16) | (cast(u64) config[offset + 2] << 8) | cast(u64) config[offset + 3]
        if (config[offset] & 0x7F) == 0 and headerLength == StreamInfoSize do
            offset += 4

        if @countof(config) < offset + StreamInfoSize do
            fail InvalidFormatError{"FLAC stream information block is truncated"}

        var reader = BitReader.create(config[offset until offset + StreamInfoSize])

        with &.info
        {
            .minBlockSize  = reader.read(16)
            .maxBlockSize  = reader.read(16)
            discard reader.read(24)
            discard reader.read(24)
            .sampleRate    = reader.read(20)
            .channels      = reader.read(3) + 1
            .bitsPerSample = reader.read(5) + 1
            .totalSamples  = (cast(u64) reader.read(4) << 32) | cast(u64) reader.read(32)
        }

        if !.info.sampleRate do
            fail InvalidFormatError{"FLAC stream declares no sample rate"}
        if .info.channels > MaxChannels do
            fail UnsupportedFormatError{"FLAC stream declares more than eight channels"}
        if .info.bitsPerSample < 4 or .info.bitsPerSample > 32 do
            fail UnsupportedFormatError{"FLAC sample width is outside the supported range"}
        if !.info.maxBlockSize do
            fail InvalidFormatError{"FLAC stream declares no maximum block size"}
    }

    // Grows the per-channel scratch so one block of `blockSize` samples fits.
    mtd reserveBlock(blockSize: u32)
    {
        if blockSize <= .capacity do
            return
        for index in MaxChannels do
            .channels[index].resize(cast(u64) blockSize)
        .residual.resize(cast(u64) blockSize)
        .capacity = blockSize
    }

    // Reads one frame header, which is what decides the shape of everything after it.
    mtd readFrameHeader(reader: *BitReader)->FrameHeader fail
    {
        if reader.read(14) != 0x3FFE do
            fail InvalidFormatError{"FLAC frame has no sync code"}
        if reader.read(1) do
            fail InvalidFormatError{"FLAC frame sets the reserved header bit"}

        let variableBlocking = reader.read(1) != 0
        let blockSizeCode    = reader.read(4)
        let sampleRateCode   = reader.read(4)

        var result: retval
        result.channelAssignment = reader.read(4)
        let depthCode            = reader.read(3)
        if reader.read(1) do
            fail InvalidFormatError{"FLAC frame sets the reserved header bit"}

        // The frame or sample number is a UTF-8-shaped integer whose leading byte states its
        // length. Its value only matters when seeking, which the container index already does.
        let lead = reader.read(8)
        var extraBytes = 0'u32
        if lead >= 0xFE do
            extraBytes = 6
        elif lead >= 0xFC do
            extraBytes = 5
        elif lead >= 0xF8 do
            extraBytes = 4
        elif lead >= 0xF0 do
            extraBytes = 3
        elif lead >= 0xE0 do
            extraBytes = 2
        elif lead >= 0xC0 do
            extraBytes = 1
        elif lead >= 0x80 do
            fail InvalidFormatError{"FLAC frame number is malformed"}
        discard variableBlocking
        for extraBytes do
            discard reader.read(8)

        switch blockSizeCode
        {
        case 0:
            fail InvalidFormatError{"FLAC frame uses the reserved block size code"}
        case 1:
            result.blockSize = 192
        case 2, 3, 4, 5:
            result.blockSize = 576'u32 << (blockSizeCode - 2)
        case 6:
            result.blockSize = reader.read(8) + 1
        case 7:
            result.blockSize = reader.read(16) + 1
        default:
            result.blockSize = 256'u32 << (blockSizeCode - 8)
        }

        switch sampleRateCode
        {
        case 0:
            result.sampleRate = .info.sampleRate
        case 12:
            result.sampleRate = reader.read(8) * 1000
        case 13:
            result.sampleRate = reader.read(16)
        case 14:
            result.sampleRate = reader.read(16) * 10
        case 15:
            fail InvalidFormatError{"FLAC frame uses the invalid sample rate code"}
        default:
            result.sampleRate = CodedRates[sampleRateCode]
        }

        result.bitsPerSample = depthCode ? CodedDepths[depthCode] : .info.bitsPerSample
        if !result.bitsPerSample do
            fail InvalidFormatError{"FLAC frame uses the reserved sample width code"}

        if result.channelAssignment < 8 do
            result.channels = result.channelAssignment + 1
        elif result.channelAssignment < 11 do
            result.channels = 2
        else do
            fail InvalidFormatError{"FLAC frame uses a reserved channel assignment"}

        // The header ends with a checksum of itself, which the container index already stands in for.
        discard reader.read(8)
        if reader.overran do
            fail InvalidFormatError{"FLAC frame header is truncated"}
        return result
    }

    // Reads the residual of one subframe into `.residual`, starting after the warmup samples.
    mtd readResidual(reader: *BitReader, blockSize, predictorOrder: u32) fail
    {
        let method = reader.read(2)
        if method > 1 do
            fail InvalidFormatError{"FLAC residual uses a reserved coding method"}

        let partitionOrder = reader.read(4)
        let partitions     = 1'u32 << partitionOrder
        if blockSize % partitions do
            fail InvalidFormatError{"FLAC residual partitioning does not divide the block"}
        let partitionSize = blockSize >> partitionOrder
        if partitionSize < predictorOrder do
            fail InvalidFormatError{"FLAC residual first partition is shorter than the predictor"}

        let paramBits = method ? 5'u32 : 4'u32
        let escape    = method ? Rice2Escape : RiceEscape
        let output    = .residual.buffer!

        var index = predictorOrder
        for partition in partitions
        {
            let end   = partitionSize * (partition + 1)
            let param = reader.read(paramBits)
            if param == escape
            {
                let rawBits = reader.read(5)
                while index < end
                {
                    output[index] = rawBits ? reader.readSigned(rawBits) : 0
                    index += 1
                }
            }
            else
            {
                while index < end
                {
                    let quotient = reader.unary()
                    let value    = (quotient << param) | reader.read(param)

                    // Residuals are zig-zag coded: the low bit is the sign.
                    output[index] = cast(s32) (value >> 1) ^ -cast(s32) (value & 1)
                    index += 1
                }
            }
        }
    }

    // Decodes one subframe of `blockSize` samples at `bitsPerSample` into `target`.
    mtd readSubframe(reader: *BitReader, target: [*] s32, blockSize, bitsPerSample: u32) fail
    {
        if reader.read(1) do
            fail InvalidFormatError{"FLAC subframe sets the reserved leading bit"}

        let kind = reader.read(6)

        // Wasted bits are trailing zeros the encoder removed from every sample of the subframe.
        var wasted = 0'u32
        if reader.read(1)
        {
            wasted = reader.unary() + 1
            if wasted >= bitsPerSample do
                fail InvalidFormatError{"FLAC subframe wastes every bit of its samples"}
        }

        let depth = bitsPerSample - wasted

        if !kind
        {
            let value = reader.readSigned(depth)
            for index in blockSize do
                target[index] = value
        }
        elif kind == 1
        {
            for index in blockSize do
                target[index] = reader.readSigned(depth)
        }
        elif kind >= 8 and kind <= 12
        {
            let order = kind - 8
            if blockSize < order do
                fail InvalidFormatError{"FLAC fixed subframe is shorter than its predictor"}
            for index in order do
                .residual[index] = reader.readSigned(depth)
            try .readResidual(reader, blockSize, order)
            .predictFixed(target, order, blockSize)
        }
        elif kind >= 32
        {
            let order = kind - 31
            if blockSize < order do
                fail InvalidFormatError{"FLAC linear subframe is shorter than its predictor"}
            for index in order do
                .residual[index] = reader.readSigned(depth)

            let precision = reader.read(4) + 1
            if precision == 16 do
                fail InvalidFormatError{"FLAC linear predictor uses the reserved coefficient precision"}
            let shift = reader.readSigned(5)
            if shift < 0 do
                fail InvalidFormatError{"FLAC linear predictor shift is negative"}

            var coefficients: [MaxLpcOrder] s32 = undefined
            for index in order do
                coefficients[index] = reader.readSigned(precision)

            try .readResidual(reader, blockSize, order)
            .predictLinear(target, &coefficients[0], order, blockSize, cast(u32) shift)
        }
        else
        {
            fail InvalidFormatError{"FLAC subframe uses a reserved type"}
        }

        if reader.overran do
            fail InvalidFormatError{"FLAC subframe is truncated"}
        if wasted
        {
            for index in blockSize do
                target[index] <<= wasted
        }
    }

    // Restores the samples of a fixed-predictor subframe from its residual.
    mtd predictFixed(target: [*] s32, order, blockSize: u32)
    {
        let source = .residual.buffer!
        for index in order do
            target[index] = source[index]

        switch order
        {
        case 0:
            for index in blockSize do
                target[index] = source[index]
        case 1:
            for index in order until blockSize do
                target[index] = source[index] + target[index - 1]
        case 2:
            for index in order until blockSize do
                target[index] = source[index] + 2 * target[index - 1] - target[index - 2]
        case 3:
            for index in order until blockSize do
                target[index] = source[index] + 3 * target[index - 1] - 3 * target[index - 2] + target[index - 3]
        default:
            for index in order until blockSize do
                target[index] = source[index] + 4 * target[index - 1] - 6 * target[index - 2] + 4 * target[index - 3] - target[index - 4]
        }
    }

    // Restores the samples of a linear-predictor subframe from its residual.
    //
    // The accumulator is 64-bit because the format allows thirty-two coefficients of fifteen
    // bits each over samples of up to thirty-two bits, which overflows a 32-bit sum long before
    // the shift brings it back into range.
    mtd predictLinear(target: [*] s32, coefficients: const [*] s32, order, blockSize, shift: u32)
    {
        let source = .residual.buffer!
        for index in order do
            target[index] = source[index]

        for index in order until blockSize
        {
            var sum = 0's64
            for tap in order do
                sum += cast(s64) coefficients[tap] * cast(s64) target[index - 1 - tap]
            target[index] = source[index] + cast(s32) (sum >> shift)
        }
    }

    // Undoes the inter-channel decorrelation a stereo frame may use.
    mtd undecorrelate(assignment, blockSize: u32)
    {
        if assignment < 8 do
            return

        let first  = .channels[0].buffer!
        let second = .channels[1].buffer!

        switch assignment
        {
        case 8:
            // Left and side: the second channel holds left minus right.
            for index in blockSize do
                second[index] = first[index] - second[index]
        case 9:
            // Side and right: the first channel holds left minus right.
            for index in blockSize do
                first[index] += second[index]
        default:
            // Mid and side. The mid channel dropped the low bit of the sum, and the side
            // channel is what restores it.
            for index in blockSize
            {
                let side = second[index]
                let mid  = (first[index] << 1) | (side & 1)
                first[index]  = (mid + side) >> 1
                second[index] = (mid - side) >> 1
            }
        }
    }

    // Decodes one complete FLAC frame into the per-channel scratch and reports its shape.
    mtd decodeFrame(packet: const [..] u8)->FrameHeader fail
    {
        var reader = BitReader.create(packet)
        let header = try .readFrameHeader(&reader)
        if header.channels > MaxChannels do
            fail UnsupportedFormatError{"FLAC frame declares more than eight channels"}
        if header.blockSize > 65535 do
            fail InvalidFormatError{"FLAC frame block size is out of range"}
        .reserveBlock(header.blockSize)

        for channel in header.channels
        {
            // In a decorrelated pair, the channel holding the difference needs one more bit
            // than the frame declares to represent its full range.
            var depth = header.bitsPerSample
            if (header.channelAssignment == 8 or header.channelAssignment == 10) and channel == 1 do
                depth += 1
            elif header.channelAssignment == 9 and !channel do
                depth += 1
            try .readSubframe(&reader, .channels[channel].buffer!, header.blockSize, depth)
        }

        .undecorrelate(header.channelAssignment, header.blockSize)
        return header
    }

    // Writes the decoded block as interleaved 16-bit PCM.
    mtd writePcm16(destination: [*] s16, header: FrameHeader)
    {
        let shift = cast(s32) header.bitsPerSample - 16
        var index = 0'u64
        for sample in header.blockSize
        {
            for channel in header.channels
            {
                let value = .channels[channel][sample]
                var scaled = shift > 0 ? value >> cast(u32) shift : value << cast(u32) -shift
                scaled = Math.clamp(scaled, -32768, 32767)
                destination[index] = cast(s16) scaled
                index += 1
            }
        }
    }
}

impl IPacketCodec for Codec
{
    mtd impl canDecode(encoding: SoundFileEncoding)->bool => encoding == .Flac

    mtd impl initialize(config: const [..] u8, sampleRateHz, channels: u32) fail
    {
        try .readStreamInfo(config)
        if .info.sampleRate != sampleRateHz or .info.channels != channels do
            fail InvalidFormatError{"FLAC stream information does not match its container track"}
        .reserveBlock(.info.maxBlockSize)
    }

    mtd impl reset()
    {
    }

    mtd impl decodePacket(destination: [*] void, destinationSize: u64, packet: const [..] u8)->u64 fail
    {
        let header   = try .decodeFrame(packet)
        let produced = cast(u64) header.blockSize * cast(u64) header.channels * #sizeof(s16)
        if destinationSize < produced do
            fail BadParameterError{"FLAC destination buffer is too small"}
        .writePcm16(cast([*] s16) destination, header)
        return produced
    }
}

// Returns the number of sample frames one FLAC frame decodes to.
//
// A container index needs this before any decoding happens, so it reads the block size out of
// the frame header rather than decoding the frame.
internal func packetFrameCount(packet: const [..] u8)->u32 fail
{
    if @countof(packet) < 5 do
        fail InvalidFormatError{"FLAC frame is truncated"}
    if packet[0] != 0xFF or (packet[1] & 0xFC) != 0xF8 do
        fail InvalidFormatError{"FLAC frame has no sync code"}

    let blockSizeCode = cast(u32) (packet[2] >> 4)
    switch blockSizeCode
    {
    case 0:
        fail InvalidFormatError{"FLAC frame uses the reserved block size code"}
    case 1:
        return 192
    case 2, 3, 4, 5:
        return 576'u32 << (blockSizeCode - 2)
    case 6, 7:
        break
    default:
        return 256'u32 << (blockSizeCode - 8)
    }

    // The block size is stated after the frame number, whose leading byte gives its length.
    var reader = BitReader.create(packet)
    discard reader.read(32)

    let lead = reader.read(8)
    var extraBytes = 0'u32
    if lead >= 0xFE do
        extraBytes = 6
    elif lead >= 0xFC do
        extraBytes = 5
    elif lead >= 0xF8 do
        extraBytes = 4
    elif lead >= 0xF0 do
        extraBytes = 3
    elif lead >= 0xE0 do
        extraBytes = 2
    elif lead >= 0xC0 do
        extraBytes = 1
    for extraBytes do
        discard reader.read(8)

    let blockSize = blockSizeCode == 6 ? reader.read(8) + 1 : reader.read(16) + 1
    if reader.overran do
        fail InvalidFormatError{"FLAC frame header is truncated"}
    return blockSize
}

#init
{
    registerPacketCodec'Codec()
}
