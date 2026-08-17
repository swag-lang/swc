using Core, Core.Math

// A font a decoded page refers to, with everything needed to lay its text out again.
//
// The type identity is part of the exported page layout, so it is public, but it carries
// no public contract of its own.
#[Swag.NoDoc]
public struct FontResource
{
    objectId: u32
    name:     String
    baseName: String
    bytes:    Array'u8

    // Code to text, from a `/ToUnicode` CMap, and code to character from the font's simple
    // encoding. The CMap wins when both describe a code.
    unicode:  HashTable'(u32, String)
    encoding: HashTable'(u32, rune)

    // Advance widths in fractions of the text size, as `/Widths` or `/W` declares them.
    widths: HashTable'(u32, f32)

    defaultWidth: f32          = 0.5
    codeBytes:    u32          = 1
    standard:     StandardFont = StandardFont.Helvetica
    hasStandard:  bool
    baseEncoding: BaseEncoding = BaseEncoding.WinAnsi
}

impl FontResource
{
    // Returns the advance width of one character code, in fractions of the text size.
    mtd const codeWidth(code: u32)->f32
    {
        let entry = .widths.tryFind(code)
        if entry do
            return entry.value
        if .hasStandard and .codeBytes == 1
        {
            let value = .runeOf(code)
            if value do
                return .standard.glyphWidth(value)
        }

        return .defaultWidth
    }

    // Returns the character a code stands for, or zero when nothing maps it.
    mtd const runeOf(code: u32)->rune
    {
        let mapped = .encoding.tryFind(code)
        if mapped do
            return mapped.value
        if .codeBytes == 1 do
            return encodingRune(.baseEncoding, cast(u8) code)
        return 0
    }

    // Converts one PDF string into UTF-8 text.
    mtd const decodeText(bytes: string)->String
    {
        var result: retval
        let size = Math.max(.codeBytes, 1)
        var pos  = 0'u64
        while pos + size <= @countof(bytes)
        {
            var code = 0'u32
            for i in size do
                code = code << 8 | bytes[pos + i]
            pos += size

            let mapped = .unicode.tryFind(code)
            if mapped
            {
                result += mapped.value
                continue
            }

            let value = .runeOf(code)
            if value do
                result.append(value)
        }

        return result
    }

    // Returns how far the text position moves after one shown string, in text-space units.
    //
    // Horizontal scaling is applied by the caller because it also scales the offsets a `TJ`
    // array contributes.
    mtd const runAdvance(bytes: string, fontSize, charSpacing, wordSpacing: f32)->f32
    {
        var result = 0.0'f32
        let size   = Math.max(.codeBytes, 1)
        var pos    = 0'u64
        while pos + size <= @countof(bytes)
        {
            var code = 0'u32
            for i in size do
                code = code << 8 | bytes[pos + i]
            pos += size

            result += .codeWidth(code) * fontSize + charSpacing

            // Word spacing applies to the single-byte code 32 only, whatever glyph it maps to.
            if size == 1 and code == 32 do
                result += wordSpacing
        }

        return result
    }
}

// Reads one font dictionary into the resource a decoded page keeps.
internal func decodeFontResource(parser: *PdfParser, fontId: u32, name: string)->FontResource fail
{
    var result: retval
    result.objectId = fontId
    result.name     = name
    result.baseName = parser.name(parser.dict(fontId, "BaseFont"))

    let match = StandardFont.fromBaseName(result.baseName.toString())
    result.standard    = match.font
    result.hasStandard = match.found

    // A composite font keeps its metrics and its descriptor one level down, in the single
    // descendant CIDFont, and addresses glyphs with two-byte codes.
    var metrics = fontId
    if parser.name(parser.dict(fontId, "Subtype")) == "Type0"
    {
        result.codeBytes    = 2
        result.defaultWidth = 1
        let descendants = parser.dict(fontId, "DescendantFonts")
        if descendants != InvalidNode and parser.nodes[descendants].kind == .Array and parser.nodes[descendants].values.count
        {
            let cid = parser.resolve(parser.nodes[descendants].values[0])
            if cid != InvalidNode
            {
                metrics             = cid
                result.defaultWidth = cast(f32) parser.number(parser.dict(cid, "DW"), 1000.0) / 1000.0
                readCidWidths(parser, &result, parser.dict(cid, "W"))
            }
        }
    }

    readEncoding(parser, &result, parser.dictRaw(fontId, "Encoding"))
    readSimpleWidths(parser, &result, metrics)

    let descriptor = parser.dict(metrics, "FontDescriptor")
    if descriptor != InvalidNode
    {
        let missing = parser.dict(descriptor, "MissingWidth")
        if missing != InvalidNode do
            result.defaultWidth = cast(f32) parser.number(missing) / 1000.0

        // Only the TrueType-shaped programs can be handed to the rasterizer; the others
        // leave the resource without bytes and fall back to a substitute face.
        let file2 = parser.dict(descriptor, "FontFile2")
        if file2 != InvalidNode do
            result.bytes = try parser.decodeStream(file2)
        else
        {
            let file3 = parser.dict(descriptor, "FontFile3")
            if file3 != InvalidNode and parser.name(parser.dict(file3, "Subtype")) == "OpenType" do
                result.bytes = try parser.decodeStream(file3)
        }
    }

    let toUnicode = parser.dict(fontId, "ToUnicode")
    if toUnicode != InvalidNode
    {
        let cmap = try parser.decodeStream(toUnicode)
        readToUnicode(&result, cmap.toSlice())
    }

    return result
}

private func readSimpleWidths(parser: const *PdfParser, font: *FontResource, metricsId: u32)
{
    let firstChar = parser.integer(parser.dict(metricsId, "FirstChar"), -1)
    let widthsId  = parser.dict(metricsId, "Widths")
    if firstChar < 0 or widthsId == InvalidNode or parser.nodes[widthsId].kind != .Array do
        return
    for value, index in parser.nodes[widthsId].values do
        font.widths[cast(u32) firstChar + cast(u32) index] = cast(f32) parser.number(value) / 1000.0
}

// Reads the `/W` array of a CIDFont, which alternates between a list form and a range form.
private func readCidWidths(parser: const *PdfParser, font: *FontResource, widthsId: u32)
{
    if widthsId == InvalidNode or parser.nodes[widthsId].kind != .Array do
        return
    let values = parser.nodes[widthsId].values
    var index  = 0'u64
    while index < @countof(values)
    {
        let first = parser.integer(values[index])
        index += 1
        if index >= @countof(values) or first < 0 do
            return

        let listId = parser.resolve(values[index])
        if listId != InvalidNode and parser.nodes[listId].kind == .Array
        {
            for value, offset in parser.nodes[listId].values do
                font.widths[cast(u32) first + cast(u32) offset] = cast(f32) parser.number(value) / 1000.0
            index += 1
            continue
        }

        let last = parser.integer(values[index])
        index += 1
        if index >= @countof(values) or last < first or last - first > 65_535 do
            return
        let width = cast(f32) parser.number(values[index]) / 1000.0
        index += 1
        for code in cast(u32) first to cast(u32) last do
            font.widths[code] = width
    }
}

private func readEncoding(parser: const *PdfParser, font: *FontResource, encodingRaw: u32)
{
    let encodingId = parser.resolve(encodingRaw)
    if encodingId == InvalidNode do
        return

    if parser.nodes[encodingId].kind == .Name
    {
        applyBaseEncoding(font, parser.nodes[encodingId].text.toString())
        return
    }

    if parser.nodes[encodingId].kind != .Dictionary do
        return
    let baseName = parser.name(parser.dict(encodingId, "BaseEncoding"))
    if @countof(baseName) do
        applyBaseEncoding(font, baseName)

    // `/Differences` alternates a starting code with the glyph names that follow it.
    let differencesId = parser.dict(encodingId, "Differences")
    if differencesId == InvalidNode or parser.nodes[differencesId].kind != .Array do
        return
    var code = 0'u32
    for value in parser.nodes[differencesId].values
    {
        let id = parser.resolve(value)
        if id == InvalidNode do
            continue
        if parser.nodes[id].kind == .Integer
        {
            let start = parser.nodes[id].integer
            if start >= 0 and start <= Swag.U16.Max do
                code = cast(u32) start
            continue
        }

        if parser.nodes[id].kind != .Name do
            continue
        let glyph = glyphNameRune(parser.nodes[id].text.toString())
        if glyph do
            font.encoding[code] = glyph
        code += 1
    }
}

private func applyBaseEncoding(font: *FontResource, name: string)
{
    switch name
    {
    case "WinAnsiEncoding":          font.baseEncoding = .WinAnsi
    case "MacRomanEncoding":         font.baseEncoding = .MacRoman
    case "StandardEncoding", "PDFDocEncoding", "MacExpertEncoding": font.baseEncoding = .Standard
    case "Identity-H", "Identity-V": font.codeBytes = 2
    }
}

// Sections of a `/ToUnicode` CMap this reader understands.
private enum CMapSection
{
    None
    CodeSpace
    Char
    Range
}

// Reads a `/ToUnicode` CMap.
//
// Only the sections that describe a code-to-text mapping are interpreted; the PostScript
// scaffolding around them is skipped as unknown words.
private func readToUnicode(font: *FontResource, bytes: const [..] u8)
{
    var scanner = PdfParser{bytes: bytes}
    var pending: Array'u32
    var section = CMapSection.None
    while scanner.pos < @countof(bytes)
    {
        scanner.skip()
        if scanner.pos >= @countof(bytes) do
            break

        // The PostScript scaffolding around the mapping sections carries dictionaries and
        // strings of its own, so anything that does not parse is stepped over rather than
        // ending the scan.
        if scanner.startsWith("<<") or scanner.startsWith(">>")
        {
            scanner.pos += 2
            continue
        }

        let mark = scanner.pos
        let c    = bytes[mark]
        if c == '<'
        {
            let id = catch scanner.parseHexString() as hexError
            if hexError != null do
                scanner.pos = mark + 1
            else do
                pending.add(id)
            continue
        }

        if c == '['
        {
            let id = catch scanner.parseArray() as arrayError
            if arrayError != null do
                scanner.pos = mark + 1
            else do
                pending.add(id)
            continue
        }

        if isDelimiter(c)
        {
            scanner.pos += 1
            continue
        }

        let start = scanner.pos
        while scanner.pos < @countof(bytes) and !isDelimiter(bytes[scanner.pos]) do
            scanner.pos += 1
        let word = cast(string) @mkslice(@dataof(bytes) + start, scanner.pos - start)
        switch word
        {
        case "begincodespacerange":
            pending.clear()
            section = .CodeSpace

        case "beginbfchar":
            pending.clear()
            section = .Char

        case "beginbfrange":
            pending.clear()
            section = .Range

        case "endcodespacerange":
            if section == .CodeSpace and pending.count >= 2
            {
                let low = scanner.nodes[pending[0]].text.length
                if low == 1 or low == 2 do
                    font.codeBytes = cast(u32) low
            }

            pending.clear()
            section = .None

        case "endbfchar":
            if section == .Char do
                applyCMapChars(font, &scanner, pending.toSlice())
            pending.clear()
            section = .None

        case "endbfrange":
            if section == .Range do
                applyCMapRanges(font, &scanner, pending.toSlice())
            pending.clear()
            section = .None
        }
    }
}

private func applyCMapChars(font: *FontResource, scanner: const *PdfParser, pending: const [..] u32)
{
    for i in @countof(pending) / 2
    {
        let source = &scanner.nodes[pending[i * 2]]
        let target = &scanner.nodes[pending[i * 2 + 1]]
        if source.kind != .String or target.kind != .String do
            continue
        if source.text.length == 1 or source.text.length == 2 do
            font.codeBytes = cast(u32) source.text.length
        font.unicode[cmapCode(source.text.toString())] = Text.decode(cast(const [..] u8) target.text.toString(), .Utf16Be)
    }
}

private func applyCMapRanges(font: *FontResource, scanner: const *PdfParser, pending: const [..] u32)
{
    for i in @countof(pending) / 3
    {
        let low  = &scanner.nodes[pending[i * 3]]
        let high = &scanner.nodes[pending[i * 3 + 1]]
        let dest = &scanner.nodes[pending[i * 3 + 2]]
        if low.kind != .String or high.kind != .String do
            continue
        if low.text.length == 1 or low.text.length == 2 do
            font.codeBytes = cast(u32) low.text.length

        let first = cmapCode(low.text.toString())
        let last  = cmapCode(high.text.toString())
        if first > last or last - first > 65_535 do
            continue

        // The list form gives one destination per code; the scalar form gives the first
        // destination and increments its last UTF-16 unit across the range.
        if dest.kind == .Array
        {
            for value, offset in dest.values where offset <= cast(u64) (last - first)
            {
                let entry = &scanner.nodes[value]
                if entry.kind == .String do
                    font.unicode[first + cast(u32) offset] = Text.decode(cast(const [..] u8) entry.text.toString(), .Utf16Be)
            }

            continue
        }

        if dest.kind != .String or dest.text.length < 2 do
            continue
        if dest.text.length > 2
        {
            font.unicode[first] = Text.decode(cast(const [..] u8) dest.text.toString(), .Utf16Be)
            continue
        }

        let base = cmapCode(dest.text.toString())
        for code in first to last
        {
            var builder: StrConv.StringBuilder
            builder.appendRune(cast(rune) (base + code - first))
            font.unicode[code] = builder.toString()
        }
    }
}

private func cmapCode(bytes: string)->u32
{
    var result = 0'u32
    for value in cast(const [..] u8) bytes do
        result = result << 8 | value
    return result
}
