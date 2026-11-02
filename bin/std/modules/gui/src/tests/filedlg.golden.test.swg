#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// The empty-folder case keeps a long path out of the actions, including at fractional DPI.
#[Swag.TestTag("golden")]
#test
{
    let folder = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("swag-empty-folder-%", Guid64.random().toString()))
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder)

    var host: Testing.HeadlessHost
    host.setup(900, 700, dpiScale: 1.5)
    let dlg  = FileDlg.create(&host.surface, {mode: .SelectFolder, initialFolder: folder.toString(), showLocationsPane: false})
    var rect = dlg.surface!.position
    rect.width  = 640 * dlg.surface.dpiScale
    rect.height = 440 * dlg.surface.dpiScale
    dlg.surface.setPosition(rect)
    dlg.applyLayout()

    // Keep the machine's temporary-directory spelling out of the visual contract.
    let path = "C:/Perso/chouette/atelier-chouette/livre/figures"
    dlg.browser.pathBar.setPath(path)
    dlg.browser.choiceLabel.setText(path)
    let image = host.renderSurface(dlg.surface)
    Pixel.Testing.assertImageGolden(&image, "dialogs.folder.empty.encre.hidpi")
    dlg.surface.destroy()
    host.pump()
}
