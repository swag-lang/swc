//! Format: WebP still-image decoder component.
//! Supported: RIFF WebP containing lossy VP8 or lossless VP8L still images, including supported alpha chunks.
//! Not supported: Animated WebP and unsupported alpha preprocessing or compression methods.
//! Role: This file owns VP8L transforms, Huffman decoding, and pixel reconstruction.
//
#global namespace Webp

using Core, Core.Errors

// @LICENCE: BSD-3-Clause
// @ORIGIN: Go x/image VP8L decoder, https://github.com/golang/image/tree/master/vp8l
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#go-x-image

const LOSSLESS_COLOR_CACHE_MULTIPLIER = 0x1E35A7BD'u32
const LOSSLESS_LUT_BITS = 8'u32
const LOSSLESS_LUT_MASK = (1 << LOSSLESS_LUT_BITS) - 1

// The largest alphabet is green with 2,048 cache entries. A direct entry
// therefore fits a 12-bit symbol with a 4-bit length plus one.
const LOSSLESS_LUT_SYMBOL_BITS    = 12
const LOSSLESS_LUT_SYMBOL_MASK    = 0xFFF
const LOSSLESS_LUT_NODE_BASE      = (LOSSLESS_LUT_BITS + 2) << LOSSLESS_LUT_SYMBOL_BITS
const LOSSLESS_LEAF_NODE          = -1's32
const LOSSLESS_MAX_CODE_LENGTH    = 15'u32
const LOSSLESS_LITERAL_CODES      = 256'u32
const LOSSLESS_LENGTH_CODES       = 24'u32
const LOSSLESS_DISTANCE_CODES     = 40'u32
const LOSSLESS_HUFFMAN_TREES      = 5
const LOSSLESS_MAX_HUFFMAN_GROUPS = 2600

const LOSSLESS_HUFF_GREEN    = 0
const LOSSLESS_HUFF_RED      = 1
const LOSSLESS_HUFF_BLUE     = 2
const LOSSLESS_HUFF_ALPHA    = 3
const LOSSLESS_HUFF_DISTANCE = 4

const LOSSLESS_TRANSFORM_PREDICTOR      = 0'u32
const LOSSLESS_TRANSFORM_CROSS_COLOR    = 1'u32
const LOSSLESS_TRANSFORM_SUBTRACT_GREEN = 2'u32
const LOSSLESS_TRANSFORM_COLOR_INDEXING = 3'u32
const LOSSLESS_TRANSFORM_COUNT          = 4

const LOSSLESS_DISTANCE_MAP: [120] u8 = [
    0x18, 0x07, 0x17, 0x19, 0x28, 0x06, 0x27, 0x29, 0x16, 0x1A,
    0x26, 0x2A, 0x38, 0x05, 0x37, 0x39, 0x15, 0x1B, 0x36, 0x3A,
    0x25, 0x2B, 0x48, 0x04, 0x47, 0x49, 0x14, 0x1C, 0x35, 0x3B,
    0x46, 0x4A, 0x24, 0x2C, 0x58, 0x45, 0x4B, 0x34, 0x3C, 0x03,
    0x57, 0x59, 0x13, 0x1D, 0x56, 0x5A, 0x23, 0x2D, 0x44, 0x4C,
    0x55, 0x5B, 0x33, 0x3D, 0x68, 0x02, 0x67, 0x69, 0x12, 0x1E,
    0x66, 0x6A, 0x22, 0x2E, 0x54, 0x5C, 0x43, 0x4D, 0x65, 0x6B,
    0x32, 0x3E, 0x78, 0x01, 0x77, 0x79, 0x53, 0x5D, 0x11, 0x1F,
    0x64, 0x6C, 0x42, 0x4E, 0x76, 0x7A, 0x21, 0x2F, 0x75, 0x7B,
    0x31, 0x3F, 0x63, 0x6D, 0x52, 0x5E, 0x00, 0x74, 0x7C, 0x41,
    0x4F, 0x10, 0x20, 0x62, 0x6E, 0x30, 0x73, 0x7D, 0x51, 0x5F,
    0x40, 0x72, 0x7E, 0x61, 0x6F, 0x50, 0x71, 0x7F, 0x60, 0x70]

const LOSSLESS_CODE_LENGTH_ORDER: [19] u8 = [
    17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

const LOSSLESS_REPEAT_BITS:    [3] u8 = [2, 3, 7]
const LOSSLESS_REPEAT_OFFSETS: [3] u8 = [3, 3, 11]
const LOSSLESS_ALPHABET_SIZES: [LOSSLESS_HUFFMAN_TREES] u32 = [
    LOSSLESS_LITERAL_CODES + LOSSLESS_LENGTH_CODES,
    LOSSLESS_LITERAL_CODES,
    LOSSLESS_LITERAL_CODES,
    LOSSLESS_LITERAL_CODES,
    LOSSLESS_DISTANCE_CODES]

struct LosslessBitReader
{
    late ptr:  const [*] u8
    late last: const [*] u8
    bits:      u64
    nBits:     u32
}

impl LosslessBitReader
{
    #[Swag.Inline]
    mtd refill()
    {
        if .last - .ptr >= 8 and .nBits < 8
        {
            // The eighth byte remains available for the next refill.
            let word = cast(const [*] u64, .ptr)[0] & 0x00FFFFFFFFFFFFFF'u64
            .bits  |= word << .nBits
            .ptr   += 7
            .nBits += 56
        }
        else
        {
            .bits  |= cast(u64, .ptr[]) << .nBits
            .ptr   += 1
            .nBits += 8
        }
    }

    mtd read(count: u32)->u32 fail
    {
        if count > 32 do
            fail InvalidFormatError{"WebP bit field exceeds 32 bits"}

        while .nBits < count
        {
            if .ptr >= .last do
                fail InvalidFormatError{"WebP data ends inside the lossless bitstream"}
            .refill()
        }

        let mask  = count == 32 ? 0xFFFFFFFF'u64 : ((1'u64 << count) - 1)
        let value = cast(u32, (.bits & mask))
        .bits  >>= count
        .nBits -= count
        return value
    }
}

struct LosslessHuffmanNode
{
    symbol:   u32
    children: s32
}

struct LosslessHuffmanTree
{
    nodes:     Array'LosslessHuffmanNode
    nodeCount: u32
    maxLength: u32
    lut:       [1 << LOSSLESS_LUT_BITS] u16
}

struct LosslessHuffmanGroup
{
    trees:        [LOSSLESS_HUFFMAN_TREES] LosslessHuffmanTree
    literalTable: Array'u32
    literalMask:  u32
}

impl LosslessHuffmanGroup
{
    mtd buildLiteralTable()
    {
        let maxBits = .trees[LOSSLESS_HUFF_RED].maxLength +
                      .trees[LOSSLESS_HUFF_BLUE].maxLength +
                      .trees[LOSSLESS_HUFF_ALPHA].maxLength
        if maxBits > LOSSLESS_LUT_BITS do
            return

        let count = 1'u32 << maxBits
        var entries: [1 << LOSSLESS_LUT_BITS] u32
        for prefix in count
        {
            var bits = cast(u32, prefix)
            let red  = .trees[LOSSLESS_HUFF_RED].lut[bits & LOSSLESS_LUT_MASK]
            if not red or red >= LOSSLESS_LUT_NODE_BASE do
                return
            let redBits = cast(u32, red >> LOSSLESS_LUT_SYMBOL_BITS) - 1
            bits >>= redBits
            let blue = .trees[LOSSLESS_HUFF_BLUE].lut[bits & LOSSLESS_LUT_MASK]
            if not blue or blue >= LOSSLESS_LUT_NODE_BASE do
                return
            let blueBits = cast(u32, blue >> LOSSLESS_LUT_SYMBOL_BITS) - 1
            bits >>= blueBits
            let alpha = .trees[LOSSLESS_HUFF_ALPHA].lut[bits & LOSSLESS_LUT_MASK]
            if not alpha or alpha >= LOSSLESS_LUT_NODE_BASE do
                return
            let length = redBits + blueBits + (alpha >> LOSSLESS_LUT_SYMBOL_BITS)

            // The green byte stores the combined bit count plus one.
            entries[prefix] = cast(u32, red & LOSSLESS_LUT_SYMBOL_MASK) | (length << 8) |
                              (cast(u32, blue & LOSSLESS_LUT_SYMBOL_MASK) << 16) |
                              (cast(u32, alpha & LOSSLESS_LUT_SYMBOL_MASK) << 24)
        }

        .literalMask = count - 1
        .literalTable.resize(count)
        Memory.copy(.literalTable.storage(), &entries[0], count * #sizeof(u32))
    }

    #[Swag.Inline]
    mtd readLiteral(reader: *LosslessBitReader, green: u32)->u32 fail
    {
        if not .literalTable.isEmpty()
        {
            let entry = .literalTable.storage()[reader.bits & .literalMask]
            let bits  = ((entry >> 8) & 0xFF) - 1
            if bits <= reader.nBits
            {
                reader.bits  >>= bits
                reader.nBits -= bits
                return (entry & 0xFFFF00FF) | (green << 8)
            }
        }

        let red   = try .trees[LOSSLESS_HUFF_RED].next(reader)
        let blue  = try .trees[LOSSLESS_HUFF_BLUE].next(reader)
        let alpha = try .trees[LOSSLESS_HUFF_ALPHA].next(reader)
        return red | (green << 8) | (blue << 16) | (alpha << 24)
    }
}

struct LosslessTransform
{
    kind:     u32
    oldWidth: s32
    bits:     u32
    pixels:   Array'u8
}

func losslessTileCount(size: s32, bits: u32)->s32 => (size + cast(s32, (1 << bits)) - 1) >> bits

func losslessReverseByte(value: u8)->u8
{
    var v = value
    v = cast(u8, (((v & 0x55) << 1) | ((v >> 1) & 0x55)))
    v = cast(u8, (((v & 0x33) << 2) | ((v >> 2) & 0x33)))
    return cast(u8, ((cast(u32, (v & 0x0F)) << 4) | (v >> 4)))
}

func losslessTreeError() fail
{
    fail InvalidFormatError{"WebP lossless Huffman tree is inconsistent"}
}

impl LosslessHuffmanTree
{
    mtd insert(symbol, code, codeLength: u32) fail
    {
        if symbol > LOSSLESS_LUT_SYMBOL_MASK or codeLength > LOSSLESS_MAX_CODE_LENGTH do
            try losslessTreeError()

        var baseCode: u32
        if codeLength > LOSSLESS_LUT_BITS
        {
            let shift = codeLength - LOSSLESS_LUT_BITS
            baseCode = cast(u32, losslessReverseByte(cast(u8, ((code >> shift) & 0xFF)))) >> (8 - LOSSLESS_LUT_BITS)
        }
        else
        {
            baseCode = cast(u32, losslessReverseByte(cast(u8, (code & 0xFF)))) >> (8 - codeLength)
            let count = 1'u32 << (LOSSLESS_LUT_BITS - codeLength)
            for i in count do
                .lut[baseCode | (i << codeLength)] = cast(u16, (((codeLength + 1) << LOSSLESS_LUT_SYMBOL_BITS) | symbol))
        }

        var node      = 0'u32
        var jump      = LOSSLESS_LUT_BITS
        var remaining = codeLength
        while remaining
        {
            remaining -= 1
            if node >= .nodeCount do
                try losslessTreeError()

            switch .nodes[node].children
            {
            case LOSSLESS_LEAF_NODE:
                try losslessTreeError()

            case 0:
                if .nodeCount + 2 > .nodes.count do
                    try losslessTreeError()
                .nodes[node].children = cast(s32, .nodeCount)
                .nodeCount += 2
            }

            node = cast(u32, .nodes[node].children) + ((code >> remaining) & 1)
            if jump
            {
                jump -= 1
                if jump == 0 and .lut[baseCode] == 0 do
                    .lut[baseCode] = cast(u16, LOSSLESS_LUT_NODE_BASE + node)
            }
        }

        if .nodes[node].children == 0
        {
            .nodes[node].children = LOSSLESS_LEAF_NODE
        }
        elif .nodes[node].children != LOSSLESS_LEAF_NODE
        {
            try losslessTreeError()
        }

        .nodes[node].symbol = symbol
    }

    mtd build(codeLengths: const [..] u32) fail
    {
        var symbolCount: u32
        var lastSymbol:  u32
        var maxLength:   u32
        for symbol in codeLengths.count
        {
            let length = codeLengths[symbol]
            if length
            {
                symbolCount += 1
                lastSymbol  = cast(u32, symbol)
                maxLength   = Math.max(maxLength, length)
            }
        }

        if symbolCount == 0 or maxLength > LOSSLESS_MAX_CODE_LENGTH do
            try losslessTreeError()

        .maxLength = symbolCount == 1 ? 0 : maxLength
        .nodes.resize(2 * symbolCount - 1)
        .nodeCount = 1
        Memory.clear(cast([*] void, .nodes.storage()), .nodes.count * #sizeof(LosslessHuffmanNode))
        Memory.clear(&.lut[0], #sizeof(.lut))

        if symbolCount == 1
        {
            try .insert(lastSymbol, 0, 0)
            return
        }

        var histogram: [LOSSLESS_MAX_CODE_LENGTH + 1] u32
        for length in codeLengths do
            histogram[length] += 1

        var nextCodes:   [LOSSLESS_MAX_CODE_LENGTH + 1] u32
        var currentCode: u32
        var length = 1'u64
        while length < nextCodes.count
        {
            currentCode       = (currentCode + histogram[length - 1]) << 1
            nextCodes[length] = currentCode
            length            += 1
        }

        for symbol in codeLengths.count
        {
            let length = codeLengths[symbol]
            if not length do
                continue
            let code = nextCodes[length]
            nextCodes[length] += 1
            try .insert(cast(u32, symbol), code, length)
        }
    }

    mtd buildSimple(symbolCount: u32, symbols: [2] u32, alphabetSize: u32) fail
    {
        .maxLength = symbolCount - 1
        .nodes.resize(2 * symbolCount - 1)
        .nodeCount = 1
        Memory.clear(cast([*] void, .nodes.storage()), .nodes.count * #sizeof(LosslessHuffmanNode))
        Memory.clear(&.lut[0], #sizeof(.lut))

        for i in symbolCount
        {
            if symbols[i] >= alphabetSize do
                try losslessTreeError()
            try .insert(symbols[i], i, symbolCount - 1)
        }
    }

    #[Swag.Inline]
    mtd next(reader: *LosslessBitReader)->u32 fail
    {
        var node: u32
        if reader.nBits < LOSSLESS_LUT_BITS and reader.ptr < reader.last do
            reader.refill()

        if reader.nBits >= LOSSLESS_LUT_BITS
        {
            let entry = cast(u32, .lut[reader.bits & LOSSLESS_LUT_MASK])
            if entry and entry < LOSSLESS_LUT_NODE_BASE
            {
                let consumed = (entry >> LOSSLESS_LUT_SYMBOL_BITS) - 1
                reader.bits  >>= consumed
                reader.nBits -= consumed
                return entry & LOSSLESS_LUT_SYMBOL_MASK
            }

            node         = entry ? entry - LOSSLESS_LUT_NODE_BASE : 0
            reader.bits  >>= LOSSLESS_LUT_BITS
            reader.nBits -= LOSSLESS_LUT_BITS
        }

        return try .nextNode(reader, node)
    }

    #[Swag.NoInline]
    private mtd nextNode(reader: *LosslessBitReader, startNode: u32)->u32 fail
    {
        var node = startNode
        while true
        {
            if node >= .nodeCount do
                try losslessTreeError()
            if .nodes[node].children == LOSSLESS_LEAF_NODE do
                return .nodes[node].symbol

            if reader.nBits == 0
            {
                if reader.ptr >= reader.last do
                    fail InvalidFormatError{"WebP data ends inside a Huffman code"}
                reader.bits  = reader.ptr[]
                reader.ptr   += 1
                reader.nBits = 8
            }

            node         = cast(u32, .nodes[node].children) + cast(u32, (reader.bits & 1))
            reader.bits  >>= 1
            reader.nBits -= 1
        }
    }
}

func losslessDistance(width: s32, code: u32)->s32
{
    if code > LOSSLESS_DISTANCE_MAP.count do
        return cast(s32, code) - LOSSLESS_DISTANCE_MAP.count

    let distanceCode = cast(s32, LOSSLESS_DISTANCE_MAP[code - 1])
    let yOffset      = distanceCode >> 4
    let xOffset      = 8 - (distanceCode & 0x0F)
    let distance     = yOffset * width + xOffset
    return Math.max(distance, 1)
}

func losslessDecodeCodeLengths(reader: *LosslessBitReader, destination: [..] u32, codeLengthCodeLengths: const [..] u32) fail
{
    var tree: LosslessHuffmanTree
    try tree.build(codeLengthCodeLengths)

    var maxSymbol = destination.count
    if try reader.read(1)
    {
        let countBits = 2 + 2 * (try reader.read(3))
        maxSymbol = cast(u64, (try reader.read(countBits))) + 2
        if maxSymbol > destination.count do
            fail InvalidFormatError{"WebP lossless code lengths exceed their alphabet"}
    }

    var previousLength = 8'u32
    var symbol: u64
    while symbol < destination.count
    {
        if maxSymbol == 0 do
            break
        maxSymbol -= 1

        let codeLength = try tree.next(reader)
        if codeLength < 16
        {
            destination[symbol] = codeLength
            symbol += 1
            if codeLength do
                previousLength = codeLength
            continue
        }

        if codeLength > 18 do
            fail InvalidFormatError{"WebP lossless code-length repeat symbol is out of range"}
        let repeatIndex = codeLength - 16
        let repeat      = try reader.read(LOSSLESS_REPEAT_BITS[repeatIndex]) + LOSSLESS_REPEAT_OFFSETS[repeatIndex]
        if symbol + repeat > destination.count do
            fail InvalidFormatError{"WebP lossless code-length repeat exceeds its alphabet"}

        let repeatedLength = codeLength == 16 ? previousLength : 0'u32
        for repeat
        {
            destination[symbol] = repeatedLength
            symbol += 1
        }
    }
}

#[Swag.Propagate]
func losslessDecodeHuffmanTree(reader: *LosslessBitReader, tree: *LosslessHuffmanTree?, alphabetSize: u32) fail
{
    if reader.read(1)
    {
        let symbolCount = reader.read(1) + 1
        let firstLength = 7 * reader.read(1) + 1
        var symbols: [2] u32
        symbols[0] = reader.read(firstLength)
        if symbolCount == 2 do
            symbols[1] = reader.read(8)
        if tree do
            tree.buildSimple(symbolCount, symbols, alphabetSize)
        return
    }

    let codeCount = reader.read(4) + 4
    if codeCount > LOSSLESS_CODE_LENGTH_ORDER.count do
        losslessTreeError()

    var codeLengthCodeLengths: [LOSSLESS_CODE_LENGTH_ORDER.count] u32
    for i in codeCount do
        codeLengthCodeLengths[LOSSLESS_CODE_LENGTH_ORDER[i]] = reader.read(3)

    var codeLengths: Array'u32
    codeLengths.resize(alphabetSize)
    losslessDecodeCodeLengths(reader, codeLengths.toSlice(), Swag.makeSlice(&codeLengthCodeLengths[0], codeLengthCodeLengths.count))
    if tree do
        tree.build(codeLengths.toSlice())
}

#[Swag.Propagate]
func losslessDecodeHeader(reader: *LosslessBitReader, source: const [..] u8, width: *s32, height: *s32) fail
{
    reader.ptr   = source.buffer
    reader.last  = reader.ptr + source.count
    reader.bits  = 0
    reader.nBits = 0
    if reader.read(8) != 0x2F do
        fail InvalidFormatError{"WebP lossless stream does not start with the VP8L signature"}

    width[]  = cast(s32, reader.read(14)) + 1
    height[] = cast(s32, reader.read(14)) + 1
    discard reader.read(1)
    if reader.read(3) != 0 do
        fail UnsupportedFormatError{"WebP lossless stream uses an unsupported version"}
}

func losslessLz77Parameter(reader: *LosslessBitReader, symbol: u32)->u32 fail
{
    if symbol < 4 do
        return symbol + 1
    let extraBits = (symbol - 2) >> 1
    let offset    = (2 + (symbol & 1)) << extraBits
    return offset + (try reader.read(extraBits)) + 1
}

func losslessDecodeTransform(reader: *LosslessBitReader, transform: *LosslessTransform, width, height: s32)->s32 fail
{
    transform.oldWidth = width
    transform.kind     = try reader.read(2)

    switch transform.kind
    {
    case LOSSLESS_TRANSFORM_PREDICTOR, LOSSLESS_TRANSFORM_CROSS_COLOR:
        transform.bits = try reader.read(3) + 2
        try losslessDecodePixels(reader, &transform.pixels, losslessTileCount(width, transform.bits), losslessTileCount(height, transform.bits), 0, false)
        return width

    case LOSSLESS_TRANSFORM_SUBTRACT_GREEN:
        return width

    case LOSSLESS_TRANSFORM_COLOR_INDEXING:
        let colorCount = try reader.read(8) + 1
        switch
        {
        case colorCount <= 2:  transform.bits = 3
        case colorCount <= 4:  transform.bits = 2
        case colorCount <= 16: transform.bits = 1
        default: transform.bits = 0
        }

        try losslessDecodePixels(reader, &transform.pixels, cast(s32, colorCount), 1, 4 * 256, false)
        var offset = 4'u64
        while offset < transform.pixels.count
        {
            transform.pixels[offset + 0] = cast(u8, (cast(u32, transform.pixels[offset + 0]) + transform.pixels[offset - 4]))
            transform.pixels[offset + 1] = cast(u8, (cast(u32, transform.pixels[offset + 1]) + transform.pixels[offset - 3]))
            transform.pixels[offset + 2] = cast(u8, (cast(u32, transform.pixels[offset + 2]) + transform.pixels[offset - 2]))
            transform.pixels[offset + 3] = cast(u8, (cast(u32, transform.pixels[offset + 3]) + transform.pixels[offset - 1]))
            offset += 4
        }

        transform.pixels.resize(4 * 256)
        return losslessTileCount(width, transform.bits)

    default:
        fail InvalidFormatError{"WebP lossless stream uses a transform outside the VP8L set"}
    }
}

func losslessDecodeHuffmanGroups(reader: *LosslessBitReader, groups: *Array'LosslessHuffmanGroup, huffmanPixels: *Array'u8, huffmanBits: *u32, width, height: s32, topLevel: bool, colorCacheBits: u32) fail
{
    var mapping:       Array's16
    var maxGroupIndex: s32
    var groupCount = 1's32

    if topLevel and (try reader.read(1))
    {
        huffmanBits[] = try reader.read(3) + 2
        let tileWidth  = losslessTileCount(width, huffmanBits[])
        let tileHeight = losslessTileCount(height, huffmanBits[])
        let tileCount  = tileWidth * tileHeight
        try losslessDecodePixels(reader, huffmanPixels, tileWidth, tileHeight, 0, false)
        let huffmanData = cast([*] u8, huffmanPixels.storage())

        var offset: u64
        while offset < huffmanPixels.count
        {
            let index = (cast(s32, huffmanData[offset]) << 8) | huffmanData[offset + 1]
            maxGroupIndex = Math.max(maxGroupIndex, index)
            offset        += 4
        }

        if maxGroupIndex >= LOSSLESS_MAX_HUFFMAN_GROUPS do
            fail UnsupportedFormatError{"WebP lossless stream uses too many Huffman groups"}

        if maxGroupIndex >= 1000 or maxGroupIndex >= tileCount
        {
            mapping.resize(maxGroupIndex + 1)
            for i in mapping.count do
                mapping[i] = -1

            groupCount = 0
            offset     = 0
            while offset < huffmanPixels.count
            {
                let index = (cast(s32, huffmanData[offset]) << 8) | huffmanData[offset + 1]
                if mapping[index] == -1
                {
                    mapping[index] = cast(s16, groupCount)
                    groupCount     += 1
                }

                huffmanData[offset]     = cast(u8, (mapping[index] >> 8))
                huffmanData[offset + 1] = cast(u8, mapping[index])
                offset += 4
            }
        }
        else
        {
            groupCount = maxGroupIndex + 1
        }
    }

    groups.resize(groupCount)
    let groupData = groups.storage()
    for realIndex in maxGroupIndex + 1
    {
        var group: *LosslessHuffmanGroup?
        if mapping.isEmpty() do
            group = groupData + realIndex
        elif mapping[realIndex] != -1 do
            group = groupData + mapping[realIndex]

        for treeIndex in LOSSLESS_HUFFMAN_TREES
        {
            var alphabetSize = LOSSLESS_ALPHABET_SIZES[treeIndex]
            if treeIndex == LOSSLESS_HUFF_GREEN and colorCacheBits do
                alphabetSize += 1 << colorCacheBits

            var tree: *LosslessHuffmanTree?
            if group do
                tree = &group.trees[treeIndex]
            try losslessDecodeHuffmanTree(reader, tree, alphabetSize)
        }

        if group do
            group.buildLiteralTable()
    }
}

func losslessCopyRun(destination: [*] u32, distance, count: u64)
{
    let source = destination - distance
    if count <= 8
    {
        for i in count do
            destination[i] = source[i]
        return
    }

    if distance == 1
    {
        let pixel = source[0]
        let block = Math.Simd.splat(pixel)
        var i: u64
        while count - i >= 4
        {
            Math.Simd.store(destination + i, block)
            i += 4
        }

        for j in i until count do
            destination[j] = pixel
        return
    }

    // Copy the available seed pixels, then expand the run in disjoint chunks.
    var copied = Math.min(distance, count)
    Memory.copy(destination, source, copied * 4)
    while copied < count
    {
        let chunk = Math.min(copied, count - copied)
        Memory.copy(destination + copied, destination, chunk * 4)
        copied += chunk
    }
}

// A single tree with no length or cache symbols can skip the general run loop.
private func losslessHasOnlyLiterals(tree: *LosslessHuffmanTree)->bool
{
    let nodes = tree.nodes.storage()
    for i in tree.nodeCount
    {
        if nodes[i].children == LOSSLESS_LEAF_NODE and nodes[i].symbol >= LOSSLESS_LITERAL_CODES do
            return false
    }

    return true
}

private func losslessUniformByteTree(tree: *LosslessHuffmanTree)->bool
{
    // An eight-level full tree with 256 byte symbols assigns code i to symbol i.
    return tree.maxLength == 8 and tree.nodes.count == 511 and tree.nodeCount == 511
}

#[Swag.Inline]
private func losslessLoadReversedBytes(source: const [*] u8, shift: u8)->Math.Simd.U8x16
{
    using Math.Simd
    var bytes = load(source)
    if shift
    {
        let mask = splat(0xFF'u8 >> shift)
        let next = load(source + 1)
        let low  = cast #bit(U8x16, (cast #bit(U16x8, bytes) >> shift))
        let high = cast #bit(U8x16, (cast #bit(U16x8, next) << (8 - shift)))
        bytes = (low & mask) | (high & ~mask)
    }

    var words = cast #bit(U16x8, bytes)
    let mask1 = splat(0x5555'u16)
    let mask2 = splat(0x3333'u16)
    let mask4 = splat(0x0F0F'u16)
    words = ((words & mask1) << 1) | ((words >> 1) & mask1)
    words = ((words & mask2) << 2) | ((words >> 2) & mask2)
    return cast #bit(U8x16, (((words & mask4) << 4) | ((words >> 4) & mask4)))
}

func(CHANNELS: u32) losslessDecodeByteLiterals(reader: *LosslessBitReader, output: [*] u32, count: u64, color: u32)->bool
{
    using Math.Simd

    #[Swag.Inline]
    func readByte(source: const [*] u8, shift: u8)->u32
    {
        var byte = cast(u16, source[0])
        if shift do
            byte |= cast(u16, source[1]) << 8
        return losslessReverseByte(cast(u8, ((byte >> shift) & 0xFF)))
    }

    // Prefetched data is still in the immutable source. Locate the current bit
    // and preserve the final partial byte for the next nested image or field.
    let shift  = cast(u8, ((8 - (reader.nBits & 7)) & 7))
    let extra  = cast(u64, shift != 0)
    let source = reader.ptr - ((reader.nBits + 7) >> 3)
    let bytes  = count * CHANNELS
    if reader.last - source < bytes + extra do
        return false

    #static if CHANNELS != 4 do
        let colors = splat(color)
    var index: u64
    while bytes - index * CHANNELS >= 16
    {
        let samples = losslessLoadReversedBytes(source + index * CHANNELS, shift)
        #static if CHANNELS == 4
        {
            const Order: [16] u8 = [1, 0, 2, 3, 5, 4, 6, 7, 9, 8, 10, 11, 13, 12, 14, 15]
            store(output + index, cast #bit(U32x4, shuffle(samples, cast #bit(U8x16, Order))))
            index += 4
        }
        elif CHANNELS == 3
        {
            const Order: [16] u8 = [1, 0, 2, 0x80, 4, 3, 5, 0x80, 7, 6, 8, 0x80, 10, 9, 11, 0x80]
            store(output + index, cast #bit(U32x4, shuffle(samples, cast #bit(U8x16, Order))) | colors)
            index += 4
        }
        else
        {
            let lo = widenLow(samples)
            let hi = widenHigh(samples)
            store(output + index, colors | (widenLow(lo) << 8))
            store(output + index + 4, colors | (widenHigh(lo) << 8))
            store(output + index + 8, colors | (widenLow(hi) << 8))
            store(output + index + 12, colors | (widenHigh(hi) << 8))
            index += 16
        }
    }

    for i in index until count
    {
        let next   = source + i * CHANNELS
        var result = color | (readByte(next, shift) << 8)
        #static if CHANNELS > 1 do
            result |= readByte(next + 1, shift) | (readByte(next + 2, shift) << 16)
        #static if CHANNELS == 4 do
            result |= readByte(next + 3, shift) << 24
        output[i] = result
    }

    reader.ptr   = source + bytes + extra
    reader.bits  = shift ? cast(u64, source[bytes] >> shift) : 0
    reader.nBits = shift ? 8 - cast(u32, shift) : 0
    return true
}

func losslessDecodePixels(reader: *LosslessBitReader, result: *Array'u8, width, height, minimumCapacity: s32, topLevel: bool) fail
{
    var colorCacheBits:  u32
    var colorCacheShift: u32
    var colorCache:      Array'u32
    if try reader.read(1)
    {
        colorCacheBits = try reader.read(4)
        if colorCacheBits < 1 or colorCacheBits > 11 do
            fail InvalidFormatError{"WebP lossless color-cache size is outside 1 to 11 bits"}
        colorCacheShift = 32 - colorCacheBits
        colorCache.resize(1 << colorCacheBits)
    }

    var groups:        Array'LosslessHuffmanGroup
    var huffmanPixels: Array'u8
    var huffmanBits:   u32
    try losslessDecodeHuffmanGroups(reader, &groups, &huffmanPixels, &huffmanBits, width, height, topLevel, colorCacheBits)

    var huffmanMask: s32
    var tilesPerRow: s32
    if huffmanBits
    {
        huffmanMask = cast(s32, (1 << huffmanBits)) - 1
        tilesPerRow = losslessTileCount(width, huffmanBits)
    }

    let pixelCount = cast(u64, width) * height
    let byteCount  = pixelCount * 4
    if byteCount > 0x7FFFFFFF'u64 do
        fail UnsupportedFormatError{"WebP image needs more than 2 GiB of decoded pixel memory"}

    result.grow(Math.max(cast(u64, minimumCapacity), byteCount))
    result.count = byteCount
    let output    = cast([*] u8, result.storage())
    let groupData = groups.storage()

    if not huffmanBits and
       pixelCount >= 16 and
       losslessUniformByteTree(&groupData[0].trees[LOSSLESS_HUFF_GREEN]) and
       losslessHasOnlyLiterals(&groupData[0].trees[LOSSLESS_HUFF_GREEN])
    {
        let target = cast([*] u32, output)
        let red    = &groupData[0].trees[LOSSLESS_HUFF_RED]
        let blue   = &groupData[0].trees[LOSSLESS_HUFF_BLUE]
        let alpha  = &groupData[0].trees[LOSSLESS_HUFF_ALPHA]
        if losslessUniformByteTree(red) and losslessUniformByteTree(blue)
        {
            if losslessUniformByteTree(alpha) and losslessDecodeByteLiterals'4(reader, target, pixelCount, 0) do
                return
            if not alpha.maxLength and losslessDecodeByteLiterals'3(reader, target, pixelCount, alpha.nodes[0].symbol << 24) do
                return
        }
        elif not red.maxLength and not blue.maxLength and not alpha.maxLength
        {
            let color = red.nodes[0].symbol | (blue.nodes[0].symbol << 16) | (alpha.nodes[0].symbol << 24)
            if losslessDecodeByteLiterals'1(reader, target, pixelCount, color) do
                return
        }
    }

    let huffmanData = huffmanBits ? cast([*] u8, huffmanPixels.storage()) : null

    var offset:       u64
    var cachedOffset: u64
    var x:            s32
    var y:            s32
    var group       = groupData
    var lookupGroup = huffmanMask != 0

    while offset < byteCount
    {
        if lookupGroup
        {
            let mapIndex   = 4 * (tilesPerRow * (y >> huffmanBits) + (x >> huffmanBits))
            let mapData    = cast([*] u8, unwrap huffmanData)
            let groupIndex = (cast(u32, mapData[mapIndex]) << 8) | mapData[mapIndex + 1]
            if groupIndex >= groups.count do
                fail InvalidFormatError{"WebP lossless Huffman-group index is out of range"}
            group = groupData + groupIndex
        }

        var green = try group.trees[LOSSLESS_HUFF_GREEN].next(reader)
        switch
        {
        case green < LOSSLESS_LITERAL_CODES:
            cast([*] u32, output + offset)[0] = try group.readLiteral(reader, green)
            offset += 4

            x += 1
            if x == width
            {
                x = 0
                y += 1
            }

            lookupGroup = huffmanMask != 0 and (x & huffmanMask) == 0

        case green < LOSSLESS_LITERAL_CODES + LOSSLESS_LENGTH_CODES:
            let length         = try losslessLz77Parameter(reader, green - LOSSLESS_LITERAL_CODES)
            let distanceSymbol = try group.trees[LOSSLESS_HUFF_DISTANCE].next(reader)
            let distanceCode   = try losslessLz77Parameter(reader, distanceSymbol)
            let distance       = losslessDistance(width, distanceCode)
            let copyBytes      = cast(u64, length) * 4

            if distance <= 0 or cast(u64, distance) * 4 > offset or offset + copyBytes > byteCount do
                fail InvalidFormatError{"WebP lossless back-reference is outside the decoded image"}

            losslessCopyRun(cast([*] u32, output + offset), cast(u64, distance), length)
            offset += copyBytes

            x += cast(s32, length)
            while x >= width
            {
                x -= width
                y += 1
            }

            lookupGroup = huffmanMask != 0

        default:
            while cachedOffset < offset
            {
                let rgba = cast(const [*] u32, output + cachedOffset)[0]

                // The WebP hash uses ARGB, while the decoded pixels are stored as RGBA.
                let argb = (rgba & 0xFF00FF00'u32) | ((rgba & 0xFF) << 16) | ((rgba >> 16) & 0xFF)
                colorCache[(argb * #wrap LOSSLESS_COLOR_CACHE_MULTIPLIER) >> colorCacheShift] = rgba
                cachedOffset += 4
            }

            green -= LOSSLESS_LITERAL_CODES + LOSSLESS_LENGTH_CODES
            if green >= colorCache.count do
                fail InvalidFormatError{"WebP lossless color-cache index is out of range"}
            cast([*] u32, output + offset)[0] = colorCache[green]
            offset += 4

            x += 1
            if x == width
            {
                x = 0
                y += 1
            }

            lookupGroup = huffmanMask != 0 and (x & huffmanMask) == 0
        }
    }
}

func losslessWrap8(value: s32)->u8 => cast(u8, (value & 0xFF))

#[Swag.Inline]
private func losslessAverageDown(a, b: Math.Simd.U8x16)->Math.Simd.U8x16
{
    using Math.Simd
    return average(a, b) - ((a ^ b) & splat(1'u8))
}

func losslessInversePredictor(transform: *LosslessTransform, pixels: *Array'u8, height: s32)
{
    using Math.Simd

    // The low seven bits of each channel add without carrying into the next channel.
    #[Swag.Inline]
    func addPixel(destination: [*] u32, prediction: u32)
    {
        let value = destination[0]
        let low   = (value & 0x7F7F7F7F'u32) + (prediction & 0x7F7F7F7F'u32)
        destination[0] = low ^ ((value ^ prediction) & 0x80808080'u32)
    }

    #[Swag.Inline]
    func averagePixel(a, b: u32)->u32 => (a & b) + (((a ^ b) & 0xFEFEFEFE'u32) >> 1)

    func addFromLeft(row: [*] u32, start, end: s32)
    {
        var column = start
        if end - start >= 4
        {
            let zero  = splat(0'u8)
            var carry = row[start - 1]
            while end - column >= 4
            {
                // Two shifts accumulate four residuals independently in every channel.
                let residual = cast #bit(U8x16, load(row + column))
                let pairs    = residual + align(zero, residual, 12)
                let sums     = pairs + align(zero, pairs, 8)
                let pixels   = cast #bit(U32x4, (sums + cast #bit(U8x16, splat(carry))))
                store(row + column, pixels)
                carry  = pixels[3]
                column += 4
            }
        }

        for x in column until end do
            addPixel(row + x, row[x - 1])
    }

    func addSpan(destination: [*] u32, prediction: const [*] u32, count: s32)
    {
        var i: s32
        while count - i >= 4
        {
            let residual = cast #bit(U8x16, load(destination + i))
            let above    = cast #bit(U8x16, load(prediction + i))
            store(destination + i, cast #bit(U32x4, (residual + above)))
            i += 4
        }

        for j in i until count do
            addPixel(destination + j, prediction[j])
    }

    func addAverages(destination: [*] u32, left, right: const [*] u32, count: s32)
    {
        var x: s32
        while count - x >= 4
        {
            let a        = cast #bit(U8x16, load(left + x))
            let b        = cast #bit(U8x16, load(right + x))
            let residual = cast #bit(U8x16, load(destination + x))
            store(destination + x, cast #bit(U32x4, (residual + losslessAverageDown(a, b))))
            x += 4
        }

        for i in x until count do
            addPixel(destination + i, averagePixel(left[i], right[i]))
    }

    func addColor(row: [*] u32, first, last: s32, color: u32)
    {
        let value = cast #bit(U8x16, splat(color))
        var x     = first
        while last - x >= 4
        {
            let residual = cast #bit(U8x16, load(row + x))
            store(row + x, cast #bit(U32x4, (residual + value)))
            x += 4
        }

        for i in x until last do
            addPixel(row + i, color)
    }

    func addSelected(row: [*] u32, top: const [*] u32, first, last: s32)
    {
        var left   = cast #bit(U8x16, splat(row[first - 1]))
        var corner = cast #bit(U8x16, splat(top[first - 1]))
        for x in first until last
        {
            let above    = cast #bit(U8x16, splat(top[x]))
            let residual = cast #bit(U8x16, splat(row[x]))

            // The low half contains two copies of the four channel differences.
            let aboveDistance = absoluteDifferences(corner, above)[0]
            let leftDistance  = absoluteDifferences(corner, left)[0]
            left = residual + (aboveDistance < leftDistance ? left : above)
            storeLow4(cast([*] u8, row + x), left)
            corner = above
        }
    }

    func(HALF: bool) addGradient(row: [*] u32, top: const [*] u32, first, last: s32)
    {
        #[Swag.Inline]
        func halve(value: U8x16)->U8x16
        {
            let even = value & splat(0xFE'u8)
            return cast #bit(U8x16, (cast #bit(U16x8, even) >> 1))
        }

        var left   = cast #bit(U8x16, splat(row[first - 1]))
        var corner = cast #bit(U8x16, splat(top[first - 1]))
        for x in first until last
        {
            let above    = cast #bit(U8x16, splat(top[x]))
            let residual = cast #bit(U8x16, splat(row[x]))
            #static if HALF
            {
                // Halve the magnitude before applying its sign, matching signed division.
                let mean     = losslessAverageDown(left, above)
                let increase = halve(subSaturating(mean, corner))
                let decrease = halve(subSaturating(corner, mean))
                left = residual + addSaturating(subSaturating(mean, decrease), increase)
            }
            else
            {
                // At most one direction is nonzero in a channel, so saturation clips once.
                let increase = subSaturating(above, corner)
                let decrease = subSaturating(corner, above)
                left = residual + addSaturating(subSaturating(left, decrease), increase)
            }

            storeLow4(cast([*] u8, row + x), left)
            corner = above
        }
    }

    let width = transform.oldWidth
    if width == 0 or height == 0 do
        return

    let data = cast([*] u32, pixels.storage())
    addPixel(data, 0xFF000000)
    addFromLeft(data, 1, width)

    let tileWidth   = 1's32 << transform.bits
    let tilesPerRow = losslessTileCount(width, transform.bits)
    let parameters  = transform.pixels.storage()
    for y in 1 until height
    {
        let row = data + cast(u64, y) * width
        let top = row - width
        addPixel(row, top[0])

        var tile     = cast(u64, (4 * (y >> transform.bits) * tilesPerRow)) + 1
        var x        = 1's32
        var boundary = tileWidth
        while x < width
        {
            let endX = Math.min(width, boundary)
            switch parameters[tile] & 0x0F
            {
            case 0:
                addColor(row, x, endX, 0xFF000000)

            case 1:
                addFromLeft(row, x, endX)

            case 2:
                addSpan(row + x, top + x, endX - x)

            case 3:
                addSpan(row + x, top + x + 1, endX - x)

            case 4:
                addSpan(row + x, top + x - 1, endX - x)

            case 5:
                for column in x until endX do
                    addPixel(row + column, averagePixel(averagePixel(row[column - 1], top[column + 1]), top[column]))

            case 6:
                for column in x until endX do
                    addPixel(row + column, averagePixel(row[column - 1], top[column - 1]))

            case 7:
                for column in x until endX do
                    addPixel(row + column, averagePixel(row[column - 1], top[column]))

            case 8:
                addAverages(row + x, top + x - 1, top + x, endX - x)

            case 9:
                addAverages(row + x, top + x, top + x + 1, endX - x)

            case 10:
                for column in x until endX do
                    addPixel(row + column, averagePixel(averagePixel(row[column - 1], top[column - 1]), averagePixel(top[column], top[column + 1])))

            case 11:
                addSelected(row, top, x, endX)

            case 12:
                addGradient'false(row, top, x, endX)

            case 13:
                addGradient'true(row, top, x, endX)
            }

            x        = endX
            boundary += tileWidth
            tile     += 4
        }
    }
}

func losslessInverseCrossColor(transform: *LosslessTransform, pixels: *Array'u8, height: s32)
{
    using Math.Simd

    const GreenSamples = cast(U8x16, [0x80'u8, 1, 0x80, 1, 0x80, 5, 0x80, 5, 0x80, 9, 0x80, 9, 0x80, 13, 0x80, 13])
    const RedSamples   = cast(U8x16, [0x80'u8, 0, 0x80, 0, 0x80, 4, 0x80, 4, 0x80, 8, 0x80, 8, 0x80, 12, 0x80, 12])
    const GreenAlpha   = cast(U8x16, [0'u8, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255])

    #[Swag.Inline]
    func multipliers(red, blue: s32)->S16x8
    {
        // Samples occupy the high byte of each signed lane. Shifting factors by three makes
        // the signed high product equal to (sample * factor) >> 5.
        let redLanes  = cast #bit(U16x8, splat(cast(s16, red * 8)))
        let blueLanes = cast #bit(U16x8, splat(cast(s16, blue * 8)))
        return cast #bit(S16x8, interleaveLow(redLanes, blueLanes))
    }

    let width        = transform.oldWidth
    let tileWidth    = 1's32 << transform.bits
    let tilesPerRow  = losslessTileCount(width, transform.bits)
    let data         = pixels.storage()
    let coefficients = transform.pixels.storage()

    for y in height
    {
        let row     = data + cast(u64, y) * width * 4
        let tileRow = coefficients + cast(u64, ((y >> transform.bits) * tilesPerRow)) * 4
        for tile in tilesPerRow
        {
            let color        = tileRow + cast(u64, tile) * 4
            let redToBlue    = cast(s32, cast #bit(s8, color[0]))
            let greenToBlue  = cast(s32, cast #bit(s8, color[1]))
            let greenToRed   = cast(s32, cast #bit(s8, color[2]))
            let greenFactors = multipliers(greenToRed, greenToBlue)
            let redFactors   = multipliers(0, redToBlue)
            var x            = tile * tileWidth
            let end          = Math.min(x + tileWidth, width)
            var target       = row + cast(u64, x) * 4
            while end - x >= 4
            {
                let input     = load(target)
                let green     = cast #bit(S16x8, shuffle(input, GreenSamples))
                let corrected = input + cast #bit(U8x16, mulHigh(green, greenFactors))
                let red       = cast #bit(S16x8, shuffle(corrected, RedSamples))
                let output    = corrected + cast #bit(U8x16, mulHigh(red, redFactors))
                store(target, (output & ~GreenAlpha) | (input & GreenAlpha))
                target += 16
                x      += 4
            }

            for end - x
            {
                let green = cast(s32, cast #bit(s8, target[1]))
                let red   = cast(s32, target[0]) + ((greenToRed * green) >> 5)
                let blue  = cast(s32, target[2]) + ((greenToBlue * green) >> 5) + ((redToBlue * cast(s32, cast #bit(s8, losslessWrap8(red)))) >> 5)
                target[0] = losslessWrap8(red)
                target[2] = losslessWrap8(blue)
                target    += 4
            }
        }
    }
}

func losslessInverseSubtractGreen(pixels: *Array'u8)
{
    using Math.Simd

    const Green = cast(U8x16, [1'u8, 0x80, 1, 0x80, 5, 0x80, 5, 0x80, 9, 0x80, 9, 0x80, 13, 0x80, 13, 0x80])
    let data = cast([*] u8, pixels.storage())
    var offset: u64
    while pixels.count - offset >= 16
    {
        let rgba = load(data + offset)
        store(data + offset, rgba + shuffle(rgba, Green))
        offset += 16
    }

    while offset < pixels.count
    {
        let green = data[offset + 1]
        data[offset + 0] += #wrap green
        data[offset + 2] += #wrap green
        offset += 4
    }
}

func losslessInverseColorIndexing(transform: *LosslessTransform, pixels: *Array'u8, height: s32)
{
    using Math.Simd

    let data    = cast([*] u32, pixels.storage())
    let palette = cast(const [*] u32, transform.pixels.storage())
    if transform.bits == 0
    {
        for i in pixels.count / 4 do
            data[i] = palette[(data[i] >> 8) & 0xFF]
        return
    }

    let width        = transform.oldWidth
    let packedWidth  = losslessTileCount(width, transform.bits)
    let groupSize    = 1's32 << transform.bits
    let bitsPerPixel = 8'u32 >> transform.bits
    let valueMask    = (1'u32 << bitsPerPixel) - 1
    let byteCount    = 4'u64 * width * height
    var decoded: Array'u8
    decoded.grow(byteCount)
    decoded.count = byteCount
    let target = cast([*] u32, decoded.storage())

    let zero     = splat(0'u32)
    let first    = splat(palette[0])
    let second   = splat(palette[1])
    let lowBits  = cast(U32x4, [1'u32, 2, 4, 8])
    let highBits = lowBits << 4
    for y in height
    {
        let input  = data + cast(u64, y) * packedWidth
        let output = target + cast(u64, y) * width
        var x: s32
        var packedColumn: s32
        if transform.bits == 3
        {
            // Expand each green byte to eight consecutive entries of the two-color palette.
            while width - x >= 8
            {
                let selector = splat((input[packedColumn] >> 8) & 0xFF)
                store(output + x, select((selector & lowBits) != zero, second, first))
                store(output + x + 4, select((selector & highBits) != zero, second, first))
                x += 8
                packedColumn += 1
            }
        }

        while x < width
        {
            let count   = Math.min(groupSize, width - x)
            var indices = (input[packedColumn] >> 8) & 0xFF
            for i in count
            {
                output[x + i] = palette[indices & valueMask]
                indices       >>= bitsPerPixel
            }

            x += count
            packedColumn += 1
        }
    }

    swap(pixels, &decoded)
}

func losslessApplyInverseTransform(transform: *LosslessTransform, pixels: *Array'u8, height: s32)
{
    switch transform.kind
    {
    case LOSSLESS_TRANSFORM_PREDICTOR:      losslessInversePredictor(transform, pixels, height)
    case LOSSLESS_TRANSFORM_CROSS_COLOR:    losslessInverseCrossColor(transform, pixels, height)
    case LOSSLESS_TRANSFORM_SUBTRACT_GREEN: losslessInverseSubtractGreen(pixels)
    case LOSSLESS_TRANSFORM_COLOR_INDEXING: losslessInverseColorIndexing(transform, pixels, height)
    }
}

func losslessDecode(source: const [..] u8, pixels: *Array'u8, width: *s32, height: *s32) fail
{
    var reader: LosslessBitReader
    try losslessDecodeHeader(&reader, source, width, height)

    try losslessDecodeStream(&reader, pixels, width[], height[])
}

func losslessDecodeStream(reader: *LosslessBitReader, pixels: *Array'u8, width, height: s32) fail
{
    var transforms:     Array'LosslessTransform
    var seenTransforms: [LOSSLESS_TRANSFORM_COUNT] bool
    let originalWidth    = width
    var transformedWidth = originalWidth

    while try reader.read(1)
    {
        if transforms.count == LOSSLESS_TRANSFORM_COUNT do
            fail InvalidFormatError{"WebP lossless stream contains too many transforms"}

        transforms.resize(transforms.count + 1)
        let transform = &transforms[transforms.count - 1]
        transformedWidth = try losslessDecodeTransform(reader, transform, transformedWidth, height)
        if seenTransforms[transform.kind] do
            fail InvalidFormatError{"WebP lossless stream repeats a transform"}
        seenTransforms[transform.kind] = true
    }

    try losslessDecodePixels(reader, pixels, transformedWidth, height, 0, true)

    var index = transforms.count
    while index
    {
        index -= 1
        losslessApplyInverseTransform(&transforms[index], pixels, height)
    }

    let expectedSize = cast(u64, originalWidth) * height * 4
    if pixels.count != expectedSize do
        fail InvalidFormatError{"WebP lossless transforms produce a pixel count different from the image dimensions"}
}
