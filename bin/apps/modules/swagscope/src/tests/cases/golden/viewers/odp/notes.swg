#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// A slide without notes explains the absence in the reader, with French wording on Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.odp"), true, 560, 400)
    let panel  = assume cast(*Pptx.Panel, window.currentView)
    panel.showNotes()
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.odp.notes.empty.fr.paper")
}
