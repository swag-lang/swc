#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// A search jump within the open chapter can be undone to the passage the reader left.
#test
{
    var host: Testing.HeadlessHost
    let window  = framedViewerWindow(&host, scopeTestDataPath("viewer.navigation.epub"), true)
    let panel   = assume cast(*Epub.Panel, window.instances[window.activeChoiceIndex].view)
    let session = &window.instances[window.activeChoiceIndex]
    Swag.require(panel.view != null and panel.view.findText("Paragraph 15."))
    let beforeChapter  = panel.chapter
    let beforeProgress = panel.view.readingProgress()

    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(unwrap session.collectMatches, "chapter: Paragraph 0.", &matches)
    Swag.require(matches.count == 1 and panel.revealSearchMatch(matches[0], "Paragraph 0."))
    Swag.require(panel.history.backVisits.count == 1 and panel.history.backVisits[0].position.isValid())
    Swag.require(panel.view.readingProgress() < beforeProgress)

    panel.goBack()
    Swag.require(panel.chapter == beforeChapter and panel.view.readingProgress() >= beforeProgress - 0.05)
}

// A session bookmark returns to its logical passage across chapters and joins Back/Forward history.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.navigation.epub"), true)
    let panel  = assume cast(*Epub.Panel, window.currentView)
    Swag.require(panel.view != null and panel.view.findText("Paragraph 15."))
    let expectedProgress = panel.view.readingProgress()

    var setResults: Lens.Results
    var setEntries = Viewer.LensEntries.create(&setResults, "EPUB", host.theme)
    panel.describeLens(&setEntries)
    var setBookmark: *Lens.Entry?
    for &entry in setResults.sections[0]!.entries where entry.title == Epub.texts().ui_SetBookmark do
        setBookmark = entry
    Swag.require(setBookmark != null and not setBookmark.disabled)
    setBookmark.run!()
    Swag.require(panel.hasBookmark and panel.bookmark.chapter == 0 and panel.bookmark.position.isValid())

    panel.showChapter(1)
    completeQueuedViewerFile(&host, window)
    Swag.require(panel.chapter == 1)

    var goResults: Lens.Results
    var goEntries = Viewer.LensEntries.create(&goResults, "EPUB", host.theme)
    panel.describeLens(&goEntries)
    let title = Format.toString(Epub.texts().ui_GoToBookmark, 1)
    var goBookmark: *Lens.Entry?
    for &entry in goResults.sections[0]!.entries where entry.title == title do
        goBookmark = entry
    Swag.require(goBookmark != null and not goBookmark.disabled)
    goBookmark.run!()
    completeQueuedViewerFile(&host, window)
    Swag.require(panel.chapter == 0 and
                 Math.abs(panel.view.readingProgress() - expectedProgress) < 0.05 and
                 panel.history.canGoBack())

    panel.goBack()
    completeQueuedViewerFile(&host, window)
    Swag.require(panel.chapter == 1)

    defer expect host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    Swag.require(Epub.texts().ui_SetBookmark == "Marquer ce passage")
    Swag.require(Format.toString(Epub.texts().ui_GoToBookmark, 2) == "Aller au signet du chapitre 2")
}

// Chapter, fragment and keyboard navigation share the book's back and forward history.
#test
{
    var host: Testing.HeadlessHost
    let window = openFramedViewerWindow(&host, scopeTestDataPath("viewer.navigation.epub"), false)
    let panel  = assume cast(*Epub.Panel, window.currentView)
    Swag.require(panel.history.backVisits.isEmpty() and panel.history.forwardVisits.isEmpty())

    // Blocked or missing destinations leave the history empty.
    for target in ["https://example.invalid", "../../private.html", "missing.xhtml"] do
        panel.followLink(target)
    Swag.require(panel.history.backVisits.isEmpty() and panel.history.forwardVisits.isEmpty())

    Swag.require(panel.view != null and panel.view.findText("Paragraph 15."))
    panel.followLink("two.xhtml#arrival")
    completeQueuedViewerFile(&host, window)
    Swag.require(panel.chapter == 1 and
                 panel.history.backVisits.count == 1 and
                 panel.history.forwardVisits.isEmpty())
    Swag.require(panel.history.backVisits[0].chapter == 0 and panel.history.backVisits[0].position.isValid())
    panel.goBack()
    completeQueuedViewerFile(&host, window)
    Swag.require(panel.chapter == 0 and
                 panel.history.backVisits.isEmpty() and
                 panel.history.forwardVisits.count == 1)
    Swag.require(not panel.pendingPosition.isValid())
    panel.goForward()
    completeQueuedViewerFile(&host, window)
    Swag.require(panel.chapter == 1 and
                 panel.history.backVisits.count == 1 and
                 panel.history.forwardVisits.isEmpty())

    // With text focused, Alt+arrow belongs to the book rather than the folder shortcuts.
    Swag.require(panel.view != null)
    panel.view.setFocus()
    host.keyPress(.Left, .Alt)
    completeQueuedViewerFile(&host, window)
    Swag.require(panel.chapter == 0)
    Swag.require(panel.view != null)
    panel.view.setFocus()
    host.keyPress(.Right, .Alt)
    completeQueuedViewerFile(&host, window)
    Swag.require(panel.chapter == 1)

    panel.goBack()
    completeQueuedViewerFile(&host, window)
    panel.followLink("#passage")
    Swag.require(panel.chapter == 0 and
                 panel.history.backVisits.count == 1 and
                 panel.history.forwardVisits.isEmpty())

    // A new visit drops the forward branch.
    panel.showChapter(1)
    completeQueuedViewerFile(&host, window)
    panel.goBack()
    completeQueuedViewerFile(&host, window)
    Swag.require(panel.history.forwardVisits.count == 1)
    panel.showChapter(1, "arrival")
    completeQueuedViewerFile(&host, window)
    Swag.require(panel.history.forwardVisits.isEmpty())
    panel.goForward()
    Swag.require(panel.chapter == 1)

    defer expect host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    Swag.require(Epub.texts().ui_Back == "Retour dans le livre")
}
