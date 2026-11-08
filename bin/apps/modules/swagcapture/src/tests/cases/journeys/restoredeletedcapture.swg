#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Move a capture to the library recycle bin, restore it, and reopen its annotations.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main
    var path = journey.newCapture()
    journey.drawForm(ActionToolMode.Shape, .Shape, {8, 8}, {55, 40})
    main.saveCapture(unwrap main.editWnd.getCapture())
    journey.openLibrary(1)

    let library = main.libWnd
    library.view.setFocusItem(0)
    journey.confirmCommand(ActionFile.DeleteCapture, Dialog.BtnYes)
    journey.waitFor("capture recycled", func|library, &path|()->bool => library.view.items.isEmpty() and
                                                                  not File.exists(path))

    library.sendCommandEvent(ActionLibTrash.Toggle)
    journey.waitFor("recycle bin opened", func|library|()->bool => library.trashMode and
                                                                   library.view.items.count == 1)
    library.view.setFocusItem(0)
    library.sendCommandEvent(ActionLibTrash.Restore)
    journey.waitFor("capture restored", func|library, &path|()->bool => library.view.items.isEmpty() and
                                                                  File.exists(path))

    library.sendCommandEvent(ActionLibTrash.Toggle)
    journey.waitFor("library restored", func|library|()->bool => not library.trashMode and
                                                               library.view.items.count == 1 and
                                                               library.view.items[0].loaded and
                                                               library.view.items[0].capture != null)
    library.view.openItem(library.view.items[0])
    journey.waitFor("reopen restored capture", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and opened.forms.count == 1
    })
}
