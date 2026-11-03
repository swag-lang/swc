#global if #command == Swag.CompilerCommand.Test

using Core, Core.Math, Pdf

// Standard metrics are read from the built-in tables, so a run can be measured without any
// font file on the machine.
#test
{
    Swag.require(Math.isEqualEpsilon(StandardFont.Helvetica.glyphWidth('A'), 0.667, 0.0005))
    Swag.require(Math.isEqualEpsilon(StandardFont.HelveticaBold.glyphWidth('A'), 0.722, 0.0005))
    Swag.require(Math.isEqualEpsilon(StandardFont.TimesRoman.glyphWidth(' '), 0.25, 0.0005))
    Swag.require(Math.isEqualEpsilon(StandardFont.Courier.glyphWidth('W'), 0.6, 0.0005))
    Swag.require(StandardFont.Courier.glyphWidth('i') == StandardFont.Courier.glyphWidth('W'))

    // A composed Latin letter has the advance of the letter it is built on, and a character
    // outside the tables still measures as something plausible.
    Swag.require(StandardFont.Helvetica.glyphWidth('é') == StandardFont.Helvetica.glyphWidth('e'))
    Swag.require(StandardFont.TimesBold.glyphWidth('Ó') == StandardFont.TimesBold.glyphWidth('O'))
    Swag.require(StandardFont.Helvetica.glyphWidth('☺') > 0)

    // "Hi" is 722 + 222 thousandths of the size in Helvetica.
    Swag.require(Math.isEqualEpsilon(StandardFont.Helvetica.textWidth("Hi", 100), 94.4, 0.01))
    Swag.require(StandardFont.Courier.textWidth("abcd", 10) == 24)
    Swag.require(StandardFont.Helvetica.textWidth("", 12) == 0)
}

#test
{
    let helvetica = StandardFont.fromBaseName("Helvetica")
    Swag.require(helvetica.found and helvetica.font == .Helvetica)

    // A subset prefix is not part of the name.
    let subset = StandardFont.fromBaseName("ABCDEF+Times-BoldItalic")
    Swag.require(subset.found and subset.font == .TimesBoldItalic)

    let arial = StandardFont.fromBaseName("Arial-BoldMT")
    Swag.require(arial.found and arial.font == .HelveticaBold)

    let courier = StandardFont.fromBaseName("CourierNewPS-ItalicMT")
    Swag.require(courier.found and courier.font == .CourierOblique)

    let unknown = StandardFont.fromBaseName("Wingdings")
    Swag.require(not unknown.found)

    let all: [6] StandardFont = [.Helvetica, .HelveticaBold, .TimesRoman, .TimesBoldItalic, .Courier, .CourierBoldOblique]
    for font in all
    {
        let round = StandardFont.fromBaseName(font.baseFontName())
        Swag.require(round.found and round.font == font)
    }
}

// The four base encodings map a byte to the character the format assigns it.
#test
{
    Swag.require(encodingRune(.WinAnsi, 'A') == 'A')
    Swag.require(encodingRune(.WinAnsi, 0xE9) == 'é')
    Swag.require(encodingRune(.WinAnsi, 0x80) == '€')
    Swag.require(encodingRune(.MacRoman, 0x8E) == 'é')
    Swag.require(encodingRune(.MacRoman, 0xD5) == '’')
    Swag.require(encodingRune(.Standard, 0x27) == '’')
    Swag.require(encodingRune(.Standard, 0xE1) == 'Æ')

    Swag.require(glyphNameRune("eacute") == 'é')
    Swag.require(glyphNameRune("Euro") == '€')
    Swag.require(glyphNameRune("uni2713") == '✓')
    Swag.require(glyphNameRune("u01FF") == 'ǿ')
    Swag.require(glyphNameRune("not-a-glyph") == 0)
}

// `Td`, `TD`, `T*`, and `TL` move the line matrix through it, so a rotated text matrix
// carries the line advance with it.
#test
{
    let content = "BT /F0 10 Tf 0 -1 1 0 20 30 Tm 5 0 Td (A) Tj 12 TL T* (B) Tj ET"
    var objects: Array'u8
    addObject(&objects, 5, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")

    let document = expect Document.decode(singlePagePdf("/Font << /F0 5 0 R >>", cast(const [..] u8, content), objects.toSlice()).toSlice())
    let page     = document.pages[0]
    Swag.require(page.items.count == 2)

    // The text matrix rotates by ninety degrees, so `Td 5 0` moves down the page and the
    // following line moves left by the leading.
    let first  = page.items[0].itemTransform()
    let second = page.items[1].itemTransform()
    Swag.require(Math.isEqualEpsilon(first.tx, 30, 0.01))
    Swag.require(Math.isEqualEpsilon(second.tx - first.tx, -12, 0.01))
    Swag.require(Math.isEqualEpsilon(second.ty, first.ty, 0.01))
}

// `/Widths` decides how far a shown string moves the position, and the entries of a `TJ`
// array move it back by their own amount.
#test
{
    var objects: Array'u8
    addObject(&objects, 5, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /FirstChar 65 /LastChar 66 /Widths [1000 500] >>")

    let content  = "BT /F0 10 Tf 0 0 Td (AB) Tj (C) Tj ET"
    let document = expect Document.decode(singlePagePdf("/Font << /F0 5 0 R >>", cast(const [..] u8, content), objects.toSlice()).toSlice())
    let page     = document.pages[0]
    Swag.require(page.items.count == 2)

    // "A" is one em wide and "B" half of one, so the second run starts 15 points further right.
    Swag.require(Math.isEqualEpsilon(page.items[1].itemTransform().tx - page.items[0].itemTransform().tx, 15, 0.01))

    let kerned = "BT /F0 10 Tf 0 0 Td [(A) -500 (B)] TJ ET"
    let second = expect Document.decode(singlePagePdf("/Font << /F0 5 0 R >>", cast(const [..] u8, kerned), objects.toSlice()).toSlice())
    Swag.require(second.pages[0].items.count == 2)

    // One em for "A", then five extra points of kerning.
    let offset = second.pages[0].items[1].itemTransform().tx - second.pages[0].items[0].itemTransform().tx
    Swag.require(Math.isEqualEpsilon(offset, 15, 0.01))
}

// Render mode 3 hides the marks but still advances, which is what an invisible text layer over
// a scanned page relies on.
#test
{
    var objects: Array'u8
    addObject(&objects, 5, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")

    let content  = "BT /F0 10 Tf 3 Tr (hidden) Tj 0 Tr (shown) Tj ET"
    let document = expect Document.decode(singlePagePdf("/Font << /F0 5 0 R >>", cast(const [..] u8, content), objects.toSlice()).toSlice())
    Swag.require(pageText(document.pages[0]) == "hiddenshown")
    Swag.require(document.pages[0].items.count == 2)
    Swag.require(document.pages[0].items[0].invisibleText)
    Swag.require(not document.pages[0].items[1].invisibleText)

    // The hidden run still moved the position, so the visible one does not start at the origin.
    Swag.require(document.pages[0].items[1].itemTransform().tx > 20)
}

// Invisible OCR text remains searchable at the same offsets as the displayed page's index.
#test
{
    var objects: Array'u8
    addObject(&objects, 5, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    let content  = "BT /F0 10 Tf 10 80 Td 3 Tr (hidden) Tj 0 Tr (shown) Tj 7 Tr (clipped) Tj ET"
    let bytes    = singlePagePdf("/Font << /F0 5 0 R >>", cast(const [..] u8, content), objects.toSlice())
    let fileName = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("pdf-invisible-%{X016}.pdf", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, bytes.toSlice())

    var reader = expect Reader.open(fileName)
    let text   = expect reader.loadPageText(0)
    Swag.require(text.contains(cast(string, "hidden")))
    Swag.require(text.contains(cast(string, "shown")))
    Swag.require(text.contains(cast(string, "clipped")))
    var page    = expect reader.loadPage(0)
    let indexed = TextIndex.build(&page)
    Swag.require(text == indexed.text)
}

// A `/Differences` array renames single codes, and text extraction follows the new names.
#test
{
    var objects: Array'u8
    addObject(&objects, 5, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding 6 0 R >>")
    addObject(&objects, 6, "<< /Type /Encoding /BaseEncoding /WinAnsiEncoding /Differences [65 /eacute /Euro] >>")

    let content  = "BT /F0 10 Tf (ABC) Tj ET"
    let document = expect Document.decode(singlePagePdf("/Font << /F0 5 0 R >>", cast(const [..] u8, content), objects.toSlice()).toSlice())
    Swag.require(pageText(document.pages[0]) == "é€C")
}

// A `/ToUnicode` CMap outranks the encoding, in both its single and its range form.
#test
{
    let cmap = #raw """
/CIDInit /ProcSet findresource begin
1 begincodespacerange
<00> <FF>
endcodespacerange
1 beginbfchar
<41> <0041 0042>
endbfchar
1 beginbfrange
<42> <44> <0061>
endbfrange
endcmap
"""

    var objects: Array'u8
    addObject(&objects, 5, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /ToUnicode 6 0 R >>")
    addStreamObject(&objects, 6, "", cast(const [..] u8, cmap))

    let content  = "BT /F0 10 Tf (ABCD) Tj ET"
    let document = expect Document.decode(singlePagePdf("/Font << /F0 5 0 R >>", cast(const [..] u8, content), objects.toSlice()).toSlice())
    Swag.require(pageText(document.pages[0]) == "ABabc")
}

// A simple font keeps its one-byte codes whatever its `/ToUnicode` CMap declares.
//
// Writers routinely give a simple font a map with the two-byte codespace of an identity
// encoding while writing the map's own codes one byte wide, and mix a two-byte entry in among
// them. The map says how a code spells out as text; it never says how wide a code is.
#test
{
    let cmap = #raw """
/CIDInit /ProcSet findresource begin
1 begincodespacerange
<0000> <FFFF>
endcodespacerange
2 beginbfchar
<42> <0042>
<0020> <0020>
endbfchar
endcmap
"""

    var objects: Array'u8
    addObject(&objects, 5, "<< /Type /Font /Subtype /TrueType /BaseFont /ABCDEF+Calibri-Bold /Encoding /WinAnsiEncoding /ToUnicode 6 0 R >>")
    addStreamObject(&objects, 6, "", cast(const [..] u8, cmap))

    let content  = "BT /F0 10 Tf (B) Tj ET"
    let document = expect Document.decode(singlePagePdf("/Font << /F0 5 0 R >>", cast(const [..] u8, content), objects.toSlice()).toSlice())
    Swag.require(document.pages[0].fonts[0].codeBytes == 1)
    Swag.require(pageText(document.pages[0]) == "B")
}

// A composite font addresses glyphs with two-byte codes and takes its widths from `/W`.
#test
{
    let cmap = #raw """
2 begincodespacerange
<0000> <FFFF>
endcodespacerange
2 beginbfchar
<0003> <0048>
<0004> <0069>
endbfchar
endcmap
"""

    var objects: Array'u8
    addObject(&objects, 5, "<< /Type /Font /Subtype /Type0 /BaseFont /Custom /Encoding /Identity-H /DescendantFonts [6 0 R] /ToUnicode 7 0 R >>")
    addObject(&objects, 6, "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Custom /DW 1000 /W [3 [500 250]] >>")
    addStreamObject(&objects, 7, "", cast(const [..] u8, cmap))

    let content  = "BT /F0 20 Tf <00030004> Tj <0003> Tj ET"
    let document = expect Document.decode(singlePagePdf("/Font << /F0 5 0 R >>", cast(const [..] u8, content), objects.toSlice()).toSlice())
    let page     = document.pages[0]
    Swag.require(page.items.count == 2)
    Swag.require(page.items[0].textValue() == "Hi")
    Swag.require(page.items[1].textValue() == "H")
    Swag.require(page.fonts[0].identityGlyphs)
    Swag.require(page.items[0].textCodes.count == 2 and
                 page.items[0].textCodes[0] == 3 and
                 page.items[0].textCodes[1] == 4)
    Swag.require(page.items[0].textAdvances.count == 2 and
                 page.items[0].textAdvances[0] == 10 and
                 page.items[0].textAdvances[1] == 5)
    Swag.require(page.fonts[0].glyphIndex(4) == {index: 4, found: true})

    // The two glyphs are 500 and 250 thousandths wide at size twenty.
    Swag.require(Math.isEqualEpsilon(page.items[1].itemTransform().tx - page.items[0].itemTransform().tx, 15, 0.01))
}

// An explicit `/CIDToGIDMap` replaces the identity mapping for a TrueType descendant.
#test
{
    const glyphMap: [10] u8 = [0, 0, 0, 1, 0, 2, 0, 7, 0, 8]
    var objects: Array'u8
    addObject(&objects, 5, "<< /Type /Font /Subtype /Type0 /BaseFont /Custom /Encoding /Identity-H /DescendantFonts [6 0 R] >>")
    addObject(&objects, 6, "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Custom /CIDToGIDMap 7 0 R >>")
    addStreamObject(&objects, 7, "", glyphMap)

    let document = expect Document.decode(singlePagePdf("/Font << /F0 5 0 R >>", cast(const [..] u8, ""), objects.toSlice()).toSlice())
    let font     = &document.pages[0].fonts[0]
    Swag.require(not font.identityGlyphs)
    Swag.require(font.glyphIndex(3) == {index: 7, found: true})
    Swag.require(font.glyphIndex(4) == {index: 8, found: true})
    Swag.require(not font.glyphIndex(5).found)
}

// The writer keeps the face each run asks for, and a decoded document reports the standard
// face closest to the one the file names.
#test
{
    var document = Document.create()
    var page     = Page.create(300, 120)
    page.addText("Regular", 10, 20, 12)
    page.addText("Bold serif", 10, 50, 12, Color.fromArgb(Argb.Black), .TimesBold)
    page.addText("Fixed", 10, 80, 12, Color.fromArgb(Argb.Black), .CourierOblique)
    document.addPage(#move page)

    let bytes   = expect document.encode()
    let decoded = expect Document.decode(bytes.toSlice())
    Swag.require(decoded.pages[0].items.count == 3)
    Swag.require(decoded.pages[0].items[0].textFont() == .Helvetica)
    Swag.require(decoded.pages[0].items[1].textFont() == .TimesBold)
    Swag.require(decoded.pages[0].items[2].textFont() == .CourierOblique)
    Swag.require(pageText(decoded.pages[0]) == "RegularBold serifFixed")
}

// A face is emitted once however many runs use it, and a page with no text emits no font.
#test
{
    var document = Document.create()
    var page     = Page.create(200, 100)
    page.addText("one", 10, 20, 12, Color.fromArgb(Argb.Black), .TimesBold)
    page.addText("two", 10, 40, 12, Color.fromArgb(Argb.Black), .TimesBold)
    document.addPage(#move page)

    let bytes = expect document.encode()
    let text  = cast(string, bytes.toSlice())
    Swag.require(Utf8.indexOf(text, "/Times-Bold") != Swag.U64.Max)
    Swag.require(Utf8.indexOf(text, "/Times-Bold", Utf8.indexOf(text, "/Times-Bold") + 1) == Swag.U64.Max)

    var empty = Document.create()
    empty.addPage(Page.create(100, 100))
    let emptyBytes = expect empty.encode()
    Swag.require(Utf8.indexOf(cast(string, emptyBytes.toSlice()), "/Font") == Swag.U64.Max)
}
