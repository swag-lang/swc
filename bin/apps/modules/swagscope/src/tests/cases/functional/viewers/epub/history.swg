#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

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
