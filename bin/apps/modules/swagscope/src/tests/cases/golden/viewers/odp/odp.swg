#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// A fitted Impress canvas keeps authored type and rectangles beside the outline in Encre.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.odp"), false, 1040, 720)
    window.sendCommandEvent(ViewerCommands.Outline)
    window.applyLayout()
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.odp.canvas.encre")
}

// Impress's embedded photo keeps its aspect and its position in Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.odp"), true, 960, 660)
    let panel  = assume cast(*Pptx.Panel, window.currentView)
    panel.turn(1)
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.odp.photo.paper")
}

// French presentation controls and slide text fit the minimum window in Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.poi-sample.odp"), true, 560, 400)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    let panel = assume cast(*Pptx.Panel, window.currentView)
    panel.turn(1)
    panel.setTextMode(true)
    window.applyLayout()
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.odp.text.fr.paper")
}
