#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Two structural panel panes keep all four rounded sides, including the sides facing their
// draggable divider. The same grid-sized gap separates panels throughout the interface.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)

    let splitter = SplitterCtrl.create(&host.root, {20, 20, 280, 180}, vertical: true)
    splitter.backgroundStyle = .ToolBar

    let pane0 = Wnd.create'Wnd(splitter)
    pane0.backgroundStyle = .Panel
    let pane1 = Wnd.create'Wnd(splitter)
    pane1.backgroundStyle = .Panel
    splitter.addPane(pane0, 88)
    splitter.addPane(pane1)
    splitter.sendResizeEvent()

    Swag.assert(splitter.themeMetrics().splitView_BarSize == 5)
    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, "splitter.panel-panes.vertical")
}

// Panes are parented, counted, and fill the client area (panes + bars).

// Panes authored before the splitter has a rectangle keep their initial sizes for first layout.

// A size change is shared within each priority group, including when every pane preserves size.

// A pane can be hidden and shown again, updating the visible-pane count.

// setPaneSize clamps to the pane minimum size.

// Hidden panes do not absorb size transferred between visible neighbors.
