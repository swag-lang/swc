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

    var faces: Array'(*TypeFace?)
    result.fonts = page.fonts.count
    for font in page.fonts
    {
        var face: *TypeFace?
        if not font.bytes.isEmpty()
        {
            result.embedded += 1
            let key = Format.toString("probe-%{X08}", Hash.Crc32.compute(font.bytes.toSlice()))
            catch
            {
                face = try TypeFace.create(key.toString(), font.bytes.toSlice())
                result.loaded += 1
            }
        }

        faces.add(face)
    }

    var cache: FontCache
    for item in page.items where item.kind == .Text and item.fontIndex < page.fonts.count
    {
        let face = faces[item.fontIndex]
        if not face do
            continue

        result.drawn += 1
        let font  = cache.createFont(face, 16)
        var whole = not item.textCodes.isEmpty()
        for code in item.textCodes where not page.fonts[item.fontIndex].glyphFor(font, code).found do
            whole = false
        if whole do
            result.resolved += 1
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
    var objects: Array'u8
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
            for x in 40 until 64 where image.pixelColor(x, y).r < 128 do
                ink += 1
        }

        Swag.require(ink > 30)
        Swag.require(image.pixelColor(49, top + 9).r == 255)
    }
}
