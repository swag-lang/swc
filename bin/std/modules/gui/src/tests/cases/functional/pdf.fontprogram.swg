#global if #command == Swag.CompilerCommand.Test

using Core, Pixel, Pdf

private struct ProgramReport
{
    fonts:    u64     // Font resources the page refers to.
    embedded: u64     // Resources carrying a font program.
    loaded:   u64     // Programs the rasterizer accepted.
    resolved: u64     // Text items whose every code reached a glyph of its own program.
    drawn:    u64     // Text items backed by a program at all.
}

// Reports how far each font of a page gets, from an embedded program to an addressed glyph.
private func reportPage(name: string, pageIndex: u64)->ProgramReport
{
    var result: #returntype
    var reader = expect Reader.open(guiTestDataPath(name))
    var page   = expect reader.loadPage(pageIndex)

    var faces: Array!{*TypeFace?}
    result.fonts = page.fonts.count
    for font in page.fonts
    {
        var face: *TypeFace?
        if font.programBytes().count
        {
            result.embedded += 1
            let key = Format.toString("probe-%{X08}", Hash.Crc32.compute(font.programBytes()))
            catch
            {
                face = try TypeFace.create(key.toString(), font.programBytes())
                result.loaded += 1
            }
        }

        faces.add(face)
    }

    var cache: FontCache
    for item in page.items where item.kind == .Text and item.fontIndex < page.fonts.count
    {
        let face = faces[item.fontIndex]
        if not face
        {
            continue
        }

        result.drawn += 1
        let font  = cache.createFont(face, 16)
        var whole = not item.textCodes.isEmpty()
        for code in item.textCodes where not page.fonts[item.fontIndex].glyphFor(font, code).found
        {
            whole = false
        }

        if whole
        {
            result.resolved += 1
        }
    }

    return result
}

// Every page of the corpus that embeds a font program must draw with that program.
//
// A page whose program is refused still renders, through a substitute face with metrics of
// its own — which is exactly the silent degradation this checks against: the failure shows
// up as a page that is subtly not the document, never as an error.
#test
{
    const pages: [6] { name: string, page: u64 } = [
        {name: "llvm-polly-impact-2011-paper.pdf",          page: 0},
        {name: "llvm-polly-impact-2011-paper.pdf",          page: 3},
        {name: "llvm-openmp-reference.pdf",                 page: 12},
        {name: "llvm-polly-raghesh-masters-thesis.pdf",     page: 20},
        {name: "llvm-polly-kernelgen-ncar-2012-slides.pdf", page: 4},
        {name: "llvm-polly-impact-2011-slides.pdf",         page: 5}]

    for entry in pages
    {
        let report = reportPage(entry.name, entry.page)
        Swag.require(report.embedded != 0)
        Swag.require(report.loaded == report.embedded)
        Swag.require(report.drawn != 0)
        Swag.require(report.resolved == report.drawn)
    }
}

// An embedded outline keeps its holes and PDF advances through a rotated text matrix.
#test
{
    const FontBytes = #include("../../../theme/inter-regular.ttf")
    var objects: Array!{u8}
    addObject(&objects, 5, "<< /Type /Font /Subtype /TrueType /BaseFont /Inter /Encoding /WinAnsiEncoding /FirstChar 79 /LastChar 79 /Widths [1000] /FontDescriptor 6 0 R >>")
    addObject(&objects, 6, "<< /Type /FontDescriptor /FontName /Inter /FontFile2 7 0 R >>")
    addStreamObject(&objects, 7, "", FontBytes)

    let text     = "BT /F0 24 Tf 0 -1 1 0 40 80 Tm (OO) Tj ET"
    var document = #move expect Document.decode(singlePagePdf("/Font << /F0 5 0 R >>", cast(const [..] u8, text), objects.toSlice()).toSlice())
    var page     = document.pages[0]
    let image    = expect page.render()
    for glyph in 2
    {
        let top = 20 + 24 * cast(s32, glyph)
        var ink: u32
        for y in top until top + 24
        {
            for x in 40 until 64 where image.pixelColor(x, y).r < 128
            {
                ink += 1
            }
        }

        Swag.require(ink > 30)
        Swag.require(image.pixelColor(49, top + 9).r == 255)
    }
}

// Saving decoded CID text retains its character mapping, outlines and advances.
#test
{
    const FontBytes = #include("../../../theme/inter-regular.ttf")
    var objects: Array!{u8}
    addObject(&objects, 5, "<< /Type /Font /Subtype /Type0 /BaseFont /Inter /Encoding /Identity-H /DescendantFonts [6 0 R] /ToUnicode 9 0 R >>")
    addObject(&objects, 6, "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Inter /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor 7 0 R /DW 750 /W [2 [1000 720]] /CIDToGIDMap 10 0 R >>")
    addObject(&objects, 7, "<< /Type /FontDescriptor /FontName /Inter /Flags 32 /FontBBox [-700 -350 2600 1200] /Ascent 968 /Descent -241 /CapHeight 728 /ItalicAngle 0 /StemV 80 /FontFile2 8 0 R >>")
    addStreamObject(&objects, 8, "", FontBytes)
    let unicode = "2 beginbfchar\n<0002> <004F>\n<0003> <03A9>\nendbfchar\n"
    addStreamObject(&objects, 9, "", cast(const [..] u8, unicode))

    // The codes point to Inter's O and Omega glyphs by index.
    addStreamObject(&objects, 10, "", [0_u8, 0, 0, 0, 0x01, 0x41, 0x04, 0x12])

    let content   = "BT /F0 24 Tf 1 0 0 1 18 42 Tm <00020003> Tj ET"
    let source    = singlePagePdf("/Font << /F0 5 0 R >>", cast(const [..] u8, content), objects.toSlice())
    var document  = #move expect Document.decode(source.toSlice())
    let encoded   = expect document.encode()
    var rewritten = #move expect Document.decode(encoded.toSlice())
    let item      = onlyItem(rewritten.pages[0], .Text)
    let font      = &rewritten.pages[0].fonts[item.fontIndex]
    Swag.require(item.text == "OΩ")
    Swag.require(Slice.equals(item.textCodes.toSlice(), [2_u32, 3]))
    Swag.require(item.textAdvances.count == 2 and
                 item.textAdvances[0] == 24 and
                 Math.abs(item.textAdvances[1] - 17.28) < 0.001)
    Swag.require(Slice.equals(font.programBytes(), FontBytes))
    Swag.require(font.glyphIndices[2] == 321 and font.glyphIndices[3] == 1042)
    var originalPage  = document.pages[0]
    var roundTripPage = rewritten.pages[0]
    let before        = expect originalPage.render()
    let after         = expect roundTripPage.render()
    Swag.require(Slice.equals(before.pixels.toSlice(), after.pixels.toSlice()))
}

// A rotated substitute run keeps its baseline, declared spacing and open counters.
#test
{
    const FontBytes = #include("../../../theme/inter-regular.ttf")
    let fontPath = Testing.tempFilePath("pdf-outline-substitute-", ".ttf")
    defer catch { try File.delete(fontPath) }
    expect File.writeAllBytes(fontPath, FontBytes)

    var objects: Array!{u8}
    addObject(&objects, 5, "<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman /Encoding /WinAnsiEncoding /FirstChar 79 /LastChar 79 /Widths [1000] >>")
    let content  = "BT /F0 24 Tf 0 -1 1 0 40 80 Tm (OO) Tj ET"
    let source   = singlePagePdf("/Font << /F0 5 0 R >>", cast(const [..] u8, content), objects.toSlice())
    let document = expect Document.decode(source.toSlice())
    var page     = document.pages[0]
    let image    = expect page.render({scale: 2, fallbackFontFile: fontPath.toString()})

    for glyph in 2
    {
        let top        = 40 + 48 * cast(s32, glyph)
        var ink: u32
        var hasCounter = false
        for y in top until top + 48
        {
            var state: u32
            for x in 80 until 128
            {
                let value = image.pixelColor(x, y).r
                if value < 96
                {
                    ink += 1
                    if state == 2
                    {
                        hasCounter = true
                    }

                    state = 1
                }
                else if state == 1 and value == 255
                {
                    state = 2
                }
            }
        }

        Swag.require(ink > 120 and hasCounter)
    }
}

// Distinct font dictionaries and pages can refer to one program. Each page retains its bytes.
#test
{
    const FontBytes = #include("../../../theme/inter-regular.ttf")
    let file = Testing.tempFilePath("pdf-shared-font-", ".pdf")
    defer discard catch File.delete(file)

    var objects: Array!{u8}
    addObject(&objects, 5, "<< /Type /Font /Subtype /TrueType /BaseFont /Inter /FontDescriptor 7 0 R >>")
    addObject(&objects, 6, "<< /Type /Font /Subtype /TrueType /BaseFont /InterAlternate /FontDescriptor 7 0 R >>")
    addObject(&objects, 7, "<< /Type /FontDescriptor /FontName /Inter /FontFile2 8 0 R >>")
    addStreamObject(&objects, 8, "", FontBytes)
    let content = "BT /F0 20 Tf 10 20 Td (A) Tj /F1 20 Tf (B) Tj ET"
    let source = singlePagePdf("/Font << /F0 5 0 R /F1 6 0 R >>", cast(const [..] u8, content), objects.toSlice())
    expect File.writeAllBytes(file, source.toSlice())

    func laterPage(path: string)->Page
    {
        var reader = expect Reader.open(path)
        let first  = expect reader.loadPage(0)
        var second = #move expect reader.loadPage(0)
        Swag.require(first.fonts.count == 2 and second.fonts.count == 2)
        let bytes = first.fonts[0].programBytes()
        Swag.require(bytes.count != 0)
        Swag.require(bytes.buffer == first.fonts[1].programBytes().buffer)
        Swag.require(bytes.buffer == second.fonts[0].programBytes().buffer)
        Swag.require(second.fonts[0].baseName != second.fonts[1].baseName)
        return #move second
    }

    let page = laterPage(file)
    for font in page.fonts
    {
        Swag.require(Slice.equals(font.programBytes(), FontBytes))
    }
}
