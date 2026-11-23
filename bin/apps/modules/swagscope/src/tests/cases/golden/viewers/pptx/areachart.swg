#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Standard cached area series show the signed trends and keep their direct colors.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.area-chart.pptx"), false, "viewer.pptx.area-chart")
}
