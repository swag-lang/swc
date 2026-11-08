#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Search a populated library by capture title, open the result, and return to all captures
// after resizing the native window. This checks the filtered list and the page transition.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main

    for title in ["North report", "South report", "West report"]
    {
        discard journey.newCapture()
        let capture = unwrap main.editWnd.getCapture()
        capture.title = title
        capture.changed = true
        main.saveCapture(capture)
    }

    journey.openLibrary(3)
    main.libWnd.setSearch("South")
    journey.waitFor("search captures", func|main|()->bool
    {
        return main.libraryMode and main.libWnd.view.items.count == 1 and
               main.libWnd.view.items[0].capture!.title == "South report"
    })

    main.libWnd.view.openItem(main.libWnd.view.items[0])
    journey.waitFor("open search result", func|main|()->bool
    {
        let capture = main.editWnd.getCapture()
        return not main.libraryMode and capture and capture.title == "South report"
    })

    journey.surface.setPosition({40, 40, 1193, 823})
    journey.waitFor("resize editor", func|main|()->bool => not main.libraryMode)
    journey.openLibrary(3)
    main.libWnd.setSearch("")
    journey.waitFor("clear search", func|main|()->bool => main.libraryMode and main.libWnd.view.items.count == 3)
}
