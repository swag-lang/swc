//! Format: Dolby Digital Plus (E-AC-3) packet decoder component.
//! Supported: Common independent E-AC-3 substreams through 5.1 channels with standard transform, coupling, exponent, bit-allocation, and LFE paths.
//! Not supported: Dependent substreams, Adaptive Hybrid Transform, enhanced coupling, spectral extension, transient processing, attenuation data, and mixing metadata.
//! Role: This file owns E-AC-3 frame syntax, audio blocks, coupling, and packet dispatch.
//
#global namespace Dolby

using Core, Core.Errors, Core.Math

// Table E2.10: one five-bit frame strategy expands to six block strategies.
private const Eac3FrameExponentStrategies: [32, 6] u32 = [
    1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 3, 1, 0, 0, 0, 2, 0, 1, 0, 0, 0, 3, 3,
    2, 0, 0, 2, 0, 0, 2, 0, 0, 2, 0, 3, 2, 0, 0, 3, 2, 0, 2, 0, 0, 3, 3, 3,
    2, 0, 1, 0, 0, 0, 2, 0, 2, 0, 0, 3, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 3, 3,
    2, 0, 3, 2, 0, 0, 2, 0, 3, 2, 0, 3, 2, 0, 3, 3, 2, 0, 2, 0, 3, 3, 3, 3,
    3, 1, 0, 0, 0, 0, 3, 1, 0, 0, 0, 3, 3, 2, 0, 0, 2, 0, 3, 2, 0, 0, 3, 3,
    3, 2, 0, 2, 0, 0, 3, 2, 0, 2, 0, 3, 3, 2, 0, 3, 2, 0, 3, 2, 0, 3, 3, 3,
    3, 3, 1, 0, 0, 0, 3, 3, 2, 0, 0, 3, 3, 3, 2, 0, 2, 0, 3, 3, 2, 0, 3, 3,
    3, 3, 3, 2, 0, 0, 3, 3, 3, 2, 0, 3, 3, 3, 3, 3, 2, 0, 3, 3, 3, 3, 3, 3]

private struct Eac3Bsi
{
    streamType: u32
    frameSize:  u32
    fscod:      u32
    sampleRate: u32
    blocks:     u32
    acmod:      u32
    nfchans:    u32
    lfeon:      bool
}

private struct Eac3Frame
{
    expstre:     bool
    snrStrategy: u32
    blockSwitch: bool
    ditherFlags: bool
    allocation:  bool
    fastGain:    bool
    delta:       bool
    skip:        bool
    coupling:    [BlocksPerAc3Frame] bool
    couplingNew: [BlocksPerAc3Frame] bool
    couplingExp: [BlocksPerAc3Frame] u32
    channelExp:  [BlocksPerAc3Frame, MaxFullBandwidthChannels] u32
    lfeExp:      [BlocksPerAc3Frame] u32
    coarseSnr:   u32
    fineSnr:     u32
}

private struct Eac3Codec
{
    using base: Codec

    sampleRate:   u32
    channels:     u32
    block:        Ac3Block
    imdct:        [MaxChannels] Imdct
    coefficients: [MaxChannels, SamplesPerBlock] f64
    pcm:          [MaxChannels, SamplesPerBlock] f64
    ditherState:  u32 = 0x6E624EB7
}

private func parseEac3Bsi(reader: *BitReader)->Eac3Bsi fail
{
    if reader.read(16) != 0x0B77 do
        fail InvalidFormatError{"E-AC-3 packet has an invalid sync word"}
    var result: retval
    result.streamType = reader.read(2)
    if result.streamType != 0 do
        fail UnsupportedFormatError{"E-AC-3 decoding currently supports independent substreams"}
    discard reader.read(3)
    result.frameSize = (reader.read(11) + 1) * 2
    result.fscod     = reader.read(2)
    if result.fscod == 3
    {
        let reduced = reader.read(2)
        if reduced >= 3 do
            fail InvalidFormatError{"E-AC-3 packet has a reserved reduced sample rate"}
        result.sampleRate = SampleRates[reduced] / 2
        result.blocks     = 6
    }
    else
    {
        result.sampleRate = SampleRates[result.fscod]
        const BlockCounts: [4] u32 = [1, 2, 3, 6]
        result.blocks = BlockCounts[reader.read(2)]
    }

    result.acmod   = reader.read(3)
    result.nfchans = FullBandwidthChannels[result.acmod]
    result.lfeon   = reader.read(1) != 0
    let bsid = reader.read(5)
    if bsid < 11 or bsid > 16 do
        fail InvalidFormatError{"E-AC-3 packet has an invalid bit-stream identification"}

    discard reader.read(5)
    if reader.read(1) do
        reader.skip(8)
    if !result.acmod
    {
        reader.skip(5)
        if reader.read(1) do
            reader.skip(8)
    }

    if reader.read(1) do
        fail UnsupportedFormatError{"E-AC-3 mixing metadata is not supported"}
    if reader.read(1)
    {
        reader.skip(5)     // bsmod, copyrightb, origbs
        if result.acmod == 2 do
            reader.skip(4)     // dsurmod, dheadphonmod
        if result.acmod >= 6 do
            reader.skip(2)     // dsurexmod
        if reader.read(1) do
            reader.skip(8)     // mixlevel, roomtyp, adconvtyp
        if !result.acmod and reader.read(1) do
            reader.skip(8)
        if result.fscod < 3 do
            reader.skip(1)     // sourcefscod
        if result.streamType == 0 and result.blocks != 6 do
            reader.skip(1)     // convsync
    }

    if reader.read(1)
    {
        let bytes = reader.read(6) + 1
        reader.skip(cast(u64) bytes * 8)
    }

    if reader.overrun do
        fail InvalidFormatError{"E-AC-3 bit-stream information is truncated"}
    return result
}

private func parseEac3Frame(reader: *BitReader, bsi: const *Eac3Bsi)->Eac3Frame fail
{
    var result: retval
    if bsi.blocks == 6
    {
        result.expstre = reader.read(1) != 0
        if reader.read(1) do
            fail UnsupportedFormatError{"E-AC-3 adaptive hybrid transform is not supported"}
    }
    else do
        result.expstre = true
    result.snrStrategy = reader.read(2)
    if reader.read(1) do
        fail UnsupportedFormatError{"E-AC-3 transient pre-noise processing is not supported"}
    result.blockSwitch = reader.read(1) != 0
    result.ditherFlags = reader.read(1) != 0
    result.allocation  = reader.read(1) != 0
    result.fastGain    = reader.read(1) != 0
    result.delta       = reader.read(1) != 0
    result.skip        = reader.read(1) != 0
    if reader.read(1) do
        fail UnsupportedFormatError{"E-AC-3 spectral-extension attenuation is not supported"}

    if bsi.acmod > 1
    {
        result.coupling[0]    = reader.read(1) != 0
        result.couplingNew[0] = true
        var previous = result.coupling[0]
        var block    = 1'u32
        while block < bsi.blocks
        {
            result.couplingNew[block] = reader.read(1) != 0
            if result.couplingNew[block] do
                previous = reader.read(1) != 0
            result.coupling[block] = previous
            block += 1
        }
    }

    if result.expstre
    {
        for block in bsi.blocks
        {
            if result.coupling[block] do
                result.couplingExp[block] = reader.read(2)
            for channel in bsi.nfchans do
                result.channelExp[block, channel] = reader.read(2)
        }
    }
    else
    {
        if bsi.acmod > 1
        {
            var coupled = false
            for block in bsi.blocks where result.coupling[block] do
                coupled = true
            if coupled
            {
                let code = reader.read(5)
                for block in bsi.blocks do
                    result.couplingExp[block] = Eac3FrameExponentStrategies[code, block]
            }
        }

        for channel in bsi.nfchans
        {
            let code = reader.read(5)
            for block in bsi.blocks do
                result.channelExp[block, channel] = Eac3FrameExponentStrategies[code, block]
        }
    }

    if bsi.lfeon
    {
        for block in bsi.blocks do
            result.lfeExp[block] = reader.read(1)
    }

    if bsi.streamType == 0
    {
        let converterStrategies = bsi.blocks == 6 or reader.read(1) != 0
        if converterStrategies
        {
            for channel in bsi.nfchans do
                discard reader.read(5)
        }
    }

    if result.snrStrategy == 0
    {
        result.coarseSnr = reader.read(6)
        result.fineSnr   = reader.read(4)
    }

    if bsi.blocks != 1 and reader.read(1)
    {
        var frameBits = bsi.frameSize * 8
        var log2      = 0'u32
        while frameBits
        {
            log2      += 1
            frameBits >>= 1
        }

        reader.skip(cast(u64) (bsi.blocks - 1) * (4 + log2))
    }

    if reader.overrun do
        fail InvalidFormatError{"E-AC-3 audio-frame header is truncated"}
    return result
}

private func isDefaultEac3CouplingJoin(absoluteSubband: u32)->bool
{
    return absoluteSubband == 8 or absoluteSubband == 10 or absoluteSubband == 11 or absoluteSubband == 13 or absoluteSubband >= 14
}

private impl Eac3Codec
{
    mtd resetState()
    {
        Memory.set(&.block, 0, #sizeof(.block))
        Memory.set(&.coefficients, 0, #sizeof(.coefficients))
        Memory.set(&.pcm, 0, #sizeof(.pcm))
        for channel in MaxChannels do
            .imdct[channel].reset()
        .ditherState = 0x6E624EB7
    }

    mtd ditherValue()->f64
    {
        .ditherState *= #wrap 1_664_525
        .ditherState += #wrap 1_013_904_223
        return (cast(f64) (.ditherState >> 8) / 16_777_216.0 - 0.5) * 1.4142135623730951
    }

    mtd readCoupling(reader: *BitReader, bsi: const *Eac3Bsi, frame: const *Eac3Frame, blockIndex: u32, firstCoordinates: *[MaxFullBandwidthChannels] bool, firstStrategy: *bool) fail
    {
        let block = &.block
        block.coupling = frame.coupling[blockIndex]
        if frame.couplingNew[blockIndex]
        {
            if !block.coupling
            {
                for channel in bsi.nfchans do
                    block.channelCoupled[channel] = false
                return
            }

            if reader.read(1) do
                fail UnsupportedFormatError{"E-AC-3 enhanced coupling is not supported"}
            if bsi.acmod == 2
            {
                block.channelCoupled[0] = true
                block.channelCoupled[1] = true
            }
            else
            {
                for channel in bsi.nfchans do
                    block.channelCoupled[channel] = reader.read(1) != 0
            }

            block.phaseFlagsInUse = bsi.acmod == 2 and reader.read(1) != 0
            block.couplingBegin   = reader.read(4)
            block.couplingEnd     = reader.read(4)
            let subbands = 3's32 + cast(s32) block.couplingEnd - cast(s32) block.couplingBegin
            if subbands < 1 or subbands > 18 do
                fail InvalidFormatError{"E-AC-3 coupling range is invalid"}
            block.couplingSubbands = cast(u32) subbands
            let explicitBands = reader.read(1) != 0
            block.couplingBandJoin[0] = false
            block.couplingBands       = block.couplingSubbands
            var subband = 1'u32
            while subband < block.couplingSubbands
            {
                block.couplingBandJoin[subband] = explicitBands ? reader.read(1) != 0 : (firstStrategy[] ? isDefaultEac3CouplingJoin(block.couplingBegin + subband) : block.couplingBandJoin[subband])
                if block.couplingBandJoin[subband] do
                    block.couplingBands -= 1
                subband += 1
            }

            firstStrategy[]           = false
            block.couplingStart       = cast(s32) block.couplingBegin * 12 + 37
            block.couplingEndMantissa = cast(s32) (block.couplingEnd + 3) * 12 + 37
        }

        if !block.coupling do
            return

        var anyCoordinates = false
        for channel in bsi.nfchans where block.channelCoupled[channel]
        {
            let newCoordinates = firstCoordinates[][channel] or reader.read(1) != 0
            firstCoordinates[][channel] = false
            if newCoordinates
            {
                anyCoordinates                = true
                block.couplingMaster[channel] = reader.read(2)
                for band in block.couplingBands
                {
                    block.couplingCoordExp[channel, band]  = reader.read(4)
                    block.couplingCoordMant[channel, band] = reader.read(4)
                }
            }
        }

        if bsi.acmod == 2 and block.phaseFlagsInUse and anyCoordinates
        {
            for band in block.couplingBands do
                block.couplingPhase[band] = reader.read(1) != 0
        }

        for channel in bsi.nfchans where block.channelCoupled[channel]
        {
            var coordinate: f64
            var coordinateBand = 0'u32
            for subband in block.couplingSubbands
            {
                if !block.couplingBandJoin[subband]
                {
                    let exponent = block.couplingCoordExp[channel, coordinateBand]
                    let mantissa = block.couplingCoordMant[channel, coordinateBand]
                    coordinate = exponent == 15 ? cast(f64) mantissa / 16.0 : cast(f64) (mantissa + 16) / 32.0
                    coordinate /= Math.pow(2.0, cast(f64) (exponent + 3 * block.couplingMaster[channel]))
                    if channel == 1 and block.phaseFlagsInUse and block.couplingPhase[coordinateBand] do
                        coordinate = -coordinate
                    coordinateBand += 1
                }

                block.couplingCoord[channel, subband] = coordinate
            }
        }
    }

    mtd readExponents(reader: *BitReader, bsi: const *Eac3Bsi, frame: const *Eac3Frame, blockIndex: u32) fail
    {
        let block = &.block
        block.couplingExpStrategy = frame.couplingExp[blockIndex]
        for channel in bsi.nfchans do
            block.channelExpStrategy[channel] = frame.channelExp[blockIndex, channel]
        block.lfeExpStrategy = frame.lfeExp[blockIndex]

        for channel in bsi.nfchans where block.channelExpStrategy[channel] and !block.channelCoupled[channel] do
            block.channelBandwidth[channel] = reader.read(6)
        if block.coupling and block.couplingExpStrategy
        {
            let groups = cast(u32) ((block.couplingEndMantissa - block.couplingStart) / cast(s32) (3 * ExponentGroupSize[block.couplingExpStrategy]))
            try decodeExponents(reader, block.couplingExpStrategy, groups, reader.read(4) << 1, 0, &block.couplingExponents)
        }

        for channel in bsi.nfchans where block.channelExpStrategy[channel]
        {
            block.channelEnd[channel] = block.channelCoupled[channel] ? block.couplingStart : 37 + 3 * cast(s32) (block.channelBandwidth[channel] + 12)
            let groupSize = cast(s32) ExponentGroupSize[block.channelExpStrategy[channel]]
            let groups    = cast(u32) ((block.channelEnd[channel] - 1 + 3 * groupSize - 1) / (3 * groupSize))
            try decodeExponents(reader, block.channelExpStrategy[channel], groups, reader.read(4), 1, &block.channelExponents[channel, 0])
            discard reader.read(2)
        }

        for channel in bsi.nfchans where !block.channelExpStrategy[channel] and block.channelCoupled[channel] do
            block.channelEnd[channel] = block.couplingStart
        if bsi.lfeon and block.lfeExpStrategy do
            try decodeExponents(reader, 1, 2, reader.read(4), 1, &block.lfeExponents)
    }

    mtd readAllocation(reader: *BitReader, bsi: const *Eac3Bsi, frame: const *Eac3Frame, blockIndex: u32) fail
    {
        let block = &.block
        if frame.allocation and reader.read(1)
        {
            block.slowDecayCode = reader.read(2)
            block.fastDecayCode = reader.read(2)
            block.slowGainCode  = reader.read(2)
            block.dbPerBitCode  = reader.read(2)
            block.floorCode     = reader.read(3)
        }
        elif !blockIndex
        {
            block.slowDecayCode = 2
            block.fastDecayCode = 1
            block.slowGainCode  = 1
            block.dbPerBitCode  = 2
            block.floorCode     = 7
        }

        if !blockIndex
        {
            block.coarseSnr = frame.coarseSnr
            for channel in bsi.nfchans
            {
                block.channelFineSnr[channel]  = frame.fineSnr
                block.channelFastGain[channel] = 4
            }

            block.couplingFineSnr  = frame.fineSnr
            block.couplingFastGain = 4
            block.lfeFineSnr       = frame.fineSnr
            block.lfeFastGain      = 4
        }

        if frame.snrStrategy != 0
        {
            let present = !blockIndex or reader.read(1) != 0
            if present
            {
                block.coarseSnr = reader.read(6)
                if frame.snrStrategy == 1
                {
                    let fine = reader.read(4)
                    block.couplingFineSnr = fine
                    for channel in bsi.nfchans do
                        block.channelFineSnr[channel] = fine
                    block.lfeFineSnr = fine
                }
                else
                {
                    if block.coupling do
                        block.couplingFineSnr = reader.read(4)
                    for channel in bsi.nfchans do
                        block.channelFineSnr[channel] = reader.read(4)
                    if bsi.lfeon do
                        block.lfeFineSnr = reader.read(4)
                }
            }
        }

        if frame.fastGain and reader.read(1)
        {
            if block.coupling do
                block.couplingFastGain = reader.read(3)
            for channel in bsi.nfchans do
                block.channelFastGain[channel] = reader.read(3)
            if bsi.lfeon do
                block.lfeFastGain = reader.read(3)
        }

        if bsi.streamType == 0 and reader.read(1) do
            reader.skip(10)
        if block.coupling
        {
            let leakPresent = !blockIndex or reader.read(1) != 0
            if leakPresent
            {
                block.couplingFastLeak = reader.read(3)
                block.couplingSlowLeak = reader.read(3)
            }
        }

        if frame.delta and reader.read(1)
        {
            if block.coupling
            {
                block.couplingDelta.mode = reader.read(2)
                if block.couplingDelta.mode == 3 do
                    fail InvalidFormatError{"E-AC-3 coupling delta allocation is reserved"}
            }

            for channel in bsi.nfchans
            {
                block.channelDelta[channel].mode = reader.read(2)
                if block.channelDelta[channel].mode == 3 do
                    fail InvalidFormatError{"E-AC-3 channel delta allocation is reserved"}
            }

            if block.coupling and block.couplingDelta.mode == 1
            {
                block.couplingDelta.count = reader.read(3) + 1
                for segment in block.couplingDelta.count
                {
                    block.couplingDelta.offset[segment] = reader.read(5)
                    block.couplingDelta.length[segment] = reader.read(4)
                    block.couplingDelta.value[segment]  = reader.read(3)
                }
            }

            for channel in bsi.nfchans where block.channelDelta[channel].mode == 1
            {
                block.channelDelta[channel].count = reader.read(3) + 1
                for segment in block.channelDelta[channel].count
                {
                    block.channelDelta[channel].offset[segment] = reader.read(5)
                    block.channelDelta[channel].length[segment] = reader.read(4)
                    block.channelDelta[channel].value[segment]  = reader.read(3)
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

        if frame.skip and reader.read(1)
        {
            let bytes = reader.read(9)
            reader.skip(cast(u64) bytes * 8)
        }

        let slowDecay = SLOW_DECAY[block.slowDecayCode]
        let fastDecay = FAST_DECAY[block.fastDecayCode]
        let slowGain  = SLOW_GAIN[block.slowGainCode]
        let dbKnee    = DB_PER_BIT[block.dbPerBitCode]
        let floor     = FLOOR[block.floorCode]
        for channel in bsi.nfchans do
            bitAllocation(bsi.fscod, 0, block.channelEnd[channel], &block.channelExponents[channel, 0], FAST_GAIN[block.channelFastGain[channel]], slowGain, fastDecay, slowDecay, dbKnee, floor, ((cast(s32) block.coarseSnr - 15) * 16 + cast(s32) block.channelFineSnr[channel]) * 4, 0, 0, &block.channelDelta[channel], &block.channelBap[channel, 0])
        if block.coupling do
            bitAllocation(bsi.fscod, block.couplingStart, block.couplingEndMantissa, &block.couplingExponents, FAST_GAIN[block.couplingFastGain], slowGain, fastDecay, slowDecay, dbKnee, floor, ((cast(s32) block.coarseSnr - 15) * 16 + cast(s32) block.couplingFineSnr) * 4, cast(s32) (block.couplingFastLeak << 8) + 768, cast(s32) (block.couplingSlowLeak << 8) + 768, &block.couplingDelta, &block.couplingBap)
        if bsi.lfeon do
            bitAllocation(bsi.fscod, 0, 7, &block.lfeExponents, FAST_GAIN[block.lfeFastGain], slowGain, fastDecay, slowDecay, dbKnee, floor, ((cast(s32) block.coarseSnr - 15) * 16 + cast(s32) block.lfeFineSnr) * 4, 0, 0, null, &block.lfeBap)
    }

    mtd readMantissas(reader: *BitReader, bsi: const *Eac3Bsi)
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
                let bap   = block.channelBap[channel, bin]
                let value = bap or !block.dither[channel] ? mantissas.get(bap) : .ditherValue()
                .coefficients[channel, bin] = value * Math.pow(2.0, -cast(f64) block.channelExponents[channel, bin])
            }

            if block.coupling and block.channelCoupled[channel] and !couplingRead
            {
                let count = cast(u64) (block.couplingEndMantissa - block.couplingStart)
                for bin in count do
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
                        let destination = block.couplingBegin * 12 + subband * 12 + bin + 37
                        .coefficients[channel, destination] = value * block.couplingCoord[channel, subband] * 8.0
                    }
                }
            }
        }
    }

    mtd sourceChannel(destination: u32, bsi: const *Eac3Bsi)->u32
    {
        return dolbySourceChannel(destination, bsi.acmod, bsi.nfchans, bsi.lfeon)
    }

    mtd decodeFrame(packet: const [..] u8, destination: [*] s16) fail
    {
        var reader = BitReader.create(@dataof(packet), @countof(packet))
        let bsi    = try parseEac3Bsi(&reader)
        if bsi.frameSize != @countof(packet) do
            fail InvalidFormatError{"E-AC-3 packet size does not match its sync-frame header"}
        if bsi.sampleRate != .sampleRate do
            fail InvalidFormatError{"E-AC-3 packet sample rate differs from its container track"}
        if bsi.nfchans + (bsi.lfeon ? 1 : 0) != .channels do
            fail InvalidFormatError{"E-AC-3 packet channel layout differs from its container track"}
        let frame = try parseEac3Frame(&reader, &bsi)
        var firstCoordinates: [MaxFullBandwidthChannels] bool
        for channel in bsi.nfchans do
            firstCoordinates[channel] = true
        var firstStrategy = true
        for blockIndex in bsi.blocks
        {
            for channel in bsi.nfchans do
                .block.blockSwitch[channel] = frame.blockSwitch and reader.read(1) != 0
            for channel in bsi.nfchans do
                .block.dither[channel] = !frame.ditherFlags or reader.read(1) != 0
            if reader.read(1) do
                reader.skip(8)
            if !bsi.acmod and reader.read(1) do
                reader.skip(8)

            let spxStrategy = !blockIndex or reader.read(1) != 0
            if spxStrategy and reader.read(1) do
                fail UnsupportedFormatError{"E-AC-3 spectral extension is not supported"}
            try .readCoupling(&reader, &bsi, &frame, blockIndex, &firstCoordinates, &firstStrategy)
            if bsi.acmod == 2
            {
                let rematrixNew = !blockIndex or reader.read(1) != 0
                if rematrixNew
                {
                    .block.rematrixCount = .block.coupling ? (.block.couplingBegin > 2 ? 4 : .block.couplingBegin > 0 ? 3 : 2) : 4
                    for band in .block.rematrixCount do
                        .block.rematrix[band] = reader.read(1) != 0
                }
            }

            try .readExponents(&reader, &bsi, &frame, blockIndex)
            try .readAllocation(&reader, &bsi, &frame, blockIndex)
            .readMantissas(&reader, &bsi)
            if reader.overrun do
                fail InvalidFormatError{"E-AC-3 audio block is truncated"}

            for channel in bsi.nfchans do
                .imdct[channel].process(&.coefficients[channel, 0], .block.blockSwitch[channel], &.pcm[channel, 0])
            if bsi.lfeon do
                .imdct[bsi.nfchans].process(&.coefficients[bsi.nfchans, 0], false, &.pcm[bsi.nfchans, 0])
            for sample in SamplesPerBlock
            {
                for channel in .channels
                {
                    let source = .sourceChannel(channel, &bsi)
                    let scaled = Math.clamp(.pcm[source, sample] * 32767.0, -32768.0, 32767.0)
                    destination[(blockIndex * SamplesPerBlock + sample) * .channels + channel] = cast(s16) scaled
                }
            }
        }
    }
}

impl IPacketCodec for Eac3Codec
{
    mtd impl canDecode(encoding: SoundFileEncoding)->bool => encoding == .Eac3

    mtd impl initialize(config: const [..] u8, sampleRateHz, channels: u32) fail
    {
        discard config
        if !sampleRateHz or !channels or channels > MaxChannels do
            fail BadParameterError{"E-AC-3 audio needs one to six channels and a non-zero sample rate"}
        .sampleRate = sampleRateHz
        .channels   = channels
        .resetState()
    }

    mtd impl reset() => .resetState()

    mtd impl decodePacket(destination: [*] void, destinationSize: u64, packet: const [..] u8)->u64 fail
    {
        if @countof(packet) < 6 do
            fail InvalidFormatError{"E-AC-3 packet is truncated"}
        var header   = BitReader.create(@dataof(packet), @countof(packet))
        let bsi      = try parseEac3Bsi(&header)
        let required = cast(u64) bsi.blocks * SamplesPerBlock * .channels * #sizeof(s16)
        if destinationSize < required do
            fail BadParameterError{"E-AC-3 destination buffer is too small"}
        try .decodeFrame(packet, cast([*] s16) destination)
        return required
    }
}

#init
{
    registerPacketCodec'Eac3Codec()
}
