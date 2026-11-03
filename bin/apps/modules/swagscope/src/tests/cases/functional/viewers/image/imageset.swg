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
        session.sidePanelButton!.setChecked(true)
        session.sidePanelButton.sigCheckedChanged.call(session.sidePanelButton)
        Swag.require(Utf8.contains(view.information.text(), Format.toString("%", movie.frameCount).toString()))
        view.information.closeButton.sigPressed.call(view.information.closeButton)
        Swag.require(not session.sidePanelHost!.isLocallyVisible())
    }
}
