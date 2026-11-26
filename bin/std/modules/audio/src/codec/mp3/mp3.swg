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

// Frame lengths vary only with the header's three table indices and padding.
private func buildFrameBytes()->[3, 3, 15] u16
{
    var sizes: #returntype
    for version in 3'u64
    {
        let factor = version == 2 ? 144_000'u32 : 72_000
        for rate in 3'u64
        {
            for bitrate in 15'u64
            {
                let kbits = version == 2 ? BitRatesMpeg1[bitrate] : BitRatesMpeg2[bitrate]
                sizes[version, rate, bitrate] = cast(u16, (factor * kbits / SampleRates[version, rate]))
            }
        }
    }

    return sizes
}

private const FrameBytes = #run buildFrameBytes()

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

    let version = cast(u32, (bytes[1] >> 3)) & 3
    let layer   = cast(u32, (bytes[1] >> 1)) & 3
    if version == 1 do
        fail InvalidFormatError{"MP3 frame states the reserved version"}
    if layer != 1 do
        fail UnsupportedFormatError{"audio decoder reads MPEG Layer III only"}

    let rate = cast(u32, (bytes[2] >> 2)) & 3
    if rate == 3 do
        fail InvalidFormatError{"MP3 frame states the reserved sampling frequency"}

    let bitrateIndex = cast(u32, (bytes[2] >> 4)) & 15
    if not bitrateIndex do
        fail UnsupportedFormatError{"audio decoder does not read free-format MP3"}
    if bitrateIndex == 15 do
        fail InvalidFormatError{"MP3 frame states the reserved bit rate"}

    var result: #returntype
    result.isMpeg1  = version == 3
    result.isMpeg25 = version == 0
    result.hasCrc   = (bytes[1] & 1) == 0

    // Version 2.5 halves version 2, which halves version 1.
    var versionRow = 1'u64
    if result.isMpeg1 do
        versionRow = 2
    elif result.isMpeg25 do
        versionRow = 0
    result.sampleRate = SampleRates[versionRow, cast(u64, rate)]

    // The band tables are indexed by one widened number covering all three versions.
    if result.isMpeg1 do
        result.rateIndex = 5 + rate
    elif result.isMpeg25 do
        result.rateIndex = rate == 2 ? 1 : 0
    else do
        result.rateIndex = 2 + rate

    result.mode          = cast(u32, (bytes[3] >> 6)) & 3
    result.modeExtension = cast(u32, (bytes[3] >> 4)) & 3
    result.channels      = result.mode == 3 ? 1 : 2
    result.granules      = result.isMpeg1 ? 2 : 1
    result.frameSamples  = result.isMpeg1 ? 1152 : 576

    let padding = cast(u64, (bytes[2] >> 1)) & 1
    result.frameBytes = cast(u64, FrameBytes[versionRow, rate, bitrateIndex]) + padding
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
    data:      const [*] u8?
    bitEnd:    u64
    bitPos:    u64
    cache:     u64
    available: u32
    nextByte:  u64
}

impl BitReader
{
    func create(payload: const [..] u8)->BitReader
        => BitReader{data: payload.buffer, bitEnd: payload.count * 8}

    // Append a big-endian word to the left-justified cache. End-of-payload zeros
    // occupy ordinary cache slots; bitEnd and bitPos still track a physical overrun.
    mtd refill()
    {
        let at        = .nextByte
        let remaining = .bitEnd >> 3
        var word: u32
        if at + 4 <= remaining
        {
            let data = unwrap .data
            word = Math.bigEndianToNative(cast(const [*] u32, data + at)[0])
        }
        elif at < remaining
        {
            let data = unwrap .data
            for i in remaining - at do
                word |= cast(u32, data[at + i]) << cast(u32, (24 - 8 * i))
        }

        .cache     |= cast(u64, word) << (32 - .available)
        .available += 32
        .nextByte  += 4
    }

    #[Swag.Inline]
    mtd peek(count: u32)->u32
    {
        if .available < count do
            .refill()
        return cast(u32, .cache >> (64 - count))
    }

    #[Swag.Inline]
    mtd consume(count: u32)
    {
        .cache     <<= count
        .available -= count
        .bitPos    += count
    }

    // Reads up to 24 bits and preserves the old zero padding after a truncated granule.
    #[Swag.Inline]
    mtd read(count: u32)->u32
    {
        if not count do
            return 0
        let value = .peek(count)
        .consume(count)
        return value
    }

    #[Swag.Inline]
    mtd readBit()->u32 => .read(1)

    mtd seek(position: u64)
    {
        if position >= .bitPos and position - .bitPos <= .available
        {
            .consume(cast(u32, (position - .bitPos)))
            return
        }

        .nextByte  = position >> 3
        .bitPos    = position & ~7'u64
        .cache     = 0
        .available = 0
        discard .read(cast(u32, (position & 7)))
    }

    #[Swag.Inline]
    mtd readMagnitude(value, escape: u32, gain: f32)->f32
    {
        var magnitude = value
        if value == 15 and escape do
            magnitude += .read(escape)
        if not magnitude do
            return 0

        let sample = Powers43[magnitude] * gain
        return .readBit() ? -sample : sample
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
        let rate = cast(u64, rateIndex)
        if .bandKind == 1 do
            return band < 40 ? cast(u32, ScfBandShort[rate, band]) : 0
        if .bandKind == 2 do
            return band < 40 ? cast(u32, ScfBandMixed[rate, band]) : 0
        return band < 23 ? cast(u32, ScfBandLong[rate, band]) : 0
    }

    mtd const bandCount()->u64 => cast(u64, .longBands) + cast(u64, .shortBands)
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
        mainDataBegin = cast(u64, reader.read(9))
        discard reader.read(header.channels == 1 ? 5 : 3)
        scfsi = reader.read(4 * header.channels)
    }
    else
    {
        mainDataBegin = cast(u64, reader.read(8))
        discard reader.read(header.channels == 1 ? 1 : 2)
    }

    for granule in header.granules
    {
        for channel in header.channels
        {
            let info = &granules[][cast(u64, granule), cast(u64, channel)]
            info.part23Length = reader.read(12)
            info.bigValues    = reader.read(9)
            if info.bigValues > 288 do
                fail InvalidFormatError{"MP3 granule codes more spectral lines than a granule holds"}
            info.globalGain       = reader.read(8)
            info.scalefacCompress = reader.read(header.isMpeg1 ? 4 : 9)

            info.longBands  = 22
            info.shortBands = 0
            info.bandKind   = 0
            if reader.readBit() != 0
            {
                info.blockType = reader.read(2)
                if not info.blockType do
                    fail InvalidFormatError{"MP3 granule switches windows and then states a normal block"}
                info.mixedBlock = reader.readBit() != 0

                info.regionBands[0] = 7
                info.regionBands[1] = 255
                if info.blockType == 2
                {
                    if not info.mixedBlock
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

            info.preflag       = header.isMpeg1 ? reader.readBit() != 0 : info.scalefacCompress >= 500
            info.scalefacScale = reader.readBit()
            info.count1Table   = reader.readBit()

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

    sampleRate:    u32
    channels:      u32
    mainData:      Array'u8
    reservoirSize: u64
    state:         [2] ChannelState
    lines:         [2] Granule576
    scalefac:      [2, 40] u8     // The previous granule's, for the bands `scfsi` shares.
    intensityPos:  [2, 40] u8
    bandGain:      [2, 40] f32
    output:        [2, 1152] f32
    ready:         bool
}

// The largest Huffman magnitude is 15 plus a 13-bit escape value.
private func buildPowers43()->[15 + (1 << 13)] f32
{
    var powers: #returntype
    for value in powers.count do
        powers[value] = cast(f32, Math.pow(cast(f64, value), 4.0'f64 / 3.0'f64))
    return powers
}

private const Powers43 = #run buildPowers43()

// A gain exponent is in quarter steps from global_gain minus 210. Mid/side subtracts two
// steps. A five-bit scalefactor can cost four steps per unit and short-window gain another
// eight per unit of its three-bit field. The long-block preemphasis fits within that bound.
private const MinGainExponent = -210 - 2 - 4 * 31 - 8 * 7
private const MaxGainExponent = 255 - 210

private func buildBandGains()->[MaxGainExponent - MinGainExponent + 1] f32
{
    var gains: #returntype
    for index in gains.count
    {
        let exponent = cast(s32, index) + MinGainExponent
        gains[index] = cast(f32, Math.pow(2.0'f64, cast(f64, exponent) / 4.0'f64))
    }

    return gains
}

private const BandGains = #run buildBandGains()

private const Count1TableA = 25'u32
private const Count1TableB = 26'u32

// The decoding tree for a resolved Huffman table number.
private func codeTree(table: u32)->const [..] s16
{
    switch table
    {
    case 1:            return Huff1Tree
    case 2:            return Huff2Tree
    case 3:            return Huff3Tree
    case 5:            return Huff5Tree
    case 6:            return Huff6Tree
    case 7:            return Huff7Tree
    case 8:            return Huff8Tree
    case 9:            return Huff9Tree
    case 10:           return Huff10Tree
    case 11:           return Huff11Tree
    case 12:           return Huff12Tree
    case 13:           return Huff13Tree
    case 15:           return Huff15Tree
    case 16:           return Huff16Tree
    case 24:           return Huff24Tree
    case Count1TableA: return Count1ATree
    case Count1TableB: return Count1BTree
    }

    return Huff1Tree
}

// How many values one axis of that table holds, which is what splits a symbol into its pair.
private func codeWidth(table: u32)->u32
{
    switch table
    {
    case 1:          return 2
    case 2, 3:       return 3
    case 5, 6:       return 4
    case 7, 8, 9:    return 6
    case 10, 11, 12: return 8
    case 13, 15, 16, 24, Count1TableA, Count1TableB: return 16
    }

    return 1
}

// A pair's magnitudes occupy two nibbles; a count1 symbol is already a four-bit mask.
#[Swag.Inline]
private func packSymbol(symbol, axis: u32)->u32
    => (symbol / axis) << 4 | (symbol % axis)

// A complete prefix reaches a negative leaf. Otherwise it names the node where
// the bitwise walk must resume.
private func walkPrefix(tree: const [..] s16, prefix, bits: u32)->{node: s16, length: u32}
{
    var node = 0's16
    for length in 1 until bits + 1
    {
        let bit = (prefix >> (bits - length)) & 1
        node = tree[cast(u32, node) * 2 + bit]
        if node < 0 do
            return {node, length}
    }

    return {node, bits}
}

// Ten bits cover the longest count1 code and all four signs that can follow it.
private const Count1PrefixBits = 10'u32

private func buildCount1Tokens()->[2, 1 << Count1PrefixBits] u16
{
    var tokens: #returntype
    for table in 2'u32
    {
        let tree = codeTree(Count1TableA + table)
        for prefix in 1'u32 << Count1PrefixBits
        {
            let {node, length} = walkPrefix(tree, prefix, Count1PrefixBits)
            Swag.require(node < 0)
            let symbol = cast(u32, (-node - 1))
            var total  = length
            var values = 0'u32
            for i in 4'u32 where (symbol & (8'u32 >> i)) != 0
            {
                total += 1
                let sign = (prefix >> (Count1PrefixBits - total)) & 1
                values |= (1 | (sign << 1)) << (2 * i)
            }

            tokens[table, prefix] = cast(u16, (values | (length << 8) | (total << 12)))
        }
    }

    return tokens
}

private const Count1Tokens        = #run buildCount1Tokens()
private const SignedUnit: [4] f32 = [0.0, 1.0, 0.0, -1.0]

private const PairPrefixBits = 10'u32

// Leaf entries carry two five-bit magnitudes with signs, the four-bit code length,
// and the two-bit sign count. A sign count of three leaves the trailing bits to the
// reader. A zero code length carries a continuation node instead of magnitudes.
private func buildSignedPairTokens()->[25, 1 << PairPrefixBits] u16
{
    var tokens: #returntype
    for table in 25'u32
    {
        let tree = codeTree(table)
        let axis = codeWidth(table)
        for prefix in 1'u32 << PairPrefixBits
        {
            let {node, length} = walkPrefix(tree, prefix, PairPrefixBits)
            if node >= 0
            {
                Swag.require(node < 1024)
                tokens[table, prefix] = cast(u16, node)
                continue
            }

            let pair    = packSymbol(cast(u32, (-node - 1)), axis)
            var left    = pair >> 4
            var right   = pair & 15
            let signs   = cast(u32, left != 0) + cast(u32, right != 0)
            let escapes = (table == 16 or table == 24) and (left == 15 or right == 15)
            if escapes or length + signs > PairPrefixBits
            {
                tokens[table, prefix] = cast(u16, (right | (left << 5) | (length << 10) | (3 << 14)))
                continue
            }

            var total = length
            if left
            {
                total += 1
                left  |= ((prefix >> (PairPrefixBits - total)) & 1) << 4
            }

            if right
            {
                total += 1
                right |= ((prefix >> (PairPrefixBits - total)) & 1) << 4
            }

            tokens[table, prefix] = cast(u16, (right | (left << 5) | (length << 10) | (signs << 14)))
        }
    }

    return tokens
}

private func buildSignedPowers()->[32] f32
{
    var values: #returntype
    for value in values.count do
        values[value] = value & 16 ? -Powers43[value & 15] : Powers43[value & 15]
    return values
}

private const SignedPairTokens = #run buildSignedPairTokens()
private const SignedPowers     = #run buildSignedPowers()

impl Codec
{
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
        var partitionRow = 0'u64
        if info.shortBands do
            partitionRow += 1
        if not info.longBands do
            partitionRow += 1
        var partitionAt = 0'u64
        if header.isMpeg1
        {
            let packed = cast(u32, ScfCompress[cast(u64, info.scalefacCompress)])
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
            var remaining = cast(s32, (info.scalefacCompress >> (intensity ? 1'u32 : 0'u32)))
            var k         = intensity ? 12'u64 : 0'u64
            for
            {
                var product = 1's32
                var index   = 3's32
                while index >= 0
                {
                    let modulus = cast(s32, LsfModulus[k + cast(u64, index)])
                    sizes[cast(u64, index)] = cast(u32, (remaining / product % modulus))
                    product *= modulus
                    index   -= 1
                }

                remaining -= product
                k         += 4
                if remaining < 0 do
                    break
            }

            partitionAt = k
        }

        for index in 4'u64 do
            counts[index] = cast(u32, LsfPartitions[partitionRow, partitionAt + index])

        var values: [40] u8
        var at    = 0'u64
        var share = info.scfsi
        for partition in 4'u64
        {
            let count = cast(u64, counts[partition])
            if not count do
                break

            if header.isMpeg1 and (share & 8) != 0
            {
                // This partition keeps the values the previous granule read.
                for index in count where at + index < 40 do
                    values[at + index] = .scalefac[cast(u64, channel), at + index]
            }
            else
            {
                let bits = sizes[partition]
                let full = bits ? (1'u32 << bits) - 1 : 0'u32
                for index in count where at + index < 40
                {
                    let value = bits ? reader.read(bits) : 0'u32
                    values[at + index] = cast(u8, value)

                    // A low sampling frequency granule marks an unusable intensity position by
                    // saturating the field.
                    if not header.isMpeg1 and bits and value == full do
                        .intensityPos[cast(u64, channel), at + index] = 255
                    else do
                        .intensityPos[cast(u64, channel), at + index] = cast(u8, value)
                }
            }

            if header.isMpeg1
            {
                for index in count where at + index < 40 do
                    .intensityPos[cast(u64, channel), at + index] = values[at + index]
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
            .scalefac[cast(u64, channel), index] = values[index]

        // Subblock gain lowers a whole short window; preemphasis raises the top long bands.
        var scaled: [40] s32
        for index in 40'u64 do
            scaled[index] = cast(s32, values[index])
        if info.shortBands
        {
            let up    = 3 - cast(s32, shift)
            var index = 0'u64
            while index < cast(u64, info.shortBands)
            {
                for window in 3'u64 where cast(u64, info.longBands) + index + window < 40 do
                    scaled[cast(u64, info.longBands) + index + window] += cast(s32, info.subblockGain[window]) << up
                index += 3
            }
        }
        elif info.preflag
        {
            for index in 10'u64 where 11 + index < 40 do
                scaled[11 + index] += cast(s32, Preemphasis[index])
        }

        // Mid/side scales both channels down by the square root of two, which the intensity path
        // takes back for the bands it owns.
        var exponent = cast(s32, info.globalGain) - 210
        if header.isMidSide() do
            exponent -= 2

        for index in 40'u64
        {
            let power = exponent - (scaled[index] << shift)
            .bandGain[cast(u64, channel), index] = BandGains[cast(u64, (power - MinGainExponent))]
        }
    }

    // Resumes a tree walk after a complete prefix that did not reach a leaf.
    #[Swag.Inline]
    mtd const decodeSymbolTail(tree: const [..] s16, start, axis: u32, reader: *BitReader)->s32
    {
        var node = cast(s32, start)
        for PairPrefixBits until 32'u32
        {
            let slot = cast(u64, (node * 2)) + cast(u64, reader.readBit())
            if slot >= tree.count do
                return -1
            let next = tree[slot]
            if next < 0 do
                return cast(s32, packSymbol(cast(u32, (-next - 1)), axis))
            node = cast(s32, next)
        }

        return -1
    }

    // Decodes the spectral lines of one granule of one channel and requantizes them.
    //
    // The lines are read as pairs while `big_values` lasts and as quadruples afterwards, and both
    // walk the same list of scalefactor bands: the band a line belongs to is what says which gain
    // multiplies it, and the walk does not restart between the two regions.
    mtd decodeSpectrum(header: const *FrameHeader, info: const *GranuleInfo, reader: *BitReader, channel: u32, limit: u64)
    {
        let lines = &.lines[cast(u64, channel)]
        for index in 576'u64 do
            lines[][index] = 0

        var line      = 0'u64
        var band      = 0'u64
        var pairsLeft = 0'u64     // Pairs the current band still holds.
        var gain      = 0'f32
        var big       = cast(u64, info.bigValues)
        var region    = 0'u64
        var ended     = false

        while region < 3 and big and not ended
        {
            let select = info.tableSelect[region]

            // Table zero codes nothing at all: its region is a run of zero pairs that occupies no
            // bit. Reading one anyway moves the bit position and loses the rest of the granule.
            let table  = cast(u32, HuffCodeTable[cast(u64, select)])
            let empty  = table == 0
            let tree   = codeTree(table)
            let axis   = codeWidth(table)
            let escape = cast(u32, HuffLinbits[cast(u64, select)])
            var spans  = cast(s32, info.regionBands[region]) + 1
            region += 1

            while big and spans > 0
            {
                let width = info.bandWidth(header.rateIndex, band)
                if not width
                {
                    ended = true
                    break
                }

                gain  = .bandGain[cast(u64, channel), band]
                band  += 1
                spans -= 1

                pairsLeft = cast(u64, width) / 2
                let take = Math.min(big, pairsLeft)
                big       -= take
                pairsLeft -= take

                // The granule was cleared above. Each of its at most 288 big-value pairs
                // advances by two lines, including runs with no codewords.
                if empty
                {
                    line += take * 2
                    continue
                }

                for take
                {
                    let token = cast(u32, SignedPairTokens[table, reader.peek(PairPrefixBits)])
                    let bits  = (token >> 10) & 15
                    if bits
                    {
                        if reader.bitPos + bits > limit do
                            return
                        let signs = token >> 14
                        if signs == 3
                        {
                            reader.consume(bits)
                            lines[][line]     = reader.readMagnitude((token >> 5) & 15, escape, gain)
                            lines[][line + 1] = reader.readMagnitude(token & 15, escape, gain)
                        }
                        else
                        {
                            reader.consume(bits + signs)
                            lines[][line]     = SignedPowers[(token >> 5) & 31] * gain
                            lines[][line + 1] = SignedPowers[token & 31] * gain
                        }

                        line += 2
                        continue
                    }

                    reader.consume(PairPrefixBits)
                    let symbol = .decodeSymbolTail(tree, token, axis, reader)
                    if symbol < 0 or reader.bitPos > limit do
                        return

                    let pair = cast(u32, symbol)
                    lines[][line]     = reader.readMagnitude(pair >> 4, escape, gain)
                    lines[][line + 1] = reader.readMagnitude(pair & 15, escape, gain)
                    line += 2
                }
            }
        }

        // The token includes the signs of both pairs. The code length still bounds
        // the granule independently of the sign bits.
        while line + 4 <= 576 and reader.bitPos < limit and not ended
        {
            let token = cast(u32, Count1Tokens[info.count1Table, reader.peek(Count1PrefixBits)])
            if reader.bitPos + ((token >> 8) & 15) > limit do
                break
            reader.consume(token >> 12)

            // The scalefactor band can change between the quadruple's two pairs.
            for half in 2'u32
            {
                if not pairsLeft
                {
                    let width = info.bandWidth(header.rateIndex, band)
                    if not width
                    {
                        ended = true
                        break
                    }

                    gain      = .bandGain[cast(u64, channel), band]
                    band      += 1
                    pairsLeft = cast(u64, width) / 2
                }

                pairsLeft -= 1
                let value = token >> (half * 4)
                lines[][line]     = SignedUnit[value & 3] * gain
                lines[][line + 1] = SignedUnit[(value >> 2) & 3] * gain
                line += 2
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
        let takeBack = midSide ? cast(f32, Math.sqrt(2.0'f64)) : 1.0'f32

        // The intensity region starts where the right channel stopped carrying anything.
        var topBand: [3] s32 = [-1, -1, -1]
        if header.isIntensity()
        {
            var line = 0'u64
            for band in info.bandCount()
            {
                let width = cast(u64, info.bandWidth(header.rateIndex, band))
                if not width do
                    break
                var index = 0'u64
                while index < width
                {
                    if line + index < 576 and right[][line + index] != 0
                    {
                        topBand[band % 3] = cast(s32, band)
                        break
                    }

                    index += 1
                }

                line += width
            }

            if info.longBands
            {
                let top = Math.max(topBand[0], topBand[1], topBand[2])
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
                let prev = cast(s64, top) - cast(s64, blocks)
                if top >= 40 do
                    continue
                if prev >= 0 and topBand[index] < cast(s32, prev) do
                    .intensityPos[1, top] = .intensityPos[1, cast(u64, prev)]
                else do
                    .intensityPos[1, top] = neutral
            }
        }

        var line = 0'u64
        for band in info.bandCount()
        {
            let width = cast(u64, info.bandWidth(header.rateIndex, band))
            if not width do
                break

            let position = cast(u32, .intensityPos[1, band])
            if header.isIntensity() and cast(s32, band) > topBand[band % 3] and position < maxPos
            {
                var kl = 1.0'f32
                var kr = 1.0'f32
                if header.isMpeg1
                {
                    kl = Pan[cast(u64, position), 0]
                    kr = Pan[cast(u64, position), 1]
                }
                else
                {
                    kr = cast(f32, Math.pow(2.0'f64, -cast(f64, ((position + 1) >> 1 << lsfShift)) / 4.0'f64))
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
        let lines = &.lines[cast(u64, channel)]

        // A short block interleaves its windows, and a mixed block does so past its long bands.
        if info.blockType == 2
        {
            var firstLine = 0'u32
            var firstBand = 0'u64
            for band in cast(u64, info.longBands)
            {
                firstLine += info.bandWidth(header.rateIndex, band)
                firstBand += 1
            }

            var widths: [40] u8
            for band in 40'u64 do
                widths[band] = cast(u8, info.bandWidth(header.rateIndex, band))
            reorderShortBlocks(lines, widths, cast(u32, firstBand), firstLine)
        }

        // Only long blocks were aliased. A mixed block aliased its long part alone.
        var aliased = 32'u32
        if info.blockType == 2
        {
            if info.mixedBlock do
                aliased = header.rateIndex == 1 ? 4 : 2
            else do
                aliased = 1
        }

        reduceAlias(lines, aliased)

        var longSubbands = 0'u32
        if info.blockType == 2 and info.mixedBlock
        {
            if header.rateIndex == 1 do
                longSubbands = 4
            else do
                longSubbands = 2
        }
        elif info.blockType != 2
        {
            longSubbands = 32
        }

        let overlap    = &.state[cast(u64, channel)].overlap
        let longWindow = info.blockType == 2 ? 0'u32 : info.blockType
        inverseTransformBands(lines, overlap, 0, longSubbands, longWindow)
        inverseTransformBands(lines, overlap, longSubbands, 32, 2)

        invertFrequencies(lines)

        let base = cast(u64, granule) * 576
        synthesizeGranule(&.state[cast(u64, channel)], lines, &.output[cast(u64, channel), base])
    }

    // Restores the state a decode starts from.
    mtd resetState()
    {
        for channel in 2'u64 do
            .state[channel].reset()
        .mainData.clear()
        .reservoirSize = 0
        Memory.set(cast(*void, &.scalefac[0, 0]), 0, 2 * 40)
        Memory.set(cast(*void, &.intensityPos[0, 0]), 0, 2 * 40)
        .ready = false
    }

    // Decodes a validated frame into `.output`.
    mtd decodeFrame(packet: const [..] u8, header: const *FrameHeader) fail
    {
        var at = 4'u64
        if header.hasCrc do
            at += 2
        if at + header.sideInfoBytes > header.frameBytes do
            fail InvalidFormatError{"MP3 frame is too short for its side information"}

        var granules: [2, 2] GranuleInfo
        let mainDataBegin = try readSideInfo(header, packet[at until at + header.sideInfoBytes], &granules)
        at += header.sideInfoBytes

        // Keep only the requested tail from the preceding frame, in the same reusable buffer.
        let available = Math.min(mainDataBegin, .reservoirSize)
        if available
        {
            let data = .mainData.storage()
            Memory.copyOverlapping(data, data + .mainData.count - available, available)
        }

        .mainData.resize(available)
        .mainData.add(packet[at until header.frameBytes])

        // A frame that reaches further back than what was kept cannot be decoded; every frame
        // after it can, so the stream restarts rather than failing.
        let usable = available >= mainDataBegin
        var reader = BitReader.create(.mainData.toSlice())

        if usable
        {
            for granule in header.granules
            {
                for channel in header.channels
                {
                    let info  = &granules[cast(u64, granule), cast(u64, channel)]
                    let start = reader.bitPos
                    .readScalefactors(header, info, &reader, channel)
                    .decodeSpectrum(header, info, &reader, channel, start + cast(u64, info.part23Length))
                    reader.seek(start + cast(u64, info.part23Length))
                }

                if header.channels == 2 and header.mode == 1
                {
                    let next = &granules[cast(u64, granule), 1]
                    .processStereo(header, &granules[cast(u64, granule), 0], next.scalefacCompress & 1)
                }

                for channel in header.channels do
                    .synthesizeChannel(header, &granules[cast(u64, granule), cast(u64, channel)], channel, granule)
            }
        }
        else
        {
            for channel in 2'u64 do
                .state[channel].reset()
            for channel in header.channels
            {
                for index in cast(u64, header.frameSamples) do
                    .output[channel, index] = 0
            }
        }

        // The unused suffix is the reservoir for the next frame.
        let consumed = Math.min((reader.bitPos + 7) / 8, .mainData.count)
        .reservoirSize = Math.min(.mainData.count - consumed, ReservoirBytes)
    }
}

#[Swag.Inline]
private func packPcm16(source: const [*] f32)->Math.Simd.S16x8
{
    using Math.Simd
    let low  = Math.clamp(load(source) * 32767.0, splat(-32768.0'f32), splat(32767.0'f32))
    let high = Math.clamp(load(source + 4) * 32767.0, splat(-32768.0'f32), splat(32767.0'f32))
    return packSigned(truncateToS32(low), truncateToS32(high))
}

impl IPacketCodec for Codec
{
    mtd impl canDecode(encoding: SoundFileEncoding)->bool => encoding == .Mp3

    mtd impl initialize(_: const [..] u8, sampleRateHz, channels: u32) fail
    {
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
        let header = try readHeader(packet)
        if packet.count < header.frameBytes do
            fail InvalidFormatError{"MP3 frame is shorter than its header states"}
        if header.sampleRate != .sampleRate or header.channels != .channels do
            fail InvalidFormatError{"MP3 frame does not match the stream its container declared"}

        let produced = cast(u64, header.frameSamples) * cast(u64, .channels) * #sizeof(s16)
        if destinationSize < produced do
            fail BadParameterError{"MP3 destination buffer is too small"}

        try .decodeFrame(packet, &header)
        let samples = cast([*] s16, destination)
        let groups  = cast(u64, header.frameSamples) / 8
        if .channels == 1
        {
            for index in groups
            {
                let at = index * 8
                Math.Simd.store(samples + at, packPcm16(&.output[0, at]))
            }
        }
        else
        {
            using Math.Simd
            for index in groups
            {
                let at    = index * 8
                let left  = cast #bit(U16x8, packPcm16(&.output[0, at]))
                let right = cast #bit(U16x8, packPcm16(&.output[1, at]))
                store(samples + 2 * at, cast #bit(S16x8, interleaveLow(left, right)))
                store(samples + 2 * at + 8, cast #bit(S16x8, interleaveHigh(left, right)))
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
