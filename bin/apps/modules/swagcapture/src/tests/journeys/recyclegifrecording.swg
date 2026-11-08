#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Delete a recorded animation, then restore its document and frame file together from the bin.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    journey.recordAnimation(.Stop)
    let main = journey.main
    let capture = unwrap main.editWnd.getCapture()
    var path = String.from(capture.file)
    var frames = Capture.mediaPathOf(path)
    var trashed = Path.combine(Library.getTrashFolder(), Path.fileName(path) orelse "")
    var trashedFrames = Capture.mediaPathOf(trashed)

    journey.confirmCommand(ActionFile.DeleteCapture, Dialog.BtnYes)
    journey.waitFor("animation in recycle bin", func|&path, &frames, &trashed, &trashedFrames|()->bool =>
        not File.exists(path) and not File.exists(frames) and File.exists(trashed) and File.exists(trashedFrames))

    journey.openLibrary(0)
    main.libWnd.sendCommandEvent(ActionLibTrash.Toggle)
    journey.waitFor("recycle bin loaded", func|main|()->bool => main.libWnd.trashMode and
                                                               main.libWnd.view.allItems.count == 1 and
                                                               main.libWnd.view.allItems[0]!.loaded)
    main.libWnd.view.setFocusItem(0)
    main.libWnd.sendCommandEvent(ActionLibTrash.Restore)
    journey.waitFor("animation restored", func|&path, &frames|()->bool => File.exists(path) and File.exists(frames))

    main.libWnd.sendCommandEvent(ActionLibTrash.Toggle)
    journey.waitFor("restored library item", func|main|()->bool => not main.libWnd.trashMode and
                                                                 main.libWnd.view.allItems.count == 1 and
                                                                 main.libWnd.view.allItems[0]!.loaded)
    main.libWnd.view.openItem(main.libWnd.view.items[0])
    journey.waitFor("restored animation opened", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and
               opened.media == .Animation and not opened.mediaMissing
    })
}
