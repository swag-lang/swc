#global namespace Webp

using Core, Core.Errors

/*
    The VP8 decoder is derived from golang.org/x/image/vp8.
    See webp.LICENSE for the original BSD license.
*/

const VP8_UNIFORM_PROB = 128'u8
const VP8_SEGMENTS     = 4
const VP8_TOKEN_PLANES = 4
const VP8_TOKEN_BANDS  = 8
const VP8_TOKEN_CONTEXTS = 3
const VP8_TOKEN_PROBS    = 11
const VP8_TOKEN_PROB_COUNT = VP8_TOKEN_PLANES * VP8_TOKEN_BANDS * VP8_TOKEN_CONTEXTS * VP8_TOKEN_PROBS

const VP8_LUT_SHIFT: [127] u8 = [
    7, 6, 6, 5, 5, 5, 5, 4, 4, 4, 4, 4, 4, 4, 4,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
]

const VP8_LUT_RANGE_MINUS_ONE: [127] u8 = [
    127,
    127, 191,
    127, 159, 191, 223,
    127, 143, 159, 175, 191, 207, 223, 239,
    127, 135, 143, 151, 159, 167, 175, 183, 191, 199, 207, 215, 223, 231, 239, 247,
    127, 131, 135, 139, 143, 147, 151, 155, 159, 163, 167, 171, 175, 179, 183, 187,
    191, 195, 199, 203, 207, 211, 215, 219, 223, 227, 231, 235, 239, 243, 247, 251,
    127, 129, 131, 133, 135, 137, 139, 141, 143, 145, 147, 149, 151, 153, 155, 157,
    159, 161, 163, 165, 167, 169, 171, 173, 175, 177, 179, 181, 183, 185, 187, 189,
    191, 193, 195, 197, 199, 201, 203, 205, 207, 209, 211, 213, 215, 217, 219, 221,
    223, 225, 227, 229, 231, 233, 235, 237, 239, 241, 243, 245, 247, 249, 251, 253,
]

const VP8_DEQUANT_DC: [128] u16 = [
    4, 5, 6, 7, 8, 9, 10, 10, 11, 12, 13, 14, 15, 16, 17, 17,
    18, 19, 20, 20, 21, 21, 22, 22, 23, 23, 24, 25, 25, 26, 27, 28,
    29, 30, 31, 32, 33, 34, 35, 36, 37, 37, 38, 39, 40, 41, 42, 43,
    44, 45, 46, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58,
    59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74,
    75, 76, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
    91, 93, 95, 96, 98, 100, 101, 102, 104, 106, 108, 110, 112, 114, 116, 118,
    122, 124, 126, 128, 130, 132, 134, 136, 138, 140, 143, 145, 148, 151, 154, 157,
]

const VP8_DEQUANT_AC: [128] u16 = [
    4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
    20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35,
    36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51,
    52, 53, 54, 55, 56, 57, 58, 60, 62, 64, 66, 68, 70, 72, 74, 76,
    78, 80, 82, 84, 86, 88, 90, 92, 94, 96, 98, 100, 102, 104, 106, 108,
    110, 112, 114, 116, 119, 122, 125, 128, 131, 134, 137, 140, 143, 146, 149, 152,
    155, 158, 161, 164, 167, 170, 173, 177, 181, 185, 189, 193, 197, 201, 205, 209,
    213, 217, 221, 225, 229, 234, 239, 245, 249, 254, 259, 264, 269, 274, 279, 284,
]

struct Vp8Partition
{
    data:       #null const [*] u8
    size:       u32
    offset:     u32
    rangeM1:    u32
    bits:       u32
    bitCount:   u8
    unexpectedEnd: bool
}

impl Vp8Partition
{
    mtd init(data: const [*] u8, size: u32)
    {
        .data          = data
        .size          = size
        .offset        = 0
        .rangeM1       = 254
        .bits          = 0
        .bitCount      = 0
        .unexpectedEnd = false
    }

    mtd readBit(probability: u8)->bool
    {
        if .bitCount < 8
        {
            if .offset >= .size
            {
                .unexpectedEnd = true
                return false
            }

            .bits |= cast(u32) (notnull .data)[.offset] << (8 - .bitCount)
            .offset   += 1
            .bitCount += 8
        }

        let split = ((.rangeM1 * probability) >> 8) + 1
        let bit   = .bits >= split << 8
        if bit
        {
            .rangeM1 -= split
            .bits    -= split << 8
        }
        else
        {
            .rangeM1 = split - 1
        }

        if .rangeM1 < 127
        {
            let shift = VP8_LUT_SHIFT[.rangeM1]
            .rangeM1  = VP8_LUT_RANGE_MINUS_ONE[.rangeM1]
            .bits   <<= shift
            .bitCount -= shift
        }
        return bit
    }

    mtd readUint(probability, count: u8)->u32
    {
        var result: retval
        var remaining = count
        while remaining
        {
            remaining -= 1
            if .readBit(probability) do
                result |= 1 << remaining
        }
        return result
    }

    mtd readInt(probability, count: u8)->s32
    {
        let value = cast(s32) .readUint(probability, count)
        return .readBit(probability) ? -value : value
    }

    mtd readOptionalInt(probability, count: u8)->s32
    {
        if !.readBit(probability) do
            return 0
        return .readInt(probability, count)
    }
}

struct Vp8FrameHeader
{
    version:       u8
    firstPartSize: u32
    width:         s32
    height:        s32
}

struct Vp8SegmentHeader
{
    useSegment:     bool
    updateMap:      bool
    relativeDelta:  bool
    quantizer:      [VP8_SEGMENTS] s8
    filterStrength: [VP8_SEGMENTS] s8
    probability:    [3] u8
}

struct Vp8FilterHeader
{
    simple:          bool
    level:           s8
    sharpness:       u8
    useDelta:        bool
    referenceDelta:  [4] s8
    modeDelta:       [4] s8
}

struct Vp8Macroblock
{
    predictor: [4] u8
    nzMask:    u8
    nzY16:     u8
}

struct Vp8Quant
{
    y1: [2] u16
    y2: [2] u16
    uv: [2] u16
}

struct Vp8FilterParam
{
    level:  u8
    iLevel: u8
    hLevel: u8
    inner:  bool
}

struct Vp8Decoder
{
    source: const [*] u8
    size:   u32
    header: Vp8FrameHeader
    mbWidth:  s32
    mbHeight: s32

    segmentHeader: Vp8SegmentHeader
    filterHeader:  Vp8FilterHeader
    firstPart:     Vp8Partition
    otherParts:    [8] Vp8Partition
    otherPartCount: s32
    quant:         [VP8_SEGMENTS] Vp8Quant
    tokenProb:     [VP8_TOKEN_PROB_COUNT] u8
    useSkipProb:   bool
    skipProb:      u8

    filterParams:      [VP8_SEGMENTS][2] Vp8FilterParam
    perMbFilterParams: Array'Vp8FilterParam
    segment:           s32
    leftMb:            Vp8Macroblock
    upMb:              Array'Vp8Macroblock

    nzDcMask: u32
    nzAcMask: u32
    usePredY16: bool
    predY16: u8
    predC8:  u8
    predY4:  [4][4] u8

    coeff: [400] s16
    ybr:   [26][32] u8
    y:     Array'u8
    cb:    Array'u8
    cr:    Array'u8
    yStride: s32
    cStride: s32
}

func vp8Clip(value, minimum, maximum: s32)->s32
{
    return Math.min(Math.max(value, minimum), maximum)
}

func vp8TokenIndex(plane, band: s32, context, probability: u8)->u64
{
    return cast(u64) (((plane * VP8_TOKEN_BANDS + band) * VP8_TOKEN_CONTEXTS + context) * VP8_TOKEN_PROBS + probability)
}

func vp8DecodeFrameHeader(decoder: *Vp8Decoder, source: const [..] u8) fail
{
    if @countof(source) < 10 do
        fail InvalidFormatError{"WebP VP8 data ends before the frame header"}

    decoder.source = @dataof(source)
    decoder.size   = cast(u32) @countof(source)
    let data       = decoder.source
    if data[0] & 1 do
        fail UnsupportedFormatError{"WebP still image contains a non-key VP8 frame"}

    decoder.header.version       = (data[0] >> 1) & 7
    decoder.header.firstPartSize = (cast(u32) data[0] >> 5) | (cast(u32) data[1] << 3) | (cast(u32) data[2] << 11)
    if data[3] != 0x9D or data[4] != 0x01 or data[5] != 0x2A do
        fail InvalidFormatError{"WebP VP8 frame does not start with the key-frame code"}

    decoder.header.width  = data[6] | (cast(s32) (data[7] & 0x3F) << 8)
    decoder.header.height = data[8] | (cast(s32) (data[9] & 0x3F) << 8)
    if decoder.header.width == 0 or decoder.header.height == 0 do
        fail InvalidFormatError{"WebP VP8 frame has an empty image"}
    if cast(u64) decoder.header.width * decoder.header.height > 0x1FFFFFFF do
        fail UnsupportedFormatError{"WebP image needs more than 2 GiB of decoded pixel memory"}
    if decoder.header.firstPartSize > decoder.size - 10 do
        fail InvalidFormatError{"WebP data ends inside the first VP8 partition"}

    decoder.mbWidth  = (decoder.header.width + 15) >> 4
    decoder.mbHeight = (decoder.header.height + 15) >> 4
    decoder.segmentHeader.probability = [0xFF, 0xFF, 0xFF]
    decoder.segment = 0
    for [i] in VP8_TOKEN_PROB_COUNT do
        decoder.tokenProb[i] = VP8_DEFAULT_TOKEN_PROB[i]
}

func vp8ParseSegmentHeader(decoder: *Vp8Decoder)
{
    let part = &decoder.firstPart
    decoder.segmentHeader.useSegment = part.readBit(VP8_UNIFORM_PROB)
    if !decoder.segmentHeader.useSegment
    {
        decoder.segmentHeader.updateMap = false
        return
    }

    decoder.segmentHeader.updateMap = part.readBit(VP8_UNIFORM_PROB)
    if part.readBit(VP8_UNIFORM_PROB)
    {
        decoder.segmentHeader.relativeDelta = !part.readBit(VP8_UNIFORM_PROB)
        for [i] in VP8_SEGMENTS do
            decoder.segmentHeader.quantizer[i] = cast(s8) part.readOptionalInt(VP8_UNIFORM_PROB, 7)
        for [i] in VP8_SEGMENTS do
            decoder.segmentHeader.filterStrength[i] = cast(s8) part.readOptionalInt(VP8_UNIFORM_PROB, 6)
    }

    if !decoder.segmentHeader.updateMap do
        return
    for [i] in 3
    {
        decoder.segmentHeader.probability[i] = part.readBit(VP8_UNIFORM_PROB)
            ? cast(u8) part.readUint(VP8_UNIFORM_PROB, 8)
            : 0xFF
    }
}

func vp8ParseFilterHeader(decoder: *Vp8Decoder)
{
    let part = &decoder.firstPart
    decoder.filterHeader.simple    = part.readBit(VP8_UNIFORM_PROB)
    decoder.filterHeader.level     = cast(s8) part.readUint(VP8_UNIFORM_PROB, 6)
    decoder.filterHeader.sharpness = cast(u8) part.readUint(VP8_UNIFORM_PROB, 3)
    decoder.filterHeader.useDelta  = part.readBit(VP8_UNIFORM_PROB)
    if decoder.filterHeader.useDelta and part.readBit(VP8_UNIFORM_PROB)
    {
        for [i] in 4 do
            decoder.filterHeader.referenceDelta[i] = cast(s8) part.readOptionalInt(VP8_UNIFORM_PROB, 6)
        for [i] in 4 do
            decoder.filterHeader.modeDelta[i] = cast(s8) part.readOptionalInt(VP8_UNIFORM_PROB, 6)
    }
}

func vp8ParseOtherPartitions(decoder: *Vp8Decoder, offset: u32) fail
{
    decoder.otherPartCount = 1 << decoder.firstPart.readUint(VP8_UNIFORM_PROB, 2)
    let lengthBytes = cast(u32) (3 * (decoder.otherPartCount - 1))
    if offset + lengthBytes > decoder.size do
        fail InvalidFormatError{"WebP data ends inside the VP8 partition table"}

    var lengths: [8] u32
    var remaining = decoder.size - offset - lengthBytes
    let lengthData = decoder.source + offset
    for [i] in decoder.otherPartCount - 1
    {
        let length = readU24(lengthData + 3 * i)
        if length > remaining do
            fail InvalidFormatError{"WebP VP8 partition length exceeds the image data"}
        lengths[i] = length
        remaining -= length
    }
    lengths[decoder.otherPartCount - 1] = remaining
    if remaining >= 1 << 24 do
        fail UnsupportedFormatError{"WebP VP8 coefficient partition is too large"}

    var data = lengthData + lengthBytes
    for [i] in decoder.otherPartCount
    {
        decoder.otherParts[i].init(data, lengths[i])
        data += lengths[i]
    }
}

func vp8ParseQuant(decoder: *Vp8Decoder)
{
    let part    = &decoder.firstPart
    let baseQ0  = cast(s32) part.readUint(VP8_UNIFORM_PROB, 7)
    let dY1Dc   = part.readOptionalInt(VP8_UNIFORM_PROB, 4)
    let dY2Dc   = part.readOptionalInt(VP8_UNIFORM_PROB, 4)
    let dY2Ac   = part.readOptionalInt(VP8_UNIFORM_PROB, 4)
    let dUvDc   = part.readOptionalInt(VP8_UNIFORM_PROB, 4)
    let dUvAc   = part.readOptionalInt(VP8_UNIFORM_PROB, 4)

    for [i] in VP8_SEGMENTS
    {
        var q = baseQ0
        if decoder.segmentHeader.useSegment
        {
            q = decoder.segmentHeader.relativeDelta
                ? q + decoder.segmentHeader.quantizer[i]
                : decoder.segmentHeader.quantizer[i]
        }

        let y1Dc = vp8Clip(q + dY1Dc, 0, 127)
        let y1Ac = vp8Clip(q, 0, 127)
        let y2Dc = vp8Clip(q + dY2Dc, 0, 127)
        let y2Ac = vp8Clip(q + dY2Ac, 0, 127)
        let uvDc = vp8Clip(q + dUvDc, 0, 117)
        let uvAc = vp8Clip(q + dUvAc, 0, 127)
        decoder.quant[i].y1[0] = VP8_DEQUANT_DC[y1Dc]
        decoder.quant[i].y1[1] = VP8_DEQUANT_AC[y1Ac]
        decoder.quant[i].y2[0] = VP8_DEQUANT_DC[y2Dc] * 2
        decoder.quant[i].y2[1] = Math.max(cast(u16) 8, cast(u16) (VP8_DEQUANT_AC[y2Ac] * 155 / 100))
        decoder.quant[i].uv[0] = VP8_DEQUANT_DC[uvDc]
        decoder.quant[i].uv[1] = VP8_DEQUANT_AC[uvAc]
    }
}

func vp8ParseTokenProbabilities(decoder: *Vp8Decoder)
{
    for [i] in VP8_TOKEN_PROB_COUNT
    {
        if decoder.firstPart.readBit(VP8_TOKEN_UPDATE_PROB[i]) do
            decoder.tokenProb[i] = cast(u8) decoder.firstPart.readUint(VP8_UNIFORM_PROB, 8)
    }
}

func vp8ParseHeaders(decoder: *Vp8Decoder) fail
{
    let firstOffset = 10'u32
    decoder.firstPart.init(decoder.source + firstOffset, decoder.header.firstPartSize)
    discard decoder.firstPart.readBit(VP8_UNIFORM_PROB)
    discard decoder.firstPart.readBit(VP8_UNIFORM_PROB)
    vp8ParseSegmentHeader(decoder)
    vp8ParseFilterHeader(decoder)
    vp8ComputeFilterParams(decoder)
    vp8ParseOtherPartitions(decoder, firstOffset + decoder.header.firstPartSize)
    vp8ParseQuant(decoder)

    discard decoder.firstPart.readBit(VP8_UNIFORM_PROB)
    vp8ParseTokenProbabilities(decoder)
    decoder.useSkipProb = decoder.firstPart.readBit(VP8_UNIFORM_PROB)
    if decoder.useSkipProb do
        decoder.skipProb = cast(u8) decoder.firstPart.readUint(VP8_UNIFORM_PROB, 8)
    if decoder.firstPart.unexpectedEnd do
        fail InvalidFormatError{"WebP data ends inside the VP8 control partition"}
}

func vp8AllocatePlanes(decoder: *Vp8Decoder)
{
    decoder.yStride = decoder.mbWidth * 16
    decoder.cStride = decoder.mbWidth * 8
    decoder.y.resize(cast(u64) decoder.yStride * decoder.mbHeight * 16)
    decoder.cb.resize(cast(u64) decoder.cStride * decoder.mbHeight * 8)
    decoder.cr.resize(cast(u64) decoder.cStride * decoder.mbHeight * 8)
    decoder.upMb.resize(decoder.mbWidth)
    decoder.perMbFilterParams.resize(cast(u64) decoder.mbWidth * decoder.mbHeight)
}
