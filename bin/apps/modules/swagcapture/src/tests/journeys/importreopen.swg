#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Import a local picture, edit the linked capture, and return from the library to the same
// document. The original picture remains a separate library item throughout the journey.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main

    let picture = Path.combine(journey.root, "source.png")
    var image = Testing.indexedImage(72, 48)
    expect image.save(picture)
    main.loadExternalImage(picture)
    journey.waitFor("import local picture", func|main|()->bool
    {
        let capture = main.editWnd.getCapture()
        return capture and capture.width == 72 and capture.height == 48 and capture.sourceKind == .ImageFile
    })

    let capture = unwrap main.editWnd.getCapture()
    var capturePath = String.from(capture.file)
    Swag.require(capture.linkedImage == picture)
    discard testAddText(capture, 5, 6, 40, 20)
    capture.changed = true
    main.saveCapture(capture)

    journey.openLibrary(2)
    var imported: *LibraryItem?
    for item in main.libWnd.view.items where item.fi.fullName == capturePath do
        imported = item
    Swag.require(imported != null)
    main.libWnd.view.openItem(imported)
    journey.waitFor("reopen imported picture", func|main, &capturePath|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == capturePath and opened.forms.count == 1
    })
    Swag.require(File.exists(picture))
}
