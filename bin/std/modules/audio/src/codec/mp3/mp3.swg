//! Format: MPEG-1, MPEG-2, and MPEG-2.5 Layer III packet decoder component.
//! Supported: Layer III at every sampling frequency and bit rate of the three versions, mono, dual channel, joint stereo with mid/side and intensity coupling, long, short and mixed blocks, and the bit reservoir.
//! Not supported: Layer I and Layer II, free-format streams, and the CRC the frame header may carry.
//! Role: This file owns frame headers, side information, the bit reservoir, scalefactors, entropy decoding, requantization, stereo, and PCM output.
//
#global namespace Mp3
#global internal

using Core, Core.Errors

// The largest main data a frame may reach back over, clause 2.4.2.7.
const ReservoirBytes = 511'u64

// Sampling frequencies of the three versions, by the header's own index.
const SampleRates: [3, 3] u32 = [
    [11_025, 12_000, 8_000],      // MPEG-2.5
    [22_050, 24_000, 16_000],     // MPEG-2
    [44_100, 48_000, 32_000]]     // MPEG-1

// Layer III bit rates in kilobits per second, by the header's own index.
const BitRatesMpeg1: [15] u32 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
const BitRatesMpeg2: [15] u32 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]

// What the four bytes of a frame header say.
struct FrameHeader
{
    isMpeg1:       bool     // A version 1 frame carries two granules and nine-bit scalefactors.
    isMpeg25:      bool
    rateIndex:     u32     // Index into the widened band tables: 0-1 MPEG-2.5, 2-4 MPEG-2, 5-7 MPEG-1.
    sampleRate:    u32
    channels:      u32
    mode:          u32     // 0 stereo, 1 joint stereo, 2 dual channel, 3 single channel.
    modeExtension: u32
    hasCrc:        bool
    frameBytes:    u64     // Whole frame, header included.
    sideInfoBytes: u64
    frameSamples:  u32     // Sample frames one frame decodes to.
    granules:      u32
}

impl FrameHeader
{
    mtd const isMidSide()->bool   => .mode == 1 and (.modeExtension & 2) != 0
    mtd const isIntensity()->bool => .mode == 1 and (.modeExtension & 1) != 0
}

// Reads the four header bytes of a frame, or says why they are not one.
func readHeader(bytes: const [..] u8)->FrameHeader fail
{
    if bytes.count < 4 do
        fail InvalidFormatError{"MP3 frame header is truncated"}
    if bytes[0] != 0xFF or (bytes[1] & 0xE0) != 0xE0 do
        fail InvalidFormatError{"MP3 frame has no sync word"}

    let version = cast(u32) (bytes[1] >> 3) & 3
    let layer   = cast(u32) (bytes[1] >> 1) & 3
    if version == 1 do
        fail InvalidFormatError{"MP3 frame states the reserved version"}
    if layer != 1 do
        fail UnsupportedFormatError{"audio decoder reads MPEG Layer III only"}

    let rate = cast(u32) (bytes[2] >> 2) & 3
    if rate == 3 do
        fail InvalidFormatError{"MP3 frame states the reserved sampling frequency"}

    let bitrateIndex = cast(u32) (bytes[2] >> 4) & 15
    if !bitrateIndex do
        fail UnsupportedFormatError{"audio decoder does not read free-format MP3"}
    if bitrateIndex == 15 do
        fail InvalidFormatError{"MP3 frame states the reserved bit rate"}

    var result: retval
    result.isMpeg1  = version == 3
    result.isMpeg25 = version == 0
    result.hasCrc   = (bytes[1] & 1) == 0

    // Version 2.5 halves version 2, which halves version 1.
    let versionRow = result.isMpeg1 ? 2'u64 : (result.isMpeg25 ? 0'u64 : 1'u64)
    result.sampleRate = SampleRates[versionRow, cast(u64) rate]

    // The band tables are indexed by one widened number covering all three versions.
    result.rateIndex = result.isMpeg1 ? 5 + rate : (result.isMpeg25 ? (rate == 2 ? 1 : 0) : 2 + rate)

    result.mode          = cast(u32) (bytes[3] >> 6) & 3
    result.modeExtension = cast(u32) (bytes[3] >> 4) & 3
    result.channels      = result.mode == 3 ? 1 : 2
    result.granules      = result.isMpeg1 ? 2 : 1
    result.frameSamples  = result.isMpeg1 ? 1152 : 576

    let kbits   = result.isMpeg1 ? BitRatesMpeg1[cast(u64) bitrateIndex] : BitRatesMpeg2[cast(u64) bitrateIndex]
    let padding = cast(u64) (bytes[2] >> 1) & 1
    result.frameBytes = cast(u64) (result.frameSamples / 8) * cast(u64) kbits * 1000 / cast(u64) result.sampleRate + padding
    if result.frameBytes < 4 do
        fail InvalidFormatError{"MP3 frame states a size no frame can have"}

    if result.isMpeg1 do
        result.sideInfoBytes = result.channels == 1 ? 17 : 32
    else do
        result.sideInfoBytes = result.channels == 1 ? 9 : 17

    return result
}

// Reads syntax elements from the main data, most significant bit first.
struct BitReader
{
    data:   const [*] u8?
    bitEnd: u64
    bitPos: u64
}

impl BitReader
{
    func create(payload: const [..] u8)->BitReader => {payload.buffer, payload.count * 8, 0}

    // Reads `count` bits, at most 24 at a time. Past the end every bit reads as zero, which lets a
    // truncated granule finish rather than fault; the caller sees it through `overran`.
    mtd read(count: u32)->u32
    {
        var result = 0'u32
        for index in count
        {
            result <<= 1
            if .bitPos < .bitEnd
            {
                let byte = .data![.bitPos >> 3]
                result |= cast(u32) (byte >> (7 - cast(u32) (.bitPos & 7))) & 1
            }

            .bitPos += 1
        }

        return result
    }

    mtd const overran()->bool => .bitPos > .bitEnd
}

// The side information of one granule of one channel.
struct GranuleInfo
{
    part23Length:     u32
    bigValues:        u32
    globalGain:       u32
    scalefacCompress: u32
    blockType:        u32
    mixedBlock:       bool
    tableSelect:      [3] u32
    subblockGain:     [3] u32
    regionBands:      [3] u32     // How many scalefactor bands each region spans, less one.
    preflag:          bool
    scalefacScale:    u32
    count1Table:      u32
    scfsi:            u32
    longBands:        u32     // Scalefactor bands the granule reads as long blocks.
    shortBands:       u32     // Scalefactor bands it reads as three short windows.
    bandKind:         u32     // 0 long, 1 short, 2 mixed: which band table applies.
}

impl GranuleInfo
{
    // The width of one scalefactor band of this granule, in spectral lines.
    mtd const bandWidth(rateIndex: u32, band: u64)->u32
    {
        let rate = cast(u64) rateIndex
        if .bandKind == 1 do
            return band < 40 ? cast(u32) ScfBandShort[rate, band] : 0
        if .bandKind == 2 do
            return band < 40 ? cast(u32) ScfBandMixed[rate, band] : 0
        return band < 23 ? cast(u32) ScfBandLong[rate, band] : 0
    }

    mtd const bandCount()->u64 => cast(u64) .longBands + cast(u64) .shortBands
}

// Reads the side information of one frame, clause 2.4.1.7.
//
// Returns how far back into the reservoir the main data of this frame starts.
func readSideInfo(header: const *FrameHeader, bytes: const [..] u8, granules: *[2, 2] GranuleInfo)->u64 fail
{
    var reader = BitReader.create(bytes)

    var mainDataBegin = 0'u64
    var scfsi         = 0'u32
    if header.isMpeg1
    {
        mainDataBegin = cast(u64) reader.read(9)
        discard reader.read(header.channels == 1 ? 5 : 3)
        scfsi = reader.read(4 * header.channels)
    }
    else
    {
        mainDataBegin = cast(u64) reader.read(8)
        discard reader.read(header.channels == 1 ? 1 : 2)
    }

    for granule in header.granules
    {
        for channel in header.channels
        {
            let info = &granules[][cast(u64) granule, cast(u64) channel]
            info.part23Length = reader.read(12)
            info.bigValues    = reader.read(9)
            if info.bigValues > 288 do
                fail InvalidFormatError{"MP3 granule codes more spectral lines than a granule holds"}
            info.globalGain       = reader.read(8)
            info.scalefacCompress = reader.read(header.isMpeg1 ? 4 : 9)

            info.longBands  = 22
            info.shortBands = 0
            info.bandKind   = 0
            if reader.read(1) != 0
            {
                info.blockType = reader.read(2)
                if !info.blockType do
                    fail InvalidFormatError{"MP3 granule switches windows and then states a normal block"}
                info.mixedBlock = reader.read(1) != 0

                info.regionBands[0] = 7
                info.regionBands[1] = 255
                if info.blockType == 2
                {
                    if !info.mixedBlock
                    {
                        info.regionBands[0] = 8
                        info.bandKind       = 1
                        info.longBands      = 0
                        info.shortBands     = 39
                    }
                    else
                    {
                        info.bandKind   = 2
                        info.longBands  = header.isMpeg1 ? 8 : 6
                        info.shortBands = 30
                    }
                }

                for region in 2'u64 do
                    info.tableSelect[region] = reader.read(5)
                info.tableSelect[2] = 0
                for window in 3'u64 do
                    info.subblockGain[window] = reader.read(3)
            }
            else
            {
                info.blockType  = 0
                info.mixedBlock = false
                for region in 3'u64 do
                    info.tableSelect[region] = reader.read(5)
                info.regionBands[0] = reader.read(4)
                info.regionBands[1] = reader.read(3)
                info.regionBands[2] = 255
            }

            info.preflag       = header.isMpeg1 ? reader.read(1) != 0 : info.scalefacCompress >= 500
            info.scalefacScale = reader.read(1)
            info.count1Table   = reader.read(1)

            // `scfsi` says whether the second granule keeps what the first read, so the first
            // never shares, and a short block never shares either.
            var mask = 0'u32
            if granule == 1 and info.blockType != 2 do
                mask = (scfsi >> (4 * (header.channels - 1 - channel))) & 15
            info.scfsi = mask
        }
    }

    if reader.overran() do
        fail InvalidFormatError{"MP3 side information is truncated"}
    return mainDataBegin
}

// Decodes one Layer III elementary stream, one frame at a time.
//
// The instance belongs to one voice: a frame reaches back into the main data of the frames before
// it, and every channel carries filter state across granules, so frames must arrive in order and a
// seek must go through `reset`.
struct Codec
{
    // Every registered codec starts with the registry's own header.
    using base: Audio.Codec

    sampleRate:   u32
    channels:     u32
    reservoir:    Array'u8
    state:        [2] ChannelState
    lines:        [2] Granule576
    scalefac:     [2, 40] u8     // The previous granule's, for the bands `scfsi` shares.
    intensityPos: [2, 40] u8
    bandGain:     [2, 40] f32
    output:       [2, 1152] f32
    ready:        bool
}

// Small magnitudes are almost all of them, so their power is stated rather than computed.
const Pow43Small: [16] f32 = [
    0.0, 1.0, 2.5198421, 4.32674871, 6.34960421, 8.54987973, 10.9027236, 13.3905183,
    16.0, 18.7207544, 21.5443469, 24.4637810, 27.4731418, 30.5671579, 33.7411249, 36.9908313]

impl Codec
{
    // The magnitude of one quantized line, `|value| ^ (4 / 3)`.
    #[Swag.Inline]
    mtd const power43(value: u32)->f32
    {
        if value < 16 do
            return Pow43Small[cast(u64) value]
        return cast(f32) Math.pow(cast(f64) value, 4.0'f64 / 3.0'f64)
    }

    // Reads the scalefactors of one granule and folds them into one gain per band.
    //
    // What the decoder needs is not the scalefactor but the factor every line of its band is
    // multiplied by, so the exponent of clause 2.4.3.4 is resolved here, once per band, rather
    // than once per line.
    mtd readScalefactors(header: const *FrameHeader, info: const *GranuleInfo, reader: *BitReader, channel: u32)
    {
        var sizes:  [4] u32
        var counts: [4] u32
        let shift = info.scalefacScale + 1

        // Long blocks, mixed blocks, and short blocks each partition their scalefactors
        // differently, and the row that says how is the same for both versions.
        let partitionRow = cast(u64) (info.shortBands != 0 ? 1'u32 : 0'u32) + cast(u64) (info.longBands == 0 ? 1'u32 : 0'u32)
        var partitionAt  = 0'u64
        if header.isMpeg1
        {
            let packed = cast(u32) ScfCompress[cast(u64) info.scalefacCompress]
            sizes[0] = packed >> 2
            sizes[1] = packed >> 2
            sizes[2] = packed & 3
            sizes[3] = packed & 3
        }
        else
        {
            // A low sampling frequency granule states four lengths as one number, and the
            // partition they apply to comes out of the same division, clause 2.4.3.2.
            let intensity = header.isIntensity() and channel == 1
            var remaining = cast(s32) (info.scalefacCompress >> (intensity ? 1'u32 : 0'u32))
            var k         = intensity ? 12'u64 : 0'u64
            for
            {
                var product = 1's32
                var index   = 3's32
                while index >= 0
                {
                    let modulus = cast(s32) LsfModulus[k + cast(u64) index]
                    sizes[cast(u64) index] = cast(u32) (remaining / product % modulus)
                    product                *= modulus
                    index                  -= 1
                }

                remaining -= product
                k         += 4
                if remaining < 0 do
                    break
            }

            partitionAt = k
        }

        for index in 4'u64 do
            counts[index] = cast(u32) LsfPartitions[partitionRow, partitionAt + index]

        var values: [40] u8
        var at    = 0'u64
        var share = info.scfsi
        for partition in 4'u64
        {
            let count = cast(u64) counts[partition]
            if !count do
                break

            if header.isMpeg1 and (share & 8) != 0
            {
                // This partition keeps the values the previous granule read.
                for index in count where at + index < 40 do
                    values[at + index] = .scalefac[cast(u64) channel, at + index]
            }
            else
            {
                let bits = sizes[partition]
                let full = bits ? (1'u32 << bits) - 1 : 0'u32
                for index in count where at + index < 40
                {
                    let value = bits ? reader.read(bits) : 0'u32
                    values[at + index] = cast(u8) value

                    // A low sampling frequency granule marks an unusable intensity position by
                    // saturating the field.
                    if !header.isMpeg1 and bits and value == full do
                        .intensityPos[cast(u64) channel, at + index] = 255
                    else do
                        .intensityPos[cast(u64) channel, at + index] = cast(u8) value
                }
            }

            if header.isMpeg1
            {
                for index in count where at + index < 40 do
                    .intensityPos[cast(u64) channel, at + index] = values[at + index]
            }

            at    += count
            share <<= 1
        }

        while at < 40
        {
            values[at] = 0
            at         += 1
        }

        for index in 40'u64 do
            .scalefac[cast(u64) channel, index] = values[index]

        // Subblock gain lowers a whole short window; preemphasis raises the top long bands.
        var scaled: [40] s32
        for index in 40'u64 do
            scaled[index] = cast(s32) values[index]
        if info.shortBands
        {
            let up    = 3 - cast(s32) shift
            var index = 0'u64
            while index < cast(u64) info.shortBands
            {
                for window in 3'u64 where cast(u64) info.longBands + index + window < 40 do
                    scaled[cast(u64) info.longBands + index + window] += cast(s32) info.subblockGain[window] << up
                index += 3
            }
        }
        elif info.preflag
        {
            for index in 10'u64 where 11 + index < 40 do
                scaled[11 + index] += cast(s32) Preemphasis[index]
        }

        // Mid/side scales both channels down by the square root of two, which the intensity path
        // takes back for the bands it owns.
        var exponent = cast(s32) info.globalGain - 210
        if header.isMidSide() do
            exponent -= 2

        for index in 40'u64
        {
            let power = cast(f64) (exponent - (scaled[index] << shift)) / 4.0'f64
            .bandGain[cast(u64) channel, index] = cast(f32) Math.pow(2.0'f64, power)
        }
    }

    // Walks one Huffman code through the tree of its table and returns the symbol.
    #[Swag.Inline]
    mtd const decodeSymbol(tree: const [..] s16, reader: *BitReader)->s32
    {
        var node = 0's32
        for 32'u32
        {
            let slot = cast(u64) (node * 2) + cast(u64) reader.read(1)
            if slot >= tree.count do
                return -1
            let next = tree[slot]
            if next < 0 do
                return cast(s32) (-next - 1)
            node = cast(s32) next
        }

        return -1
    }

    // The decoding tree of one `table_select` value.
    mtd const codeTree(select: u32)->const [..] s16
    {
        switch cast(u32) HuffCodeTable[cast(u64) select]
        {
        case 1:  return Huff1Tree
        case 2:  return Huff2Tree
        case 3:  return Huff3Tree
        case 5:  return Huff5Tree
        case 6:  return Huff6Tree
        case 7:  return Huff7Tree
        case 8:  return Huff8Tree
        case 9:  return Huff9Tree
        case 10: return Huff10Tree
        case 11: return Huff11Tree
        case 12: return Huff12Tree
        case 13: return Huff13Tree
        case 15: return Huff15Tree
        case 16: return Huff16Tree
        case 24: return Huff24Tree
        }

        return Huff1Tree
    }

    // How many values one axis of that table holds, which is what splits a symbol into its pair.
    mtd const codeWidth(select: u32)->u32
    {
        switch cast(u32) HuffCodeTable[cast(u64) select]
        {
        case 1:              return 2
        case 2, 3:           return 3
        case 5, 6:           return 4
        case 7, 8, 9:        return 6
        case 10, 11, 12:     return 8
        case 13, 15, 16, 24: return 16
        }

        return 1
    }

    // Decodes the spectral lines of one granule of one channel and requantizes them.
    //
    // The lines are read as pairs while `big_values` lasts and as quadruples afterwards, and both
    // walk the same list of scalefactor bands: the band a line belongs to is what says which gain
    // multiplies it, and the walk does not restart between the two regions.
    mtd decodeSpectrum(header: const *FrameHeader, info: const *GranuleInfo, reader: *BitReader, channel: u32, limit: u64)
    {
        let lines = &.lines[cast(u64) channel]
        for index in 576'u64 do
            lines[][index] = 0

        var line      = 0'u64
        var band      = 0'u64
        var pairsLeft = 0'u64     // Pairs the current band still holds.
        var gain      = 0'f32
        var big       = cast(u64) info.bigValues
        var region    = 0'u64
        var ended     = false

        while region < 3 and big and !ended
        {
            let select = info.tableSelect[region]

            // Table zero codes nothing at all: its region is a run of zero pairs that occupies no
            // bit. Reading one anyway moves the bit position and loses the rest of the granule.
            let empty  = HuffCodeTable[cast(u64) select] == 0
            let tree   = .codeTree(select)
            let axis   = .codeWidth(select)
            let escape = cast(u32) HuffLinbits[cast(u64) select]
            var spans  = cast(s32) info.regionBands[region] + 1
            region += 1

            while big and spans > 0
            {
                let width = info.bandWidth(header.rateIndex, band)
                if !width
                {
                    ended = true
                    break
                }

                gain  = .bandGain[cast(u64) channel, band]
                band  += 1
                spans -= 1

                pairsLeft = cast(u64) width / 2
                var take = Math.min(big, pairsLeft)
                big       -= take
                pairsLeft -= take

                while take
                {
                    take -= 1
                    if empty
                    {
                        if line + 2 <= 576
                        {
                            lines[][line]     = 0
                            lines[][line + 1] = 0
                            line              += 2
                        }

                        continue
                    }

                    let symbol = .decodeSymbol(tree, reader)
                    if symbol < 0 or reader.bitPos > limit do
                        return

                    let pair = cast(u32) symbol
                    for component in 2'u32
                    {
                        var value = component == 0 ? pair / axis : pair % axis
                        if value == 15 and escape do
                            value += reader.read(escape)

                        var sample = 0'f32
                        if value
                        {
                            sample = .power43(value) * gain
                            if reader.read(1) != 0 do
                                sample = -sample
                        }

                        if line < 576
                        {
                            lines[][line] = sample
                            line          += 1
                        }
                    }
                }
            }
        }

        // The count1 region codes four lines at a time until the granule's bits run out.
        let quadTree: const [..] s16 = info.count1Table != 0 ? Count1BTree : Count1ATree
        while line + 4 <= 576 and reader.bitPos < limit and !ended
        {
            let symbol = .decodeSymbol(quadTree, reader)
            if symbol < 0 or reader.bitPos > limit do
                break

            // A quadruple spans two pairs, and the band may change between them.
            for half in 2'u32
            {
                if !pairsLeft
                {
                    let width = info.bandWidth(header.rateIndex, band)
                    if !width
                    {
                        ended = true
                        break
                    }

                    gain      = .bandGain[cast(u64) channel, band]
                    band      += 1
                    pairsLeft = cast(u64) width / 2
                    if !pairsLeft do
                        continue
                }

                pairsLeft -= 1
                for component in 2'u32
                {
                    var sample = 0'f32
                    if (cast(u32) symbol & (8 >> (half * 2 + component))) != 0
                    {
                        sample = gain
                        if reader.read(1) != 0 do
                            sample = -sample
                    }

                    if line < 576
                    {
                        lines[][line] = sample
                        line          += 1
                    }
                }
            }
        }
    }

    // Recombines the two channels of a joint stereo granule, clause 2.4.3.4.9.
    mtd processStereo(header: const *FrameHeader, info: const *GranuleInfo, lsfShift: u32)
    {
        // The pan a position states, for a version 1 stream. Position seven is illegal and the
        // band it names stays as it is.
        const Pan: [7, 2] f32 = [
            [0.0, 1.0], [0.211324865, 0.788675135], [0.366025404, 0.633974596], [0.5, 0.5],
            [0.633974596, 0.366025404], [0.788675135, 0.211324865], [1.0, 0.0]]

        let left     = &.lines[0]
        let right    = &.lines[1]
        let maxPos   = header.isMpeg1 ? 7'u32 : 64'u32
        let midSide  = header.isMidSide()
        let takeBack = midSide ? cast(f32) Math.sqrt(2.0'f64) : 1.0'f32

        // The intensity region starts where the right channel stopped carrying anything.
        var topBand: [3] s32 = [-1, -1, -1]
        if header.isIntensity()
        {
            var line = 0'u64
            for band in info.bandCount()
            {
                let width = cast(u64) info.bandWidth(header.rateIndex, band)
                if !width do
                    break
                var index = 0'u64
                while index < width
                {
                    if line + index < 576 and right[][line + index] != 0
                    {
                        topBand[band % 3] = cast(s32) band
                        break
                    }

                    index += 1
                }

                line += width
            }

            if info.longBands
            {
                let top = Math.max(Math.max(topBand[0], topBand[1]), topBand[2])
                topBand[0] = top
                topBand[1] = top
                topBand[2] = top
            }

            // The last band of each window inherits a position rather than reading one.
            let blocks  = info.shortBands ? 3'u64 : 1'u64
            let count   = info.bandCount()
            let neutral = header.isMpeg1 ? 3'u8 : 0'u8
            for index in blocks
            {
                if count < blocks do
                    break
                let top  = count - blocks + index
                let prev = cast(s64) top - cast(s64) blocks
                if top >= 40 do
                    continue
                if prev >= 0 and topBand[index] < cast(s32) prev do
                    .intensityPos[1, top] = .intensityPos[1, cast(u64) prev]
                else do
                    .intensityPos[1, top] = neutral
            }
        }

        var line = 0'u64
        for band in info.bandCount()
        {
            let width = cast(u64) info.bandWidth(header.rateIndex, band)
            if !width do
                break

            let position = cast(u32) .intensityPos[1, band]
            if header.isIntensity() and cast(s32) band > topBand[band % 3] and position < maxPos
            {
                var kl = 1.0'f32
                var kr = 1.0'f32
                if header.isMpeg1
                {
                    kl = Pan[cast(u64) position, 0]
                    kr = Pan[cast(u64) position, 1]
                }
                else
                {
                    kr = cast(f32) Math.pow(2.0'f64, -cast(f64) ((position + 1) >> 1 << lsfShift) / 4.0'f64)
                    if (position & 1) != 0
                    {
                        kl = kr
                        kr = 1.0
                    }
                }

                for index in width where line + index < 576
                {
                    let value = left[][line + index]
                    left[][line + index]  = value * kl * takeBack
                    right[][line + index] = value * kr * takeBack
                }
            }
            elif midSide
            {
                for index in width where line + index < 576
                {
                    let a = left[][line + index]
                    let b = right[][line + index]
                    left[][line + index]  = a + b
                    right[][line + index] = a - b
                }
            }

            line += width
        }
    }

    // Turns the spectral lines of one granule of one channel into 576 samples.
    mtd synthesizeChannel(header: const *FrameHeader, info: const *GranuleInfo, channel, granule: u32)
    {
        let lines = &.lines[cast(u64) channel]

        // A short block interleaves its windows, and a mixed block does so past its long bands.
        if info.blockType == 2
        {
            var firstLine = 0'u32
            var firstBand = 0'u64
            for band in cast(u64) info.longBands
            {
                firstLine += info.bandWidth(header.rateIndex, band)
                firstBand += 1
            }

            var widths: [40] u8
            for band in 40'u64 do
                widths[band] = cast(u8) info.bandWidth(header.rateIndex, band)
            reorderShortBlocks(lines, widths, cast(u32) firstBand, firstLine)
        }

        // Only long blocks were aliased. A mixed block aliased its long part alone.
        var aliased = 32'u32
        if info.blockType == 2 do
            aliased = info.mixedBlock ? (header.rateIndex == 1 ? 4'u32 : 2'u32) : 1'u32
        reduceAlias(lines, aliased)

        var longSubbands = 0'u32
        if info.blockType == 2 and info.mixedBlock do
            longSubbands = header.rateIndex == 1 ? 4 : 2
        elif info.blockType != 2 do
            longSubbands = 32

        for subband in 32'u32
        {
            let kind = subband < longSubbands ? (info.blockType == 2 ? 0'u32 : info.blockType) : 2'u32
            inverseTransform(lines, &.state[cast(u64) channel].overlap, subband, kind)
        }

        invertFrequencies(lines)

        let base = cast(u64) granule * 576
        synthesizeGranule(&.state[cast(u64) channel], lines, &.output[cast(u64) channel, base], 1)
    }

    // Restores the state a decode starts from.
    mtd resetState()
    {
        for channel in 2'u64 do
            .state[channel].reset()
        .reservoir.clear()
        Memory.set(cast(*void) &.scalefac[0, 0], 0, 2 * 40)
        Memory.set(cast(*void) &.intensityPos[0, 0], 0, 2 * 40)
        .ready = false
    }

    // Decodes one frame into `.output`, and returns how many sample frames it produced.
    mtd decodeFrame(packet: const [..] u8)->u32 fail
    {
        let header = try readHeader(packet)
        if packet.count < header.frameBytes do
            fail InvalidFormatError{"MP3 frame is shorter than its header states"}
        if header.sampleRate != .sampleRate or header.channels != .channels do
            fail InvalidFormatError{"MP3 frame does not match the stream its container declared"}

        var at = 4'u64
        if header.hasCrc do
            at += 2
        if at + header.sideInfoBytes > header.frameBytes do
            fail InvalidFormatError{"MP3 frame is too short for its side information"}

        var granules: [2, 2] GranuleInfo
        let mainDataBegin = try readSideInfo(&header, packet[at until at + header.sideInfoBytes], &granules)
        at += header.sideInfoBytes

        // The main data of this frame continues what the frames before it left in the reservoir.
        let available = Math.min(mainDataBegin, .reservoir.count)
        var main: Array'u8
        main.reserve(available + header.frameBytes - at)
        if available do
            main.add(.reservoir.toSlice()[.reservoir.count - available until .reservoir.count])
        main.add(packet[at until header.frameBytes])

        // A frame that reaches further back than what was kept cannot be decoded; every frame
        // after it can, so the stream restarts rather than failing.
        let usable = available >= mainDataBegin

        // The history taken is exactly what this frame asked for, so its own data starts at zero.
        var reader = BitReader.create(main.toSlice())

        var produced = 0'u32
        if usable
        {
            for granule in header.granules
            {
                for channel in header.channels
                {
                    let info  = &granules[cast(u64) granule, cast(u64) channel]
                    let start = reader.bitPos
                    .readScalefactors(&header, info, &reader, channel)
                    .decodeSpectrum(&header, info, &reader, channel, start + cast(u64) info.part23Length)
                    reader.bitPos = start + cast(u64) info.part23Length
                }

                if header.channels == 2 and header.mode == 1
                {
                    let next = &granules[cast(u64) granule, 1]
                    .processStereo(&header, &granules[cast(u64) granule, 0], next.scalefacCompress & 1)
                }

                for channel in header.channels do
                    .synthesizeChannel(&header, &granules[cast(u64) granule, cast(u64) channel], channel, granule)
            }

            produced = header.frameSamples
        }
        else
        {
            for channel in 2'u64 do
                .state[channel].reset()
            for channel in header.channels
            {
                for index in cast(u64) header.frameSamples do
                    .output[channel, index] = 0
            }

            produced = header.frameSamples
        }

        // What this frame did not consume is what the next one may reach back over.
        var keptFrom = (reader.bitPos + 7) / 8
        if keptFrom > main.count do
            keptFrom = main.count
        var kept = main.count - keptFrom
        if kept > ReservoirBytes
        {
            keptFrom += kept - ReservoirBytes
            kept     = ReservoirBytes
        }

        .reservoir.clear()
        if kept do
            .reservoir.add(main.toSlice()[keptFrom until keptFrom + kept])

        return produced
    }
}

impl IPacketCodec for Codec
{
    mtd impl canDecode(encoding: SoundFileEncoding)->bool => encoding == .Mp3

    mtd impl initialize(config: const [..] u8, sampleRateHz, channels: u32) fail
    {
        discard config
        if channels < 1 or channels > 2 do
            fail UnsupportedFormatError{"MP3 carries one or two channels"}
        .sampleRate = sampleRateHz
        .channels   = channels
        .resetState()
    }

    mtd impl reset()
    {
        .resetState()
    }

    mtd impl decodePacket(destination: [*] void, destinationSize: u64, packet: const [..] u8)->u64 fail
    {
        let frames   = try .decodeFrame(packet)
        let produced = cast(u64) frames * cast(u64) .channels * #sizeof(s16)
        if destinationSize < produced do
            fail BadParameterError{"MP3 destination buffer is too small"}

        let samples = cast([*] s16) destination
        var at      = 0'u64
        for index in cast(u64) frames
        {
            for channel in cast(u64) .channels
            {
                let value = .output[channel, index] * 32767.0
                samples[at] = cast(s16) Math.clamp(value, -32768.0'f32, 32767.0'f32)
                at          += 1
            }
        }

        return produced
    }
}

// Returns the number of sample frames one frame of `packet` decodes to.
//
// A container builds its packet index before any decoding happens, so this reads the version out
// of the frame header rather than decoding it.
internal func packetFrameCount(packet: const [..] u8)->u32 fail
{
    let header = try readHeader(packet)
    return header.frameSamples
}

#init
{
    registerPacketCodec'Codec()
}
