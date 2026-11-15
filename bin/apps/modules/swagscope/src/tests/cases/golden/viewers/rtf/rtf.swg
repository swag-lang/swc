#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Styled rich text in Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.rtf"), false, "viewer.rtf.page")
}

// An embedded photograph keeps its place between paragraphs in Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.pictures.rtf"), true, "viewer.rtf.picture.paper")
}
