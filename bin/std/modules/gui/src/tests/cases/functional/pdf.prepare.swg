#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Pdf

// A page with nothing but text has no vector geometry to prepare, and preparing an invalid scale
// is refused rather than half-applied.
#test
{
    var reader = expect Reader.open(corpusPdfPath("llvm-polly-raghesh-masters-thesis.pdf"))
    var page   = expect reader.loadPage(69)
    page.prepare(2)
    page.prepare(0)
    page.prepare(-1)
    let image = expect page.render({scale: 0.5, maxDimension: 8192})
    Swag.assert(image.isValid())
}
