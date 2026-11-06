#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// A destructive query in the real editor lens uses Papier's critical ink, including its glyphs.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    main.lens.open("delete")

    // Deleting the capture and deleting the selection never read alike.
    var titles: Array'String
    for section in main.lens.results.sections
    {
        for entry in section!.entries
        {
            Swag.require(not titles.contains(entry.title), entry.title)
            titles.add(entry.title)
        }
    }
    Swag.require(titles.contains(appStrings().act_DeleteCapture) and titles.contains(appStrings().act_Delete))

    var image = host.renderSettled(main)
    Pixel.Testing.assertImageGolden(&image, "commands.delete.paper")
    main.lens.close()
}

// Pixel-selection actions combine icons and labels in the narrow inspector; Clear removes pixels.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap main.getCapture()
    discard testAddShape(capture, 40, 40, 160, 100, .PixSel)
    capture.selection.add(0)
    capture.selectionHasChanged()
    main.updateState()

    // A region is measured, not counted, and is not duplicated: its head offers Delete alone,
    // and the hint line does not teach Ctrl D for it.
    Swag.require(main.inspector.title == appStrings().act_PixSel)
    Swag.require(main.inspector.detail == "160 × 100")
    Swag.require(main.inspector.childById(ActionCopyPaste.Duplicate) == null)
    Swag.require(main.inspector.childById(ActionSelection.DeleteSelection) != null)
    for hint in main.hintLine.hints do
        Swag.require(hint.text != appStrings().hint_Duplicate)

    var image = host.renderSettled(main)
    Pixel.Testing.assertImageGolden(&image, "commands.pixels.ink")
}
