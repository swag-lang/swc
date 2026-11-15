#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Writer typography and a table sit beside the heading outline in Encre.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.odt"), false, 1040, 720)
    window.sendCommandEvent(ViewerCommands.Outline)
    window.applyLayout()
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.odt.reading.encre")
}

// An embedded Writer photo keeps its reading position on Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.image.odt"), true, "viewer.odt.picture.paper", 960, 660)
}

// French details fit the minimum reading window while a bookmarked section is visible.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.odt"), true, 560, 400)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    let panel = assume cast(*Odt.Panel, window.currentView)
    Swag.require(panel.view != null)
    Swag.require(panel.view.navigateToFragment("#next-visit"))
    window.applyLayout()
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.odt.narrow.fr.paper")
}
