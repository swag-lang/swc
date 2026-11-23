#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Cached pie proportions rasterize with their slice order and theme fixed to Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.pie-chart.pptx"), false, "viewer.pptx.pie-chart")
}
