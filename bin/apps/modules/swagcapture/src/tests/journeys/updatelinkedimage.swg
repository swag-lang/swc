#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Export a linked picture, update it after editing, then remove its link without losing the file.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main
    var path = journey.newCapture()
    let capture = unwrap main.editWnd.getCapture()
    journey.drawForm(ActionToolMode.Arrow, .Arrow, {5, 5}, {45, 30})

    let exports = Path.combine(journey.root, "exports")
    expect Directory.create(exports)
    var linked = Path.combine(exports, "review.png")
    main.doSaveAsImage(linked, linked: true)
    journey.waitFor("linked image exported", func|&linked|()->bool => File.exists(linked))
    Swag.require(capture.linkedImage == linked)
    let before = expect File.readAllBytes(linked)

    journey.drawForm(ActionToolMode.Shape, .Shape, {50, 10}, {80, 40})
    main.editorOptions.confirmLinkedOverwrite = false
    main.sendCommandEvent(ActionFile.UpdateLinkedImage)
    let after = expect File.readAllBytes(linked)
    Swag.require(not Slice.equals(before.toSlice(), after.toSlice()) and capture.linkedImage == linked)

    journey.confirmCommand(ActionFile.UnlinkImage, Dialog.BtnYes)
    Swag.require(capture.linkedImage.isEmpty() and File.exists(linked))
    main.saveCapture(capture)
    journey.openLibrary(1)
    main.libWnd.view.openItem(main.libWnd.view.items[0])
    journey.waitFor("unlinked capture reopened", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and
               opened.forms.count == 2 and opened.linkedImage.isEmpty()
    })
}
