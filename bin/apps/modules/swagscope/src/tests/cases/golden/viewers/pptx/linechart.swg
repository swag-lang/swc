#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Cached line series rasterize with their trend, category order, and theme fixed to Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.line-chart.pptx"), false, "viewer.pptx.line-chart")
}
