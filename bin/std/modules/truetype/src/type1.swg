using Swag, Core

// Encryption constants Type 1 uses for both its private section and its charstrings.
private const EexecC1 = 52845'u32
private const EexecC2 = 22719'u32

// Key the private section is encrypted with, and the one every charstring uses.
private const EexecPrivateKey    = 55665'u16
private const EexecCharstringKey = 4330'u16

// Bytes of random padding the private section prefixes its plaintext with.
private const EexecPrivateSkip = 4'u64

// A parsed Type 1 font program.
//
// Type 1 stores its outlines as encrypted charstrings in a PostScript dictionary keyed by
// glyph name, so a glyph is addressed by name first and by index only as a consequence of
// the order the dictionary was read in.
struct Type1Font
{
    charstrings: Array'(Array'u8)
    subrs:       Array'(Array'u8)
    glyphNames:  Array'String
    nameToGid:   HashTable'(String, u32)
    codeToGid:   HashTable'(u32, u32)
    unitsPerEm:  u16 = 1000

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

// Reverses the stream cipher that protects a Type 1 private section or charstring.
func eexecDecrypt(data: const [..] u8?, key: u16, skip: u64)->Array'u8
{
    var result: retval
    if data.count <= skip do
        return result

    var state = cast(u32) key
    result.reserve(data.count - skip)
    for cipher, index in data
    {
        let plain = cipher ^ cast(u8) (state >> 8)
        state = ((cast(u32) cipher + state) * EexecC1 + EexecC2) & 0xFFFF
        if index >= skip do
            result.add(plain)
    }

    return result
}

func findBytes(data: const [..] u8?, from: u64, needle: string)->u64
{
    let size  = needle.count
    let total = data.count
    if !size or size > total do
        return total

    let bytes = data!
    var start = from
    while start + size <= total
    {
        var found = true
        for k in size where bytes[start + k] != needle[k]
        {
            found = false
            break
        }

        if found do
            return start
        start += 1
    }

    return total
}

private func isPostScriptSpace(c: u8)->bool
{
    return c == ' ' or c == '\t' or c == '\r' or c == '\n' or c == '\f' or c == 0
}

private func isPostScriptDelimiter(c: u8)->bool
{
    return isPostScriptSpace(c) or c == '/' or c == '[' or c == ']' or c == '{' or c == '}' or c == '(' or c == ')'
}

private func skipPostScriptSpaces(data: const [..] u8?, from: u64)->u64
{
    var pos = from
    while pos < data.count and isPostScriptSpace(data![pos]) do
        pos += 1
    return pos
}

// Reads the next whitespace-delimited token, without its leading delimiter.
private func readPostScriptToken(data: const [..] u8?, from: u64)->{ text: string, next: u64 }
{
    var pos   = skipPostScriptSpaces(data, from)
    let start = pos
    while pos < data.count and !isPostScriptDelimiter(data![pos]) do
        pos += 1

    return {cast(string) Swag.makeSlice(data.buffer + start, pos - start), pos}
}

private func readPostScriptNumber(data: const [..] u8?, from: u64)->{ value: f64, next: u64 }
{
    var pos = skipPostScriptSpaces(data, from)

    var negative = false
    if pos < data.count and (data![pos] == '-' or data![pos] == '+')
    {
        negative = data![pos] == '-'
        pos      += 1
    }

    var value = 0.0'f64
    while pos < data.count and data![pos] >= '0' and data![pos] <= '9'
    {
        value = value * 10.0 + cast(f64) (data![pos] - '0')
        pos   += 1
    }

    if pos < data.count and data![pos] == '.'
    {
        pos += 1
        var scale = 0.1'f64
        while pos < data.count and data![pos] >= '0' and data![pos] <= '9'
        {
            value += cast(f64) (data![pos] - '0') * scale
            scale *= 0.1
            pos   += 1
        }
    }

    return {negative ? -value : value, pos}
}

// Concatenates the segments of a PFB container, or returns the bytes unchanged.
//
// A PFB file interleaves ASCII and binary segments behind six-byte headers; the font
// program itself is their concatenation.
private func unwrapPfb(bytes: const [..] u8?)->Array'u8 fail
{
    var result: retval
    if bytes.count < 6 or bytes![0] != 0x80
    {
        result.add(bytes)
        return result
    }

    let data = bytes!
    var pos  = 0'u64
    while pos + 6 <= bytes.count and data[pos] == 0x80
    {
        let kind = data[pos + 1]
        if kind == 3 do
            break

        var size = 0'u64
        for k in 4'u64 do
            size |= cast(u64) data[pos + 2 + k] << (k * 8)
        pos += 6
        if pos + size > bytes.count do
            fault(0x03)
        result.add(getSlice(bytes, pos, size))
        pos += size
    }

    return result
}

// Decodes the hexadecimal spelling a PFA file gives the private section.
private func decodeEexecHex(data: const [..] u8?)->Array'u8
{
    var result: retval
    var high = 0'u8
    var have = false
    for c in data
    {
        var value = 0'u8
        if c >= '0' and c <= '9' do
            value = c - '0'
        elif c >= 'A' and c <= 'F' do
            value = c - 'A' + 10
        elif c >= 'a' and c <= 'f' do
            value = c - 'a' + 10
        else do
            continue

        if have
        {
            result.add(high << 4 | value)
            have = false
        }
        else
        {
            high = value
            have = true
        }
    }

    return result
}

// Answers whether the bytes right after `eexec` spell the private section in hexadecimal.
//
// The binary form starts with four random bytes, so the test is whether the first four
// non-space bytes are all hexadecimal digits — the check the format itself prescribes.
private func isHexPrivateSection(data: const [..] u8?)->bool
{
    var seen = 0'u32
    for c in data
    {
        if isPostScriptSpace(c) do
            continue
        let isHexDigit = (c >= '0' and c <= '9') or (c >= 'A' and c <= 'F') or (c >= 'a' and c <= 'f')
        if !isHexDigit do
            return false
        seen += 1
        if seen == 4 do
            return true
    }

    return false
}

// Reads one `<length> RD <bytes>` block, whatever spelling the font gives the operator.
private func readCharstringData(data: const [..] u8?, from: u64, lenIV: u64)->{ bytes: Array'u8, next: u64 } fail
{
    var result: retval
    let length = readPostScriptNumber(data, from)
    let size   = cast(u64) length.value
    let token  = readPostScriptToken(data, length.next)
    if !token.text.count
    {
        result.next = data.count
        return result
    }

    // Exactly one space separates the operator from the binary that follows it.
    let start = token.next + 1
    if start + size > data.count
    {
        result.next = data.count
        return result
    }

    result.bytes = eexecDecrypt(getSlice(data, start, size), EexecCharstringKey, lenIV)
    result.next  = start + size
    return result
}

private func parseType1Subrs(font: *Type1Font, data: const [..] u8?, lenIV: u64) fail
{
    let marker = findBytes(data, 0, "/Subrs")
    if marker >= data.count do
        return

    let count = readPostScriptNumber(data, marker + 6)
    let total = cast(u64) count.value
    if !total or total > 65_536 do
        return

    font.subrs.resize(total)
    var pos = count.next
    for total
    {
        let dup = findBytes(data, pos, "dup ")
        if dup >= data.count do
            return

        let index = readPostScriptNumber(data, dup + 3)
        let entry = readCharstringData(data, index.next, lenIV)
        let slot  = cast(u64) index.value
        if slot < font.subrs.count do
            font.subrs[slot] = entry.bytes
        pos = entry.next
    }
}

// The name every font reserves for the glyph drawn in place of one it does not have.
private const NotDefName = ".notdef"

private func parseType1CharStrings(font: *Type1Font, data: const [..] u8?, lenIV: u64) fail
{
    var pos = findBytes(data, 0, "/CharStrings")
    if pos >= data.count do
        fault(0xBA)
    pos += 12

    // A Type 1 dictionary is unordered, so the first glyph it happens to spell out would
    // otherwise take index zero — the index every caller reads as "no such glyph". Holding
    // that index for `.notdef` is what makes an index answer mean what it says.
    font.glyphNames.add(String.from(NotDefName))
    font.charstrings.add(Array'u8{})
    font.nameToGid.add(String.from(NotDefName), 0)

    // The dictionary body is a run of `/name <length> RD <bytes> ND` entries; `end` closes
    // it. Names are read in file order, which is the order glyph indices follow.
    while pos < data.count
    {
        pos = skipPostScriptSpaces(data, pos)
        if pos >= data.count do
            break

        if data![pos] != '/'
        {
            let token = readPostScriptToken(data, pos)
            if !token.text.count
            {
                pos += 1
                continue
            }

            if token.text == "end" do
                break
            pos = token.next
            continue
        }

        let name = readPostScriptToken(data, pos + 1)
        if !name.text.count
        {
            pos += 1
            continue
        }

        let entry = readCharstringData(data, name.next, lenIV)
        if entry.bytes.isEmpty() and entry.next >= data.count do
            break

        let owned = String.from(name.text)
        if owned == NotDefName
        {
            font.charstrings[0] = entry.bytes
            pos                 = entry.next
            continue
        }

        if !font.nameToGid.contains(owned) do
            font.nameToGid.add(owned, cast(u32) font.charstrings.count)
        font.glyphNames.add(owned)
        font.charstrings.add(entry.bytes)
        pos = entry.next
    }

    if font.charstrings.count < 2 do
        fault(0xBA)
}

private func parseType1Encoding(font: *Type1Font, clear: const [..] u8?) fail
{
    let marker = findBytes(clear, 0, "/Encoding")
    if marker >= clear.count do
        return

    let token = readPostScriptToken(clear, marker + 9)
    if token.text == "StandardEncoding"
    {
        for code in 256'u32
        {
            let name = standardEncodingName(cast(u8) code)
            if !name.count do
                continue
            let found = font.nameToGid.tryFind(String.from(name))
            if found do
                font.codeToGid[code] = found.value
        }

        return
    }

    // A custom encoding is a run of `dup <code> /<name> put` entries closed by `readonly`
    // or by `def`, whichever the writer emitted.
    var pos = token.next
    while pos < clear.count
    {
        let dup = findBytes(clear, pos, "dup ")
        if dup >= clear.count do
            return

        let stop = findBytes(clear, pos, " def")
        if stop < dup do
            return

        let code    = readPostScriptNumber(clear, dup + 3)
        var namePos = skipPostScriptSpaces(clear, code.next)
        if namePos >= clear.count or clear![namePos] != '/'
        {
            pos = dup + 4
            continue
        }

        let name  = readPostScriptToken(clear, namePos + 1)
        let found = font.nameToGid.tryFind(String.from(name.text))
        if found do
            font.codeToGid[cast(u32) code.value] = found.value
        pos = name.next
    }
}

private func parseType1Header(font: *Type1Font, clear: const [..] u8?)
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
                if upem >= 16 and upem <= 16_384 do
                    font.unitsPerEm = cast(u16) upem
            }
        }
    }

    font.xMax = cast(s16) font.unitsPerEm
    font.yMax = cast(s16) font.unitsPerEm

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
        if slash < clear.count and clear![slash] == '/' do
            font.fontName = String.from(readPostScriptToken(clear, slash + 1).text)
    }

    let italic = findBytes(clear, 0, "/ItalicAngle")
    if italic < clear.count do
        font.italic = readPostScriptNumber(clear, italic + 12).value != 0

    let weight = findBytes(clear, 0, "/Weight")
    if weight < clear.count
    {
        let slash = skipPostScriptSpaces(clear, weight + 7)
        if slash < clear.count and (clear![slash] == '(' or clear![slash] == '/') do
            font.bold = isBoldWeightName(readPostScriptToken(clear, slash + 1).text)
    }
}

// Reads a complete Type 1 font program, in its PFB, PFA, or bare form.
func parseType1Font(bytes: const [..] u8?)->Type1Font fail
{
    var result: retval

    let program = unwrapPfb(bytes)
    let flat    = program.toSlice()
    let marker  = findBytes(flat, 0, "eexec")
    if marker >= flat.count do
        fault(0x02)

    let clear   = getSlice(flat, 0, marker)
    let start   = skipPostScriptSpaces(flat, marker + 5)
    let encoded = getSlice(flat, start, flat.count - start)
    let binary  = isHexPrivateSection(encoded) ? decodeEexecHex(encoded) : Array'u8{}

    var privateSection: Array'u8
    if binary.count do
        privateSection = eexecDecrypt(binary.toSlice(), EexecPrivateKey, EexecPrivateSkip)
    else do
        privateSection = eexecDecrypt(encoded, EexecPrivateKey, EexecPrivateSkip)

    let decrypted = privateSection.toSlice()

    // Charstrings carry random padding of their own; the private section states how much.
    var lenIV  = 4'u64
    let lenPos = findBytes(decrypted, 0, "/lenIV")
    if lenPos < decrypted.count
    {
        let value = readPostScriptNumber(decrypted, lenPos + 6)
        if value.value >= 0 and value.value <= 16 do
            lenIV = cast(u64) value.value
    }

    parseType1Subrs(&result, decrypted, lenIV)
    parseType1CharStrings(&result, decrypted, lenIV)
    parseType1Encoding(&result, clear)
    parseType1Header(&result, clear)
    return result
}
