#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// A monitor-scale change preserves both complete timestamps, including the selected row.
#[Swag.TestTag("golden")]
#test
{
    let root = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("folder-date-golden-%", Guid64.random()))
    for name in ["chouette", "swag-lang"] do
        expect Directory.create(Path.combine(root, name), recurse: true)
    defer discard catch Directory.delete(root, recurse: true)
    var host: Testing.HeadlessHost
    host.setup(720, 200, dpiScale: 1.5)
    let browser = FileBrowserCtrl.create(&host.root, {mode: .SelectFolder, initialFolder: root, showLocationsPane: false}, {12, 12, 696, 176})
    browser.pathBar.setPath("C:/Perso")
    browser.listCtrl.selectLine(0)
    browser.choiceLabel.setText("C:/Perso/chouette")
    discard browser.listCtrl.lines[0]!.setItem(1, "3 Nov · 13:00")
    discard browser.listCtrl.lines[1]!.setItem(1, "3 Nov · 15:13")

    // Size at the old scale. Painting on the new monitor must refit without disk I/O.
    host.surface.setDpiScaleRaw(1.0)
    browser.fitDateColumn()
    host.surface.setDpiScaleRaw(1.5)
    let image = host.render()
    for line in browser.listCtrl.lines
    {
        let item = unwrap line!.items[1]
        Swag.require(item.name.chunks.count > 0)
        for &chunk in item.name.chunks
        {
            Swag.require(chunk.visible)
            for glyph in chunk.shaped.glyphs do
                Swag.require(glyph.glyphIndex != chunk.font.glyphIndex('…'))
        }
    }

    Pixel.Testing.assertImageGolden(&image, "dialogs.folder.dates.encre.hidpi")
}

// Editing a path uses one full-width field and keeps its focus ring intact at fractional DPI.
#[Swag.TestTag("golden")]
#test
{
    let folder = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("swag-empty-folder-%", Guid64.random().toString()))
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder)

    var host: Testing.HeadlessHost
    host.setup(900, 700, dpiScale: 1.5)
    let dlg = FileDlg.create(&host.surface, {mode: .SelectFolder, initialFolder: folder.toString(), showLocationsPane: false})
    dlg.surface!.setDpiScaleRaw(1.5)
    var rect = dlg.surface.position
    rect.width  = 640 * dlg.surface.dpiScale
    rect.height = 440 * dlg.surface.dpiScale
    dlg.surface.setPosition(rect)
    dlg.applyLayout()

    // Keep the machine's temporary-directory spelling out of the visual contract.
    let path = "C:/Perso/chouette/atelier-chouette/livre/figures"
    dlg.browser.pathBar.setPath(path)
    dlg.browser.pathBar.beginEdit()
    Swag.require(not dlg.browser.pathBar.isLocallyVisible())
    Swag.require(not dlg.browser.pathBar.edit.isLocallyVisible())
    dlg.browser.pathBar.breadcrumb.layout()
    let beforeHover = host.renderSurface(dlg.surface)
    dlg.browser.pathBar.breadcrumb.hotItem = dlg.browser.pathBar.breadcrumb.firstVisible
    let image = host.renderSurface(dlg.surface)
    let field = dlg.browser.pathField.surfaceRect().scaledFromOrigin(dlg.surface.dpiScale)
    let ring  = cast(u32, Math.ceil(dlg.themeMetrics().focusRing_Size * dlg.surface.dpiScale))
    for x in cast(u32, field.x) until cast(u32, field.right())
    {
        for inset in ring + 1
        {
            let top    = cast(u32, field.y) + inset
            let bottom = cast(u32, field.bottom()) - inset - 1
            Swag.require(image.pixelColor(x, top) == beforeHover.pixelColor(x, top))
            Swag.require(image.pixelColor(x, bottom) == beforeHover.pixelColor(x, bottom))
        }
    }

    Pixel.Testing.assertImageGolden(&image, "dialogs.folder.empty.encre.hidpi")
    dlg.surface.destroy()
    host.pump()
}

// A long selected folder fits beside stable translated actions, with dates at the trailing edge.
#[Swag.TestTag("golden")]
#test
{
    let root = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("folder-choice-%", Guid64.random()))
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)
    let longName = "Archives et documents pour la préparation du prochain atelier"
    for name in [longName, "Images", "Maquettes"] do
        expect Directory.create(Path.combine(root, name))
    var host: Testing.HeadlessHost
    host.setup(900, 700)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    let dlg = FileDlg.create(&host.surface, {mode: .SelectFolder, initialFolder: root, showLocationsPane: false})
    dlg.browser.pathBar.setPath("C:/Perso/Projets")
    dlg.browser.listCtrl.selectLine(0)
    dlg.browser.choiceLabel.setText(Format.toString("C:/Perso/Projets/%", longName))
    pinBrowserDates(dlg.browser)
    dlg.applyLayout()
    let image = host.renderSurface(unwrap dlg.surface)
    Pixel.Testing.assertImageGolden(&image, "dialogs.folder.selection.fr.encre")
    dlg.surface.destroy()
    host.pump()
}
