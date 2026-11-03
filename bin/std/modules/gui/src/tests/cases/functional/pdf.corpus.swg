#global if #command == Swag.CompilerCommand.Test

using Core, Pixel, Pdf

private struct CorpusPdf
{
    name:      string
    pageCount: u64
    scale:     f32 = 0.25
}

private func renderCorpus(fixtures: const [..] CorpusPdf)
{
    for fixture in fixtures
    {
        var reader = expect Reader.open(corpusPdfPath(fixture.name))
        Swag.assert(reader.pageCount() == fixture.pageCount)
        for pageIndex in fixture.pageCount
        {
            var page  = expect reader.loadPage(pageIndex)
            let image = expect page.render({scale: fixture.scale, maxDimension: 8192})
            Swag.assert(image.isValid())
        }
    }
}

// Real documents from several LLVM subprojects exercise 354 pages produced by different PDF
// writers. Every page is decoded lazily and rendered, so one incompatible late page fails here.
// Quarter-size pages keep this compatibility sweep small; visual and zoom tests own full detail.




// A search reads a page's text without decoding its images, paths and masks, and what it reads
// is byte for byte what the displayed page indexes, so a match found in one lands on the same
// characters of the other. Slides carry the images and forms, the PDFBox fixtures the form
// XObject and the photograph.
#test
{
    const fixtures: [4] string = ["llvm-polly-impact-2011-slides.pdf", "llvm-polly-kernelgen-ncar-2012-slides.pdf", "pdfbox-form-xobject.pdf", "pdfbox-jpeg-rgb.pdf"]
    var indexed = 0'u64
    for name in fixtures
    {
        let path   = corpusPdfPath(name)
        var reader = expect Reader.open(path.toString())
        Swag.assert(reader.fileName() == path.toString())
        for pageIndex in reader.pageCount()
        {
            var page  = expect reader.loadPage(pageIndex)
            let index = TextIndex.build(&page)
            let text  = expect reader.loadPageText(pageIndex)
            Swag.assert(text == index.text)
            if not text.isEmpty() do
                indexed += 1
        }
    }

    Swag.assert(indexed > 40)
    var reader = expect Reader.open(corpusPdfPath("pdfbox-jpeg-rgb.pdf"))
    var rangeErrorOutcome: Swag.Error
    var overflow: #decltype(expect reader.loadPageText(reader.pageCount()))
    catch { overflow = try reader.loadPageText(reader.pageCount()) } as rangeErrorOutcome
    let rangeError = rangeErrorOutcome.value()
    Swag.assert(rangeError != null and overflow.isEmpty())
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
        let typeface = expect TypeFace.create("FKFJSD+DejaVuSans", font.bytes.toSlice())
        Swag.assert(typeface.familyName() == "FKFJSD+DejaVuSans")
        Swag.assert(font.identityGlyphs)
        found = true
        break
    }

    Swag.assert(found)
}
