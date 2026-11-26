//! Format: FLAC (Free Lossless Audio Codec).
//! Supported: Subset, verbatim, fixed, and linear predictive subframes, every Rice partition order, left/right/mid side stereo, one to eight channels, and four to thirty-two bits a sample.
//! Not supported: Sample widths above sixteen bits keep their range but are reduced to PCM16.
//! Role: This file owns FLAC frame syntax, subframe prediction, residual decoding, and PCM output.
//
#global namespace Flac

using Core, Core.Errors

// The format reserves four bits for the partition order, so a block never splits further.
private const MaxPartitionOrder = 15_u32

// A linear predictor reads at most thirty-two previous samples, which also bounds the warmup.
private const MaxLpcOrder = 32_u32

// FLAC carries at most eight channels, and the escape codes that mean "raw bits" are the
// largest value each Rice parameter field can hold.
private const MaxChannels = 8_u32
private const RiceEscape  = 15_u32
private const Rice2Escape = 31_u32

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
    data:    const [*] u8?
    size:    u64
    bitPos:  u64
    overran: bool
}

private impl BitReader
{
    func create(payload: const [..] u8)->BitReader => BitReader{payload.buffer, payload.count, 0, false}

    mtd const bitsLeft()->u64 => .bitPos >= .size * 8 ? 0 : .size * 8 - .bitPos

    // Reads `count` bits as an unsigned value. `count` is at most 32.
    mtd read(count: u32)->u32
    {
        if not count
        {
            return 0
        }

        if .bitPos + count > .size * 8
        {
            .overran = true
            .bitPos  = .size * 8
            return 0
        }

        var result = 0_u32
        var need   = count
        while need
        {
            let bitOffset = cast(u32, (.bitPos & 7))
            let available = 8 - bitOffset
            let take      = Math.min(available, need)
            let value     = (cast(u32, .data![.bitPos >> 3]) >> (available - take)) & ((1_u32 << take) - 1)
            result  = (result << take) | value
            .bitPos += take
            need    -= take
        }

        return result
    }

    // Reads a two's-complement sample, including the 33-bit side channel of 32-bit stereo FLAC.
    mtd readSigned(count: u32)->s64
    {
        if count > 32
        {
            // FLAC decorrelation can add one bit to a 32-bit sample. Consume the sign bit
            // separately so the remaining 32 bits retain their full range in the reader.
            let sign  = .read(1)
            let lower = .read(32)
            let value = (cast(u64, sign) << 32) | cast(u64, lower)
            if sign
            {
                return cast(s64, value) - (1_s64 << 33)
            }

            return cast(s64, value)
        }

        let value = .read(count)
        if count == 32
        {
            return cast(s64, cast #bit(s32, value))
        }

        // A negative value is `value - 2^count`. Subtracting the sign bit twice reaches it without
        // ever leaving the range of either type: the usual `(value ^ sign) - sign` is one unsigned
        // subtraction below zero, which is a fault here rather than a wrap.
        let sign = 1_u32 << (count - 1)
        if not (value & sign)
        {
            return cast(s64, value)
        }

        return cast(s64, cast(s32, (value - sign))) - cast(s64, sign)
    }

    // Read fixed-width subframe data in groups from each available word.
    mtd(Group: u32) readSignedRun(destination: [*] s64, count, width: u32)
    {
        let source   = unwrap .data
        let limit    = (.size - Math.min(.size, 7)) * 8
        let shift    = 64 - width
        var position = .bitPos
        var index    = 0_u32
        while count - index >= Group and position < limit
        {
            let offset = cast(u32, position & 7)
            let packed = cast(const [*] u64, source + (position >> 3))[0]
            let word   = Math.bigEndianToNative(packed) << offset
            destination[index] = cast #bit(s64, word) >> shift
            #static if Group == 2
            {
                destination[index + 1] = cast #bit(s64, word << width) >> shift
            }

            position += Group * width
            index    += Group
        }

        .bitPos = position
        for tail in index until count
        {
            destination[tail] = .readSigned(width)
        }
    }

    // Aligned native-depth runs can unpack complete vectors of big-endian samples.
    mtd(Width: u32) readSignedAligned(destination: [*] s64, count: u32)->u32
    {
        const Samples = Width == 16 ? 8_u32 : 4_u32
        const Stride  = Width == 24 ? 12_u32 : 16_u32
        const Swap16  = cast(Math.Simd.U8x16, [1_u8, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14])
        const Swap24  = cast(Math.Simd.U8x16, [0_u8, 2, 1, 0, 0, 5, 4, 3, 0, 8, 7, 6, 0, 11, 10, 9])
        const Swap32  = cast(Math.Simd.U8x16, [3_u8, 2, 1, 0, 7, 6, 5, 4, 11, 10, 9, 8, 15, 14, 13, 12])
        let bytes = .bitsLeft() >> 3
        if bytes < 16
        {
            return 0
        }

        let groups = cast(u32, Math.min(cast(u64, count / Samples), (bytes - 16) / Stride + 1))
        let source = unwrap .data + (.bitPos >> 3)
        for index in groups
        {
            let input  = Math.Simd.load(source + index * Stride)
            let output = destination + index * Samples
            #static if Width == 16
            {
                let signed = cast #bit(Math.Simd.S16x8, Math.Simd.permute(input, Swap16))
                let first  = Math.Simd.widenLow(signed)
                let second = Math.Simd.widenHigh(signed)
                Math.Simd.store(output, Math.Simd.widenLow(first))
                Math.Simd.store(output + 2, Math.Simd.widenHigh(first))
                Math.Simd.store(output + 4, Math.Simd.widenLow(second))
                Math.Simd.store(output + 6, Math.Simd.widenHigh(second))
            }
            else
            {
                const Swap  = Width == 24 ? Swap24 : Swap32
                const Shift = Width == 24 ? 8_u32 : 0
                let signed = cast #bit(Math.Simd.S32x4, Math.Simd.permute(input, Swap)) >> Shift
                Math.Simd.store(output, Math.Simd.widenLow(signed))
                Math.Simd.store(output + 2, Math.Simd.widenHigh(signed))
            }
        }

        .bitPos += cast(u64, groups) * Stride * 8
        return groups * Samples
    }

    mtd readSignedSamples(destination: [*] s64, count, width: u32)
    {
        var start = 0_u32
        #static if not Core.BIG_ENDIAN
        {
            if not (.bitPos & 7)
            {
                switch width
                {
                case 16: start = .readSignedAligned!{16}(destination, count)
                case 24: start = .readSignedAligned!{24}(destination, count)
                case 32: start = .readSignedAligned!{32}(destination, count)
                }
            }
        }

        if width <= 28
        {
            .readSignedRun!{2}(destination + start, count - start, width)
        }
        else
        {
            .readSignedRun!{1}(destination + start, count - start, width)
        }
    }

    // Counts the zero bits before the next set bit, and consumes that set bit.
    //
    // This is the quotient of every Rice code in the stream, so it skips whole zero bytes
    // instead of walking bits.
    mtd unary()->u32
    {
        var zeros = 0_u32
        while .bitPos < .size * 8
        {
            let bitOffset = cast(u32, (.bitPos & 7))
            let masked    = cast(u32, .data![.bitPos >> 3]) & (0xFF_u32 >> bitOffset)
            if masked
            {
                let highest = 31 - cast(u32, Swag.leadingZeros(masked))
                let found   = 7 - highest
                zeros   += found - bitOffset
                .bitPos += cast(u64, (found - bitOffset)) + 1
                return zeros
            }

            zeros   += 8 - bitOffset
            .bitPos += 8 - bitOffset
        }

        .overran = true
        return zeros
    }

    // Decode the Rice quotient and remainder from a single word when both fit.
    #[Swag.Inline]
    mtd readRice(parameter: u32, mask: u64)->u64
    {
        let byteIndex = .bitPos >> 3
        if .size - byteIndex >= 8
        {
            let bitOffset = cast(u32, .bitPos & 7)
            let word      = Math.bigEndianToNative(cast(const [*] u64, unwrap .data + byteIndex)[0]) << bitOffset
            let quotient  = cast(u32, Swag.leadingZeros(word))
            let width     = quotient + 1 + parameter
            if width <= 64 - bitOffset
            {
                .bitPos += width
                let remainder = (word >> (64 - width)) & mask
                return (cast(u64, quotient) << parameter) | remainder
            }
        }

        let quotient = .unary()
        return (cast(u64, quotient) << parameter) | cast(u64, .read(parameter))
    }

    #[Swag.Inline]
    func signedResidual(code: u64)->s64 => cast(s64, code >> 1) ^ -cast(s64, code & 1)

    // Read one partition, decoding four short codes from each word when they fit.
    mtd readRiceRun(destination: [*] s64, count, parameter: u32)
    {
        let source    = unwrap .data
        let wideLimit = (.size - Math.min(.size, 7)) * 8
        let mask      = (1_u64 << parameter) - 1

        // At most thirteen remainder bits leave room for four codes even across byte boundaries.
        let bulkCount = parameter <= 13 ? count & ~3_u32 : 0
        var position  = .bitPos
        var index     = 0_u32
        while index < bulkCount and position < wideLimit
        {
            let bitOffset = cast(u32, position & 7)
            let packed    = cast(const [*] u64, source + (position >> 3))[0]
            let word0     = Math.bigEndianToNative(packed) << bitOffset
            let quotient0 = cast(u32, Swag.leadingZeros(word0))
            let width0    = quotient0 + 1 + parameter
            let word1     = word0 << (width0 & 63)
            let quotient1 = cast(u32, Swag.leadingZeros(word1))
            let width1    = quotient1 + 1 + parameter
            let word2     = word1 << (width1 & 63)
            let quotient2 = cast(u32, Swag.leadingZeros(word2))
            let width2    = quotient2 + 1 + parameter
            let word3     = word2 << (width2 & 63)
            let quotient3 = cast(u32, Swag.leadingZeros(word3))
            let width3    = quotient3 + 1 + parameter
            let used      = width0 + width1 + width2 + width3

            // A masked speculative shift can wrap. Its code is used only when the full group fits.
            if used <= 64 - bitOffset
            {
                let code0 = (cast(u64, quotient0) << parameter) | ((word0 >> (64 - width0)) & mask)
                let code1 = (cast(u64, quotient1) << parameter) | ((word1 >> (64 - width1)) & mask)
                let code2 = (cast(u64, quotient2) << parameter) | ((word2 >> (64 - width2)) & mask)
                let code3 = (cast(u64, quotient3) << parameter) | ((word3 >> (64 - width3)) & mask)
                destination[index]     = signedResidual(code0)
                destination[index + 1] = signedResidual(code1)
                destination[index + 2] = signedResidual(code2)
                destination[index + 3] = signedResidual(code3)
                position += used
            }
            else
            {
                .bitPos = position
                for lane in 4
                {
                    destination[index + lane] = signedResidual(.readRice(parameter, mask))
                }

                position = .bitPos
            }

            index += 4
        }

        .bitPos = position
        for tail in index until count
        {
            destination[tail] = signedResidual(.readRice(parameter, mask))
        }
    }

    // Read pairs when the wider remainder makes four codes impractical.
    mtd readRicePairs(destination: [*] s64, count, parameter: u32)
    {
        #[Swag.Inline]
        func wordResidual(word: u64, quotient, width, parameter: u32, mask: u64)->s64
        {
            let code = (cast(u64, quotient) << parameter) | ((word >> ((128 - width) & 63)) & mask)
            return signedResidual(code)
        }

        let source    = unwrap .data
        let wideLimit = (.size - Math.min(.size, 7)) * 8
        let mask      = (1_u64 << parameter) - 1
        var position  = .bitPos
        var index     = 0_u32
        while count - index >= 2 and position < wideLimit
        {
            let bitOffset = cast(u32, position & 7)
            let packed    = cast(const [*] u64, source + (position >> 3))[0]
            let word0     = Math.bigEndianToNative(packed) << bitOffset
            let quotient0 = cast(u32, Swag.leadingZeros(word0))
            let width0    = quotient0 + 1 + parameter
            let word1     = word0 << (width0 & 63)
            let quotient1 = cast(u32, Swag.leadingZeros(word1))
            let width1    = quotient1 + 1 + parameter

            // Both stores target residual scratch. A pair crossing the word is read again.
            destination[index]     = wordResidual(word0, quotient0, width0, parameter, mask)
            destination[index + 1] = wordResidual(word1, quotient1, width1, parameter, mask)
            let used = width0 + width1
            if used <= 64 - bitOffset
            {
                position += used
            }
            else
            {
                .bitPos                = position
                destination[index]     = signedResidual(.readRice(parameter, mask))
                destination[index + 1] = signedResidual(.readRice(parameter, mask))
                position               = .bitPos
            }

            index += 2
        }

        .bitPos = position
        for tail in index until count
        {
            destination[tail] = signedResidual(.readRice(parameter, mask))
        }
    }

    // Advances to the next byte boundary.
    mtd alignByte()
    {
        .bitPos = (.bitPos + 7) & ~7_u64
    }
}

// The stream-wide properties a FLAC frame header may omit.
//
// A frame is allowed to name its own sample rate and sample width, but it is also allowed to
// say "the one the stream declared", which is why the decoder keeps these even though the
// container already reported them.
internal struct StreamInfo
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
private const StreamInfoSize = 34_u64

internal struct Codec
{
    // Every registered codec starts with the registry's own header: a voice destroys one through
    // this, reading back the concrete type and the allocator the instance was made with.
    using base: Audio.Codec

    info:                     StreamInfo
    channels:                 [MaxChannels] Array!{s64}
    residual:                 Array!{s64}
    capacity:                 u32
    inOgg:                    bool
    oggSerial:                u32
    firstAudioSequence:       u32
    headerPacketsOnAudioPage: u32
    oggFrame:                 Array!{u8}
}

private impl Codec
{
    // Reads the "fLaC" marker and the stream information block a container carries.
    internal mtd readStreamInfo(config: const [..] u8) fail
    {
        if config.count < 4
        {
            fail InvalidFormatError{"FLAC stream information is truncated"}
        }

        // A container may hand over the whole metadata prologue, or the stream information
        // block alone. Both spellings are in use, so the marker is optional.
        var offset = 0_u64
        if config[0] == 'f' and config[1] == 'L' and config[2] == 'a' and config[3] == 'C'
        {
            offset = 4
        }

        if config.count < offset + 4
        {
            fail InvalidFormatError{"FLAC stream information is truncated"}
        }

        // A metadata block header may precede the payload: skip its type and length. Its type
        // alone does not identify it — a stream information block whose smallest block is under
        // 256 samples starts with a zero byte too — so the length it states has to agree.
        let headerLength = (cast(u64, config[offset + 1]) << 16) |
                           (cast(u64, config[offset + 2]) << 8) |
                           cast(u64, config[offset + 3])
        if (config[offset] & 0x7F) == 0 and headerLength == StreamInfoSize
        {
            offset += 4
        }

        if config.count < offset + StreamInfoSize
        {
            fail InvalidFormatError{"FLAC stream information block is truncated"}
        }

        var reader = BitReader.create(config[offset until offset + StreamInfoSize])

        with &.info
        {
            .minBlockSize = reader.read(16)
            .maxBlockSize = reader.read(16)
            discard reader.read(24)
            discard reader.read(24)
            .sampleRate    = reader.read(20)
            .channels      = reader.read(3) + 1
            .bitsPerSample = reader.read(5) + 1
            .totalSamples  = (cast(u64, reader.read(4)) << 32) | cast(u64, reader.read(32))
        }

        if not .info.sampleRate
        {
            fail InvalidFormatError{"FLAC stream declares no sample rate"}
        }

        if .info.channels > MaxChannels
        {
            fail UnsupportedFormatError{"FLAC stream declares more than eight channels"}
        }

        if .info.bitsPerSample < 4 or .info.bitsPerSample > 32
        {
            fail UnsupportedFormatError{"FLAC sample width is outside the supported range"}
        }

        if not .info.maxBlockSize
        {
            fail InvalidFormatError{"FLAC stream declares no maximum block size"}
        }
    }

    // Grows the per-channel scratch so one block of `blockSize` samples fits.
    mtd reserveBlock(blockSize: u32)
    {
        if blockSize <= .capacity
        {
            return
        }

        for index in MaxChannels
        {
            .channels[index].resize(cast(u64, blockSize))
        }

        .residual.resize(cast(u64, blockSize))
        .capacity = blockSize
    }

    // Reads one frame header, which is what decides the shape of everything after it.
    mtd readFrameHeader(reader: *BitReader)->FrameHeader fail
    {
        if reader.read(14) != 0x3FFE
        {
            fail InvalidFormatError{"FLAC frame has no sync code"}
        }

        if reader.read(1)
        {
            fail InvalidFormatError{"FLAC frame sets the reserved header bit"}
        }

        discard reader.read(1)     // Blocking strategy bit: decoding does not depend on it.
        let blockSizeCode  = reader.read(4)
        let sampleRateCode = reader.read(4)

        var result: #returntype
        result.channelAssignment = reader.read(4)
        let depthCode = reader.read(3)
        if reader.read(1)
        {
            fail InvalidFormatError{"FLAC frame sets the reserved header bit"}
        }

        // The frame or sample number is a UTF-8-shaped integer whose leading byte states its
        // length. Its value only matters when seeking, which the container index already does.
        let lead       = reader.read(8)
        var extraBytes = 0_u32
        if lead == 0xFE
        {
            extraBytes = 6
        }
        else if lead == 0xFF
        {
            fail InvalidFormatError{"FLAC frame number is malformed"}
        }
        else if lead >= 0xFC
        {
            extraBytes = 5
        }
        else if lead >= 0xF8
        {
            extraBytes = 4
        }
        else if lead >= 0xF0
        {
            extraBytes = 3
        }
        else if lead >= 0xE0
        {
            extraBytes = 2
        }
        else if lead >= 0xC0
        {
            extraBytes = 1
        }
        else if lead >= 0x80
        {
            fail InvalidFormatError{"FLAC frame number is malformed"}
        }

        for extraBytes
        {
            let continuation = reader.read(8)
            if (continuation & 0xC0) != 0x80
            {
                fail InvalidFormatError{"FLAC frame number has an invalid continuation byte"}
            }
        }

        switch blockSizeCode
        {
        case 0:          fail InvalidFormatError{"FLAC frame uses the reserved block size code"}
        case 1:          result.blockSize = 192
        case 2, 3, 4, 5: result.blockSize = 576_u32 << (blockSizeCode - 2)
        case 6:          result.blockSize = reader.read(8) + 1
        case 7:          result.blockSize = reader.read(16) + 1
        default:         result.blockSize = 256_u32 << (blockSizeCode - 8)
        }

        switch sampleRateCode
        {
        case 0:  result.sampleRate = .info.sampleRate
        case 12: result.sampleRate = reader.read(8) * 1000
        case 13: result.sampleRate = reader.read(16)
        case 14: result.sampleRate = reader.read(16) * 10
        case 15: fail InvalidFormatError{"FLAC frame uses the invalid sample rate code"}
        default: result.sampleRate = CodedRates[sampleRateCode]
        }

        result.bitsPerSample = depthCode ? CodedDepths[depthCode] : .info.bitsPerSample
        if not result.bitsPerSample
        {
            fail InvalidFormatError{"FLAC frame uses the reserved sample width code"}
        }

        if result.channelAssignment < 8
        {
            result.channels = result.channelAssignment + 1
        }
        else if result.channelAssignment < 11
        {
            result.channels = 2
        }
        else
        {
            fail InvalidFormatError{"FLAC frame uses a reserved channel assignment"}
        }

        // The header ends with a checksum of itself, which the container index already stands in for.
        discard reader.read(8)
        if reader.overran
        {
            fail InvalidFormatError{"FLAC frame header is truncated"}
        }

        return result
    }

    // Reads the residual of one subframe into `.residual`, starting after the warmup samples.
    mtd readResidual(reader: *BitReader, blockSize, predictorOrder: u32) fail
    {
        let method = reader.read(2)
        if method > 1
        {
            fail InvalidFormatError{"FLAC residual uses a reserved coding method"}
        }

        let partitionOrder = reader.read(4)
        let partitions     = 1_u32 << partitionOrder
        if blockSize % partitions
        {
            fail InvalidFormatError{"FLAC residual partitioning does not divide the block"}
        }

        let partitionSize = blockSize >> partitionOrder
        if partitionSize < predictorOrder
        {
            fail InvalidFormatError{"FLAC residual first partition is shorter than the predictor"}
        }

        let paramBits = method ? 5_u32 : 4_u32
        let escape    = method ? Rice2Escape : RiceEscape
        let output    = .residual.storage()

        var index = predictorOrder
        for partition in partitions
        {
            let end   = partitionSize * (partition + 1)
            let param = reader.read(paramBits)
            if param == escape
            {
                let rawBits = reader.read(5)
                if rawBits
                {
                    reader.readSignedSamples(output + index, end - index, rawBits)
                }
                else
                {
                    for sample in index until end
                    {
                        output[sample] = 0
                    }
                }

                index = end
            }
            else
            {
                if param >= 14 and param <= 27
                {
                    reader.readRicePairs(output + index, end - index, param)
                }
                else
                {
                    reader.readRiceRun(output + index, end - index, param)
                }

                index = end
            }
        }
    }

    // Decodes one subframe of `blockSize` samples at `bitsPerSample` into `target`.
    mtd readSubframe(reader: *BitReader, target: [*] s64, blockSize, bitsPerSample: u32) fail
    {
        if reader.read(1)
        {
            fail InvalidFormatError{"FLAC subframe sets the reserved leading bit"}
        }

        let kind = reader.read(6)

        // Wasted bits are trailing zeros the encoder removed from every sample of the subframe.
        var wasted = 0_u32
        if reader.read(1)
        {
            wasted = reader.unary() + 1
            if wasted >= bitsPerSample
            {
                fail InvalidFormatError{"FLAC subframe wastes every bit of its samples"}
            }
        }

        let depth = bitsPerSample - wasted

        if not kind
        {
            let value = reader.readSigned(depth)
            for index in blockSize
            {
                target[index] = value
            }
        }
        else if kind == 1
        {
            for index in blockSize
            {
                target[index] = reader.readSigned(depth)
            }
        }
        else if kind >= 8 and kind <= 12
        {
            let order = kind - 8
            if blockSize < order
            {
                fail InvalidFormatError{"FLAC fixed subframe is shorter than its predictor"}
            }

            for index in order
            {
                .residual[index] = reader.readSigned(depth)
            }

            try .readResidual(reader, blockSize, order)
            .predictFixed(target, order, blockSize)
        }
        else if kind >= 32
        {
            let order = kind - 31
            if blockSize < order
            {
                fail InvalidFormatError{"FLAC linear subframe is shorter than its predictor"}
            }

            for index in order
            {
                .residual[index] = reader.readSigned(depth)
            }

            let precision = reader.read(4) + 1
            if precision == 16
            {
                fail InvalidFormatError{"FLAC linear predictor uses the reserved coefficient precision"}
            }

            let shift = reader.readSigned(5)

            var coefficients: [MaxLpcOrder] s64
            for index in order
            {
                coefficients[index] = reader.readSigned(precision)
            }

            try .readResidual(reader, blockSize, order)
            try .predictLinear(target, &coefficients[0], order, blockSize, cast(s32, shift), depth)
        }
        else
        {
            fail InvalidFormatError{"FLAC subframe uses a reserved type"}
        }

        if reader.overran
        {
            fail InvalidFormatError{"FLAC subframe is truncated"}
        }

        if wasted
        {
            for index in blockSize
            {
                target[index] <<= wasted
            }
        }
    }

    // Restores the samples of a fixed-predictor subframe from its residual.
    mtd predictFixed(target: [*] s64, order, blockSize: u32)
    {
        let source = .residual.storage()
        for index in order
        {
            target[index] = source[index]
        }

        switch order
        {
        case 0:
            for index in blockSize
            {
                target[index] = source[index]
            }

        case 1:
            for index in order until blockSize
            {
                target[index] = source[index] + target[index - 1]
            }

        case 2:
            for index in order until blockSize
            {
                target[index] = source[index] + 2 * target[index - 1] - target[index - 2]
            }

        case 3:
            for index in order until blockSize
            {
                target[index] = source[index] + 3 * target[index - 1] - 3 * target[index - 2] + target[index - 3]
            }

        default:
            for index in order until blockSize
            {
                target[index] = source[index] + 4 * target[index - 1] - 6 * target[index - 2] + 4 * target[index - 3] - target[index - 4]
            }
        }
    }

    // Predict four samples together from the existing history. Complete each later
    // dot product with the newly reconstructed samples before shifting it. Speculative
    // products can wrap after history leaves the narrow range, so validate before storing.
    #[Swag.Safety(.Overflow, false)]
    mtd(Wide: bool) predictLinearPacked(target, residual: [*] s64, coefficients: const [*] s64, order, blockSize, shift: u32)->u32
    {
        const Limit   = Wide ? 1_s64 << 30 : 1_s64 << 15
        const LowBias = 32768_s64
        var norm, bias: s64
        var weights:    [4, 8] s16
        var warmup, upperWarmup: [8] s16
        #static if not Wide
        {
            discard bias, upperWarmup
        }

        for tap in order
        {
            let sample = residual[tap]
            if sample < -Limit or sample >= Limit
            {
                return order
            }

            #static if Wide
            {
                // A wide sample equals (high << 16) + biasedLow + 32768.
                warmup[8 - order + tap]      = cast #wrap (s16, sample ^ LowBias)
                upperWarmup[8 - order + tap] = cast(s16, sample >> 16)
                bias += coefficients[tap] * LowBias
            }
            else
            {
                warmup[8 - order + tap] = cast(s16, sample)
            }

            norm += Math.abs(coefficients[tap])
        }

        if norm > 65535
        {
            return order
        }

        for pair in 4
        {
            for lane in 8
            {
                let tap = 7 - 2 * pair - (lane & 1) + (lane >> 1)
                if tap < order
                {
                    weights[pair, lane] = cast(s16, coefficients[tap])
                }
            }
        }

        let weight0 = Math.Simd.load(cast(const [*] s16, &weights[0, 0]))
        let weight1 = Math.Simd.load(cast(const [*] s16, &weights[1, 0]))
        let weight2 = Math.Simd.load(cast(const [*] s16, &weights[2, 0]))
        let weight3 = Math.Simd.load(cast(const [*] s16, &weights[3, 0]))
        var history = Math.Simd.load(cast(const [*] s16, &warmup[0]))
        let tap0    = coefficients[0]
        let tap1    = coefficients[1]
        let tap2    = coefficients[2]
        const Pair0 = cast(Math.Simd.U16x8, [0_u16, 1, 0, 1, 0, 1, 0, 1])
        const Pair1 = cast(Math.Simd.U16x8, [2_u16, 3, 2, 3, 2, 3, 2, 3])
        const Pair2 = cast(Math.Simd.U16x8, [4_u16, 5, 4, 5, 4, 5, 4, 5])
        const Pair3 = cast(Math.Simd.U16x8, [6_u16, 7, 6, 7, 6, 7, 6, 7])

        var upperHistory:        Math.Simd.S16x8
        var bias1, bias2, bias3: s64
        #static if Wide
        {
            upperHistory = Math.Simd.load(cast(const [*] s16, &upperWarmup[0]))

            // Later lanes omit the taps supplied by the newly reconstructed samples.
            bias1 = bias - tap0 * LowBias
            bias2 = bias1 - tap1 * LowBias
            bias3 = bias2 - tap2 * LowBias
        }
        else
        {
            discard upperHistory, bias1, bias2, bias3
        }

        var index = order
        while blockSize - index >= 4
        {
            let predictions = Math.Simd.mulAddPairs(weight0, Swag.vecShuffle(history, Pair0)) +
                              Math.Simd.mulAddPairs(weight1, Swag.vecShuffle(history, Pair1)) +
                              Math.Simd.mulAddPairs(weight2, Swag.vecShuffle(history, Pair2)) +
                              Math.Simd.mulAddPairs(weight3, Swag.vecShuffle(history, Pair3))
            var p0 = cast(s64, predictions[0] >> shift)
            var p1 = cast(s64, predictions[1])
            var p2 = cast(s64, predictions[2])
            var p3 = cast(s64, predictions[3])
            #static if Wide
            {
                let upper = Math.Simd.mulAddPairs(weight0, Swag.vecShuffle(upperHistory, Pair0)) +
                            Math.Simd.mulAddPairs(weight1, Swag.vecShuffle(upperHistory, Pair1)) +
                            Math.Simd.mulAddPairs(weight2, Swag.vecShuffle(upperHistory, Pair2)) +
                            Math.Simd.mulAddPairs(weight3, Swag.vecShuffle(upperHistory, Pair3))
                p0 = (cast(s64, predictions[0]) + (cast(s64, upper[0]) << 16) + bias) >> shift
                p1 += (cast(s64, upper[1]) << 16) + bias1
                p2 += (cast(s64, upper[2]) << 16) + bias2
                p3 += (cast(s64, upper[3]) << 16) + bias3
            }

            let sample0 = residual[index] + p0
            let sample1 = residual[index + 1] + ((p1 + tap0 * sample0) >> shift)
            let sample2 = residual[index + 2] + ((p2 + tap1 * sample0 + tap0 * sample1) >> shift)
            let sample3 = residual[index + 3] + ((p3 + tap2 * sample0 + tap1 * sample1 + tap0 * sample2) >> shift)

            // The first out-of-range sample is still exact because its input history fits.
            // If it exists, discard the entire group and let the wide predictor redo it.
            let outside = cast #bit (u64, (sample0 + Limit)) | cast #bit (u64, (sample1 + Limit)) |
                          cast #bit (u64, (sample2 + Limit)) | cast #bit (u64, (sample3 + Limit))
            if outside >= cast(u64, Limit * 2)
            {
                return index
            }

            target[index]     = sample0
            target[index + 1] = sample1
            target[index + 2] = sample2
            target[index + 3] = sample3
            #static if Wide
            {
                let low = [cast #wrap(s16, sample0 ^ LowBias), cast #wrap(s16, sample1 ^ LowBias),
                           cast #wrap(s16, sample2 ^ LowBias), cast #wrap(s16, sample3 ^ LowBias), 0, 0, 0, 0]
                let high = [cast(s16, sample0 >> 16), cast(s16, sample1 >> 16),
                            cast(s16, sample2 >> 16), cast(s16, sample3 >> 16), 0, 0, 0, 0]
                history      = Swag.vecAlign(history, Math.Simd.load(cast(const [*] s16, &low[0])), 8)
                upperHistory = Swag.vecAlign(upperHistory, Math.Simd.load(cast(const [*] s16, &high[0])), 8)
            }
            else
            {
                let samples = [cast(s16, sample0), cast(s16, sample1), cast(s16, sample2), cast(s16, sample3), 0, 0, 0, 0]
                history = Swag.vecAlign(history, Math.Simd.load(cast(const [*] s16, &samples[0])), 8)
            }

            index += 4
        }

        return index
    }

    // Restores the samples of a linear-predictor subframe from its residual.
    //
    // The accumulator is 64-bit because the format allows thirty-two coefficients of fifteen
    // bits each over samples of up to thirty-three bits in a decorrelated stereo side channel.
    mtd predictLinear(target: [*] s64, coefficients: const [*] s64, order, blockSize, shift: s32, depth: u32) fail
    {
        let source = .residual.storage()
        for index in order
        {
            target[index] = source[index]
        }

        var start = cast(u32, order)
        if order >= 3 and order <= 8 and shift >= 0
        {
            let tapCount    = cast(u32, order)
            let sampleCount = cast(u32, blockSize)
            let rightShift  = cast(u32, shift)
            start = .predictLinearPacked!{false}(target, source, coefficients, tapCount, sampleCount, rightShift)
            if start == tapCount and depth > 16
            {
                start = .predictLinearPacked!{true}(target, source, coefficients, tapCount, sampleCount, rightShift)
            }
        }

        let groups      = order / 4
        let groupedTaps = groups * 4
        for index in start until blockSize
        {
            var sum = 0_s64
            for tap in order
            {
                sum += coefficients[tap] * target[index - 1 - tap]
            }

            var prediction: s64
            if shift >= 0
            {
                prediction = sum >> cast(u32, shift)
            }
            else
            {
                let amount = cast(u32, -shift)
                if (sum > 0 and sum > (Swag.S64.Max >> amount)) or
                   (sum < 0 and sum < (Swag.S64.Min >> amount))
                {
                    fail InvalidFormatError{"FLAC linear predictor overflows its accumulator"}
                }

                prediction = sum << amount
            }

            let residual = source[index]
            if (prediction > 0 and residual > Swag.S64.Max - prediction) or
               (prediction < 0 and residual < Swag.S64.Min - prediction)
            {
                fail InvalidFormatError{"FLAC linear predictor overflows its accumulator"}
            }

            target[index] = residual + prediction
        }
    }

    // Undoes the inter-channel decorrelation a stereo frame may use.
    mtd undecorrelate(assignment, blockSize: u32)
    {
        if assignment < 8
        {
            return
        }

        let first  = .channels[0].storage()
        let second = .channels[1].storage()

        switch assignment
        {
        case 8:

            // Left and side: the second channel holds left minus right.
            for index in blockSize
            {
                second[index] = first[index] - second[index]
            }

        case 9:

            // Side and right: the first channel holds left minus right.
            for index in blockSize
            {
                first[index] += second[index]
            }

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
        if header.channels > MaxChannels
        {
            fail UnsupportedFormatError{"FLAC frame declares more than eight channels"}
        }

        if header.blockSize > 65535
        {
            fail InvalidFormatError{"FLAC frame block size is out of range"}
        }

        .reserveBlock(header.blockSize)

        for channel in header.channels
        {
            // In a decorrelated pair, the channel holding the difference needs one more bit
            // than the frame declares to represent its full range.
            var depth = header.bitsPerSample
            if (header.channelAssignment == 8 or header.channelAssignment == 10) and channel == 1
            {
                depth += 1
            }
            else if header.channelAssignment == 9 and not channel
            {
                depth += 1
            }

            try .readSubframe(&reader, .channels[channel].storage(), header.blockSize, depth)
        }

        return header
    }

    // Apply stereo decorrelation while interleaving, so the wide scratch is read once.
    mtd(Assignment: u32, ScaleDown: bool, FullWidth: bool) interleaveStereoPcm16(destination: [*] s16, blockSize, shift: u32)
    {
        #static if not ScaleDown
        {
            discard shift
        }

        let firstPlane  = .channels[0].storage()
        let secondPlane = .channels[1].storage()
        var done        = 0_u32
        #static if not Core.BIG_ENDIAN
        {
            while blockSize - done >= 4
            {
                var left, right: Math.Simd.S32x4
                #static if FullWidth
                {
                    // Without decorrelation, signed-32 saturation still gives the same
                    // PCM16 result after shifting by at most sixteen bits.
                    left  = pcmWords(firstPlane + done)
                    right = pcmWords(secondPlane + done)
                }
                else
                {
                    const Bias = cast(Math.Simd.U64x2, [0x2000_0000_u64, 0x2000_0000])
                    const High = cast(Math.Simd.U64x2, [0xFFFF_FFFF_C000_0000_u64, 0xFFFF_FFFF_C000_0000])
                    const Zero = cast(Math.Simd.U64x2, [0_u64, 0])
                    let a0 = cast #bit (Math.Simd.U64x2, Math.Simd.load(firstPlane + done))
                    let a1 = cast #bit (Math.Simd.U64x2, Math.Simd.load(firstPlane + done + 2))
                    let b0 = cast #bit (Math.Simd.U64x2, Math.Simd.load(secondPlane + done))
                    let b1 = cast #bit (Math.Simd.U64x2, Math.Simd.load(secondPlane + done + 2))

                    // Inputs in [-2^29, 2^29) keep decorrelation in signed 32 bits.
                    // The bias maps that interval to the unsigned low thirty bits.
                    let large = ((a0 + Bias) | (a1 + Bias) | (b0 + Bias) | (b1 + Bias)) & High
                    if Math.Simd.bitmask(large == Zero) != 0b11
                    {
                        break
                    }

                    left  = cast #bit (Math.Simd.S32x4, Math.Simd.deinterleaveEven(cast #bit(Math.Simd.U32x4, a0), cast #bit(Math.Simd.U32x4, a1)))
                    right = cast #bit (Math.Simd.S32x4, Math.Simd.deinterleaveEven(cast #bit(Math.Simd.U32x4, b0), cast #bit(Math.Simd.U32x4, b1)))
                }

                #static if Assignment == 8
                {
                    right = left - right
                }
                else if Assignment == 9
                {
                    left += right
                }
                else if Assignment == 10
                {
                    // The arithmetic shift floors half the side value, including odd negative values.
                    let restoredRight = left - (right >> 1)
                    left  = restoredRight + right
                    right = restoredRight
                }

                #static if ScaleDown
                {
                    left  >>= shift
                    right >>= shift
                }

                let leftWords  = cast #bit (Math.Simd.U32x4, left)
                let rightWords = cast #bit (Math.Simd.U32x4, right)
                let low        = cast #bit (Math.Simd.S32x4, Math.Simd.interleaveLow(leftWords, rightWords))
                let high       = cast #bit (Math.Simd.S32x4, Math.Simd.interleaveHigh(leftWords, rightWords))
                Math.Simd.store(destination + 2 * done, Math.Simd.packSigned(low, high))
                done += 4
            }
        }

        for sample in done until blockSize
        {
            var left  = firstPlane[sample]
            var right = secondPlane[sample]
            #static if Assignment == 8
            {
                right = left - right
            }
            else if Assignment == 9
            {
                left += right
            }
            else if Assignment == 10
            {
                let mid = (left << 1) | (right & 1)
                left  = (mid + right) >> 1
                right = (mid - right) >> 1
            }

            #static if ScaleDown
            {
                left  >>= shift
                right >>= shift
            }

            destination[2 * sample]     = cast(s16, Math.clamp(left, -32768_s64, 32767_s64))
            destination[2 * sample + 1] = cast(s16, Math.clamp(right, -32768_s64, 32767_s64))
        }
    }

    mtd(ScaleDown: bool) writeStereoPcm16(destination: [*] s16, header: FrameHeader, shift: u32)
    {
        switch header.channelAssignment
        {
        case 8:  .interleaveStereoPcm16!{8_u32, ScaleDown, false}(destination, header.blockSize, shift)
        case 9:  .interleaveStereoPcm16!{9_u32, ScaleDown, false}(destination, header.blockSize, shift)
        case 10: .interleaveStereoPcm16!{10_u32, ScaleDown, false}(destination, header.blockSize, shift)
        default: .interleaveStereoPcm16!{1_u32, ScaleDown, false}(destination, header.blockSize, shift)
        }
    }

    // Saturate four wide decoded samples to signed 32 bits before the PCM16 pack.
    #[Swag.Inline]
    func pcmWords(source: const [*] s64)->Math.Simd.S32x4
    {
        let first  = cast #bit(Math.Simd.U32x4, Math.Simd.load(source))
        let second = cast #bit(Math.Simd.U32x4, Math.Simd.load(source + 2))
        let lower  = cast #bit(Math.Simd.S32x4, Math.Simd.deinterleaveEven(first, second))
        let upper  = cast #bit(Math.Simd.S32x4, Math.Simd.deinterleaveOdd(first, second))

        // The low word is exact when the high word is its sign extension.
        let saturated = (upper >> 31) ^ Math.Simd.splat(Swag.S32.Max)
        return Math.Simd.select(upper == (lower >> 31), lower, saturated)
    }

    // Keep the six source-plane addresses in the output loop.
    mtd writeSixChannelPcm16(destination: [*] s16, blockSize: u32)
    {
        const MinSample = -32768_s64
        const MaxSample = 32767_s64
        let plane0 = .channels[0].storage()
        let plane1 = .channels[1].storage()
        let plane2 = .channels[2].storage()
        let plane3 = .channels[3].storage()
        let plane4 = .channels[4].storage()
        let plane5 = .channels[5].storage()
        var done   = 0_u32
        #static if not Core.BIG_ENDIAN
        {
            #[Swag.Inline]
            func packPairs(first, second: Math.Simd.S32x4)->Math.Simd.U32x4
            {
                const Interleaved = cast(Math.Simd.U16x8, [0_u16, 4, 1, 5, 2, 6, 3, 7])
                let packed = Math.Simd.packSigned(first, second)
                return cast #bit(Math.Simd.U32x4, Math.Simd.permute(packed, Interleaved))
            }

            // A 32-bit lane holds one adjacent channel pair. Four frames fill three vectors.
            const RowsFirst = cast(Math.Simd.U32x4, [0_u32, 1, 4, 2])
            const RowsMid   = cast(Math.Simd.U32x4, [3_u32, 5, 0, 0])
            const RowsNext  = cast(Math.Simd.U32x4, [0_u32, 1, 4, 5])
            const RowsLast  = cast(Math.Simd.U32x4, [6_u32, 2, 3, 7])
            while blockSize - done >= 4
            {
                let ab     = packPairs(pcmWords(plane0 + done), pcmWords(plane1 + done))
                let cd     = packPairs(pcmWords(plane2 + done), pcmWords(plane3 + done))
                let ef     = packPairs(pcmWords(plane4 + done), pcmWords(plane5 + done))
                let ac0    = Math.Simd.interleaveLow(ab, cd)
                let ac1    = Math.Simd.interleaveHigh(ab, cd)
                let start  = Math.Simd.permute2(ac0, ef, RowsFirst)
                let mid    = Math.Simd.permute2(ac0, ef, RowsMid)
                let next   = Math.Simd.permute2(mid, ac1, RowsNext)
                let last   = Math.Simd.permute2(ac1, ef, RowsLast)
                let output = destination + done * 6
                Math.Simd.store(output, cast #bit(Math.Simd.S16x8, start))
                Math.Simd.store(output + 8, cast #bit(Math.Simd.S16x8, next))
                Math.Simd.store(output + 16, cast #bit(Math.Simd.S16x8, last))
                done += 4
            }
        }

        for sample in done until blockSize
        {
            let output = destination + sample * 6
            output[0] = cast(s16, Math.clamp(plane0[sample], MinSample, MaxSample))
            output[1] = cast(s16, Math.clamp(plane1[sample], MinSample, MaxSample))
            output[2] = cast(s16, Math.clamp(plane2[sample], MinSample, MaxSample))
            output[3] = cast(s16, Math.clamp(plane3[sample], MinSample, MaxSample))
            output[4] = cast(s16, Math.clamp(plane4[sample], MinSample, MaxSample))
            output[5] = cast(s16, Math.clamp(plane5[sample], MinSample, MaxSample))
        }
    }

    mtd writeMonoPcm16(destination: [*] s16, blockSize: u32)
    {
        let source = .channels[0].storage()
        var done   = 0_u32
        #static if not Core.BIG_ENDIAN
        {
            while blockSize - done >= 8
            {
                let low  = pcmWords(source + done)
                let high = pcmWords(source + done + 4)
                Math.Simd.store(destination + done, Math.Simd.packSigned(low, high))
                done += 8
            }
        }

        for sample in done until blockSize
        {
            destination[sample] = cast(s16, Math.clamp(source[sample], -32768_s64, 32767_s64))
        }
    }

    // Writes the decoded block as interleaved 16-bit PCM.
    mtd writePcm16(destination: [*] s16, header: FrameHeader)
    {
        let shift = cast(s32, header.bitsPerSample) - 16
        var index = 0_u64
        for sample in header.blockSize
        {
            for channel in header.channels
            {
                let value  = .channels[channel][sample]
                var scaled = shift > 0 ? value >> cast(u32, shift) : value << cast(u32, -shift)
                scaled = Math.clamp(scaled, -32768_s64, 32767_s64)
                destination[index] = cast(s16, scaled)
                index  += 1
            }
        }
    }

    mtd decodePcm(destination: [*] s16, destinationSize: u64, packet: const [..] u8)->u64 fail
    {
        let header   = try .decodeFrame(packet)
        let produced = cast(u64, header.blockSize) * cast(u64, header.channels) * #sizeof(s16)
        if header.channels != .info.channels
        {
            fail InvalidFormatError{"FLAC frame channel count differs from its stream"}
        }

        if destinationSize < produced
        {
            fail BadParameterError{"FLAC destination buffer is too small"}
        }

        .writePcm16(destination, header)
        return produced
    }

    // Copies the fragment of a frame that crosses a page boundary.
    mtd appendOggFrame(part: const [..] u8) fail
    {
        // STREAMINFO represents native frame sizes with 24 bits.
        if .oggFrame.count + part.count > 0xFF_FFFF
        {
            fail InvalidFormatError{"Ogg FLAC frame exceeds the FLAC frame-size limit"}
        }

        .oggFrame.add(part)
    }

    // An indexed Ogg run can hold many frames, including frames split across pages.
    mtd decodeOggRun(destination: [*] s16, destinationSize: u64, pages: const [..] u8)->u64 fail
    {
        var offset, produced: u64
        .oggFrame.clear()
        while offset < pages.count
        {
            let page = try Ogg.readPageHeader(pages, offset)
            if page.totalBytes() > pages.count - offset
            {
                fail InvalidFormatError{"Ogg FLAC page runs past the end of its packet group"}
            }

            var at = offset + page.headerBytes
            offset += page.totalBytes()
            if page.serial != .oggSerial
            {
                continue
            }

            var skip = page.sequence == .firstAudioSequence ? .headerPacketsOnAudioPage : 0_u32
            for index in page.segments
            {
                at += size
                if size == 255
                {
                    continue
                }

                if skip
                {
                    if size < 255
                    {
                        skip -= 1
                    }
                }
                else
                {
                    // Native FLAC frames fit in STREAMINFO's 24-bit maximum frame size.
                    if .oggFrame.count + size > 0xFF_FFFF
                    {
                        fail InvalidFormatError{"Ogg FLAC frame exceeds the FLAC frame-size limit"}
                    }

                    .oggFrame.add(pages[at until at + size])
                    if size < 255
                    {
                        try .appendOggFrame(frame)
                        frame = .oggFrame.toSlice()
                    }

                    produced += try .decodePcm(destination + produced / #sizeof(s16), destinationSize - produced, frame)
                    .oggFrame.clear()
                }

                start = at
            }

            if start < at and not skip
            {
                try .appendOggFrame(pages[start until at])
            }
        }

        if not .oggFrame.isEmpty()
        {
            fail InvalidFormatError{"Ogg FLAC packet group ends inside a frame"}
        }

        return produced
    }
}

impl IPacketCodec for Codec
{
    mtd impl canDecode(encoding: SoundFileEncoding)->bool => encoding == .Flac

    mtd impl initialize(config: const [..] u8, sampleRateHz, channels: u32) fail
    {
        .inOgg = config.count >= 4 and config[until 4] == cast(const [..] u8, "OggS")
        if .inOgg
        {
            let setup = try Ogg.flacSetup(config)
            .oggSerial = setup.serial
            .firstAudioSequence       = setup.firstAudioSequence
            .headerPacketsOnAudioPage = setup.headerPacketsOnAudioPage
            try .readStreamInfo(setup.streamInfo)
        }
        else
        {
            try .readStreamInfo(config)
        }

        if .info.sampleRate != sampleRateHz or .info.channels != channels
        {
            fail InvalidFormatError{"FLAC stream information does not match its container track"}
        }

        .reserveBlock(.info.maxBlockSize)
    }

    mtd impl reset() {}

    mtd impl decodePacket(destination: [*] void, destinationSize: u64, packet: const [..] u8)->u64 fail
    {
        let pcm = cast([*] s16, destination)
        if .inOgg
        {
            return try .decodeOggRun(pcm, destinationSize, packet)
        }

        return try .decodePcm(pcm, destinationSize, packet)
    }
}

// Returns the number of sample frames one FLAC frame decodes to.
//
// A container index needs this before any decoding happens, so it reads the block size out of
// the frame header rather than decoding the frame.
internal func packetFrameCount(packet: const [..] u8)->u32 fail
{
    if packet.count < 5
    {
        fail InvalidFormatError{"FLAC frame is truncated"}
    }

    if packet[0] != 0xFF or (packet[1] & 0xFC) != 0xF8
    {
        fail InvalidFormatError{"FLAC frame has no sync code"}
    }

    let blockSizeCode = cast(u32, (packet[2] >> 4))
    switch blockSizeCode
    {
    case 0:          fail InvalidFormatError{"FLAC frame uses the reserved block size code"}
    case 1:          return 192
    case 2, 3, 4, 5: return 576_u32 << (blockSizeCode - 2)
    case 6, 7:       break
    default:         return 256_u32 << (blockSizeCode - 8)
    }

    // The block size is stated after the frame number, whose leading byte gives its length.
    var reader = BitReader.create(packet)
    discard reader.read(32)

    let lead       = reader.read(8)
    var extraBytes = 0_u32
    if lead >= 0xFE
    {
        extraBytes = 6
    }
    else if lead >= 0xFC
    {
        extraBytes = 5
    }
    else if lead >= 0xF8
    {
        extraBytes = 4
    }
    else if lead >= 0xF0
    {
        extraBytes = 3
    }
    else if lead >= 0xE0
    {
        extraBytes = 2
    }
    else if lead >= 0xC0
    {
        extraBytes = 1
    }

    for extraBytes
    {
        discard reader.read(8)
    }

    let blockSize = blockSizeCode == 6 ? reader.read(8) + 1 : reader.read(16) + 1
    if reader.overran
    {
        fail InvalidFormatError{"FLAC frame header is truncated"}
    }

    return blockSize
}

#init
{
    registerPacketCodec!{Codec}()
}
