#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Duplicate an annotated capture, rename the copy, then delete only that copy.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main
    var original = journey.newCapture()
    let capture = unwrap main.editWnd.getCapture()
    capture.title = "Original"
    journey.drawForm(ActionToolMode.Arrow, .Arrow, {5, 5}, {45, 30})
    main.saveCapture(capture)

    main.sendCommandEvent(ActionFile.DupCapture)
    journey.openLibrary(2)
    var copy: *LibraryItem?
    for item in main.libWnd.view.items where item.fi.fullName != original do
        copy = item
    Swag.require(copy != null)
    main.libWnd.view.openItem(copy)
    journey.waitFor("duplicate opened", func|main, &original|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file != original and opened.forms.count == 1
    })

    let duplicated = unwrap main.editWnd.getCapture()
    var duplicatePath = String.from(duplicated.file)
    var answered: bool
    let app = journey.app
    defer app.sigFrame.clear()
    app.sigFrame += func|app, answered = &answered|(_)
    {
        if answered[] or app.surfaces.count < 2 do
            return
        let dialog = assume cast(*EditDlg, app.surfaces.back().view())
        dialog.edit!.setText("Reviewed copy")
        answered[] = true
        Swag.require(dialog.closeWithResult(Dialog.BtnOk))
    }
    main.sendCommandEvent(ActionFile.RenameCapture)
    Swag.require(answered)
    journey.waitFor("copy renamed", func|main|()->bool => main.editWnd.getCapture()!.title == "Reviewed copy")

    journey.confirmCommand(ActionFile.DeleteCapture, Dialog.BtnYes)
    journey.waitFor("copy removed", func|&duplicatePath|()->bool => not File.exists(duplicatePath))
    Swag.require(File.exists(original))
    journey.openLibrary(1)
    Swag.require(main.libWnd.view.items[0].fi.fullName == original)
}
