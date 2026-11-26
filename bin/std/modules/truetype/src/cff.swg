using Swag, Core

// Top DICT and Private DICT operators this module reads. The two-byte forms carry
// their escape in the high byte so one number identifies every operator.
const CFF_OP_FONT_BBOX       = 5'u16
const CFF_OP_CHARSET         = 15'u16
const CFF_OP_ENCODING        = 16'u16
const CFF_OP_CHARSTRINGS     = 17'u16
const CFF_OP_PRIVATE         = 18'u16
const CFF_OP_SUBRS           = 19'u16
const CFF_OP_DEFAULT_WIDTH   = 20'u16
const CFF_OP_NOMINAL_WIDTH   = 21'u16
const CFF_OP_ITALIC_ANGLE    = 0x0C02'u16
const CFF_OP_WEIGHT          = 0x0C04'u16
const CFF_OP_CHARSTRING_TYPE = 0x0C06'u16
const CFF_OP_FONT_MATRIX     = 0x0C07'u16
const CFF_OP_ROS             = 0x0C1E'u16
const CFF_OP_FD_ARRAY        = 0x0C24'u16
const CFF_OP_FD_SELECT       = 0x0C25'u16

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
        if index >= .itemCount do
            return ""

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
    ops:      Array'CffDictOp
    operands: Array'f64
}

impl CffDict
{
    // Returns one operand of an operator, or `fallback` when either is absent.
    mtd const value(op: u16, index: u32, fallback: f64)->f64
    {
        for entry in .ops where entry.op == op
        {
            if index >= entry.count do
                return fallback
            return .operands[entry.first + index]
        }

        return fallback
    }

    mtd const has(op: u16)->bool
    {
        for entry in .ops where entry.op == op do
            return true
        return false
    }
}

enum CffEncoding
{
    Custom
    Standard
    Expert
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
    localSubrs:  CffIndex
    strings:     CffIndex

    glyphNames:    GlyphNames
    encoding:      CffEncoding
    codeToGid:     HashTable'(u32, u32)
    cidToGid:      HashTable'(u32, u32)
    cidIsIdentity: bool

    // A CID-keyed font splits its private data across font dictionaries, one selected
    // per glyph, so the subroutines and width defaults are per dictionary rather than
    // per font.
    isCid:          bool
    fdSelect:       Array'u8
    fdLocalSubrs:   Array'CffIndex
    fdDefaultWidth: Array'f64
    fdNominalWidth: Array'f64

    defaultWidthX:  f64
    nominalWidthX:  f64
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
    mtd const privateFor(gid: u32)->{ subrs: const *CffIndex, defaultWidth: f64, nominalWidth: f64 }
    {
        if not .isCid or .fdLocalSubrs.isEmpty() do
            return {subrs: &.localSubrs, defaultWidth: .defaultWidthX, nominalWidth: .nominalWidthX}

        var fd = 0'u32
        if gid < .fdSelect.count do
            fd = .fdSelect[gid]
        if fd >= .fdLocalSubrs.count do
            fd = 0

        return {subrs: &.fdLocalSubrs[fd], defaultWidth: .fdDefaultWidth[fd], nominalWidth: .fdNominalWidth[fd]}
    }

    mtd glyphIndexByCode(code: u32)->u32
    {
        if code > Swag.U8.Max do
            return 0

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
        if .cidIsIdentity do
            return cid < .charStrings.count() ? cid : 0
        return .cidToGid.getOrDefault(cid, 0)
    }

    // Returns the name a string identifier selects, from the standard vocabulary or the
    // font's own string INDEX.
    mtd const stringOf(sid: u32)->string fail
    {
        let standard = standardString(sid)
        if standard.count do
            return standard

        let customSid = sid - cast(u32, StandardStrings.count)
        if customSid >= .strings.count() do
            try fault(0x08)
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
    if count < 1240 do
        return 107
    if count < 33900 do
        return 1131
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
    if offSize < 1 or offSize > 4 do
        try fault(0x08)

    // Offsets are one-based. The last offset gives the end of the data and bounds
    // all the preceding items once the offsets have been checked for monotonicity.
    let table     = offset + 3
    let offsets   = try getSlice(block, table, (cast(u64, count) + 1) * offSize)
    let dataStart = table + offsets.count
    if readPackedOffset(offsets.buffer, offSize) != 1 do
        try fault(0x08)

    var lastOffset: u32
    switch offSize
    {
    case 1:  lastOffset = try validatePackedOffsets'1(offsets.buffer, count)
    case 2:  lastOffset = try validatePackedOffsets'2(offsets.buffer, count)
    case 3:  lastOffset = try validatePackedOffsets'3(offsets.buffer, count)
    default: lastOffset = try validatePackedOffsets'4(offsets.buffer, count)
    }

    let dataLength = cast(u64, lastOffset) - 1
    if dataLength > block.count - dataStart or dataStart + dataLength > Swag.U32.Max do
        try fault(0x08)

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
    var mantissa          = 0.0'f64
    var exponent          = 0
    var decimalExponent   = 0's64
    var significantDigits = 0'u32
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
        if pos >= data.count do
            try fault(0x08)
        let byte = peekU8(data, pos)
        pos += 1
        for half in 2'u32
        {
            let nibble = half == 0 ? byte >> 4 : byte & 0x0F
            if nibble <= 9
            {
                let digit = cast(f64, nibble)
                if inExponent
                {
                    let exponentDigit = cast(s32, nibble)
                    if exponent > (Swag.S32.Max - exponentDigit) / 10 do
                        try fault(0x08)
                    exponent         = exponent * 10 + exponentDigit
                    hasExponentDigit = true
                }
                elif inFraction
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
            elif nibble == 0x0A
            {
                if hasDecimalPoint or inExponent do
                    try fault(0x08)
                inFraction      = true
                hasDecimalPoint = true
            }
            elif nibble == 0x0B or nibble == 0x0C
            {
                if inExponent or not hasMantissaDigit do
                    try fault(0x08)
                inExponent  = true
                expNegative = nibble == 0x0C
            }
            elif nibble == 0x0D
            {
                try fault(0x08)
            }
            elif nibble == 0x0E
            {
                if hasSign or hasMantissaDigit or hasDecimalPoint or inExponent do
                    try fault(0x08)
                negative = true
                hasSign  = true
            }
            elif nibble == 0x0F
            {
                if not hasMantissaDigit or (inExponent and not hasExponentDigit) do
                    try fault(0x08)
                done = true
                break
            }
        }
    }

    var value = mantissa
    if significantDigits
    {
        if expNegative do
            decimalExponent -= cast(s64, exponent)
        else do
            decimalExponent += cast(s64, exponent)

        if decimalExponent > 308
        {
            try fault(0x08)
        }
        elif decimalExponent < -341
        {
            value = 0.0
        }
        else
        {
            var remainingExponent = decimalExponent
            while remainingExponent > 0
            {
                let step  = Math.min(cast(s32, remainingExponent), 300)
                let power = Math.pow(10.0'f64, cast(f64, step))
                value *= power
                remainingExponent -= step
            }

            while remainingExponent < 0
            {
                let step  = Math.min(cast(s32, -remainingExponent), 300)
                let power = Math.pow(10.0'f64, cast(f64, step))
                value /= power
                remainingExponent += step
            }
        }
    }

    if not Math.isFinite(value) do
        try fault(0x08)

    result.value = negative ? -value : value
    result.next  = pos
    return result
}

func parseCffDict(data: const [..] u8)->CffDict fail
{
    var result:  #returntype
    var pending: Array'f64
    var pos = 0'u64

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
            entry.first = cast(u32, result.operands.count)
            entry.count = cast(u32, pending.count)
            result.operands.add(pending.toSlice())
            result.ops.add(entry)
            pending.clear()
            continue
        }

        if b0 == 28
        {
            pending.add(cast(f64, (try readS16(data, pos + 1))))
            pos += 3
        }
        elif b0 == 29
        {
            pending.add(cast(f64, (try readS32(data, pos + 1))))
            pos += 5
        }
        elif b0 == 30
        {
            let real = try readCffReal(data, pos + 1)
            pending.add(real.value)
            pos = real.next
        }
        elif b0 >= 32 and b0 <= 246
        {
            pending.add(cast(f64, (cast(s32, b0) - 139)))
            pos += 1
        }
        elif b0 >= 247 and b0 <= 250
        {
            let b1 = try readU8(data, pos + 1)
            pending.add(cast(f64, ((cast(s32, b0) - 247) * 256 + cast(s32, b1) + 108)))
            pos += 2
        }
        elif b0 >= 251 and b0 <= 254
        {
            let b1 = try readU8(data, pos + 1)
            pending.add(cast(f64, (-(cast(s32, b0) - 251) * 256 - cast(s32, b1) - 108)))
            pos += 2
        }
        else
        {
            try fault(0x08)
        }
    }

    return result
}

// Reads the private DICT one font dictionary points at, and the local subroutines it owns.
private func readCffPrivate(font: *CffFont, dict: const *CffDict)->{ subrs: CffIndex, defaultWidth: f64, nominalWidth: f64 } fail
{
    var result: #returntype
    let size   = cast(u64, dict.value(CFF_OP_PRIVATE, 0, 0))
    let offset = cast(u64, dict.value(CFF_OP_PRIVATE, 1, 0))
    if not size or not offset do
        return result

    let priv = try parseCffDict(try getSlice(font.block, offset, size))
    result.defaultWidth = priv.value(CFF_OP_DEFAULT_WIDTH, 0, 0)
    result.nominalWidth = priv.value(CFF_OP_NOMINAL_WIDTH, 0, 0)

    // The subroutine offset is stated relative to the private DICT, not to the file.
    let subrs = cast(u64, priv.value(CFF_OP_SUBRS, 0, 0))
    if subrs do
        result.subrs = try readCffIndex(font.block, offset + subrs)
    return result
}

private func readCffCharset(font: *CffFont, offset: u64) fail
{
    let glyphCount = font.charStrings.count()
    if not glyphCount do
        try fault(0x08)

    // The predefined identity charset needs no per-glyph storage for a CID font.
    if font.isCid and offset <= 2
    {
        font.cidIsIdentity = true
        return
    }

    var charset: Array'u32
    charset.reserve(glyphCount)
    let sids = unwrap charset.buffer
    sids[0] = 0

    if offset == 0
    {
        if glyphCount > 229 do
            try fault(0x08)
        for gid in 1'u32 until glyphCount do
            sids[gid] = gid
    }
    elif offset == 1
    {
        if glyphCount > CffExpertCharset.count do
            try fault(0x08)
        for gid in 1'u32 until glyphCount do
            sids[gid] = CffExpertCharset[gid]
    }
    elif offset == 2
    {
        if glyphCount > CffExpertSubsetCharset.count do
            try fault(0x08)
        for gid in 1'u32 until glyphCount do
            sids[gid] = CffExpertSubsetCharset[gid]
    }
    else
    {
        let format = try readU8(font.block, offset)
        var pos    = offset + 1
        if format == 0
        {
            let values = try getSlice(font.block, pos, cast(u64, glyphCount - 1) * 2)
            var entry  = values.buffer
            for gid in 1'u32 until glyphCount
            {
                sids[gid] = Math.make16(entry[0], entry[1])
                entry     += 2
            }
        }
        elif format == 1 or format == 2
        {
            let leftSize = format == 1 ? 1'u64 : 2'u64
            var gid      = 1'u32
            while gid < glyphCount
            {
                let first = cast(u32, try readU16(font.block, pos))
                let left  = format == 1 ? cast(u32, try readU8(font.block, pos + 2)) : cast(u32, try readU16(font.block, pos + 2))
                let count = left + 1
                if count > glyphCount - gid do
                    try fault(0x08)

                // A single range from CID 1 through the last glyph is also identity.
                if font.isCid and gid == 1 and first == 1 and count == glyphCount - 1
                {
                    font.cidIsIdentity = true
                    return
                }

                pos += 2 + leftSize
                for offsetInRange in count do
                    sids[gid + offsetInRange] = first + cast(u32, offsetInRange)
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
        font.cidIsIdentity = true
        for gid in glyphCount where sids[gid] != gid
        {
            font.cidIsIdentity = false
            break
        }

        if not font.cidIsIdentity
        {
            for gid in glyphCount do
                font.cidToGid[sids[gid]] = gid
        }

        return
    }

    font.glyphNames.entries.reserve(glyphCount)
    let names = unwrap font.glyphNames.entries.buffer
    for gid in glyphCount do
        names[gid] = try font.stringOf(sids[gid])
    font.glyphNames.entries.count = glyphCount
}

private func readCffEncoding(font: *CffFont, offset: u64) fail
{
    if font.isCid do
        return

    // Predefined encodings resolve through the charset on demand.
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
        if cast(u32, count) + 1 > font.charStrings.count() do
            try fault(0x08)
        for i in count
        {
            font.codeToGid[cast(u32, try readU8(font.block, pos))] = cast(u32, i) + 1
            pos += 1
        }
    }
    elif (format & 0x7F) == 1
    {
        let ranges = try readU8(font.block, pos)
        pos += 1
        var gid = 1'u32
        for ranges
        {
            let first = cast(u32, try readU8(font.block, pos))
            let left  = cast(u32, try readU8(font.block, pos + 1))
            if first + left > Swag.U8.Max do
                try fault(0x08)
            pos += 2
            for k in left + 1
            {
                if gid >= font.charStrings.count() do
                    try fault(0x08)
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
        if supplements do
            font.glyphNames.buildIndex()
        pos += 1
        for supplements
        {
            let code = cast(u32, try readU8(font.block, pos))
            let sid  = cast(u32, try readU16(font.block, pos + 1))
            pos += 3
            let found = font.glyphNames.byName.tryFind(try font.stringOf(sid))
            if found do
                font.codeToGid[code] = found.value
        }
    }
}

private func readCffFdSelect(font: *CffFont, offset: u64) fail
{
    let glyphCount = font.charStrings.count()
    font.fdSelect.resize(glyphCount)

    let format = try readU8(font.block, offset)
    if format == 0
    {
        for gid in glyphCount
        {
            let fd = try readU8(font.block, offset + 1 + gid)
            if fd >= font.fdLocalSubrs.count do
                try fault(0x08)
            font.fdSelect[gid] = fd
        }

        return
    }

    if format != 3 do
        try fault(0x08)

    let ranges     = try readU16(font.block, offset + 1)
    var pos        = offset + 3
    var sentinel   = 0'u32
    var firstRange = true
    for ranges
    {
        let first = cast(u32, try readU16(font.block, pos))
        let fd    = try readU8(font.block, pos + 2)
        let next  = cast(u32, try readU16(font.block, pos + 3))
        if next <= first or next > glyphCount do
            try fault(0x08)
        if firstRange and first != 0 do
            try fault(0x08)
        if fd >= font.fdLocalSubrs.count do
            try fault(0x08)
        sentinel   = next
        firstRange = false
        pos        += 3
        Memory.set(unwrap font.fdSelect.buffer + first, fd, next - first)
    }

    if sentinel != glyphCount do
        try fault(0x08)
}

private func readCffFdArray(font: *CffFont, offset: u64) fail
{
    let fdArray = try readCffIndex(font.block, offset)
    for index in fdArray.count()
    {
        let dict        = try parseCffDict(fdArray.item(index))
        let privateData = try readCffPrivate(font, &dict)
        font.fdLocalSubrs.add(privateData.subrs)
        font.fdDefaultWidth.add(privateData.defaultWidth)
        font.fdNominalWidth.add(privateData.nominalWidth)
    }
}

// Reads a complete CFF program into the form the charstring interpreter addresses.
func parseCffFont(block: const [..] u8)->CffFont fail
{
    var result: #returntype
    result.block = block

    let headerSize = cast(u64, peekU8(block, 2))
    if headerSize < 4 do
        try fault(0x08)

    let names   = try readCffIndex(block, headerSize)
    let topDict = try readCffIndex(block, names.end)
    result.strings     = try readCffIndex(block, topDict.end)
    result.globalSubrs = try readCffIndex(block, result.strings.end)
    if not topDict.count() do
        try fault(0x08)

    let top = try parseCffDict(topDict.item(0))
    result.isCid = top.has(CFF_OP_ROS)
    result.charstringType = cast(u32, top.value(CFF_OP_CHARSTRING_TYPE, 0, 2))
    if result.charstringType != 2 do
        try fault(0x07)

    // The font matrix scales charstring units to the em square; its reciprocal is the
    // units-per-em the rest of the module measures a design in.
    let matrixScale = top.value(CFF_OP_FONT_MATRIX, 0, 0.001)
    if matrixScale > 0
    {
        let upem = Math.round(1.0 / matrixScale)
        if upem >= 16 and upem <= 16_384 do
            result.unitsPerEm = cast(u16, upem)
    }

    let charStrings = cast(u64, top.value(CFF_OP_CHARSTRINGS, 0, 0))
    if not charStrings do
        try fault(0x08)
    result.charStrings = try readCffIndex(block, charStrings)

    result.fontName = String.from(cast(string?, names.item(0)))
    result.xMin     = clampToS16(top.value(CFF_OP_FONT_BBOX, 0, 0))
    result.yMin     = clampToS16(top.value(CFF_OP_FONT_BBOX, 1, 0))
    result.xMax     = clampToS16(top.value(CFF_OP_FONT_BBOX, 2, cast(f64, result.unitsPerEm)))
    result.yMax     = clampToS16(top.value(CFF_OP_FONT_BBOX, 3, cast(f64, result.unitsPerEm)))
    result.italic   = top.value(CFF_OP_ITALIC_ANGLE, 0, 0) != 0
    result.bold     = isBoldWeightName(try result.stringOf(cast(u32, top.value(CFF_OP_WEIGHT, 0, 0))))

    let privateData = try readCffPrivate(&result, &top)
    result.localSubrs    = privateData.subrs
    result.defaultWidthX = privateData.defaultWidth
    result.nominalWidthX = privateData.nominalWidth

    if result.isCid
    {
        let fdArray = cast(u64, top.value(CFF_OP_FD_ARRAY, 0, 0))
        if fdArray do
            try readCffFdArray(&result, fdArray)
        let fdSelect = cast(u64, top.value(CFF_OP_FD_SELECT, 0, 0))
        if fdSelect do
            try readCffFdSelect(&result, fdSelect)
    }

    try readCffCharset(&result, cast(u64, top.value(CFF_OP_CHARSET, 0, 0)))
    try readCffEncoding(&result, cast(u64, top.value(CFF_OP_ENCODING, 0, 0)))
    return result
}
