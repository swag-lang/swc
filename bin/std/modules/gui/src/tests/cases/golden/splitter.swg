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
