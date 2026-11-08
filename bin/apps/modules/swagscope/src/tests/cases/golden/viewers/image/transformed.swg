#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// The picture and its transform reading agree after zoom, rotation and mirror in Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("sample.svg"), true, 900, 600)
    Swag.require(window.choices[window.activeChoiceIndex].key == "image")
    let view = assume cast(*Picture.Panel, window.currentView)
    view.imageView.setZoom(3)
    view.rotateClockwise()
    view.mirrorHorizontally()
    Swag.require(view.imageView.zoom == 3 and view.imageView.rotationQuarterTurns == 3 and
                 view.imageView.isMirrored)
    window.applyLayout()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.image.transformed.paper")
}
