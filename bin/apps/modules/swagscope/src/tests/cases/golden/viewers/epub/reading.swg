#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// A compact column with enlarged type keeps the chosen passage visible on Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.christmas-carol.epub"), true, 960, 660)
    let panel  = assume cast(*Epub.Panel, window.currentView)
    panel.showChapter(1)
    completeQueuedViewerFile(&host, window)
    Swag.require(panel.view != null and panel.view.findText("to begin with"))
    panel.view.clearSearch()
    panel.setReadingColumn(.Compact)
    panel.setZoom(125)
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.epub.reading.compact.paper")
}

// A wide reading column on a real book remains within Encre's floating reading inset.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.christmas-carol.epub"), false, 1040, 720)
    let panel  = assume cast(*Epub.Panel, window.currentView)
    panel.showChapter(1)
    completeQueuedViewerFile(&host, window)
    Swag.require(panel.view != null and panel.view.navigateToFragment("#pgepubid00016"))
    panel.setReadingColumn(.Wide)
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.epub.reading.wide.encre")
}
