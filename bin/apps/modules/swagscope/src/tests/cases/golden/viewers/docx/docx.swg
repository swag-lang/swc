#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

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
