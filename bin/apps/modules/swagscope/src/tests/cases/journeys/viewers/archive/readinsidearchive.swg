#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Browse a ZIP folder, open an extracted document, then return to the same archive position.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let archive = journey.copyData("viewer.archive.zip", "documents.zip")
    let window = journey.window

    window.openFile(archive)
    journey.waitFor("archive root", func|window|()->bool
    {
        let explorer = window.explorer
        return window.isExploring() and explorer and not explorer.load.started and explorer.entries.count > 0
    })

    let explorer = unwrap window.explorer
    explorer.navigate(archive, "docs/")
    journey.waitFor("archive documents", func|explorer|()->bool => not explorer.load.started and
                                                                explorer.entries.count == 1 and
                                                                explorer.entries[0].name == "readme.txt")
    explorer.grid.select(0)
    explorer.activate(0)
    journey.waitFor("archive preview", func|window|()->bool
    {
        if not window.isArchivePreview() or window.currentView == null or
           window.activeChoiceIndex >= window.instances.count do
            return false
        let instance = &window.instances[window.activeChoiceIndex]
        Swag.require(instance.failureReason.isEmpty())
        return instance.isLoading == null or not instance.isLoading()
    })
    Swag.require(Utf8.endsWith(explorer.displayPath(window.currentFile), "docs/readme.txt"))

    window.sendCommandEvent(ViewerCommands.Close)
    journey.waitFor("return to archive", func|window, explorer|()->bool => window.currentView == null and
                                                                   explorer.isLocallyVisible() and
                                                                   explorer.selected == 0)
}
