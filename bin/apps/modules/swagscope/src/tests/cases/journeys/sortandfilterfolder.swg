#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Sort and filter a folder, open a picture, then recover that presentation after another folder.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let folder = Path.combine(journey.root, "Folder")
    expect Directory.create(folder)
    var image = Testing.indexedImage(24, 20)
    expect image.save(Path.combine(folder, "A-picture.png"))
    expect image.save(Path.combine(folder, "B-picture.png"))
    expect File.writeAllText(Path.combine(folder, "C-notes.txt"), "folder notes\n")
    let window = journey.window

    window.openExplorer(folder)
    journey.waitFor("mixed folder", func|window|()->bool => window.isExploring() and
                                                            not window.explorer!.load.started and
                                                            window.explorer!.entries.count == 3)
    let explorer = unwrap window.explorer
    window.sendCommandEvent(ViewerCommands.SortName)
    journey.waitFor("name sort", func|explorer|()->bool => not explorer.load.started and
                                                           explorer.sortColumn == 0 and
                                                           explorer.shown.count == 3)
    window.sendCommandEvent(ViewerCommands.SortDescending)
    journey.waitFor("reverse name sort", func|explorer|()->bool => not explorer.load.started and
                                                                   explorer.descending and
                                                                   explorer.entries[explorer.shown[0]].name == "C-notes.txt")

    window.sendCommandEvent(ViewerCommands.FilterImages)
    journey.waitFor("pictures only", func|explorer|()->bool => explorer.kindFilter == .Images and
                                                               explorer.shown.count == 2)
    explorer.grid.select(0)
    window.sendCommandEvent(ViewerCommands.OpenChosen)
    journey.waitFor("picture opened", func|window|()->bool => window.currentView != null and
                                                              window.choices[window.activeChoiceIndex].key == "image")
    window.sendCommandEvent(ViewerCommands.Close)
    journey.waitFor("folder restored", func|window, explorer|()->bool => window.isExploring() and
                                                                         explorer.isLocallyVisible() and
                                                                         explorer.kindFilter == .Images)

    explorer.forceBoard(true, .Grid)
    explorer.setMode(.Large)
    explorer.setArtworkSource(.Local)
    let other = Path.combine(journey.root, "Other")
    expect Directory.create(other)
    window.openExplorer(other)
    journey.waitFor("other folder", func|explorer|()->bool => not explorer.load.started and explorer.entries.isEmpty())
    window.sendCommandEvent(ViewerCommands.FilterAll)
    window.sendCommandEvent(ViewerCommands.SortAscending)
    journey.waitFor("other sort", func|explorer|()->bool => not explorer.load.started and not explorer.descending)
    explorer.setMode(.Names)
    window.openExplorer(folder)
    journey.waitFor("remembered folder", func|explorer|()->bool => not explorer.load.started and
                                                                   explorer.shown.count == 2 and
                                                                   explorer.kindFilter == .Images and
                                                                   explorer.mode == .Large and
                                                                   explorer.descending and
                                                                   explorer.forced and
                                                                   explorer.forcedBoard == .Grid and
                                                                   explorer.artworkSource == .Local)
}
