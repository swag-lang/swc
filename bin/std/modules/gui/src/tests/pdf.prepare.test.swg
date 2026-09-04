#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Pdf

// Returns the page of a corpus document that carries the most items.
func heaviestPage(name: string)->{ reader: Reader, index: u64 }
{
    var result: retval
    result.reader = #move expect Reader.open(corpusPdfPath(name))
    var best = 0'u64
    for pageIndex in result.reader.pageCount()
    {
        var page = expect result.reader.loadPage(pageIndex)
        if page.items.count > best
        {
            best         = page.items.count
            result.index = pageIndex
        }
    }

    return #move result
}

// Preparing a page changes what it costs to draw, never what is drawn: the same page prepared
// for a scale and left alone renders to the same pixels at that scale.
#[Swag.TestTag("golden")]
#test
{
    const Scale = 0.75'f32

    var plain    = #move heaviestPage("llvm-polly-impact-2011-slides.pdf")
    var plainPg  = expect plain.reader.loadPage(plain.index)
    let expected = expect plainPg.render({scale: Scale, maxDimension: 8192})

    var ready   = #move heaviestPage("llvm-polly-impact-2011-slides.pdf")
    var readyPg = expect ready.reader.loadPage(ready.index)
    readyPg.prepare(Scale)
    let actual = expect readyPg.render({scale: Scale, maxDimension: 8192})

    Pixel.Testing.assertImagesNear(&expected, &actual, "pdf.prepare.slides")
}

// A page prepared for a fine scale is prepared for every coarser one, so a reader who zoomed in
// and back out draws from what is already there.
#[Swag.TestTag("golden")]
#test
{
    var plain    = #move heaviestPage("llvm-polly-impact-2011-slides.pdf")
    var plainPg  = expect plain.reader.loadPage(plain.index)
    let expected = expect plainPg.render({scale: 1.0, maxDimension: 8192})

    var ready   = #move heaviestPage("llvm-polly-impact-2011-slides.pdf")
    var readyPg = expect ready.reader.loadPage(ready.index)
    readyPg.prepare(8)
    let actual = expect readyPg.render({scale: 1.0, maxDimension: 8192})

    // The finer flattening is what both now draw, so the two agree to within the segment a curve
    // gains from it rather than exactly.
    Pixel.Testing.assertImagesNear(&expected, &actual, "pdf.prepare.finer", {maxChannelDelta: 255, maxDifferentPixels: 4000})
}

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
