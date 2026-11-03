#global if #command == Swag.CompilerCommand.Test

using Core, Core.Math, Pdf

// Standard metrics are read from the built-in tables, so a run can be measured without any
// font file on the machine.


// The four base encodings map a byte to the character the format assigns it.

// `Td`, `TD`, `T*`, and `TL` move the line matrix through it, so a rotated text matrix
// carries the line advance with it.

// `/Widths` decides how far a shown string moves the position, and the entries of a `TJ`
// array move it back by their own amount.

// Render mode 3 hides the marks but still advances, which is what an invisible text layer over
// a scanned page relies on.

// Invisible OCR text remains searchable at the same offsets as the displayed page's index.

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

// A `/Differences` array renames single codes, and text extraction follows the new names.

// A `/ToUnicode` CMap outranks the encoding, in both its single and its range form.

// A simple font keeps its one-byte codes whatever its `/ToUnicode` CMap declares.
//
// Writers routinely give a simple font a map with the two-byte codespace of an identity
// encoding while writing the map's own codes one byte wide, and mix a two-byte entry in among
// them. The map says how a code spells out as text; it never says how wide a code is.

// A composite font addresses glyphs with two-byte codes and takes its widths from `/W`.

// An explicit `/CIDToGIDMap` replaces the identity mapping for a TrueType descendant.

// The writer keeps the face each run asks for, and a decoded document reports the standard
// face closest to the one the file names.

// A face is emitted once however many runs use it, and a page with no text emits no font.
