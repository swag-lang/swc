#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// A pane title neither overpaints its sibling nor leaves a negative content rectangle.
#test
{
    for vertical in [false, true]
    {
        var host: Testing.HeadlessHost
        host.setup(320, 220)
        let titleColor = Color.fromArgb(Argb.Red)
        let paneColor  = Color.fromArgb(Argb.Blue)
        host.theme.colors.ground = titleColor
        host.theme.colors.wnd_Bk = paneColor

        let splitter   = SplitterCtrl.create(&host.root, {0, 0, 300, 200}, vertical)
        let firstView  = Wnd.create'Wnd(splitter)
        let secondView = Wnd.create'Wnd(splitter)
        firstView.backgroundStyle  = .Window
        secondView.backgroundStyle = .Window
        let first = splitter.addPane(firstView, showTitle: true)
        splitter.addPane(secondView, 100)

        splitter.setPaneSize(0, 20)

        let label = unwrap first.label
        label.backgroundStyle = .Application
        Swag.require(first.size == 20)

        let image  = host.render()
        let sample = vertical ? image.pixelColor(20, 28) : image.pixelColor(28, 10)
        Swag.require(sample.argb == paneColor.argb)

        if vertical
        {
            Swag.require(label.position.height <= first.size)
            Swag.require(first.view.position.bottom() <= first.size)
        }
        else
        {
            Swag.require(label.position.width <= first.size)
            Swag.require(first.view.position.right() <= first.size)
        }
    }
}
