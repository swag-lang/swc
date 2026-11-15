#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// A CBZ page and its navigation in Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.cbz"), false, "viewer.comic.page")
}
