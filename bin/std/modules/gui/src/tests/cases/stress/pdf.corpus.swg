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
#[Swag.TestTag("stress")]
#test
{
    const fixtures: [5] CorpusPdf = [
        CorpusPdf{"llvm-polly-passes-only.pdf", 1},
        CorpusPdf{"llvm-polly-passes-late.pdf", 1},
        CorpusPdf{"llvm-polly-passes-early.pdf", 1},
        CorpusPdf{"llvm-polly-passes-all.pdf", 1},
        CorpusPdf{"llvm-openmp-reference.pdf", 67}]
    renderCorpus(fixtures)
}

#[Swag.TestTag("stress")]
#test
{
    const fixtures: [3] CorpusPdf = [
        CorpusPdf{"llvm-polly-impact-2011-paper.pdf", 6},
        CorpusPdf{"llvm-polly-impact-2011-slides.pdf", 27},
        CorpusPdf{"llvm-polly-raghesh-masters-thesis.pdf", 70}]
    renderCorpus(fixtures)
}

#[Swag.TestTag("stress")]
#test
{
    const fixtures: [1] CorpusPdf = [CorpusPdf{"llvm-polly-grosser-diploma-thesis.pdf", 101}]
    renderCorpus(fixtures)
}

#[Swag.TestTag("stress")]
#test
{
    const fixtures: [2] CorpusPdf = [
        CorpusPdf{"llvm-polly-kernelgen-pavt-2012-slides.pdf", 51},
        CorpusPdf{"llvm-polly-kernelgen-ncar-2012-slides.pdf", 28}]
    renderCorpus(fixtures)
}
