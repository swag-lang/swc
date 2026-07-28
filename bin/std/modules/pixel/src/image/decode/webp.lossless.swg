#global namespace Webp

using Core, Core.Errors

/*
    The VP8L decoder is derived from golang.org/x/image/vp8l.
    See webp.LICENSE for the original BSD license.
*/

const LOSSLESS_COLOR_CACHE_MULTIPLIER = 0x1E35A7BD'u32
const LOSSLESS_LUT_BITS               = 7'u32
const LOSSLESS_LUT_MASK               = (1 << LOSSLESS_LUT_BITS) - 1
const LOSSLESS_LEAF_NODE              = -1's32
const LOSSLESS_MAX_CODE_LENGTH        = 15'u32
const LOSSLESS_LITERAL_CODES          = 256'u32
const LOSSLESS_LENGTH_CODES           = 24'u32
const LOSSLESS_DISTANCE_CODES         = 40'u32
const LOSSLESS_HUFFMAN_TREES          = 5
const LOSSLESS_MAX_HUFFMAN_GROUPS     = 2600

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
    0x40, 0x72, 0x7E, 0x61, 0x6F, 0x50, 0x71, 0x7F, 0x60, 0x70,
    ]

const LOSSLESS_CODE_LENGTH_ORDER: [19] u8 = [
    17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    ]

const LOSSLESS_REPEAT_BITS:    [3] u8                       = [2, 3, 7]
const LOSSLESS_REPEAT_OFFSETS: [3] u8                       = [3, 3, 11]
const LOSSLESS_ALPHABET_SIZES: [LOSSLESS_HUFFMAN_TREES] u32 = [
    LOSSLESS_LITERAL_CODES + LOSSLESS_LENGTH_CODES,
    LOSSLESS_LITERAL_CODES,
    LOSSLESS_LITERAL_CODES,
    LOSSLESS_LITERAL_CODES,
    LOSSLESS_DISTANCE_CODES,
    ]

struct LosslessBitReader
{
    ptr:   const [*] u8
    last:  const [*] u8
    bits:  u64
    nBits: u32
}

impl LosslessBitReader
{
    mtd read(count: u32)->u32 fail
    {
        if count > 32 do
            fail InvalidFormatError{"WebP bit field exceeds 32 bits"}

        while .nBits < count
        {
            if .ptr >= .last do
                fail InvalidFormatError{"WebP data ends inside the lossless bitstream"}
            .bits  |= cast(u64) dref .ptr << .nBits
            .ptr   += 1
            .nBits += 8
        }

        let mask  = count == 32 ? 0xFFFFFFFF'u64 : ((1'u64 << count) - 1)
        let value = cast(u32) (.bits & mask)
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
    lut:       [1 << LOSSLESS_LUT_BITS] u32
}

struct LosslessHuffmanGroup
{
    trees: [LOSSLESS_HUFFMAN_TREES] LosslessHuffmanTree
}

struct LosslessTransform
{
    kind:     u32
    oldWidth: s32
    bits:     u32
    pixels:   Array'u8
}

func losslessTileCount(size: s32, bits: u32)->s32
{
    return (size + cast(s32) (1 << bits) - 1) >> bits
}

func losslessReverseByte(value: u8)->u8
{
    var v = value
    v = cast(u8) (((v & 0x55) << 1) | ((v >> 1) & 0x55))
    v = cast(u8) (((v & 0x33) << 2) | ((v >> 2) & 0x33))
    return cast(u8) ((cast(u32) (v & 0x0F) << 4) | (v >> 4))
}

func losslessTreeError() fail
{
    fail InvalidFormatError{"WebP lossless Huffman tree is inconsistent"}
}

impl LosslessHuffmanTree
{
    mtd insert(symbol, code, codeLength: u32) fail
    {
        if symbol > 0xFFFF or codeLength > 0xFE do
            losslessTreeError()

        var baseCode: u32
        if codeLength > LOSSLESS_LUT_BITS
        {
            let shift = codeLength - LOSSLESS_LUT_BITS
            baseCode = cast(u32) losslessReverseByte(cast(u8) ((code >> shift) & 0xFF)) >> (8 - LOSSLESS_LUT_BITS)
        }
        else
        {
            baseCode = cast(u32) losslessReverseByte(cast(u8) (code & 0xFF)) >> (8 - codeLength)
            let count = 1'u32 << (LOSSLESS_LUT_BITS - codeLength)
            for [i] in count do
                .lut[baseCode | (i << codeLength)] = (symbol << 8) | (codeLength + 1)
        }

        var node      = 0'u32
        var jump      = LOSSLESS_LUT_BITS
        var remaining = codeLength
        while remaining
        {
            remaining -= 1
            if node >= .nodeCount do
                losslessTreeError()

            switch .nodes[node].children
            {
            case LOSSLESS_LEAF_NODE:
                losslessTreeError()

            case 0:
                if .nodeCount + 2 > .nodes.count do
                    losslessTreeError()
                .nodes[node].children = cast(s32) .nodeCount
                .nodeCount            += 2
            }

            node = cast(u32) .nodes[node].children + ((code >> remaining) & 1)
            if jump
            {
                jump -= 1
                if jump == 0 and .lut[baseCode] == 0 do
                    .lut[baseCode] = node << 8
            }
        }

        if .nodes[node].children == 0
        {
            .nodes[node].children = LOSSLESS_LEAF_NODE
        }
        elif .nodes[node].children != LOSSLESS_LEAF_NODE
        {
            losslessTreeError()
        }

        .nodes[node].symbol = symbol
    }

    mtd build(codeLengths: const [..] u32) fail
    {
        var symbolCount: u32
        var lastSymbol:  u32
        var maxLength:   u32
        for [symbol] in @countof(codeLengths)
        {
            let length = codeLengths[symbol]
            if length
            {
                symbolCount += 1
                lastSymbol  = cast(u32) symbol
                maxLength   = Math.max(maxLength, length)
            }
        }

        if symbolCount == 0 or maxLength > LOSSLESS_MAX_CODE_LENGTH do
            losslessTreeError()

        .nodes.resize(2 * symbolCount - 1)
        .nodeCount = 1
        Memory.clear(cast([*] void) notnull .nodes.buffer, .nodes.count * #sizeof(LosslessHuffmanNode))
        Memory.clear(&.lut[0], #sizeof(.lut))

        if symbolCount == 1
        {
            .insert(lastSymbol, 0, 0)
            return
        }

        var histogram: [LOSSLESS_MAX_CODE_LENGTH + 1] u32
        for length in codeLengths do
            histogram[length] += 1

        var nextCodes:   [LOSSLESS_MAX_CODE_LENGTH + 1] u32
        var currentCode: u32
        var length = 1'u64
        while length < @countof(nextCodes)
        {
            currentCode       = (currentCode + histogram[length - 1]) << 1
            nextCodes[length] = currentCode
            length            += 1
        }

        for [symbol] in @countof(codeLengths)
        {
            let length = codeLengths[symbol]
            if !length do
                continue
            let code = nextCodes[length]
            nextCodes[length] += 1
            .insert(cast(u32) symbol, code, length)
        }
    }

    mtd buildSimple(symbolCount: u32, symbols: [2] u32, alphabetSize: u32) fail
    {
        .nodes.resize(2 * symbolCount - 1)
        .nodeCount = 1
        Memory.clear(cast([*] void) notnull .nodes.buffer, .nodes.count * #sizeof(LosslessHuffmanNode))
        Memory.clear(&.lut[0], #sizeof(.lut))

        for [i] in symbolCount
        {
            if symbols[i] >= alphabetSize do
                losslessTreeError()
            .insert(symbols[i], i, symbolCount - 1)
        }
    }

    mtd next(reader: *LosslessBitReader)->u32 fail
    {
        var node: u32
        if reader.nBits < LOSSLESS_LUT_BITS and reader.ptr < reader.last
        {
            reader.bits  |= cast(u64) dref reader.ptr << reader.nBits
            reader.ptr   += 1
            reader.nBits += 8
        }

        if reader.nBits >= LOSSLESS_LUT_BITS
        {
            let entry    = .lut[reader.bits & LOSSLESS_LUT_MASK]
            let bitCount = entry & 0xFF
            if bitCount
            {
                let consumed = bitCount - 1
                reader.bits  >>= consumed
                reader.nBits -= consumed
                return entry >> 8
            }

            node         = entry >> 8
            reader.bits  >>= LOSSLESS_LUT_BITS
            reader.nBits -= LOSSLESS_LUT_BITS
        }

        while true
        {
            if node >= .nodeCount do
                losslessTreeError()
            if .nodes[node].children == LOSSLESS_LEAF_NODE do
                return .nodes[node].symbol

            if reader.nBits == 0
            {
                if reader.ptr >= reader.last do
                    fail InvalidFormatError{"WebP data ends inside a Huffman code"}
                reader.bits  = dref reader.ptr
                reader.ptr   += 1
                reader.nBits = 8
            }

            node         = cast(u32) .nodes[node].children + cast(u32) (reader.bits & 1)
            reader.bits  >>= 1
            reader.nBits -= 1
        }
    }
}

func losslessDistance(width: s32, code: u32)->s32
{
    if code > @countof(LOSSLESS_DISTANCE_MAP) do
        return cast(s32) code - @countof(LOSSLESS_DISTANCE_MAP)

    let distanceCode = cast(s32) LOSSLESS_DISTANCE_MAP[code - 1]
    let yOffset      = distanceCode >> 4
    let xOffset      = 8 - (distanceCode & 0x0F)
    let distance     = yOffset * width + xOffset
    return Math.max(distance, 1)
}

func losslessDecodeCodeLengths(reader: *LosslessBitReader, destination: [..] u32, codeLengthCodeLengths: const [..] u32) fail
{
    var tree: LosslessHuffmanTree
    tree.build(codeLengthCodeLengths)

    var maxSymbol = @countof(destination)
    if reader.read(1)
    {
        let countBits = 2 + 2 * reader.read(3)
        maxSymbol = cast(u64) reader.read(countBits) + 2
        if maxSymbol > @countof(destination) do
            fail InvalidFormatError{"WebP lossless code lengths exceed their alphabet"}
    }

    var previousLength = 8'u32
    var symbol: u64
    while symbol < @countof(destination)
    {
        if maxSymbol == 0 do
            break
        maxSymbol -= 1

        let codeLength = tree.next(reader)
        if codeLength < 16
        {
            destination[symbol] = codeLength
            symbol              += 1
            if codeLength do
                previousLength = codeLength
            continue
        }

        if codeLength > 18 do
            fail InvalidFormatError{"WebP lossless code-length repeat symbol is out of range"}
        let repeatIndex = codeLength - 16
        let repeat      = reader.read(LOSSLESS_REPEAT_BITS[repeatIndex]) + LOSSLESS_REPEAT_OFFSETS[repeatIndex]
        if symbol + repeat > @countof(destination) do
            fail InvalidFormatError{"WebP lossless code-length repeat exceeds its alphabet"}

        let repeatedLength = codeLength == 16 ? previousLength : 0'u32
        for repeat
        {
            destination[symbol] = repeatedLength
            symbol              += 1
        }
    }
}

func losslessDecodeHuffmanTree(reader: *LosslessBitReader, tree: #null *LosslessHuffmanTree, alphabetSize: u32) fail
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
    if codeCount > @countof(LOSSLESS_CODE_LENGTH_ORDER) do
        losslessTreeError()

    var codeLengthCodeLengths: [@countof(LOSSLESS_CODE_LENGTH_ORDER)] u32
    for [i] in codeCount do
        codeLengthCodeLengths[LOSSLESS_CODE_LENGTH_ORDER[i]] = reader.read(3)

    var codeLengths: Array'u32
    codeLengths.resize(alphabetSize)
    losslessDecodeCodeLengths(reader, codeLengths.toSlice(), @mkslice(&codeLengthCodeLengths[0], @countof(codeLengthCodeLengths)))
    if tree do
        tree.build(codeLengths.toSlice())
}

func losslessDecodeHeader(reader: *LosslessBitReader, source: const [..] u8, width: *s32, height: *s32) fail
{
    reader.ptr   = @dataof(source)
    reader.last  = reader.ptr + @countof(source)
    reader.bits  = 0
    reader.nBits = 0
    if reader.read(8) != 0x2F do
        fail InvalidFormatError{"WebP lossless stream does not start with the VP8L signature"}

    dref width  = cast(s32) reader.read(14) + 1
    dref height = cast(s32) reader.read(14) + 1
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
    return offset + reader.read(extraBits) + 1
}

func losslessDecodeTransform(reader: *LosslessBitReader, transform: *LosslessTransform, width, height: s32)->s32 fail
{
    transform.oldWidth = width
    transform.kind     = reader.read(2)

    switch transform.kind
    {
    case LOSSLESS_TRANSFORM_PREDICTOR, LOSSLESS_TRANSFORM_CROSS_COLOR:
        transform.bits = reader.read(3) + 2
        losslessDecodePixels(reader, &transform.pixels, losslessTileCount(width, transform.bits), losslessTileCount(height, transform.bits), 0, false)
        return width

    case LOSSLESS_TRANSFORM_SUBTRACT_GREEN:
        return width

    case LOSSLESS_TRANSFORM_COLOR_INDEXING:
        let colorCount = reader.read(8) + 1
        switch
        {
        case colorCount <= 2:  transform.bits = 3
        case colorCount <= 4:  transform.bits = 2
        case colorCount <= 16: transform.bits = 1
        default:               transform.bits = 0
        }

        losslessDecodePixels(reader, &transform.pixels, cast(s32) colorCount, 1, 4 * 256, false)
        var offset = 4'u64
        while offset < transform.pixels.count
        {
            transform.pixels[offset + 0] = cast(u8) (cast(u32) transform.pixels[offset + 0] + transform.pixels[offset - 4])
            transform.pixels[offset + 1] = cast(u8) (cast(u32) transform.pixels[offset + 1] + transform.pixels[offset - 3])
            transform.pixels[offset + 2] = cast(u8) (cast(u32) transform.pixels[offset + 2] + transform.pixels[offset - 2])
            transform.pixels[offset + 3] = cast(u8) (cast(u32) transform.pixels[offset + 3] + transform.pixels[offset - 1])
            offset                       += 4
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

    if topLevel and reader.read(1)
    {
        dref huffmanBits = reader.read(3) + 2
        let tileWidth  = losslessTileCount(width, dref huffmanBits)
        let tileHeight = losslessTileCount(height, dref huffmanBits)
        let tileCount  = tileWidth * tileHeight
        losslessDecodePixels(reader, huffmanPixels, tileWidth, tileHeight, 0, false)
        let huffmanData = cast([*] u8) notnull huffmanPixels.buffer

        var offset: u64
        while offset < huffmanPixels.count
        {
            let index = (cast(s32) huffmanData[offset] << 8) | huffmanData[offset + 1]
            maxGroupIndex = Math.max(maxGroupIndex, index)
            offset        += 4
        }

        if maxGroupIndex >= LOSSLESS_MAX_HUFFMAN_GROUPS do
            fail UnsupportedFormatError{"WebP lossless stream uses too many Huffman groups"}

        if maxGroupIndex >= 1000 or maxGroupIndex >= tileCount
        {
            mapping.resize(maxGroupIndex + 1)
            for [i] in mapping.count do
                mapping[i] = -1

            groupCount = 0
            offset     = 0
            while offset < huffmanPixels.count
            {
                let index = (cast(s32) huffmanData[offset] << 8) | huffmanData[offset + 1]
                if mapping[index] == -1
                {
                    mapping[index] = cast(s16) groupCount
                    groupCount     += 1
                }

                huffmanData[offset]     = cast(u8) (mapping[index] >> 8)
                huffmanData[offset + 1] = cast(u8) mapping[index]
                offset                  += 4
            }
        }
        else
        {
            groupCount = maxGroupIndex + 1
        }
    }

    groups.resize(groupCount)
    let groupData = notnull groups.buffer
    for [realIndex] in maxGroupIndex + 1
    {
        var group: #null *LosslessHuffmanGroup
        if mapping.count == 0 do
            group = groupData + realIndex
        elif mapping[realIndex] != -1 do
            group = groupData + mapping[realIndex]

        for [treeIndex] in LOSSLESS_HUFFMAN_TREES
        {
            var alphabetSize = LOSSLESS_ALPHABET_SIZES[treeIndex]
            if treeIndex == LOSSLESS_HUFF_GREEN and colorCacheBits do
                alphabetSize += 1 << colorCacheBits

            var tree: #null *LosslessHuffmanTree
            if group do
                tree = &group.trees[treeIndex]
            losslessDecodeHuffmanTree(reader, tree, alphabetSize)
        }
    }
}

func losslessDecodePixels(reader: *LosslessBitReader, result: *Array'u8, width, height, minimumCapacity: s32, topLevel: bool) fail
{
    var colorCacheBits:  u32
    var colorCacheShift: u32
    var colorCache:      Array'u32
    if reader.read(1)
    {
        colorCacheBits = reader.read(4)
        if colorCacheBits < 1 or colorCacheBits > 11 do
            fail InvalidFormatError{"WebP lossless color-cache size is outside 1 to 11 bits"}
        colorCacheShift = 32 - colorCacheBits
        colorCache.resize(1 << colorCacheBits)
    }

    var groups:        Array'LosslessHuffmanGroup
    var huffmanPixels: Array'u8
    var huffmanBits:   u32
    losslessDecodeHuffmanGroups(reader, &groups, &huffmanPixels, &huffmanBits, width, height, topLevel, colorCacheBits)

    var huffmanMask: s32
    var tilesPerRow: s32
    if huffmanBits
    {
        huffmanMask = cast(s32) (1 << huffmanBits) - 1
        tilesPerRow = losslessTileCount(width, huffmanBits)
    }

    let pixelCount = cast(u64) width * height
    let byteCount  = pixelCount * 4
    if byteCount > 0x7FFFFFFF'u64 do
        fail UnsupportedFormatError{"WebP image needs more than 2 GiB of decoded pixel memory"}

    result.resize(Math.max(cast(u64) minimumCapacity, byteCount))
    result.count = byteCount
    let output      = cast([*] u8) notnull result.buffer
    let groupData   = notnull groups.buffer
    let huffmanData = huffmanBits ? cast([*] u8) notnull huffmanPixels.buffer : null

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
            let mapData    = cast([*] u8) notnull huffmanData
            let groupIndex = (cast(u32) mapData[mapIndex] << 8) | mapData[mapIndex + 1]
            if groupIndex >= groups.count do
                fail InvalidFormatError{"WebP lossless Huffman-group index is out of range"}
            group = groupData + groupIndex
        }

        var green = group.trees[LOSSLESS_HUFF_GREEN].next(reader)
        switch
        {
        case green < LOSSLESS_LITERAL_CODES:
            output[offset + 0] = cast(u8) group.trees[LOSSLESS_HUFF_RED].next(reader)
            output[offset + 1] = cast(u8) green
            output[offset + 2] = cast(u8) group.trees[LOSSLESS_HUFF_BLUE].next(reader)
            output[offset + 3] = cast(u8) group.trees[LOSSLESS_HUFF_ALPHA].next(reader)
            offset             += 4

            x += 1
            if x == width
            {
                x = 0
                y += 1
            }

            lookupGroup = huffmanMask != 0 and (x & huffmanMask) == 0

        case green < LOSSLESS_LITERAL_CODES + LOSSLESS_LENGTH_CODES:
            let length         = losslessLz77Parameter(reader, green - LOSSLESS_LITERAL_CODES)
            let distanceSymbol = group.trees[LOSSLESS_HUFF_DISTANCE].next(reader)
            let distanceCode   = losslessLz77Parameter(reader, distanceSymbol)
            let distance       = losslessDistance(width, distanceCode)
            let copyBytes      = cast(u64) length * 4

            if distance <= 0 or cast(u64) distance * 4 > offset or offset + copyBytes > byteCount do
                fail InvalidFormatError{"WebP lossless back-reference is outside the decoded image"}

            var sourceOffset = offset - cast(u64) distance * 4
            let endOffset    = offset + copyBytes
            while offset < endOffset
            {
                output[offset] = output[sourceOffset]
                offset         += 1
                sourceOffset   += 1
            }

            x += cast(s32) length
            while x >= width
            {
                x -= width
                y += 1
            }

            lookupGroup = huffmanMask != 0

        default:
            while cachedOffset < offset
            {
                let argb = (cast(u32) output[cachedOffset + 0] << 16) |
                           (cast(u32) output[cachedOffset + 1] << 8) |
                           output[cachedOffset + 2] |
                           (cast(u32) output[cachedOffset + 3] << 24)
                colorCache[(argb * LOSSLESS_COLOR_CACHE_MULTIPLIER) >> colorCacheShift] = argb
                cachedOffset                                                            += 4
            }

            green -= LOSSLESS_LITERAL_CODES + LOSSLESS_LENGTH_CODES
            if green >= colorCache.count do
                fail InvalidFormatError{"WebP lossless color-cache index is out of range"}
            let argb = colorCache[green]
            output[offset + 0] = cast(u8) (argb >> 16)
            output[offset + 1] = cast(u8) (argb >> 8)
            output[offset + 2] = cast(u8) argb
            output[offset + 3] = cast(u8) (argb >> 24)
            offset             += 4

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

func losslessWrap8(value: s32)->u8
{
    return cast(u8) (value & 0xFF)
}

func losslessAverage(a, b: u8)->u8
{
    return cast(u8) ((cast(u32) a + b) / 2)
}

func losslessClampAddSubtractFull(a, b, c: u8)->u8
{
    return cast(u8) Math.clamp(cast(s32) a + b - c, 0, 255)
}

func losslessClampAddSubtractHalf(a, b: u8)->u8
{
    let value = cast(s32) a + (cast(s32) a - b) / 2
    return cast(u8) Math.clamp(value, 0, 255)
}

func losslessAddAt(pixels: *Array'u8, offset: u64, value: u8)
{
    let data = cast([*] u8) notnull pixels.buffer
    data[offset] = cast(u8) (cast(u32) data[offset] + value)
}

func losslessInversePredictor(transform: *LosslessTransform, pixels: *Array'u8, height: s32)
{
    if transform.oldWidth == 0 or height == 0 do
        return

    losslessAddAt(pixels, 3, 0xFF)
    let data   = cast([*] u8) notnull pixels.buffer
    var offset = 4'u64
    let mask   = cast(s32) (1 << transform.bits) - 1
    for transform.oldWidth - 1
    {
        losslessAddAt(pixels, offset + 0, data[offset - 4])
        losslessAddAt(pixels, offset + 1, data[offset - 3])
        losslessAddAt(pixels, offset + 2, data[offset - 2])
        losslessAddAt(pixels, offset + 3, data[offset - 1])
        offset += 4
    }

    var top         = 0'u64
    let tilesPerRow = losslessTileCount(transform.oldWidth, transform.bits)
    var y           = 1's32
    while y < height
    {
        losslessAddAt(pixels, offset + 0, data[top + 0])
        losslessAddAt(pixels, offset + 1, data[top + 1])
        losslessAddAt(pixels, offset + 2, data[top + 2])
        losslessAddAt(pixels, offset + 3, data[top + 3])
        offset += 4
        top    += 4

        var transformOffset = cast(u64) (4 * (y >> transform.bits) * tilesPerRow)
        var predictorMode   = transform.pixels[transformOffset + 1] & 0x0F
        transformOffset += 4

        var x = 1's32
        while x < transform.oldWidth
        {
            if (x & mask) == 0
            {
                predictorMode   = transform.pixels[transformOffset + 1] & 0x0F
                transformOffset += 4
            }

            switch predictorMode
            {
            case 0:
                losslessAddAt(pixels, offset + 3, 0xFF)

            case 1:
                for [channel] in 4 do
                    losslessAddAt(pixels, offset + channel, data[offset + channel - 4])

            case 2:
                for [channel] in 4 do
                    losslessAddAt(pixels, offset + channel, data[top + channel])

            case 3:
                for [channel] in 4 do
                    losslessAddAt(pixels, offset + channel, data[top + channel + 4])

            case 4:
                for [channel] in 4 do
                    losslessAddAt(pixels, offset + channel, data[top + channel - 4])

            case 5:
                for [channel] in 4
                {
                    let prediction = losslessAverage(losslessAverage(data[offset + channel - 4], data[top + channel + 4]), data[top + channel])
                    losslessAddAt(pixels, offset + channel, prediction)
                }

            case 6:
                for [channel] in 4 do
                    losslessAddAt(pixels, offset + channel, losslessAverage(data[offset + channel - 4], data[top + channel - 4]))

            case 7:
                for [channel] in 4 do
                    losslessAddAt(pixels, offset + channel, losslessAverage(data[offset + channel - 4], data[top + channel]))

            case 8:
                for [channel] in 4 do
                    losslessAddAt(pixels, offset + channel, losslessAverage(data[top + channel - 4], data[top + channel]))

            case 9:
                for [channel] in 4 do
                    losslessAddAt(pixels, offset + channel, losslessAverage(data[top + channel], data[top + channel + 4]))

            case 10:
                for [channel] in 4
                {
                    let leftAverage = losslessAverage(data[offset + channel - 4], data[top + channel - 4])
                    let topAverage  = losslessAverage(data[top + channel], data[top + channel + 4])
                    losslessAddAt(pixels, offset + channel, losslessAverage(leftAverage, topAverage))
                }

            case 11:
                let left0        = cast(s32) data[offset - 4]
                let left1        = cast(s32) data[offset - 3]
                let left2        = cast(s32) data[offset - 2]
                let left3        = cast(s32) data[offset - 1]
                let corner0      = cast(s32) data[top - 4]
                let corner1      = cast(s32) data[top - 3]
                let corner2      = cast(s32) data[top - 2]
                let corner3      = cast(s32) data[top - 1]
                let upper0       = cast(s32) data[top + 0]
                let upper1       = cast(s32) data[top + 1]
                let upper2       = cast(s32) data[top + 2]
                let upper3       = cast(s32) data[top + 3]
                let leftDistance = Math.abs(corner0 - upper0) + Math.abs(corner1 - upper1) + Math.abs(corner2 - upper2) + Math.abs(corner3 - upper3)
                let topDistance  = Math.abs(corner0 - left0) + Math.abs(corner1 - left1) + Math.abs(corner2 - left2) + Math.abs(corner3 - left3)
                if leftDistance < topDistance
                {
                    losslessAddAt(pixels, offset + 0, cast(u8) left0)
                    losslessAddAt(pixels, offset + 1, cast(u8) left1)
                    losslessAddAt(pixels, offset + 2, cast(u8) left2)
                    losslessAddAt(pixels, offset + 3, cast(u8) left3)
                }
                else
                {
                    losslessAddAt(pixels, offset + 0, cast(u8) upper0)
                    losslessAddAt(pixels, offset + 1, cast(u8) upper1)
                    losslessAddAt(pixels, offset + 2, cast(u8) upper2)
                    losslessAddAt(pixels, offset + 3, cast(u8) upper3)
                }

            case 12:
                for [channel] in 4 do
                    losslessAddAt(pixels, offset + channel, losslessClampAddSubtractFull(data[offset + channel - 4], data[top + channel], data[top + channel - 4]))

            case 13:
                for [channel] in 4
                {
                    let average = losslessAverage(data[offset + channel - 4], data[top + channel])
                    losslessAddAt(pixels, offset + channel, losslessClampAddSubtractHalf(average, data[top + channel - 4]))
                }
            }

            offset += 4
            top    += 4
            x      += 1
        }

        y += 1
    }
}

func losslessInverseCrossColor(transform: *LosslessTransform, pixels: *Array'u8, height: s32)
{
    var greenToRed:  s32
    var greenToBlue: s32
    var redToBlue:   s32
    var offset:      u64
    let mask        = cast(s32) (1 << transform.bits) - 1
    let tilesPerRow = losslessTileCount(transform.oldWidth, transform.bits)
    let data        = cast([*] u8) notnull pixels.buffer

    for [y] in height
    {
        var transformOffset = cast(u64) (4 * (y >> transform.bits) * tilesPerRow)
        for [x] in transform.oldWidth
        {
            if (x & mask) == 0
            {
                redToBlue       = cast(s8) transform.pixels[transformOffset + 0]
                greenToBlue     = cast(s8) transform.pixels[transformOffset + 1]
                greenToRed      = cast(s8) transform.pixels[transformOffset + 2]
                transformOffset += 4
            }

            let green = cast(s32) cast(s8) data[offset + 1]
            let red   = cast(s32) data[offset + 0] + ((greenToRed * green) >> 5)
            let blue  = cast(s32) data[offset + 2] + ((greenToBlue * green) >> 5) + ((redToBlue * cast(s32) cast(s8) losslessWrap8(red)) >> 5)
            data[offset + 0] = losslessWrap8(red)
            data[offset + 2] = losslessWrap8(blue)
            offset           += 4
        }
    }
}

func losslessInverseSubtractGreen(pixels: *Array'u8)
{
    let data = cast([*] u8) notnull pixels.buffer
    var offset: u64
    while offset < pixels.count
    {
        let green = data[offset + 1]
        data[offset + 0] = losslessWrap8(cast(s32) data[offset + 0] + green)
        data[offset + 2] = losslessWrap8(cast(s32) data[offset + 2] + green)
        offset           += 4
    }
}

func losslessInverseColorIndexing(transform: *LosslessTransform, pixels: *Array'u8, height: s32)
{
    let data = cast([*] u8) notnull pixels.buffer
    if transform.bits == 0
    {
        var offset: u64
        while offset < pixels.count
        {
            let paletteOffset = cast(u64) 4 * data[offset + 1]
            data[offset + 0] = transform.pixels[paletteOffset + 0]
            data[offset + 1] = transform.pixels[paletteOffset + 1]
            data[offset + 2] = transform.pixels[paletteOffset + 2]
            data[offset + 3] = transform.pixels[paletteOffset + 3]
            offset           += 4
        }

        return
    }

    var valueMask: u32
    var xMask:     s32
    let bitsPerPixel = 8'u32 >> transform.bits
    switch transform.bits
    {
    case 1:
        valueMask = 0x0F
        xMask     = 0x01

    case 2:
        valueMask = 0x03
        xMask     = 0x03

    case 3:
        valueMask = 0x01
        xMask     = 0x07
    }

    var decoded: Array'u8
    decoded.resize(cast(u64) 4 * transform.oldWidth * height)
    var sourceOffset:      u64
    var destinationOffset: u64
    var packedValue:       u32
    for height
    {
        for [x] in transform.oldWidth
        {
            if (x & xMask) == 0
            {
                packedValue  = data[sourceOffset + 1]
                sourceOffset += 4
            }

            let paletteOffset = cast(u64) (4 * (packedValue & valueMask))
            decoded[destinationOffset + 0] = transform.pixels[paletteOffset + 0]
            decoded[destinationOffset + 1] = transform.pixels[paletteOffset + 1]
            decoded[destinationOffset + 2] = transform.pixels[paletteOffset + 2]
            decoded[destinationOffset + 3] = transform.pixels[paletteOffset + 3]
            destinationOffset              += 4
            packedValue                    >>= bitsPerPixel
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
    var reader: LosslessBitReader = undefined
    losslessDecodeHeader(&reader, source, width, height)

    var transforms:     Array'LosslessTransform
    var seenTransforms: [LOSSLESS_TRANSFORM_COUNT] bool
    let originalWidth    = dref width
    var transformedWidth = originalWidth

    while reader.read(1)
    {
        if transforms.count == LOSSLESS_TRANSFORM_COUNT do
            fail InvalidFormatError{"WebP lossless stream contains too many transforms"}

        transforms.resize(transforms.count + 1)
        let transform = &transforms[transforms.count - 1]
        transformedWidth = losslessDecodeTransform(&reader, transform, transformedWidth, dref height)
        if seenTransforms[transform.kind] do
            fail InvalidFormatError{"WebP lossless stream repeats a transform"}
        seenTransforms[transform.kind] = true
    }

    losslessDecodePixels(&reader, pixels, transformedWidth, dref height, 0, true)

    var index = transforms.count
    while index
    {
        index -= 1
        losslessApplyInverseTransform(&transforms[index], pixels, dref height)
    }

    let expectedSize = cast(u64) originalWidth * dref height * 4
    if pixels.count != expectedSize do
        fail InvalidFormatError{"WebP lossless transforms produce a pixel count different from the image dimensions"}
}
