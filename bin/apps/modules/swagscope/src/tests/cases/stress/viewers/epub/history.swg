#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Repeated in-chapter visits cap retained history; an oversized fragment cannot enter it.
#[Swag.TestTag("stress")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.navigation.epub"), false)
    let panel  = assume cast(*Epub.Panel, window.currentView)
    for index in 160 do
        panel.showChapter(0, index % 2 == 0 ? "passage" : "")
    Swag.require(panel.history.backVisits.count == 128 and panel.history.forwardVisits.isEmpty())
    var oversized: String
    for 4097 do
        oversized += "x"
    panel.showChapter(1, oversized)
    Swag.require(panel.chapter == 0 and panel.history.backVisits.count == 128)
    for 128 do
        panel.goBack()
    Swag.require(panel.history.backVisits.isEmpty() and panel.history.forwardVisits.count == 128)
    panel.goBack()
    Swag.require(panel.history.forwardVisits.count == 128)
    for 128 do
        panel.goForward()
    Swag.require(panel.history.backVisits.count == 128 and panel.history.forwardVisits.isEmpty())
}
