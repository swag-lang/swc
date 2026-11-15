#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Styled rich text in Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.rtf"), false, "viewer.rtf.page")
}

// An embedded photograph keeps its place between paragraphs in Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.pictures.rtf"), true, "viewer.rtf.picture.paper")
}

// Authored RTF typography and colored passages remain readable on paper inside Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.styles.rtf"), false, "viewer.rtf.styles.encre", 960, 720)
}

// French document facts and authored spacing fit a narrow Papier reading window.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.styles.rtf"), true, 560, 540)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    window.applyLayout()
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.rtf.styles.fr.paper")
}
