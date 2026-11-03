#global if #command == Swag.CompilerCommand.Test

using Core, Pixel, Pdf

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
        Swag.require(reader.fileName() == path.toString())
        for pageIndex in reader.pageCount()
        {
            var page  = expect reader.loadPage(pageIndex)
            let index = TextIndex.build(&page)
            let text  = expect reader.loadPageText(pageIndex)
            Swag.require(text == index.text)
            if not text.isEmpty() do
                indexed += 1
        }
    }

    Swag.require(indexed > 40)
    var reader = expect Reader.open(corpusPdfPath("pdfbox-jpeg-rgb.pdf"))
    var rangeErrorOutcome: Swag.Error
    var overflow: #decltype(expect reader.loadPageText(reader.pageCount()))
    catch { overflow = try reader.loadPageText(reader.pageCount()) } as rangeErrorOutcome
    let rangeError = rangeErrorOutcome.value()
    Swag.require(rangeError != null and overflow.isEmpty())
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
        Swag.require(typeface.familyName() == "FKFJSD+DejaVuSans")
        Swag.require(font.identityGlyphs)
        found = true
        break
    }

    Swag.require(found)
}
