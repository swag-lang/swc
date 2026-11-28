#global namespace Pdf

using Core, Core.Math

private const InvalidCidFont = Swag.U64.Max
private const HexDigits      = "0123456789ABCDEF"

private func appendHexByte(result: *String, byte: u8)
{
    result[] += HexDigits[byte >> 4]
    result[] += HexDigits[byte & 15]
}

private func appendCid(result: *String, code: u32)
{
    appendHexByte(result, cast(u8, code >> 8))
    appendHexByte(result, cast(u8, code & 255))
}

private func appendFontName(result: *String, name: string)
{
    result[] += '/'
    for byte in cast(const [..] u8, name)
    {
        switch byte
        {
        case '#', '%', '/', '(', ')', '<', '>', '[', ']', '{', '}':
            result[] += '#'
            appendHexByte(result, byte)

        default:
            if byte <= 32 or byte >= 127
            {
                result[] += '#'
                appendHexByte(result, byte)
            }
            else
            {
                result[] += byte
            }
        }
    }
}

private func needsCompositeEncoding(text: string)->bool
{
    Utf8.visitRunes(text)
    {
        if windows1252Byte(c) < 0
        {
            return true
        }
    }

    return false
}

// Single-face quadratic SFNTs can use the standard or the older Apple signature.
private func isSingleTrueTypeProgram(bytes: const [..] u8)->bool
{
    let signature = bytes[0 until 4]
    return Slice.equals(signature, [0_u8, 1, 0, 0]) or Slice.equals(signature, cast(const [..] u8, "true"))
}

// Keep source codes only when the written font can reproduce their intended glyph addresses.
private func cidFontSlot(page: const *Page, item: const *Item, fonts: *Array!{CidFontUse})->u64
{
    if item.fontIndex >= page.fonts.count or
       item.textCodes.isEmpty() or
       item.textCodes.count != item.textAdvances.count
    {
        return InvalidCidFont
    }

    let font = &page.fonts[item.fontIndex]
    if not font.identityHorizontal or
       not font.hasCidDescriptor or
       font.programBytes().count < 4 or
       font.baseName.isEmpty() or
       font.cidKeyed or
       font.unicode.isEmpty() or
       (not font.identityGlyphs and font.glyphIndices.isEmpty()) or
       not isSingleTrueTypeProgram(font.programBytes()) or
       not needsCompositeEncoding(item.text.toString())
    {
        return InvalidCidFont
    }

    for existing, index in fonts[] where existing.resource == font
    {
        return index
    }

    fonts.add({resource: font})
    return fonts.count - 1
}

private func appendCidRun(result: *String, item: const *Item, font: const *FontResource)
{
    result[] += "[<"
    for code, index in item.textCodes
    {
        appendCid(result, code)
        let natural = font.codeWidth(code) * item.fontSize
        if index + 1 < item.textCodes.count and
           natural != item.textAdvances[index] and
           item.fontSize > 0
        {
            result[] += "> "
            appendPdfNumber(result, (natural - item.textAdvances[index]) * 1000 / item.fontSize)
            result[] += " <"
        }
    }

    result[] += ">] TJ\n"
}

private func cidUnicodeMap(font: const *FontResource)->String fail
{
    var result: #returntype = """
        /CIDInit /ProcSet findresource begin
        12 dict begin
        begincmap
        /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def
        /CMapName /SwagToUnicode def
        /CMapType 2 def
        1 begincodespacerange
        <0000> <FFFF>
        endcodespacerange
        """
    result += '\n'
    var chunk: String
    var count: u32
    for code, text in font.unicode where code <= 65535 and not text.isEmpty()
    {
        chunk += '<'
        appendCid(&chunk, code)
        chunk += "> <"
        let bytes = #move try Text.encode(text.toString(), .Utf16Be)
        for byte in bytes
        {
            appendHexByte(&chunk, byte)
        }

        chunk += ">\n"
        count += 1
        if count == 100
        {
            result += "100 beginbfchar\n"
            result += chunk
            result += "endbfchar\n"
            count  = 0
            chunk.clear()
        }
    }

    if count
    {
        result.appendFormat("% beginbfchar\n", count)
        result += chunk
        result += "endbfchar\n"
    }

    result += "endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n"
    return result
}

private impl Writer
{
    mtd writeTrueTypeProgram(font: const *FontResource, nextObject: *u32)->u32 fail
    {
        if .shareFontPrograms
        {
            if let known = .fontPrograms.tryFind(font.programKey()) where Slice.equals(known.value.resource.programBytes(), font.programBytes())
            {
                return known.value.object
            }
        }

        let number = nextObject[]
        nextObject[] += 1
        let dictionary = Format.toString("/Length1 % /Filter /FlateDecode", font.programBytes().count)
        let retained   = font.programData.flate.toSlice()
        if retained.count
        {
            let borrow = .borrowStreams and retained.count >= MinBorrowedStreamSize
            .streamObject(number, retained, dictionary.toString(), borrow)
        }
        else
        {
            let bytes = #move try .zlib.compress(font.programBytes())
            .streamObject(number, bytes.toSlice(), dictionary.toString())
        }

        if .shareFontPrograms
        {
            .fontPrograms.add(font.programKey(), {number, font})
        }

        return number
    }

    mtd writeCidFont(font: const *FontResource, nextObject: *u32)->u32 fail
    {
        let program    = try .writeTrueTypeProgram(font, nextObject)
        let composite  = nextObject[]
        let descendant = composite + 1
        let descriptor = composite + 2
        let unicode    = composite + 3
        nextObject[] += 4

        var encodedName: String
        appendFontName(&encodedName, font.baseName.toString())
        .beginObject(composite)
        .append(Format.toString("<< /Type /Font /Subtype /Type0 /BaseFont % /Encoding /Identity-H /DescendantFonts [% 0 R] /ToUnicode % 0 R >>\n",
                                encodedName,
                                descendant,
                                unicode).toString())
        .endObject()

        var mapping: String = "/Identity"
        if not font.identityGlyphs
        {
            let mapObject = nextObject[]
            nextObject[] += 1
            let count = Math.min(font.glyphIndices.count, 65536_u64)
            var map: Array!{u8}
            map.resize(count * 2)
            for index in count
            {
                let glyph = font.glyphIndices[index]
                map[index * 2]     = cast(u8, glyph >> 8)
                map[index * 2 + 1] = cast(u8, glyph & 255)
            }

            let packed = #move try .zlib.compress(map.toSlice())
            .streamObject(mapObject, packed.toSlice(), "/Filter /FlateDecode")
            mapping = Format.toString("% 0 R", mapObject)
        }

        var data = Format.toString("<< /Type /Font /Subtype /CIDFontType2 /BaseFont % /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor % 0 R /CIDToGIDMap % /DW ",
                                   encodedName,
                                   descriptor,
                                   mapping)
        appendPdfNumber(&data, font.defaultWidth * 1000)
        if not font.widths.isEmpty()
        {
            data += " /W ["
            var codes: Array!{u32}
            codes.reserve(font.widths.count)
            for code, _ in font.widths where code <= 65535
            {
                codes.add(code)
            }

            codes.sort(func(a, b: u32)->s32 => a < b ? -1 : (a > b ? 1 : 0))
            for code in codes
            {
                data.appendFormat("% [", code)
                appendPdfNumber(&data, font.codeWidth(code) * 1000)
                data += "] "
            }

            data += ']'
        }

        data += " >>\n"
        .beginObject(descendant)
        .append(data.toString())
        .endObject()

        let metrics = &font.cidDescriptor
        let bounds  = metrics.bounds
        .beginObject(descriptor)
        .append(Format.toString("<< /Type /FontDescriptor /FontName % /Flags % /FontBBox [% % % %] /Ascent % /Descent % /CapHeight % /ItalicAngle % /StemV % /FontFile2 % 0 R >>\n",
                                encodedName,
                                metrics.flags,
                                pdfNumber(bounds[0]),
                                pdfNumber(bounds[1]),
                                pdfNumber(bounds[2]),
                                pdfNumber(bounds[3]),
                                pdfNumber(metrics.ascent),
                                pdfNumber(metrics.descent),
                                pdfNumber(metrics.capHeight),
                                pdfNumber(metrics.italicAngle),
                                pdfNumber(metrics.stemV),
                                program).toString())
        .endObject()

        let cmap       = #move try cidUnicodeMap(font)
        let packedCmap = #move try .zlib.compress(cast(const [..] u8, cmap))
        .streamObject(unicode, packedCmap.toSlice(), "/Filter /FlateDecode")
        return composite
    }
}
