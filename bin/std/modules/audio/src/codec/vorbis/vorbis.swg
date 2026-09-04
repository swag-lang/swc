//! Format: Vorbis I audio decoder.
//! Supported: The identification and setup headers, codebooks with every lookup type, floor types 0 and 1, residue types 0, 1, and 2, channel coupling, both block sizes with every window shape, one to eight channels delivered in WAVE order, packets handed over raw or inside runs of Ogg pages, and the trimming of the first and last pages their granule positions ask for.
//! Not supported: The comment header, which is skipped, and chained streams beyond their first link.
//! Role: This file owns Vorbis packet syntax, spectral reconstruction, lapping, and PCM output.
//
#global namespace Vorbis

using Core, Core.Errors, Core.Math

internal const MaxChannels    = 8'u32
private const MinBlockSize    = 64'u32
private const MaxBlockSize    = 8192'u32
private const MaxCodewordBits = 32'u32

// Speaker masks for the channel counts the format defines, in WAVE order.
private const SpeakerMasks: [9] u32 = [0, 0x0004, 0x0003, 0x0007, 0x0033, 0x0037, 0x003F, 0x070F, 0x063F]

// Where each Vorbis channel of a stream lands in the WAVE order of the same speakers.
//
// Vorbis orders a stream as left, center, right, then the surrounds, then the low-frequency
// channel; WAVE puts the center third, the low-frequency channel fourth, and the sides last.
private const ChannelSlots: [9, 8] u32 = [
    [0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0],
    [0, 1, 0, 0, 0, 0, 0, 0],
    [0, 2, 1, 0, 0, 0, 0, 0],
    [0, 1, 2, 3, 0, 0, 0, 0],
    [0, 2, 1, 3, 4, 0, 0, 0],
    [0, 2, 1, 4, 5, 3, 0, 0],
    [0, 2, 1, 5, 6, 4, 3, 0],
    [0, 2, 1, 6, 7, 4, 5, 3]]

// Returns the WAVE speaker mask of a stream of `channels` channels.
internal func speakerMask(channels: u32)->u32 => channels <= 8 ? SpeakerMasks[channels] : 0

// Returns the number of bits needed to hold `value`, which is what the format calls `ilog`.
private func ilog(value: u32)->u32 => value ? 32 - cast(u32) Swag.bitCountLz(value) : 0

// Unpacks the 32-bit floating-point representation the format uses for codebook scales.
private func unpackFloat(raw: u32)->f32
{
    let mantissa = cast(f64) (raw & 0x1FFFFF)
    let exponent = cast(f64) ((raw & 0x7FE00000) >> 21) - 788.0
    let value    = mantissa * Math.pow(2.0, exponent)
    return cast(f32) (raw & 0x80000000 ? -value : value)
}

// Reads the bits of a Vorbis packet, least significant bit first.
//
// Reading past the end returns zeros and records the overrun; the format treats running out of
// data inside the audio of a packet as a normal event, so the decoder checks the flag where it
// matters rather than failing on the spot.
private struct BitReader
{
    data:    const [*] u8?
    size:    u64
    bitPos:  u64
    overran: bool
}

private impl BitReader
{
    func create(payload: const [..] u8)->BitReader => {payload.buffer, payload.count, 0, false}

    // Reads `count` bits, at most 32, as an unsigned value.
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
        var got    = 0'u32
        while got < count
        {
            let bitOffset = cast(u32) (.bitPos & 7)
            let available = 8 - bitOffset
            let take      = Math.min(available, count - got)
            let value     = (cast(u32) .data![.bitPos >> 3] >> bitOffset) & ((1'u32 << take) - 1)
            result  |= value << got
            got     += take
            .bitPos += take
        }

        return result
    }

    mtd readFlag()->bool => .read(1) != 0
}

// One codebook of the setup header: a prefix code over its entries, and the vectors the entries
// may name.
private struct Codebook
{
    dimensions:  u32
    entries:     u32
    usedEntries: u32
    lookupType:  u32
    lengths:     Array'u8
    children:    Array's32     // Two per node; a positive value names a node, a negative one a leaf holding entry `-value - 1`, zero is unassigned.
    values:      Array'f32     // Lookup vectors, `dimensions` values per entry, empty without a lookup.
}

private impl Codebook
{
    // Returns the largest count whose `dimensions`-th power fits the entries: the size of the
    // value list a lookup of type 1 spreads over every dimension.
    mtd const lookup1Values()->u32
    {
        if !.entries do
            return 0
        var count = cast(u32) Math.floor(Math.pow(cast(f64) .entries, 1.0 / cast(f64) .dimensions))
        if !count do
            count = 1
        while count > 1 and !.powerFits(count) do
            count -= 1
        while .powerFits(count + 1) do
            count += 1
        return count
    }

    mtd const powerFits(base: u32)->bool
    {
        var product = 1'u64
        for .dimensions
        {
            product *= base
            if product > .entries do
                return false
        }

        return true
    }

    // Adds the leaf of `entry` at the end of `codeword`, whose `length` bits are read most
    // significant first.
    mtd insert(codeword, length, entry: u32) fail
    {
        var node = 0'u32
        var bit  = length
        while bit
        {
            bit -= 1
            let slot  = cast(u64) node * 2 + ((codeword >> bit) & 1)
            let child = .children[slot]
            if !bit
            {
                if child do
                    fail InvalidFormatError{"Vorbis codebook assigns one codeword twice"}
                .children[slot] = -cast(s32) entry - 1
                return
            }

            if child < 0 do
                fail InvalidFormatError{"Vorbis codebook prefixes one codeword with another"}
            if !child
            {
                .children.add(0)
                .children.add(0)
                let created = cast(s32) (.children.count / 2 - 1)
                .children[slot] = created
                node            = cast(u32) created
            }
            else do
                node = cast(u32) child
        }
    }

    // Assigns every used entry the lowest codeword of its length that no earlier entry took or
    // prefixes, the way clause 3.2.1 of the specification lays out the tree.
    mtd buildTree() fail
    {
        .children.clear()
        .children.add(0)
        .children.add(0)
        .usedEntries = 0

        var marker: [33] u32
        for length, index in .lengths where length
        {
            let bits  = cast(u32) length
            var entry = marker[bits]
            if bits < 32 and (entry >> bits) do
                fail InvalidFormatError{"Vorbis codebook lengths overpopulate the tree"}
            try .insert(entry, bits, cast(u32) index)
            .usedEntries += 1

            // Advance the marker of this length, carrying into the shorter ones that shared the branch.
            var level = bits
            while level
            {
                if marker[level] & 1
                {
                    if level == 1 do
                        marker[1] += 1
                    else do
                        marker[level] = marker[level - 1] << 1
                    break
                }

                marker[level] += 1
                level         -= 1
            }

            // The longer markers that hung from the node just taken now hang from the next one.
            var longer = bits + 1
            while longer < 33
            {
                if (marker[longer] >> 1) != entry do
                    break
                entry          = marker[longer]
                marker[longer] = marker[longer - 1] << 1
                longer         += 1
            }
        }

        // A single codeword of length one is the one tree the format allows to stay incomplete.
        if .usedEntries == 1 and marker[2] == 2 do
            return
        for level in 1'u32 until 33
        {
            if marker[level] & (0xFFFFFFFF'u32 >> (32 - level)) do
                fail InvalidFormatError{"Vorbis codebook lengths underpopulate the tree"}
        }
    }

    // Reads one codeword and returns its entry, or -1 when the packet ends or the code is invalid.
    mtd const decode(reader: *BitReader)->s32
    {
        if !.usedEntries do
            return -1
        var node = 0'u32
        for MaxCodewordBits
        {
            let bit = reader.read(1)
            if reader.overran do
                return -1
            let child = .children[cast(u64) node * 2 + bit]
            if child < 0 do
                return -child - 1
            if !child do
                return -1
            node = cast(u32) child
        }

        return -1
    }

    mtd parse(reader: *BitReader) fail
    {
        if reader.read(24) != 0x564342 do
            fail InvalidFormatError{"Vorbis codebook has no synchronization pattern"}
        .dimensions = reader.read(16)
        .entries    = reader.read(24)
        if !.dimensions do
            fail InvalidFormatError{"Vorbis codebook has no dimensions"}
        .lengths.resize(.entries)

        if !reader.readFlag()
        {
            let sparse = reader.readFlag()
            for index in .entries
            {
                if sparse and !reader.readFlag() do
                    .lengths[index] = 0
                else do
                    .lengths[index] = cast(u8) (reader.read(5) + 1)
            }
        }
        else
        {
            var current = reader.read(5) + 1
            var index   = 0'u32
            while index < .entries
            {
                let count = reader.read(ilog(.entries - index))
                if count > .entries - index do
                    fail InvalidFormatError{"Vorbis codebook length runs exceed its entries"}
                for count
                {
                    .lengths[index] = cast(u8) current
                    index           += 1
                }

                current += 1
                if current > MaxCodewordBits do
                    fail InvalidFormatError{"Vorbis codebook length exceeds thirty-two bits"}
            }
        }

        if reader.overran do
            fail InvalidFormatError{"Vorbis setup header is truncated"}
        try .buildTree()

        .lookupType = reader.read(4)
        if !.lookupType do
            return
        if .lookupType > 2 do
            fail InvalidFormatError{"Vorbis codebook uses a reserved lookup type"}

        let minimum   = unpackFloat(reader.read(32))
        let delta     = unpackFloat(reader.read(32))
        let valueBits = reader.read(4) + 1
        let sequence  = reader.readFlag()
        let quantized = .lookupType == 1 ? .lookup1Values() : .entries * .dimensions
        var quant: Array'f32
        quant.resize(quantized)
        for index in quantized do
            quant[index] = cast(f32) reader.read(valueBits)
        if reader.overran do
            fail InvalidFormatError{"Vorbis setup header is truncated"}

        .values.resize(cast(u64) .entries * .dimensions)
        for entry in .entries
        {
            var last    = 0.0'f32
            var divisor = 1'u64
            for dimension in .dimensions
            {
                var index: u64
                if .lookupType == 1
                {
                    index   = (cast(u64) entry / divisor) % quantized
                    divisor *= quantized
                }
                else do
                    index = cast(u64) entry * .dimensions + dimension
                let value = quant[index] * delta + minimum + last
                if sequence do
                    last = value
                .values[cast(u64) entry * .dimensions + dimension] = value
            }
        }
    }
}

// One floor of the setup header, of type 0 or 1.
private struct Floor
{
    kind: u32

    // Type 0: a linear predictive envelope over a bark-scaled map.
    order:           u32
    rate:            u32
    barkMapSize:     u32
    amplitudeBits:   u32
    amplitudeOffset: u32
    books:           Array'u32
    barkMap:         [2] Array'u32     // Lazily built map from spectral line to bark bin, per block size.

    // Type 1: a piecewise linear curve through posts on a fixed grid.
    partitions:      u32
    partitionClass:  [32] u32
    classDimensions: [16] u32
    classSubclasses: [16] u32
    classMasterbook: [16] u32
    subclassBooks:   [16, 8] s32
    multiplier:      u32
    posts:           Array'u32     // X position of every post, in the order the packet states them.
    sortedPosts:     Array'u32     // Post indices in increasing X.
    lowNeighbor:     Array'u32     // For every post, the nearest lower earlier post.
    highNeighbor:    Array'u32     // For every post, the nearest higher earlier post.
}

private impl Floor
{
    mtd parse(reader: *BitReader, codebooks: u32) fail
    {
        .kind = reader.read(16)
        if .kind == 0 do
            try .parseType0(reader, codebooks)
        elif .kind == 1 do
            try .parseType1(reader, codebooks)
        else do
            fail InvalidFormatError{"Vorbis floor uses a reserved type"}
    }

    mtd parseType0(reader: *BitReader, codebooks: u32) fail
    {
        .order           = reader.read(8)
        .rate            = reader.read(16)
        .barkMapSize     = reader.read(16)
        .amplitudeBits   = reader.read(6)
        .amplitudeOffset = reader.read(8)
        let count = reader.read(4) + 1
        for count
        {
            let book = reader.read(8)
            if book >= codebooks do
                fail InvalidFormatError{"Vorbis floor names a codebook that does not exist"}
            .books.add(book)
        }

        if !.order or !.rate or !.barkMapSize do
            fail InvalidFormatError{"Vorbis floor 0 states an empty configuration"}
    }

    mtd parseType1(reader: *BitReader, codebooks: u32) fail
    {
        .partitions = reader.read(5)
        var maxClass = 0'u32
        for index in .partitions
        {
            .partitionClass[index] = reader.read(4)
            maxClass               = Math.max(maxClass, .partitionClass[index] + 1)
        }

        for cls in maxClass
        {
            .classDimensions[cls] = reader.read(3) + 1
            .classSubclasses[cls] = reader.read(2)
            if .classSubclasses[cls]
            {
                .classMasterbook[cls] = reader.read(8)
                if .classMasterbook[cls] >= codebooks do
                    fail InvalidFormatError{"Vorbis floor names a codebook that does not exist"}
            }

            for sub in 1'u32 << .classSubclasses[cls]
            {
                let book = cast(s32) reader.read(8) - 1
                if book >= cast(s32) codebooks do
                    fail InvalidFormatError{"Vorbis floor names a codebook that does not exist"}
                .subclassBooks[cls, sub] = book
            }
        }

        .multiplier = reader.read(2) + 1
        let rangeBits = reader.read(4)
        .posts.add(0)
        .posts.add(1'u32 << rangeBits)
        for index in .partitions
        {
            let cls = .partitionClass[index]
            for .classDimensions[cls] do
                .posts.add(reader.read(rangeBits))
        }

        if reader.overran do
            fail InvalidFormatError{"Vorbis setup header is truncated"}

        // The posts are rendered in increasing X, and every post after the first two predicts
        // itself from the nearest earlier posts on either side.
        let count = cast(u32) .posts.count
        .sortedPosts.resize(count)
        for index in count do
            .sortedPosts[index] = index
        for first in count
        {
            for second in first + 1 until count
            {
                if .posts[.sortedPosts[second]] < .posts[.sortedPosts[first]]
                {
                    let swap = .sortedPosts[first]
                    .sortedPosts[first]  = .sortedPosts[second]
                    .sortedPosts[second] = swap
                }
            }
        }

        for index in 1'u32 until count
        {
            if .posts[.sortedPosts[index]] == .posts[.sortedPosts[index - 1]] do
                fail InvalidFormatError{"Vorbis floor places two posts at the same position"}
        }

        .lowNeighbor.resize(count)
        .highNeighbor.resize(count)
        for index in 2'u32 until count
        {
            var low  = 0'u32
            var high = 1'u32
            for earlier in index
            {
                if .posts[earlier] < .posts[index] and .posts[earlier] >= .posts[low] do
                    low = earlier
                if .posts[earlier] > .posts[index] and .posts[earlier] <= .posts[high] do
                    high = earlier
            }

            .lowNeighbor[index]  = low
            .highNeighbor[index] = high
        }
    }

    // Builds the map from spectral line to bark bin for a half block of `half` lines.
    mtd buildBarkMap(which: u32, half: u32)
    {
        func bark(frequency: f64)->f64 => 13.1 * Math.atan(0.00074 * frequency) + 2.24 * Math.atan(1.85e-8 * frequency * frequency) + 1e-4 * frequency

        let map = &.barkMap[which]
        map.resize(cast(u64) half + 1)
        let scale = cast(f64) .barkMapSize / bark(cast(f64) .rate / 2.0)
        for line in half
        {
            var value = cast(s64) Math.floor(bark(cast(f64) .rate / 2.0 / cast(f64) half * cast(f64) line) * scale)
            if value < 0 do
                value = 0
            if value >= cast(s64) .barkMapSize do
                value = cast(s64) .barkMapSize - 1
            map[][line] = cast(u32) value
        }

        map[][half] = Swag.U32.Max
    }
}

// One residue of the setup header, of type 0, 1, or 2.
private struct Residue
{
    kind:            u32
    begin:           u32
    end:             u32
    partitionSize:   u32
    classifications: u32
    classbook:       u32
    stages:          u32     // Passes the cascade of any class needs.
    cascade:         [64] u32
    books:           [64, 8] s32
}

private impl Residue
{
    mtd parse(reader: *BitReader, codebooks: const [..] Codebook) fail
    {
        .kind = reader.read(16)
        if .kind > 2 do
            fail InvalidFormatError{"Vorbis residue uses a reserved type"}
        .begin           = reader.read(24)
        .end             = reader.read(24)
        .partitionSize   = reader.read(24) + 1
        .classifications = reader.read(6) + 1
        .classbook       = reader.read(8)
        if .classbook >= codebooks.count do
            fail InvalidFormatError{"Vorbis residue names a codebook that does not exist"}

        for cls in .classifications
        {
            var bits = reader.read(3)
            if reader.readFlag() do
                bits |= reader.read(5) << 3
            .cascade[cls] = bits
            .stages       = Math.max(.stages, ilog(bits))
        }

        for cls in .classifications
        {
            for stage in 8
            {
                .books[cls, stage] = -1
                if .cascade[cls] & (1'u32 << stage)
                {
                    let book = reader.read(8)
                    if book >= codebooks.count do
                        fail InvalidFormatError{"Vorbis residue names a codebook that does not exist"}
                    if !codebooks[book].lookupType do
                        fail InvalidFormatError{"Vorbis residue names a codebook that carries no vectors"}
                    .books[cls, stage] = cast(s32) book
                }
            }
        }

        if reader.overran do
            fail InvalidFormatError{"Vorbis setup header is truncated"}
    }
}

// One mapping of the setup header: which floor and residue each channel uses, and the coupling.
private struct Mapping
{
    submaps:       u32
    couplingSteps: u32
    magnitude:     Array'u32
    angle:         Array'u32
    mux:           [MaxChannels] u32
    submapFloor:   [16] u32
    submapResidue: [16] u32
}

private impl Mapping
{
    mtd parse(reader: *BitReader, channels, floors, residues: u32) fail
    {
        if reader.read(16) != 0 do
            fail InvalidFormatError{"Vorbis mapping uses a reserved type"}
        .submaps = reader.readFlag() ? reader.read(4) + 1 : 1
        if reader.readFlag()
        {
            .couplingSteps = reader.read(8) + 1
            let bits = ilog(channels - 1)
            for .couplingSteps
            {
                let magnitude = reader.read(bits)
                let angle     = reader.read(bits)
                if magnitude >= channels or angle >= channels or magnitude == angle do
                    fail InvalidFormatError{"Vorbis coupling names an invalid channel pair"}
                .magnitude.add(magnitude)
                .angle.add(angle)
            }
        }

        if reader.read(2) != 0 do
            fail InvalidFormatError{"Vorbis mapping sets reserved bits"}
        if .submaps > 1
        {
            for channel in channels
            {
                .mux[channel] = reader.read(4)
                if .mux[channel] >= .submaps do
                    fail InvalidFormatError{"Vorbis mapping routes a channel to a submap that does not exist"}
            }
        }

        for submap in .submaps
        {
            discard reader.read(8)
            .submapFloor[submap]   = reader.read(8)
            .submapResidue[submap] = reader.read(8)
            if .submapFloor[submap] >= floors or .submapResidue[submap] >= residues do
                fail InvalidFormatError{"Vorbis mapping names a floor or residue that does not exist"}
        }

        if reader.overran do
            fail InvalidFormatError{"Vorbis setup header is truncated"}
    }
}

// One mode of the setup header: a block size and a mapping.
private struct Mode
{
    longBlock: bool
    mapping:   u32
}

// Decodes Vorbis packets, one run of Ogg pages or one raw packet per call.
//
// The codec keeps the lapping state of the previous block and, when it decodes page runs, the
// granule position the last run ended on, which is what lets it trim the first and last runs
// exactly as the container promised.
private struct Codec
{
    // Every registered codec starts with the registry's own header: a voice destroys one through
    // this, reading back the concrete type and the allocator the instance was made with.
    using base: Audio.Codec

    channels:   u32
    sampleRate: u32
    blockSizes: [2] u32
    codebooks:  Array'Codebook
    floors:     Array'Floor
    residues:   Array'Residue
    mappings:   Array'Mapping
    modes:      Array'Mode
    modeBits:   u32

    slopes:     [2] Array'f32     // Window slopes for the short and the long half block.
    transforms: [2] Mdct

    spectrum:     [MaxChannels] Array'f32     // Residue, then the floored spectrum, of every channel.
    timeDomain:   Array'f32                   // One channel of transform output.
    saved:        [MaxChannels] Array'f32     // Right half of the previous windowed block.
    previousSize: u32                         // Zero before the first block has been decoded.

    floorPosts:   [MaxChannels] Array's32      // Floor 1 post values of every channel.
    floorUsed:    [MaxChannels] Array'bool     // Whether each post takes part in the rendering.
    floorCurve:   [MaxChannels] Array'f32      // Floor 0 coefficients, with the amplitude last.
    floorPresent: [MaxChannels] bool           // The channel's floor was coded in the current block.
    nonzero:      [MaxChannels] bool           // The channel carries residue, coded or through coupling.
    classes:      Array'u32                    // Residue partition classes of the current pass.
    entries:      Array's32                    // Codeword entries of one vector-sliced partition.
    output:       Array's16                    // Interleaved samples of the run being decoded.
    packet:       Array'u8                     // Packet being assembled across pages.

    serial:             u32
    firstAudioSequence: u32
    granule:            u64
    granuleKnown:       bool
}

private impl Codec
{
    mtd resetState()
    {
        for channel in MaxChannels do
            Memory.set(.saved[channel].buffer!, 0, .saved[channel].count * #sizeof(f32))
        .previousSize = 0
        .granuleKnown = false
        .packet.clear()
    }

    // Reads the identification header and sizes the buffers it implies.
    mtd readIdentification(header: const [..] u8) fail
    {
        if header.count < 30 or header[0] != 1 or header[1] != 'v' or header[2] != 'o' or header[3] != 'r' or header[4] != 'b' or header[5] != 'i' or header[6] != 's' do
            fail InvalidFormatError{"Vorbis identification header is missing"}
        var reader = BitReader.create(header[7 until header.count])
        if reader.read(32) != 0 do
            fail UnsupportedFormatError{"Vorbis stream uses an unknown version"}
        .channels   = reader.read(8)
        .sampleRate = reader.read(32)
        discard reader.read(32)
        discard reader.read(32)
        discard reader.read(32)
        .blockSizes[0] = 1'u32 << reader.read(4)
        .blockSizes[1] = 1'u32 << reader.read(4)
        if !reader.readFlag() do
            fail InvalidFormatError{"Vorbis identification header has no framing bit"}
        if !.channels or .channels > MaxChannels do
            fail UnsupportedFormatError{"Vorbis stream needs one to eight channels"}
        if !.sampleRate do
            fail InvalidFormatError{"Vorbis stream declares no sample rate"}
        if .blockSizes[0] < MinBlockSize or .blockSizes[1] < .blockSizes[0] or .blockSizes[1] > MaxBlockSize do
            fail InvalidFormatError{"Vorbis stream declares invalid block sizes"}

        for which in 2
        {
            let half = .blockSizes[which] / 2
            .slopes[which].resize(half)
            for index in half
            {
                let inner = Math.sin((cast(f64) index + 0.5) / cast(f64) half * Math.ConstF64.Pi / 2.0)
                .slopes[which][index] = cast(f32) Math.sin(Math.ConstF64.Pi / 2.0 * inner * inner)
            }

            .transforms[which] = Mdct.create(.blockSizes[which])
        }

        let longHalf = .blockSizes[1] / 2
        .timeDomain.resize(.blockSizes[1])
        for channel in MaxChannels
        {
            .spectrum[channel].resize(longHalf)
            .saved[channel].resize(longHalf)
        }
    }

    // Reads the setup header: codebooks, floors, residues, mappings, and modes.
    mtd readSetup(header: const [..] u8) fail
    {
        if header.count < 7 or header[0] != 5 or header[1] != 'v' or header[2] != 'o' or header[3] != 'r' or header[4] != 'b' or header[5] != 'i' or header[6] != 's' do
            fail InvalidFormatError{"Vorbis setup header is missing"}
        var reader = BitReader.create(header[7 until header.count])

        let bookCount = reader.read(8) + 1
        .codebooks.resize(bookCount)
        for index in bookCount do
            try .codebooks[index].parse(&reader)

        let timeCount = reader.read(6) + 1
        for timeCount
        {
            if reader.read(16) != 0 do
                fail InvalidFormatError{"Vorbis setup header uses a reserved time transform"}
        }

        let floorCount = reader.read(6) + 1
        .floors.resize(floorCount)
        for index in floorCount do
            try .floors[index].parse(&reader, bookCount)

        let residueCount = reader.read(6) + 1
        .residues.resize(residueCount)
        for index in residueCount do
            try .residues[index].parse(&reader, .codebooks.toSlice())

        let mappingCount = reader.read(6) + 1
        .mappings.resize(mappingCount)
        for index in mappingCount do
            try .mappings[index].parse(&reader, .channels, floorCount, residueCount)

        let modeCount = reader.read(6) + 1
        .modes.resize(modeCount)
        for index in modeCount
        {
            .modes[index].longBlock = reader.readFlag()
            if reader.read(16) != 0 or reader.read(16) != 0 do
                fail InvalidFormatError{"Vorbis mode uses a reserved window or transform"}
            .modes[index].mapping = reader.read(8)
            if .modes[index].mapping >= mappingCount do
                fail InvalidFormatError{"Vorbis mode names a mapping that does not exist"}
        }

        .modeBits = ilog(modeCount - 1)
        if !reader.readFlag() or reader.overran do
            fail InvalidFormatError{"Vorbis setup header has no framing bit"}
    }

    // Reads the three header packets out of the pages the container recorded, or out of the
    // laced form a Matroska track carries them in.
    mtd readConfig(config: const [..] u8) fail
    {
        var headers: [3] Array'u8
        if config.count >= 4 and config[0] == 'O' and config[1] == 'g' and config[2] == 'g' and config[3] == 'S'
        {
            var hasSerial = false
            var completed = 0'u32
            var offset    = 0'u64
            while offset < config.count and completed < 3
            {
                let page = try Ogg.readPageHeader(config, offset)
                if offset + page.totalBytes() > config.count do
                    fail InvalidFormatError{"Vorbis header pages are truncated"}
                let body = config[offset + page.headerBytes until offset + page.totalBytes()]
                if !hasSerial
                {
                    if (page.flags & Ogg.FirstPage) and body.count >= 7 and body[0] == 1 and body[1] == 'v' and body[2] == 'o' and body[3] == 'r' and body[4] == 'b' and body[5] == 'i' and body[6] == 's'
                    {
                        .serial   = page.serial
                        hasSerial = true
                    }
                }

                if hasSerial and page.serial == .serial
                {
                    var at = 0'u64
                    for index in page.segments
                    {
                        let size = cast(u64) page.lacing[index]
                        headers[completed].add(body[at until at + size])
                        at += size
                        if size < 255
                        {
                            completed += 1
                            if completed == 3
                            {
                                .firstAudioSequence = page.sequence + 1
                                break
                            }
                        }
                    }
                }

                offset += page.totalBytes()
            }

            if completed < 3 do
                fail InvalidFormatError{"Vorbis stream ends inside its header packets"}
        }
        elif config.count >= 3 and config[0] == 2
        {
            // Xiph lacing: a count, then every size but the last as runs of 255-bytes.
            var offset = 1'u64
            var sizes: [2] u64
            for index in 2
            {
                while true
                {
                    if offset >= config.count do
                        fail InvalidFormatError{"Vorbis header lacing is truncated"}
                    let byte = config[offset]
                    offset       += 1
                    sizes[index] += byte
                    if byte != 255 do
                        break
                }
            }

            if sizes[0] + sizes[1] > config.count - offset do
                fail InvalidFormatError{"Vorbis header lacing exceeds the configuration"}
            headers[0].add(config[offset until offset + sizes[0]])
            headers[1].add(config[offset + sizes[0] until offset + sizes[0] + sizes[1]])
            headers[2].add(config[offset + sizes[0] + sizes[1] until config.count])
        }
        else do
            fail InvalidFormatError{"Vorbis configuration is neither Ogg pages nor laced headers"}

        try .readIdentification(headers[0].toSlice())
        try .readSetup(headers[2].toSlice())
    }

    // Reads the floor of one channel and returns whether the channel carries audio in this block.
    mtd decodeFloor(floor: *Floor, reader: *BitReader, channel: u32)->bool fail
    {
        if floor.kind == 0 do
            return try .decodeFloor0(floor, reader, channel)
        return try .decodeFloor1(floor, reader, channel)
    }

    mtd decodeFloor0(floor: *Floor, reader: *BitReader, channel: u32)->bool fail
    {
        let amplitude = reader.read(floor.amplitudeBits)
        if !amplitude or reader.overran do
            return false
        let bookNumber = reader.read(ilog(cast(u32) floor.books.count))
        if bookNumber >= floor.books.count do
            return false
        let book = &.codebooks[floor.books[bookNumber]]
        if !book.lookupType do
            fail InvalidFormatError{"Vorbis floor 0 names a codebook that carries no vectors"}

        let curve = &.floorCurve[channel]
        curve.resize(cast(u64) floor.order + 1)
        var index = 0'u32
        while index < floor.order
        {
            let entry = book.decode(reader)
            if entry < 0 do
                return false
            for dimension in book.dimensions where index < floor.order
            {
                curve[][index] = book.values[cast(u64) entry * book.dimensions + dimension]
                index          += 1
            }
        }

        // Every vector is stated relative to the last value of the vector before it.
        var last = 0.0'f32
        index = 0
        while index < floor.order
        {
            for dimension in book.dimensions where index < floor.order
            {
                curve[][index] += last
                index          += 1
            }

            last = curve[][index - 1]
        }

        let maximum = cast(f64) ((1'u32 << floor.amplitudeBits) - 1)
        curve[][floor.order] = cast(f32) (cast(f64) amplitude / maximum * cast(f64) floor.amplitudeOffset)
        return true
    }

    mtd decodeFloor1(floor: *Floor, reader: *BitReader, channel: u32)->bool fail
    {
        if !reader.readFlag() do
            return false
        const Ranges: [4] u32 = [256, 128, 86, 64]
        let range = Ranges[floor.multiplier - 1]
        let bits  = ilog(range - 1)
        let count = floor.posts.count
        let posts = &.floorPosts[channel]
        let used  = &.floorUsed[channel]
        posts.resize(count)
        used.resize(count)
        posts[][0] = cast(s32) reader.read(bits)
        posts[][1] = cast(s32) reader.read(bits)

        var offset = 2'u64
        for partition in floor.partitions
        {
            let cls        = floor.partitionClass[partition]
            let dimensions = floor.classDimensions[cls]
            let subBits    = floor.classSubclasses[cls]
            let subMask    = (1'u32 << subBits) - 1
            var value      = 0'u32
            if subBits
            {
                let decoded = .codebooks[floor.classMasterbook[cls]].decode(reader)
                if decoded < 0 do
                    return false
                value = cast(u32) decoded
            }

            for dimension in dimensions
            {
                let book = floor.subclassBooks[cls, value & subMask]
                value >>= subBits
                if book >= 0
                {
                    let decoded = .codebooks[cast(u32) book].decode(reader)
                    if decoded < 0 do
                        return false
                    posts[][offset + dimension] = decoded
                }
                else do
                    posts[][offset + dimension] = 0
            }

            offset += dimensions
        }

        // Every later post is coded against the line through its neighbors, and a zero means it
        // sits on that line and does not bend the curve.
        used[][0] = true
        used[][1] = true
        for index in 2'u64 until count
        {
            let low       = floor.lowNeighbor[index]
            let high      = floor.highNeighbor[index]
            let predicted = renderPoint(cast(s32) floor.posts[low], cast(s32) floor.posts[high], posts[][low], posts[][high], cast(s32) floor.posts[index])
            let highRoom  = cast(s32) range - predicted
            let lowRoom   = predicted
            let room      = Math.min(highRoom, lowRoom) * 2
            var value     = posts[][index]
            if value
            {
                if value >= room do
                    value = highRoom > lowRoom ? value - lowRoom : -1 - (value - highRoom)
                elif value & 1 do
                    value = -((value + 1) >> 1)
                else do
                    value >>= 1
                posts[][index] = (predicted + value) & 0x7FFF
                used[][index]  = true
                used[][low]    = true
                used[][high]   = true
            }
            else
            {
                posts[][index] = predicted
                used[][index]  = false
            }
        }

        return true
    }

    // Multiplies the spectrum of a channel by the curve its floor 0 describes.
    mtd applyFloor0(floor: *Floor, which: u32, channel: u32, half: u32)
    {
        if floor.barkMap[which].count != cast(u64) half + 1 do
            floor.buildBarkMap(which, half)
        let map       = floor.barkMap[which].buffer!
        let curve     = .floorCurve[channel].buffer!
        let spectrum  = .spectrum[channel].buffer!
        let order     = floor.order
        let amplitude = cast(f64) curve[order]
        let offset    = cast(f64) floor.amplitudeOffset
        let maximum   = cast(f64) ((1'u32 << floor.amplitudeBits) - 1)

        var cosines: Array'f64
        cosines.resize(order)
        for index in order do
            cosines[index] = Math.cos(cast(f64) curve[index])

        var line = 0'u32
        while line < half
        {
            let bin   = map[line]
            let omega = Math.ConstF64.Pi * cast(f64) bin / cast(f64) floor.barkMapSize
            let cosw  = Math.cos(omega)
            var p     = 1.0'f64
            var q     = 1.0'f64
            if order & 1
            {
                for index in (order - 1) / 2
                {
                    let odd  = cosines[2 * index + 1] - cosw
                    let even = cosines[2 * index] - cosw
                    p *= 4.0 * odd * odd
                    q *= 4.0 * even * even
                }

                let lastEven = cosines[order - 1] - cosw
                q *= 4.0 * lastEven * lastEven
                p *= 1.0 - cosw * cosw
                q *= 0.25
            }
            else
            {
                for index in order / 2
                {
                    let odd  = cosines[2 * index + 1] - cosw
                    let even = cosines[2 * index] - cosw
                    p *= 4.0 * odd * odd
                    q *= 4.0 * even * even
                }

                p *= (1.0 - cosw) / 2.0
                q *= (1.0 + cosw) / 2.0
            }

            let value = cast(f32) Math.exp(0.11512925 * (amplitude * offset / (maximum * Math.sqrt(p + q)) - offset))
            while line < half and map[line] == bin
            {
                spectrum[line] *= value
                line           += 1
            }
        }
    }

    // Multiplies the spectrum of a channel by the piecewise curve its floor 1 posts describe.
    mtd applyFloor1(floor: *Floor, channel: u32, half: u32)
    {
        let posts    = .floorPosts[channel].buffer!
        let used     = .floorUsed[channel].buffer!
        let spectrum = .spectrum[channel].buffer!
        var lowX     = 0'u32
        var highX    = 0'u32
        var lowY     = Math.clamp(posts[0] * cast(s32) floor.multiplier, 0, 255)
        for index in 1'u64 until floor.sortedPosts.count
        {
            let current = floor.sortedPosts[index]
            if !used[current] do
                continue
            highX = floor.posts[current]
            let highY = Math.clamp(posts[current] * cast(s32) floor.multiplier, 0, 255)
            renderLine(half, lowX, highX, lowY, highY, spectrum)
            lowX = highX
            lowY = highY
        }

        for line in highX until half do
            spectrum[line] *= Floor1InverseDb[cast(u32) lowY]
    }

    // Decodes a residue into the channels of `list`, whose nonzero flags select what is coded.
    mtd decodeResidue(residue: *Residue, reader: *BitReader, list: const [..] u32, half: u32) fail
    {
        var active: [MaxChannels] u32
        var used = 0'u32
        for channel in list
        {
            if .nonzero[channel]
            {
                active[used] = channel
                used         += 1
            }
        }

        if !used do
            return
        var vectors = used
        if residue.kind == 2
        {
            for channel, index in list do
                active[index] = channel
            vectors = 1
        }

        let width      = residue.kind == 2 ? cast(u64) list.count : 1
        let actualSize = cast(u64) half * width
        let limitBegin = Math.min(cast(u64) residue.begin, actualSize)
        let limitEnd   = Math.min(cast(u64) residue.end, actualSize)
        if limitEnd <= limitBegin do
            return
        let partitions      = (limitEnd - limitBegin) / residue.partitionSize
        let classbook       = &.codebooks[residue.classbook]
        let wordSize        = cast(u64) classbook.dimensions
        let words           = (partitions + wordSize - 1) / wordSize
        var partitionValues = 1'u64
        for wordSize
        {
            if partitionValues > Swag.U32.Max do
                break
            partitionValues *= residue.classifications
        }

        .classes.resize(vectors * words * wordSize)
        for pass in residue.stages
        {
            var partition = 0'u64
            var word      = 0'u64
            while partition < partitions
            {
                if !pass
                {
                    for vector in vectors
                    {
                        let decoded = classbook.decode(reader)
                        if decoded < 0 or cast(u64) decoded >= partitionValues do
                            return
                        var value   = cast(u64) decoded
                        var divisor = partitionValues / residue.classifications
                        for digit in wordSize
                        {
                            .classes[(vector * words + word) * wordSize + digit] = cast(u32) (value / divisor)
                            value   %= divisor
                            divisor /= residue.classifications
                            if !divisor do
                                divisor = 1
                        }
                    }
                }

                for digit in wordSize where partition < partitions
                {
                    for vector in vectors
                    {
                        let cls  = .classes[(vector * words + word) * wordSize + digit]
                        let book = residue.books[cls, pass]
                        if (residue.cascade[cls] & (1'u32 << pass)) and book >= 0
                        {
                            let offset   = limitBegin + partition * residue.partitionSize
                            let codebook = &.codebooks[cast(u32) book]
                            var complete: bool
                            if residue.kind == 0 do
                                complete = .decodeInterleaved(codebook, reader, .spectrum[active[vector]].buffer! + offset, residue.partitionSize)
                            elif residue.kind == 1 do
                                complete = .decodeSequential(codebook, reader, .spectrum[active[vector]].buffer! + offset, residue.partitionSize)
                            else do
                                complete = .decodeAcrossChannels(codebook, reader, active, cast(u32) list.count, offset, residue.partitionSize)
                            if !complete do
                                return
                        }
                    }

                    partition += 1
                }

                word += 1
            }
        }
    }

    // Residue type 0: every vector spreads its values one dimension apart across the partition.
    mtd decodeInterleaved(book: *Codebook, reader: *BitReader, target: [*] f32, count: u32)->bool
    {
        let step = count / book.dimensions
        .entries.resize(step)
        for index in step
        {
            let entry = book.decode(reader)
            if entry < 0 do
                return false
            .entries[index] = entry
        }

        for dimension in book.dimensions
        {
            for index in step
            {
                let position = dimension * step + index
                if position < count do
                    target[position] += book.values[cast(u64) .entries[index] * book.dimensions + dimension]
            }
        }

        return true
    }

    // Residue type 1: every vector fills the next `dimensions` values.
    mtd decodeSequential(book: *Codebook, reader: *BitReader, target: [*] f32, count: u32)->bool
    {
        var index = 0'u32
        while index < count
        {
            let entry = book.decode(reader)
            if entry < 0 do
                return false
            for dimension in book.dimensions where index < count
            {
                target[index] += book.values[cast(u64) entry * book.dimensions + dimension]
                index         += 1
            }
        }

        return true
    }

    // Residue type 2: the channels are interleaved into one vector before partitioning.
    mtd decodeAcrossChannels(book: *Codebook, reader: *BitReader, active: const [MaxChannels] u32, width: u32, offset: u64, count: u32)->bool
    {
        let limit   = (offset + count) / width
        var index   = offset / width
        var channel = 0'u32
        while index < limit
        {
            let entry = book.decode(reader)
            if entry < 0 do
                return false
            for dimension in book.dimensions where index < limit
            {
                .spectrum[active[channel]][index] += book.values[cast(u64) entry * book.dimensions + dimension]
                channel += 1
                if channel == width
                {
                    channel = 0
                    index   += 1
                }
            }
        }

        return true
    }

    // Decodes one audio packet, appends the samples it completes to `.output`, and returns how
    // many sample frames those are.
    mtd decodeAudioPacket(packet: const [..] u8)->u64 fail
    {
        var reader = BitReader.create(packet)
        if reader.readFlag() do
            fail InvalidFormatError{"Vorbis packet is not an audio packet"}
        let modeIndex = reader.read(.modeBits)
        if modeIndex >= .modes.count do
            fail InvalidFormatError{"Vorbis packet names a mode that does not exist"}
        let mode         = .modes[modeIndex]
        let which        = mode.longBlock ? 1'u32 : 0
        let n            = .blockSizes[which]
        let half         = n / 2
        var previousLong = true
        var nextLong     = true
        if mode.longBlock
        {
            previousLong = reader.readFlag()
            nextLong     = reader.readFlag()
        }

        if reader.overran do
            fail InvalidFormatError{"Vorbis packet is truncated"}
        let mapping = &.mappings[mode.mapping]

        for channel in .channels
        {
            Memory.set(.spectrum[channel].buffer!, 0, cast(u64) half * #sizeof(f32))
            let floor = &.floors[mapping.submapFloor[mapping.mux[channel]]]
            .floorPresent[channel] = try .decodeFloor(floor, &reader, channel)
            .nonzero[channel]      = .floorPresent[channel]
        }

        for step in mapping.couplingSteps
        {
            if .nonzero[mapping.magnitude[step]] or .nonzero[mapping.angle[step]]
            {
                .nonzero[mapping.magnitude[step]] = true
                .nonzero[mapping.angle[step]]     = true
            }
        }

        for submap in mapping.submaps
        {
            var list: [MaxChannels] u32
            var count = 0'u32
            for channel in .channels where mapping.mux[channel] == submap
            {
                list[count] = channel
                count       += 1
            }

            try .decodeResidue(&.residues[mapping.submapResidue[submap]], &reader, list[0 until count], half)
        }

        var step = mapping.couplingSteps
        while step
        {
            step -= 1
            let magnitudes = .spectrum[mapping.magnitude[step]].buffer!
            let angles     = .spectrum[mapping.angle[step]].buffer!
            for line in half
            {
                let magnitude = magnitudes[line]
                let angle     = angles[line]
                if magnitude > 0
                {
                    if angle > 0
                    {
                        magnitudes[line] = magnitude
                        angles[line]     = magnitude - angle
                    }
                    else
                    {
                        angles[line]     = magnitude
                        magnitudes[line] = magnitude + angle
                    }
                }
                elif angle > 0
                {
                    magnitudes[line] = magnitude
                    angles[line]     = magnitude + angle
                }
                else
                {
                    angles[line]     = magnitude
                    magnitudes[line] = magnitude - angle
                }
            }
        }

        // A channel without a floor of its own contributed to the coupling only; it plays silence.
        for channel in .channels
        {
            if !.floorPresent[channel]
            {
                Memory.set(.spectrum[channel].buffer!, 0, cast(u64) half * #sizeof(f32))
                continue
            }

            let floor = &.floors[mapping.submapFloor[mapping.mux[channel]]]
            if floor.kind == 0 do
                .applyFloor0(floor, which, channel, half)
            else do
                .applyFloor1(floor, channel, half)
        }

        // Window the block, add it to the tail of the previous one, and keep its own tail.
        let shortHalf = .blockSizes[0] / 2
        var leftStart = 0'u32
        var leftEnd   = half
        var leftSlope = which
        if mode.longBlock and !previousLong
        {
            leftStart = n / 4 - shortHalf / 2
            leftEnd   = n / 4 + shortHalf / 2
            leftSlope = 0
        }

        var rightStart = half
        var rightEnd   = n
        var rightSlope = which
        if mode.longBlock and !nextLong
        {
            rightStart = n * 3 / 4 - shortHalf / 2
            rightEnd   = n * 3 / 4 + shortHalf / 2
            rightSlope = 0
        }

        let outputFrames = .previousSize ? cast(u64) .previousSize / 4 + n / 4 : 0
        let base         = .output.count / .channels
        .output.resize((base + outputFrames) * .channels)
        let time = .timeDomain.buffer!
        for channel in .channels
        {
            .transforms[which].inverse(.spectrum[channel].buffer!, time)
            for index in leftStart do
                time[index] = 0
            for index in leftStart until leftEnd do
                time[index] *= .slopes[leftSlope][index - leftStart]
            let rightLength = rightEnd - rightStart
            for index in rightStart until rightEnd do
                time[index] *= .slopes[rightSlope][rightLength - 1 - (index - rightStart)]
            for index in rightEnd until n do
                time[index] = 0

            if outputFrames
            {
                let saved    = .saved[channel].buffer!
                let slot     = ChannelSlots[.channels, channel]
                let previous = cast(u64) .previousSize
                let shift    = cast(s64) n / 4 - cast(s64) previous / 4
                for frame in outputFrames
                {
                    var value         = 0.0'f32
                    let previousIndex = previous / 2 + frame
                    if previousIndex < previous do
                        value += saved[previousIndex - previous / 2]
                    let current = cast(s64) frame + shift
                    if current >= 0 and current < cast(s64) n do
                        value += time[cast(u64) current]
                    .output[(base + frame) * .channels + slot] = cast(s16) Math.clamp(Math.round(cast(f64) value * 32767.0), -32768.0, 32767.0)
                }
            }

            Memory.copy(.saved[channel].buffer!, time + half, cast(u64) half * #sizeof(f32))
        }

        .previousSize = n
        return outputFrames
    }

    // Decodes every packet of one run of pages and returns the frames the run completes, after the
    // trimming its granule positions ask for.
    mtd decodeRun(run: const [..] u8)->u64 fail
    {
        var produced      = 0'u64
        var lastGranule   = Ogg.NoGranule
        var firstSequence = Swag.U32.Max
        var offset        = 0'u64
        .packet.clear()
        while offset < run.count
        {
            let page = try Ogg.readPageHeader(run, offset)
            if offset + page.totalBytes() > run.count do
                fail InvalidFormatError{"Ogg page run is truncated"}
            if page.serial == .serial
            {
                if firstSequence == Swag.U32.Max do
                    firstSequence = page.sequence
                if page.granule != Ogg.NoGranule do
                    lastGranule = page.granule
                let body = run[offset + page.headerBytes until offset + page.totalBytes()]
                var at   = 0'u64
                for index in page.segments
                {
                    let size = cast(u64) page.lacing[index]
                    .packet.add(body[at until at + size])
                    at += size
                    if size < 255
                    {
                        if .packet.count do
                            produced += try .decodeAudioPacket(.packet.toSlice())
                        .packet.clear()
                    }
                }
            }

            offset += page.totalBytes()
        }

        if lastGranule == Ogg.NoGranule do
            return produced

        // The first run starts at position zero and the later ones where the previous one ended;
        // a run decoded fresh after a seek knows neither, and keeps what it produced.
        var expected = produced
        var known    = false
        if firstSequence == .firstAudioSequence
        {
            expected = lastGranule
            known    = true
        }
        elif .granuleKnown
        {
            if lastGranule < .granule do
                fail InvalidFormatError{"Ogg granule position runs backwards"}
            expected = lastGranule - .granule
            known    = true
        }

        if known and produced > expected
        {
            let excess = produced - expected
            if firstSequence == .firstAudioSequence
            {
                // A first page whose granule position falls short of its samples asks for the
                // start of the stream to be cut, which is how an encoder states a negative offset.
                let keep = expected * .channels
                let skip = excess * .channels
                for index in keep do
                    .output[index] = .output[skip + index]
            }

            .output.resize(expected * .channels)
            produced = expected
        }
        elif known and produced < expected
        {
            .output.resize(expected * .channels)
            for index in produced * .channels until expected * .channels do
                .output[index] = 0
            produced = expected
        }

        .granule      = lastGranule
        .granuleKnown = true
        return produced
    }
}

// Advances `y` along the line from `(x0, y0)` to `(x1, y1)` and returns its value at `x`.
private func renderPoint(x0, x1, y0, y1, x: s32)->s32
{
    let dy  = y1 - y0
    let adx = x1 - x0
    let ady = Math.abs(dy)
    let off = (ady * (x - x0)) / adx
    return dy < 0 ? y0 - off : y0 + off
}

// Multiplies `target` by the line from `(x0, y0)` to `(x1, y1)`, stepping through the amplitude
// table exactly as the specification's integer walk does.
private func renderLine(limit: u32, x0, x1: u32, y0, y1: s32, target: [*] f32)
{
    let dy   = y1 - y0
    let adx  = cast(s32) (x1 - x0)
    var ady  = Math.abs(dy)
    let base = dy / adx
    let sy   = dy < 0 ? base - 1 : base + 1
    var x    = x0
    var y    = y0
    var err  = 0
    ady -= Math.abs(base * adx)

    let end = Math.min(limit, x1)
    if x < end do
        target[x] *= Floor1InverseDb[cast(u32) Math.clamp(y, 0, 255)]
    x += 1
    while x < end
    {
        err += ady
        if err >= adx
        {
            err -= adx
            y   += sy
        }
        else do
            y += base
        target[x] *= Floor1InverseDb[cast(u32) Math.clamp(y, 0, 255)]
        x         += 1
    }
}

// Measures packet durations for a container: the block size of each packet, read from its mode,
// against the block size of the packet before it.
internal struct DurationProbe
{
    codec:    Codec
    previous: u32     // Block size of the previous packet, zero before the first one.
}

internal impl DurationProbe
{
    mtd initialize(config: const [..] u8) fail
    {
        try .codec.readConfig(config)
    }

    // Returns the frames `packet` completes: a quarter of its block size and a quarter of the
    // previous one, which is what their windows overlap to; the first packet completes none.
    mtd frames(packet: const [..] u8)->u32 fail
    {
        var reader = BitReader.create(packet)
        if reader.readFlag() do
            fail InvalidFormatError{"Vorbis packet is not an audio packet"}
        let modeIndex = reader.read(.codec.modeBits)
        if modeIndex >= .codec.modes.count do
            fail InvalidFormatError{"Vorbis packet names a mode that does not exist"}
        let size   = .codec.blockSizes[.codec.modes[modeIndex].longBlock ? 1 : 0]
        let result = .previous ? (.previous + size) / 4 : 0
        .previous = size
        return result
    }
}

impl IPacketCodec for Codec
{
    mtd impl canDecode(encoding: SoundFileEncoding)->bool => encoding == .Vorbis

    mtd impl initialize(config: const [..] u8, sampleRateHz, channels: u32) fail
    {
        try .readConfig(config)
        if .sampleRate != sampleRateHz or .channels != channels do
            fail InvalidFormatError{"Vorbis stream shape differs from its container track"}
        .resetState()
    }

    mtd impl reset() => .resetState()

    mtd impl decodePacket(destination: [*] void, destinationSize: u64, packet: const [..] u8)->u64 fail
    {
        .output.clear()
        var frames: u64
        if packet.count >= 4 and packet[0] == 'O' and packet[1] == 'g' and packet[2] == 'g' and packet[3] == 'S' do
            frames = try .decodeRun(packet)
        else do
            frames = try .decodeAudioPacket(packet)

        // A container's index is the authority on what a packet contributes: a trailing
        // padding it declares, or a rounding of its own clock, shortens what the packet decodes to.
        let produced = Math.min(frames * .channels * #sizeof(s16), destinationSize)
        if produced do
            Memory.copy(destination, .output.buffer!, produced)
        return produced
    }
}

#init
{
    registerPacketCodec'Codec()
}
