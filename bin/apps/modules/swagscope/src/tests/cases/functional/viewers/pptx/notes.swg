#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Real PowerPoint notes retain prose and emphasis, excluding the notes-page slide counter.
#test
{
    let deck = expect Pptx.Presentation.load(scopeTestDataPath("viewer.poi-sample.pptx"))
    Swag.require(Utf8.contains(deck.slides[0].notesHtml, "I am the notes of the first slide"))
    Swag.require(Utf8.contains(deck.slides[1].notesHtml, "<b>THIS LINE IS BOLD</b>"))
    Swag.require(not Utf8.contains(deck.slides[0].notesHtml, "<p>1</p>"))
    Swag.require(not Utf8.contains(deck.slides[1].notesHtml, "font-size:"))
    Swag.require(not Utf8.contains(deck.slides[1].readingHtml(), "THIS LINE IS BOLD"))
}

// The dedicated reader keeps its mode across slide turns; text and canvas modes clear it.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.poi-sample.pptx"), false)
    let panel  = assume cast(*Pptx.Panel, window.currentView)
    panel.showNotes()
    Swag.require(panel.notesMode and not panel.textMode and panel.view != null)
    Swag.require(panel.view.findText("notes of the first slide"))
    panel.turn(1)
    Swag.require(panel.slide == 1 and panel.notesMode and panel.view != null)
    Swag.require(panel.view.findText("THIS LINE IS BOLD"))
    panel.setTextMode(true)
    Swag.require(panel.textMode and not panel.notesMode)
    panel.showNotes()
    panel.setTextMode(false)
    Swag.require(not panel.notesMode and not panel.textMode)
}

// A slide with no notes explains the absence and updates its wording when language changes.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.pptx"), true)
    let panel  = assume cast(*Pptx.Panel, window.currentView)
    panel.showNotes()
    Swag.require(panel.view != null and panel.view.findText("no speaker notes"))
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.require(panel.view != null and panel.view.findText("ne contient pas de notes"))
}

// Footers, dates, slide thumbnails and hidden shapes are not speaker prose.
#test
{
    let xml   = "<p:notes><p:sp><p:nvSpPr><p:nvPr><p:ph type='ftr'/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>footer</a:t></a:r></a:p></p:txBody></p:sp><p:sp><p:nvSpPr><p:nvPr><p:ph type='body'/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>Speak &amp; listen</a:t></a:r></a:p></p:txBody></p:sp></p:notes>"
    var theme = Pptx.SlideTheme.defaults()
    let notes = expect Pptx.readSpeakerNotes(xml, &theme)
    Swag.require(Utf8.contains(notes, "Speak &amp; listen") and not Utf8.contains(notes, "footer"))
}

// Both presentation plugins expose the new reading mode through the live command catalog.
#test
{
    for file in ["viewer.poi-sample.pptx", "viewer.poi-sample.odp"]
    {
        var host: Testing.HeadlessHost
        let window = framedViewerWindow(&host, scopeTestDataPath(file), false)
        window.lens.open(">")
        var found: bool
        for section in window.lens.results.sections where section and not section.inline do
            for entry in section.entries where entry.title == Pptx.texts().ui_ReadNotes
            {
                Swag.require(entry.run != null and entry.glyph.isValid())
                found = true
            }

        Swag.require(found, file)
        window.lens.close()
    }
}
