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
        Swag.require(main.editWnd.surfaceRect() == area)
        Swag.require(main.dock.surfaceRect().x == area.x + metrics.floating_Inset)
        Swag.require(main.inspector.surfaceRect().right() == area.right() - metrics.floating_Inset)
        Swag.require(main.miniBar.isLocallyVisible() and main.miniBarKind == .Text)
        Swag.require(main.sizeReading.text() == "400 × 240")
        Swag.require(main.zoomReading.text() == "100 %")

        // The mini-bar stands clear of the dock and of the inspector, and never straddles the top
        // edge of the capture.
        let bar  = main.miniBar.surfaceRect()
        let view = main.editWnd.editView
        let edge = view.localToSurface(Math.Point{0, view.getCaptureRect().y - view.scrollPos.y}).y
        Swag.require(bar.x >= main.dock.surfaceRect().right())
        Swag.require(bar.right() <= main.inspector.surfaceRect().x)
        Swag.require(bar.bottom() <= edge or bar.y >= edge)

        // The presets are those of the selection, a text, whatever the tool in hand.
        Swag.require(main.editMode == .Shape and main.quickWnd.currentStyle == &main.quickWnd.qsText)
        Swag.require(not main.recentBar.isLocallyVisible())

        var image = host.render(main)
        Pixel.Testing.assertImageGolden(&image, dark ? "surface" : "surface.paper")
    }
}
