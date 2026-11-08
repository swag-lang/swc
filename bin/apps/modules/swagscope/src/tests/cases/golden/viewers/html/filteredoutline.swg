#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// The filtered HTML outline stays legible beside a document in Papier.
#[Swag.TestTag("golden")]
#test
{
    let file = scopeTestDataPath("viewer.page.html")

    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, file, true, 900, 600)
    Swag.require(window.choices[window.activeChoiceIndex].key == "html")
    window.sendCommandEvent(ViewerCommands.Outline)
    let outline = assume cast(*DocumentOutline, window.currentSidePanelHost!.children[0].children[0])
    Swag.require(outline.rows.count == 4)
    outline.filterBox.setText("Moving")
    Swag.require(outline.rows.count == 1 and outline.isLocallyVisible())
    window.applyLayout()
    host.finishAnimations()
    Swag.require(outline.surfaceRect().right() <= window.surfaceRect().right())

    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.html.filtered-outline.paper")
}
