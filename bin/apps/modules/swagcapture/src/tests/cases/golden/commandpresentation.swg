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
    var image = host.renderSettled(main)
    Pixel.Testing.assertImageGolden(&image, "commands.pixels.ink")
}
