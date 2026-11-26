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

// Vorbis transmits a codeword's first bit in the low bit of the packet window.
private const PrefixBits  = 8'u32
private const PrefixCount = 1'u32 << PrefixBits
private const PrefixMask  = PrefixCount - 1
private const LeafBits    = 4'u32
private const LeafMask    = (1 << LeafBits) - 1

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
private func ilog(value: u32)->u32 => value ? 32 - cast(u32, Swag.leadingZeros(value)) : 0

// Unpacks the 32-bit floating-point representation the format uses for codebook scales.
private func unpackFloat(raw: u32)->f32
{
    let mantissa = cast(f64, (raw & 0x1FFFFF))
    let exponent = cast(f64, ((raw & 0x7FE00000) >> 21)) - 788.0
    let value    = mantissa * Math.pow(2.0, exponent)
    return cast(f32, (raw & 0x80000000 ? -value : value))
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
    func create(payload: const [..] u8)->BitReader => BitReader{payload.buffer, payload.count, 0, false}

    mtd const remainingBits()->u64 => .size * 8 - .bitPos

    // Reads `count` bits, at most 32, as an unsigned value.
    mtd read(count: u32)->u32
    {
        if not count do
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
            let bitOffset = cast(u32, (.bitPos & 7))
            let available = 8 - bitOffset
            let take      = Math.min(available, count - got)
            let value     = (cast(u32, .data![.bitPos >> 3]) >> bitOffset) & ((1'u32 << take) - 1)
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
    children:    Array's32             // Two per node; a positive value names a node, a negative one a leaf holding entry `-value - 1`, zero is unassigned.
    values:      Array'f32             // Lookup vectors, `dimensions` values per entry, empty without a lookup.
    prefixes:    [PrefixCount] s32     // Continuation nodes, packed leaves, or zero for unassigned.
}

private impl Codebook
{
    // Returns the largest count whose `dimensions`-th power fits the entries: the size of the
    // value list a lookup of type 1 spreads over every dimension.
    mtd const lookup1Values()->u32
    {
        if not .entries do
            return 0
        var count = cast(u32, Math.floor(Math.pow(cast(f64, .entries), 1.0 / cast(f64, .dimensions))))
        if not count do
            count = 1
        while count > 1 and not .powerFits(count) do
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
            let slot  = cast(u64, node) * 2 + ((codeword >> bit) & 1)
            let child = .children[slot]
            if not bit
            {
                if child do
                    fail InvalidFormatError{"Vorbis codebook assigns one codeword twice"}
                .children[slot] = -cast(s32, entry) - 1
                return
            }

            if child < 0 do
                fail InvalidFormatError{"Vorbis codebook prefixes one codeword with another"}
            if not child
            {
                .children.add(0)
                .children.add(0)
                let created = cast(s32, (.children.count / 2 - 1))
                .children[slot] = created
                node = cast(u32, created)
            }
            else
            {
                node = cast(u32, child)
            }
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
            let bits  = cast(u32, length)
            var entry = marker[bits]
            if bits < 32 and (entry >> bits) do
                fail InvalidFormatError{"Vorbis codebook lengths overpopulate the tree"}
            try .insert(entry, bits, cast(u32, index))
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

    // Resolves short codewords and the starting nodes of longer ones in a single lookup.
    // A negative leaf packs the entry index above the four bits that hold its length.
    mtd buildPrefixes()
    {
        let children = .children.storage()
        for prefix in PrefixCount
        {
            var child = 0's32
            var depth = 0'u32
            while depth < PrefixBits
            {
                let bit = (prefix >> depth) & 1
                child = children[cast(u64, child) * 2 + bit]
                depth += 1
                if child <= 0 do
                    break
            }

            .prefixes[prefix] = child < 0 ? -(((-child - 1) << LeafBits) | cast(s32, depth)) : child
        }
    }

    // Reads a common codeword from its prefix, falling back to the tree for longer ones.
    #[Swag.Inline]
    mtd const decode(reader: *BitReader)->s32
    {
        let position = reader.bitPos
        let offset   = position >> 3
        if reader.size - offset >= 2
        {
            let data = unwrap reader.data
            var window: u16
            Memory.copy(&window, data + offset, #sizeof(u16))
            let prefix = (cast(u32, Math.littleEndianToNative(window)) >> cast(u32, position & 7)) & PrefixMask
            let child  = .prefixes[prefix]
            if child < 0
            {
                let leaf = -child
                reader.bitPos = position + cast(u64, leaf & LeafMask)
                return leaf >> LeafBits
            }

            if child
            {
                reader.bitPos = position + PrefixBits
                return .decodeTree(reader, cast(u32, child), PrefixBits)
            }
        }

        return .decodeTree(reader, 0, 0)
    }

    mtd const decodeTree(reader: *BitReader, startNode, depth: u32)->s32
    {
        if not .usedEntries do
            return -1
        let children = .children.storage()
        var node     = startNode
        for depth until MaxCodewordBits
        {
            let bit = reader.read(1)
            if reader.overran do
                return -1
            let child = children[cast(u64, node) * 2 + bit]
            if child < 0 do
                return -child - 1
            if not child do
                return -1
            node = cast(u32, child)
        }

        return -1
    }

    mtd parse(reader: *BitReader) fail
    {
        if reader.read(24) != 0x564342 do
            fail InvalidFormatError{"Vorbis codebook has no synchronization pattern"}
        .dimensions = reader.read(16)
        .entries    = reader.read(24)
        if not .dimensions do
            fail InvalidFormatError{"Vorbis codebook has no dimensions"}
        .lengths.resize(.entries)

        if not reader.readFlag()
        {
            let sparse = reader.readFlag()
            for index in .entries
            {
                if sparse and not reader.readFlag() do
                    .lengths[index] = 0
                else do
                    .lengths[index] = cast(u8, (reader.read(5) + 1))
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
                    .lengths[index] = cast(u8, current)
                    index += 1
                }

                current += 1
                if current > MaxCodewordBits do
                    fail InvalidFormatError{"Vorbis codebook length exceeds thirty-two bits"}
            }
        }

        if reader.overran do
            fail InvalidFormatError{"Vorbis setup header is truncated"}
        try .buildTree()
        .buildPrefixes()

        .lookupType = reader.read(4)
        if not .lookupType do
            return
        if .lookupType > 2 do
            fail InvalidFormatError{"Vorbis codebook uses a reserved lookup type"}

        let minimum   = unpackFloat(reader.read(32))
        let delta     = unpackFloat(reader.read(32))
        let valueBits = reader.read(4) + 1
        let sequence  = reader.readFlag()
        let quantized = .lookupType == 1 ? cast(u64, .lookup1Values()) :
                        cast(u64, .entries) * cast(u64, .dimensions)
        let quantizedBits = quantized * cast(u64, valueBits)
        if quantizedBits > reader.remainingBits() do
            fail InvalidFormatError{"Vorbis codebook lookup values are truncated"}

        var quant: Array'f32
        quant.resize(quantized)
        for index in quantized do
            quant[index] = cast(f32, reader.read(valueBits))
        if reader.overran do
            fail InvalidFormatError{"Vorbis setup header is truncated"}

        let valueCount = cast(u64, .entries) * cast(u64, .dimensions)
        .values.resize(valueCount)
        for entry in .entries
        {
            var last    = 0.0'f32
            var divisor = 1'u64
            for dimension in .dimensions
            {
                var index: u64
                if .lookupType == 1
                {
                    index   = (cast(u64, entry) / divisor) % quantized
                    divisor *= quantized
                }
                else
                {
                    index = cast(u64, entry) * cast(u64, .dimensions) + dimension
                }

                let value = quant[index] * delta + minimum + last
                if sequence do
                    last = value
                .values[cast(u64, entry) * cast(u64, .dimensions) + dimension] = value
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

        if not .order or not .rate or not .barkMapSize do
            fail InvalidFormatError{"Vorbis floor 0 states an empty configuration"}
    }

    mtd parseType1(reader: *BitReader, codebooks: u32) fail
    {
        .partitions = reader.read(5)
        var maxClass = 0'u32
        for index in .partitions
        {
            .partitionClass[index] = reader.read(4)
            maxClass = Math.max(maxClass, .partitionClass[index] + 1)
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
                let book = cast(s32, reader.read(8)) - 1
                if book >= cast(s32, codebooks) do
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
        let count = cast(u32, .posts.count)
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
        map.resize(cast(u64, half) + 1)
        let scale = cast(f64, .barkMapSize) / bark(cast(f64, .rate) / 2.0)
        for line in half
        {
            var value = cast(s64, Math.floor(bark(cast(f64, .rate) / 2.0 / cast(f64, half) * cast(f64, line)) * scale))
            if value < 0 do
                value = 0
            if value >= cast(s64, .barkMapSize) do
                value = cast(s64, .barkMapSize) - 1
            map[][line] = cast(u32, value)
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
    partitionValues: u64
    classDigits:     Array'u8
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

        var cascade: [64] u32
        for cls in .classifications
        {
            var bits = reader.read(3)
            if reader.readFlag() do
                bits |= reader.read(5) << 3
            cascade[cls] = bits
            .stages      = Math.max(.stages, ilog(bits))
        }

        for cls in .classifications
        {
            for stage in 8
            {
                .books[cls, stage] = -1
                if cascade[cls] & (1'u32 << stage)
                {
                    let book = reader.read(8)
                    if book >= codebooks.count do
                        fail InvalidFormatError{"Vorbis residue names a codebook that does not exist"}
                    if not codebooks[book].lookupType do
                        fail InvalidFormatError{"Vorbis residue names a codebook that carries no vectors"}
                    .books[cls, stage] = cast(s32, book)
                }
            }
        }

        if reader.overran do
            fail InvalidFormatError{"Vorbis setup header is truncated"}

        let book = &codebooks[.classbook]
        .partitionValues = 1
        for book.dimensions
        {
            if .partitionValues > Swag.U32.Max do
                break
            .partitionValues *= .classifications
        }

        // Decode small classification words once. Large sparse books use the same base
        // conversion while reading the packet, keeping setup allocation bounded.
        let entries = Math.min(cast(u64, book.entries), .partitionValues)
        let count   = entries * book.dimensions
        if count <= 4096
        {
            .classDigits.resize(count)
            for entry in entries
            {
                var value   = entry
                var divisor = .partitionValues / .classifications
                for digit in book.dimensions
                {
                    .classDigits[entry * book.dimensions + digit] = cast(u8, value / divisor)
                    value   %= divisor
                    divisor = Math.max(1'u64, divisor / .classifications)
                }
            }
        }
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

    serial:                   u32
    firstAudioSequence:       u32
    headerPacketsOnAudioPage: u32
    granule:                  u64
    granuleKnown:             bool
}

private impl Codec
{
    mtd resetState()
    {
        for channel in MaxChannels do
            Memory.set(.saved[channel].storage(), 0, .saved[channel].count * #sizeof(f32))
        .previousSize = 0
        .granuleKnown = false
        .packet.clear()
    }

    // Reads the identification header and sizes the buffers it implies.
    mtd readIdentification(header: const [..] u8) fail
    {
        if header.count < 30 or
           header[0] != 1 or
           header[1] != 'v' or
           header[2] != 'o' or
           header[3] != 'r' or
           header[4] != 'b' or
           header[5] != 'i' or
           header[6] != 's' do
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
        if not reader.readFlag() do
            fail InvalidFormatError{"Vorbis identification header has no framing bit"}
        if not .channels or .channels > MaxChannels do
            fail UnsupportedFormatError{"Vorbis stream needs one to eight channels"}
        if not .sampleRate do
            fail InvalidFormatError{"Vorbis stream declares no sample rate"}
        if .blockSizes[0] < MinBlockSize or
           .blockSizes[1] < .blockSizes[0] or
           .blockSizes[1] > MaxBlockSize do
            fail InvalidFormatError{"Vorbis stream declares invalid block sizes"}

        for which in 2
        {
            let half = .blockSizes[which] / 2
            .slopes[which].resize(half)
            for index in half
            {
                let inner = Math.sin((cast(f64, index) + 0.5) / cast(f64, half) * Math.ConstF64.Pi / 2.0)
                .slopes[which][index] = cast(f32, Math.sin(Math.ConstF64.Pi / 2.0 * inner * inner))
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
        if header.count < 7 or
           header[0] != 5 or
           header[1] != 'v' or
           header[2] != 'o' or
           header[3] != 'r' or
           header[4] != 'b' or
           header[5] != 'i' or
           header[6] != 's' do
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
        if not reader.readFlag() or reader.overran do
            fail InvalidFormatError{"Vorbis setup header has no framing bit"}
    }

    // Reads the three header packets out of the pages the container recorded, or out of the
    // laced form a Matroska track carries them in.
    mtd readConfig(config: const [..] u8) fail
    {
        var headers: [3] Array'u8
        if config.count >= 4 and
           config[0] == 'O' and
           config[1] == 'g' and
           config[2] == 'g' and
           config[3] == 'S'
        {
            var hasSerial = false
            var completed = 0'u32
            var offset    = 0'u64
            while offset < config.count and completed < 3
            {
                let page      = try Ogg.readPageHeader(config, offset)
                let pageBytes = page.totalBytes()
                if pageBytes > config.count - offset do
                    fail InvalidFormatError{"Vorbis header pages are truncated"}
                let body = config[offset + page.headerBytes until offset + pageBytes]
                if not hasSerial
                {
                    if (page.flags & Ogg.FirstPage) and
                       body.count >= 7 and
                       body[0] == 1 and
                       body[1] == 'v' and
                       body[2] == 'o' and
                       body[3] == 'r' and
                       body[4] == 'b' and
                       body[5] == 'i' and
                       body[6] == 's'
                    {
                        .serial   = page.serial
                        hasSerial = true
                    }
                }

                if hasSerial and page.serial == .serial
                {
                    var at = 0'u64
                    var completedOnPage = 0'u32
                    for index in page.segments
                    {
                        let size = cast(u64, page.lacing[index])
                        headers[completed].add(body[at until at + size])
                        at += size
                        if size < 255
                        {
                            completed       += 1
                            completedOnPage += 1
                            if completed == 3
                            {
                                if index + 1 < cast(u64, page.segments)
                                {
                                    .firstAudioSequence       = page.sequence
                                    .headerPacketsOnAudioPage = completedOnPage
                                }
                                else
                                {
                                    .firstAudioSequence       = page.sequence == Swag.U32.Max ? 0 : page.sequence + 1
                                    .headerPacketsOnAudioPage = 0
                                }

                                break
                            }
                        }
                    }
                }

                offset += pageBytes
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
                    if sizes[index] > config.count - offset do
                        fail InvalidFormatError{"Vorbis header lacing exceeds the configuration"}
                    if byte != 255 do
                        break
                }
            }

            let remaining = config.count - offset
            if sizes[0] > remaining do
                fail InvalidFormatError{"Vorbis header lacing exceeds the configuration"}
            let remainingAfterFirst = remaining - sizes[0]
            if sizes[1] > remainingAfterFirst do
                fail InvalidFormatError{"Vorbis header lacing exceeds the configuration"}
            let firstEnd  = offset + sizes[0]
            let secondEnd = firstEnd + sizes[1]
            headers[0].add(config[offset until firstEnd])
            headers[1].add(config[firstEnd until secondEnd])
            headers[2].add(config[secondEnd until config.count])
        }
        else
        {
            fail InvalidFormatError{"Vorbis configuration is neither Ogg pages nor laced headers"}
        }

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
        if not amplitude or reader.overran do
            return false
        let bookNumber = reader.read(ilog(cast(u32, floor.books.count)))
        if bookNumber >= floor.books.count do
            return false
        let book = &.codebooks[floor.books[bookNumber]]
        if not book.lookupType do
            fail InvalidFormatError{"Vorbis floor 0 names a codebook that carries no vectors"}

        let curve = &.floorCurve[channel]
        curve.resize(cast(u64, floor.order) + 1)
        var index = 0'u32
        while index < floor.order
        {
            let entry = book.decode(reader)
            if entry < 0 do
                return false
            for dimension in book.dimensions where index < floor.order
            {
                curve[][index] = book.values[cast(u64, entry) * book.dimensions + dimension]
                index += 1
            }
        }

        // Every vector is stated relative to the last value of the vector before it.
        var last = 0.0'f32
        index = 0
        while index < floor.order
        {
            for book.dimensions where index < floor.order
            {
                curve[][index] += last
                index += 1
            }

            last = curve[][index - 1]
        }

        let maximum = cast(f64, ((1'u32 << floor.amplitudeBits) - 1))
        curve[][floor.order] = cast(f32, (cast(f64, amplitude) / maximum * cast(f64, floor.amplitudeOffset)))
        return true
    }

    mtd decodeFloor1(floor: *Floor, reader: *BitReader, channel: u32)->bool fail
    {
        if not reader.readFlag() do
            return false
        const Ranges: [4] u32 = [256, 128, 86, 64]
        let range = Ranges[floor.multiplier - 1]
        let bits  = ilog(range - 1)
        let count = floor.posts.count
        let posts = &.floorPosts[channel]
        let used  = &.floorUsed[channel]
        posts.resize(count)
        used.resize(count)
        posts[][0] = cast(s32, reader.read(bits))
        posts[][1] = cast(s32, reader.read(bits))

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
                value = cast(u32, decoded)
            }

            for dimension in dimensions
            {
                let book = floor.subclassBooks[cls, value & subMask]
                value >>= subBits
                if book >= 0
                {
                    let decoded = .codebooks[cast(u32, book)].decode(reader)
                    if decoded < 0 do
                        return false
                    posts[][offset + dimension] = decoded
                }
                else
                {
                    posts[][offset + dimension] = 0
                }
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
            let predicted = renderPoint(cast(s32, floor.posts[low]),
                                        cast(s32, floor.posts[high]),
                                        posts[][low],
                                        posts[][high],
                                        cast(s32, floor.posts[index]))
            let highRoom = cast(s32, range) - predicted
            let lowRoom  = predicted
            let room     = Math.min(highRoom, lowRoom) * 2
            var value    = posts[][index]
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
        if floor.barkMap[which].count != cast(u64, half) + 1 do
            floor.buildBarkMap(which, half)
        let map       = floor.barkMap[which].storage()
        let curve     = .floorCurve[channel].storage()
        let spectrum  = .spectrum[channel].storage()
        let order     = floor.order
        let amplitude = cast(f64, curve[order])
        let offset    = cast(f64, floor.amplitudeOffset)
        let maximum   = cast(f64, ((1'u32 << floor.amplitudeBits) - 1))

        var cosines: Array'f64
        cosines.resize(order)
        for index in order do
            cosines[index] = Math.cos(cast(f64, curve[index]))

        var line = 0'u32
        while line < half
        {
            let bin   = map[line]
            let omega = Math.ConstF64.Pi * cast(f64, bin) / cast(f64, floor.barkMapSize)
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

            let value = cast(f32, Math.exp(0.11512925 * (amplitude * offset / (maximum * Math.sqrt(p + q)) - offset)))
            while line < half and map[line] == bin
            {
                spectrum[line] *= value
                line += 1
            }
        }
    }

    // Multiplies the spectrum of a channel by the piecewise curve its floor 1 posts describe.
    mtd applyFloor1(floor: *Floor, channel: u32, limit: u32)
    {
        if not limit do
            return
        let posts    = .floorPosts[channel].storage()
        let used     = .floorUsed[channel].storage()
        let spectrum = .spectrum[channel].storage()
        var lowX     = 0'u32
        var highX    = 0'u32
        var lowY     = Math.clamp(posts[0] * cast(s32, floor.multiplier), 0, 255)
        for index in 1'u64 until floor.sortedPosts.count
        {
            let current = floor.sortedPosts[index]
            if not used[current] do
                continue
            highX = floor.posts[current]
            let highY = Math.clamp(posts[current] * cast(s32, floor.multiplier), 0, 255)
            renderLine(limit, lowX, highX, lowY, highY, spectrum)
            if highX >= limit do
                return
            lowX = highX
            lowY = highY
        }

        let gain = Floor1InverseDb[cast(u32, lowY)]
        for line in highX until limit do
            spectrum[line] *= gain
    }

    // Decodes a residue into the channels of `list`, whose nonzero flags select what is coded.
    mtd decodeResidue(residue: *Residue, reader: *BitReader, list: const [..] u32, half: u32) fail
    {
        switch residue.kind
        {
        case 0:
            try .decodeResidueKind'(0, false)(residue, reader, list, half)

        case 1:
            try .decodeResidueKind'(1, false)(residue, reader, list, half)

        default:
            if list.count == 2 do
                try .decodeResidueKind'(2, true)(residue, reader, list, half)
            else do
                try .decodeResidueKind'(2, false)(residue, reader, list, half)
        }
    }

    mtd(Kind: u32, Stereo: bool) decodeResidueKind(residue: *Residue, reader: *BitReader, list: const [..] u32, half: u32) fail
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

        if not used do
            return
        let vectors = Kind == 2 ? 1'u32 : used
        #static if Kind == 2
        {
            for channel, index in list do
                active[index] = channel
        }

        let width      = Stereo ? 2'u64 : (Kind == 2 ? cast(u64, list.count) : 1)
        let actualSize = cast(u64, half) * width
        let limitBegin = Math.min(cast(u64, residue.begin), actualSize)
        let limitEnd   = Math.min(cast(u64, residue.end), actualSize)
        if limitEnd <= limitBegin do
            return
        let partitions      = (limitEnd - limitBegin) / residue.partitionSize
        let classbook       = &.codebooks[residue.classbook]
        let wordSize        = cast(u64, classbook.dimensions)
        let words           = (partitions + wordSize - 1) / wordSize
        let partitionValues = residue.partitionValues

        .classes.resize(vectors * words * wordSize)
        let classes     = .classes.storage()
        let classDigits = residue.classDigits.storage()
        for pass in residue.stages
        {
            var partition = 0'u64
            var word      = 0'u64
            while partition < partitions
            {
                if not pass
                {
                    for vector in vectors
                    {
                        let decoded = classbook.decode(reader)
                        if decoded < 0 or cast(u64, decoded) >= partitionValues do
                            return
                        let target = classes + (vector * words + word) * wordSize
                        if residue.classDigits.count
                        {
                            let digits = classDigits + cast(u64, decoded) * wordSize
                            for digit in wordSize do
                                target[digit] = digits[digit]
                        }
                        else
                        {
                            var value   = cast(u64, decoded)
                            var divisor = partitionValues / residue.classifications
                            for digit in wordSize
                            {
                                target[digit] = cast(u32, value / divisor)
                                value         %= divisor
                                divisor       = Math.max(1'u64, divisor / residue.classifications)
                            }
                        }
                    }
                }

                for digit in wordSize where partition < partitions
                {
                    for vector in vectors
                    {
                        let cls  = classes[(vector * words + word) * wordSize + digit]
                        let book = residue.books[cls, pass]
                        if book >= 0
                        {
                            let offset   = limitBegin + partition * residue.partitionSize
                            let codebook = &.codebooks[cast(u32, book)]
                            var complete: bool
                            #static if Kind == 0 do
                                complete = .decodeInterleaved(codebook, reader, .spectrum[active[vector]].storage() + offset, residue.partitionSize)
                            elif Kind == 1 do
                                complete = .decodeSequential(codebook, reader, .spectrum[active[vector]].storage() + offset, residue.partitionSize)
                            else do
                                complete = .decodeAcrossChannels'Stereo(codebook, reader, active, cast(u32, list.count), offset, residue.partitionSize)
                            if not complete do
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
                    target[position] += book.values[cast(u64, .entries[index]) * book.dimensions + dimension]
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
                target[index] += book.values[cast(u64, entry) * book.dimensions + dimension]
                index         += 1
            }
        }

        return true
    }

    // Residue type 2: the channels are interleaved into one vector before partitioning.
    mtd(Stereo: bool) decodeAcrossChannels(book: *Codebook, reader: *BitReader, active: const [MaxChannels] u32, width: u32, offset: u64, count: u32)->bool
    {
        let channels = Stereo ? 2'u32 : width
        let limit    = (offset + count) / channels
        var index    = offset / channels
        let values   = book.values.storage()

        // A stereo codeword with an even dimension contains whole left/right pairs.
        if Stereo and (book.dimensions & 1) == 0
        {
            let left  = .spectrum[active[0]].storage()
            let right = .spectrum[active[1]].storage()
            let pairs = book.dimensions / 2
            if pairs == 1
            {
                while index < limit
                {
                    let entry = book.decode(reader)
                    if entry < 0 do
                        return false
                    let vector = values + cast(u64, entry) * 2
                    left[index]  += vector[0]
                    right[index] += vector[1]
                    index        += 1
                }

                return true
            }

            if pairs == 2
            {
                while index + 2 <= limit
                {
                    let entry = book.decode(reader)
                    if entry < 0 do
                        return false
                    let vector = values + cast(u64, entry) * 4
                    left[index]      += vector[0]
                    right[index]     += vector[1]
                    left[index + 1]  += vector[2]
                    right[index + 1] += vector[3]
                    index            += 2
                }
            }

            if pairs == 4
            {
                while index + 4 <= limit
                {
                    let entry = book.decode(reader)
                    if entry < 0 do
                        return false
                    let vector      = values + cast(u64, entry) * 8
                    let first       = cast #bit(Simd.U32x4, Simd.load(vector))
                    let second      = cast #bit(Simd.U32x4, Simd.load(vector + 4))
                    let leftValues  = cast #bit(Simd.F32x4, Simd.deinterleaveEven(first, second))
                    let rightValues = cast #bit(Simd.F32x4, Simd.deinterleaveOdd(first, second))
                    Simd.store(left + index, Simd.load(left + index) + leftValues)
                    Simd.store(right + index, Simd.load(right + index) + rightValues)
                    index += 4
                }
            }

            while index < limit
            {
                let entry = book.decode(reader)
                if entry < 0 do
                    return false
                let vector = values + cast(u64, entry) * book.dimensions
                let frames = Math.min(cast(u64, pairs), limit - index)
                for frame in frames
                {
                    left[index + frame]  += vector[2 * frame]
                    right[index + frame] += vector[2 * frame + 1]
                }

                index += frames
            }

            return true
        }

        var channel = 0'u32
        while index < limit
        {
            let entry = book.decode(reader)
            if entry < 0 do
                return false
            let vector = values + cast(u64, entry) * book.dimensions
            for dimension in book.dimensions where index < limit
            {
                .spectrum[active[channel]][index] += vector[dimension]
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
            Memory.set(.spectrum[channel].storage(), 0, cast(u64, half) * #sizeof(f32))
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

        // Residue cannot write beyond the coded range. Keep this upper bound
        // through coupling so floor reconstruction skips guaranteed zero bins.
        var activeBins: [MaxChannels] u32
        for submap in mapping.submaps
        {
            var list: [MaxChannels] u32
            var count = 0'u32
            for channel in .channels where mapping.mux[channel] == submap
            {
                list[count] = channel
                count       += 1
            }

            if not count do
                continue

            let residue = &.residues[mapping.submapResidue[submap]]
            let width   = residue.kind == 2 ? count : 1
            let bins    = Math.min(half, (residue.end + width - 1) / width)
            for channel in list[0 until count] do
                activeBins[channel] = bins
            try .decodeResidue(residue, &reader, list[0 until count], half)
        }

        var step = mapping.couplingSteps
        while step
        {
            step -= 1
            let magnitudeChannel = mapping.magnitude[step]
            let angleChannel     = mapping.angle[step]
            let bins             = Math.max(activeBins[magnitudeChannel], activeBins[angleChannel])
            activeBins[magnitudeChannel] = bins
            activeBins[angleChannel]     = bins
            let magnitudes = .spectrum[magnitudeChannel].storage()
            let angles     = .spectrum[angleChannel].storage()
            let zero       = Simd.splat(0'f32)

            // The signs select the reconstructed value and the channel that receives it.
            // At most three extra zero bins finish the last vector inside the block.
            var line = 0'u32
            while line < bins
            {
                let magnitude     = Simd.load(magnitudes + line)
                let angle         = Simd.load(angles + line)
                let positiveAngle = angle > zero
                let addAngle      = (magnitude > zero) ^ positiveAngle
                let combined      = Simd.select(addAngle, magnitude + angle, magnitude - angle)
                Simd.store(magnitudes + line, Simd.select(positiveAngle, magnitude, combined))
                Simd.store(angles + line, Simd.select(positiveAngle, combined, magnitude))
                line += 4
            }
        }

        // A channel without a floor of its own contributed to the coupling only; it plays silence.
        for channel in .channels
        {
            if not .floorPresent[channel]
            {
                Memory.set(.spectrum[channel].storage(), 0, cast(u64, half) * #sizeof(f32))
                continue
            }

            let floor = &.floors[mapping.submapFloor[mapping.mux[channel]]]
            if floor.kind == 0 do
                .applyFloor0(floor, which, channel, half)
            else do
                .applyFloor1(floor, channel, activeBins[channel])
        }

        // Window the block, add it to the tail of the previous one, and keep its own tail.
        let shortHalf = .blockSizes[0] / 2
        var leftStart = 0'u32
        var leftEnd   = half
        var leftSlope = which
        if mode.longBlock and not previousLong
        {
            leftStart = n / 4 - shortHalf / 2
            leftEnd   = n / 4 + shortHalf / 2
            leftSlope = 0
        }

        var rightStart = half
        var rightEnd   = n
        var rightSlope = which
        if mode.longBlock and not nextLong
        {
            rightStart = n * 3 / 4 - shortHalf / 2
            rightEnd   = n * 3 / 4 + shortHalf / 2
            rightSlope = 0
        }

        let outputFrames = .previousSize ? cast(u64, .previousSize) / 4 + n / 4 : 0

        // Every channel writes all of its new samples before the next packet.
        let pcm       = .output.emplaceAddress(cast(u32, outputFrames * .channels))
        let time      = .timeDomain.storage()
        let stereo    = .channels == 2
        let fusedLeft = stereo and .previousSize == n and leftStart == 0 and leftEnd == half
        let left      = .slopes[leftSlope].storage()
        let right     = .slopes[rightSlope].storage()
        const Reverse = cast(Simd.U32x4, [3'u32, 2, 1, 0])
        for channel in .channels
        {
            .transforms[which].inverse(.spectrum[channel].storage(), time)
            let saved = .saved[channel].storage()
            if not fusedLeft
            {
                if leftStart do
                    Memory.clear(time, cast(u64, leftStart) * #sizeof(f32))

                var index = leftStart
                while index < leftEnd
                {
                    let samples = Simd.load(time + index)
                    let gain    = Simd.load(left + (index - leftStart))
                    Simd.store(time + index, samples * gain)
                    index += 4
                }
            }

            if outputFrames
            {
                #[Swag.Inline]
                func toPcm16(value: f32)->s16
                {
                    // Add half a sample away from zero. The integer cast truncates it.
                    let scaled = cast(f64, value) * 32767.0
                    let biased = scaled + Math.copysign(0.5, scaled)
                    return cast(s16, Math.clamp(biased, -32768.0, 32767.0))
                }

                let slot   = ChannelSlots[.channels, channel]
                let output = pcm + slot

                // Different block sizes leave samples to one side of the overlap. Compute
                // that span once, then add the two windows without bounds checks per sample.
                let shift        = cast(s64, n) / 4 - cast(s64, .previousSize) / 4
                let overlapStart = shift < 0 ? cast(u64, -shift) : 0
                let overlapEnd   = Math.min(cast(u64, .previousSize) / 2, outputFrames)
                if fusedLeft
                {
                    // The steady overlap covers the entire left window. Multiply and
                    // overlap in one pass while saving this channel's PCM plane.
                    let plane = .spectrum[channel].storage()
                    var frame = 0'u32
                    while frame < half
                    {
                        let current = Simd.load(time + frame) * Simd.load(left + frame)
                        Simd.store(plane + frame, current + Simd.load(saved + frame))
                        frame += 4
                    }
                }
                elif stereo
                {
                    // The spectrum is dead after the inverse transform. Reuse it as one
                    // PCM plane until both channels are ready to interleave.
                    let plane = .spectrum[channel].storage()
                    if overlapStart do
                        Memory.copy(plane, saved, overlapStart * #sizeof(f32))
                    if overlapEnd < outputFrames
                    {
                        let tail = cast(u64, cast(s64, overlapEnd) + shift)
                        Memory.copy(plane + overlapEnd, time + tail, (outputFrames - overlapEnd) * #sizeof(f32))
                    }

                    let current = time + cast(u64, cast(s64, overlapStart) + shift)
                    var frame   = overlapStart
                    while frame < overlapEnd
                    {
                        let sum = Simd.load(saved + frame) + Simd.load(current + (frame - overlapStart))
                        Simd.store(plane + frame, sum)
                        frame += 4
                    }
                }
                else
                {
                    for frame in overlapStart do
                        output[frame * .channels] = toPcm16(saved[frame])
                    for frame in overlapStart until overlapEnd do
                        output[frame * .channels] = toPcm16(saved[frame] + time[cast(u64, cast(s64, frame) + shift)])
                    for frame in overlapEnd until outputFrames do
                        output[frame * .channels] = toPcm16(time[cast(u64, cast(s64, frame) + shift)])
                }
            }

            // The right half is only used by the next packet. Apply its window while
            // writing it to the overlap buffer rather than modifying it in timeDomain.
            if rightStart > half do
                Memory.copy(saved, time + half, cast(u64, rightStart - half) * #sizeof(f32))
            if rightEnd < n do
                Memory.clear(saved + (rightEnd - half), cast(u64, n - rightEnd) * #sizeof(f32))

            var index = rightStart
            while index < rightEnd
            {
                let samples = Simd.load(time + index)
                let gain    = Simd.load(right + (rightEnd - index - 4))
                Simd.store(saved + (index - half), samples * Simd.permute(gain, Reverse))
                index += 4
            }
        }

        if stereo and outputFrames
        {
            #[Swag.Inline]
            func toPcm32(value: Simd.F32x4)->Simd.S32x4
            {
                let scaled  = value * 32767.0'f32
                let biased  = scaled + Math.copysign(Simd.splat(0.5'f32), scaled)
                let clamped = Math.min(Math.max(biased, Simd.splat(-32768.0'f32)), Simd.splat(32767.0'f32))
                return Simd.truncateToS32(clamped)
            }

            let left   = .spectrum[0].storage()
            let right  = .spectrum[1].storage()
            let output = cast([*] u16, pcm)
            var frame  = 0'u64
            while frame < outputFrames
            {
                let leftLow   = toPcm32(Simd.load(left + frame))
                let leftHigh  = toPcm32(Simd.load(left + frame + 4))
                let rightLow  = toPcm32(Simd.load(right + frame))
                let rightHigh = toPcm32(Simd.load(right + frame + 4))
                let leftPcm   = cast #bit(Simd.U16x8, Simd.packSigned(leftLow, leftHigh))
                let rightPcm  = cast #bit(Simd.U16x8, Simd.packSigned(rightLow, rightHigh))
                Simd.store(output + 2 * frame, Simd.interleaveLow(leftPcm, rightPcm))
                Simd.store(output + 2 * frame + 8, Simd.interleaveHigh(leftPcm, rightPcm))
                frame += 8
            }
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
        var endsStream    = false
        var offset        = 0'u64
        .packet.clear()
        while offset < run.count
        {
            let page      = try Ogg.readPageHeader(run, offset)
            let pageBytes = page.totalBytes()
            if pageBytes > run.count - offset do
                fail InvalidFormatError{"Ogg page run is truncated"}
            if page.serial == .serial
            {
                if firstSequence == Swag.U32.Max do
                    firstSequence = page.sequence
                endsStream = endsStream or (page.flags & Ogg.LastPage) != 0
                if page.granule != Ogg.NoGranule do
                    lastGranule = page.granule
                let body          = run[offset + page.headerBytes until offset + pageBytes]
                var at            = 0'u64
                var packetStart   = 0'u64
                var headersToSkip = page.sequence == .firstAudioSequence ? .headerPacketsOnAudioPage : 0'u32
                for index in page.segments
                {
                    let size = page.lacing[index]
                    at += size
                    if size == 255 do
                        continue

                    // Borrow packets that fit on this page. Only packets with a fragment from
                    // a preceding page need to be joined in the scratch buffer.
                    let payload = body[packetStart until at]
                    if headersToSkip
                    {
                        headersToSkip -= 1
                    }
                    elif .packet.count
                    {
                        .packet.add(payload)
                        produced += try .decodeAudioPacket(.packet.toSlice())
                    }
                    elif payload.count
                    {
                        produced += try .decodeAudioPacket(payload)
                    }

                    .packet.clear()
                    packetStart = at
                }

                if packetStart < at do
                    .packet.add(body[packetStart until at])
            }

            offset += pageBytes
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
            if firstSequence == .firstAudioSequence and not endsStream
            {
                // A non-final first page whose granule position falls short of its decoded
                // samples asks for the start of the stream to be cut, which is how an encoder
                // states a negative offset. When this run also ends the stream, the final granule
                // trims packet padding at the end instead.
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
// table exactly as the specification's integer walk does. Both endpoints are clamped to valid
// table indices before the interpolation, so every intermediate value is in range.
private func renderLine(limit: u32, x0, x1: u32, y0, y1: s32, target: [*] f32)
{
    let end = Math.min(limit, x1)
    if end <= x0 do
        return

    if y0 == y1
    {
        let gain  = Floor1InverseDb[cast(u32, y0)]
        let gain4 = Simd.splat(gain)
        var line  = x0
        while line + 4 <= end
        {
            Simd.store(target + line, Simd.load(target + line) * gain4)
            line += 4
        }

        for tail in line until end do
            target[tail] *= gain
        return
    }

    let span      = x1 - x0
    let dy        = y1 - y0
    let delta     = cast(u32, Math.abs(dy))
    let wholeStep = delta / span
    let remainder = delta % span
    let sign      = dy < 0 ? -1 : 1
    var x         = x0
    if end - x >= 4
    {
        // The ceiling of the Q32 step gives the same floor as the integer walk:
        // a span is at most 32768 and accumulating its error stays below 1/span.
        let fraction   = cast(u32, ((cast(u64, remainder) << 32) + span - 1) / span)
        let base       = Simd.splat(y0)
        let direction  = Simd.splat(sign)
        let whole      = Simd.splat(wholeStep)
        let step       = Simd.splat(fraction)
        let amplitudes = cast(const [*] s32, &Floor1InverseDb[0])
        var offsets    = cast(Simd.U32x4, [0'u32, 1, 2, 3])
        while x + 4 <= end
        {
            let distance = cast #bit(Simd.S32x4, whole * offsets + Simd.mulHigh(offsets, step))
            let indices  = cast #bit(Simd.U32x4, base + distance * direction)
            let gain     = cast #bit(Simd.F32x4, Simd.gather(amplitudes, indices))
            Simd.store(target + x, Simd.load(target + x) * gain)
            offsets += Simd.splat(4'u32)
            x       += 4
        }
    }

    for line in x until end
    {
        let distance = cast(s32, ((line - x0) * delta) / span)
        target[line] *= Floor1InverseDb[cast(u32, y0 + sign * distance)]
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
        if reader.overran do
            fail InvalidFormatError{"Vorbis audio packet is truncated"}
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
        if packet.count >= 4 and
           packet[0] == 'O' and
           packet[1] == 'g' and
           packet[2] == 'g' and
           packet[3] == 'S' do
            frames = try .decodeRun(packet)
        else do
            frames = try .decodeAudioPacket(packet)

        // A container's index is the authority on what a packet contributes: a trailing
        // padding it declares, or a rounding of its own clock, shortens what the packet decodes to.
        let produced = Math.min(frames * .channels * #sizeof(s16), destinationSize)
        if produced do
            Memory.copy(destination, .output.storage(), produced)
        return produced
    }
}

#init
{
    registerPacketCodec'Codec()
}
