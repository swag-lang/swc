//! Format: Dolby Digital (AC-3) packet decoder component.
//! Supported: Independent AC-3 sync frames through 5.1 channels, including coupling, rematrixing, exponent reuse, bit allocation, and LFE.
//! Not supported: Dependent substreams and formats other than AC-3.
//! Role: This file owns AC-3 frame syntax, audio blocks, coupling, rematrixing, and packet dispatch.
//
#global namespace Dolby

using Core, Core.Errors, Core.Math

private struct Ac3Bsi
{
    fscod:     u32
    frameSize: u32
    bsid:      u32
    acmod:     u32
    nfchans:   u32
    lfeon:     bool
}

private struct Ac3Block
{
    blockSwitch: [MaxFullBandwidthChannels] bool
    dither:      [MaxFullBandwidthChannels] bool

    coupling:          bool
    channelCoupled:    [MaxFullBandwidthChannels] bool
    phaseFlagsInUse:   bool
    couplingBegin:     u32
    couplingEnd:       u32
    couplingSubbands:  u32
    couplingBands:     u32
    couplingBandJoin:  [18] bool
    couplingCoordNew:  [MaxFullBandwidthChannels] bool
    couplingMaster:    [MaxFullBandwidthChannels] u32
    couplingCoordExp:  [MaxFullBandwidthChannels, 18] u32
    couplingCoordMant: [MaxFullBandwidthChannels, 18] u32
    couplingCoord:     [MaxFullBandwidthChannels, 18] f64
    couplingPhase:     [18] bool

    rematrix:      [4] bool
    rematrixCount: u32

    couplingExpStrategy: u32
    channelExpStrategy:  [MaxFullBandwidthChannels] u32
    lfeExpStrategy:      u32
    channelBandwidth:    [MaxFullBandwidthChannels] u32
    channelEnd:          [MaxFullBandwidthChannels] s32
    channelExponents:    [MaxFullBandwidthChannels, SamplesPerBlock] s32
    couplingStart:       s32
    couplingEndMantissa: s32
    couplingExponents:   [SamplesPerBlock] s32
    lfeExponents:        [7] s32

    slowDecayCode:    u32
    fastDecayCode:    u32
    slowGainCode:     u32
    dbPerBitCode:     u32
    floorCode:        u32
    coarseSnr:        u32
    channelFineSnr:   [MaxFullBandwidthChannels] u32
    channelFastGain:  [MaxFullBandwidthChannels] u32
    couplingFineSnr:  u32
    couplingFastGain: u32
    lfeFineSnr:       u32
    lfeFastGain:      u32
    couplingFastLeak: u32
    couplingSlowLeak: u32
    channelDelta:     [MaxFullBandwidthChannels] DeltaAllocation
    couplingDelta:    DeltaAllocation

    channelBap:  [MaxFullBandwidthChannels, SamplesPerBlock] s32
    couplingBap: [SamplesPerBlock] s32
    lfeBap:      [7] s32
}

// `chbwcod` is defined from 0 through 60; larger six-bit values are reserved.
private const MaxChannelBandwidthCode = 60_u32

// The lowest sample rate has up to six bytes per kbps in a sync frame.
private const MaxAc3FrameBytes = 6 * BitRates[BitRates.count - 1]

// At the start of mantissas, the cursor is still within the packet. A block
// can read up to 256 16-bit mantissas per channel plus shared coupling.
// Leave four more bytes for the last unaligned word.
private const MantissaReadPadding = (MaxChannels + 1) * SamplesPerBlock * 2 + 4

private struct Ac3Codec
{
    using base: Codec

    sampleRate:      u32
    channels:        u32
    block:           Ac3Block
    imdct:           [MaxChannels] Imdct
    stereoImdct:     StereoImdct
    surroundImdct:   SurroundImdct
    mantissaGains:   PreparedMantissaGains
    coefficients:    [MaxChannels, SamplesPerBlock] f64
    dither:          DitherGenerator
    packetCopy:      [MaxAc3FrameBytes + MantissaReadPadding] u8
    packetCopyBytes: u64
}

private func parseAc3Bsi(reader: *BitReader)->Ac3Bsi fail
{
    if reader.read(16) != 0x0B77
    {
        fail InvalidFormatError{"AC-3 packet has an invalid sync word"}
    }

    discard reader.read(16)
    var result: #returntype
    result.fscod = reader.read(2)
    let frameSizeCode = reader.read(6)
    if result.fscod >= 3 or frameSizeCode >= 38
    {
        fail InvalidFormatError{"AC-3 packet has a reserved sample-rate or frame-size code"}
    }

    let bitRate = BitRates[frameSizeCode >> 1]
    if not result.fscod
    {
        result.frameSize = 4 * bitRate
    }
    else if result.fscod == 1
    {
        result.frameSize = 2 * ((320 * bitRate) / 147 + (frameSizeCode & 1))
    }
    else
    {
        result.frameSize = 6 * bitRate
    }

    result.bsid = reader.read(5)
    discard reader.read(3)
    if result.bsid > 10
    {
        fail InvalidFormatError{"E-AC-3 packet was sent to the AC-3 decoder"}
    }

    result.acmod   = reader.read(3)
    result.nfchans = FullBandwidthChannels[result.acmod]
    if result.acmod & 1 and result.acmod != 1
    {
        discard reader.read(2)
    }

    if result.acmod & 4
    {
        discard reader.read(2)
    }

    if result.acmod == 2
    {
        discard reader.read(2)
    }

    result.lfeon = reader.read(1) != 0
    discard reader.read(5)
    if reader.read(1)
    {
        discard reader.read(8)
    }

    if reader.read(1)
    {
        discard reader.read(8)
    }

    if reader.read(1)
    {
        reader.skip(7)
    }

    if not result.acmod
    {
        reader.skip(5)
        if reader.read(1)
        {
            reader.skip(8)
        }

        if reader.read(1)
        {
            reader.skip(8)
        }

        if reader.read(1)
        {
            reader.skip(7)
        }
    }

    reader.skip(2)
    if reader.readBit()
    {
        if result.bsid == 6
        {
            reader.skip(14)
        }
        else
        {
            reader.skip(14)
        }
    }

    if reader.readBit()
    {
        if result.bsid == 6
        {
            reader.skip(14)
        }
        else
        {
            reader.skip(14)
        }
    }

    if reader.readBit()
    {
        let additional = reader.read(6) + 1
        reader.skip(cast(u64, additional) * 8)
    }

    if reader.overrun
    {
        fail InvalidFormatError{"AC-3 bit-stream information is truncated"}
    }

    return result
}

// The group code contains three cumulative offsets, each in [-2, 2].
// Coupling can supply a five-bit starting value. Bit 15 distinguishes a valid
// zero tuple from reserved codes and tuples with an out-of-range exponent.
private const Ac3ExponentGroups: [32, 128] u16 = #run
{
    let groupSize = ExponentGroupSize[strategy]
    var previous  = cast(s32, absolute)
    var written   = 0_u32
    if skip
    {
        destination[0] = previous
        written        = 1
    }

    for groups
    {
        let code = reader.read(7)
        if code >= 125
        {
            fail InvalidFormatError{"AC-3 exponent group has a reserved code"}
        }

        const Divisors: [3] u32 = [25, 5, 1]
        for part in 3
        {
            previous += cast(s32, ((code / Divisors[part]) % 5)) - 2
            if previous < 0 or previous > 24
            {
                fail InvalidFormatError{"AC-3 exponent is outside its valid range"}
            }

            for groupSize
            {
                destination[written] = previous
                written += 1
            }
        }

        let first  = cast(s32, decoded & 31)
        let second = cast(s32, (decoded >> 5) & 31)
        previous = cast(s32, (decoded >> 10) & 31)
        if GroupSize == 1
        {
            destination[written]     = first
            destination[written + 1] = second
            destination[written + 2] = previous
        }
        elif GroupSize == 2
        {
            destination[written]     = first
            destination[written + 1] = first
            destination[written + 2] = second
            destination[written + 3] = second
            destination[written + 4] = previous
            destination[written + 5] = previous
        }
        else
        {
            Simd.store(destination + written, Simd.splat(first))
            Simd.store(destination + written + 4, Simd.splat(second))
            Simd.store(destination + written + 8, Simd.splat(previous))
        }

        written += 3 * GroupSize
    }
}

private func decodeExponents(reader: *BitReader, strategy, groups, absolute, skip: u32, destination: [*] s32) fail
{
    switch strategy
    {
    case 1: try decodeExponentGroups'1(reader, groups, absolute, skip, destination)
    case 2: try decodeExponentGroups'2(reader, groups, absolute, skip, destination)
    case 3: try decodeExponentGroups'4(reader, groups, absolute, skip, destination)
    }
}

private func readDelta(reader: *BitReader, delta: *DeltaAllocation) fail
{
    delta.count = reader.read(2) + 1
    if delta.count > 8
    {
        fail InvalidFormatError{"AC-3 delta allocation has too many segments"}
    }

    for segment in delta.count
    {
        delta.offset[segment] = reader.read(5)
        delta.length[segment] = reader.read(4)
        delta.value[segment]  = reader.read(3)
    }
}

private impl Ac3Codec
{
    mtd resetState()
    {
        Memory.set(&.block, 0, #sizeof(.block))
        Memory.set(&.coefficients, 0, #sizeof(.coefficients))
        Memory.set(&.pcm, 0, #sizeof(.pcm))
        for channel in MaxChannels
        {
            .imdct[channel].reset()
        }

        .ditherState = 0x1234ABCD
    }

    mtd ditherValue()->f64
    {
        .ditherState *= #wrap 1_664_525
        .ditherState += #wrap 1_013_904_223
        return (cast(f64, (.ditherState >> 8)) / 16_777_216.0 - 0.5) * 1.4142135623730951
    }

    mtd readCoupling(reader: *BitReader, bsi: const *Ac3Bsi) fail
    {
        let block = &.block
        if reader.readBit()
        {
            block.coupling = reader.readBit() != 0
            if block.coupling
            {
                for channel in bsi.nfchans
                {
                    block.channelCoupled[channel] = reader.read(1) != 0
                }

                if bsi.acmod == 2
                {
                    block.phaseFlagsInUse = reader.read(1) != 0
                }

                block.couplingBegin    = reader.read(4)
                block.couplingEnd      = reader.read(4)
                block.couplingSubbands = 3 + block.couplingEnd - block.couplingBegin
                if block.couplingSubbands > 18
                {
                    fail InvalidFormatError{"AC-3 coupling range is invalid"}
                }

                block.couplingBands       = block.couplingSubbands
                block.couplingBandJoin[0] = false
                var band = 1_u32
                while band < block.couplingSubbands
                {
                    block.couplingBandJoin[band] = reader.read(1) != 0
                    if block.couplingBandJoin[band]
                    {
                        block.couplingBands -= 1
                    }

                    band += 1
                }
            }
            else
            {
                for channel in bsi.nfchans
                {
                    block.channelCoupled[channel] = false
                }
            }
        }

        if not block.coupling
        {
            return
        }

        for channel in bsi.nfchans where block.channelCoupled[channel]
        {
            block.couplingCoordNew[channel] = reader.readBit() != 0
            if block.couplingCoordNew[channel]
            {
                block.couplingMaster[channel] = reader.read(2)
                for band in block.couplingBands
                {
                    block.couplingCoordExp[channel, band]  = reader.read(4)
                    block.couplingCoordMant[channel, band] = reader.read(4)
                }
            }

            var coordinate: f64
            var coordBand = 0_u32
            for subband in block.couplingSubbands
            {
                if not block.couplingBandJoin[subband]
                {
                    let exponent = block.couplingCoordExp[channel, coordBand]
                    let mantissa = block.couplingCoordMant[channel, coordBand]
                    coordinate = exponent == 15 ? cast(f64, mantissa) / 16.0 : cast(f64, (mantissa + 16)) / 32.0
                    coordinate /= Math.pow(2.0, cast(f64, (exponent + 3 * block.couplingMaster[channel])))
                    if channel == 1 and block.phaseFlagsInUse and block.couplingPhase[coordBand]
                    {
                        coordinate = -coordinate
                    }

                    coordBand += 1
                }

                block.couplingCoord[channel, subband] = coordinate
            }
        }

        if bsi.acmod == 2 and
           block.phaseFlagsInUse and
           (block.couplingCoordNew[0] or block.couplingCoordNew[1])
        {
            for band in block.couplingBands
            {
                block.couplingPhase[band] = reader.read(1) != 0
            }
        }
    }

    mtd readExponents(reader: *BitReader, bsi: const *Ac3Bsi) fail
    {
        let block = &.block
        if block.coupling
        {
            block.couplingExpStrategy = reader.read(2)
        }

        for channel in bsi.nfchans
        {
            block.channelExpStrategy[channel] = reader.read(2)
        }

        if bsi.lfeon
        {
            block.lfeExpStrategy = reader.read(1)
        }

        for channel in bsi.nfchans where block.channelExpStrategy[channel] != 0 and not block.channelCoupled[channel]
        {
            let bandwidth = reader.read(6)
            if bandwidth > MaxChannelBandwidthCode
            {
                fail InvalidFormatError{"AC-3 channel bandwidth code is reserved"}
            }

            block.channelBandwidth[channel] = bandwidth
        }

        if block.coupling
        {
            block.couplingStart       = cast(s32, block.couplingBegin) * 12 + 37
            block.couplingEndMantissa = cast(s32, (block.couplingEnd + 3)) * 12 + 37
            if block.couplingExpStrategy
            {
                let divisor  = cast(s32, (3 * ExponentGroupSize[block.couplingExpStrategy]))
                let groups   = cast(u32, ((block.couplingEndMantissa - block.couplingStart) / divisor))
                let absolute = reader.read(4) << 1
                try decodeExponents(reader, block.couplingExpStrategy, groups, absolute, 0, &block.couplingExponents)
            }
        }

        for channel in bsi.nfchans where block.channelExpStrategy[channel] != 0
        {
            block.channelEnd[channel] = block.channelCoupled[channel] ? 37 + cast(s32, (12 * block.couplingBegin)) : 37 + 3 * cast(s32, (block.channelBandwidth[channel] + 12))
            let groupSize = cast(s32, ExponentGroupSize[block.channelExpStrategy[channel]])
            let groups    = cast(u32, ((block.channelEnd[channel] - 1 + 3 * groupSize - 1) / (3 * groupSize)))
            let absolute  = reader.read(4)
            try decodeExponents(reader, block.channelExpStrategy[channel], groups, absolute, 1, &block.channelExponents[channel, 0])
            discard reader.read(2)
        }

        if bsi.lfeon and block.lfeExpStrategy
        {
            let absolute = reader.read(4)
            try decodeExponents(reader, 1, 2, absolute, 1, &block.lfeExponents)
        }
    }

    mtd readAllocation(reader: *BitReader, bsi: const *Ac3Bsi, blockIndex: u32, couplingChanged: bool) fail
    {
        let block = &.block

        // An unchanged allocation is valid only within the current sync frame.
        var refreshAll      = not blockIndex
        var refreshCoupling = couplingChanged
        if reader.readBit()
        {
            refreshAll          = true
            block.slowDecayCode = reader.read(2)
            block.fastDecayCode = reader.read(2)
            block.slowGainCode  = reader.read(2)
            block.dbPerBitCode  = reader.read(2)
            block.floorCode     = reader.read(3)
        }
        else if not blockIndex
        {
            fail InvalidFormatError{"first AC-3 block omits bit-allocation parameters"}
        }

        if reader.readBit()
        {
            refreshAll      = true
            block.coarseSnr = reader.read(6)
            if block.coupling
            {
                block.couplingFineSnr  = reader.read(4)
                block.couplingFastGain = reader.read(3)
            }

            for channel in bsi.nfchans
            {
                block.channelFineSnr[channel]  = reader.read(4)
                block.channelFastGain[channel] = reader.read(3)
            }

            if bsi.lfeon
            {
                block.lfeFineSnr  = reader.read(4)
                block.lfeFastGain = reader.read(3)
            }
        }
        else if not blockIndex
        {
            fail InvalidFormatError{"first AC-3 block omits signal-to-noise offsets"}
        }

        if block.coupling and reader.readBit()
        {
            refreshCoupling        = true
            block.couplingFastLeak = reader.read(3)
            block.couplingSlowLeak = reader.read(3)
        }

        if reader.readBit()
        {
            if block.coupling
            {
                block.couplingDelta.mode = reader.read(2)
            }

            for channel in bsi.nfchans
            {
                block.channelDelta[channel].mode = reader.read(2)
            }

            if block.coupling and block.couplingDelta.mode == 1
            {
                try readDelta(reader, &block.couplingDelta)
            }

            for channel in bsi.nfchans where block.channelDelta[channel].mode == 1
            {
                try readDelta(reader, &block.channelDelta[channel])
            }
        }
        else if not blockIndex
        {
            block.couplingDelta.mode = 2
            for channel in bsi.nfchans
            {
                block.channelDelta[channel].mode = 2
            }
        }

        let slowDecay = SLOW_DECAY[block.slowDecayCode]
        let fastDecay = FAST_DECAY[block.fastDecayCode]
        let slowGain  = SLOW_GAIN[block.slowGainCode]
        let dbKnee    = DB_PER_BIT[block.dbPerBitCode]
        let floor     = FLOOR[block.floorCode]
        for channel in bsi.nfchans where refreshAll or block.channelExpStrategy[channel]
        {
            let delta = &block.channelDelta[channel]
            try bitAllocation(bsi.fscod, 0, block.channelEnd[channel], &block.channelExponents[channel, 0], FAST_GAIN[block.channelFastGain[channel]], slowGain, fastDecay, slowDecay, dbKnee, floor, ((cast(s32, block.coarseSnr) - 15) * 16 + cast(s32, block.channelFineSnr[channel])) * 4, 0, 0, delta, &block.channelBap[channel, 0], &.mantissaGains.channel[channel, 0])
        }

        if block.coupling
        {
            try bitAllocation(bsi.fscod, block.couplingStart, block.couplingEndMantissa, &block.couplingExponents, FAST_GAIN[block.couplingFastGain], slowGain, fastDecay, slowDecay, dbKnee, floor, ((cast(s32, block.coarseSnr) - 15) * 16 + cast(s32, block.couplingFineSnr)) * 4, cast(s32, (block.couplingFastLeak << 8)) + 768, cast(s32, (block.couplingSlowLeak << 8)) + 768, &block.couplingDelta, &block.couplingBap)
        }

        if bsi.lfeon
        {
            try bitAllocation(bsi.fscod, 0, 7, &block.lfeExponents, FAST_GAIN[block.lfeFastGain], slowGain, fastDecay, slowDecay, dbKnee, floor, ((cast(s32, block.coarseSnr) - 15) * 16 + cast(s32, block.lfeFineSnr)) * 4, 0, 0, null, &block.lfeBap)
        }
    }

    mtd preparePacketBits(packet: const [..] u8)->BitReader
    {
        if not packet.count or packet.count > MaxAc3FrameBytes do
            return BitReader.create(packet.buffer, packet.count)

            if block.coupling and block.channelCoupled[channel] and not couplingRead
            {
                for bin in block.couplingSubbands * 12
                {
                    couplingMantissas[bin] = mantissas.get(block.couplingBap[bin]) * Math.pow(2.0, -cast(f64, block.couplingExponents[bin]))
                }

    mtd readMantissas(reader: *BitReader, bsi: const *Ac3Bsi, coefficients: [*] f64)
    {
        let block  = &.block
        let copied = reader.data == cast(const [*] u8, &.packetCopy[0])
        if copied and not reader.overrun
        {
            // Reads stay within the padded allocation. The logical limit is
            // checked once at the end of the block, before any PCM is emitted.
            readPreparedMantissas'(false, true)(reader, block, bsi.nfchans, bsi.lfeon, coefficients, &.mantissaGains, &.dither)
            reader.overrun = reader.bitPos > reader.size * 8
        }
        else
        {
            readPreparedMantissas'(true, true)(reader, block, bsi.nfchans, bsi.lfeon, coefficients, &.mantissaGains, &.dither)
        }

        for band in block.rematrixCount where block.rematrix[band]
        {
            let begin = REMATRIX_BANDS[band]
            var end   = REMATRIX_BANDS[band + 1]
            if block.coupling
            {
                end = Math.min(end, 36 + cast(s32, block.couplingBegin) * 12)
            }

            var bin = begin
            while bin < end
            {
                let left  = coefficients[bin]
                let right = coefficients[SamplesPerBlock + bin]
                coefficients[bin] = left + right
                coefficients[SamplesPerBlock + bin] = left - right
                bin += 1
            }
        }
    }

    #[Swag.Inline]
    mtd parseBlock(reader: *BitReader, bsi: const *Ac3Bsi, blockIndex: u32, coefficients: [*] f64) fail
    {
        let block = &.block
        for channel in bsi.nfchans
        {
            block.blockSwitch[channel] = reader.read(1) != 0
        }

        for channel in bsi.nfchans
        {
            block.dither[channel] = reader.read(1) != 0
        }

        if reader.read(1)
        {
            reader.skip(8)
        }

        if not bsi.acmod and reader.read(1)
        {
            reader.skip(8)
        }

        let hadCoupling   = block.coupling
        let previousStart = block.couplingStart
        let previousEnd   = block.couplingEndMantissa
        try .readCoupling(reader, bsi)
        if bsi.acmod == 2 and reader.readBit()
        {
            var rematrixCount = 4_u32
            if block.coupling
            {
                if block.couplingBegin > 2
                {
                    rematrixCount = 4
                }
                else if block.couplingBegin > 0
                {
                    rematrixCount = 3
                }
                else
                {
                    rematrixCount = 2
                }
            }

            block.rematrixCount = rematrixCount
            for band in block.rematrixCount
            {
                block.rematrix[band] = reader.read(1) != 0
            }
        }

        try .readExponents(reader, bsi)
        let couplingChanged = not hadCoupling or
                              previousStart != block.couplingStart or
                              previousEnd != block.couplingEndMantissa
        try .readAllocation(reader, bsi, blockIndex, couplingChanged)
        if reader.readBit()
        {
            let skipBytes = reader.read(9)
            reader.skip(cast(u64, skipBytes) * 8)
        }

        .readMantissas(reader, bsi)
        if reader.overrun
        {
            fail InvalidFormatError{"AC-3 audio block is truncated"}
        }

        for channel in bsi.nfchans
        {
            .imdct[channel].process(&.coefficients[channel, 0], block.blockSwitch[channel], &.pcm[channel, 0])
        }

        switch channels
        {
        case 3:
            .surroundImdct.processMapped'3(&.imdct, coefficients, blockSwitch, bsi.acmod, bsi.nfchans, bsi.lfeon, destination)
            return

        case 4:
            .surroundImdct.processMapped'4(&.imdct, coefficients, blockSwitch, bsi.acmod, bsi.nfchans, bsi.lfeon, destination)
            return

        case 5:
            .surroundImdct.processMapped'5(&.imdct, coefficients, blockSwitch, bsi.acmod, bsi.nfchans, bsi.lfeon, destination)
            return
        }

        .stereoImdct.restore(&.imdct)
        for channel in channels
        {
            .imdct[bsi.nfchans].process(&.coefficients[bsi.nfchans, 0], false, &.pcm[bsi.nfchans, 0])
        }
    }

    mtd sourceChannel(destination: u32, bsi: const *Ac3Bsi)->u32 => dolbySourceChannel(destination, bsi.acmod, bsi.nfchans, bsi.lfeon)

    mtd readFrameHeader(reader: *BitReader, packetSize: u64)->Ac3Bsi fail
    {
        var reader = BitReader.create(packet.buffer, packet.count)
        let bsi    = try parseAc3Bsi(&reader)
        if bsi.frameSize != packet.count
        {
            fail InvalidFormatError{"AC-3 packet size does not match its sync-frame header"}
        }

        if SampleRates[bsi.fscod] != .sampleRate
        {
            fail InvalidFormatError{"AC-3 packet sample rate differs from its container track"}
        }

        let decodedChannels = bsi.nfchans + (bsi.lfeon ? 1 : 0)
        if decodedChannels != .channels
        {
            fail InvalidFormatError{"AC-3 packet channel layout differs from its container track"}
        }

        return bsi
    }

    mtd decodeFrame(packet: const [..] u8, destination: [*] s16) fail
    {
        var reader = .preparePacketBits(packet)
        let bsi    = try .readFrameHeader(&reader, packet.count)
        for blockIndex in BlocksPerAc3Frame
        {
            try .parseBlock(&reader, &bsi, blockIndex, &.coefficients[0, 0])
            .synthesizeBlock(&bsi, &.block.blockSwitch, &.coefficients[0, 0], destination + blockIndex * SamplesPerBlock * .channels, .channels)
        }
    }
}

impl IPacketCodec for Ac3Codec
{
    mtd impl canDecode(encoding: SoundFileEncoding)->bool => encoding == .Ac3

    mtd impl initialize(_: const [..] u8, sampleRateHz, channels: u32) fail
    {
        if not sampleRateHz or not channels or channels > MaxChannels
        {
            fail BadParameterError{"AC-3 audio needs one to six channels and a non-zero sample rate"}
        }

        .sampleRate = sampleRateHz
        .channels   = channels
        .resetState()
    }

    mtd impl reset() => .resetState()

    mtd impl decodePacket(destination: [*] void, destinationSize: u64, packet: const [..] u8)->u64 fail
    {
        let required = cast(u64, BlocksPerAc3Frame) * SamplesPerBlock * .channels * #sizeof(s16)
        if destinationSize < required
        {
            fail BadParameterError{"AC-3 destination buffer is too small"}
        }

        try .decodeFrame(packet, cast([*] s16, destination))
        return required
    }
}

// The packet parser owns dither and bit allocation. The synthesis worker owns
// overlap state and consumes completed batches in input order.
private struct Ac3PreparedFrame
{
    bsi:         Ac3Bsi
    blockSwitch: [BlocksPerAc3Frame, MaxFullBandwidthChannels] bool
}

internal const Ac3PipelineFrames  = BlocksPerAc3Frame * SamplesPerBlock
private const Ac3PipelineCapacity = 16'u64

internal struct Ac3DecodeBatch
{
    private headers:     [Ac3PipelineCapacity] Ac3PreparedFrame
    private spectra:     Array'f64
    private packetLimit: u64
    pcm:                 Array's16
    count:               u64
}

internal impl Ac3DecodeBatch
{
    mtd initialize(channels: u32)
    {
        // Keep the maximum batch footprint independent of channel count.
        .packetLimit = Math.min(Ac3PipelineCapacity, 32'u64 / channels)
        let capacity = .packetLimit * Ac3PipelineFrames * channels
        .spectra.reserve(capacity)
        .pcm.reserve(capacity)
    }

    mtd const capacity()->u64 => .packetLimit
}

internal struct Ac3DecodePipeline
{
    private codec: Ac3Codec
}

internal func isNativeAc3Codec(type: const *Swag.TypeInfoStruct)->bool => type == #typeof(Ac3Codec)

internal impl Ac3DecodePipeline
{
    mtd initialize(sampleRate, channels: u32)
    {
        .codec.sampleRate = sampleRate
        .codec.channels   = channels
        .codec.resetState()
    }

    mtd decode(packet: const [..] u8, output: [*] s16) fail
    {
        try .codec.decodeFrame(packet, output)
    }

    mtd(FixedChannels: u32) prepareFrame(batch: *Ac3DecodeBatch, packet: const [..] u8) fail
    {
        var reader = .codec.preparePacketBits(packet)
        let header = &batch.headers[batch.count]
        header.bsi = try .codec.readFrameHeader(&reader, packet.count)
        let channels = FixedChannels ? FixedChannels : .codec.channels
        let spectra  = batch.spectra.storage() + batch.count * Ac3PipelineFrames * channels
        for blockIndex in BlocksPerAc3Frame
        {
            let destination = spectra + blockIndex * channels * SamplesPerBlock
            try .codec.parseBlock(&reader, &header.bsi, blockIndex, destination)
            for channel in header.bsi.nfchans do
                header.blockSwitch[blockIndex, channel] = .codec.block.blockSwitch[channel]
        }

        batch.count += 1
    }

    mtd prepare(batch: *Ac3DecodeBatch, packet: const [..] u8) fail
    {
        if .codec.channels == 2 do
            try .prepareFrame'2(batch, packet)
        else do
            try .prepareFrame'0(batch, packet)
    }

    mtd(FixedChannels: u32) synthesizeFrames(batch: *Ac3DecodeBatch)
    {
        let channels = FixedChannels ? FixedChannels : .codec.channels
        let spectra  = batch.spectra.storage()
        let pcm      = batch.pcm.storage()
        for packet in batch.count
        {
            let header = &batch.headers[packet]
            for blockIndex in BlocksPerAc3Frame
            {
                let offset       = (packet * Ac3PipelineFrames + blockIndex * SamplesPerBlock) * channels
                let coefficients = spectra + offset
                let switches     = cast(const *[MaxFullBandwidthChannels] bool, &header.blockSwitch[blockIndex, 0])
                .codec.synthesizeBlock(&header.bsi, switches, coefficients, pcm + offset, channels)
            }
        }
    }

    mtd synthesize(batch: *Ac3DecodeBatch)
    {
        if .codec.channels == 2 do
            .synthesizeFrames'2(batch)
        else do
            .synthesizeFrames'0(batch)
    }
}

// What one sync frame says about the stream it belongs to.
internal struct FrameInfo
{
    frameBytes:  u64
    sampleRate:  u32
    channels:    u32
    speakerMask: u32
    frames:      u32     // Sample frames the frame decodes to.
}

// The channels each `acmod` names, before the low frequency effects channel is counted.
private const AcmodChannels: [8] u32 = [2, 1, 2, 3, 3, 4, 4, 5]

// Reads the shape of one AC-3 sync frame without decoding it, clause 5.3.
internal func ac3FrameInfo(packet: const [..] u8)->FrameInfo fail
{
    const BitRates: [19] u32 = [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512, 576, 640]
    const Rates:    [3] u32  = [48_000, 44_100, 32_000]

    if packet.count < 7
    {
        fail InvalidFormatError{"AC-3 packet header is truncated"}
    }

    if packet[0] != 0x0B or packet[1] != 0x77
    {
        fail InvalidFormatError{"AC-3 packet has no sync word"}
    }

    let fscod    = cast(u32, (packet[4] >> 6)) & 3
    let sizeCode = cast(u32, packet[4]) & 0x3F
    if fscod >= 3 or sizeCode >= 38
    {
        fail InvalidFormatError{"AC-3 frame states a reserved sampling frequency or size"}
    }

    var result: #returntype
    result.sampleRate = Rates[cast(u64, fscod)]
    result.frames     = 1536

    let bitRate = cast(u64, BitRates[cast(u64, sizeCode) >> 1])
    if not fscod
    {
        result.frameBytes = 4 * bitRate
    }
    else if fscod == 1
    {
        result.frameBytes = 2 * ((320 * bitRate) / 147 + cast(u64, (sizeCode & 1)))
    }
    else
    {
        result.frameBytes = 6 * bitRate
    }

    // The channel mode and the low frequency effects flag follow the bit stream identification.
    let acmod = cast(u32, (packet[6] >> 5)) & 7
    var skip  = 3_u32
    if (acmod & 1) != 0 and acmod != 1
    {
        skip += 2
    }

    if (acmod & 4) != 0
    {
        skip += 2
    }

    if acmod == 2
    {
        skip += 2
    }

    let lfe = (cast(u32, packet[6]) >> (7 - skip)) & 1
    result.channels    = AcmodChannels[cast(u64, acmod)] + lfe
    result.speakerMask = dolbySpeakerMask(acmod, lfe != 0)
    return result
}

// Returns the number of sample frames one AC-3 sync frame decodes to.
//
// Every AC-3 frame carries six blocks of 256 samples, so only the sync word needs checking.
internal func ac3PacketFrameCount(packet: const [..] u8)->u32 fail
{
    if packet.count < 7
    {
        fail InvalidFormatError{"AC-3 packet header is truncated"}
    }

    if packet[0] != 0x0B or packet[1] != 0x77
    {
        fail InvalidFormatError{"AC-3 packet has no sync word"}
    }

    return 1536
}

#init
{
    initializeDolbyCore()
    registerPacketCodec!{Ac3Codec}()
}
