#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// EPUB's chapter text and reading controls in Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.epub"), true, "viewer.epub.chapter")
}

// A CBZ page and its navigation in Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.cbz"), false, "viewer.comic.page")
}

// Word paragraphs and the omitted-image notice in Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.docx"), true, "viewer.docx.page")
}

// Word headings and styled runs in Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.formatted.docx"), false, "viewer.docx.formatted")
}

// An authored Word page break in Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.pagebreak.docx"), true, "viewer.docx.pagebreak")
}

// A Word document with an embedded photo in Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.image.docx"), true, "viewer.docx.image")
}

// Styled rich text in Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.rtf"), false, "viewer.rtf.page")
}

// Ordered workbook cells and the reading column in Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.xlsx"), false, "viewer.xlsx.sheets")
}

// Uncached formulas stay visible in a Papier workbook.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.formulas.xlsx"), true, "viewer.xlsx.formulas")
}

// A presentation's slide text in Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.pptx"), true, "viewer.pptx.slide")
}

// A presentation with an embedded photo in Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.pictures.pptx"), false, "viewer.pptx.picture")
}

// Aligned and styled presentation text in Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.formatted.pptx"), true, "viewer.pptx.formatted")
}
