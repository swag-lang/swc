#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Gutenberg's authored no-break space in the stave heading stays blank and unbroken.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.christmas-carol.epub"), false, 880, 520)
    let panel  = assume cast(*Epub.Panel, window.currentView)
    panel.showChapter(1)
    completeQueuedViewerFile(&host, window)
    Swag.require(panel.view != null and panel.view.navigateToFragment("#pgepubid00015"))
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.epub.heading.encre")
}
