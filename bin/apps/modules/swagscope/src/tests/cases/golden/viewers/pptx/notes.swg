#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Real speaker notes stay readable in their own flow, separate from the authored slide canvas.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.poi-sample.pptx"), false, 760, 460)
    let panel  = assume cast(*Pptx.Panel, window.currentView)
    panel.showSlide(1)
    panel.showNotes()
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.pptx.notes.fr.encre")
}
