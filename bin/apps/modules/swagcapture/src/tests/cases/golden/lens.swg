#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The lens over the editor, answering a query with commands of several families, in Papier.
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

    // Recent captures whose names the query matches close the results as pictures.
    for name, i in ["image-panel.scc", "image-dark.scc", "image-dune.scc"]
    {
        const Colors = [Argb.WhiteSmoke, Argb.DimGray, Argb.Peru]
        var preview = Image.create(160, 100, .BGRA8)
        preview.fill(Colors[i])
        let item = main.recentWnd.recentView.items.addNew()
        item.file    = name
        item.preview = g_App.renderer.addImage(preview)
    }

    main.lens.open("image")
    Swag.assert(main.lens.isOpen() and not main.lens.rows.isEmpty())
    Swag.assert(main.lens.rows.back().entry == Lens.PictureRow)
    host.finishAnimations()

    var image = host.render(main)
    Pixel.Testing.assertImageGolden(&image, "lens.paper")
    main.recentWnd.recentView.items.clear()
    main.lens.close()
}

// The recent captures close the lens as a strip of pictures, after every row a key can reach,
// ended by the way to the library.
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

    for name in ["first.scc", "second.scc"]
    {
        let item = main.recentWnd.recentView.items.addNew()
        item.file = name
    }

    main.lens.open("")
    let rows = main.lens.rows
    Swag.assert(rows.count > 2 and rows.back().entry == Lens.PictureRow)
    let section = rows.back().section
    Swag.assert(section.label == appStrings().lens_Recent and section.pictures.count == 2)
    Swag.assert(section.link == appStrings().lens_LibraryLink and section.linkRun != null)

    // The keys reach the strip: down into it, then along it to the link and back.
    for rows.count do
        host.keyPress(.Down)
    Swag.assert(main.lens.chosen == rows.count - 1 and main.lens.chosenPicture == 0)
    host.keyPress(.Right)
    Swag.assert(main.lens.chosenPicture == 1)
    host.finishAnimations()
    var image = host.render(main)
    Pixel.Testing.assertImageGolden(&image, "lens.recent.paper")
    host.keyPress(.Right)
    host.keyPress(.Right)
    Swag.assert(main.lens.chosenPicture == 2)
    host.keyPress(.Left)
    Swag.assert(main.lens.chosenPicture == 1)
    main.lens.close()

    // A query keeps the captures whose name it matches.
    main.lens.open("second")
    Swag.assert(main.lens.rows.back().entry == Lens.PictureRow and main.lens.rows.back().section.pictures.count == 1)
    main.lens.close()
    main.recentWnd.recentView.items.clear()
}
