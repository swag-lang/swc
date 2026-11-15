#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Column currency and row typography retain the character of a small producer-authored budget.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.default-styles.xlsx"), true, 900, 620)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.xlsx.defaults.fr.paper")
}
