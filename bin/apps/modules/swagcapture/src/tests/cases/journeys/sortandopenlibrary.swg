#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Sort titled captures, reverse the order, navigate the grid, and open the chosen capture.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main
    for title in ["Charlie", "Alpha", "Bravo"]
    {
        discard journey.newCapture()
        let capture = unwrap main.editWnd.getCapture()
        capture.title = title
        capture.changed = true
        main.saveCapture(capture)
    }

    journey.openLibrary(3)
    let library = main.libWnd
    library.sendCommandEvent(ActionLibSort.Name)
    Swag.require(library.view.items[0].capture!.title == "Alpha" and
                 library.view.items[2].capture!.title == "Charlie")
    library.sendCommandEvent(ActionLibSort.Invert)
    Swag.require(library.invertSort and library.view.items[0].capture!.title == "Charlie")

    library.view.setFocusItem(1)
    library.sendCommandEvent(ActionLibSel.Home)
    Swag.require(library.view.focusItem == 0)
    library.sendCommandEvent(ActionLibSel.End)
    Swag.require(library.view.focusItem == 2)
    library.sendCommandEvent(ActionLibSel.Open)
    journey.waitFor("chosen capture opened", func|main|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.title == "Alpha"
    })
}
