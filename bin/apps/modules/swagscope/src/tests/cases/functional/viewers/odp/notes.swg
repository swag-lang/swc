#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Producer-exported ODP notes retain the speaker body without page-number placeholders.
#test
{
    let deck = expect Odp.load(scopeTestDataPath("viewer.poi-sample.odp"))
    Swag.require(Utf8.contains(deck.slides[0].notesHtml, "I am the notes of the first slide"))
    Swag.require(Utf8.contains(deck.slides[1].notesHtml, "<b>THIS LINE IS BOLD</b>"))
    Swag.require(not Utf8.contains(deck.slides[1].notesHtml, "&lt;number&gt;"))
    Swag.require(not Utf8.contains(deck.slides[1].notesHtml, "font-size:"))
    Swag.require(not Utf8.contains(deck.slides[1].readingHtml(), "THIS LINE IS BOLD"))
}

// OpenDocument uses the same reader and slide navigation while notes remain separate.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.poi-sample.odp"), true)
    let panel  = assume cast(*Pptx.Panel, window.currentView)
    panel.showNotes()
    Swag.require(panel.view != null and panel.view.findText("notes of the first slide"))
    panel.turn(1)
    Swag.require(panel.slide == 1 and panel.notesMode and panel.view != null)
    Swag.require(panel.view.findText("THIS LINE IS BOLD"))
    panel.setTextMode(false)
    Swag.require(not panel.notesMode and not panel.textMode)
}
