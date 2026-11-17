#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Reading measure and zoom retain the current passage without losing the search highlight.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.navigation.epub"), false, 1040, 720)
    let panel  = assume cast(*Epub.Panel, window.currentView)
    Swag.require(panel.view != null)
    Swag.require(panel.view.findText("Paragraph 15."))
    var before: Math.Rectangle
    Swag.require(panel.view.searchMatchRect(&before))
    panel.setReadingColumn(.Compact)
    panel.setZoom(150)
    Swag.require(panel.view.documentStyle.maxContentWidth == 520 and panel.view.documentStyle.bodyFontSize == 27)
    var after: Math.Rectangle
    Swag.require(panel.view.searchMatchRect(&after))
    let frame = panel.view.surfaceRect()
    Swag.require(after.y >= frame.y - 1 and after.bottom() <= frame.bottom() + 1, Format.toString("before %, after %, frame %", before, after, frame))
    Swag.require(panel.chapter == 0 and panel.view.readingPosition().isValid())
    panel.setReadingColumn(.Wide)
    Swag.require(panel.view.documentStyle.maxContentWidth == 900)
    Swag.require(panel.view.searchMatchRect(&after) and after.y >= frame.y - 1 and after.y < frame.bottom())
}

// The selected book measure and type scale follow chapter turns and French command resources.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.navigation.epub"), true)
    let panel  = assume cast(*Epub.Panel, window.currentView)
    panel.setReadingColumn(.Wide)
    panel.setZoom(125)
    panel.showChapter(1)
    Swag.require(panel.view != null)
    Swag.require(panel.view.documentStyle.maxContentWidth == 900 and panel.view.documentStyle.bodyFontSize == 23)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    Swag.require(Epub.texts().ui_CompactColumn == "Colonne de lecture étroite")
    Swag.require(Epub.texts().ui_WideColumn == "Colonne de lecture large")
}

// Ctrl and the wheel step the zoom of a book, as they step the zoom of every other reading viewer.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.navigation.epub"), false, 1040, 720)
    let panel  = assume cast(*Epub.Panel, window.currentView)
    Swag.require(panel.view != null)
    panel.setZoom(100)
    host.mouseWheel(panel.view.surfaceRect().center(), 120, .Control)
    Swag.require(panel.zoomPercent == 125)
    host.mouseWheel(panel.view.surfaceRect().center(), -120, .Control)
    host.mouseWheel(panel.view.surfaceRect().center(), -120, .Control)
    Swag.require(panel.zoomPercent == 75)
    host.mouseWheel(panel.view.surfaceRect().center(), 120, .Control | .Shift)
    Swag.require(panel.zoomPercent == 75)
}
