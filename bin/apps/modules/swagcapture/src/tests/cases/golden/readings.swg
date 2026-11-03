#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// The editor readings are quiet menu controls in Encre and Papier.
#[Swag.TestTag("golden")]
#test
{
    for dark in [true, false]
    {
        var host: Gui.Testing.HeadlessHost
        let main = testSetupEditorSurface(&host, dark)
        defer
        {
            main.libWnd.requestClose()
            host.shutdown()
            g_Main = null
        }

        // The floating parts take no room from the work: the editor takes the whole window.
        let metrics = main.themeMetrics()
        let area    = main.editArea.surfaceRect()
        Swag.assert(main.editWnd.surfaceRect() == area)
        Swag.assert(main.dock.surfaceRect().x == area.x + metrics.floating_Inset)
        Swag.assert(main.inspector.surfaceRect().right() == area.right() - metrics.floating_Inset)
        Swag.assert(main.miniBar.isLocallyVisible() and main.miniBarKind == .Text)
        Swag.assert(main.sizeReading.text() == "400 × 240")
        Swag.assert(main.zoomReading.text() == "100 %")

        // The mini-bar stands clear of the dock and of the inspector, and never straddles the top
        // edge of the capture.
        let bar  = main.miniBar.surfaceRect()
        let view = main.editWnd.editView
        let edge = view.localToSurface(Math.Point{0, view.getCaptureRect().y - view.scrollPos.y}).y
        Swag.assert(bar.x >= main.dock.surfaceRect().right())
        Swag.assert(bar.right() <= main.inspector.surfaceRect().x)
        Swag.assert(bar.bottom() <= edge or bar.y >= edge)

        // The presets are those of the selection, a text, whatever the tool in hand.
        Swag.assert(main.editMode == .Shape and main.quickWnd.currentStyle == &main.quickWnd.qsText)
        Swag.assert(not main.recentBar.isLocallyVisible())

        var image = host.render(main)
        Pixel.Testing.assertImageGolden(&image, dark ? "surface" : "surface.paper")
    }
}
