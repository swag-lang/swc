#global if #command == Swag.CompilerCommand.Test

using Core, Core.Math, Pdf

// Invisible runs stay unpainted through decode, preparation, and encoding, without hiding a
// later visible run through leaked text state.
#[Swag.TestTag("golden")]
#test
{
    var objects: Array'u8
    addObject(&objects, 5, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    let content  = "BT /F0 10 Tf 10 80 Td 3 Tr (hidden) Tj 7 Tr (clipped) Tj ET"
    var document = expect Document.decode(singlePagePdf("/Font << /F0 5 0 R >>", cast(const [..] u8, content), objects.toSlice()).toSlice())
    var page     = document.pages[0]
    page.prepare(1)
    var blank    = Page.create(page.width, page.height)
    let expected = expect blank.render()
    let actual   = expect page.render()
    Pixel.Testing.assertImagesNear(&expected, &actual, "pdf.text.invisible")

    document.editPage(0).addText("visible", 10, 40, 10)
    let bytes     = expect document.encode()
    var roundtrip = expect Document.decode(bytes.toSlice())
    Swag.assert(pageText(roundtrip.pages[0]) == "hiddenclippedvisible")
    Swag.assert(roundtrip.pages[0].items.count == 3)
    Swag.assert(roundtrip.pages[0].items[0].invisibleText)
    Swag.assert(roundtrip.pages[0].items[1].invisibleText)
    Swag.assert(not roundtrip.pages[0].items[2].invisibleText)
    var roundPage = roundtrip.pages[0]
    var visible   = Page.create(page.width, page.height)
    visible.addText("visible", 10, 40, 10)
    let expectedRound = expect visible.render()
    let actualRound   = expect roundPage.render()
    Pixel.Testing.assertImagesNear(&expectedRound, &actualRound, "pdf.text.invisible-roundtrip")
}
