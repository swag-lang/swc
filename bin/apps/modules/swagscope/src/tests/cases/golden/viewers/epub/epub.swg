#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// EPUB's chapter text and reading controls in Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.epub"), true, "viewer.epub.chapter")
}

// The book's authored hierarchy remains readable beside a chapter in Encre.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.navigation.epub"), false, 900, 600)
    let view   = assume cast(*Epub.Panel, window.currentView)
    window.sendCommandEvent(ViewerCommands.Outline)
    Swag.require(view.outline.rows.count == 3)
    window.applyLayout()
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.epub.contents.encre")
}
