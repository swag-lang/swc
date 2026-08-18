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

// One CFF INDEX: a counted array of byte strings addressed through an offset table.
struct CffIndex
{
    starts: Array'u32     // Absolute offset of every item, plus the end of the last one.
    end:    u64           // First byte after the whole structure.
}

impl CffIndex
{
    mtd const count()->u32 => .starts.count ? cast(u32) (.starts.count - 1) : 0

    // Returns one item of the index, or an empty slice for a position it does not hold.
    mtd const item(block: #null const [..] u8, index: u32)->#null const [..] u8 fail
    {
        if cast(u64) index + 1 >= .starts.count do
            return null
        let from = .starts[index]
        let stop = .starts[index + 1]
        if stop < from do
            fault(0x08)
        return getSlice(block, from, stop - from)
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

// A parsed CFF font program, from a bare `Type1C` stream or an OpenType `CFF ` table.
//
// Outlines stay in their Type 2 charstring form and are interpreted on demand; only the
// tables needed to address a glyph — by index, by name, by code, or by CID — are expanded.
struct CffFont
{
    block: #null const [..] u8     // Borrowed CFF program; the face owns the bytes.

    charStrings: CffIndex
    globalSubrs: CffIndex
    localSubrs:  CffIndex
    strings:     CffIndex

    glyphNames: Array'String
    nameToGid:  HashTable'(String, u32)
    codeToGid:  HashTable'(u32, u32)
    cidToGid:   HashTable'(u32, u32)

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
        if !.isCid or .fdLocalSubrs.isEmpty() do
            return {&.localSubrs, .defaultWidthX, .nominalWidthX}

        var fd = 0'u32
        if gid < .fdSelect.count do
            fd = .fdSelect[gid]
        if fd >= .fdLocalSubrs.count do
            fd = 0

        return {&.fdLocalSubrs[fd], .fdDefaultWidth[fd], .fdNominalWidth[fd]}
    }

    // Returns the name a string identifier selects, from the standard vocabulary or the
    // font's own string INDEX.
    mtd const stringOf(sid: u32)->String fail
    {
        let standard = standardString(sid)
        if @countof(standard) do
            return String.from(standard)

        let custom = .strings.item(.block, sid - cast(u32) @countof(StandardStrings))
        return String.from(cast(#null string) custom)
    }
}

func clampToS16(value: f64)->s16
{
    return cast(s16) Math.clamp(Math.round(value), cast(f64) Swag.S16.Min, cast(f64) Swag.S16.Max)
}

// Answers whether a PostScript weight name describes a bold face.
func isBoldWeightName(weight: string)->bool
{
    return weight == "Bold" or weight == "Black" or weight == "Heavy" or weight == "Semibold" or weight == "Demi" or weight == "DemiBold"
}

// Returns the offset added to a subroutine number before it indexes the subroutine array.
func subrBias(count: u32)->s32
{
    if count < 1240 do
        return 107
    if count < 33900 do
        return 1131
    return 32768
}

func readCffIndex(block: #null const [..] u8, offset: u64)->CffIndex fail
{
    var result: retval
    let count = readU16(block, offset)
    if !count
    {
        result.end = offset + 2
        return result
    }

    let offSize = readU8(block, offset + 2)
    if offSize < 1 or offSize > 4 do
        fault(0x08)

    // Item offsets are one-based and relative to the byte before the data block, which
    // is what makes the first item start exactly where the offset table ends.
    let table    = offset + 3
    let dataBase = table + cast(u64) (count + 1) * offSize - 1

    result.starts.reserve(cast(u64) count + 1)
    for i in cast(u64) count + 1
    {
        var value = 0'u32
        for b in cast(u64) offSize do
            value = value << 8 | readU8(block, table + i * offSize + b)
        result.starts.add(cast(u32) (dataBase + value))
    }

    result.end = result.starts.back()
    if result.end > @countof(block) do
        fault(0x08)
    return result
}

// Decodes the packed decimal form a DICT stores a real number in.
func readCffReal(data: #null const [..] u8, offset: u64)->{ value: f64, next: u64 } fail
{
    var result: retval
    var mantissa    = 0.0'f64
    var fraction    = 0.1'f64
    var exponent    = 0
    var negative    = false
    var expNegative = false
    var inFraction  = false
    var inExponent  = false
    var done        = false
    var pos         = offset

    while !done
    {
        let byte = readU8(data, pos)
        pos += 1
        for half in 2'u32
        {
            let nibble = half == 0 ? byte >> 4 : byte & 0x0F
            if nibble <= 9
            {
                let digit = cast(f64) nibble
                if inExponent do
                    exponent = exponent * 10 + cast(s32) nibble
                elif inFraction
                {
                    mantissa += digit * fraction
                    fraction *= 0.1
                }
                else
                {
                    mantissa = mantissa * 10.0 + digit
                }
            }
            elif nibble == 0x0A
            {
                inFraction = true
            }
            elif nibble == 0x0B
            {
                inExponent = true
            }
            elif nibble == 0x0C
            {
                inExponent  = true
                expNegative = true
            }
            elif nibble == 0x0E
            {
                negative = true
            }
            elif nibble == 0x0F
            {
                done = true
                break
            }
        }
    }

    var value = mantissa
    if exponent
    {
        let power = Math.pow(10.0'f64, cast(f64) exponent)
        value = expNegative ? value / power : value * power
    }

    result.value = negative ? -value : value
    result.next  = pos
    return result
}

func parseCffDict(data: #null const [..] u8)->CffDict fail
{
    var result:  retval
    var pending: Array'f64
    var pos = 0'u64

    while pos < @countof(data)
    {
        let b0 = readU8(data, pos)
        if b0 <= 21
        {
            var op = cast(u16) b0
            pos += 1
            if b0 == 12
            {
                op  = 0x0C00 | cast(u16) readU8(data, pos)
                pos += 1
            }

            var entry: CffDictOp
            entry.op    = op
            entry.first = cast(u32) result.operands.count
            entry.count = cast(u32) pending.count
            result.operands.add(pending.toSlice())
            result.ops.add(entry)
            pending.clear()
            continue
        }

        if b0 == 28
        {
            pending.add(cast(f64) readS16(data, pos + 1))
            pos += 3
        }
        elif b0 == 29
        {
            pending.add(cast(f64) readS32(data!, pos + 1))
            pos += 5
        }
        elif b0 == 30
        {
            let real = readCffReal(data, pos + 1)
            pending.add(real.value)
            pos = real.next
        }
        elif b0 >= 32 and b0 <= 246
        {
            pending.add(cast(f64) (cast(s32) b0 - 139))
            pos += 1
        }
        elif b0 >= 247 and b0 <= 250
        {
            let b1 = readU8(data, pos + 1)
            pending.add(cast(f64) ((cast(s32) b0 - 247) * 256 + cast(s32) b1 + 108))
            pos += 2
        }
        elif b0 >= 251 and b0 <= 254
        {
            let b1 = readU8(data, pos + 1)
            pending.add(cast(f64) (-(cast(s32) b0 - 251) * 256 - cast(s32) b1 - 108))
            pos += 2
        }
        else
        {
            fault(0x08)
        }
    }

    return result
}

// Reads the private DICT one font dictionary points at, and the local subroutines it owns.
private func readCffPrivate(font: *CffFont, dict: const *CffDict)->{ subrs: CffIndex, defaultWidth: f64, nominalWidth: f64 } fail
{
    var result: retval
    let size   = cast(u64) dict.value(CFF_OP_PRIVATE, 0, 0)
    let offset = cast(u64) dict.value(CFF_OP_PRIVATE, 1, 0)
    if !size or !offset do
        return result

    let priv = parseCffDict(getSlice(font.block, offset, size))
    result.defaultWidth = priv.value(CFF_OP_DEFAULT_WIDTH, 0, 0)
    result.nominalWidth = priv.value(CFF_OP_NOMINAL_WIDTH, 0, 0)

    // The subroutine offset is stated relative to the private DICT, not to the file.
    let subrs = cast(u64) priv.value(CFF_OP_SUBRS, 0, 0)
    if subrs do
        result.subrs = readCffIndex(font.block, offset + subrs)
    return result
}

private func readCffCharset(font: *CffFont, offset: u64) fail
{
    let glyphCount = font.charStrings.count()
    var sids: Array'u32
    sids.reserve(glyphCount)
    sids.add(0)

    // The predefined charsets name glyphs by their position in the standard vocabulary,
    // which is exactly what an identity mapping produces for the ISOAdobe set.
    if offset <= 2
    {
        for gid in 1'u32 until glyphCount do
            sids.add(gid)
    }
    else
    {
        let format = readU8(font.block, offset)
        var pos    = offset + 1
        if format == 0
        {
            while sids.count < glyphCount
            {
                sids.add(readU16(font.block, pos))
                pos += 2
            }
        }
        elif format == 1 or format == 2
        {
            let leftSize = format == 1 ? 1'u64 : 2'u64
            while sids.count < glyphCount
            {
                let first = cast(u32) readU16(font.block, pos)
                let left  = format == 1 ? cast(u32) readU8(font.block, pos + 2) : cast(u32) readU16(font.block, pos + 2)
                pos += 2 + leftSize
                for offsetInRange in left + 1
                {
                    if sids.count >= glyphCount do
                        break
                    sids.add(first + cast(u32) offsetInRange)
                }
            }
        }
        else
        {
            fault(0x08)
        }
    }

    // A CID-keyed font stores character identifiers where a plain font stores names, so
    // the same table answers two different questions depending on the font's kind.
    if font.isCid
    {
        for sid, gid in sids do
            font.cidToGid[sid] = cast(u32) gid
        return
    }

    font.glyphNames.reserve(sids.count)
    for sid, gid in sids
    {
        let name = font.stringOf(sid)
        if name.length and !font.nameToGid.contains(name) do
            font.nameToGid.add(name, cast(u32) gid)
        font.glyphNames.add(name)
    }
}

private func readCffEncoding(font: *CffFont, offset: u64) fail
{
    if font.isCid do
        return

    // The predefined encodings are named by their glyphs, so they resolve through the
    // charset that was just read rather than through a table of their own.
    if offset <= 1
    {
        for code in 256'u32
        {
            let name = standardEncodingName(cast(u8) code)
            if !@countof(name) do
                continue
            let found = font.nameToGid.tryFind(String.from(name))
            if found do
                font.codeToGid[code] = found.value
        }

        return
    }

    let format = readU8(font.block, offset)
    var pos    = offset + 1
    if (format & 0x7F) == 0
    {
        let count = readU8(font.block, pos)
        pos += 1
        for i in count
        {
            font.codeToGid[cast(u32) readU8(font.block, pos)] = cast(u32) i + 1
            pos += 1
        }
    }
    elif (format & 0x7F) == 1
    {
        let ranges = readU8(font.block, pos)
        pos += 1
        var gid = 1'u32
        for ranges
        {
            let first = cast(u32) readU8(font.block, pos)
            let left  = cast(u32) readU8(font.block, pos + 1)
            pos += 2
            for k in left + 1
            {
                font.codeToGid[first + cast(u32) k] = gid
                gid += 1
            }
        }
    }
    else
    {
        fault(0x08)
    }

    if (format & 0x80) != 0
    {
        let supplements = readU8(font.block, pos)
        pos += 1
        for supplements
        {
            let code = cast(u32) readU8(font.block, pos)
            let sid  = cast(u32) readU16(font.block, pos + 1)
            pos += 3
            let found = font.nameToGid.tryFind(font.stringOf(sid))
            if found do
                font.codeToGid[code] = found.value
        }
    }
}

private func readCffFdSelect(font: *CffFont, offset: u64) fail
{
    let glyphCount = font.charStrings.count()
    font.fdSelect.resize(glyphCount)

    let format = readU8(font.block, offset)
    if format == 0
    {
        for gid in glyphCount do
            font.fdSelect[gid] = readU8(font.block, offset + 1 + gid)
        return
    }

    if format != 3 do
        fault(0x08)

    let ranges = readU16(font.block, offset + 1)
    var pos    = offset + 3
    for ranges
    {
        let first = cast(u32) readU16(font.block, pos)
        let fd    = readU8(font.block, pos + 2)
        let next  = cast(u32) readU16(font.block, pos + 3)
        pos += 3
        for gid in first until Math.min(next, glyphCount) do
            font.fdSelect[gid] = fd
    }
}

private func readCffFdArray(font: *CffFont, offset: u64) fail
{
    let fdArray = readCffIndex(font.block, offset)
    for index in fdArray.count()
    {
        let dict        = parseCffDict(fdArray.item(font.block, index))
        let privateData = readCffPrivate(font, &dict)
        font.fdLocalSubrs.add(privateData.subrs)
        font.fdDefaultWidth.add(privateData.defaultWidth)
        font.fdNominalWidth.add(privateData.nominalWidth)
    }
}

// Reads a complete CFF program into the form the charstring interpreter addresses.
func parseCffFont(block: #null const [..] u8)->CffFont fail
{
    var result: retval
    result.block = block

    let headerSize = cast(u64) readU8(block, 2)
    if headerSize < 4 do
        fault(0x08)

    let names   = readCffIndex(block, headerSize)
    let topDict = readCffIndex(block, names.end)
    result.strings     = readCffIndex(block, topDict.end)
    result.globalSubrs = readCffIndex(block, result.strings.end)
    if !topDict.count() do
        fault(0x08)

    let top = parseCffDict(topDict.item(block, 0))
    result.isCid          = top.has(CFF_OP_ROS)
    result.charstringType = cast(u32) top.value(CFF_OP_CHARSTRING_TYPE, 0, 2)
    if result.charstringType != 2 do
        fault(0x07)

    // The font matrix scales charstring units to the em square; its reciprocal is the
    // units-per-em the rest of the module measures a design in.
    let matrixScale = top.value(CFF_OP_FONT_MATRIX, 0, 0.001)
    if matrixScale > 0
    {
        let upem = Math.round(1.0 / matrixScale)
        if upem >= 16 and upem <= 16_384 do
            result.unitsPerEm = cast(u16) upem
    }

    let charStrings = cast(u64) top.value(CFF_OP_CHARSTRINGS, 0, 0)
    if !charStrings do
        fault(0x08)
    result.charStrings = readCffIndex(block, charStrings)

    result.fontName = String.from(cast(#null string) names.item(block, 0))
    result.xMin     = clampToS16(top.value(CFF_OP_FONT_BBOX, 0, 0))
    result.yMin     = clampToS16(top.value(CFF_OP_FONT_BBOX, 1, 0))
    result.xMax     = clampToS16(top.value(CFF_OP_FONT_BBOX, 2, cast(f64) result.unitsPerEm))
    result.yMax     = clampToS16(top.value(CFF_OP_FONT_BBOX, 3, cast(f64) result.unitsPerEm))
    result.italic   = top.value(CFF_OP_ITALIC_ANGLE, 0, 0) != 0
    result.bold     = isBoldWeightName(result.stringOf(cast(u32) top.value(CFF_OP_WEIGHT, 0, 0)).toString())

    let privateData = readCffPrivate(&result, &top)
    result.localSubrs    = privateData.subrs
    result.defaultWidthX = privateData.defaultWidth
    result.nominalWidthX = privateData.nominalWidth

    if result.isCid
    {
        let fdArray = cast(u64) top.value(CFF_OP_FD_ARRAY, 0, 0)
        if fdArray do
            readCffFdArray(&result, fdArray)
        let fdSelect = cast(u64) top.value(CFF_OP_FD_SELECT, 0, 0)
        if fdSelect do
            readCffFdSelect(&result, fdSelect)
    }

    readCffCharset(&result, cast(u64) top.value(CFF_OP_CHARSET, 0, 0))
    readCffEncoding(&result, cast(u64) top.value(CFF_OP_ENCODING, 0, 0))
    return result
}
