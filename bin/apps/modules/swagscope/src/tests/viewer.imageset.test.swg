#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

// Every multi-image codec reaches the same viewer navigation, including unequal image dimensions.
#test
{
    for name in ["imageset-animation.webp", "imageset-animation.apng", "imageset-animation.gif", "imageset-pages-raw.tiff", "imageset-icons.ico", "imageset-array.dds", "imageset-array.ktx2", "imageset-parts.exr", "imageset-layers-0.psd"]
    {
        let fileName = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas", name)
        var host: Testing.HeadlessHost
        host.setup(960, 540)
        defer host.shutdown()
        var session = openTestViewer(imageViewerPlugin(), &host.root, fileName)
        let view    = cast(*ImageViewer) session.view!
        completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
        let movie = &view.imageView.movie
        Swag.assert(view.failureReason.isEmpty() and movie.isValid() and movie.frameCount > 1)
        Swag.assert(view.timeline.isLocallyVisible() and view.frameLabel.isLocallyVisible())
        Swag.assert(view.playButton.isLocallyVisible() == movie.isAnimated())
        Swag.assert(movie.isPaused != movie.isAnimated())
        view.imageView.setPaused(true)
        view.imageView.setFrameIndex(movie.frameCount - 1)
        view.refreshFrame()
        Swag.assert(movie.frameIndex == movie.frameCount - 1 and movie.frame.isValid())
        view.imageView.setFrameIndex(0)
        Swag.assert(movie.frameIndex == 0 and movie.failureReason.isEmpty())
        session.sidePanelButton!.setChecked(true)
        session.sidePanelButton!.sigCheckedChanged.call(session.sidePanelButton!)
        Swag.assert(Utf8.contains(view.information.text(), Format.toString("%", movie.frameCount).toString()))
        view.information.closeButton.sigPressed.call(view.information.closeButton)
        Swag.assert(not session.sidePanelHost!.isLocallyVisible())
    }
}
