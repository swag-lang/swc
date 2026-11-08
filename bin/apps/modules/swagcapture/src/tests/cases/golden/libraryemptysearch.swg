#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// A search with no matching capture keeps the library controls and empty state readable in Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    testEmptyTrash()
    g_Library.loaded = true
    main.swapLibraryMode()
    host.theme.setLight()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    discard testAddLibraryItem(main.libWnd.view, "guide.scc", 1000, 20, title: "Field guide")
    main.libWnd.refreshAutomaticFilters(force: true)
    main.libWnd.searchEdit.setText("no matching capture")
    Swag.require(main.libWnd.view.items.isEmpty())
    main.applyLayout()
    host.finishAnimations()
    var image = host.renderSettled(main)
    Pixel.Testing.assertImageGolden(&image, "library.empty-search.paper")
}
