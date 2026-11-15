#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Returning from a chapter link restores the previously visible passage, not the chapter start.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.navigation.epub"), true, 560, 400)
    let panel  = assume cast(*Epub.Panel, window.currentView)
    Swag.require(panel.view != null and panel.view.findText("Paragraph 15."))
    panel.view.clearSearch()
    panel.followLink("two.xhtml#arrival")
    completeQueuedViewerFile(&host, window)
    panel.goBack()
    completeQueuedViewerFile(&host, window)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.epub.history.return.fr.paper")
}
