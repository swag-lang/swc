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

private struct Ac3Codec
{
    using base: Codec

    sampleRate:   u32
    channels:     u32
    block:        Ac3Block
    imdct:        [MaxChannels] Imdct
    coefficients: [MaxChannels, SamplesPerBlock] f64
    pcm:          [MaxChannels, SamplesPerBlock] f64
    ditherState:  u32 = 0x1234ABCD
}

private func parseAc3Bsi(reader: *BitReader)->Ac3Bsi fail
{
    if reader.read(16) != 0x0B77 do
        fail InvalidFormatError{"AC-3 packet has an invalid sync word"}
    discard reader.read(16)
    var result: retval
    result.fscod = reader.read(2)
    let frameSizeCode = reader.read(6)
    if result.fscod >= 3 or frameSizeCode >= 38 do
        fail InvalidFormatError{"AC-3 packet has a reserved sample-rate or frame-size code"}
    let bitRate = BitRates[frameSizeCode >> 1]
    if !result.fscod do
        result.frameSize = 4 * bitRate
    elif result.fscod == 1 do
        result.frameSize = 2 * ((320 * bitRate) / 147 + (frameSizeCode & 1))
    else do
        result.frameSize = 6 * bitRate
    result.bsid = reader.read(5)
    discard reader.read(3)
    if result.bsid > 10 do
        fail InvalidFormatError{"E-AC-3 packet was sent to the AC-3 decoder"}
    result.acmod   = reader.read(3)
    result.nfchans = FullBandwidthChannels[result.acmod]
    if result.acmod & 1 and result.acmod != 1 do
        discard reader.read(2)
    if result.acmod & 4 do
        discard reader.read(2)
    if result.acmod == 2 do
        discard reader.read(2)
    result.lfeon = reader.read(1) != 0
    discard reader.read(5)
    if reader.read(1) do
        discard reader.read(8)
    if reader.read(1) do
        discard reader.read(8)
    if reader.read(1) do
        reader.skip(7)
    if !result.acmod
    {
        reader.skip(5)
        if reader.read(1) do
            reader.skip(8)
        if reader.read(1) do
            reader.skip(8)
        if reader.read(1) do
            reader.skip(7)
    }

    reader.skip(2)
    if reader.read(1)
    {
        if result.bsid == 6 do
            reader.skip(14)
        else do
            reader.skip(14)
    }

    if reader.read(1)
    {
        if result.bsid == 6 do
            reader.skip(14)
        else do
            reader.skip(14)
    }

    if reader.read(1)
    {
        let additional = reader.read(6) + 1
        reader.skip(cast(u64) additional * 8)
    }

    if reader.overrun do
        fail InvalidFormatError{"AC-3 bit-stream information is truncated"}
    return result
}

private func decodeExponents(reader: *BitReader, strategy, groups, absolute, skip: u32, destination: [*] s32) fail
{
    let groupSize = ExponentGroupSize[strategy]
    var previous  = cast(s32) absolute
    var written   = 0'u32
    if skip
    {
        destination[0] = previous
        written        = 1
    }

    for group in groups
    {
        discard group
        let code = reader.read(7)
        if code >= 125 do
            fail InvalidFormatError{"AC-3 exponent group has a reserved code"}
        const Divisors: [3] u32 = [25, 5, 1]
        for part in 3
        {
            previous += cast(s32) ((code / Divisors[part]) % 5) - 2
            if previous < 0 or previous > 24 do
                fail InvalidFormatError{"AC-3 exponent is outside its valid range"}
            for repeated in groupSize
            {
                discard repeated
                destination[written] = previous
                written              += 1
            }
        }
    }
}

private func readDelta(reader: *BitReader, delta: *DeltaAllocation) fail
{
    delta.count = reader.read(2) + 1
    if delta.count > 8 do
        fail InvalidFormatError{"AC-3 delta allocation has too many segments"}
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
        for channel in MaxChannels do
            .imdct[channel].reset()
        .ditherState = 0x1234ABCD
    }

    mtd ditherValue()->f64
    {
        .ditherState *= #wrap 1_664_525
        .ditherState += #wrap 1_013_904_223
        return (cast(f64) (.ditherState >> 8) / 16_777_216.0 - 0.5) * 1.4142135623730951
    }

    mtd readCoupling(reader: *BitReader, bsi: const *Ac3Bsi) fail
    {
        let block = &.block
        if reader.read(1)
        {
            block.coupling = reader.read(1) != 0
            if block.coupling
            {
                for channel in bsi.nfchans do
                    block.channelCoupled[channel] = reader.read(1) != 0
                if bsi.acmod == 2 do
                    block.phaseFlagsInUse = reader.read(1) != 0
                block.couplingBegin    = reader.read(4)
                block.couplingEnd      = reader.read(4)
                block.couplingSubbands = 3 + block.couplingEnd - block.couplingBegin
                if block.couplingSubbands > 18 do
                    fail InvalidFormatError{"AC-3 coupling range is invalid"}
                block.couplingBands       = block.couplingSubbands
                block.couplingBandJoin[0] = false
                var band = 1'u32
                while band < block.couplingSubbands
                {
                    block.couplingBandJoin[band] = reader.read(1) != 0
                    if block.couplingBandJoin[band] do
                        block.couplingBands -= 1
                    band += 1
                }
            }
            else
            {
                for channel in bsi.nfchans do
                    block.channelCoupled[channel] = false
            }
        }

        if !block.coupling do
            return
        for channel in bsi.nfchans where block.channelCoupled[channel]
        {
            block.couplingCoordNew[channel] = reader.read(1) != 0
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
            var coordBand = 0'u32
            for subband in block.couplingSubbands
            {
                if !block.couplingBandJoin[subband]
                {
                    let exponent = block.couplingCoordExp[channel, coordBand]
                    let mantissa = block.couplingCoordMant[channel, coordBand]
                    coordinate = exponent == 15 ? cast(f64) mantissa / 16.0 : cast(f64) (mantissa + 16) / 32.0
                    coordinate /= Math.pow(2.0, cast(f64) (exponent + 3 * block.couplingMaster[channel]))
                    if channel == 1 and block.phaseFlagsInUse and block.couplingPhase[coordBand] do
                        coordinate = -coordinate
                    coordBand += 1
                }

                block.couplingCoord[channel, subband] = coordinate
            }
        }

        if bsi.acmod == 2 and block.phaseFlagsInUse and (block.couplingCoordNew[0] or block.couplingCoordNew[1])
        {
            for band in block.couplingBands do
                block.couplingPhase[band] = reader.read(1) != 0
        }
    }

    mtd readExponents(reader: *BitReader, bsi: const *Ac3Bsi) fail
    {
        let block = &.block
        if block.coupling do
            block.couplingExpStrategy = reader.read(2)
        for channel in bsi.nfchans do
            block.channelExpStrategy[channel] = reader.read(2)
        if bsi.lfeon do
            block.lfeExpStrategy = reader.read(1)

        for channel in bsi.nfchans where block.channelExpStrategy[channel] != 0 and !block.channelCoupled[channel] do
            block.channelBandwidth[channel] = reader.read(6)

        if block.coupling
        {
            block.couplingStart       = cast(s32) block.couplingBegin * 12 + 37
            block.couplingEndMantissa = cast(s32) (block.couplingEnd + 3) * 12 + 37
            if block.couplingExpStrategy
            {
                let divisor  = cast(s32) (3 * ExponentGroupSize[block.couplingExpStrategy])
                let groups   = cast(u32) ((block.couplingEndMantissa - block.couplingStart) / divisor)
                let absolute = reader.read(4) << 1
                try decodeExponents(reader, block.couplingExpStrategy, groups, absolute, 0, &block.couplingExponents)
            }
        }

        for channel in bsi.nfchans where block.channelExpStrategy[channel] != 0
        {
            block.channelEnd[channel] = block.channelCoupled[channel] ? 37 + cast(s32) (12 * block.couplingBegin) : 37 + 3 * cast(s32) (block.channelBandwidth[channel] + 12)
            let groupSize = cast(s32) ExponentGroupSize[block.channelExpStrategy[channel]]
            let groups    = cast(u32) ((block.channelEnd[channel] - 1 + 3 * groupSize - 1) / (3 * groupSize))
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

    mtd readAllocation(reader: *BitReader, bsi: const *Ac3Bsi, blockIndex: u32) fail
    {
        let block = &.block
        if reader.read(1)
        {
            block.slowDecayCode = reader.read(2)
            block.fastDecayCode = reader.read(2)
            block.slowGainCode  = reader.read(2)
            block.dbPerBitCode  = reader.read(2)
            block.floorCode     = reader.read(3)
        }
        elif !blockIndex do
            fail InvalidFormatError{"first AC-3 block omits bit-allocation parameters"}

        if reader.read(1)
        {
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
        elif !blockIndex do
            fail InvalidFormatError{"first AC-3 block omits signal-to-noise offsets"}

        if block.coupling and reader.read(1)
        {
            block.couplingFastLeak = reader.read(3)
            block.couplingSlowLeak = reader.read(3)
        }

        if reader.read(1)
        {
            if block.coupling do
                block.couplingDelta.mode = reader.read(2)
            for channel in bsi.nfchans do
                block.channelDelta[channel].mode = reader.read(2)
            if block.coupling and block.couplingDelta.mode == 1 do
                try readDelta(reader, &block.couplingDelta)
            for channel in bsi.nfchans where block.channelDelta[channel].mode == 1 do
                try readDelta(reader, &block.channelDelta[channel])
        }
        elif !blockIndex
        {
            block.couplingDelta.mode = 2
            for channel in bsi.nfchans do
                block.channelDelta[channel].mode = 2
        }

        let slowDecay = SLOW_DECAY[block.slowDecayCode]
        let fastDecay = FAST_DECAY[block.fastDecayCode]
        let slowGain  = SLOW_GAIN[block.slowGainCode]
        let dbKnee    = DB_PER_BIT[block.dbPerBitCode]
        let floor     = FLOOR[block.floorCode]
        for channel in bsi.nfchans
        {
            let delta = &block.channelDelta[channel]
            bitAllocation(bsi.fscod, 0, block.channelEnd[channel], &block.channelExponents[channel, 0], FAST_GAIN[block.channelFastGain[channel]], slowGain, fastDecay, slowDecay, dbKnee, floor, ((cast(s32) block.coarseSnr - 15) * 16 + cast(s32) block.channelFineSnr[channel]) * 4, 0, 0, delta, &block.channelBap[channel, 0])
        }

        if block.coupling do
            bitAllocation(bsi.fscod, block.couplingStart, block.couplingEndMantissa, &block.couplingExponents, FAST_GAIN[block.couplingFastGain], slowGain, fastDecay, slowDecay, dbKnee, floor, ((cast(s32) block.coarseSnr - 15) * 16 + cast(s32) block.couplingFineSnr) * 4, cast(s32) (block.couplingFastLeak << 8) + 768, cast(s32) (block.couplingSlowLeak << 8) + 768, &block.couplingDelta, &block.couplingBap)
        if bsi.lfeon do
            bitAllocation(bsi.fscod, 0, 7, &block.lfeExponents, FAST_GAIN[block.lfeFastGain], slowGain, fastDecay, slowDecay, dbKnee, floor, ((cast(s32) block.coarseSnr - 15) * 16 + cast(s32) block.lfeFineSnr) * 4, 0, 0, null, &block.lfeBap)
    }

    mtd readMantissas(reader: *BitReader, bsi: const *Ac3Bsi)
    {
        let block        = &.block
        var mantissas    = MantissaReader.create(reader)
        var couplingRead = false
        var couplingMantissas: [216] f64
        for channel in bsi.nfchans
        {
            Memory.set(&.coefficients[channel, 0], 0, SamplesPerBlock * #sizeof(f64))
            for bin in cast(u64) block.channelEnd[channel]
            {
                let exponent = block.channelExponents[channel, bin]
                let value    = block.channelBap[channel, bin] or !block.dither[channel] ? mantissas.get(block.channelBap[channel, bin]) : .ditherValue()
                .coefficients[channel, bin] = value * Math.pow(2.0, -cast(f64) exponent)
            }

            if block.coupling and block.channelCoupled[channel] and !couplingRead
            {
                for bin in block.couplingSubbands * 12 do
                    couplingMantissas[bin] = mantissas.get(block.couplingBap[bin]) * Math.pow(2.0, -cast(f64) block.couplingExponents[bin])
                couplingRead = true
            }
        }

        if bsi.lfeon
        {
            let channel = bsi.nfchans
            Memory.set(&.coefficients[channel, 0], 0, SamplesPerBlock * #sizeof(f64))
            for bin in 7 do
                .coefficients[channel, bin] = mantissas.get(block.lfeBap[bin]) * Math.pow(2.0, -cast(f64) block.lfeExponents[bin])
        }

        if block.coupling
        {
            for channel in bsi.nfchans where block.channelCoupled[channel]
            {
                for subband in block.couplingSubbands
                {
                    for bin in 12
                    {
                        let source = subband * 12 + bin
                        var value  = couplingMantissas[source]
                        if !value and block.dither[channel] do
                            value = .ditherValue() * Math.pow(2.0, -cast(f64) block.couplingExponents[source])
                        let destination = (subband + block.couplingBegin) * 12 + bin + 37
                        .coefficients[channel, destination] = value * block.couplingCoord[channel, subband] * 8.0
                    }
                }
            }
        }

        for band in block.rematrixCount where block.rematrix[band]
        {
            let begin = REMATRIX_BANDS[band]
            var end   = REMATRIX_BANDS[band + 1]
            if block.coupling do
                end = Math.min(end, 36 + cast(s32) block.couplingBegin * 12)
            var bin = begin
            while bin < end
            {
                let left  = .coefficients[0, bin]
                let right = .coefficients[1, bin]
                .coefficients[0, bin] = left + right
                .coefficients[1, bin] = left - right
                bin += 1
            }
        }
    }

    mtd decodeBlock(reader: *BitReader, bsi: const *Ac3Bsi, blockIndex: u32) fail
    {
        let block = &.block
        for channel in bsi.nfchans do
            block.blockSwitch[channel] = reader.read(1) != 0
        for channel in bsi.nfchans do
            block.dither[channel] = reader.read(1) != 0
        if reader.read(1) do
            reader.skip(8)
        if !bsi.acmod and reader.read(1) do
            reader.skip(8)

        try .readCoupling(reader, bsi)
        if bsi.acmod == 2 and reader.read(1)
        {
            block.rematrixCount = block.coupling ? (block.couplingBegin > 2 ? 4 : block.couplingBegin > 0 ? 3 : 2) : 4
            for band in block.rematrixCount do
                block.rematrix[band] = reader.read(1) != 0
        }

        try .readExponents(reader, bsi)
        try .readAllocation(reader, bsi, blockIndex)
        if reader.read(1)
        {
            let skipBytes = reader.read(9)
            reader.skip(cast(u64) skipBytes * 8)
        }

        .readMantissas(reader, bsi)
        if reader.overrun do
            fail InvalidFormatError{"AC-3 audio block is truncated"}

        for channel in bsi.nfchans do
            .imdct[channel].process(&.coefficients[channel, 0], block.blockSwitch[channel], &.pcm[channel, 0])
        if bsi.lfeon do
            .imdct[bsi.nfchans].process(&.coefficients[bsi.nfchans, 0], false, &.pcm[bsi.nfchans, 0])
    }

    mtd sourceChannel(destination: u32, bsi: const *Ac3Bsi)->u32
    {
        return dolbySourceChannel(destination, bsi.acmod, bsi.nfchans, bsi.lfeon)
    }

    mtd decodeFrame(packet: const [..] u8, destination: [*] s16) fail
    {
        var reader = BitReader.create(@dataof(packet), @countof(packet))
        let bsi    = try parseAc3Bsi(&reader)
        if bsi.frameSize != @countof(packet) do
            fail InvalidFormatError{"AC-3 packet size does not match its sync-frame header"}
        if SampleRates[bsi.fscod] != .sampleRate do
            fail InvalidFormatError{"AC-3 packet sample rate differs from its container track"}
        let decodedChannels = bsi.nfchans + (bsi.lfeon ? 1 : 0)
        if decodedChannels != .channels do
            fail InvalidFormatError{"AC-3 packet channel layout differs from its container track"}

        for blockIndex in BlocksPerAc3Frame
        {
            try .decodeBlock(&reader, &bsi, blockIndex)
            for frame in SamplesPerBlock
            {
                for channel in .channels
                {
                    let source = .sourceChannel(channel, &bsi)
                    let scaled = Math.clamp(.pcm[source, frame] * 32767.0, -32768.0, 32767.0)
                    destination[(blockIndex * SamplesPerBlock + frame) * .channels + channel] = cast(s16) scaled
                }
            }
        }
    }
}

impl IPacketCodec for Ac3Codec
{
    mtd impl canDecode(encoding: SoundFileEncoding)->bool => encoding == .Ac3

    mtd impl initialize(config: const [..] u8, sampleRateHz, channels: u32) fail
    {
        discard config
        if !sampleRateHz or !channels or channels > MaxChannels do
            fail BadParameterError{"AC-3 audio needs one to six channels and a non-zero sample rate"}
        .sampleRate = sampleRateHz
        .channels   = channels
        .resetState()
    }

    mtd impl reset() => .resetState()

    mtd impl decodePacket(destination: [*] void, destinationSize: u64, packet: const [..] u8)->u64 fail
    {
        let required = cast(u64) BlocksPerAc3Frame * SamplesPerBlock * .channels * #sizeof(s16)
        if destinationSize < required do
            fail BadParameterError{"AC-3 destination buffer is too small"}
        try .decodeFrame(packet, cast([*] s16) destination)
        return required
    }
}

// Returns the number of sample frames one AC-3 sync frame decodes to.
//
// Every AC-3 frame carries six blocks of 256 samples, so only the sync word needs checking.
internal func ac3PacketFrameCount(packet: const [..] u8)->u32 fail
{
    if @countof(packet) < 7 do
        fail InvalidFormatError{"AC-3 packet header is truncated"}
    if packet[0] != 0x0B or packet[1] != 0x77 do
        fail InvalidFormatError{"AC-3 packet has no sync word"}
    return 1536
}

#init
{
    initializeDolbyCore()
    registerPacketCodec'Ac3Codec()
}
