using Swag, Core

// Top DICT and Private DICT operators this module reads. The two-byte forms carry
// their escape in the high byte so one number identifies every operator.
const CFF_OP_FONT_BBOX       = 5_u16
const CFF_OP_CHARSET         = 15_u16
const CFF_OP_ENCODING        = 16_u16
const CFF_OP_CHARSTRINGS     = 17_u16
const CFF_OP_PRIVATE         = 18_u16
const CFF_OP_SUBRS           = 19_u16
const CFF_OP_DEFAULT_WIDTH   = 20_u16
const CFF_OP_NOMINAL_WIDTH   = 21_u16
const CFF_OP_ITALIC_ANGLE    = 0x0C02_u16
const CFF_OP_WEIGHT          = 0x0C04_u16
const CFF_OP_CHARSTRING_TYPE = 0x0C06_u16
const CFF_OP_FONT_MATRIX     = 0x0C07_u16
const CFF_OP_ROS             = 0x0C1E_u16
const CFF_OP_FD_ARRAY        = 0x0C24_u16
const CFF_OP_FD_SELECT       = 0x0C25_u16

// Standard SIDs in the predefined Expert and ExpertSubset charsets.
const CffExpertCharset: [166] u16 = [
    0, 1, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 13, 14, 15, 99,
    239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 27, 28, 249, 250, 251, 252,
    253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 109, 110,
    267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282,
    283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298,
    299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314,
    315, 316, 317, 318, 158, 155, 163, 319, 320, 321, 322, 323, 324, 325, 326, 150,
    164, 169, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340,
    341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356,
    357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372,
    373, 374, 375, 376, 377, 378]

const CffExpertSubsetCharset: [87] u16 = [
    0, 1, 231, 232, 235, 236, 237, 238, 13, 14, 15, 99, 239, 240, 241, 242,
    243, 244, 245, 246, 247, 248, 27, 28, 249, 250, 251, 253, 254, 255, 256, 257,
    258, 259, 260, 261, 262, 263, 264, 265, 266, 109, 110, 267, 268, 269, 270, 272,
    300, 301, 302, 305, 314, 315, 158, 155, 163, 320, 321, 322, 323, 324, 325, 326,
    150, 164, 169, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339,
    340, 341, 342, 343, 344, 345, 346]

// Standard SIDs assigned to the 256 codes in the predefined ExpertEncoding.
const CffExpertEncoding: [256] u16 = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 229, 230, 0, 231, 232, 233, 234, 235, 236, 237, 238, 13, 14, 15, 99,
    239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 27, 28, 249, 250, 251, 252,
    0, 253, 254, 255, 256, 257, 0, 0, 0, 258, 0, 0, 259, 260, 261, 262,
    0, 0, 263, 264, 265, 0, 266, 109, 110, 267, 268, 269, 0, 270, 271, 272,
    273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288,
    289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 304, 305, 306, 0, 0, 307, 308, 309, 310, 311, 0, 312, 0, 0, 313,
    0, 0, 314, 315, 0, 0, 316, 317, 318, 0, 0, 0, 158, 155, 163, 319,
    320, 321, 322, 323, 324, 325, 0, 0, 326, 150, 164, 169, 327, 328, 329, 330,
    331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346,
    347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362,
    363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378]

// A CFF INDEX borrows its validated packed offsets and item bytes from the font.
struct CffIndex
{
    late offsets: const [..] u8
    late data:    const [..] u8
    itemCount:    u32
    offsetSize:   u8
    end:          u64     // First byte after the whole structure.
}

impl CffIndex
{
    mtd const count()->u32 => .itemCount

    // Returns one item of the index, or an empty slice for a position it does not hold.
    mtd const item(index: u32)->const [..] u8
    {
        if index >= .itemCount
        {
            return ""
        }

        let entry = .offsets.buffer + cast(u64, index) * .offsetSize
        let from  = readPackedOffset(entry, .offsetSize)
        let stop  = readPackedOffset(entry + .offsetSize, .offsetSize)
        return Swag.makeSlice(.data.buffer + (from - 1), stop - from)
    }
}

// One operator of a CFF DICT with the operands that preceded it.
struct CffDictOp
{
    op:    u16
    first: u32
    count: u32
}

// A parsed CFF DICT: operators in file order over one shared operand pool.
struct CffDict
{
    ops:      Array!{CffDictOp}
    operands: Array!{f64}
}

impl CffDict
{
    // Decodes into the existing buffers so a series of dictionaries can reuse them.
    mtd decode(data: const [..] u8) fail
    {
        .ops.clear()
        .operands.clear()
        var first = 0_u64
        var pos   = 0_u64

        while pos < data.count
        {
            let b0 = peekU8(data, pos)
            if b0 <= 21
            {
                var op = cast(u16, b0)
                pos += 1
                if b0 == 12
                {
                    op  = 0x0C00 | cast(u16, (try readU8(data, pos)))
                    pos += 1
                }

                var entry: CffDictOp
                entry.op    = op
                entry.first = cast(u32, first)
                entry.count = cast(u32, .operands.count - first)
                .ops.add(entry)
                first = .operands.count
                continue
            }

            if b0 == 28
            {
                .operands.add(cast(f64, (try readS16(data, pos + 1))))
                pos += 3
            }
            else if b0 == 29
            {
                .operands.add(cast(f64, (try readS32(data, pos + 1))))
                pos += 5
            }
            else if b0 == 30
            {
                let real = try readCffReal(data, pos + 1)
                .operands.add(real.value)
                pos = real.next
            }
            else if b0 >= 32 and b0 <= 246
            {
                .operands.add(cast(f64, (cast(s32, b0) - 139)))
                pos += 1
            }
            else if b0 >= 247 and b0 <= 250
            {
                let b1 = try readU8(data, pos + 1)
                .operands.add(cast(f64, ((cast(s32, b0) - 247) * 256 + cast(s32, b1) + 108)))
                pos += 2
            }
            else if b0 >= 251 and b0 <= 254
            {
                let b1 = try readU8(data, pos + 1)
                .operands.add(cast(f64, (-(cast(s32, b0) - 251) * 256 - cast(s32, b1) - 108)))
                pos += 2
            }
            else
            {
                try fault(0x08)
            }
        }

        // Operands without a following operator do not belong to the dictionary.
        .operands.resize(first)
    }

    // Returns one operand of an operator, or `fallback` when either is absent.
    mtd const value(op: u16, index: u32, fallback: f64)->f64
    {
        for entry in .ops where entry.op == op
        {
            if index >= entry.count
            {
                return fallback
            }

            return .operands[entry.first + index]
        }

        return fallback
    }

    mtd const has(op: u16)->bool
    {
        for entry in .ops where entry.op == op
        {
            return true
        }

        return false
    }
}

enum CffEncoding
{
    Custom
    Standard
    Expert
}

// Width defaults and local subroutines from one Private DICT.
struct CffPrivate
{
    subrs:        CffIndex
    defaultWidth: f64
    nominalWidth: f64
}

// A parsed CFF font program, from a bare `Type1C` stream or an OpenType `CFF ` table.
//
// Outlines stay in their Type 2 charstring form and are interpreted on demand; only the
// tables needed to address a glyph — by index, by name, by code, or by CID — are expanded.
struct CffFont
{
    late block: const [..] u8     // Borrowed CFF program; the face owns the bytes.

    charStrings: CffIndex
    globalSubrs: CffIndex
    strings:     CffIndex

    glyphNames:    GlyphNames
    encoding:      CffEncoding
    codeToGid:     HashTable!{u32, u32}
    denseCidToGid: Array!{u16}
    cidToGid:      HashTable!{u32, u32}
    cidIsIdentity: bool

    // A CID-keyed font splits its private data across font dictionaries, one selected
    // per glyph, so the subroutines and width defaults are per dictionary rather than
    // per font.
    isCid:          bool
    late fdSelect:  const [..] u8
    fdPrivate:      Array!{CffPrivate}
    defaultPrivate: CffPrivate
    charstringType: u32 = 2
    unitsPerEm:     u16 = 1000

    // Identity and metrics a bare CFF has to supply itself, because it ships without the
    // sfnt tables an OpenType file would state them in.
    fontName: String
    xMin:     s16
    yMin:     s16
    xMax:     s16
    yMax:     s16
    italic:   bool
    bold:     bool
}

impl CffFont
{
    // Returns the local subroutines and width defaults that apply to one glyph.
    mtd const privateFor(gid: u32)->const *CffPrivate
    {
        if not .isCid or .fdPrivate.isEmpty()
        {
            return &.defaultPrivate
        }

        return &.fdPrivate[.dictionaryIndex(gid)]
    }

    // Format 0 indexes directly. In format 3, find the last range start at or before the glyph.
    mtd const dictionaryIndex(gid: u32)->u32
    {
        if not .fdSelect.count or gid >= .charStrings.count()
        {
            return 0
        }

        let data = .fdSelect.buffer
        if data[0] == 0
        {
            return data[1 + gid]
        }

        let ranges = data + 3
        var first  = 0_u32
        var end    = cast(u32, Math.make16(data[1], data[2]))
        while end - first > 1
        {
            let middle = first + (end - first) / 2
            let entry  = ranges + middle * 3
            if Math.make16(entry[0], entry[1]) <= gid
            {
                first = middle
            }
            else
            {
                end = middle
            }
        }

        return ranges[first * 3 + 2]
    }

    mtd glyphIndexByCode(code: u32)->u32
    {
        if code > Swag.U8.Max
        {
            return 0
        }

        switch #complete .encoding
        {
        case .Custom:
            return .codeToGid.getOrDefault(code, 0)

        case .Standard:
            let name = standardEncodingName(cast(u8, code))
            return .glyphNames.glyphIndex(name)

        case .Expert:
            let sid = CffExpertEncoding[code]
            return sid ? .glyphNames.glyphIndex(standardString(sid)) : 0
        }
    }

    mtd const glyphIndexByCid(cid: u32)->u32
    {
        if .cidIsIdentity
        {
            return cid < .charStrings.count() ? cid : 0
        }

        if .denseCidToGid.count
        {
            return cid < .denseCidToGid.count ? .denseCidToGid[cid] : 0
        }

        return .cidToGid.getOrDefault(cid, 0)
    }

    // Returns the name a string identifier selects, from the standard vocabulary or the
    // font's own string INDEX.
    mtd const stringOf(sid: u32)->string fail
    {
        let standard = standardString(sid)
        if standard.count
        {
            return standard
        }

        let customSid = sid - cast(u32, StandardStrings.count)
        if customSid >= .strings.count()
        {
            try fault(0x08)
        }

        let custom = .strings.item(customSid)
        return cast(string?, custom) orelse ""
    }
}

func clampToS16(value: f64)->s16 => cast(s16, Math.clamp(Math.round(value), cast(f64, Swag.S16.Min), cast(f64, Swag.S16.Max)))

// Answers whether a PostScript weight name describes a bold face.
func isBoldWeightName(weight: string)->bool => weight == "Bold" or
                                               weight == "Black" or
                                               weight == "Heavy" or
                                               weight == "Semibold" or
                                               weight == "Demi" or
                                               weight == "DemiBold"

// Returns the offset added to a subroutine number before it indexes the subroutine array.
func subrBias(count: u32)->s32
{
    if count < 1240
    {
        return 107
    }

    if count < 33900
    {
        return 1131
    }

    return 32768
}

func readCffIndex(block: const [..] u8, offset: u64)->CffIndex fail
{
    var result: #returntype
    let count = try readU16(block, offset)
    if not count
    {
        result.end = offset + 2
        return result
    }

    let offSize = try readU8(block, offset + 2)
    if offSize < 1 or offSize > 4
    {
        try fault(0x08)

        // Offsets are one-based. The last offset gives the end of the data and bounds
        // all the preceding items once the offsets have been checked for monotonicity.
    }

    let table     = offset + 3
    let offsets   = try getSlice(block, table, (cast(u64, count) + 1) * offSize)
    let dataStart = table + offsets.count
    if readPackedOffset(offsets.buffer, offSize) != 1
    {
        try fault(0x08)
    }

    var lastOffset: u32
    switch offSize
    {
    case 1:  lastOffset = try validatePackedOffsets!{1}(offsets.buffer, count)
    case 2:  lastOffset = try validatePackedOffsets!{2}(offsets.buffer, count)
    case 3:  lastOffset = try validatePackedOffsets!{3}(offsets.buffer, count)
    default: lastOffset = try validatePackedOffsets!{4}(offsets.buffer, count)
    }

    let dataLength = cast(u64, lastOffset) - 1
    if dataLength > block.count - dataStart or dataStart + dataLength > Swag.U32.Max
    {
        try fault(0x08)
    }

    result.offsets    = offsets
    result.data       = Swag.makeSlice(block.buffer + dataStart, dataLength)
    result.itemCount  = count
    result.offsetSize = offSize
    result.end        = dataStart + dataLength
    return result
}

// Decodes the packed decimal form a DICT stores a real number in.
func readCffReal(data: const [..] u8, offset: u64)->{ value: f64, next: u64 } fail
{
    var result: #returntype

    // Keep f64-significant digits separate from the decimal scale so an exponent can cancel a long fraction.
    var mantissa          = 0.0_f64
    var exponent          = 0
    var decimalExponent   = 0_s64
    var significantDigits = 0_u32
    var negative          = false
    var expNegative       = false
    var inFraction        = false
    var inExponent        = false
    var hasMantissaDigit  = false
    var hasExponentDigit  = false
    var hasDecimalPoint   = false
    var hasSign           = false
    var done              = false
    var pos               = offset

    while not done
    {
        if pos >= data.count
        {
            try fault(0x08)
        }

        let byte = peekU8(data, pos)
        pos += 1
        for half in 2_u32
        {
            let nibble = half == 0 ? byte >> 4 : byte & 0x0F
            if nibble <= 9
            {
                let digit = cast(f64, nibble)
                if inExponent
                {
                    let exponentDigit = cast(s32, nibble)
                    if exponent > (Swag.S32.Max - exponentDigit) / 10
                    {
                        try fault(0x08)
                    }

                    exponent         = exponent * 10 + exponentDigit
                    hasExponentDigit = true
                }
                else if inFraction
                {
                    hasMantissaDigit = true
                    if significantDigits < 17
                    {
                        decimalExponent -= 1
                        if significantDigits or nibble
                        {
                            mantissa = mantissa * 10.0 + digit
                            significantDigits += 1
                        }
                    }
                }
                else
                {
                    hasMantissaDigit = true
                    if significantDigits < 17
                    {
                        if significantDigits or nibble
                        {
                            mantissa = mantissa * 10.0 + digit
                            significantDigits += 1
                        }
                    }
                    else
                    {
                        decimalExponent += 1
                    }
                }
            }
            else if nibble == 0x0A
            {
                if hasDecimalPoint or inExponent
                {
                    try fault(0x08)
                }

                inFraction      = true
                hasDecimalPoint = true
            }
            else if nibble == 0x0B or nibble == 0x0C
            {
                if inExponent or not hasMantissaDigit
                {
                    try fault(0x08)
                }

                inExponent  = true
                expNegative = nibble == 0x0C
            }
            else if nibble == 0x0D
            {
                try fault(0x08)
            }
            else if nibble == 0x0E
            {
                if hasSign or hasMantissaDigit or hasDecimalPoint or inExponent
                {
                    try fault(0x08)
                }

                negative = true
                hasSign  = true
            }
            else if nibble == 0x0F
            {
                if not hasMantissaDigit or (inExponent and not hasExponentDigit)
                {
                    try fault(0x08)
                }

                done = true
                break
            }
        }
    }

    var value = mantissa
    if significantDigits
    {
        if expNegative
        {
            decimalExponent -= cast(s64, exponent)
        }
        else
        {
            decimalExponent += cast(s64, exponent)
        }

        if decimalExponent > 308
        {
            try fault(0x08)
        }
        else if decimalExponent < -341
        {
            value = 0.0
        }
        else
        {
            var remainingExponent = decimalExponent
            while remainingExponent > 0
            {
                let step  = Math.min(cast(s32, remainingExponent), 300)
                let power = Math.pow(10.0_f64, cast(f64, step))
                value *= power
                remainingExponent -= step
            }

            while remainingExponent < 0
            {
                let step  = Math.min(cast(s32, -remainingExponent), 300)
                let power = Math.pow(10.0_f64, cast(f64, step))
                value /= power
                remainingExponent += step
            }
        }
    }

    if not Math.isFinite(value)
    {
        try fault(0x08)
    }

    result.value = negative ? -value : value
    result.next  = pos
    return result
}

func parseCffDict(data: const [..] u8)->CffDict fail
{
    var result: #returntype
    try result.decode(data)
    return result
}

// Reads the private DICT one font dictionary points at, and the local subroutines it owns.
private func readCffPrivate(font: *CffFont, dict: const *CffDict, privateDict: *CffDict)->CffPrivate fail
{
    var result: #returntype
    let size   = cast(u64, dict.value(CFF_OP_PRIVATE, 0, 0))
    let offset = cast(u64, dict.value(CFF_OP_PRIVATE, 1, 0))
    if not size or not offset
    {
        return result
    }

    try privateDict.decode(try getSlice(font.block, offset, size))
    result.defaultWidth = privateDict.value(CFF_OP_DEFAULT_WIDTH, 0, 0)
    result.nominalWidth = privateDict.value(CFF_OP_NOMINAL_WIDTH, 0, 0)

    // The subroutine offset is stated relative to the private DICT, not to the file.
    let subrs = cast(u64, privateDict.value(CFF_OP_SUBRS, 0, 0))
    if subrs
    {
        result.subrs = try readCffIndex(font.block, offset + subrs)
    }

    return result
}

private func readCffCharset(font: *CffFont, offset: u64) fail
{
    let glyphCount = font.charStrings.count()
    if not glyphCount
    {
        try fault(0x08)

        // The predefined identity charset needs no per-glyph storage for a CID font.
    }

    if font.isCid and offset <= 2
    {
        font.cidIsIdentity = true
        return
    }

    var charset: Array!{u32}
    charset.reserve(glyphCount)
    let sids = unwrap charset.buffer
    sids[0] = 0

    if offset == 0
    {
        if glyphCount > 229
        {
            try fault(0x08)
        }

        for gid in 1_u32 until glyphCount
        {
            sids[gid] = gid
        }
    }
    else if offset == 1
    {
        if glyphCount > CffExpertCharset.count
        {
            try fault(0x08)
        }

        for gid in 1_u32 until glyphCount
        {
            sids[gid] = CffExpertCharset[gid]
        }
    }
    else if offset == 2
    {
        if glyphCount > CffExpertSubsetCharset.count
        {
            try fault(0x08)
        }

        for gid in 1_u32 until glyphCount
        {
            sids[gid] = CffExpertSubsetCharset[gid]
        }
    }
    else
    {
        let format = try readU8(font.block, offset)
        var pos    = offset + 1
        if format == 0
        {
            let values = try getSlice(font.block, pos, cast(u64, glyphCount - 1) * 2)
            var entry  = values.buffer
            for gid in 1_u32 until glyphCount
            {
                sids[gid] = Math.make16(entry[0], entry[1])
                entry     += 2
            }
        }
        else if format == 1 or format == 2
        {
            let rangeSize = format == 1 ? 3_u64 : 4_u64
            let source    = font.block
            var gid       = 1_u32
            while gid < glyphCount
            {
                // The format byte and each preceding range were already checked.
                if rangeSize > source.count - pos
                {
                    try fault(0x03)
                }

                let range = source.buffer + pos
                let first = cast(u32, Math.make16(range[0], range[1]))
                let left  = format == 1 ? cast(u32, range[2]) : cast(u32, Math.make16(range[2], range[3]))
                let count = left + 1
                if count > glyphCount - gid
                {
                    try fault(0x08)

                    // A single range from CID 1 through the last glyph is also identity.
                }

                if font.isCid and gid == 1 and first == 1 and count == glyphCount - 1
                {
                    font.cidIsIdentity = true
                    return
                }

                pos += rangeSize
                for offsetInRange in count
                {
                    sids[gid + offsetInRange] = first + cast(u32, offsetInRange)
                }

                gid += count
            }
        }
        else
        {
            try fault(0x08)
        }
    }

    // A CID-keyed font stores character identifiers where a plain font stores names, so
    // the same table answers two different questions depending on the font's kind.
    if font.isCid
    {
        var largest     = 0_u32
        var differences = 0_u32
        for gid in glyphCount
        {
            let cid = sids[gid]
            differences |= cid ^ gid
            largest     = Math.max(largest, cid)
        }

        font.cidIsIdentity = differences == 0
        if font.cidIsIdentity
        {
            return

            // At this density a table of 16-bit glyph indices uses no more than
            // eight bytes per glyph. Dispersed CIDs use the sparse index instead.
        }

        if largest < glyphCount * 4
        {
            font.denseCidToGid.resize(largest + 1)
            let glyphs = font.denseCidToGid.storage()
            for gid in glyphCount
            {
                glyphs[sids[gid]] = cast(u16, gid)
            }
        }
        else
        {
            for gid in glyphCount
            {
                font.cidToGid[sids[gid]] = gid
            }
        }

        return
    }

    font.glyphNames.entries.reserve(glyphCount)
    let names = unwrap font.glyphNames.entries.buffer
    for gid in glyphCount
    {
        names[gid] = try font.stringOf(sids[gid])
    }

    font.glyphNames.entries.count = glyphCount
}

private func readCffEncoding(font: *CffFont, offset: u64) fail
{
    if font.isCid
    {
        return

        // Predefined encodings resolve through the charset on demand.
    }

    if offset <= 1
    {
        font.encoding = offset == 0 ? .Standard : .Expert
        return
    }

    let format = try readU8(font.block, offset)
    var pos    = offset + 1
    if (format & 0x7F) == 0
    {
        let count = try readU8(font.block, pos)
        pos += 1
        if cast(u32, count) + 1 > font.charStrings.count()
        {
            try fault(0x08)
        }

        for i in count
        {
            font.codeToGid[cast(u32, try readU8(font.block, pos))] = cast(u32, i) + 1
            pos += 1
        }
    }
    else if (format & 0x7F) == 1
    {
        let ranges = try readU8(font.block, pos)
        pos += 1
        var gid = 1_u32
        for ranges
        {
            let first = cast(u32, try readU8(font.block, pos))
            let left  = cast(u32, try readU8(font.block, pos + 1))
            if first + left > Swag.U8.Max
            {
                try fault(0x08)
            }

            pos += 2
            for k in left + 1
            {
                if gid >= font.charStrings.count()
                {
                    try fault(0x08)
                }

                font.codeToGid[first + cast(u32, k)] = gid
                gid += 1
            }
        }
    }
    else
    {
        try fault(0x08)
    }

    if (format & 0x80) != 0
    {
        let supplements = try readU8(font.block, pos)
        if supplements
        {
            font.glyphNames.buildIndex()
        }

        pos += 1
        for supplements
        {
            let code = cast(u32, try readU8(font.block, pos))
            let sid  = cast(u32, try readU16(font.block, pos + 1))
            pos += 3
            let found = font.glyphNames.byName.tryFind(try font.stringOf(sid))
            if found
            {
                font.codeToGid[code] = found.value
            }
        }
    }
}

// Keeps the validated FDSelect table in the owned font buffer.
private func readCffFdSelect(font: const *CffFont, offset: u64)->const [..] u8 fail
{
    let glyphCount = font.charStrings.count()
    let fdCount    = font.fdPrivate.count
    let format     = try readU8(font.block, offset)
    if format == 0
    {
        let table = try getSlice(font.block, offset, 1_u64 + glyphCount)
        for fd in table[1 to] where fd >= fdCount
        {
            try fault(0x08)
        }

        return table
    }

    if format != 3
    {
        try fault(0x08)
    }

    let count = try readU16(font.block, offset + 1)
    if not count
    {
        try fault(0x08)
    }

    let table = try getSlice(font.block, offset, 5_u64 + cast(u64, count) * 3)
    var range = table.buffer + 3
    var start = cast(u32, Math.make16(range[0], range[1]))
    if start
    {
        try fault(0x08)
    }

    for count
    {
        let end = cast(u32, Math.make16(range[3], range[4]))
        if end <= start or end > glyphCount or range[2] >= fdCount
        {
            try fault(0x08)
        }

        start = end
        range += 3
    }

    if start != glyphCount
    {
        try fault(0x08)
    }

    return table
}

private func readCffFdArray(font: *CffFont, offset: u64, privateDict: *CffDict) fail
{
    let fdArray = try readCffIndex(font.block, offset)
    font.fdPrivate.reserve(fdArray.count())

    var dict: CffDict
    for index in fdArray.count()
    {
        try dict.decode(fdArray.item(index))
        font.fdPrivate.add(try readCffPrivate(font, &dict, privateDict))
    }
}

// Reads a complete CFF program into the form the charstring interpreter addresses.
func parseCffFont(block: const [..] u8)->CffFont fail
{
    var result: #returntype
    result.block = block

    let headerSize = cast(u64, peekU8(block, 2))
    if headerSize < 4
    {
        try fault(0x08)
    }

    let names   = try readCffIndex(block, headerSize)
    let topDict = try readCffIndex(block, names.end)
    result.strings     = try readCffIndex(block, topDict.end)
    result.globalSubrs = try readCffIndex(block, result.strings.end)
    if not topDict.count()
    {
        try fault(0x08)
    }

    let top = try parseCffDict(topDict.item(0))
    result.isCid = top.has(CFF_OP_ROS)
    result.charstringType = cast(u32, top.value(CFF_OP_CHARSTRING_TYPE, 0, 2))
    if result.charstringType != 2
    {
        try fault(0x07)

        // The font matrix scales charstring units to the em square; its reciprocal is the
        // units-per-em the rest of the module measures a design in.
    }

    let matrixScale = top.value(CFF_OP_FONT_MATRIX, 0, 0.001)
    if matrixScale > 0
    {
        let upem = Math.round(1.0 / matrixScale)
        if upem >= 16 and upem <= 16_384
        {
            result.unitsPerEm = cast(u16, upem)
        }
    }

    let charStrings = cast(u64, top.value(CFF_OP_CHARSTRINGS, 0, 0))
    if not charStrings
    {
        try fault(0x08)
    }

    result.charStrings = try readCffIndex(block, charStrings)

    result.fontName = String.from(cast(string?, names.item(0)))
    result.xMin     = clampToS16(top.value(CFF_OP_FONT_BBOX, 0, 0))
    result.yMin     = clampToS16(top.value(CFF_OP_FONT_BBOX, 1, 0))
    result.xMax     = clampToS16(top.value(CFF_OP_FONT_BBOX, 2, cast(f64, result.unitsPerEm)))
    result.yMax     = clampToS16(top.value(CFF_OP_FONT_BBOX, 3, cast(f64, result.unitsPerEm)))
    result.italic   = top.value(CFF_OP_ITALIC_ANGLE, 0, 0) != 0
    result.bold     = isBoldWeightName(try result.stringOf(cast(u32, top.value(CFF_OP_WEIGHT, 0, 0))))

    var privateDict: CffDict
    result.defaultPrivate = try readCffPrivate(&result, &top, &privateDict)

    if result.isCid
    {
        let fdArray = cast(u64, top.value(CFF_OP_FD_ARRAY, 0, 0))
        if fdArray
        {
            try readCffFdArray(&result, fdArray, &privateDict)
        }

        let fdSelect = cast(u64, top.value(CFF_OP_FD_SELECT, 0, 0))
        if fdSelect
        {
            result.fdSelect = try readCffFdSelect(&result, fdSelect)
        }
    }

    try readCffCharset(&result, cast(u64, top.value(CFF_OP_CHARSET, 0, 0)))
    try readCffEncoding(&result, cast(u64, top.value(CFF_OP_ENCODING, 0, 0)))
    return result
}
