#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Duplicate from a library preview without changing the original image or retaining its link.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    var source = journey.newCapture(37, 23)
    let main = journey.main
    let original = unwrap main.editWnd.getCapture()
    original.linkedImage = Path.combine(journey.root, "linked.png")
    original.changed = true
    main.saveCapture(original)

    journey.openLibrary(1)
    main.libWnd.view.setFocusItem(0)
    main.sendCommandEvent(ActionFile.DupCapture)
    journey.waitFor("library duplicate written", func|main|()->bool =>
                    main.duplicateJob == null and main.libWnd.view.allItems.count == 2)

    var copiedPath: String
    for item in g_Library.files where item.fullName != source do
        copiedPath = item.fullName
    Swag.require(not copiedPath.isEmpty())

    let sourceCapture = expect Capture.load(source)
    defer Memory.delete(sourceCapture)
    let copyCapture = expect Capture.load(copiedPath)
    defer Memory.delete(copyCapture)
    Swag.require(sourceCapture.backImg.isValid() and sourceCapture.width == 37 and sourceCapture.height == 23)
    Swag.require(not sourceCapture.linkedImage.isEmpty())
    Swag.require(copyCapture.backImg.isValid() and copyCapture.width == 37 and copyCapture.height == 23)
    Swag.require(copyCapture.linkedImage.isEmpty())
}
