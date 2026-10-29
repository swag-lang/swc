#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

// Each viewer in the window the application ships, at the size of its picture, so its golden is
// judged whole against the picture of the charter.
func picturedViewer(fileName: string, light: bool, golden: string)
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fileName, light)
    window.applyLayout()
    host.settleAnimations(window, 8)
    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, golden)
}

func picturedFixture(name: string)->String => Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas", name)

#[Swag.TestTag("golden")]
#test
{
    picturedViewer(picturedFixture("imageset-real-review.webp"), false, "pictured.image")
    picturedViewer(picturedFixture("viewer.csv"), true, "pictured.table.paper")
    picturedViewer(picturedFixture("viewer.html"), true, "pictured.html.paper")
    picturedViewer(picturedFixture("segoeui.ttf"), true, "pictured.font.paper")
}
