#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Every multi-image codec reaches the same viewer navigation, including unequal image dimensions.
#test
{
    for name in ["imageset-animation.webp", "imageset-animation.apng", "imageset-animation.gif", "imageset-pages-raw.tiff", "imageset-icons.ico", "imageset-array.dds", "imageset-array.ktx2", "imageset-parts.exr", "imageset-layers-0.psd"]
    {
        let fileName = scopeTestDataPath(name)
        var host: Testing.HeadlessHost
        host.setup(960, 540)
        var session = openTestViewer(Picture.viewerPlugin(), &host.root, fileName)
        let view    = assume cast(*Picture.Panel, session.view)
        completeViewerBackgroundLoad(&host, &view.load)
        let movie = &view.imageView.movie
        Swag.require(view.failureReason.isEmpty() and movie.isValid() and movie.frameCount > 1)
        Swag.require(view.timeline.isLocallyVisible() and view.frameLabel.isLocallyVisible())
        Swag.require(view.playButton.isLocallyVisible() == movie.isAnimated())
        Swag.require(movie.isPaused != movie.isAnimated())
        view.imageView.setPaused(true)
        view.imageView.setFrameIndex(movie.frameCount - 1)
        view.refreshFrame()
        Swag.require(movie.frameIndex == movie.frameCount - 1 and movie.frame.isValid())
        view.imageView.setFrameIndex(0)
        Swag.require(movie.frameIndex == 0 and movie.failureReason.isEmpty())
        var information = InfoSheet.create(&host.root)
        view.information.describe(information)
        Swag.require(Utf8.contains(information.text(), Format.toString("%", movie.frameCount).toString()))
    }
}

// Over a set of independent images the summary names the item in view, its size and its place in
// a texture; an animation keeps the summary of the whole.
#test
{
    for name in ["imageset-icons.ico", "imageset-array.dds", "imageset-animation.gif"]
    {
        var host: Testing.HeadlessHost
        host.setup(960, 540)
        var session = openTestViewer(Picture.viewerPlugin(), &host.root, scopeTestDataPath(name))
        let view    = assume cast(*Picture.Panel, session.view)
        completeViewerBackgroundLoad(&host, &view.load)
        let movie = &view.imageView.movie
        view.imageView.setPaused(true)
        view.imageView.setFrameIndex(1)
        view.refreshFrame()
        let info  = unwrap movie.frameInfo()
        let shown = view.shownDetails()
        if info.kind == .Animation
        {
            Swag.require(view.itemText().isEmpty() and shown == view.details, name)
            continue
        }

        Swag.require(Utf8.startsWith(shown.toString(), view.details.toString()), name)
        Swag.require(Utf8.contains(shown.toString(), Format.toString("% × %", info.width, info.height).toString()), shown.toString())
        if info.kind == .Texture and info.layer do
            Swag.require(Utf8.contains(shown.toString(), Format.toString(Picture.texts().ui_ItemLayer, info.layer).toString()), shown.toString())
    }
}
