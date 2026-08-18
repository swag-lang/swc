#global if #command == Swag.CompilerCommand.Test

using Core, Pixel

private func createCorpusTypeFace(name: string, bytes: const [..] u8)->#null *TypeFace fail => try TypeFace.create(name, bytes)

private struct CorpusPdf
{
    name:      string
    pageCount: u64
    scale:     f32 = 0.5
}

private func renderCorpus(fixtures: const [..] CorpusPdf)
{
    for fixture in fixtures
    {
        var reader = expect Reader.open(corpusPdfPath(fixture.name))
        @assert(reader.pageCount() == fixture.pageCount)
        for pageIndex in fixture.pageCount
        {
            var page  = expect reader.loadPage(pageIndex)
            let image = expect page.render({scale: fixture.scale, maxDimension: 8192})
            @assert(image.isValid())
        }
    }
}

// Real documents from several LLVM subprojects exercise 354 pages produced by different PDF
// writers. Every page is decoded lazily and rendered, so one incompatible late page fails here.
#test
{
    const fixtures: [5] CorpusPdf = [
        {"llvm-polly-passes-only.pdf",  1},
        {"llvm-polly-passes-late.pdf",  1},
        {"llvm-polly-passes-early.pdf", 1},
        {"llvm-polly-passes-all.pdf",   1},
        {"llvm-openmp-reference.pdf",   67}]
    renderCorpus(fixtures)
}

#test
{
    const fixtures: [3] CorpusPdf = [
        {"llvm-polly-impact-2011-paper.pdf", 6},
        {"llvm-polly-impact-2011-slides.pdf", 27, 96.0 / 72.0},
        {"llvm-polly-raghesh-masters-thesis.pdf", 70}]
    renderCorpus(fixtures)
}

#test
{
    const fixtures: [1] CorpusPdf = [{"llvm-polly-grosser-diploma-thesis.pdf", 101}]
    renderCorpus(fixtures)
}

#test
{
    const fixtures: [2] CorpusPdf = [
        {"llvm-polly-kernelgen-pavt-2012-slides.pdf", 51},
        {"llvm-polly-kernelgen-ncar-2012-slides.pdf", 28}]
    renderCorpus(fixtures)
}

// PDF permits rendering-only TrueType subsets to omit standalone `name` and `post` metadata.
// Object 103 is such a DejaVu Sans subset; its Identity-H CIDs must address its glyphs directly.
#test
{
    var reader = expect Reader.open(corpusPdfPath("llvm-polly-impact-2011-slides.pdf"))
    var page   = expect reader.loadPage(5)
    var found  = false
    for font in page.fonts where font.bytes.count == 11_148
    {
        let typeface = (expect createCorpusTypeFace("FKFJSD+DejaVuSans", font.bytes.toSlice()))!
        @assert(typeface.familyName() == "FKFJSD+DejaVuSans")
        @assert(font.identityGlyphs)
        found = true
        break
    }

    @assert(found)
}
