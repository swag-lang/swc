#global if #command == Swag.CompilerCommand.Test

using Core, Pixel, Pdf

private func createProgramTypeFace(name: string, bytes: const [..] u8)->#null *TypeFace fail => try TypeFace.create(name, bytes)

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
    var result: retval
    var reader = expect Reader.open(corpusPdfPath(name))
    var page   = expect reader.loadPage(pageIndex)

    var faces: Array'(#null *TypeFace)
    result.fonts = page.fonts.count
    for font in page.fonts
    {
        var face: #null *TypeFace
        if !font.bytes.isEmpty()
        {
            result.embedded += 1
            let key    = Format.toString("probe-%{X08}", Hash.Crc32.compute(font.bytes.toSlice()))
            let opened = catch createProgramTypeFace(key.toString(), font.bytes.toSlice()) as loadError
            if loadError == null
            {
                result.loaded += 1
                face          = opened
            }
        }

        faces.add(face)
    }

    var cache: FontCache
    for item in page.items where item.kind == .Text and item.fontIndex < page.fonts.count
    {
        let face = faces[item.fontIndex]
        if !face do
            continue

        result.drawn += 1
        let font  = cache.createFont(face!, 16)
        var whole = !item.textCodes.isEmpty()
        for code in item.textCodes where !page.fonts[item.fontIndex].glyphFor(font, code).found do
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
        {"llvm-polly-impact-2011-paper.pdf",          0},
        {"llvm-polly-impact-2011-paper.pdf",          3},
        {"llvm-openmp-reference.pdf",                 12},
        {"llvm-polly-raghesh-masters-thesis.pdf",     20},
        {"llvm-polly-kernelgen-ncar-2012-slides.pdf", 4},
        {"llvm-polly-impact-2011-slides.pdf",         5}]

    for entry in pages
    {
        let report = reportPage(entry.name, entry.page)
        Swag.assert(report.embedded != 0)
        Swag.assert(report.loaded == report.embedded)
        Swag.assert(report.drawn != 0)
        Swag.assert(report.resolved == report.drawn)
    }
}
