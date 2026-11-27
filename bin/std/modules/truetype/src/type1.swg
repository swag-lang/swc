using Swag, Core

// Encryption constants Type 1 uses for both its private section and its charstrings.
private const EexecC1 = 52845_u32
private const EexecC2 = 22719_u32

// Key the private section is encrypted with, and the one every charstring uses.
private const EexecPrivateKey    = 55665_u16
private const EexecCharstringKey = 4330_u16

// Bytes of random padding the private section prefixes its plaintext with.
private const EexecPrivateSkip = 4_u64

struct Type1Code
{
    offset, length: u64
}

// A parsed Type 1 font program.
//
// Type 1 stores its outlines as encrypted charstrings in a PostScript dictionary keyed by
// glyph name, so a glyph is addressed by name first and by index only as a consequence of
// the order the dictionary was read in.
struct Type1Font
{
    charstrings: Array!{Type1Code}
    subrs:       Array!{Type1Code}
    codeBytes:   Array!{u8}

    // Names point into this immutable decrypted dictionary.
    privateSection: Array!{u8}
    glyphNames:     Array!{string}
    nameToGid:      HashTable!{string, u32}
    codeToGid:      HashTable!{u32, u32}
    unitsPerEm:     u16 = 1000

    // Identity and metrics the cleartext header declares, standing in for the sfnt tables
    // a Type 1 program has none of.
    fontName: String
    xMin:     s16
    yMin:     s16
    xMax:     s16
    yMax:     s16
    italic:   bool
    bold:     bool
}

impl Type1Font
{
    #[Swag.Inline]
    mtd const codeOf(code: Type1Code)->const [..] u8
    {
        if not code.length
        {
            return ""
        }

        return Swag.makeSlice(.codeBytes.storage() + code.offset, code.length)
    }

    mtd storeCode(data: const [..] u8, lenIV: s32)->Type1Code
    {
        let skip = lenIV >= 0 ? cast(u64, lenIV) : 0
        if data.count <= skip
        {
            return {}
        }

        let length = data.count - skip
        let offset = .codeBytes.count
        .codeBytes.reserve(offset + length)
        let target = unwrap .codeBytes.buffer + offset
        if lenIV < 0
        {
            Memory.copy(target, data.buffer, length)
        }
        else
        {
            eexecDecryptInto(target, data, EexecCharstringKey, skip)
        }

        .codeBytes.count = offset + length
        return {offset, length}
    }
}

// Reverses the stream cipher that protects a Type 1 private section or charstring.
func eexecDecrypt(data: const [..] u8, key: u16, skip: u64)->Array!{u8}
{
    var result: #returntype
    if data.count <= skip
    {
        return result
    }

    let size = data.count - skip
    result.reserve(size)
    eexecDecryptInto(unwrap result.buffer, data, key, skip)
    result.count = size
    return result
}

// Generate the eight successive powers of the multiplier modulo 2^16.
private const EexecPowers: [8] u16 = #run
{
    var powers: [8] u16
    var power = 1_u32
    for index in powers.count
    {
        power         = (power * EexecC1) & 0xFFFF
        powers[index] = cast(u16, power)
    }

    return powers
}

#[Swag.Inline]
private func decryptEexecLanes(cipher: Math.Simd.U16x8, state: *u32)->Math.Simd.S16x8
{
    const Powers = cast(Math.Simd.U16x8, EexecPowers)
    let zero = Math.Simd.splat(0_u16)

    // Each byte contributes an affine state update. Combine updates one, two,
    // and four lanes apart to obtain the cumulative state at every position.
    let terms   = cipher * cast(u16, EexecC1) + cast(u16, EexecC2)
    let pairs   = terms + Math.Simd.align(zero, terms, 14) * EexecPowers[0]
    let quads   = pairs + Math.Simd.align(zero, pairs, 12) * EexecPowers[1]
    let octet   = quads + Math.Simd.align(zero, quads, 8) * EexecPowers[3]
    let initial = cast #wrap(u16, state[])
    let next    = octet + Powers * initial
    let prior   = Math.Simd.align(Math.Simd.splat(initial), next, 14)
    state[] = next[7]
    return cast #bit(Math.Simd.S16x8, cipher ^ (prior >> 8))
}

private func eexecDecryptInto(output: [*] u8, data: const [..] u8, key: u16, skip: u64)
{
    // Only bits 8–15 feed the output. Higher bits never feed back into them.
    var state = cast(u32, key)
    var input = data.buffer
    for skip
    {
        state = (cast(u32, input[]) + #wrap state) * #wrap EexecC1 + #wrap EexecC2
        input += 1
    }

    let length = data.count - skip
    var done   = 0_u64
    while length - done >= 16
    {
        let packed = Math.Simd.load(input + done)
        let lo     = decryptEexecLanes(Math.Simd.widenLow(packed), &state)
        let hi     = decryptEexecLanes(Math.Simd.widenHigh(packed), &state)
        Math.Simd.store(output + done, Math.Simd.packUnsigned(lo, hi))
        done += 16
    }

    for index in done until length
    {
        let cipher = input[index]
        output[index] = cipher ^ cast #wrap(u8, state >> 8)
        state         = (cast(u32, cipher) + #wrap state) * #wrap EexecC1 + #wrap EexecC2
    }
}

func findBytes(data: const [..] u8, from: u64, needle: string)->u64
{
    if from >= data.count or not needle.count
    {
        return data.count
    }

    let relative = Slice.findSubslice(data[from to], needle)
    return relative == Swag.U64.Max ? data.count : from + relative
}

private func isPostScriptSpace(c: u8)->bool => c == ' ' or c == '\t' or c == '\r' or c == '\n' or c == '\f' or c == 0

private func isPostScriptDelimiter(c: u8)->bool => isPostScriptSpace(c) or
                                                   c == '/' or
                                                   c == '[' or
                                                   c == ']' or
                                                   c == '{' or
                                                   c == '}' or
                                                   c == '(' or
                                                   c == ')'

private func skipPostScriptSpaces(data: const [..] u8, from: u64)->u64
{
    var pos = from
    while pos < data.count and isPostScriptSpace(data[pos])
    {
        pos += 1
    }

    return pos
}

// Reads the next whitespace-delimited token, without its leading delimiter.
private func readPostScriptToken(data: const [..] u8, from: u64)->{ text: string, next: u64 }
{
    var pos   = skipPostScriptSpaces(data, from)
    let start = pos
    while pos < data.count and not isPostScriptDelimiter(data[pos])
    {
        pos += 1
    }

    return {text: cast(string, data[start until pos]), next: pos}
}

private func readPostScriptNumber(data: const [..] u8, from: u64)->{ value: f64, next: u64 }
{
    var pos = skipPostScriptSpaces(data, from)

    var negative = false
    if pos < data.count and (data[pos] == '-' or data[pos] == '+')
    {
        negative = data[pos] == '-'
        pos      += 1
    }

    var value = 0.0_f64
    while pos < data.count and data[pos] >= '0' and data[pos] <= '9'
    {
        value = value * 10.0 + cast(f64, (data[pos] - '0'))
        pos   += 1
    }

    if pos < data.count and data[pos] == '.'
    {
        pos += 1
        var scale = 0.1_f64
        while pos < data.count and data[pos] >= '0' and data[pos] <= '9'
        {
            value += cast(f64, (data[pos] - '0')) * scale
            scale *= 0.1
            pos   += 1
        }
    }

    return {value: negative ? -value : value, next: pos}
}

// Concatenates the segments of a PFB container, or returns the bytes unchanged.
//
// A PFB file interleaves ASCII and binary segments behind six-byte headers; the font
// program itself is their concatenation.
func unwrapPfb(bytes: const [..] u8)->Array!{u8} fail
{
    var result: #returntype
    if not bytes.count or bytes[0] != 0x80
    {
        result.add(bytes)
        return result
    }

    if bytes.count < 2
    {
        try fault(0x03)
    }

    result.reserve(bytes.count)
    let data = bytes
    var pos  = 0_u64
    while pos < bytes.count
    {
        if pos + 2 > bytes.count or data[pos] != 0x80
        {
            try fault(0x03)
        }

        let kind = data[pos + 1]
        pos += 2
        if kind == 3
        {
            if pos != bytes.count
            {
                try fault(0x03)
            }

            return result
        }

        if kind != 1 and kind != 2
        {
            try fault(0x03)
        }

        if pos + 4 > bytes.count
        {
            try fault(0x03)
        }

        var size = 0_u64
        for k in 4_u64
        {
            size |= cast(u64, data[pos + k]) << (k * 8)
        }

        pos += 4
        if pos + size > bytes.count
        {
            try fault(0x03)
        }

        result.add(try getSlice(bytes, pos, size))
        pos += size
    }

    try fault(0x03)
    return result
}

private const HexDigits: [256] u8 = #run
{
    var digits: [256] u8
    for index in digits.count
    {
        digits[index] = 0xFF
    }

    for value in 10
    {
        digits[cast(u32, '0') + value] = cast(u8, value)
    }

    for value in 6
    {
        digits[cast(u32, 'A') + value] = cast(u8, value + 10)
        digits[cast(u32, 'a') + value] = cast(u8, value + 10)
    }

    return digits
}

// The common PFA line contains adjacent hexadecimal digits. Whitespace and
// unusual tails fall through to the scalar decoder.
#[Swag.Inline]
private func scanHexPairs(input: const [*] u8, output: *Math.Simd.U16x8)->bool
{
    let ascii = Math.Simd.load(input)
    let lower = ascii | 0x20_u8
    let digit = (ascii >= Math.Simd.splat(0x30_u8)) & (ascii <= Math.Simd.splat(0x39_u8))
    let alpha = (lower >= Math.Simd.splat(0x61_u8)) & (lower <= Math.Simd.splat(0x66_u8))
    if Swag.vecMask(digit | alpha) != 0xFFFF
    {
        return false
    }

    const Weights = cast(Math.Simd.S8x16, [16_s8, 1, 16, 1, 16, 1, 16, 1, 16, 1, 16, 1, 16, 1, 16, 1])
    let nibbles = (ascii & 0x0F_u8) + (alpha & 9_u8)
    let pairs   = Math.Simd.mulAddPairs(nibbles, Weights)
    output[] = cast #bit(Math.Simd.U16x8, pairs)
    return true
}

// Recognizes and decrypts the hexadecimal form in one pass over its digits.
private func decryptHexPrivateSection(data: const [..] u8)->{hex: bool, bytes: Array!{u8}}
{
    var prefixEnd = 0_u64
    var digits    = 0_u32
    while prefixEnd < data.count and digits < 4
    {
        let c = data[prefixEnd]
        prefixEnd += 1
        if isPostScriptSpace(c)
        {
            continue
        }

        if HexDigits[c] == 0xFF
        {
            return {false, Array!{u8}{}}
        }

        digits += 1
    }

    if digits < 4
    {
        return {false, Array!{u8}{}}
    }

    let trailer = findBytes(data, 0, "cleartomark")
    if trailer < prefixEnd
    {
        return {false, Array!{u8}{}}
    }

    var result: #returntype
    result.bytes.reserve(data.count / 2)
    let output = unwrap result.bytes.buffer
    var high   = 0_u8
    var have   = false
    var state  = cast(u32, EexecPrivateKey)
    var skip   = EexecPrivateSkip
    var count  = 0_u64
    var source = 0_u64
    var block: Math.Simd.U16x8
    let input  = data.buffer
    while source < data.count
    {
        if not have and
           not skip and
           data.count - source >= 16 and
           scanHexPairs(input + source, &block)
        {
            let plain = decryptEexecLanes(block, &state)
            Math.Simd.storeLow8(output + count, Math.Simd.packUnsigned(plain, plain))

            source += 16
            count  += 8
            continue
        }

        let index = source
        let c     = input[source]
        source += 1
        let value = HexDigits[c]
        if value == 0xFF
        {
            if index < trailer and not isPostScriptSpace(c)
            {
                return {false, Array!{u8}{}}
            }

            continue
        }

        if not have
        {
            high = value
            have = true
            continue
        }

        let cipher = high << 4 | value
        have = false
        if skip
        {
            skip -= 1
        }
        else
        {
            output[count] = cipher ^ cast #wrap(u8, state >> 8)
            count         += 1
        }

        state = (cast(u32, cipher) + #wrap state) * #wrap EexecC1 + #wrap EexecC2
    }

    result.hex         = true
    result.bytes.count = count
    return result
}

// Reads one `<length> RD <bytes>` block, whatever spelling the font gives the operator.
func readCharstringData(data: const [..] u8, from: u64)->{ bytes: const [..] u8, next: u64 } fail
{
    var result: #returntype = {bytes: "", next: data.count}
    let length = readPostScriptNumber(data, from)
    let size   = cast(u64, length.value)
    let token  = readPostScriptToken(data, length.next)
    if not token.text.count
    {
        return result

        // CRLF is one PostScript line separator; preserve any following binary whitespace.
    }

    var start = token.next + 1
    if token.next < data.count and
       data[token.next] == '\r' and
       token.next + 1 < data.count and
       data[token.next + 1] == '\n'
    {
        start += 1
    }

    if start > data.count or size > data.count - start
    {
        return result
    }

    result.bytes = try getSlice(data, start, size)
    result.next  = start + size
    return result
}

private func parseType1Subrs(font: *Type1Font, data: const [..] u8, lenIV: s32) fail
{
    let marker = findBytes(data, 0, "/Subrs")
    if marker >= data.count
    {
        return
    }

    let count = readPostScriptNumber(data, marker + 6)
    let total = cast(u64, count.value)
    if not total or total > 65_536
    {
        return
    }

    font.subrs.resize(total)
    var pos = count.next
    for total
    {
        let dup = findBytes(data, pos, "dup ")
        if dup >= data.count
        {
            return
        }

        let index = readPostScriptNumber(data, dup + 3)
        let entry = try readCharstringData(data, index.next)
        let slot  = cast(u64, index.value)
        if slot < font.subrs.count
        {
            font.subrs[slot] = font.storeCode(entry.bytes, lenIV)
        }

        pos = entry.next
    }
}

// The name every font reserves for the glyph drawn in place of one it does not have.
private const NotDefName = ".notdef"

private func parseType1CharStrings(font: *Type1Font, data: const [..] u8, lenIV: s32) fail
{
    var pos = findBytes(data, 0, "/CharStrings")
    if pos >= data.count
    {
        try fault(0xBA)
    }

    pos += 12

    // A Type 1 dictionary is unordered, so the first glyph it happens to spell out would
    // otherwise take index zero — the index every caller reads as "no such glyph". Holding
    // that index for `.notdef` is what makes an index answer mean what it says.
    font.glyphNames.add(NotDefName)
    font.charstrings.add(Type1Code{})
    font.nameToGid.add(NotDefName, 0)

    // The dictionary body is a run of `/name <length> RD <bytes> ND` entries; `end` closes
    // it. Names are read in file order, which is the order glyph indices follow.
    while pos < data.count
    {
        pos = skipPostScriptSpaces(data, pos)
        if pos >= data.count
        {
            break
        }

        if data[pos] != '/'
        {
            let token = readPostScriptToken(data, pos)
            if not token.text.count
            {
                pos += 1
                continue
            }

            if token.text == "end"
            {
                break
            }

            pos = token.next
            continue
        }

        let name = readPostScriptToken(data, pos + 1)
        if not name.text.count
        {
            pos += 1
            continue
        }

        let entry = try readCharstringData(data, name.next)
        let code  = font.storeCode(entry.bytes, lenIV)
        if not code.length and entry.next >= data.count
        {
            break
        }

        if name.text == NotDefName
        {
            font.charstrings[0] = code
            pos = entry.next
            continue
        }

        font.nameToGid.add(name.text, cast(u32, font.charstrings.count), updateValue: false)
        font.glyphNames.add(name.text)
        font.charstrings.add(code)
        pos = entry.next
    }

    if font.charstrings.count < 2
    {
        try fault(0xBA)
    }
}

private func parseType1Encoding(font: *Type1Font, clear: const [..] u8) fail
{
    let marker = findBytes(clear, 0, "/Encoding")
    if marker >= clear.count
    {
        return
    }

    let token = readPostScriptToken(clear, marker + 9)
    if token.text == "StandardEncoding"
    {
        for code in 256_u32
        {
            let name = standardEncodingName(cast(u8, code))
            if not name.count
            {
                continue
            }

            let found = font.nameToGid.tryFind(name)
            if found
            {
                font.codeToGid[code] = found.value
            }
        }

        return
    }

    // A custom encoding is a run of `dup <code> /<name> put` entries closed by `readonly`
    // or by `def`, whichever the writer emitted.
    var pos = token.next
    while pos < clear.count
    {
        let dup = findBytes(clear, pos, "dup ")
        if dup >= clear.count
        {
            return
        }

        let stop = findBytes(clear, pos, " def")
        if stop < dup
        {
            return
        }

        let code    = readPostScriptNumber(clear, dup + 3)
        var namePos = skipPostScriptSpaces(clear, code.next)
        if namePos >= clear.count or clear[namePos] != '/'
        {
            pos = dup + 4
            continue
        }

        let name  = readPostScriptToken(clear, namePos + 1)
        let found = font.nameToGid.tryFind(name.text)
        if found
        {
            font.codeToGid[cast(u32, code.value)] = found.value
        }

        pos = name.next
    }
}

private func parseType1Header(font: *Type1Font, clear: const [..] u8)
{
    let matrix = findBytes(clear, 0, "/FontMatrix")
    if matrix < clear.count
    {
        let open = findBytes(clear, matrix, "[")
        if open < clear.count
        {
            let scale = readPostScriptNumber(clear, open + 1)
            if scale.value > 0
            {
                let upem = Math.round(1.0 / scale.value)
                if upem >= 16 and upem <= 16_384
                {
                    font.unitsPerEm = cast(u16, upem)
                }
            }
        }
    }

    font.xMax = cast(s16, font.unitsPerEm)
    font.yMax = cast(s16, font.unitsPerEm)

    let bbox = findBytes(clear, 0, "/FontBBox")
    if bbox < clear.count
    {
        var pos = findBytes(clear, bbox, "[")
        if pos < clear.count
        {
            pos += 1
            let xMin = readPostScriptNumber(clear, pos)
            let yMin = readPostScriptNumber(clear, xMin.next)
            let xMax = readPostScriptNumber(clear, yMin.next)
            let yMax = readPostScriptNumber(clear, xMax.next)
            font.xMin = clampToS16(xMin.value)
            font.yMin = clampToS16(yMin.value)
            font.xMax = clampToS16(xMax.value)
            font.yMax = clampToS16(yMax.value)
        }
    }

    let name = findBytes(clear, 0, "/FontName")
    if name < clear.count
    {
        let slash = skipPostScriptSpaces(clear, name + 9)
        if slash < clear.count and clear[slash] == '/'
        {
            font.fontName = String.from(readPostScriptToken(clear, slash + 1).text)
        }
    }

    let italic = findBytes(clear, 0, "/ItalicAngle")
    if italic < clear.count
    {
        font.italic = readPostScriptNumber(clear, italic + 12).value != 0
    }

    let weight = findBytes(clear, 0, "/Weight")
    if weight < clear.count
    {
        let slash = skipPostScriptSpaces(clear, weight + 7)
        if slash < clear.count and (clear[slash] == '(' or clear[slash] == '/')
        {
            font.bold = isBoldWeightName(readPostScriptToken(clear, slash + 1).text)
        }
    }
}

// Reads a complete Type 1 font program, in its PFB, PFA, or bare form.
func parseType1Font(bytes: const [..] u8)->Type1Font fail
{
    var result: #returntype

    var program: Array!{u8}
    var flat = bytes
    if bytes.count and bytes[0] == 0x80
    {
        program = try unwrapPfb(bytes)
        flat    = program.toSlice()
    }

    let marker = findBytes(flat, 0, "eexec")
    if marker >= flat.count
    {
        try fault(0x02)
    }

    let clear   = try getSlice(flat, 0, marker)
    let start   = skipPostScriptSpaces(flat, marker + 5)
    let encoded = try getSlice(flat, start, flat.count - start)
    var hex     = decryptHexPrivateSection(encoded)

    if hex.hex
    {
        result.privateSection = #move hex.bytes
    }
    else
    {
        result.privateSection = eexecDecrypt(encoded, EexecPrivateKey, EexecPrivateSkip)
    }

    let decrypted = result.privateSection.toSlice()
    result.codeBytes.reserve(decrypted.count)

    // Charstrings carry random padding of their own; the private section states how much.
    var lenIV  = 4_s32
    let lenPos = findBytes(decrypted, 0, "/lenIV")
    if lenPos < decrypted.count
    {
        let value = readPostScriptNumber(decrypted, lenPos + 6)
        if value.value == -1 or (value.value >= 0 and value.value <= 255)
        {
            lenIV = cast(s32, value.value)
        }
    }

    try parseType1Subrs(&result, decrypted, lenIV)
    try parseType1CharStrings(&result, decrypted, lenIV)
    try parseType1Encoding(&result, clear)
    parseType1Header(&result, clear)
    return result
}
