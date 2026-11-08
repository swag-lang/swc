#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Open neighboring files, narrow the folder pane by name and kind, then restore the full list.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let first = journey.copyData("appicon.png", "A-picture.png")
    discard journey.copyData("appicon.png", "B-picture.png")
    discard journey.copyData("comprehensive.txt", "C-notes.txt")
    let window = journey.window

    window.openFile(first)
    journey.waitForFile(first)
    window.sendCommandEvent(ViewerCommands.Files)
    journey.waitFor("folder pane", func|window|()->bool => window.filePanelHost.isLocallyVisible() and
                                                        window.folderList.lineCount() == 3)

    window.folderFilterBox.setText("B-picture")
    journey.waitFor("name filter", func|window|()->bool => window.folderList.lineCount() == 1)
    window.folderFilterBox.setText("")
    window.sendCommandEvent(ViewerCommands.SameKind)
    journey.waitFor("image kind", func|window|()->bool => window.folderList.lineCount() == 2)
    Swag.require(window.folderSameKind)

    window.sendCommandEvent(ViewerCommands.SameKind)
    journey.waitFor("all neighbors", func|window|()->bool => window.folderList.lineCount() == 3)
    window.closeFilesButton.sigPressed.call(window.closeFilesButton)
    Swag.require(not window.filePanelHost.isLocallyVisible())
}
